#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/testlib.sh"

SM="$SKILL_ROOT/scripts/stage_machine.sh"

# ── test harness ─────────────────────────────────────────────────────
# Each test function sources stage_machine.sh inside a subshell with fake
# BW_GH / BW_BD / BW_NOW / BW_STATE_DIR pointing at a temp sandbox.

_sm_sandbox() {
  # Usage: eval "$(_sm_sandbox)" — exports TMP, LABELS, BDLOG, and trap.
  cat <<'EOF'
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state" "$TMP/bin"
LABELS="$TMP/labels"    # one file per bead, contents = stage name
BDLOG="$TMP/bd.log"     # append-only log of bd calls
: > "$BDLOG"
mkdir -p "$LABELS"

cat > "$TMP/bin/fake-gh" <<'SH'
#!/usr/bin/env bash
# Not used yet — labels live via fake-bd below.
exit 0
SH
chmod +x "$TMP/bin/fake-gh"

cat > "$TMP/bin/fake-bd" <<SH
#!/usr/bin/env bash
# Minimal bd stub: supports "show <id> --json" (returns labels) and
# "update <id> --add-label X / --remove-label X" (mutates labels dir).
echo "bd \$*" >> "$BDLOG"
sub="\$1"; shift
id="\$1"; shift || true
case "\$sub" in
  show)
    if [ -f "$LABELS/\$id" ]; then
      stage="\$(cat "$LABELS/\$id")"
      printf '{"id":"%s","labels":[{"name":"stage:%s"}]}\n' "\$id" "\$stage"
    else
      printf '{"id":"%s","labels":[]}\n' "\$id"
    fi
    ;;
  update)
    while [ \$# -gt 0 ]; do
      case "\$1" in
        --add-label)
          lbl="\$2"; shift 2
          case "\$lbl" in stage:*) printf '%s' "\${lbl#stage:}" > "$LABELS/\$id" ;; esac
          ;;
        --remove-label)
          lbl="\$2"; shift 2
          if [ -f "$LABELS/\$id" ] && [ "stage:\$(cat "$LABELS/\$id")" = "\$lbl" ]; then
            rm -f "$LABELS/\$id"
          fi
          ;;
        *) shift ;;
      esac
    done
    ;;
esac
SH
chmod +x "$TMP/bin/fake-bd"

export BW_GH="$TMP/bin/fake-gh"
export BW_BD="$TMP/bin/fake-bd"
export BW_NOW='echo 2026-01-01T00:00:00Z'
export BW_STATE_DIR="$TMP/state"
EOF
}

# ── tests ────────────────────────────────────────────────────────────

test_bead_current_defaults_to_committed() (
  set -euo pipefail
  eval "$(_sm_sandbox)"
  # shellcheck disable=SC1090
  . "$SM"

  assert_eq "committed" "$(bead_current some-bead)" \
    "bead with no label and no manifest defaults to committed"
)

test_bead_current_reads_label() (
  set -euo pipefail
  eval "$(_sm_sandbox)"
  # shellcheck disable=SC1090
  . "$SM"

  printf 'shipping' > "$LABELS/bd-7"
  assert_eq "shipping" "$(bead_current bd-7)" "label-backed stage read"
)

test_bead_current_prefers_manifest_over_label_on_drift() (
  set -euo pipefail
  eval "$(_sm_sandbox)"
  # shellcheck disable=SC1090
  . "$SM"

  printf 'shipping' > "$LABELS/bd-9"
  printf '{"stage":"merging"}' > "$BW_STATE_DIR/bd-9.json"
  assert_eq "merging" "$(bead_current bd-9)" "manifest wins when label drifts"
)

test_bead_transition_committed_to_branched() (
  set -euo pipefail
  eval "$(_sm_sandbox)"
  # shellcheck disable=SC1090
  . "$SM"

  bead_transition bd-42 BRANCH

  assert_eq "branched" "$(bead_current bd-42)" "manifest should record next stage"
  assert_file_contains "$BW_STATE_DIR/bd-42.json" '"stage":"branched"'
  assert_eq "branched" "$(cat "$LABELS/bd-42")" "label should be set to next stage"
)

test_bead_transition_illegal_event_returns_3() (
  set -euo pipefail
  eval "$(_sm_sandbox)"
  # shellcheck disable=SC1090
  . "$SM"

  printf 'landed' > "$LABELS/bd-5"
  local rc
  set +e
  bead_transition bd-5 SHIP >/dev/null 2>&1
  rc=$?
  set -e
  assert_eq "3" "$rc" "illegal transition should exit 3"
  assert_eq "landed" "$(bead_current bd-5)" "stage must not change on illegal event"
)

test_bead_transition_logs_begin_and_done() (
  set -euo pipefail
  eval "$(_sm_sandbox)"
  # shellcheck disable=SC1090
  . "$SM"

  bead_transition bd-99 BRANCH

  local log="$BW_STATE_DIR/bd-99.intent"
  [ -f "$log" ] || fail "intent log should exist at $log"
  assert_file_contains "$log" 'BEGIN'
  assert_file_contains "$log" 'DONE'
  assert_order "$log" 'BEGIN' 'DONE'
)

test_bead_enter_from_committed_branches() (
  set -euo pipefail
  eval "$(_sm_sandbox)"
  # shellcheck disable=SC1090
  . "$SM"

  bead_enter bd-1
  assert_eq "branched" "$(bead_current bd-1)" "bead_enter should land in branched"
)

test_bead_advance_ship_role_committed_to_shipping() (
  set -euo pipefail
  eval "$(_sm_sandbox)"
  # shellcheck disable=SC1090
  . "$SM"

  BEADSWAVE_STAGE_ROLE=ship bead_advance bd-2
  assert_eq "shipping" "$(bead_current bd-2)" "ship role should SHIP committed beads"
)

test_bead_advance_ship_role_shipping_to_merging() (
  set -euo pipefail
  eval "$(_sm_sandbox)"
  # shellcheck disable=SC1090
  . "$SM"

  printf 'shipping' > "$LABELS/bd-3"
  BEADSWAVE_STAGE_ROLE=ship bead_advance bd-3
  assert_eq "merging" "$(bead_current bd-3)" "ship role at shipping should MERGE_OK"
)

test_bead_advance_merge_role_merging_to_landed() (
  set -euo pipefail
  eval "$(_sm_sandbox)"
  # shellcheck disable=SC1090
  . "$SM"

  printf 'merging' > "$LABELS/bd-4"
  BEADSWAVE_STAGE_ROLE=merge bead_advance bd-4
  assert_eq "landed" "$(bead_current bd-4)" "merge role at merging should LAND"
)

test_bead_divert_from_shipping_goes_to_review_hold() (
  set -euo pipefail
  eval "$(_sm_sandbox)"
  # shellcheck disable=SC1090
  . "$SM"

  printf 'shipping' > "$LABELS/bd-6"
  bead_divert bd-6
  assert_eq "review-hold" "$(bead_current bd-6)"
)

test_bead_rollback_from_shipping_goes_to_branched() (
  set -euo pipefail
  eval "$(_sm_sandbox)"
  # shellcheck disable=SC1090
  . "$SM"

  printf 'shipping' > "$LABELS/bd-8"
  bead_rollback bd-8
  assert_eq "branched" "$(bead_current bd-8)" "MERGE_FAIL should roll back to branched"
)

run_test "bead_current defaults to committed"           test_bead_current_defaults_to_committed
run_test "bead_current reads label from bd shim"        test_bead_current_reads_label
run_test "bead_current prefers manifest on label drift" test_bead_current_prefers_manifest_over_label_on_drift
run_test "bead_transition committed→branched commits"   test_bead_transition_committed_to_branched
run_test "bead_transition illegal event returns 3"      test_bead_transition_illegal_event_returns_3
run_test "bead_transition logs BEGIN and DONE markers"  test_bead_transition_logs_begin_and_done
run_test "bead_enter from committed → branched"         test_bead_enter_from_committed_branches
run_test "bead_advance ship role: committed → shipping" test_bead_advance_ship_role_committed_to_shipping
run_test "bead_advance ship role: shipping → merging"   test_bead_advance_ship_role_shipping_to_merging
run_test "bead_advance merge role: merging → landed"    test_bead_advance_merge_role_merging_to_landed
run_test "bead_divert from shipping → review-hold"      test_bead_divert_from_shipping_goes_to_review_hold
test_bead_intent_replay_no_pending_is_noop() (
  set -euo pipefail
  eval "$(_sm_sandbox)"
  # shellcheck disable=SC1090
  . "$SM"

  bead_transition bd-10 BRANCH  # writes BEGIN + DONE
  # No pending intent → replay should succeed silently.
  bead_intent_replay bd-10
  assert_eq "branched" "$(bead_current bd-10)" "replay must not regress stage"
)

test_bead_intent_replay_resumes_after_crash_between_manifest_and_label() (
  set -euo pipefail
  eval "$(_sm_sandbox)"
  # shellcheck disable=SC1090
  . "$SM"

  # Simulate a crash AFTER manifest was written but BEFORE label was set:
  # manifest = branched, label = committed, intent-log has BEGIN but no DONE.
  mkdir -p "$BW_STATE_DIR"
  printf '{"bead":"bd-11","stage":"branched"}' > "$BW_STATE_DIR/bd-11.json"
  printf 'committed' > "$LABELS/bd-11"
  printf '2026-01-01T00:00:00Z\tBEGIN committed BRANCH branched SET_LABEL,WRITE_MANIFEST,LOG_HISTORY\n' \
    > "$BW_STATE_DIR/bd-11.intent"

  bead_intent_replay bd-11

  assert_eq "branched" "$(cat "$LABELS/bd-11")" "replay should reconcile label to manifest stage"
  assert_file_contains "$BW_STATE_DIR/bd-11.intent" 'DONE'
)

run_test "bead_rollback from shipping → branched"       test_bead_rollback_from_shipping_goes_to_branched
run_test "bead_intent_replay no-op when already DONE"   test_bead_intent_replay_no_pending_is_noop
run_test "bead_intent_replay resumes crashed transition" test_bead_intent_replay_resumes_after_crash_between_manifest_and_label
