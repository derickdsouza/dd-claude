#!/bin/bash

# Read Claude Code context from stdin
input=$(cat)

# Extract information from Claude Code context
model_name=$(echo "$input" | jq -r '.model.display_name // .model.id')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
output_style=$(echo "$input" | jq -r '.output_style.name // "default"')

# Get user and hostname
user=$(whoami)
hostname=$(hostname -s)

# Get current time (24-hour format)
current_time=$(date "+%H:%M")

# Get current directory (folder name only for compact display)
dir_name=$(basename "$current_dir")

# Nordic color palette matching Oh My Posh dev-slick theme
# Each section has unique background + contrasting text color
USER_HOST='\033[48;2;128;0;128m\033[38;2;255;255;255m'       # Purple bg, white fg
DIRECTORY='\033[48;2;163;190;140m\033[38;2;0;0;0m'           # #A3BE8C bg, black fg (Green)
GIT_BRANCH='\033[48;2;19;35;65m\033[38;2;135;206;250m'       # #132341 bg, sky blue fg
GIT_MODIFIED='\033[48;2;208;135;112m\033[38;2;0;0;0m'        # #D08770 bg, black fg (Orange)
GIT_STAGED='\033[48;2;129;161;193m\033[38;2;0;0;0m'          # #81A1C1 bg, black fg (Light Blue)
GIT_UNTRACKED='\033[48;2;172;46;149m\033[38;2;255;255;255m'  # #ac2e95 bg, white fg (Purple)
VENV='\033[48;2;136;192;208m\033[38;2;0;0;0m'                # #88C0D0 bg, black fg (Cyan)
PROJECT='\033[48;2;191;97;106m\033[38;2;255;255;255m'        # #BF616A bg, white fg (Red)
MODEL='\033[48;2;0;255;0m\033[38;2;0;0;0m'                   # Bright green bg, black fg
TIME='\033[48;2;255;255;0m\033[38;2;0;0;0m'                  # Yellow bg, black fg

RESET='\033[0m'

# Build status line components

# User@Host
statusline="${USER_HOST} ${user}@${hostname} ${RESET}"

# Directory
statusline="${statusline}${DIRECTORY} 📁 ${dir_name} ${RESET}"

# Git information (if in a git repo)
if git -C "$current_dir" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$current_dir" --no-optional-locks branch --show-current 2>/dev/null || echo "detached")

    # Get working tree changes
    working_changed=$(git -C "$current_dir" --no-optional-locks diff --name-only 2>/dev/null | wc -l | tr -d ' ')
    # Get staged changes
    staging_changed=$(git -C "$current_dir" --no-optional-locks diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    # Get untracked files
    untracked=$(git -C "$current_dir" --no-optional-locks ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

    # Build git section with unique background colors
    git_section="${GIT_BRANCH}  ${branch} ${RESET}"

    # Add modified files if non-zero (Orange background)
    if [[ $working_changed -gt 0 ]]; then
        git_section="${git_section}${GIT_MODIFIED} ~${working_changed} ${RESET}"
    fi

    # Add staged files if non-zero (Light Blue background)
    if [[ $staging_changed -gt 0 ]]; then
        git_section="${git_section}${GIT_STAGED} +${staging_changed} ${RESET}"
    fi

    # Add untracked files if non-zero (Purple background)
    if [[ $untracked -gt 0 ]]; then
        git_section="${git_section}${GIT_UNTRACKED} ?${untracked} ${RESET}"
    fi

    # Add git section
    statusline="${statusline}${git_section}"
fi

# Python virtual environment (if active)
if [[ -n "$VIRTUAL_ENV" ]]; then
    venv_name=$(basename "$VIRTUAL_ENV")
    statusline="${statusline}${VENV} 🐍 ${venv_name} ${RESET}"
fi

# Claude Model (abbreviated for compact display)
model_abbr=$(echo "$model_name" | sed 's/Claude //; s/Sonnet/Snt/; s/Opus/Ops/; s/Haiku/Hku/')
statusline="${statusline}${MODEL} 🤖 ${model_abbr} ${RESET}"

# Current Time
statusline="${statusline}${TIME} ⏱️  ${current_time} ${RESET}"

# Output the final status line
printf "%b" "$statusline"