#!/bin/bash

# Claude Code Status Line — MFC-themed with smart git & path display
# Performance: batch jq extraction, minimal git calls, no unnecessary forks
# Available JSON: session_id, transcript_path, cwd, model, workspace, version,
#   output_style, cost.{total_cost_usd,total_duration_ms,total_api_duration_ms,
#   total_lines_added,total_lines_removed},
#   context_window.{used_percentage,remaining_percentage,total_input_tokens,
#   total_output_tokens,context_window_size}, exceeds_200k_tokens

# --- Read stdin once, batch-extract all needed fields ---
input=$(cat)
IFS=$'\t' read -r model_name current_dir output_style tok_in tok_out api_dur_ms total_dur_ms session_id < <(
  echo "$input" | jq -r '[.model.display_name // .model.id, .workspace.current_dir // .cwd, .output_style.name // "default", (.context_window.total_input_tokens // 0), (.context_window.total_output_tokens // 0), (.cost.total_api_duration_ms // 0), (.cost.total_duration_ms // 0), (.session_id // "")] | @tsv'
)

# --- MFC + Nordic hybrid palette ---
RST='\033[0m'
C_DIR='\033[48;2;212;168;67m\033[38;2;30;20;0m'              # MFC accent bg, dark fg
C_BRANCH='\033[48;2;19;35;65m\033[38;2;135;206;250m'         # Deep navy bg, sky blue fg
C_AHEAD='\033[48;2;45;90;39m\033[38;2;220;255;220m'          # MFC primary bg
C_BEHIND='\033[48;2;191;97;106m\033[38;2;255;255;255m'       # Red bg
C_STASH='\033[48;2;180;142;173m\033[38;2;255;255;255m'       # Nordic purple bg
C_CONFLICT='\033[48;2;220;38;38m\033[38;2;255;255;255m'      # Bright red bg
C_DIRTY='\033[48;2;208;135;112m\033[38;2;0;0;0m'             # Orange bg
C_STAGED='\033[48;2;129;161;193m\033[38;2;0;0;0m'            # Light blue bg
C_UNTRACKED='\033[48;2;172;46;149m\033[38;2;255;255;255m'    # Purple bg
C_VENV='\033[48;2;136;192;208m\033[38;2;0;0;0m'              # Cyan bg
C_MODEL='\033[48;2;76;145;65m\033[38;2;255;255;255m'         # MFC primary-light bg
C_PROVIDER='\033[48;2;63;81;181m\033[38;2;224;224;255m'      # Indigo bg (Bedrock/Vertex)
C_SPEED='\033[48;2;0;150;136m\033[38;2;255;255;255m'         # Teal bg (token speed)
C_TIMER='\033[48;2;121;85;72m\033[38;2;255;235;210m'         # Warm brown bg (elapsed)
C_EFFORT='\033[48;2;76;145;65m\033[38;2;220;255;220m'        # MFC green bg
C_TASK='\033[48;2;180;142;173m\033[38;2;0;0;0m'              # Nordic purple bg
C_USAGE='\033[48;2;46;52;64m\033[38;2;211;213;214m'          # Dark bg, light fg (usage)
C_CTX_G='\033[48;2;163;190;140m\033[38;2;0;0;0m'             # Green bg (low ctx)
C_CTX_Y='\033[48;2;235;203;139m\033[38;2;0;0;0m'             # Yellow bg (med ctx)
C_CTX_R='\033[48;2;191;97;106m\033[38;2;255;255;255m'        # Red bg (high ctx)
C_DISK='\033[48;2;46;52;64m\033[38;2;136;192;208m'           # Nordic polar bg, cyan fg
C_COST='\033[48;2;94;129;172m\033[38;2;216;222;233m'         # Nordic blue bg, light fg
C_TIME='\033[48;2;212;168;67m\033[38;2;30;20;0m'             # MFC accent bg

# --- Segment builder ---
seg() { printf '%b %s %b' "$1" "$2" "$RST"; }

# --- Directory: folder name / repo name / branch ---
dir_name=$(basename "$current_dir")
if git -C "$current_dir" rev-parse --git-dir >/dev/null 2>&1; then
    git_root=$(git -C "$current_dir" rev-parse --show-toplevel 2>/dev/null)
    repo_name=$(basename "$git_root")
    branch=$(git -C "$current_dir" --no-optional-locks branch --show-current 2>/dev/null || echo "detached")
    dir_display="${dir_name}  ${repo_name}  ${branch}"
else
    dir_display="$dir_name"
    branch=""
fi
statusline=$(seg "$C_DIR" "$dir_display")

# --- Git info (single porcelain call for counts, plus ahead/behind) ---
if git -C "$current_dir" rev-parse --git-dir >/dev/null 2>&1; then
    git_section=""
    upstream=$(git -C "$current_dir" --no-optional-locks rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
    if [[ -n "$upstream" ]]; then
        ab_raw=$(git -C "$current_dir" --no-optional-locks rev-list --left-right --count "$upstream...HEAD" 2>/dev/null)
        if [[ -n "$ab_raw" ]]; then
            behind=${ab_raw%%$'\t'*}
            ahead=${ab_raw##*$'\t'}
            [[ "$ahead" -gt 0 ]] && git_section+="$(seg "$C_AHEAD" "+${ahead}")"
            [[ "$behind" -gt 0 ]] && git_section+="$(seg "$C_BEHIND" "-${behind}")"
        fi
    fi

    porcelain=$(git -C "$current_dir" --no-optional-locks status --porcelain=v1 2>/dev/null)
    working_changed=0 staging_changed=0 untracked=0 conflicts=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        x="${line:0:1}" y="${line:1:1}"
        if [[ "$x" =~ [ADU] && "$y" =~ [ADU] ]]; then
            ((conflicts++))
        elif [[ "$y" == "?" ]]; then
            ((untracked++))
        else
            [[ "$x" != " " && "$x" != "?" ]] && ((staging_changed++))
            [[ "$y" != " " && "$y" != "?" ]] && ((working_changed++))
        fi
    done <<< "$porcelain"

    stash_count=$(git -C "$current_dir" --no-optional-locks stash list 2>/dev/null | wc -l | tr -d ' ')
    [[ "$stash_count" -gt 0 ]] && git_section+="$(seg "$C_STASH" "*${stash_count}")"
    [[ "$conflicts" -gt 0 ]] && git_section+="$(seg "$C_CONFLICT" "!${conflicts}")"
    [[ "$working_changed" -gt 0 ]] && git_section+="$(seg "$C_DIRTY" "~${working_changed}")"
    [[ "$staging_changed" -gt 0 ]] && git_section+="$(seg "$C_STAGED" "+${staging_changed}")"
    [[ "$untracked" -gt 0 ]] && git_section+="$(seg "$C_UNTRACKED" "?${untracked}")"
    statusline+="${git_section}"
fi

# --- Python virtual environment ---
if [[ -n "$VIRTUAL_ENV" ]]; then
    statusline+="$(seg "$C_VENV" "$(basename "$VIRTUAL_ENV")")"
fi

# --- Model (abbreviated) ---
model_abbr=$(echo "$model_name" | sed 's/Claude //; s/Sonnet/Snt/; s/Opus/Ops/; s/Haiku/Hku/')
statusline+="$(seg "$C_MODEL" "$model_abbr")"

# --- Provider label (Bedrock / Vertex / default: hidden) ---
if [[ -n "$CLAUDE_CODE_USE_BEDROCK" ]]; then
    statusline+="$(seg "$C_PROVIDER" "AWS")"
elif [[ -n "$CLAUDE_CODE_USE_VERTEX" ]]; then
    statusline+="$(seg "$C_PROVIDER" "GCP")"
fi

# --- Token speed (tokens/sec based on API duration) ---
if [[ "$tok_in" -gt 0 && "$api_dur_ms" -gt 0 ]] 2>/dev/null; then
    total_tok=$(( tok_in + tok_out ))
    speed=$(( total_tok * 1000 / api_dur_ms ))
    if [[ $speed -ge 1000 ]]; then
        speed_display="$(( speed / 1000 )).$(( (speed % 1000) / 100 ))k"
    else
        speed_display="$speed"
    fi
    statusline+="$(seg "$C_SPEED" "${speed_display}t/s")"
fi

# --- Block timer (session elapsed + 5h block progress) ---
if [[ "$total_dur_ms" -gt 0 ]] 2>/dev/null; then
    total_sec=$(( total_dur_ms / 1000 ))
    hours=$(( total_sec / 3600 ))
    mins=$(( (total_sec % 3600) / 60 ))
    secs=$(( total_sec % 60 ))
    block_pct=$(( total_sec * 100 / 18000 ))
    [[ $block_pct -gt 100 ]] && block_pct=100
    if [[ $hours -gt 0 ]]; then
        time_display="${hours}h${mins}m"
    else
        time_display="${mins}m${secs}s"
    fi
    statusline+="$(seg "$C_TIMER" "${time_display} ${block_pct}%/5h")"
fi

# --- Effort level (from settings.json) ---
effort=$(jq -r '.effortLevel // empty' "$HOME/.claude/settings.json" 2>/dev/null)
if [[ -n "$effort" && "$effort" != "null" ]]; then
    case "$effort" in
        low*) effort_icon="L" ;;
        med*) effort_icon="M" ;;
        high*) effort_icon="H" ;;
        *) effort_icon="${effort:0:1}" ;;
    esac
    statusline+="$(seg "$C_EFFORT" "ef:${effort_icon}")"
fi

# --- Todo progress (completion bar with done/total) ---
if [[ -n "$session_id" && -d "$HOME/.claude/todos" ]]; then
    todo_file=$(ls -t "$HOME/.claude/todos" 2>/dev/null | grep "^${session_id}" | grep '\-agent\-' | grep '\.json$' | head -1)
    if [[ -n "$todo_file" ]]; then
        read -r todo_total todo_done < <(
            jq -r '[length, [.[].status | select(. == "completed")] | length] | @tsv' "$HOME/.claude/todos/$todo_file" 2>/dev/null
        )
        if [[ -n "$todo_total" && "$todo_total" -gt 0 ]] 2>/dev/null; then
            filled=$(( todo_done * 5 / todo_total ))
            empty=$(( 5 - filled ))
            bar=""
            for ((i=0; i<filled; i++)); do bar+="#"; done
            for ((i=0; i<empty; i++)); do bar+="-"; done
            statusline+="$(seg "$C_TASK" "${bar} ${todo_done}/${todo_total}")"
        fi
    fi
fi

# --- Context window usage (color-coded bar + used|remaining %) ---
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
if [[ "$ctx_pct" =~ ^[0-9]+$ && "$ctx_pct" -gt 0 ]]; then
    ctx_rem=$(echo "$input" | jq -r '.context_window.remaining_percentage // (100 - '"/$ctx_pct"')' | cut -d. -f1)
    if [[ $ctx_pct -lt 50 ]]; then ctx_color="$C_CTX_G"
    elif [[ $ctx_pct -lt 80 ]]; then ctx_color="$C_CTX_Y"
    else ctx_color="$C_CTX_R"; fi
    filled=$(( ctx_pct / 20 ))
    empty=$(( 5 - filled ))
    bar=""
    for ((i=0; i<filled; i++)); do bar+="#"; done
    for ((i=0; i<empty; i++)); do bar+="-"; done
    statusline+="$(seg "$ctx_color" "${bar} ${ctx_pct}%|${ctx_rem}%")"
fi

# --- Disk space remaining ---
if command -v df >/dev/null 2>&1; then
    disk_avail=$(df -h "$current_dir" 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -n "$disk_avail" ]]; then
        statusline+="$(seg "$C_DISK" "${disk_avail} free")"
    fi
fi

# --- Session usage (abbreviated token in/out) ---
abbrev_n() {
    local n=$1
    if [[ $n -ge 1000000 ]]; then
        printf "%d.%dM" $(( n / 1000000 )) $(( (n % 1000000) / 100000 ))
    elif [[ $n -ge 1000 ]]; then
        printf "%d.%dk" $(( n / 1000 )) $(( (n % 1000) / 100 ))
    else
        echo "$n"
    fi
}
if [[ "$tok_in" -gt 0 ]] 2>/dev/null; then
    usage_display="$(abbrev_n $tok_in)i/$(abbrev_n $tok_out)o"
    statusline+="$(seg "$C_USAGE" "$usage_display")"
fi

# --- Session cost ---
session_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty' 2>/dev/null)
if [[ -n "$session_cost" && "$session_cost" != "null" ]]; then
    dollars=${session_cost%%.*}
    cents=${session_cost#*.}
    cents="${cents:0:2}"
    [[ ${#cents} -eq 1 ]] && cents="${cents}0"
    [[ -z "$cents" ]] && cents="00"
    statusline+="$(seg "$C_COST" "\$${dollars}.${cents}")"
fi

# --- Time ---
# Context quality score (from token-optimizer)
qFile="$HOME/.claude/token-optimizer/quality-cache.json"
if [[ -f "$qFile" ]]; then
    qScore=$(jq -r '.score // empty' "$qFile" 2>/dev/null)
    if [[ -n "$qScore" && "$qScore" != "null" ]]; then
        if [[ "$qScore" -lt 50 ]]; then qColor="$C_CTX_R"
        elif [[ "$qScore" -lt 70 ]]; then qColor="$C_CTX_Y"
        else qColor="$C_CTX_G"; fi
        statusline+="$(seg "$qColor" "Q:${qScore}")"
    fi
fi

statusline+="$(seg "$C_TIME" "$(date '+%H:%M')")"

# --- Output ---
printf '%b' "$statusline"
