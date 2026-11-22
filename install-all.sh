#!/bin/sh
# 42vibes stack installer.
#
# Installs the 42vibes color palette into existing tools without destroying
# user configuration. Every overwritten file is backed up first; include
# lines are appended at most once.
#
# POSIX sh / bash 3.2 compatible (macOS). No global installation, no network
# access unless --clone is given explicitly.

set -eu

PROG="42vibes-install"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
SOURCE_ROOT=${VIBES_SOURCE_ROOT:-$SCRIPT_DIR/..}

DRY_RUN=0
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
LAST_CHANGED=0
REPO_DIR=

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
  --dry-run            Show planned actions only; write nothing.
  --yes                Do not ask for confirmation.
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

while [ $# -gt 0 ]; do
	case $1 in
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
export HOME=$HOME_DIR

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
	unset GIT_CONFIG_GLOBAL BAT_CONFIG_DIR BAT_CACHE_PATH 2>/dev/null || true
fi
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
export XDG_CONFIG_HOME

case $SOURCE_ROOT in
	/*) ;;
	*) SOURCE_ROOT=$(pwd)/$SOURCE_ROOT ;;
esac
if [ -d "$SOURCE_ROOT" ]; then
	SOURCE_ROOT=$(CDPATH= cd -- "$SOURCE_ROOT" && pwd -P)
fi

TS=$(date -u +%Y%m%dT%H%M%SZ)

info "$PROG"
info "Source root: $SOURCE_ROOT"
info "Target home: $HOME_DIR"
if [ "$DRY_RUN" = 1 ]; then
	info "Mode: dry run (nothing will be written)"
else
	info "Mode: install"
fi
info "Components:$SELECTED"

if [ "$DRY_RUN" != 1 ]; then
	mkdir -p "$HOME_DIR"
fi

confirm() {
	[ "$ASSUME_YES" = 1 ] && return 0
	[ "$DRY_RUN" = 1 ] && return 0
	printf '%s [y/N] ' "$1"
	answer=
	IFS= read -r answer || return 1
	case $answer in
		y|Y|yes|YES|Yes) return 0 ;;
		*) return 1 ;;
	esac
}

if [ "$DRY_RUN" != 1 ] && [ "$ASSUME_YES" != 1 ]; then
	if ! confirm "Proceed with these changes?"; then
		info "Aborted; nothing was changed."
		exit 1
	fi
fi

ensure_repo() {
	REPO_DIR="$SOURCE_ROOT/$1"
	if [ -d "$REPO_DIR" ]; then
		return 0
	fi
	if [ "$DO_CLONE" = 1 ]; then
		if [ "$DRY_RUN" = 1 ]; then
			info "would clone https://github.com/42vibes/$1.git to $REPO_DIR"
			return 2
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
	if ensure_repo 42vibes-opencode; then
		:
	else
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	src="$REPO_DIR/themes/42vibes.json"
	dest="$HOME/.config/opencode/themes/42vibes.json"
	if [ ! -f "$src" ]; then
		warn "opencode theme not found: $src"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	install_theme "$src" "$dest" "opencode theme"
	info "  Restart OpenCode completely (a /reload is not enough) to see 42vibes."
}

install_vim() {
	if ensure_repo 42vibes-vim; then
		:
	else
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	src="$REPO_DIR/colors/42vibes.vim"
	if [ ! -f "$src" ]; then
		warn "vim colorscheme not found: $src"
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
	if ensure_repo 42vibes-bash; then
		:
	else
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	src="$REPO_DIR/starship.toml"
	dest="$HOME/.config/starship.toml"
	if [ ! -f "$src" ]; then
		warn "starship.toml not found: $src"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	install_copy "$src" "$dest" "starship"
	if [ -n "${STARSHIP_CONFIG:-}" ]; then
		warn "STARSHIP_CONFIG is set to $STARSHIP_CONFIG; Starship ignores $dest"
	fi
}

install_bat() {
	if ensure_repo 42vibes-bash; then
		:
	else
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	themes="$HOME/.config/bat/themes"
	changed=0
	for variant in 42vibes 42vibes-light; do
		src="$REPO_DIR/bat/$variant.tmTheme"
		if [ ! -f "$src" ]; then
			warn "bat theme not found: $src"
			COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
			continue
		fi
		install_copy "$src" "$themes/$variant.tmTheme" "bat $variant"
		if [ "$LAST_CHANGED" = 1 ]; then
			changed=1
		fi
	done
	if command -v bat >/dev/null 2>&1; then
		if [ "$changed" = 1 ]; then
			if [ "$DRY_RUN" = 1 ]; then
				printf '  would run: bat cache --build\n'
			elif bat cache --build; then
				info "bat: theme cache rebuilt"
			else
				warn "bat cache --build failed; run it manually"
				COUNT_MANUAL=$((COUNT_MANUAL + 1))
			fi
		else
			info "bat: theme cache already up to date"
		fi
	else
		info "bat not found; after installing bat run: bat cache --build"
		COUNT_MANUAL=$((COUNT_MANUAL + 1))
	fi
}

install_delta() {
	if ensure_repo 42vibes-bash; then
		:
	else
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	src="$REPO_DIR/delta.gitconfig"
	if [ ! -f "$src" ]; then
		warn "delta.gitconfig not found: $src"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		return 0
	fi
	if ! command -v git >/dev/null 2>&1; then
		info "git not found; add this to your git config manually:"
		info "  [include] path = $src"
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
	if git config --global --add include.path "$src"; then
		info "delta: added include.path $src"
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
	else
		warn "could not add delta include.path; add it manually"
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
			"kitty"
	else
		info "kitty: not detected; skipped"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
	fi

	if [ "$forced" = 1 ] || command -v foot >/dev/null 2>&1 || [ -d "$HOME/.config/foot" ]; then
		append_managed_block \
			"$HOME/.config/foot/foot.ini" \
			"# 42vibes" \
			"include=$repo/foot/42vibes.ini" \
			"foot"
	else
		info "foot: not detected; skipped"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
	fi

	if [ "$forced" = 1 ] || command -v tmux >/dev/null 2>&1 || [ -f "$HOME/.tmux.conf" ]; then
		append_managed_block \
			"$HOME/.tmux.conf" \
			"# 42vibes" \
			"source-file $repo/tmux/42vibes.conf" \
			"tmux"
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
			"ghostty"
	else
		info "ghostty: not detected; skipped"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
	fi

	if command -v gnome-terminal >/dev/null 2>&1; then
		if [ "$HOME_OVERRIDE" = 1 ]; then
			info "gnome-terminal: --home override; system-wide dconf profile not applied"
			info "  Apply manually: sh $repo/gnome-terminal/apply.sh dark"
			COUNT_MANUAL=$((COUNT_MANUAL + 1))
		elif command -v dconf >/dev/null 2>&1 && command -v gsettings >/dev/null 2>&1; then
			if [ "$DRY_RUN" = 1 ]; then
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
			info "gnome-terminal: dconf/gsettings not found; apply manually:"
			info "  sh $repo/gnome-terminal/apply.sh dark"
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
		if [ -f "$candidate" ]; then
			vsix=$candidate
			break
		fi
	done
	if [ -z "$vsix" ]; then
		info "vscode: no VSIX found in $repo"
		info "  Build one with: cd $repo && npx @vscode/vsce package"
		info "  Then run: $editor --install-extension 42vibes-theme-0.1.0.vsix"
		COUNT_MANUAL=$((COUNT_MANUAL + 1))
		return 0
	fi
	if [ "$DRY_RUN" = 1 ]; then
		printf '  would run: %s --install-extension %s\n' "$editor" "$vsix"
		COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		return 0
	fi
	if confirm "Install $vsix with $editor?"; then
		if "$editor" --install-extension "$vsix"; then
			info "vscode: installed $vsix"
			COUNT_INSTALLED=$((COUNT_INSTALLED + 1))
		else
			warn "vscode: extension installation failed"
			COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
		fi
	else
		info "vscode: skipped by user"
		COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
	fi
}

if selected opencode; then
	install_opencode
fi
if selected vim; then
	install_vim
fi
if selected starship; then
	install_starship
fi
if selected bat; then
	install_bat
fi
if selected delta; then
	install_delta
fi
if selected terminal; then
	install_terminal
fi
if selected vscode; then
	install_vscode
fi

printf '\n'
info "Summary"
printf '  installed/updated:  %s\n' "$COUNT_INSTALLED"
printf '  already up to date: %s\n' "$COUNT_UNCHANGED"
printf '  skipped:            %s\n' "$COUNT_SKIPPED"
printf '  manual steps:       %s\n' "$COUNT_MANUAL"
if [ "$DRY_RUN" = 1 ]; then
	printf '  dry run:            nothing was written\n'
fi
