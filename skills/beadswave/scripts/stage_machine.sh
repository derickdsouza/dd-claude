#!/usr/bin/env bash
# stage_machine.sh — porcelain + orchestrator over fsm.sh.
# Sourced by stage scripts (bd-ship, merge-wait, pipeline-driver) and tests.
#
# Dependencies (overridable for tests):
#   BW_GH, BW_BD       — CLI shims (default: gh, bd)
#   BW_NOW             — emits ISO-8601 timestamp
#   BW_STATE_DIR       — manifest + intent log directory (default: .git/beadswave-state)

_SM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$_SM_DIR/fsm.sh"

: "${BW_GH:=gh}"
: "${BW_BD:=bd}"
: "${BW_NOW:=date -u +%Y-%m-%dT%H:%M:%SZ}"
: "${BW_STATE_DIR:=.git/beadswave-state}"

_sm_manifest_stage() {
  local bead="$1" path="$BW_STATE_DIR/${bead}.json"
  [ -f "$path" ] || return 0
  python3 -c "import json,sys; print(json.load(open('$path')).get('stage',''))" 2>/dev/null || true
}

_sm_label_stage() {
  local bead="$1"
  "$BW_BD" show "$bead" --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for l in d.get('labels', []):
    name = l if isinstance(l, str) else l.get('name', '')
    if name.startswith('stage:'):
        print(name[len('stage:'):])
        break
" 2>/dev/null || true
}

bead_current() {
  local bead="$1"
  local m l
  m="$(_sm_manifest_stage "$bead")"
  if [ -n "$m" ]; then
    printf '%s\n' "$m"
    return 0
  fi
  l="$(_sm_label_stage "$bead")"
  if [ -n "$l" ]; then
    printf '%s\n' "$l"
    return 0
  fi
  printf 'committed\n'
}

_sm_now() { eval "$BW_NOW"; }

_sm_write_manifest() {
  local bead="$1" stage="$2" ts path
  ts="$(_sm_now)"
  mkdir -p "$BW_STATE_DIR"
  path="$BW_STATE_DIR/${bead}.json"
  # Merge into any pre-existing manifest so we don't clobber fields owned
  # by other writers (bd-ship: branch/pr, merge-wait: base_sha/merge_commit).
  if [ -f "$path" ]; then
    BW_BEAD="$bead" BW_STAGE="$stage" BW_TS="$ts" BW_PATH="$path" python3 -c '
import json, os, sys
p = os.environ["BW_PATH"]
try:
    d = json.load(open(p))
    if not isinstance(d, dict): d = {}
except Exception:
    d = {}
d["bead"]       = os.environ["BW_BEAD"]
d["stage"]      = os.environ["BW_STAGE"]
d["updated_at"] = os.environ["BW_TS"]
print(json.dumps(d))
' > "$path.tmp" 2>/dev/null && mv "$path.tmp" "$path"
  else
    printf '{"bead":"%s","stage":"%s","updated_at":"%s"}\n' \
      "$bead" "$stage" "$ts" > "$path"
  fi
}

_sm_set_label() {
  local bead="$1" from="$2" to="$3"
  [ -n "$from" ] && "$BW_BD" update "$bead" --remove-label "stage:$from" >/dev/null 2>&1 || true
  "$BW_BD" update "$bead" --add-label "stage:$to" >/dev/null 2>&1 || true
}

_sm_intent_log() {
  local bead="$1"; shift
  mkdir -p "$BW_STATE_DIR"
  printf '%s\t%s\n' "$(_sm_now)" "$*" >> "$BW_STATE_DIR/${bead}.intent"
}

bead_transition() {
  local bead="$1" event="$2"
  local from next intents payload
  from="$(bead_current "$bead")"

  payload="$(fsm_next "$from" "$event")" || return 3
  next="${payload%%$'\t'*}"
  intents="${payload##*$'\t'}"

  _sm_intent_log "$bead" "BEGIN $from $event $next $intents"

  local i
  IFS=',' read -ra _intents <<< "$intents"
  for i in "${_intents[@]}"; do
    case "$i" in
      WRITE_MANIFEST) _sm_write_manifest "$bead" "$next" ;;
      SET_LABEL)      _sm_set_label "$bead" "$from" "$next" ;;
      UPDATE_BEAD)    : ;;
      LOG_HISTORY)    : ;;
    esac
  done

  _sm_intent_log "$bead" "DONE $next"
  return 0
}

bead_intent_replay() {
  local bead="$1"
  local log="$BW_STATE_DIR/${bead}.intent"
  [ -f "$log" ] || return 0

  local last_begin="" last_done=""
  last_begin="$(grep -F 'BEGIN ' "$log" | tail -n 1 || true)"
  last_done="$(grep -F 'DONE ' "$log" | tail -n 1 || true)"
  [ -n "$last_begin" ] || return 0
  [ -z "$last_done" ] || return 0  # DONE present → no pending transition

  local payload from event next intents
  payload="${last_begin#*BEGIN }"
  from="${payload%% *}";   payload="${payload#* }"
  event="${payload%% *}";  payload="${payload#* }"
  next="${payload%% *}";   intents="${payload#* }"

  local i
  IFS=',' read -ra _intents <<< "$intents"
  for i in "${_intents[@]}"; do
    case "$i" in
      WRITE_MANIFEST) _sm_write_manifest "$bead" "$next" ;;
      SET_LABEL)      _sm_set_label "$bead" "$from" "$next" ;;
      UPDATE_BEAD)    : ;;
      LOG_HISTORY)    : ;;
    esac
  done
  _sm_intent_log "$bead" "DONE $next (replayed)"
}

bead_enter()    { bead_transition "$1" BRANCH; }
bead_divert()   { bead_transition "$1" HOLD; }
bead_rollback() { bead_transition "$1" MERGE_FAIL; }

bead_advance() {
  local bead="$1" role="${BEADSWAVE_STAGE_ROLE:-ship}" cur event
  cur="$(bead_current "$bead")"
  case "$role/$cur" in
    ship/committed|ship/branched) event=SHIP ;;
    ship/shipping)                event=MERGE_OK ;;
    merge/merging)                event=LAND ;;
    merge/review-hold)            event=LAND ;;
    *) echo "bead_advance: no $role transition from $cur" >&2; return 4 ;;
  esac
  bead_transition "$bead" "$event"
}
