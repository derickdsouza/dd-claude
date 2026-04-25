#!/usr/bin/env bash
# fsm.sh — pure finite state machine for beadswave stages.
# No I/O. Sourced by stage_machine.sh and tests.
#
# Stages:  committed branched shipping merging landed review-hold
# Events:  BRANCH SHIP MERGE_OK MERGE_FAIL LAND HOLD RESUME
# Intents: SET_LABEL WRITE_MANIFEST UPDATE_BEAD LOG_HISTORY

fsm_legal_events() {
  local stage="$1" event legal=()
  for event in BRANCH HOLD LAND MERGE_FAIL MERGE_OK RESUME SHIP; do
    if fsm_next "$stage" "$event" >/dev/null 2>&1; then
      legal+=("$event")
    fi
  done
  printf '%s' "${legal[*]}"
}

fsm_next() {
  local stage="$1" event="$2"
  local base='SET_LABEL,WRITE_MANIFEST,LOG_HISTORY'
  local with_bead='SET_LABEL,WRITE_MANIFEST,UPDATE_BEAD,LOG_HISTORY'
  case "$stage/$event" in
    committed/BRANCH)       printf 'branched\t%s\n'    "$base" ;;
    committed/SHIP)         printf 'shipping\t%s\n'    "$base" ;;
    branched/SHIP)          printf 'shipping\t%s\n'    "$base" ;;
    shipping/MERGE_OK)      printf 'merging\t%s\n'     "$with_bead" ;;
    shipping/HOLD)          printf 'review-hold\t%s\n' "$base" ;;
    shipping/MERGE_FAIL)    printf 'branched\t%s\n'    "$base" ;;
    merging/MERGE_FAIL)     printf 'branched\t%s\n'    "$base" ;;
    merging/LAND)           printf 'landed\t%s\n'      "$with_bead" ;;
    merging/HOLD)           printf 'review-hold\t%s\n' "$base" ;;
    review-hold/RESUME)     printf 'merging\t%s\n'     "$base" ;;
    review-hold/LAND)       printf 'landed\t%s\n'      "$with_bead" ;;
    *) return 3 ;;
  esac
}
