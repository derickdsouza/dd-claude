#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/testlib.sh"

FSM="$SKILL_ROOT/scripts/fsm.sh"

test_committed_branch_transition_is_legal() (
  set -euo pipefail
  # shellcheck disable=SC1090
  . "$FSM"

  local out rc
  set +e
  out="$(fsm_next committed BRANCH)"
  rc=$?
  set -e

  assert_eq "0" "$rc" "committed + BRANCH should be legal"
  assert_eq "branched	SET_LABEL,WRITE_MANIFEST,LOG_HISTORY" "$out" \
    "committed + BRANCH should emit branched with base intents"
)

test_landed_ship_is_illegal() (
  set -euo pipefail
  # shellcheck disable=SC1090
  . "$FSM"

  local out rc
  set +e
  out="$(fsm_next landed SHIP)"
  rc=$?
  set -e

  assert_eq "3" "$rc" "landed is terminal; SHIP must exit 3"
  assert_eq "" "$out" "illegal transition must emit nothing on stdout"
)

test_shipping_merge_ok_carries_update_bead() (
  set -euo pipefail
  # shellcheck disable=SC1090
  . "$FSM"

  local out rc
  set +e
  out="$(fsm_next shipping MERGE_OK)"
  rc=$?
  set -e

  assert_eq "0" "$rc" "shipping + MERGE_OK is legal"
  assert_eq "merging	SET_LABEL,WRITE_MANIFEST,UPDATE_BEAD,LOG_HISTORY" "$out" \
    "shipping→merging must include UPDATE_BEAD (PR metadata)"
)

test_full_legality_truth_table() (
  set -euo pipefail
  # shellcheck disable=SC1090
  . "$FSM"

  local base='SET_LABEL,WRITE_MANIFEST,LOG_HISTORY'
  local with_bead='SET_LABEL,WRITE_MANIFEST,UPDATE_BEAD,LOG_HISTORY'

  # Every legal transition: from|event|expected_next|expected_intents
  local legal=(
    "committed|BRANCH|branched|$base"
    "committed|SHIP|shipping|$base"
    "branched|SHIP|shipping|$base"
    "shipping|MERGE_OK|merging|$with_bead"
    "shipping|HOLD|review-hold|$base"
    "shipping|MERGE_FAIL|branched|$base"
    "merging|LAND|landed|$with_bead"
    "merging|HOLD|review-hold|$base"
    "review-hold|RESUME|merging|$base"
    "review-hold|LAND|landed|$with_bead"
  )

  local row from event want_next want_intents out rc
  for row in "${legal[@]}"; do
    IFS='|' read -r from event want_next want_intents <<< "$row"
    set +e
    out="$(fsm_next "$from" "$event")"
    rc=$?
    set -e
    assert_eq "0"                              "$rc"  "$from+$event should be legal"
    assert_eq "${want_next}	${want_intents}"   "$out" "$from+$event payload"
  done

  # Terminal stage — nothing legal.
  local illegal=(
    "landed|BRANCH" "landed|SHIP" "landed|MERGE_OK" "landed|MERGE_FAIL"
    "landed|LAND"   "landed|HOLD" "landed|RESUME"
    "committed|MERGE_OK" "committed|LAND" "committed|HOLD" "committed|RESUME" "committed|MERGE_FAIL"
    "branched|BRANCH"    "branched|MERGE_OK" "branched|LAND" "branched|HOLD" "branched|RESUME" "branched|MERGE_FAIL"
    "shipping|BRANCH"    "shipping|SHIP"     "shipping|LAND" "shipping|RESUME"
    "merging|BRANCH"     "merging|SHIP"      "merging|MERGE_OK" "merging|MERGE_FAIL" "merging|RESUME"
    "review-hold|BRANCH" "review-hold|SHIP"  "review-hold|MERGE_OK" "review-hold|MERGE_FAIL" "review-hold|HOLD"
  )

  for row in "${illegal[@]}"; do
    IFS='|' read -r from event <<< "$row"
    set +e
    out="$(fsm_next "$from" "$event")"
    rc=$?
    set -e
    assert_eq "3"  "$rc"  "$from+$event should be illegal"
    assert_eq ""   "$out" "$from+$event must emit nothing"
  done
)

test_legal_events_enumerates_all_legal_pairs() (
  set -euo pipefail
  # shellcheck disable=SC1090
  . "$FSM"

  # For each stage, fsm_legal_events should list exactly those events for which
  # fsm_next returns 0 — and nothing more. Order is lexicographic.
  local cases=(
    "committed|BRANCH SHIP"
    "branched|SHIP"
    "shipping|HOLD MERGE_FAIL MERGE_OK"
    "merging|HOLD LAND"
    "review-hold|LAND RESUME"
    "landed|"
  )
  local row stage want got
  for row in "${cases[@]}"; do
    IFS='|' read -r stage want <<< "$row"
    got="$(fsm_legal_events "$stage")"
    assert_eq "$want" "$got" "fsm_legal_events $stage"
  done
)

run_test "committed + BRANCH → branched"               test_committed_branch_transition_is_legal
run_test "landed + SHIP is illegal"                    test_landed_ship_is_illegal
run_test "shipping + MERGE_OK → merging (UPDATE_BEAD)" test_shipping_merge_ok_carries_update_bead
run_test "full legality truth table"                   test_full_legality_truth_table
run_test "fsm_legal_events enumerates transitions"     test_legal_events_enumerates_all_legal_pairs
