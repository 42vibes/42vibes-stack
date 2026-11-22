#!/bin/sh
# 42vibes stack installer.
#
# Installs the 42vibes color palette into existing tools without destroying
# user configuration. Every overwritten file is backed up first; include
# lines are appended at most once.
#
# POSIX sh / bash 3.2 compatible (macOS). No global installation, no network
# access unless --clone is given explicitly.
#
# Exit codes:
#   0  ready / done
#   1  blocked, partial success, or aborted
#   2  usage error (including write runs without --yes when stdin is no TTY)

set -eu

PROG="42vibes-install"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
SOURCE_ROOT=${VIBES_SOURCE_ROOT:-$SCRIPT_DIR/..}

DRY_RUN=0
CHECK_MODE=0
ASSUME_YES=0
COPY_MODE=0
DO_CLONE=0
ALL_FLAG=0
ONLY_SET=0
ONLY_RAW=
HOME_DIR=
HOME_OVERRIDE=0
SELECTED=

COUNT_INSTALLED=0
COUNT_UNCHANGED=0
COUNT_SKIPPED=0
COUNT_MANUAL=0
COUNT_FAILED=0
LAST_CHANGED=0
REPO_DIR=
REPO_PLANNED=0

GLOBAL_BLOCK=0
GLOBAL_REASON=
CANON_HOME=
PREFLIGHT_REASON=
PREFLIGHT_PLANNED_CLONE=0
REPO_PATH=

PF_PLANNED=0
PF_BLOCKED=0
PF_SKIPPED=0
PF_MANUAL=0

BAT_BIN=
BAT_SKIP_CACHE=0
GIT_INCLUDE_PRESENT=0
GNOME_NOTE=

OS_ID=
OS_LIKE=
OS_VER=

ST_OPENCODE=skip
ST_VIM=skip
ST_STARSHIP=skip
ST_BAT=skip
ST_DELTA=skip
ST_TERMINAL=skip
ST_VSCODE=skip

NOTE_OPENCODE=
NOTE_VIM=
NOTE_STARSHIP=
NOTE_BAT=
NOTE_DELTA=
NOTE_TERMINAL=
NOTE_VSCODE=

FIX_OPENCODE=
FIX_VIM=
FIX_STARSHIP=
FIX_BAT=
FIX_DELTA=
FIX_TERMINAL=
FIX_VSCODE=

MANUAL_OPENCODE=0
MANUAL_VIM=0
MANUAL_STARSHIP=0
MANUAL_BAT=0
MANUAL_DELTA=0
MANUAL_TERMINAL=0
MANUAL_VSCODE=0

usage() {
	cat <<'EOF'
42vibes stack installer

Usage:
  ./install-all.sh [options]

Installs the 42vibes palette into OpenCode, Vim, Starship, bat, delta and
supported terminal emulators. Sources are neighbouring checkouts of the
42vibes repositories (../42vibes-opencode, ../42vibes-vim, ../42vibes-bash,
../42vibes-terminal, ../42vibes-vscode).

Options:
  --check              Show status and remedies only; write nothing, do not
                       clone, do not build caches and do not create the home.
  --dry-run            Run the preflight, show planned changes, write nothing.
  --yes                Do not ask for confirmation. Required for write runs
                       when stdin is not a TTY.
  --only <list>        Comma-separated components:
                       opencode,vim,starship,bat,delta,terminal,vscode
  --all                All standard components, including terminal
                       integrations. vscode is still opt-in.
  --home <dir>         Target home directory (default: $HOME). Intended for
                       tests.
  --copy               Copy theme files instead of symlinking them.
  --clone              Clone missing checkouts from
                       https://github.com/42vibes/<repo>.git
  --help, -h           Show this help.

Default selection: opencode,vim,starship,bat,delta. The terminal component
is only enabled by --all or an explicit --only terminal. vscode is only
enabled by --only vscode.

Exit codes:
  0  ready / done
  1  blocked, partial success, or aborted
  2  usage error

Preflight runs before every write and is always read-only. It checks sources,
target paths, symlink containment and writability, and required tools. The
target home is created only after confirmation.

Backups are written next to the replaced file as
<file>.bak.YYYYMMDDTHHMMSSZ (UTC). A second run is a no-op: identical files
are not rewritten and include lines are not duplicated.
EOF
}

die() {
	printf 'Error: %s\n' "$*" >&2
	exit 2
}

info() {
	printf '[42vibes] %s\n' "$*"
}

warn() {
	printf '[42vibes] warning: %s\n' "$*" >&2
}

selected() {
	case " $SELECTED " in
		*" $1 "*) return 0 ;;
		*) return 1 ;;
	esac
}

add_selected() {
	if ! selected "$1"; then
		SELECTED="$SELECTED $1"
	fi
}

select_all_standard() {
	add_selected opencode
	add_selected vim
	add_selected starship
	add_selected bat
	add_selected delta
	add_selected terminal
}

parse_only() {
	raw=$(printf '%s' "$1" | tr -d ' ')
	[ -n "$raw" ] || die "--only needs at least one component"
	case $raw in
		*[!A-Za-z0-9_,-]*) die "invalid --only list: $1" ;;
	esac
	items=$(printf '%s' "$raw" | tr ',' ' ')
	for item in $items; do
		case $item in
			'') continue ;;
			opencode|vim|starship|bat|delta|terminal|vscode)
				add_selected "$item"
				;;
			all)
				ALL_FLAG=1
				;;
			*)
				die "unknown component: $item (expected opencode,vim,starship,bat,delta,terminal,vscode)"
				;;
		esac
	done
}

# ---------------------------------------------------------------------------
# Operating system detection and install hints (never executes an install).

read_os_release() {
	OS_ID=
	OS_LIKE=
	OS_VER=
	if [ -r /etc/os-release ]; then
		while IFS='=' read -r key value; do
			value=${value%\"}
			value=${value#\"}
			case $key in
				ID) OS_ID=$value ;;
				ID_LIKE) OS_LIKE=$value ;;
				VERSION_ID) OS_VER=$value ;;
			esac
		done < /etc/os-release
	fi
}

is_debian() {
	[ "$OS_ID" = debian ]
}

is_ubuntu() {
	[ "$OS_ID" = ubuntu ] && return 0
	case " $OS_LIKE " in
		*" ubuntu "*) return 0 ;;
	esac
	return 1
}

is_debian_family() {
	is_debian && return 0
	is_ubuntu && return 0
	case " $OS_LIKE " in
		*" debian "*) return 0 ;;
	esac
	return 1
}

is_macos() {
	[ "$(uname -s 2>/dev/null || true)" = Darwin ]
}

debian_recent() {
	[ "$OS_ID" = debian ] || return 1
	[ -n "$OS_VER" ] || return 0
	major=${OS_VER%%.*}
	case $major in
		''|*[!0-9]*) return 1 ;;
	esac
	[ "$major" -ge 13 ]
}

ubuntu_recent() {
	is_ubuntu || return 1
	[ -n "$OS_VER" ] || return 1
	major=${OS_VER%%.*}
	rest=${OS_VER#*.}
	[ "$rest" = "$OS_VER" ] && rest=0
	minor=${rest%%.*}
	case $major in
		''|*[!0-9]*) return 1 ;;
	esac
	case $minor in
		''|*[!0-9]*) minor=0 ;;
	esac
	[ $((major * 100 + minor)) -ge 2504 ]
}

apt_recent() {
	debian_recent || ubuntu_recent
}

tool_hint() {
	tool=$1
	case $tool in
		starship)
			if apt_recent; then
				printf '    apt install starship\n'
			elif is_macos; then
				printf '    brew install starship\n'
			else
				printf '    curl -sS https://starship.rs/install.sh | sh\n'
				printf '    # or: brew install starship\n'
			fi
			;;
		bat)
			if is_debian_family; then
				printf '    apt install bat\n'
				printf '    # Debian installs the binary as batcat; both names are supported.\n'
			elif is_macos; then
				printf '    brew install bat\n'
			else
				printf '    apt install bat   # or: brew install bat\n'
			fi
			;;
		delta)
			if is_debian_family; then
				printf '    apt install git-delta\n'
			elif is_macos; then
				printf '    brew install git-delta\n'
			else
				printf '    cargo install git-delta   # or: brew install git-delta\n'
			fi
			;;
		git)
			if is_debian_family; then
				printf '    apt install git\n'
			elif is_macos; then
				printf '    brew install git\n'
			else
				printf '    # install git with your package manager\n'
			fi
			;;
		code)
			printf '    # install VS Code or VSCodium and make code/codium available on PATH\n'
			;;
		*)
			printf '    # install %s with your package manager\n' "$tool"
			;;
	esac
	printf '    (hint only; this installer never runs package managers and never uses sudo)\n'
}

# ---------------------------------------------------------------------------
# Read-only path safety and preflight helpers.

canonical_path() {
	p=$1
	if command -v readlink >/dev/null 2>&1; then
		if out=$(readlink -f -- "$p" 2>/dev/null); then
			if [ -n "$out" ]; then
				printf '%s\n' "$out"
				return 0
			fi
		fi
	fi
	if [ -d "$p" ]; then
		(CDPATH= cd -P -- "$p" 2>/dev/null && pwd -P)
		return $?
	fi
	if [ -e "$p" ] || [ -L "$p" ]; then
		d=$(CDPATH= cd -P -- "$(dirname "$p")" 2>/dev/null && pwd -P) || return 1
		printf '%s/%s\n' "${d%/}" "$(basename "$p")"
		return 0
	fi
	d=$(canonical_path "$(dirname "$p")") || return 1
	printf '%s/%s\n' "${d%/}" "$(basename "$p")"
}

is_within_home() {
	real=$(canonical_path "$1") || return 1
	case $real in
		"$CANON_HOME") return 0 ;;
		"$CANON_HOME"/*) return 0 ;;
		*) return 1 ;;
	esac
}

nearest_existing_dir() {
	p=$1
	while [ ! -d "$p" ]; do
		next=$(dirname "$p")
		if [ "$next" = "$p" ]; then
			break
		fi
		p=$next
	done
	printf '%s\n' "$p"
}

# Sets PREFLIGHT_REASON and returns non-zero when a target cannot be written
# safely. Never creates anything.
#
# mode=replace: the target is removed and recreated (symlink or copy). The
#   final path component may be a symlink; only the parent must stay inside
#   the target home. No write ever follows that symlink.
# mode=append: the target is appended to in place. A symlink target must
#   resolve inside the target home.
check_target_path() {
	path=$1
	mode=${2:-replace}
	parent=$(dirname "$path")

	if [ "$mode" = append ]; then
		if ! is_within_home "$path"; then
			PREFLIGHT_REASON="target resolves outside target home: $path"
			return 1
		fi
	else
		case $path in
			"$HOME_DIR"|"$HOME_DIR"/*) ;;
			*)
				PREFLIGHT_REASON="target is outside target home: $path"
				return 1
				;;
		esac
		if ! is_within_home "$parent"; then
			PREFLIGHT_REASON="parent resolves outside target home: $parent"
			return 1
		fi
	fi

	if [ -d "$path" ] && [ ! -L "$path" ]; then
		PREFLIGHT_REASON="target is a directory: $path"
		return 1
	fi
	while [ ! -d "$parent" ]; do
		if [ -e "$parent" ] || [ -L "$parent" ]; then
			PREFLIGHT_REASON="parent is not a directory: $parent"
			return 1
		fi
		next=$(dirname "$parent")
		if [ "$next" = "$parent" ]; then
			break
		fi
		parent=$next
	done
	if [ ! -w "$parent" ] || [ ! -x "$parent" ]; then
		PREFLIGHT_REASON="not writable: $parent"
		return 1
	fi
	if [ "$mode" = append ] && [ -e "$path" ] && [ ! -w "$path" ]; then
		PREFLIGHT_REASON="target is not writable: $path"
		return 1
	fi
	return 0
}

preflight_home() {
	if [ -L "$HOME_DIR" ]; then
		GLOBAL_BLOCK=1
		GLOBAL_REASON="target home is a symlink; pass its real directory: $HOME_DIR"
		return 1
	fi
	if [ -e "$HOME_DIR" ]; then
		if [ ! -d "$HOME_DIR" ]; then
			GLOBAL_BLOCK=1
			GLOBAL_REASON="target home is not a directory: $HOME_DIR"
			return 1
		fi
		if [ ! -w "$HOME_DIR" ] || [ ! -x "$HOME_DIR" ]; then
			GLOBAL_BLOCK=1
			GLOBAL_REASON="target home is not writable: $HOME_DIR"
			return 1
		fi
	else
		parent=$(dirname "$HOME_DIR")
		while [ ! -d "$parent" ]; do
			if [ -e "$parent" ] || [ -L "$parent" ]; then
				GLOBAL_BLOCK=1
				GLOBAL_REASON="parent of target home is not a directory: $parent"
				return 1
			fi
			next=$(dirname "$parent")
			if [ "$next" = "$parent" ]; then
				break
			fi
			parent=$next
		done
		if [ ! -w "$parent" ] || [ ! -x "$parent" ]; then
			GLOBAL_BLOCK=1
			GLOBAL_REASON="cannot create target home: $parent is not writable"
			return 1
		fi
	fi
	if [ -z "$CANON_HOME" ] || [ "$CANON_HOME" = / ]; then
		GLOBAL_BLOCK=1
		GLOBAL_REASON="refusing to use / as target home"
		return 1
	fi
	return 0
}

set_status() {
	case $1 in
		opencode) ST_OPENCODE=$2; NOTE_OPENCODE=${3:-} ;;
		vim) ST_VIM=$2; NOTE_VIM=${3:-} ;;
		starship) ST_STARSHIP=$2; NOTE_STARSHIP=${3:-} ;;
		bat) ST_BAT=$2; NOTE_BAT=${3:-} ;;
		delta) ST_DELTA=$2; NOTE_DELTA=${3:-} ;;
		terminal) ST_TERMINAL=$2; NOTE_TERMINAL=${3:-} ;;
		vscode) ST_VSCODE=$2; NOTE_VSCODE=${3:-} ;;
	esac
}

get_status() {
	case $1 in
		opencode) printf '%s' "$ST_OPENCODE" ;;
		vim) printf '%s' "$ST_VIM" ;;
		starship) printf '%s' "$ST_STARSHIP" ;;
		bat) printf '%s' "$ST_BAT" ;;
		delta) printf '%s' "$ST_DELTA" ;;
		terminal) printf '%s' "$ST_TERMINAL" ;;
		vscode) printf '%s' "$ST_VSCODE" ;;
	esac
}

get_note() {
	case $1 in
		opencode) printf '%s' "$NOTE_OPENCODE" ;;
		vim) printf '%s' "$NOTE_VIM" ;;
		starship) printf '%s' "$NOTE_STARSHIP" ;;
		bat) printf '%s' "$NOTE_BAT" ;;
		delta) printf '%s' "$NOTE_DELTA" ;;
		terminal) printf '%s' "$NOTE_TERMINAL" ;;
		vscode) printf '%s' "$NOTE_VSCODE" ;;
	esac
}

set_fix() {
	case $1 in
		opencode) FIX_OPENCODE=${2:-} ;;
		vim) FIX_VIM=${2:-} ;;
		starship) FIX_STARSHIP=${2:-} ;;
		bat) FIX_BAT=${2:-} ;;
		delta) FIX_DELTA=${2:-} ;;
		terminal) FIX_TERMINAL=${2:-} ;;
		vscode) FIX_VSCODE=${2:-} ;;
	esac
}

get_fix() {
	case $1 in
		opencode) printf '%s' "$FIX_OPENCODE" ;;
		vim) printf '%s' "$FIX_VIM" ;;
		starship) printf '%s' "$FIX_STARSHIP" ;;
		bat) printf '%s' "$FIX_BAT" ;;
		delta) printf '%s' "$FIX_DELTA" ;;
		terminal) printf '%s' "$FIX_TERMINAL" ;;
		vscode) printf '%s' "$FIX_VSCODE" ;;
	esac
}

set_manual() {
	case $1 in
		opencode) MANUAL_OPENCODE=1 ;;
		vim) MANUAL_VIM=1 ;;
		starship) MANUAL_STARSHIP=1 ;;
		bat) MANUAL_BAT=1 ;;
		delta) MANUAL_DELTA=1 ;;
		terminal) MANUAL_TERMINAL=1 ;;
		vscode) MANUAL_VSCODE=1 ;;
	esac
}

is_manual() {
	case $1 in
		opencode) [ "$MANUAL_OPENCODE" = 1 ] ;;
		vim) [ "$MANUAL_VIM" = 1 ] ;;
		starship) [ "$MANUAL_STARSHIP" = 1 ] ;;
		bat) [ "$MANUAL_BAT" = 1 ] ;;
		delta) [ "$MANUAL_DELTA" = 1 ] ;;
		terminal) [ "$MANUAL_TERMINAL" = 1 ] ;;
		vscode) [ "$MANUAL_VSCODE" = 1 ] ;;
		*) return 1 ;;
	esac
}

component_blocked() {
	[ "$(get_status "$1")" = blocked ]
}

# Returns 0 when the checkout is usable or a clone is planned. On failure sets
# PREFLIGHT_REASON. Never clones.
preflight_repo() {
	repo=$1
	PREFLIGHT_PLANNED_CLONE=0
	REPO_PATH=$SOURCE_ROOT/$repo
	if [ -d "$REPO_PATH" ]; then
		if [ ! -r "$REPO_PATH" ] || [ ! -x "$REPO_PATH" ]; then
			PREFLIGHT_REASON="source checkout is not readable: $REPO_PATH"
			return 1
		fi
		return 0
	fi
	if [ -e "$REPO_PATH" ] || [ -L "$REPO_PATH" ]; then
		PREFLIGHT_REASON="source path exists but is not a directory: $REPO_PATH"
		return 1
	fi
	if [ "$DO_CLONE" = 1 ] && [ "$CHECK_MODE" != 1 ]; then
		if ! command -v git >/dev/null 2>&1; then
			PREFLIGHT_REASON="cannot clone $repo: git not found"
			return 1
		fi
		parent=$(nearest_existing_dir "$(dirname "$REPO_PATH")")
		if [ ! -d "$parent" ]; then
			PREFLIGHT_REASON="cannot clone $repo: no existing parent directory"
			return 1
		fi
		if [ ! -w "$parent" ] || [ ! -x "$parent" ]; then
			PREFLIGHT_REASON="cannot clone $repo: $parent is not writable"
			return 1
		fi
		PREFLIGHT_PLANNED_CLONE=1
		return 0
	fi
	if [ "$CHECK_MODE" = 1 ] && [ "$DO_CLONE" = 1 ]; then
		PREFLIGHT_REASON="missing checkout: $REPO_PATH (--check never clones; rerun with --clone)"
	else
		PREFLIGHT_REASON="missing checkout: $REPO_PATH"
	fi
	return 1
}

preflight_source_file() {
	src=$1
	if [ ! -f "$src" ] || [ ! -r "$src" ]; then
		PREFLIGHT_REASON="source file is not readable: $src"
		return 1
	fi
	return 0
}

block_component() {
	set_status "$1" blocked "$2"
	set_fix "$1" "${3:-path}"
}

ready_component() {
	set_status "$1" ready "$2"
}

preflight_opencode() {
	dest=$HOME_DIR/.config/opencode/themes/42vibes.json
	if ! preflight_repo 42vibes-opencode; then
		block_component opencode "$PREFLIGHT_REASON" "clone:42vibes-opencode"
		return 0
	fi
	if [ "$PREFLIGHT_PLANNED_CLONE" = 1 ]; then
		if check_target_path "$dest"; then
			ready_component opencode "will clone 42vibes-opencode; target $dest"
		else
			block_component opencode "$PREFLIGHT_REASON" path
		fi
		return 0
	fi
	if ! preflight_source_file "$REPO_PATH/themes/42vibes.json"; then
		block_component opencode "$PREFLIGHT_REASON" source
		return 0
	fi
	if check_target_path "$dest"; then
		ready_component opencode "$dest"
	else
		block_component opencode "$PREFLIGHT_REASON" path
	fi
	return 0
}

preflight_vim() {
	if ! preflight_repo 42vibes-vim; then
		block_component vim "$PREFLIGHT_REASON" "clone:42vibes-vim"
		return 0
	fi
	src="$REPO_PATH/colors/42vibes.vim"
	if [ "$PREFLIGHT_PLANNED_CLONE" = 1 ]; then
		if [ ! -d "$HOME_DIR/.vim" ] && [ -d "$XDG_CONFIG_HOME/vim" ]; then
			dest="$XDG_CONFIG_HOME/vim/colors/42vibes.vim"
		else
			dest="$HOME_DIR/.vim/colors/42vibes.vim"
		fi
		if check_target_path "$dest"; then
			ready_component vim "will clone 42vibes-vim; target $dest"
		else
			block_component vim "$PREFLIGHT_REASON" path
		fi
		return 0
	fi
	if ! preflight_source_file "$src"; then
		block_component vim "$PREFLIGHT_REASON" source
		return 0
	fi
	if [ ! -d "$HOME_DIR/.vim" ] && [ -d "$XDG_CONFIG_HOME/vim" ]; then
		dest="$XDG_CONFIG_HOME/vim/colors/42vibes.vim"
	else
		dest="$HOME_DIR/.vim/colors/42vibes.vim"
	fi
	if check_target_path "$dest"; then
		ready_component vim "$dest"
	else
		block_component vim "$PREFLIGHT_REASON" path
	fi
	return 0
}

preflight_starship() {
	dest=$HOME_DIR/.config/starship.toml
	if ! preflight_repo 42vibes-bash; then
		block_component starship "$PREFLIGHT_REASON" "clone:42vibes-bash"
		return 0
	fi
	if [ "$PREFLIGHT_PLANNED_CLONE" = 1 ]; then
		if check_target_path "$dest"; then
			ready_component starship "will clone 42vibes-bash; target $dest"
		else
			block_component starship "$PREFLIGHT_REASON" path
		fi
		return 0
	fi
	if ! preflight_source_file "$REPO_PATH/starship.toml"; then
		block_component starship "$PREFLIGHT_REASON" source
		return 0
	fi
	if ! check_target_path "$dest"; then
		block_component starship "$PREFLIGHT_REASON" path
		return 0
	fi
	if command -v starship >/dev/null 2>&1; then
		ready_component starship "$dest"
	elif [ "$ONLY_SET" = 1 ] && [ "$ALL_FLAG" != 1 ]; then
		block_component starship "starship is not installed" "install:starship"
		return 0
	else
		ready_component starship "$dest (config prepared; starship is not installed yet)"
		set_manual starship
	fi
	if [ -n "${STARSHIP_CONFIG:-}" ]; then
		set_status starship "$(get_status starship)" "$(get_note starship); STARSHIP_CONFIG=$STARSHIP_CONFIG overrides this path"
		set_manual starship
	fi
	return 0
}

preflight_bat() {
	themes=$HOME_DIR/.config/bat/themes
	dest1=$themes/42vibes.tmTheme
	dest2=$themes/42vibes-light.tmTheme
	BAT_SKIP_CACHE=0
	if ! preflight_repo 42vibes-bash; then
		block_component bat "$PREFLIGHT_REASON" "clone:42vibes-bash"
		return 0
	fi
	if [ "$PREFLIGHT_PLANNED_CLONE" = 1 ]; then
		if check_target_path "$dest1" && check_target_path "$dest2"; then
			ready_component bat "will clone 42vibes-bash; target $themes"
		else
			block_component bat "$PREFLIGHT_REASON" path
		fi
		return 0
	fi
	for variant in 42vibes 42vibes-light; do
		if ! preflight_source_file "$REPO_PATH/bat/$variant.tmTheme"; then
			block_component bat "$PREFLIGHT_REASON" source
			return 0
		fi
	done
	if ! check_target_path "$dest1" || ! check_target_path "$dest2"; then
		block_component bat "$PREFLIGHT_REASON" path
		return 0
	fi

	BAT_BIN=
	if command -v bat >/dev/null 2>&1; then
		BAT_BIN=bat
	elif command -v batcat >/dev/null 2>&1; then
		BAT_BIN=batcat
	fi
	if [ -z "$BAT_BIN" ]; then
		if [ "$ONLY_SET" = 1 ] && [ "$ALL_FLAG" != 1 ]; then
			block_component bat "neither bat nor batcat is installed" "install:bat"
			return 0
		fi
		ready_component bat "$themes (bat/batcat is not installed yet; cache build deferred)"
		set_manual bat
		return 0
	fi

	cache_dir=${BAT_CACHE_PATH:-${XDG_CACHE_HOME:-$HOME_DIR/.cache}/bat}
	case $cache_dir in
		/*) ;;
		*)
			ready_component bat "$themes (relative cache path; cache build skipped)"
			set_manual bat
			BAT_SKIP_CACHE=1
			return 0
			;;
	esac
	if ! is_within_home "$cache_dir"; then
		ready_component bat "$themes (cache path outside target home; cache build skipped)"
		set_manual bat
		BAT_SKIP_CACHE=1
		return 0
	fi
	cache_parent=$(nearest_existing_dir "$(dirname "$cache_dir")")
	if [ ! -w "$cache_parent" ] || [ ! -x "$cache_parent" ]; then
		ready_component bat "$themes (cache path not writable; cache build skipped)"
		set_manual bat
		BAT_SKIP_CACHE=1
		return 0
	fi
	ready_component bat "$themes (cache build via $BAT_BIN)"
	return 0
}

preflight_delta() {
	gitconfig1=$HOME_DIR/.gitconfig
	gitconfig2=$XDG_CONFIG_HOME/git/config
	if ! preflight_repo 42vibes-bash; then
		block_component delta "$PREFLIGHT_REASON" "clone:42vibes-bash"
		return 0
	fi
	if ! command -v git >/dev/null 2>&1; then
		block_component delta "git is not installed" "install:git"
		return 0
	fi
	if ! command -v delta >/dev/null 2>&1; then
		block_component delta "delta is not installed (the include would set pager/diffFilter without delta)" "install:delta"
		return 0
	fi
	if [ "$PREFLIGHT_PLANNED_CLONE" = 1 ]; then
		ready_component delta "will clone 42vibes-bash; include path $REPO_PATH/delta.gitconfig"
		return 0
	fi
	if ! preflight_source_file "$REPO_PATH/delta.gitconfig"; then
		block_component delta "$PREFLIGHT_REASON" source
		return 0
	fi

	if [ -n "${GIT_CONFIG_GLOBAL:-}" ]; then
		gitconfig1=$GIT_CONFIG_GLOBAL
		gitconfig2=
	fi
	if [ -n "$gitconfig1" ] && ! check_target_path "$gitconfig1" append; then
		block_component delta "$PREFLIGHT_REASON" path
		return 0
	fi
	if [ -n "$gitconfig2" ] && { [ -e "$gitconfig2" ] || [ -L "$gitconfig2" ]; } && ! check_target_path "$gitconfig2" append; then
		block_component delta "$PREFLIGHT_REASON" path
		return 0
	fi

	GIT_INCLUDE_PRESENT=0
	if git config --global --get-all include.path 2>/dev/null | grep -Fqx -e "$REPO_PATH/delta.gitconfig"; then
		GIT_INCLUDE_PRESENT=1
	fi
	ready_component delta "$REPO_PATH/delta.gitconfig (include in $gitconfig1)"
	return 0
}

preflight_terminal() {
	if ! preflight_repo 42vibes-terminal; then
		block_component terminal "$PREFLIGHT_REASON" "clone:42vibes-terminal"
		return 0
	fi

	planned=
	if [ "$ALL_FLAG" = 1 ] || command -v kitty >/dev/null 2>&1 || [ -d "$HOME_DIR/.config/kitty" ]; then
		planned="$planned kitty"
	fi
	if [ "$ALL_FLAG" = 1 ] || command -v foot >/dev/null 2>&1 || [ -d "$HOME_DIR/.config/foot" ]; then
		planned="$planned foot"
	fi
	if [ "$ALL_FLAG" = 1 ] || command -v tmux >/dev/null 2>&1 || [ -f "$HOME_DIR/.tmux.conf" ]; then
		planned="$planned tmux"
	fi
	if [ "$ALL_FLAG" = 1 ] || command -v ghostty >/dev/null 2>&1 || [ -d "$HOME_DIR/.config/ghostty" ]; then
		planned="$planned ghostty"
	fi

	GNOME_PLANNED=0
	GNOME_NOTE=
	if command -v gnome-terminal >/dev/null 2>&1; then
		if [ "$HOME_OVERRIDE" = 1 ]; then
			GNOME_NOTE="gnome-terminal: --home override; apply manually"
			set_manual terminal
		elif ! command -v dconf >/dev/null 2>&1 || ! command -v gsettings >/dev/null 2>&1; then
			GNOME_NOTE="gnome-terminal: dconf/gsettings missing; apply manually"
			set_manual terminal
		elif ! gsettings list-schemas 2>/dev/null | grep -Fqx org.gnome.Terminal.ProfilesList; then
			GNOME_NOTE="gnome-terminal: schema missing; apply manually"
			set_manual terminal
		elif [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] || { [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; }; then
			GNOME_NOTE="gnome-terminal: no real graphical session; apply manually"
			set_manual terminal
		elif [ "$PREFLIGHT_PLANNED_CLONE" != 1 ] && [ ! -r "$REPO_PATH/gnome-terminal/apply.sh" ]; then
			block_component terminal "gnome-terminal apply.sh is not readable: $REPO_PATH/gnome-terminal/apply.sh" source
			return 0
		else
			GNOME_PLANNED=1
		fi
	fi

	if [ -z "$planned" ] && [ "$GNOME_PLANNED" = 0 ]; then
		set_status terminal skip "no supported terminal detected; manual snippets only"
		set_manual terminal
		return 0
	fi

	if [ "$PREFLIGHT_PLANNED_CLONE" = 1 ]; then
		ready_component terminal "will clone 42vibes-terminal; targets:${planned:- none}"
		set_manual terminal
		return 0
	fi

	for term in $planned; do
		case $term in
			kitty)
				src=$REPO_PATH/kitty/42vibes.conf
				dest=$HOME_DIR/.config/kitty/kitty.conf
				;;
			foot)
				src=$REPO_PATH/foot/42vibes.ini
				dest=$HOME_DIR/.config/foot/foot.ini
				;;
			tmux)
				src=$REPO_PATH/tmux/42vibes.conf
				dest=$HOME_DIR/.tmux.conf
				;;
			ghostty)
				src=$REPO_PATH/ghostty/42vibes.conf
				dest=$HOME_DIR/.config/ghostty/config
				;;
		esac
		if ! preflight_source_file "$src"; then
			block_component terminal "$PREFLIGHT_REASON" source
			return 0
		fi
		if ! check_target_path "$dest" append; then
			block_component terminal "$term: $PREFLIGHT_REASON" path
			return 0
		fi
	done

	if [ -n "$GNOME_NOTE" ]; then
		ready_component terminal "targets:${planned:- none}; $GNOME_NOTE"
	elif [ "$GNOME_PLANNED" = 1 ]; then
		ready_component terminal "targets:${planned:- none} gnome-terminal"
	else
		ready_component terminal "targets:${planned:- none}"
	fi
	set_manual terminal
	return 0
}

preflight_vscode() {
	editor=
	if command -v code >/dev/null 2>&1; then
		editor=code
	elif command -v codium >/dev/null 2>&1; then
		editor=codium
	fi
	if ! preflight_repo 42vibes-vscode; then
		block_component vscode "$PREFLIGHT_REASON" "clone:42vibes-vscode"
		return 0
	fi
	if [ -z "$editor" ]; then
		block_component vscode "neither code nor codium is installed" "install:code"
		return 0
	fi
	if [ "$PREFLIGHT_PLANNED_CLONE" = 1 ]; then
		ready_component vscode "will clone 42vibes-vscode; VSIX checked after clone"
		return 0
	fi
	vsix=
	for candidate in "$REPO_PATH"/42vibes-theme-*.vsix; do
		if [ -f "$candidate" ] && [ -r "$candidate" ]; then
			vsix=$candidate
			break
		fi
	done
	if [ -z "$vsix" ]; then
		block_component vscode "no readable VSIX in $REPO_PATH" "vsix"
		return 0
	fi
	ready_component vscode "$vsix via $editor"
	return 0
}

preflight_components() {
	for comp in opencode vim starship bat delta terminal vscode; do
		if ! selected "$comp"; then
			set_status "$comp" skip "not selected"
		fi
	done

	if [ "$GLOBAL_BLOCK" = 1 ]; then
		for comp in opencode vim starship bat delta terminal vscode; do
			if selected "$comp"; then
				set_status "$comp" blocked "$GLOBAL_REASON"
				set_fix "$comp" home
			fi
		done
		return 0
	fi

	if selected opencode; then preflight_opencode; fi
	if selected vim; then preflight_vim; fi
	if selected starship; then preflight_starship; fi
	if selected bat; then preflight_bat; fi
	if selected delta; then preflight_delta; fi
	if selected terminal; then preflight_terminal; fi
	if selected vscode; then preflight_vscode; fi
	return 0
}

count_preflight() {
	PF_PLANNED=0
	PF_BLOCKED=0
	PF_SKIPPED=0
	PF_MANUAL=0
	for comp in opencode vim starship bat delta terminal vscode; do
		case $(get_status "$comp") in
			ready) PF_PLANNED=$((PF_PLANNED + 1)) ;;
			blocked) PF_BLOCKED=$((PF_BLOCKED + 1)) ;;
			skip) PF_SKIPPED=$((PF_SKIPPED + 1)) ;;
		esac
		if is_manual "$comp"; then
			PF_MANUAL=$((PF_MANUAL + 1))
		fi
	done
}

print_status_table() {
	printf '\nPreflight status\n'
	printf '  %-10s %-8s %s\n' "component" "status" "details"
	for comp in opencode vim starship bat delta terminal vscode; do
		printf '  %-10s %-8s %s\n' "$comp" "$(get_status "$comp")" "$(get_note "$comp")"
	done
}

print_preflight_summary() {
	printf '\nPreflight summary\n'
	printf '  planned:  %s\n' "$PF_PLANNED"
	printf '  skipped:  %s\n' "$PF_SKIPPED"
	printf '  blocked:  %s\n' "$PF_BLOCKED"
	printf '  manual:   %s\n' "$PF_MANUAL"
}

print_remedies() {
	for comp in opencode vim starship bat delta terminal vscode; do
		if [ "$(get_status "$comp")" = blocked ]; then
			printf '\nRemedy for %s:\n  %s\n' "$comp" "$(get_note "$comp")"
			fix=$(get_fix "$comp")
			case $fix in
				install:*)
					tool_hint "${fix#install:}"
					;;
				clone:*)
					repo=${fix#clone:}
					printf '    git clone https://github.com/42vibes/%s.git "%s/%s"\n' "$repo" "$SOURCE_ROOT" "$repo"
					printf '    # or rerun with --clone\n'
					;;
				vsix)
					printf '    cd "%s/42vibes-vscode" && npx @vscode/vsce package\n' "$SOURCE_ROOT"
					;;
				source)
					printf '    Restore the source file or update the checkout.\n'
					;;
				path|cache)
					printf '    Fix the path or permissions so it stays inside %s.\n' "$HOME_DIR"
					;;
			esac
		fi
	done
	for comp in starship bat; do
		if is_manual "$comp"; then
			if [ "$comp" = starship ] && ! command -v starship >/dev/null 2>&1; then
				printf '\nOptional install for starship:\n'
				tool_hint starship
			fi
			if [ "$comp" = bat ] && ! command -v bat >/dev/null 2>&1 && ! command -v batcat >/dev/null 2>&1; then
				printf '\nOptional install for bat:\n'
				tool_hint bat
			fi
		fi
	done
}

detect_starship_init() {
	found=
	for file in "$HOME_DIR/.bashrc" "$HOME_DIR/.bash_profile" "$HOME_DIR/.profile" "$HOME_DIR/.zshrc" "$HOME_DIR/.config/fish/config.fish"; do
		if [ -r "$file" ] && grep -Fq "starship init" "$file" 2>/dev/null; then
			found="$found $file"
		fi
	done
	printf '%s' "$found"
}

print_starship_activation() {
	info "Starship activation (not written automatically):"
	info '  bash: add to ~/.bashrc:'
	info '    eval "$(starship init bash)"'
	info '  zsh:  add to ~/.zshrc:'
	info '    eval "$(starship init zsh)"'
	info "  macOS login shells: ~/.bash_profile or ~/.profile must source ~/.bashrc."
	info "  \$SHELL does not prove which shell is actually running."
	found=$(detect_starship_init)
	if [ -n "$found" ]; then
		info "  existing starship init found in:$found"
	else
		info "  no existing starship init line found in common rc files"
	fi
}

confirm() {
	[ "$ASSUME_YES" = 1 ] && return 0
	[ "$DRY_RUN" = 1 ] && return 0
	[ "$CHECK_MODE" = 1 ] && return 0
	printf '%s [y/N] ' "$1"
	answer=
	IFS= read -r answer || return 1
	case $answer in
		y|Y|yes|YES|Yes) return 0 ;;
		*) return 1 ;;
	esac
}

# ---------------------------------------------------------------------------
# Execution (only called after preflight, confirmation and home creation).

ensure_repo() {
	REPO_DIR="$SOURCE_ROOT/$1"
	REPO_PLANNED=0
	if [ -d "$REPO_DIR" ]; then
		return 0
	fi
	if [ "$DO_CLONE" = 1 ]; then
		if [ "$DRY_RUN" = 1 ] || [ "$CHECK_MODE" = 1 ]; then
			info "would clone https://github.com/42vibes/$1.git to $REPO_DIR"
			REPO_PLANNED=1
			return 0
		fi
		if ! command -v git >/dev/null 2>&1; then
			warn "git not found; cannot clone $1"
			return 1
		fi
		info "Cloning https://github.com/42vibes/$1.git"
		if git clone --depth 1 "https://github.com/42vibes/$1.git" "$REPO_DIR"; then
			return 0
		fi
		warn "clone failed for $1"
		return 1
	fi
	warn "missing checkout: $REPO_DIR"
	warn "  git clone https://github.com/42vibes/$1.git \"$REPO_DIR\""
	warn "  or rerun with --clone"
	return 1
}

ensure_parent() {
	parent=$1
	[ -d "$parent" ] && return 0
	if [ "$DRY_RUN" = 1 ]; then
		printf '  would create directory %s\n' "$parent"
		return 0
	fi
	mkdir -p "$parent"
}

backup_file() {
	path=$1
	if [ -d "$path" ] && [ ! -L "$path" ]; then
		warn "refusing to replace directory: $path"
		return 1
	fi
	if [ ! -f "$path" ] && [ ! -L "$path" ]; then
		return 0
	fi
	bak="$path.bak.$TS"
	n=1
	while [ -f "$bak" ] || [ -L "$bak" ]; do
		bak="$path.bak.$TS.$n"
		n=$((n + 1))
	done
	if [ "$DRY_RUN" = 1 ]; then
		printf '  would back up %s -> %s\n' "$path" "$bak"
		return 0
	fi
	cp -pP "$path" "$bak"
	info "backup: $bak"
}

file_contains() {
	[ -f "$1" ] || return 1
	grep -Fqx -e "$2" "$1" >/dev/null 2>&1
}

install_theme() {
	src=$1
	dest=$2
	label=$3
	if [ "$COPY_MODE" = 1 ]; then
		if [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$src" "$dest"; then
			info "$label: already up to date ($dest)"
			COUNT_UNCHANGED=$((COUNT_UNCHANGED + 1))
			LAST_CHANGED=0
			return 0
		fi
		if [ -d "$dest" ] && [ ! -L "$dest" ]; then
			warn "$label: destination is a directory, skipping: $dest"
			COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
			LAST_CHANGED=0
			return 0
		fi
		if [ "$DRY_RUN" = 1 ]; then
			if [ -f "$dest" ] || [ -L "$dest" ]; then
				backup_file "$dest"
			fi
			printf '  would copy %s -> %s\n' "$src" "$dest"
			COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
			LAST_CHANGED=1
			return 0
		fi
		ensure_parent "$(dirname "$dest")"
		backup_file "$dest"
		if [ -L "$dest" ]; then
			rm -f "$dest"
		fi
		cp "$src" "$dest"
		info "$label: installed $dest (copy)"
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		LAST_CHANGED=1
		return 0
	fi

	if [ -L "$dest" ]; then
		current=$(readlink "$dest" 2>/dev/null || true)
		if [ "$current" = "$src" ]; then
			info "$label: already linked ($dest)"
			COUNT_UNCHANGED=$((COUNT_UNCHANGED + 1))
			LAST_CHANGED=0
			return 0
		fi
	fi

	if [ -d "$dest" ] && [ ! -L "$dest" ]; then
		warn "$label: destination is a directory, skipping: $dest"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		LAST_CHANGED=0
		return 0
	fi

	if [ "$DRY_RUN" = 1 ]; then
		if [ -f "$dest" ] || [ -L "$dest" ]; then
			backup_file "$dest"
		fi
		printf '  would link %s -> %s\n' "$dest" "$src"
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		LAST_CHANGED=1
		return 0
	fi

	ensure_parent "$(dirname "$dest")"
	backup_file "$dest"
	rm -f "$dest"
	ln -s "$src" "$dest"
	info "$label: linked $dest"
	COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
	LAST_CHANGED=1
}

install_copy() {
	src=$1
	dest=$2
	label=$3
	if [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$src" "$dest"; then
		info "$label: already up to date ($dest)"
		COUNT_UNCHANGED=$((COUNT_UNCHANGED + 1))
		LAST_CHANGED=0
		return 0
	fi
	if [ -d "$dest" ] && [ ! -L "$dest" ]; then
		warn "$label: destination is a directory, skipping: $dest"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		LAST_CHANGED=0
		return 0
	fi
	if [ "$DRY_RUN" = 1 ]; then
		if [ -f "$dest" ] || [ -L "$dest" ]; then
			backup_file "$dest"
		fi
		printf '  would copy %s -> %s\n' "$src" "$dest"
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		LAST_CHANGED=1
		return 0
	fi
	ensure_parent "$(dirname "$dest")"
	backup_file "$dest"
	if [ -L "$dest" ]; then
		rm -f "$dest"
	fi
	cp "$src" "$dest"
	info "$label: installed $dest"
	COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
	LAST_CHANGED=1
}

append_managed_block() {
	file=$1
	marker=$2
	line=$3
	label=$4
	source=${5:-}

	if [ -n "$source" ] && { [ ! -f "$source" ] || [ ! -r "$source" ]; }; then
		warn "$label: source is not readable: $source"
		COUNT_FAILED=1
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		LAST_CHANGED=0
		return 0
	fi

	if file_contains "$file" "$line"; then
		info "$label: already configured in $file"
		COUNT_UNCHANGED=$((COUNT_UNCHANGED + 1))
		LAST_CHANGED=0
		return 0
	fi

	if [ -d "$file" ] && [ ! -L "$file" ]; then
		warn "$label: config path is a directory, skipping: $file"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		LAST_CHANGED=0
		return 0
	fi
	if [ -L "$file" ] && ! is_within_home "$file"; then
		warn "$label: config path resolves outside target home, skipping: $file"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		LAST_CHANGED=0
		return 0
	fi

	if [ "$DRY_RUN" = 1 ]; then
		if [ -f "$file" ] || [ -L "$file" ]; then
			backup_file "$file"
			printf '  would append to %s:\n' "$file"
		else
			printf '  would create %s with:\n' "$file"
		fi
		printf '    %s\n' "$marker"
		printf '    %s\n' "$line"
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		LAST_CHANGED=1
		return 0
	fi

	ensure_parent "$(dirname "$file")"
	if [ -f "$file" ] || [ -L "$file" ]; then
		backup_file "$file"
	fi
	if [ ! -f "$file" ]; then
		: > "$file"
	fi
	if [ -s "$file" ] && [ -n "$(tail -c 1 "$file")" ]; then
		printf '\n' >> "$file"
	fi
	printf '%s\n' "$marker" >> "$file"
	printf '%s\n' "$line" >> "$file"
	info "$label: updated $file"
	COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
	LAST_CHANGED=1
}

install_opencode() {
	if ! ensure_repo 42vibes-opencode; then
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	if [ "$REPO_PLANNED" = 1 ]; then
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		return 0
	fi
	src="$REPO_DIR/themes/42vibes.json"
	dest="$HOME/.config/opencode/themes/42vibes.json"
	if [ ! -f "$src" ]; then
		warn "opencode theme not found: $src"
		COUNT_FAILED=1
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	install_theme "$src" "$dest" "opencode theme"
	info "  Restart OpenCode completely (a /reload is not enough) to see 42vibes."
}

install_vim() {
	if ! ensure_repo 42vibes-vim; then
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	if [ "$REPO_PLANNED" = 1 ]; then
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		return 0
	fi
	src="$REPO_DIR/colors/42vibes.vim"
	if [ ! -f "$src" ]; then
		warn "vim colorscheme not found: $src"
		COUNT_FAILED=1
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	vim_default="$HOME/.vim"
	vim_xdg="$XDG_CONFIG_HOME/vim"
	if [ ! -d "$vim_default" ] && [ -d "$vim_xdg" ]; then
		dest="$vim_xdg/colors/42vibes.vim"
		install_theme "$src" "$dest" "vim colorscheme"
		info "  Vim does not load $vim_xdg by itself; add: set runtimepath^=$vim_xdg"
	else
		dest="$vim_default/colors/42vibes.vim"
		install_theme "$src" "$dest" "vim colorscheme"
	fi
	info "  Activate with: colorscheme 42vibes"
}

install_starship() {
	if ! ensure_repo 42vibes-bash; then
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	if [ "$REPO_PLANNED" = 1 ]; then
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		return 0
	fi
	src="$REPO_DIR/starship.toml"
	dest="$HOME/.config/starship.toml"
	if [ ! -f "$src" ]; then
		warn "starship.toml not found: $src"
		COUNT_FAILED=1
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	install_copy "$src" "$dest" "starship"
	if ! command -v starship >/dev/null 2>&1; then
		info "starship is not installed yet; the config is prepared but not usable"
		COUNT_MANUAL=$((COUNT_MANUAL + 1))
	fi
	if [ -n "${STARSHIP_CONFIG:-}" ]; then
		warn "STARSHIP_CONFIG is set to $STARSHIP_CONFIG; Starship ignores $dest"
	fi
}

install_bat() {
	if ! ensure_repo 42vibes-bash; then
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	if [ "$REPO_PLANNED" = 1 ]; then
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		return 0
	fi
	themes="$HOME/.config/bat/themes"
	changed=0
	for variant in 42vibes 42vibes-light; do
		src="$REPO_DIR/bat/$variant.tmTheme"
		if [ ! -f "$src" ]; then
			warn "bat theme not found: $src"
			COUNT_FAILED=1
			COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
			continue
		fi
		install_copy "$src" "$themes/$variant.tmTheme" "bat $variant"
		if [ "$LAST_CHANGED" = 1 ]; then
			changed=1
		fi
	done
	BAT_BIN=
	if command -v bat >/dev/null 2>&1; then
		BAT_BIN=bat
	elif command -v batcat >/dev/null 2>&1; then
		BAT_BIN=batcat
	fi
	if [ -z "$BAT_BIN" ]; then
		info "bat/batcat not found; after installing bat run: bat cache --build"
		COUNT_MANUAL=$((COUNT_MANUAL + 1))
		return 0
	fi
	if [ "$BAT_SKIP_CACHE" = 1 ]; then
		info "bat: cache path is not usable; run '$BAT_BIN cache --build' manually"
		COUNT_MANUAL=$((COUNT_MANUAL + 1))
		return 0
	fi
	if [ "$changed" = 1 ]; then
		if [ "$DRY_RUN" = 1 ]; then
			printf '  would run: %s cache --build\n' "$BAT_BIN"
		elif "$BAT_BIN" cache --build; then
			info "bat: theme cache rebuilt"
		else
			warn "bat cache --build failed; run it manually"
			COUNT_MANUAL=$((COUNT_MANUAL + 1))
		fi
	else
		info "bat: theme cache already up to date"
	fi
}

install_delta() {
	if ! ensure_repo 42vibes-bash; then
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	if [ "$REPO_PLANNED" = 1 ]; then
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		return 0
	fi
	src="$REPO_DIR/delta.gitconfig"
	if [ ! -f "$src" ]; then
		warn "delta.gitconfig not found: $src"
		COUNT_FAILED=1
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	if ! command -v git >/dev/null 2>&1; then
		info "git not found; add this to your git config manually:"
		info "  [include] path = $src"
		COUNT_MANUAL=$((COUNT_MANUAL + 1))
		return 0
	fi
	if ! command -v delta >/dev/null 2>&1; then
		info "delta not found; not adding the include (it sets pager/diffFilter)"
		COUNT_MANUAL=$((COUNT_MANUAL + 1))
		return 0
	fi
	if git config --global --get-all include.path 2>/dev/null | grep -Fqx -e "$src"; then
		info "delta: include.path already present ($src)"
		COUNT_UNCHANGED=$((COUNT_UNCHANGED + 1))
		return 0
	fi
	if [ "$DRY_RUN" = 1 ]; then
		if [ -f "$HOME/.gitconfig" ]; then
			backup_file "$HOME/.gitconfig"
		fi
		if [ -f "$XDG_CONFIG_HOME/git/config" ]; then
			backup_file "$XDG_CONFIG_HOME/git/config"
		fi
		if [ -n "${GIT_CONFIG_GLOBAL:-}" ] && [ "$GIT_CONFIG_GLOBAL" != "$HOME/.gitconfig" ] && [ "$GIT_CONFIG_GLOBAL" != "$XDG_CONFIG_HOME/git/config" ] && [ -f "$GIT_CONFIG_GLOBAL" ]; then
			backup_file "$GIT_CONFIG_GLOBAL"
		fi
		printf '  would run: git config --global --add include.path %s\n' "$src"
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		return 0
	fi
	if [ -f "$HOME/.gitconfig" ]; then
		backup_file "$HOME/.gitconfig"
	fi
	if [ -f "$XDG_CONFIG_HOME/git/config" ]; then
		backup_file "$XDG_CONFIG_HOME/git/config"
	fi
	if [ -n "${GIT_CONFIG_GLOBAL:-}" ] && [ "$GIT_CONFIG_GLOBAL" != "$HOME/.gitconfig" ] && [ "$GIT_CONFIG_GLOBAL" != "$XDG_CONFIG_HOME/git/config" ] && [ -f "$GIT_CONFIG_GLOBAL" ]; then
		backup_file "$GIT_CONFIG_GLOBAL"
	fi
	if git config --global --add include.path "$src"; then
		info "delta: added include.path $src"
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
	else
		warn "could not add delta include.path; add it manually"
		COUNT_FAILED=1
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
	fi
}

manual_terminal_snippets() {
	repo=$1
	info "Manual terminal integrations (not modified by this installer):"
	info "  Alacritty: add to ~/.config/alacritty/alacritty.toml:"
	info "    import = [\"$repo/alacritty/42vibes.toml\"]"
	info "  WezTerm: add to ~/.config/wezterm/wezterm.lua:"
	info "    local vibes = dofile(\"$repo/wezterm/42vibes.lua\")"
	info "    config.colors = vibes"
	info "  xfce4-terminal: close all windows, back up, then copy:"
	info "    cp ~/.config/xfce4/terminal/terminalrc ~/.config/xfce4/terminal/terminalrc.bak"
	info "    cp $repo/xfce4-terminal/terminalrc ~/.config/xfce4/terminal/terminalrc"
	info "    (xfce4-terminal >= 1.1.0 uses xfconf after the first migration; see README)"
	COUNT_MANUAL=$((COUNT_MANUAL + 1))
}

install_terminal() {
	if ! ensure_repo 42vibes-terminal; then
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	if [ "$REPO_PLANNED" = 1 ]; then
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		return 0
	fi
	repo=$REPO_DIR
	forced=0
	[ "$ALL_FLAG" = 1 ] && forced=1

	detected=0
	if command -v kitty >/dev/null 2>&1 || [ -d "$HOME/.config/kitty" ]; then
		detected=1
	fi
	if command -v foot >/dev/null 2>&1 || [ -d "$HOME/.config/foot" ]; then
		detected=1
	fi
	if command -v tmux >/dev/null 2>&1 || [ -f "$HOME/.tmux.conf" ]; then
		detected=1
	fi
	if command -v ghostty >/dev/null 2>&1 || [ -d "$HOME/.config/ghostty" ]; then
		detected=1
	fi
	if command -v gnome-terminal >/dev/null 2>&1; then
		detected=1
	fi
	if [ "$forced" = 0 ] && [ "$detected" = 0 ]; then
		info "terminal: no supported terminal detected; nothing installed"
		manual_terminal_snippets "$repo"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi

	if [ "$forced" = 1 ] || command -v kitty >/dev/null 2>&1 || [ -d "$HOME/.config/kitty" ]; then
		append_managed_block \
			"$HOME/.config/kitty/kitty.conf" \
			"# 42vibes" \
			"include $repo/kitty/42vibes.conf" \
			"kitty" \
			"$repo/kitty/42vibes.conf"
	else
		info "kitty: not detected; skipped"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
	fi

	if [ "$forced" = 1 ] || command -v foot >/dev/null 2>&1 || [ -d "$HOME/.config/foot" ]; then
		append_managed_block \
			"$HOME/.config/foot/foot.ini" \
			"# 42vibes" \
			"include=$repo/foot/42vibes.ini" \
			"foot" \
			"$repo/foot/42vibes.ini"
	else
		info "foot: not detected; skipped"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
	fi

	if [ "$forced" = 1 ] || command -v tmux >/dev/null 2>&1 || [ -f "$HOME/.tmux.conf" ]; then
		append_managed_block \
			"$HOME/.tmux.conf" \
			"# 42vibes" \
			"source-file $repo/tmux/42vibes.conf" \
			"tmux" \
			"$repo/tmux/42vibes.conf"
		info "  tmux: run 'tmux kill-server' before starting a new server."
	else
		info "tmux: not detected; skipped"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
	fi

	if [ "$forced" = 1 ] || command -v ghostty >/dev/null 2>&1 || [ -d "$HOME/.config/ghostty" ]; then
		append_managed_block \
			"$HOME/.config/ghostty/config" \
			"# 42vibes" \
			"config-file = $repo/ghostty/42vibes.conf" \
			"ghostty" \
			"$repo/ghostty/42vibes.conf"
	else
		info "ghostty: not detected; skipped"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
	fi

	if command -v gnome-terminal >/dev/null 2>&1; then
		if [ "$HOME_OVERRIDE" = 1 ]; then
			info "gnome-terminal: --home override; system-wide dconf profile not applied"
			info "  Apply manually: sh $repo/gnome-terminal/apply.sh dark"
			COUNT_MANUAL=$((COUNT_MANUAL + 1))
		elif ! command -v dconf >/dev/null 2>&1 || ! command -v gsettings >/dev/null 2>&1; then
			info "gnome-terminal: dconf/gsettings not found; apply manually:"
			info "  sh $repo/gnome-terminal/apply.sh dark"
			COUNT_MANUAL=$((COUNT_MANUAL + 1))
		elif ! gsettings list-schemas 2>/dev/null | grep -Fqx org.gnome.Terminal.ProfilesList; then
			info "gnome-terminal: schema missing; apply manually:"
			info "  sh $repo/gnome-terminal/apply.sh dark"
			COUNT_MANUAL=$((COUNT_MANUAL + 1))
		elif [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] || { [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; }; then
			info "gnome-terminal: no real graphical session; apply manually:"
			info "  sh $repo/gnome-terminal/apply.sh dark"
			COUNT_MANUAL=$((COUNT_MANUAL + 1))
		elif [ "$DRY_RUN" = 1 ]; then
			printf '  would run: sh %s/gnome-terminal/apply.sh dark\n' "$repo"
			COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		elif sh "$repo/gnome-terminal/apply.sh" dark; then
			info "gnome-terminal: dark profile applied (existing profiles kept)"
			COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		else
			warn "gnome-terminal: apply.sh failed; run it manually"
			COUNT_MANUAL=$((COUNT_MANUAL + 1))
		fi
	else
		info "gnome-terminal: not detected; skipped"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
	fi

	manual_terminal_snippets "$repo"
}

install_vscode() {
	if ! ensure_repo 42vibes-vscode; then
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	if [ "$REPO_PLANNED" = 1 ]; then
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		return 0
	fi
	repo=$REPO_DIR
	editor=
	if command -v code >/dev/null 2>&1; then
		editor=code
	elif command -v codium >/dev/null 2>&1; then
		editor=codium
	fi
	if [ -z "$editor" ]; then
		info "vscode: neither 'code' nor 'codium' found; nothing installed"
		info "  Build a VSIX with: cd $repo && npx @vscode/vsce package"
		COUNT_MANUAL=$((COUNT_MANUAL + 1))
		return 0
	fi
	vsix=
	for candidate in "$repo"/42vibes-theme-*.vsix; do
		if [ -f "$candidate" ] && [ -r "$candidate" ]; then
			vsix=$candidate
			break
		fi
	done
	if [ -z "$vsix" ]; then
		info "vscode: no readable VSIX found in $repo"
		info "  Build one with: cd $repo && npx @vscode/vsce package"
		info "  Then run: $editor --install-extension 42vibes-theme-0.1.0.vsix"
		COUNT_FAILED=1
		COUNT_MANUAL=$((COUNT_MANUAL + 1))
		return 0
	fi
	if [ "$DRY_RUN" = 1 ]; then
		printf '  would run: %s --install-extension %s\n' "$editor" "$vsix"
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		return 0
	fi
	if "$editor" --install-extension "$vsix"; then
		info "vscode: installed $vsix"
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
	else
		warn "vscode: extension installation failed"
		COUNT_FAILED=1
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
	fi
}

dispatch_component() {
	comp=$1
	st=$(get_status "$comp")
	if [ "$st" = ready ]; then
		case $comp in
			opencode) install_opencode ;;
			vim) install_vim ;;
			starship) install_starship ;;
			bat) install_bat ;;
			delta) install_delta ;;
			terminal) install_terminal ;;
			vscode) install_vscode ;;
		esac
	elif [ "$comp" = terminal ] && [ "$st" = skip ]; then
		# Still print the manual Alacritty/WezTerm/xfce snippets.
		install_terminal
	fi
}

dispatch_ready() {
	for comp in opencode vim starship bat delta terminal vscode; do
		if selected "$comp"; then
			dispatch_component "$comp"
		fi
	done
}

print_final_summary() {
	printf '\n'
	info "Summary"
	if [ "$DRY_RUN" = 1 ]; then
		printf '  planned changes:    %s\n' "$COUNT_INSTALLED"
		printf '  dry run:            nothing was written\n'
	else
		printf '  installed/updated:  %s\n' "$COUNT_INSTALLED"
	fi
	printf '  already up to date: %s\n' "$COUNT_UNCHANGED"
	printf '  skipped:            %s\n' "$COUNT_SKIPPED"
	printf '  failed:             %s\n' "$COUNT_FAILED"
	printf '  blocked:            %s\n' "$PF_BLOCKED"
	printf '  manual steps:       %s\n' "$COUNT_MANUAL"
}

# ---------------------------------------------------------------------------
# Argument parsing.

while [ $# -gt 0 ]; do
	case $1 in
		--check)
			CHECK_MODE=1
			;;
		--dry-run)
			DRY_RUN=1
			;;
		--yes|-y)
			ASSUME_YES=1
			;;
		--copy)
			COPY_MODE=1
			;;
		--clone)
			DO_CLONE=1
			;;
		--all)
			ALL_FLAG=1
			;;
		--only)
			shift
			[ $# -gt 0 ] || die "--only needs an argument"
			ONLY_SET=1
			ONLY_RAW=$1
			;;
		--only=*)
			ONLY_SET=1
			ONLY_RAW=${1#*=}
			;;
		--home)
			shift
			[ $# -gt 0 ] || die "--home needs an argument"
			HOME_DIR=$1
			HOME_OVERRIDE=1
			;;
		--home=*)
			HOME_DIR=${1#*=}
			HOME_OVERRIDE=1
			;;
		--help|-h)
			usage
			exit 0
			;;
		--)
			shift
			break
			;;
		*)
			die "unknown option: $1 (see --help)"
			;;
	esac
	shift
done

[ $# -eq 0 ] || die "unexpected argument: $1"

if [ "$ALL_FLAG" = 1 ] && [ "$ONLY_SET" = 1 ]; then
	# --only all is just a more verbose --all.
	if [ "$ONLY_RAW" != "all" ]; then
		die "use either --all or --only, not both"
	fi
fi

if [ "$ALL_FLAG" = 1 ]; then
	SELECTED=
	select_all_standard
elif [ "$ONLY_SET" = 1 ]; then
	SELECTED=
	parse_only "$ONLY_RAW"
else
	SELECTED=
	add_selected opencode
	add_selected vim
	add_selected starship
	add_selected bat
	add_selected delta
fi

[ -n "$SELECTED" ] || die "no components selected"

if [ -z "$HOME_DIR" ]; then
	[ -n "${HOME:-}" ] || die "HOME is not set; use --home <dir>"
	HOME_DIR=$HOME
else
	HOME_OVERRIDE=1
fi

case $HOME_DIR in
	/*) ;;
	*) HOME_DIR=$(pwd)/$HOME_DIR ;;
esac
if [ "$HOME_DIR" != "/" ]; then
	HOME_DIR=${HOME_DIR%/}
fi
export HOME="$HOME_DIR"

# When --home points somewhere else, do not let ambient XDG variables redirect
# writes back into the real user's home.
if [ "$HOME_OVERRIDE" = 1 ]; then
	case ${XDG_CONFIG_HOME:-} in
		"$HOME"|"$HOME"/*) ;;
		*) XDG_CONFIG_HOME="$HOME/.config" ;;
	esac
	case ${XDG_CACHE_HOME:-} in
		"$HOME"|"$HOME"/*) ;;
		*) XDG_CACHE_HOME="$HOME/.cache" ;;
	esac
	# Keep tool-specific overrides from redirecting writes out of the test home.
	unset GIT_CONFIG_GLOBAL BAT_CONFIG_DIR BAT_CACHE_PATH STARSHIP_CONFIG 2>/dev/null || true
fi
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
export XDG_CONFIG_HOME
XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
export XDG_CACHE_HOME

case $SOURCE_ROOT in
	/*) ;;
	*) SOURCE_ROOT=$(pwd)/$SOURCE_ROOT ;;
esac
if [ -d "$SOURCE_ROOT" ]; then
	SOURCE_ROOT=$(CDPATH= cd -- "$SOURCE_ROOT" && pwd -P)
fi

read_os_release

# A write run needs a confirmation source. Without a TTY, --yes is mandatory.
if [ "$DRY_RUN" = 0 ] && [ "$CHECK_MODE" = 0 ] && [ "$ASSUME_YES" != 1 ] && [ ! -t 0 ]; then
	printf 'Error: no TTY; use --yes for write runs (or --check/--dry-run).\n' >&2
	exit 2
fi

TS=$(date -u +%Y%m%dT%H%M%SZ)

info "$PROG"
info "Source root: $SOURCE_ROOT"
info "Target home: $HOME_DIR"
if [ "$CHECK_MODE" = 1 ]; then
	info "Mode: check (read-only; no clone, no cache build, no home creation)"
elif [ "$DRY_RUN" = 1 ]; then
	info "Mode: dry run (read-only; nothing will be written or cloned)"
else
	info "Mode: install"
fi
info "Components:$SELECTED"
info "No Nerd Font is required; the palette avoids Nerd Font glyphs."

CANON_HOME=$(canonical_path "$HOME_DIR" 2>/dev/null || true)
preflight_home || true
preflight_components || true
count_preflight

print_status_table
print_preflight_summary

if [ "$PF_BLOCKED" -gt 0 ] || [ "$PF_MANUAL" -gt 0 ]; then
	print_remedies
fi

if [ "$CHECK_MODE" = 1 ]; then
	if selected starship; then
		print_starship_activation
	fi
	printf '\n[42vibes] Check complete; nothing was written.\n'
	if [ "$PF_BLOCKED" -gt 0 ] || [ "$GLOBAL_BLOCK" = 1 ]; then
		exit 1
	fi
	exit 0
fi

if [ "$GLOBAL_BLOCK" = 1 ]; then
	printf '[42vibes] Error: %s\n' "$GLOBAL_REASON" >&2
	printf '  Nothing was written.\n' >&2
	exit 1
fi

if [ "$ONLY_SET" = 1 ] && [ "$ALL_FLAG" != 1 ] && [ "$PF_BLOCKED" -gt 0 ]; then
	printf '[42vibes] Error: a requested component is blocked; nothing was written.\n' >&2
	printf '  Fix the items above or rerun without --only to skip blocked components.\n' >&2
	exit 1
fi

if [ "$DRY_RUN" = 1 ]; then
	dispatch_ready
	print_final_summary
	if selected starship; then
		print_starship_activation
	fi
	if [ "$PF_BLOCKED" -gt 0 ]; then
		exit 1
	fi
	exit 0
fi

if ! confirm "Proceed with these changes?"; then
	info "Aborted; nothing was changed."
	exit 1
fi

# The target home is created only after confirmation.
if ! mkdir -p "$HOME_DIR"; then
	printf '[42vibes] Error: could not create target home: %s\n' "$HOME_DIR" >&2
	exit 1
fi

dispatch_ready
print_final_summary
if selected starship; then
	print_starship_activation
fi

if [ "$PF_BLOCKED" -gt 0 ] || [ "$COUNT_FAILED" -gt 0 ]; then
	exit 1
fi
exit 0
