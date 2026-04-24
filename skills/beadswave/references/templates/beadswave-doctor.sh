#!/usr/bin/env bash
# beadswave-doctor.sh — reconcile bead manifests, bead tracker state, branches,
# and PR state to surface or repair deterministic workflow drift.
#
# Usage:
#   beadswave-doctor.sh [--json] [--fix] [<bead-id> ...]
#
# Safe fixes:
#   --fix currently repairs the "merged PR but bead still open" case by
#   restoring the bead external-ref if needed and delegating to merge-wait.sh.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BEADSWAVE_RUNTIME="${BEADSWAVE_SKILL_DIR:-$HOME/.claude/skills/beadswave}/scripts/runtime.sh"

if [[ -f "$BEADSWAVE_RUNTIME" ]]; then
  # shellcheck disable=SC1090
  . "$BEADSWAVE_RUNTIME"
else
  echo "beadswave runtime missing at $BEADSWAVE_RUNTIME" >&2
  exit 1
fi

JSON_OUTPUT=false
FIX_MODE=false
TARGET_BEADS=()

usage() {
  cat <<'EOF'
Usage: beadswave-doctor.sh [--json] [--fix] [<bead-id> ...]

Options:
  --json     Emit machine-readable findings
  --fix      Apply safe automatic repairs where possible
  -h, --help Show this help

Checks:
  - missing or invalid manifests
  - missing beads, missing branches, missing PRs
  - bead/manifest/PR stage mismatches
  - merged PRs whose beads are still open
  - stale branches whose recorded base now overlaps origin/main changes
EOF
}

emit_finding() {
  local bead_id="${1:-}"
  local kind="${2:-}"
  local severity="${3:-error}"
  local detail="${4:-}"
  local fixable="${5:-false}"
  local meta_json="${6:-}"
  local finding=""

  if [[ -z "$meta_json" ]]; then
    meta_json='{}'
  fi

  finding="$(jq -nc \
    --arg bead_id "$bead_id" \
    --arg kind "$kind" \
    --arg severity "$severity" \
    --arg detail "$detail" \
    --argjson fixable "$fixable" \
    --argjson meta "$meta_json" \
    '{bead_id:$bead_id, kind:$kind, severity:$severity, detail:$detail, fixable:$fixable, meta:$meta}')"

  printf '%s\n' "$finding" >>"$FINDINGS_FILE"

  if [[ "$JSON_OUTPUT" != "true" ]]; then
    printf '[%s] %s %s: %s\n' "$severity" "${bead_id:-unknown}" "$kind" "$detail"
  fi
}

expected_stage_label() {
  case "${1:-}" in
    shipping) printf 'stage:shipping\n' ;;
    merging) printf 'stage:merging\n' ;;
    review-hold) printf 'stage:review-hold\n' ;;
    landed) printf 'stage:landed\n' ;;
    *) return 1 ;;
  esac
}

branch_exists_anywhere() {
  local branch="${1:-}"
  [[ -n "$branch" && "$branch" != "null" ]] || return 1
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    return 0
  fi
  if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    return 0
  fi
  return 1
}

record_target_manifest() {
  local bead_id="${1:-}"
  local expanded="$bead_id"
  local manifest_path=""

  if expanded_bead="$(beadswave_expand_bead_id "$bead_id" "$REPO_ROOT" 2>/dev/null || true)"; then
    if [[ -n "$expanded_bead" ]]; then
      expanded="$expanded_bead"
    fi
  fi

  manifest_path="$(beadswave_manifest_path "$expanded" "$REPO_ROOT" 2>/dev/null || true)"
  if [[ -n "$manifest_path" && -f "$manifest_path" ]]; then
    printf '%s\n' "$manifest_path"
    return 0
  fi

  emit_finding "$expanded" "missing-manifest" "error" "No manifest exists for this bead." false '{}'
  return 1
}

safe_fix_merged_open_bead() {
  local bead_id="${1:-}"
  local pr_number="${2:-}"
  local current_external_ref="${3:-}"
  local merge_wait_script=""

  [[ "$FIX_MODE" == "true" ]] || return 1
  [[ -n "$bead_id" && -n "$pr_number" ]] || return 1

  if printf '%s\n' "$FIXED_BEADS" | grep -Fxq "$bead_id"; then
    return 1
  fi

  merge_wait_script="$(beadswave_resolve_merge_wait "$REPO_ROOT" 2>/dev/null || true)"
  [[ -n "$merge_wait_script" ]] || return 1

  if [[ "$current_external_ref" != "gh-$pr_number" ]]; then
    bd update "$bead_id" --external-ref "gh-$pr_number" >/dev/null 2>&1 || return 1
  fi

  if MERGE_WAIT_TIMEOUT=15 MERGE_WAIT_POLL=1 "$merge_wait_script" "$bead_id" --json >/dev/null 2>&1; then
    FIXED_BEADS="${FIXED_BEADS}${bead_id}"$'\n'
    return 0
  fi

  return 1
}

freshness_overlap_meta() {
  local base_sha="${1:-}"
  local branch="${2:-}"
  local branch_ahead="${3:-0}"
  local main_ahead="${4:-0}"
  local overlap_file="${5:-}"

  python3 - "$base_sha" "$branch" "$branch_ahead" "$main_ahead" "$overlap_file" <<'PY'
import json
import sys

paths = []
if sys.argv[5]:
    with open(sys.argv[5], encoding="utf-8") as handle:
        paths = [line.strip() for line in handle if line.strip()]

print(json.dumps({
    "base_sha": sys.argv[1],
    "branch": sys.argv[2],
    "branch_ahead": int(sys.argv[3]),
    "main_ahead": int(sys.argv[4]),
    "overlap_paths": paths,
}))
PY
}

inspect_manifest() {
  local manifest_path="${1:-}"
  local manifest_json=""
  local bead_id=""
  local stage=""
  local branch=""
  local base_sha=""
  local pr_number=""
  local external_ref=""
  local hold_state=""
  local bead_json=""
  local bead_status=""
  local bead_external_ref=""
  local bead_stage_label=""
  local expected_label=""
  local pr_json=""
  local pr_state=""
  local pr_head_branch=""
  local merged_at=""
  local auto_fixed=false

  manifest_json="$(cat "$manifest_path")"
  bead_id="$(printf '%s' "$manifest_json" | jq -r '.bead_id // empty' 2>/dev/null || true)"
  if [[ -z "$bead_id" ]]; then
    emit_finding "" "invalid-manifest" "error" "Manifest at $manifest_path has no bead_id." false "{\"manifest_path\":$(jq -Rn --arg v "$manifest_path" '$v')}"
    return 0
  fi

  stage="$(printf '%s' "$manifest_json" | jq -r '.stage // empty' 2>/dev/null || true)"
  branch="$(printf '%s' "$manifest_json" | jq -r '.branch // empty' 2>/dev/null || true)"
  base_sha="$(printf '%s' "$manifest_json" | jq -r '.base_sha // empty' 2>/dev/null || true)"
  pr_number="$(printf '%s' "$manifest_json" | jq -r '.pr_number // empty' 2>/dev/null || true)"
  external_ref="$(printf '%s' "$manifest_json" | jq -r '.external_ref // empty' 2>/dev/null || true)"
  hold_state="$(printf '%s' "$manifest_json" | jq -r '.hold_state // empty' 2>/dev/null || true)"

  bead_json="$(bd show "$bead_id" --json 2>/dev/null || true)"
  if [[ -z "$bead_json" ]]; then
    emit_finding "$bead_id" "missing-bead" "error" "Manifest exists but bd show could not find the bead." false "{\"manifest_path\":$(jq -Rn --arg v "$manifest_path" '$v')}"
  else
    bead_status="$(printf '%s' "$bead_json" | jq -r 'if type=="array" then .[0].status else .status end // empty' 2>/dev/null || true)"
    bead_external_ref="$(printf '%s' "$bead_json" | jq -r 'if type=="array" then .[0].external_refs[0].ref else .external_refs[0].ref end // empty' 2>/dev/null || true)"
    bead_stage_label="$(printf '%s' "$bead_json" | jq -r '
      (if type=="array" then .[0] else . end).labels // []
      | map(select(startswith("stage:")))
      | .[0] // empty
    ' 2>/dev/null || true)"

    if [[ -n "$pr_number" && "$bead_external_ref" != "gh-$pr_number" ]]; then
      emit_finding "$bead_id" "pr-ref-mismatch" "error" "Bead external-ref does not match the manifest PR number." false "$(jq -nc --arg bead_external_ref "$bead_external_ref" --arg expected_ref "gh-$pr_number" '{bead_external_ref:$bead_external_ref, expected_ref:$expected_ref}')"
    fi

    if expected_label="$(expected_stage_label "$stage" 2>/dev/null || true)"; then
      if [[ -n "$bead_stage_label" && "$bead_stage_label" != "$expected_label" ]]; then
        emit_finding "$bead_id" "stage-mismatch" "warning" "Bead stage label does not match the manifest stage." false "$(jq -nc --arg bead_stage_label "$bead_stage_label" --arg expected_label "$expected_label" --arg manifest_stage "$stage" '{bead_stage_label:$bead_stage_label, expected_label:$expected_label, manifest_stage:$manifest_stage}')"
      fi
    fi

    if [[ "$bead_status" == "closed" && "$stage" != "landed" ]]; then
      emit_finding "$bead_id" "closed-bead-not-landed" "warning" "Bead is closed but the manifest is not marked landed." false "$(jq -nc --arg bead_status "$bead_status" --arg manifest_stage "$stage" '{bead_status:$bead_status, manifest_stage:$manifest_stage}')"
    fi
  fi

  if [[ -n "$branch" && "$stage" != "landed" ]] && ! branch_exists_anywhere "$branch"; then
    emit_finding "$bead_id" "missing-branch" "error" "Manifest branch no longer exists locally or on origin." false "$(jq -nc --arg branch "$branch" '{branch:$branch}')"
  fi

  if [[ -n "$branch" && -n "$base_sha" && "$base_sha" != "null" && "$stage" != "landed" ]] && branch_exists_anywhere "$branch"; then
    if git merge-base --is-ancestor "$base_sha" "origin/main" >/dev/null 2>&1 && git merge-base --is-ancestor "$base_sha" "$branch" >/dev/null 2>&1; then
      local main_ahead="0"
      local branch_ahead="0"
      local branch_paths=""
      local main_paths=""
      local overlap_file=""
      local overlap_paths=""

      main_ahead="$(beadswave_count_commits "$REPO_ROOT" "$base_sha..origin/main" 2>/dev/null || echo "0")"
      if [[ "${main_ahead:-0}" -gt 0 ]]; then
        branch_ahead="$(beadswave_count_commits "$REPO_ROOT" "$base_sha..$branch" 2>/dev/null || echo "0")"
        branch_paths="$(beadswave_tmpfile beadswave-doctor-branch)" || true
        main_paths="$(beadswave_tmpfile beadswave-doctor-main)" || true
        overlap_file="$(beadswave_tmpfile beadswave-doctor-overlap)" || true

        if [[ -n "$branch_paths" && -n "$main_paths" && -n "$overlap_file" ]]; then
          beadswave_diff_name_only "$REPO_ROOT" "$base_sha..$branch" >"$branch_paths"
          beadswave_diff_name_only "$REPO_ROOT" "$base_sha..origin/main" >"$main_paths"
          beadswave_intersect_paths "$branch_paths" "$main_paths" >"$overlap_file" || true
          overlap_paths="$(cat "$overlap_file" 2>/dev/null || true)"
          if [[ -n "$overlap_paths" ]]; then
            emit_finding "$bead_id" "branch-stale-overlap" "error" "Branch base is stale and overlaps current origin/main changes." false "$(freshness_overlap_meta "$base_sha" "$branch" "$branch_ahead" "$main_ahead" "$overlap_file")"
          fi
        fi
        rm -f "$branch_paths" "$main_paths" "$overlap_file"
      fi
    fi
  fi

  if [[ -n "$pr_number" && "$pr_number" != "null" ]]; then
    pr_json="$(gh pr view "$pr_number" --json number,state,mergedAt,headRefName,headRefOid 2>/dev/null || true)"
    if [[ -z "$pr_json" ]]; then
      emit_finding "$bead_id" "missing-pr" "error" "Manifest references a PR that gh pr view could not load." false "$(jq -nc --arg pr_number "$pr_number" '{pr_number:$pr_number}')"
    else
      pr_state="$(printf '%s' "$pr_json" | jq -r '.state // empty' 2>/dev/null || true)"
      pr_head_branch="$(printf '%s' "$pr_json" | jq -r '.headRefName // empty' 2>/dev/null || true)"
      merged_at="$(printf '%s' "$pr_json" | jq -r '.mergedAt // empty' 2>/dev/null || true)"

      if [[ -n "$branch" && -n "$pr_head_branch" && "$pr_head_branch" != "$branch" && "$pr_state" == "OPEN" ]]; then
        emit_finding "$bead_id" "pr-branch-mismatch" "warning" "Open PR head branch does not match the manifest branch." false "$(jq -nc --arg branch "$branch" --arg pr_head_branch "$pr_head_branch" '{branch:$branch, pr_head_branch:$pr_head_branch}')"
      fi

      if [[ "$pr_state" == "MERGED" || ( -n "$merged_at" && "$merged_at" != "null" ) ]]; then
        if [[ "$bead_status" != "closed" ]]; then
          if safe_fix_merged_open_bead "$bead_id" "$pr_number" "$bead_external_ref"; then
            auto_fixed=true
          fi
          emit_finding "$bead_id" "merged-pr-open-bead" "error" "PR is merged but the bead is still open." true "$(jq -nc --arg pr_number "$pr_number" --argjson auto_fixed "$auto_fixed" --arg hold_state "$hold_state" '{pr_number:$pr_number, auto_fixed:$auto_fixed, hold_state:$hold_state}')"
        fi
      elif [[ "$pr_state" == "CLOSED" && "$stage" != "landed" ]]; then
        emit_finding "$bead_id" "closed-pr-not-landed" "warning" "PR was closed without merge while the manifest is not landed." false "$(jq -nc --arg pr_number "$pr_number" '{pr_number:$pr_number}')"
      fi
    fi
  elif [[ -n "$external_ref" && "$external_ref" != "null" ]]; then
    emit_finding "$bead_id" "manifest-missing-pr-number" "warning" "Manifest has an external_ref but no pr_number." false "$(jq -nc --arg external_ref "$external_ref" '{external_ref:$external_ref}')"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --fix)
      FIX_MODE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      TARGET_BEADS+=("$1")
      shift
      ;;
  esac
done

FINDINGS_FILE="$(beadswave_tmpfile beadswave-doctor-findings)"
trap 'rm -f "$FINDINGS_FILE"' EXIT
FIXED_BEADS=""

STATE_DIR="$(beadswave_state_dir "$REPO_ROOT")"
MANIFEST_PATHS=()

if [[ "${#TARGET_BEADS[@]}" -gt 0 ]]; then
  for bead in "${TARGET_BEADS[@]}"; do
    if manifest_path="$(record_target_manifest "$bead" 2>/dev/null || true)"; then
      [[ -n "$manifest_path" ]] && MANIFEST_PATHS+=("$manifest_path")
    fi
  done
else
  shopt -s nullglob
  for manifest_path in "$STATE_DIR"/*.json; do
    MANIFEST_PATHS+=("$manifest_path")
  done
  shopt -u nullglob
fi

for manifest_path in "${MANIFEST_PATHS[@]}"; do
  inspect_manifest "$manifest_path"
done

# ── Orphan-stage-label scan ───────────────────────────────────────────────
# Beads that carry an in-flight stage:* label but have NO manifest on disk
# are invisible to pipeline-driver's manifest-fallback — there is nothing
# to fall back to. Only meaningful on a full sweep (no explicit targets).
if [[ "${#TARGET_BEADS[@]}" -eq 0 ]]; then
  ORPHAN_JSON="$(bd list --status=in_progress --json -n 0 2>/dev/null || echo '[]')"
  printf '%s' "$ORPHAN_JSON" | BEADSWAVE_STATE_DIR="$STATE_DIR" python3 -c '
import json, os, sys
state_dir = os.environ["BEADSWAVE_STATE_DIR"]
try:
    beads = json.load(sys.stdin)
except Exception:
    beads = []
INFLIGHT = {"stage:shipping", "stage:merging", "stage:review-hold"}
for b in beads:
    bid = b.get("id") or ""
    if not bid:
        continue
    labels = [l if isinstance(l, str) else l.get("name", "") for l in (b.get("labels") or [])]
    stage_labels = [l for l in labels if l in INFLIGHT]
    if not stage_labels:
        continue
    manifest = os.path.join(state_dir, f"{bid}.json")
    if os.path.isfile(manifest):
        continue
    print(json.dumps({
        "bead_id": bid,
        "kind": "orphan-stage-label",
        "severity": "warning",
        "detail": f"Bead carries {stage_labels[0]} but has no manifest on disk.",
        "fixable": False,
        "meta": {"stage_label": stage_labels[0]},
    }))
' >> "$FINDINGS_FILE"
  # Mirror orphan findings to stdout when not in --json mode so the human
  # summary includes them.
  if [[ "$JSON_OUTPUT" != "true" ]]; then
    grep -F '"orphan-stage-label"' "$FINDINGS_FILE" 2>/dev/null \
      | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: d = json.loads(line)
    except: continue
    print(f\"[{d['severity']}] {d['bead_id']} {d['kind']}: {d['detail']}\")
" || true
  fi
fi

if [[ "$JSON_OUTPUT" == "true" ]]; then
  python3 - "$FINDINGS_FILE" <<'PY'
import json
import sys

items = []
with open(sys.argv[1], encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if not line:
            continue
        items.append(json.loads(line))

print(json.dumps(items, indent=2, sort_keys=True))
PY
else
  count="$(grep -c '.' "$FINDINGS_FILE" 2>/dev/null || true)"
  if [[ "${count:-0}" -eq 0 ]]; then
    echo "No beadswave doctor findings."
  else
    echo "Findings: $count"
  fi
fi
