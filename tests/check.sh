#!/bin/sh
# Read-only preflight/installer self-tests. Everything happens below a
# temporary directory; the real HOME is never touched.

set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
SCRIPT=$REPO/install-all.sh
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/42vibes-check.XXXXXX")

cleanup() {
	chmod -R u+rwX "$TMP_ROOT" 2>/dev/null || true
	rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

LAST_OUT=
FAILURES=0

pass() {
	printf 'check: ok: %s\n' "$1"
}

fail() {
	printf 'check: FAIL: %s\n' "$1" >&2
	exit 1
}

run() {
	expected=$1
	label=$2
	shift 2
	set +e
	LAST_OUT=$("$@" 2>&1)
	rc=$?
	set -e
	if [ "$rc" -ne "$expected" ]; then
		printf '%s\n' "----- output: $label -----" >&2
		printf '%s\n' "$LAST_OUT" >&2
		fail "$label: expected exit $expected, got $rc"
	fi
	pass "$label"
}

run_no_stdin() {
	expected=$1
	label=$2
	shift 2
	set +e
	LAST_OUT=$("$@" </dev/null 2>&1)
	rc=$?
	set -e
	if [ "$rc" -ne "$expected" ]; then
		printf '%s\n' "----- output: $label -----" >&2
		printf '%s\n' "$LAST_OUT" >&2
		fail "$label: expected exit $expected, got $rc"
	fi
	pass "$label"
}

assert_contains() {
	printf '%s' "$LAST_OUT" | grep -Fq -- "$1" || fail "output does not contain: $1"
}

assert_not_contains() {
	if printf '%s' "$LAST_OUT" | grep -Fq -- "$1"; then
		fail "output unexpectedly contains: $1"
	fi
}

assert_absent() {
	[ ! -e "$1" ] || fail "path should not exist: $1"
}

assert_present() {
	[ -e "$1" ] || fail "path should exist: $1"
}

assert_eq() {
	[ "$1" = "$2" ] || fail "$3: expected '$2', got '$1'"
}

count_backups() {
	find "$1" -name '*.bak.*' -print | wc -l | tr -d ' '
}

# ---------------------------------------------------------------------------
# Syntax and help.

sh -n "$SCRIPT"
pass "sh -n"
bash -n "$SCRIPT"
pass "bash -n"
run 0 "--help (sh)" sh "$SCRIPT" --help
if command -v dash >/dev/null 2>&1; then
	dash -n "$SCRIPT"
	pass "dash -n"
	run 0 "--help (dash)" dash "$SCRIPT" --help
fi
run 0 "--help (bash)" bash "$SCRIPT" --help

# ---------------------------------------------------------------------------
# Hermetic fake checkouts.

SRC=$TMP_ROOT/src
mkdir -p \
	"$SRC/42vibes-opencode/themes" \
	"$SRC/42vibes-vim/colors" \
	"$SRC/42vibes-bash/bat" \
	"$SRC/42vibes-terminal/kitty" \
	"$SRC/42vibes-terminal/foot" \
	"$SRC/42vibes-terminal/tmux" \
	"$SRC/42vibes-terminal/ghostty" \
	"$SRC/42vibes-terminal/gnome-terminal" \
	"$SRC/42vibes-vscode"

printf '%s\n' 'SOURCE-OPENCODE' > "$SRC/42vibes-opencode/themes/42vibes.json"
printf '%s\n' '" SOURCE-VIM' > "$SRC/42vibes-vim/colors/42vibes.vim"
printf '%s\n' 'palette = "42vibes"' > "$SRC/42vibes-bash/starship.toml"
printf '%s\n' '<plist>42vibes</plist>' > "$SRC/42vibes-bash/bat/42vibes.tmTheme"
printf '%s\n' '<plist>42vibes-light</plist>' > "$SRC/42vibes-bash/bat/42vibes-light.tmTheme"
printf '%s\n' '[delta]' > "$SRC/42vibes-bash/delta.gitconfig"
printf '%s\n' '# 42vibes kitty' > "$SRC/42vibes-terminal/kitty/42vibes.conf"
printf '%s\n' '# 42vibes foot' > "$SRC/42vibes-terminal/foot/42vibes.ini"
printf '%s\n' '# 42vibes tmux' > "$SRC/42vibes-terminal/tmux/42vibes.conf"
printf '%s\n' '# 42vibes ghostty' > "$SRC/42vibes-terminal/ghostty/42vibes.conf"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$SRC/42vibes-terminal/gnome-terminal/apply.sh"
printf '%s\n' 'fake-vsix' > "$SRC/42vibes-vscode/42vibes-theme-0.1.0.vsix"

# A PATH that contains the tools the script needs, but not starship, bat,
# batcat, delta, code, codium, gnome-terminal, dconf or gsettings.
BASE_BIN=$TMP_ROOT/base-bin
mkdir -p "$BASE_BIN"
for cmd in dirname basename readlink uname date mkdir rm cp ln cmp grep tail tr git cat chmod; do
	bin=$(command -v "$cmd" 2>/dev/null || true)
	if [ -n "$bin" ]; then
		ln -s "$bin" "$BASE_BIN/$cmd"
	fi
done
EMPTY_PATH=$BASE_BIN

FAKE_BIN=$TMP_ROOT/fake-bin
mkdir -p "$FAKE_BIN"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$FAKE_BIN/starship"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$FAKE_BIN/delta"
printf '%s\n' '#!/bin/sh' \
	'if [ -n "${FAKE_BAT_MARKER:-}" ]; then printf "called\n" >> "$FAKE_BAT_MARKER"; fi' \
	'exit 0' > "$FAKE_BIN/bat"
printf '%s\n' '#!/bin/sh' \
	'if [ -n "${FAKE_CODE_MARKER:-}" ]; then printf "%s\n" "$*" >> "$FAKE_CODE_MARKER"; fi' \
	'exit 0' > "$FAKE_BIN/code"
chmod +x "$FAKE_BIN"/*
FAKE_PATH=$FAKE_BIN:$EMPTY_PATH

export VIBES_SOURCE_ROOT=$SRC

# ---------------------------------------------------------------------------
# --check is read-only and distinguishes ready from blocked.

run 0 "--check ready (all, fake tools)" \
	env PATH="$FAKE_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --check --all --home "$TMP_ROOT/check-ready"
assert_contains "Preflight status"
assert_contains "planned:"
assert_absent "$TMP_ROOT/check-ready"

run 1 "--check blocked (starship missing)" \
	env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --check --only starship --home "$TMP_ROOT/check-blocked"
assert_contains "starship is not installed"
assert_absent "$TMP_ROOT/check-blocked"

run 0 "--check ready (only opencode,vim)" \
	env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --check --only opencode,vim --home "$TMP_ROOT/check-ready-small"
assert_contains "planned:"
assert_absent "$TMP_ROOT/check-ready-small"

# ---------------------------------------------------------------------------
# --dry-run never writes, clones or builds a cache.

BAT_MARKER=$TMP_ROOT/bat-marker
run 0 "--dry-run --all (fake tools)" \
	env PATH="$FAKE_PATH" VIBES_SOURCE_ROOT="$SRC" FAKE_BAT_MARKER="$BAT_MARKER" \
	"$SCRIPT" --dry-run --all --home "$TMP_ROOT/dry-home"
assert_contains "would"
assert_absent "$TMP_ROOT/dry-home"
assert_absent "$BAT_MARKER"

run 1 "--dry-run --all (missing delta)" \
	env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --dry-run --all --home "$TMP_ROOT/dry-missing"
assert_contains "blocked"
assert_absent "$TMP_ROOT/dry-missing"

DRY_EXISTING=$TMP_ROOT/dry-existing
mkdir -p "$DRY_EXISTING/.config"
printf '%s\n' 'old-config' > "$DRY_EXISTING/.config/starship.toml"
run 0 "--dry-run creates no backups" \
	env PATH="$FAKE_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --dry-run --only starship --home "$DRY_EXISTING"
assert_contains "would back up"
assert_eq "$(count_backups "$DRY_EXISTING")" "0" "dry run creates no backups"
assert_eq "$(cat "$DRY_EXISTING/.config/starship.toml")" "old-config" "dry run leaves the file unchanged"

NO_SRC=$TMP_ROOT/no-src
run 1 "--check --clone never clones" \
	env PATH="$FAKE_PATH" VIBES_SOURCE_ROOT="$NO_SRC" "$SCRIPT" --check --only opencode --clone --home "$TMP_ROOT/check-clone"
assert_contains "never clones"
assert_absent "$NO_SRC"

run 0 "--dry-run --clone never clones" \
	env PATH="$FAKE_PATH" VIBES_SOURCE_ROOT="$NO_SRC" "$SCRIPT" --dry-run --only opencode --clone --home "$TMP_ROOT/dry-clone"
assert_contains "would clone"
assert_absent "$NO_SRC"

# ---------------------------------------------------------------------------
# Missing binaries: --only blocks the whole run, --all skips and reports.

run_no_stdin 1 "--only starship blocks before writes" \
	env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --only starship --yes --home "$TMP_ROOT/missing-home"
assert_contains "starship is not installed"
assert_contains "nothing was written"
assert_absent "$TMP_ROOT/missing-home"

run_no_stdin 1 "--all skips blocked components and reports partial success" \
	env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --all --yes --home "$TMP_ROOT/partial-home"
assert_contains "delta is not installed"
assert_contains "Summary"
assert_contains "blocked:"
assert_present "$TMP_ROOT/partial-home/.config/opencode/themes/42vibes.json"
assert_present "$TMP_ROOT/partial-home/.config/starship.toml"
assert_present "$TMP_ROOT/partial-home/.config/bat/themes/42vibes.tmTheme"
assert_present "$TMP_ROOT/partial-home/.config/kitty/kitty.conf"
assert_absent "$TMP_ROOT/partial-home/.gitconfig"

run_no_stdin 1 "--only bat blocks when bat is missing" \
	env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --only bat --yes --home "$TMP_ROOT/bat-home"
assert_contains "neither bat nor batcat is installed"
assert_absent "$TMP_ROOT/bat-home"

run_no_stdin 1 "--only delta blocks when delta is missing" \
	env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --only delta --yes --home "$TMP_ROOT/delta-home"
assert_contains "delta is not installed"
assert_absent "$TMP_ROOT/delta-home"

# VS Code needs an editor and a readable VSIX.
VSCODE_MARKER=$TMP_ROOT/vscode-marker
run_no_stdin 0 "--only vscode with code and a readable VSIX" \
	env PATH="$FAKE_PATH" VIBES_SOURCE_ROOT="$SRC" FAKE_CODE_MARKER="$VSCODE_MARKER" \
	"$SCRIPT" --only vscode --yes --home "$TMP_ROOT/vscode-home"
assert_contains "vscode: installed"
assert_present "$VSCODE_MARKER"
assert_contains "42vibes-theme-0.1.0.vsix"

run_no_stdin 1 "--only vscode blocks without an editor" \
	env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --only vscode --yes --home "$TMP_ROOT/vscode-no-editor"
assert_contains "neither code nor codium is installed"
assert_absent "$TMP_ROOT/vscode-no-editor"

SRC_NO_VSIX=$TMP_ROOT/src-novsix
mkdir -p "$SRC_NO_VSIX/42vibes-vscode"
run_no_stdin 1 "--only vscode blocks without a readable VSIX" \
	env PATH="$FAKE_PATH" VIBES_SOURCE_ROOT="$SRC_NO_VSIX" "$SCRIPT" --only vscode --yes --home "$TMP_ROOT/vscode-no-vsix"
assert_contains "no readable VSIX"
assert_absent "$TMP_ROOT/vscode-no-vsix"

# ---------------------------------------------------------------------------
# Read-only target home as a non-root user.

if [ "$(id -u)" -ne 0 ]; then
	RO_HOME=$TMP_ROOT/ro-home
	mkdir -p "$RO_HOME"
	chmod 500 "$RO_HOME"
	run_no_stdin 1 "read-only home is blocked globally" \
		env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --only opencode --yes --home "$RO_HOME"
	assert_contains "not writable"
	assert_eq "$(find "$RO_HOME" -mindepth 1 -print | wc -l | tr -d ' ')" "0" "read-only home stays empty"
	chmod 700 "$RO_HOME"
else
	printf 'check: skip: read-only home test (running as root)\n'
fi

# ---------------------------------------------------------------------------
# Symlink escape must be blocked, and must not write through the link.

LINK_HOME=$TMP_ROOT/link-home
LINK_OUT=$TMP_ROOT/link-out
mkdir -p "$LINK_HOME" "$LINK_OUT"
ln -s "$LINK_OUT" "$LINK_HOME/.config"
run_no_stdin 1 "symlinked target directory outside home is blocked" \
	env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --only opencode --yes --home "$LINK_HOME"
assert_contains "outside target home"
assert_eq "$(find "$LINK_OUT" -mindepth 1 -print | wc -l | tr -d ' ')" "0" "symlink target stays empty"

APPEND_HOME=$TMP_ROOT/append-home
APPEND_OUT=$TMP_ROOT/append-out
mkdir -p "$APPEND_HOME" "$APPEND_OUT"
printf '%s\n' 'keep-me' > "$APPEND_OUT/tmux.conf"
ln -s "$APPEND_OUT/tmux.conf" "$APPEND_HOME/.tmux.conf"
run_no_stdin 1 "symlinked append target outside home is blocked" \
	env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --only terminal --yes --home "$APPEND_HOME"
assert_contains "outside target home"
assert_eq "$(cat "$APPEND_OUT/tmux.conf")" "keep-me" "append target stays unchanged"

# A replaced symlink (copy/symlink install) must not be followed either.
REPLACE_HOME=$TMP_ROOT/replace-home
REPLACE_OUT=$TMP_ROOT/replace-out
mkdir -p "$REPLACE_HOME/.config" "$REPLACE_OUT"
printf '%s\n' 'keep-secret' > "$REPLACE_OUT/secret"
ln -s "$REPLACE_OUT/secret" "$REPLACE_HOME/.config/starship.toml"
run_no_stdin 0 "replaced symlink is not followed" \
	env PATH="$FAKE_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --only starship --yes --home "$REPLACE_HOME"
assert_eq "$(cat "$REPLACE_OUT/secret")" "keep-secret" "replaced symlink target stays unchanged"
[ ! -L "$REPLACE_HOME/.config/starship.toml" ] || fail "replaced symlink target should be a regular file"

# ---------------------------------------------------------------------------
# TTY handling: --yes is mandatory for write runs without a TTY.

run_no_stdin 2 "write run without TTY and without --yes exits 2" \
	env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --only opencode --home "$TMP_ROOT/tty-home"
assert_absent "$TMP_ROOT/tty-home"

run_no_stdin 0 "write run without TTY and with --yes succeeds" \
	env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --only opencode --yes --home "$TMP_ROOT/tty-home"
assert_present "$TMP_ROOT/tty-home/.config/opencode/themes/42vibes.json"

if command -v script >/dev/null 2>&1 && script --help 2>&1 | grep -q -- '--return'; then
	WRAPPER=$TMP_ROOT/abort-wrapper.sh
	cat > "$WRAPPER" <<EOF
#!/bin/sh
export PATH="$EMPTY_PATH"
export VIBES_SOURCE_ROOT="$SRC"
exec "$SCRIPT" --only opencode --home "$TMP_ROOT/tty-abort"
EOF
	chmod +x "$WRAPPER"
	set +e
	printf 'n\n' | script -qec "$WRAPPER" /dev/null >/dev/null 2>&1
	rc=$?
	set -e
	[ "$rc" -eq 1 ] || fail "TTY abort: expected exit 1, got $rc"
	assert_absent "$TMP_ROOT/tty-abort"
	pass "TTY confirmation can abort without writes"
fi

# ---------------------------------------------------------------------------
# A second real run creates no new backups and duplicates no include lines.

IDEM_HOME=$TMP_ROOT/idem-home
mkdir -p "$IDEM_HOME/.config/kitty"
printf '%s\n' 'old-starship' > "$IDEM_HOME/.config/starship.toml"
printf '%s\n' 'existing-kitty' > "$IDEM_HOME/.config/kitty/kitty.conf"
IDEM_MARKER=$TMP_ROOT/idem-bat-marker

run_no_stdin 0 "first real run (all, fake tools)" \
	env PATH="$FAKE_PATH" VIBES_SOURCE_ROOT="$SRC" FAKE_BAT_MARKER="$IDEM_MARKER" \
	"$SCRIPT" --all --yes --home "$IDEM_HOME"
BACKUPS1=$(count_backups "$IDEM_HOME")
[ "$BACKUPS1" -ge 2 ] || fail "first run should create backups, got $BACKUPS1"
KITTY_INCLUDE="include $SRC/42vibes-terminal/kitty/42vibes.conf"
KITTY_COUNT1=$(grep -Fc -- "$KITTY_INCLUDE" "$IDEM_HOME/.config/kitty/kitty.conf")
assert_eq "$KITTY_COUNT1" "1" "kitty include appears once after first run"
DELTA_COUNT1=$(HOME="$IDEM_HOME" XDG_CONFIG_HOME="$IDEM_HOME/.config" git config --global --get-all include.path | grep -Fxc -- "$SRC/42vibes-bash/delta.gitconfig" || true)
assert_eq "$DELTA_COUNT1" "1" "delta include appears once after first run"
BAT_RUNS1=$(wc -l < "$IDEM_MARKER" | tr -d ' ')
assert_eq "$BAT_RUNS1" "1" "bat cache build runs once"

run_no_stdin 0 "second real run is a no-op" \
	env PATH="$FAKE_PATH" VIBES_SOURCE_ROOT="$SRC" FAKE_BAT_MARKER="$IDEM_MARKER" \
	"$SCRIPT" --all --yes --home "$IDEM_HOME"
BACKUPS2=$(count_backups "$IDEM_HOME")
assert_eq "$BACKUPS2" "$BACKUPS1" "no new backups on second run"
KITTY_COUNT2=$(grep -Fc -- "$KITTY_INCLUDE" "$IDEM_HOME/.config/kitty/kitty.conf")
assert_eq "$KITTY_COUNT2" "1" "kitty include is not duplicated"
DELTA_COUNT2=$(HOME="$IDEM_HOME" XDG_CONFIG_HOME="$IDEM_HOME/.config" git config --global --get-all include.path | grep -Fxc -- "$SRC/42vibes-bash/delta.gitconfig" || true)
assert_eq "$DELTA_COUNT2" "1" "delta include is not duplicated"
BAT_RUNS2=$(wc -l < "$IDEM_MARKER" | tr -d ' ')
assert_eq "$BAT_RUNS2" "1" "bat cache is not rebuilt without changes"

# ---------------------------------------------------------------------------
# --copy replaces a managed symlink instead of writing through it.

COPY_HOME=$TMP_ROOT/copy-home
run_no_stdin 0 "symlink install for --copy test" \
	env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --only opencode --yes --home "$COPY_HOME"
[ -L "$COPY_HOME/.config/opencode/themes/42vibes.json" ] || fail "expected a managed symlink"
run_no_stdin 0 "copy mode replaces the symlink safely" \
	env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$SCRIPT" --only opencode --copy --yes --home "$COPY_HOME"
[ ! -L "$COPY_HOME/.config/opencode/themes/42vibes.json" ] || fail "copy mode left a symlink"
assert_eq "$(cat "$SRC/42vibes-opencode/themes/42vibes.json")" "SOURCE-OPENCODE" "copy mode did not overwrite the source"
assert_eq "$(cat "$COPY_HOME/.config/opencode/themes/42vibes.json")" "SOURCE-OPENCODE" "copy mode wrote the theme"

# ---------------------------------------------------------------------------
# dash and bash execute the same read-only check.

DASH_BIN=$(command -v dash 2>/dev/null || true)
BASH_BIN=$(command -v bash 2>/dev/null || true)
if [ -n "$DASH_BIN" ]; then
	run 0 "dash --check" env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$DASH_BIN" "$SCRIPT" --check --only opencode,vim --home "$TMP_ROOT/dash-home"
	assert_absent "$TMP_ROOT/dash-home"
fi
if [ -n "$BASH_BIN" ]; then
	run 0 "bash --check" env PATH="$EMPTY_PATH" VIBES_SOURCE_ROOT="$SRC" "$BASH_BIN" "$SCRIPT" --check --only opencode,vim --home "$TMP_ROOT/bash-home"
	assert_absent "$TMP_ROOT/bash-home"
fi

printf 'check: all tests passed\n'
