# Snapshot file
# Unset all aliases to avoid conflicts with functions
unalias -a 2>/dev/null || true
# Functions
__arguments () {
	# undefined
	builtin autoload -XUz
}
__bun_dynamic_comp () {
	local comp="" 
	for arg in scripts
	do
		local line
		while read -r line
		do
			local name="$line" 
			local desc="$line" 
			name="${name%$'\t'*}" 
			desc="${desc/*$'\t'/}" 
			echo
		done <<< "$arg"
	done
	return $comp
}
activate () {
	_lazy_conda_setup && conda activate "$@"
}
add-zsh-hook () {
	emulate -L zsh
	local -a hooktypes
	hooktypes=(chpwd precmd preexec periodic zshaddhistory zshexit zsh_directory_name) 
	local usage="Usage: add-zsh-hook hook function\nValid hooks are:\n  $hooktypes" 
	local opt
	local -a autoopts
	integer del list help
	while getopts "dDhLUzk" opt
	do
		case $opt in
			(d) del=1  ;;
			(D) del=2  ;;
			(h) help=1  ;;
			(L) list=1  ;;
			([Uzk]) autoopts+=(-$opt)  ;;
			(*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))
	if (( list ))
	then
		typeset -mp "(${1:-${(@j:|:)hooktypes}})_functions"
		return $?
	elif (( help || $# != 2 || ${hooktypes[(I)$1]} == 0 ))
	then
		print -u$(( 2 - help )) $usage
		return $(( 1 - help ))
	fi
	local hook="${1}_functions" 
	local fn="$2" 
	if (( del ))
	then
		if (( ${(P)+hook} ))
		then
			if (( del == 2 ))
			then
				set -A $hook ${(P)hook:#${~fn}}
			else
				set -A $hook ${(P)hook:#$fn}
			fi
			if (( ! ${(P)#hook} ))
			then
				unset $hook
			fi
		fi
	else
		if (( ${(P)+hook} ))
		then
			if (( ${${(P)hook}[(I)$fn]} == 0 ))
			then
				typeset -ga $hook
				set -A $hook ${(P)hook} $fn
			fi
		else
			typeset -ga $hook
			set -A $hook $fn
		fi
		autoload $autoopts -- $fn
	fi
}
ai-commit () {
	echo "🤖 Remember to follow the Git Commit Protocol:"
	echo "   1. Pre-commit hooks (Step 0)"
	echo "   2. Categorization table (Step 1.5)"
	echo "   3. Commit plan review (Step 2.5)"
	echo "   4. Use --no-verify for commits"
	echo "   5. Pre-push audit (Step 5.5)"
	echo ""
	echo "💡 Tell your AI: 'Follow ~/.ai-instructions/git_commit_protocol.md for this commit'"
}
ai-init () {
	local project_path="${1:-.}" 
	echo "🤖 Setting up AI instructions for: $project_path"
	"$AI_INSTRUCTIONS_DIR/setup/setup-project.sh" "$project_path"
}
ai-status () {
	if [[ -f ".ai-instructions.md" && -f ".claude/git_commit_protocol.md" ]]
	then
		echo "✅ AI instructions are set up in this project"
	else
		echo "❌ AI instructions not found. Run 'ai-setup' to install."
	fi
}
array_contains () {
	local val="$1" 
	shift
	for elem in "$@"
	do
		if [[ "$elem" == "$val" ]]
		then
			return 0
		fi
	done
	return 1
}
autospec () {
	local target="${1:-.}" 
	cp /Users/derickdsouza/Projects/development/coding-agent-harness/templates/app_spec_template.xml "$target/app_spec.txt"
	echo "✅ Copied app_spec.txt template to: $target/"
	echo "📝 Edit the file and replace all {{PLACEHOLDER}} values"
	echo "📖 See template comments for detailed instructions"
}
claude () {
	command claude --dangerously-skip-permissions "$@"
}
command_not_found_handler () {
	if [ -d "$HOME/.config/fabric/patterns/$1" ]
	then
		local cmd="$1" 
		shift
		_fabric_pattern "$cmd" "$@"
	else
		_original_command_not_found_handler "$@"
	fi
}
compaudit () {
	# undefined
	builtin autoload -XUz /usr/share/zsh/5.9/functions
}
compdef () {
	local opt autol type func delete eval new i ret=0 cmd svc 
	local -a match mbegin mend
	emulate -L zsh
	setopt extendedglob
	if (( ! $# ))
	then
		print -u2 "$0: I need arguments"
		return 1
	fi
	while getopts "anpPkKde" opt
	do
		case "$opt" in
			(a) autol=yes  ;;
			(n) new=yes  ;;
			([pPkK]) if [[ -n "$type" ]]
				then
					print -u2 "$0: type already set to $type"
					return 1
				fi
				if [[ "$opt" = p ]]
				then
					type=pattern 
				elif [[ "$opt" = P ]]
				then
					type=postpattern 
				elif [[ "$opt" = K ]]
				then
					type=widgetkey 
				else
					type=key 
				fi ;;
			(d) delete=yes  ;;
			(e) eval=yes  ;;
		esac
	done
	shift OPTIND-1
	if (( ! $# ))
	then
		print -u2 "$0: I need arguments"
		return 1
	fi
	if [[ -z "$delete" ]]
	then
		if [[ -z "$eval" ]] && [[ "$1" = *\=* ]]
		then
			while (( $# ))
			do
				if [[ "$1" = *\=* ]]
				then
					cmd="${1%%\=*}" 
					svc="${1#*\=}" 
					func="$_comps[${_services[(r)$svc]:-$svc}]" 
					[[ -n ${_services[$svc]} ]] && svc=${_services[$svc]} 
					[[ -z "$func" ]] && func="${${_patcomps[(K)$svc][1]}:-${_postpatcomps[(K)$svc][1]}}" 
					if [[ -n "$func" ]]
					then
						_comps[$cmd]="$func" 
						_services[$cmd]="$svc" 
					else
						print -u2 "$0: unknown command or service: $svc"
						ret=1 
					fi
				else
					print -u2 "$0: invalid argument: $1"
					ret=1 
				fi
				shift
			done
			return ret
		fi
		func="$1" 
		[[ -n "$autol" ]] && autoload -rUz "$func"
		shift
		case "$type" in
			(widgetkey) while [[ -n $1 ]]
				do
					if [[ $# -lt 3 ]]
					then
						print -u2 "$0: compdef -K requires <widget> <comp-widget> <key>"
						return 1
					fi
					[[ $1 = _* ]] || 1="_$1" 
					[[ $2 = .* ]] || 2=".$2" 
					[[ $2 = .menu-select ]] && zmodload -i zsh/complist
					zle -C "$1" "$2" "$func"
					if [[ -n $new ]]
					then
						bindkey "$3" | IFS=$' \t' read -A opt
						[[ $opt[-1] = undefined-key ]] && bindkey "$3" "$1"
					else
						bindkey "$3" "$1"
					fi
					shift 3
				done ;;
			(key) if [[ $# -lt 2 ]]
				then
					print -u2 "$0: missing keys"
					return 1
				fi
				if [[ $1 = .* ]]
				then
					[[ $1 = .menu-select ]] && zmodload -i zsh/complist
					zle -C "$func" "$1" "$func"
				else
					[[ $1 = menu-select ]] && zmodload -i zsh/complist
					zle -C "$func" ".$1" "$func"
				fi
				shift
				for i
				do
					if [[ -n $new ]]
					then
						bindkey "$i" | IFS=$' \t' read -A opt
						[[ $opt[-1] = undefined-key ]] || continue
					fi
					bindkey "$i" "$func"
				done ;;
			(*) while (( $# ))
				do
					if [[ "$1" = -N ]]
					then
						type=normal 
					elif [[ "$1" = -p ]]
					then
						type=pattern 
					elif [[ "$1" = -P ]]
					then
						type=postpattern 
					else
						case "$type" in
							(pattern) if [[ $1 = (#b)(*)=(*) ]]
								then
									_patcomps[$match[1]]="=$match[2]=$func" 
								else
									_patcomps[$1]="$func" 
								fi ;;
							(postpattern) if [[ $1 = (#b)(*)=(*) ]]
								then
									_postpatcomps[$match[1]]="=$match[2]=$func" 
								else
									_postpatcomps[$1]="$func" 
								fi ;;
							(*) if [[ "$1" = *\=* ]]
								then
									cmd="${1%%\=*}" 
									svc=yes 
								else
									cmd="$1" 
									svc= 
								fi
								if [[ -z "$new" || -z "${_comps[$1]}" ]]
								then
									_comps[$cmd]="$func" 
									[[ -n "$svc" ]] && _services[$cmd]="${1#*\=}" 
								fi ;;
						esac
					fi
					shift
				done ;;
		esac
	else
		case "$type" in
			(pattern) unset "_patcomps[$^@]" ;;
			(postpattern) unset "_postpatcomps[$^@]" ;;
			(key) print -u2 "$0: cannot restore key bindings"
				return 1 ;;
			(*) unset "_comps[$^@]" ;;
		esac
	fi
}
compdump () {
	# undefined
	builtin autoload -XUz /usr/share/zsh/5.9/functions
}
compinit () {
	# undefined
	builtin autoload -XUz /usr/share/zsh/5.9/functions
}
compinstall () {
	# undefined
	builtin autoload -XUz /usr/share/zsh/5.9/functions
}
conda () {
	_lazy_conda_setup && conda "$@"
}
create_playlist () {
	local playlist_name="$1" 
	local partial_name="$2" 
	echo "[DEBUG] create_playlist called with:" >&2
	echo "  playlist_name: $playlist_name" >&2
	echo "  partial_name: $partial_name" >&2
	if [[ "$playlist_name" != *.m3u ]]
	then
		playlist_name="${playlist_name}.m3u" 
	fi
	echo "[DEBUG] Using playlist name: $playlist_name" >&2
	local folder="/Users/derickdsouza/focusmusic" 
	if [[ ! -d "$folder" ]]
	then
		echo "[ERROR] Folder $folder does not exist." >&2
		return 1
	fi
	cd "$folder" || {
		echo "[ERROR] Could not navigate to $folder" >&2
		return 1
	}
	echo "[DEBUG] Current folder: $(pwd)" >&2
	: > "$playlist_name"
	echo "[DEBUG] Playlist initialized: $playlist_name" >&2
	local -a matching_files=() 
	if [[ -n "$partial_name" ]]
	then
		while IFS= read -r -d $'\0' file
		do
			matching_files+=("$file") 
		done < <(find . -maxdepth 1 -type f -iname "*$partial_name*" -print0 2>/dev/null)
	fi
	local -a all_files=() 
	while IFS= read -r -d $'\0' file
	do
		all_files+=("$file") 
	done < <(find . -maxdepth 1 -type f -print0 2>/dev/null)
	if [[ ${#matching_files[@]} -gt 0 ]]
	then
		echo "[DEBUG] Adding matching files to playlist..." >&2
		printf "%s\n" "${matching_files[@]}" >> "$playlist_name"
	else
		echo "[DEBUG] No matching files found for partial name: $partial_name" >&2
	fi
	echo "[DEBUG] Adding non-matching files..." >&2
	for f in "${all_files[@]}"
	do
		if ! array_contains matching_files "$f"
		then
			echo "$f" >> "$playlist_name"
		fi
	done
	echo "[DEBUG] Final playlist created: $playlist_name" >&2
	echo "$playlist_name"
	return 0
}
deactivate () {
	_lazy_conda_setup && conda deactivate "$@"
}
enable_poshtooltips () {
	local widget=${$(bindkey ' '):2} 
	if [[ -z $widget ]]
	then
		widget=self-insert 
	fi
	_omp_create_widget $widget _omp_render_tooltip
}
enable_poshtransientprompt () {
	
}
fix_symlinks () {
	local folder="${1:-.}" 
	echo "Scanning folder: $folder for symbolic links..."
	for item in "$folder"/*
	do
		if [ -L "$item" ]
		then
			local target
			target="$(readlink "$item")" 
			if [ ! -e "$target" ]
			then
				echo "Broken symlink found: $item -> $target"
				local base
				base="$(basename "$target")" 
				echo "Searching for a file/directory named '$base' in your home directory..."
				IFS=$'\n' read -r -d '' -a matches < <(find "$HOME" -name "$base" 2>/dev/null && printf '\0')
				if [ "${#matches[@]}" -eq 1 ]
				then
					local new_target="${matches[0]}" 
					echo "Found unique match: $new_target"
					echo "Updating symlink: $item will now point to $new_target"
					rm "$item"
					ln -s "$new_target" "$item"
				else
					echo "Unable to auto-fix $item. Found ${#matches[@]} matches for '$base'."
					echo "Please update it manually."
				fi
			else
				echo "Symlink OK: $item -> $target"
			fi
		fi
	done
	echo "Done scanning $folder."
}
gcdd () {
	local repo="$1" 
	git clone "git@derickdsouza:$repo.git"
}
getent () {
	if [[ $1 = hosts ]]
	then
		sed 's/#.*//' /etc/$1 | grep -w $2
	elif [[ $2 = <-> ]]
	then
		grep ":$2:[^:]*$" /etc/$1
	else
		grep "^$2:" /etc/$1
	fi
}
node () {
	_lazy_nvm && node "$@"
}
npm () {
	_lazy_nvm && npm "$@"
}
npx () {
	_lazy_nvm && npx "$@"
}
nvm () {
	_lazy_nvm && nvm "$@"
}
set_poshcontext () {
	return
}
yt () {
	local video_link="$1" 
	fabric -y "$video_link" --transcript
}
# Shell Options
setopt nohashdirs
setopt login
# Aliases
alias -- ai-help='cat /Users/derickdsouza/.ai-instructions/README.md'
alias -- ai-protocol='cat /Users/derickdsouza/.ai-instructions/git_commit_protocol.md'
alias -- ai-setup=/Users/derickdsouza/.ai-instructions/setup/setup-project.sh
alias -- autocode='source /Users/derickdsouza/Projects/development/coding-agent-harness/.venv/bin/activate && python /Users/derickdsouza/Projects/development/coding-agent-harness/autocode.py'
alias -- autocode-dashboard=/Users/derickdsouza/Projects/development/coding-agent-harness/autocode-dashboard.sh
alias -- ccall=claude
alias -- claude-doctor='timeout 2 claude doctor && echo '\''✅ Claude Code diagnostic completed'\'
alias -- cls=clear
alias -- code-agent-cd='cd /Users/derickdsouza/Projects/development/coding-agent-harness'
alias -- code-agent-detect='source /Users/derickdsouza/Projects/development/coding-agent-harness/.venv/bin/activate && cd /Users/derickdsouza/Projects/development/coding-agent-harness && ./work-on-project.sh detect'
alias -- code-agent-run='source /Users/derickdsouza/Projects/development/coding-agent-harness/.venv/bin/activate && cd /Users/derickdsouza/Projects/development/coding-agent-harness && ./work-on-project.sh run'
alias -- code-agent-update='source /Users/derickdsouza/Projects/development/coding-agent-harness/.venv/bin/activate && cd /Users/derickdsouza/Projects/development/coding-agent-harness && ./work-on-project.sh both'
alias -- comfyui='cd /Users/derickdsouza/ai/repos/ComfyUI && conda activate comfyenv && python main.py'
alias -- cpall='copilot --allow-all-tools'
alias -- cxall='codex --dangerously-bypass-approvals-and-sandbox'
alias -- deconda='conda deactivate'
alias -- fcd='cd $(find . -type d | fzf)'
alias -- fe='fzf --preview "cat {}" | xargs -r nano'
alias -- ff='fzf --preview "cat {}" --preview-window=right:50%'
alias -- fgit='git log --oneline | fzf --preview "git show {1}"'
alias -- fixlinks=fix_symlinks
alias -- fkill='ps aux | fzf | awk "{print \$2}" | xargs kill'
alias -- focus=_playfolder
alias -- getrss='python ~/ai/apps/get_yt_channel_feed.py'
alias -- mfc='cd /Users/derickdsouza/Projects/development/mfcapp'
alias -- mywles='cd ~/Projects/GitHub/mywles'
alias -- nelson-ctl=/Users/derickdsouza/Projects/development/minion-scripts/mutation-testing/nelson-ctl.sh
alias -- noprint='unset DYLD_PRINT_LIBRARIES'
alias -- npmfix='npm audit fix'
alias -- profile='nano ~/.zprofile'
alias -- ralph-ctl=/Users/derickdsouza/Projects/development/minion-scripts/mutation-testing/ralph-ctl.sh
alias -- reprofile='source ~/.zprofile'
alias -- requirements='pip install -r requirements.txt'
alias -- run-help=man
alias -- sa='cd ~/Projects/GitHub/smartaffirm/SmartAffirm'
alias -- saui='cd ~/Projects/GitHub/smartaffirm/SmartAffirm/saUI'
alias -- sfx='cd ~/Projects/GitHub/sfxlive'
alias -- ssot=./scripts/ssot-sync.sh
alias -- ssot-docs='code ~/.ai-dev-workflow/README-SSOT.md'
alias -- ssot-framework='~/.ai-dev-workflow/agent-agnostic-ssot-framework.md'
alias -- ssot-templates='~/.ai-dev-workflow/agent-agnostic-command-templates.md'
alias -- ssot-validate='~/.ai-dev-workflow/agent-agnostic-validation-framework.md'
alias -- web='cd ~/Projects/GitHub/website'
alias -- which-command=whence
# Check for rg availability
if ! (unalias rg 2>/dev/null; command -v rg) >/dev/null 2>&1; then
  function rg {
  local _cc_bin="${CLAUDE_CODE_EXECPATH:-}"
  [[ -x $_cc_bin ]] || _cc_bin=$(command -v claude 2>/dev/null)
  if [[ ! -x $_cc_bin ]]; then command rg "$@"; return; fi
  if [[ -n $ZSH_VERSION ]]; then
    ARGV0=rg "$_cc_bin" "$@"
  elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    ARGV0=rg "$_cc_bin" "$@"
  elif [[ $BASHPID != $$ ]]; then
    exec -a rg "$_cc_bin" "$@"
  else
    (exec -a rg "$_cc_bin" "$@")
  fi
}
fi
# Shadow find/grep with embedded bfs/ugrep
unalias find 2>/dev/null || true
unalias grep 2>/dev/null || true
function find {
  local _cc_bin="${CLAUDE_CODE_EXECPATH:-}"
  [[ -x $_cc_bin ]] || _cc_bin=$(command -v claude 2>/dev/null)
  if [[ ! -x $_cc_bin ]]; then command find "$@"; return; fi
  if [[ -n $ZSH_VERSION ]]; then
    ARGV0=bfs "$_cc_bin" -regextype findutils-default "$@"
  elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    ARGV0=bfs "$_cc_bin" -regextype findutils-default "$@"
  elif [[ $BASHPID != $$ ]]; then
    exec -a bfs "$_cc_bin" -regextype findutils-default "$@"
  else
    (exec -a bfs "$_cc_bin" -regextype findutils-default "$@")
  fi
}
function grep {
  local _cc_bin="${CLAUDE_CODE_EXECPATH:-}"
  [[ -x $_cc_bin ]] || _cc_bin=$(command -v claude 2>/dev/null)
  if [[ ! -x $_cc_bin ]]; then command grep "$@"; return; fi
  if [[ -n $ZSH_VERSION ]]; then
    ARGV0=ugrep "$_cc_bin" -G --ignore-files --hidden -I --exclude-dir=.git --exclude-dir=.svn --exclude-dir=.hg --exclude-dir=.bzr --exclude-dir=.jj --exclude-dir=.sl "$@"
  elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    ARGV0=ugrep "$_cc_bin" -G --ignore-files --hidden -I --exclude-dir=.git --exclude-dir=.svn --exclude-dir=.hg --exclude-dir=.bzr --exclude-dir=.jj --exclude-dir=.sl "$@"
  elif [[ $BASHPID != $$ ]]; then
    exec -a ugrep "$_cc_bin" -G --ignore-files --hidden -I --exclude-dir=.git --exclude-dir=.svn --exclude-dir=.hg --exclude-dir=.bzr --exclude-dir=.jj --exclude-dir=.sl "$@"
  else
    (exec -a ugrep "$_cc_bin" -G --ignore-files --hidden -I --exclude-dir=.git --exclude-dir=.svn --exclude-dir=.hg --exclude-dir=.bzr --exclude-dir=.jj --exclude-dir=.sl "$@")
  fi
}
export PATH='/Applications/cmux.app/Contents/Resources/bin:/Users/derickdsouza/Projects/development/portfolio-manager/scripts:/Users/derickdsouza/.cargo/bin:/Users/derickdsouza/bin:/Users/derickdsouza/.antigravity/antigravity/bin:/Users/derickdsouza/.bun/bin:/Users/derickdsouza/.nvm/versions/node/v24.7.0/bin:/Users/derickdsouza/.codeium/windsurf/bin:/Users/derickdsouza/.claude/local/node_modules/.bin:/opt/homebrew/anaconda3/condabin:/Users/derickdsouza/go/bin:/usr/local/go/lib/bin:/Users/derickdsouza/.local/bin:/usr/local/go/bin:/Users/derickdsouza/ai/apps:/Users/derickdsouza/.pyenv/bin:/opt/homebrew/anaconda3/bin:/Users/derickdsouza/.dotnet/tools:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin:/opt/pkg/env/active/bin:/opt/pmk/env/global/bin:/Library/Apple/usr/bin:/Applications/VMware Fusion.app/Contents/Public:/usr/local/share/dotnet:~/.dotnet/tools:/usr/local/go/bin:/opt/podman/bin:/Users/derickdsouza/.cache/lm-studio/bin:/Users/derickdsouza/.claude/plugins/cache/claude-plugins-official/typescript-lsp/1.0.0/bin'
