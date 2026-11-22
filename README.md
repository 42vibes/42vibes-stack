# 42vibes Stack Installer

**English** · [Deutsch](README.de.md)

One safe installer for the six 42vibes projects: OpenCode, Vim, Starship,
bat, delta and the terminal profiles (plus an optional VS Code extension).
It installs the palette into existing tools, backs up every file it
overwrites and never duplicates include lines on a second run.

The installer works on Linux and macOS (`/bin/sh`, bash 3.2 compatible). It
does not install packages globally and does not touch anything outside the
target home directory. Network access only happens when `--clone` is given
explicitly.

## Requirements and preflight

### Source checkouts

The default source locations are sibling checkouts:

```text
../42vibes-opencode
../42vibes-vim
../42vibes-bash
../42vibes-terminal
../42vibes-vscode
```

If a checkout is missing, the installer prints the exact `git clone` command
and skips that component. It never clones automatically. With `--clone` it
may clone a missing checkout from
`https://github.com/42vibes/<repo>.git` into the sibling path. `--check` and
`--dry-run` never clone.

You can point the installer at another source parent with
`VIBES_SOURCE_ROOT=/path/to/checkouts`.

### Install matrix

The installer never installs packages and never calls `sudo`. Install what
you need yourself. Debian 13+ and Ubuntu 25.04+ are the first releases with a
`starship` package; older systems use the install script or Homebrew.

| Tool | Debian 13+ / Ubuntu 25.04+ | Other Linux | macOS |
| --- | --- | --- | --- |
| `starship` | `apt install starship` | `curl -sS https://starship.rs/install.sh \| sh` or `brew install starship` | `brew install starship` |
| `bat` | `apt install bat` (binary is `batcat` on Debian) | `apt install bat` or the distro package | `brew install bat` |
| `delta` | `apt install git-delta` | `cargo install git-delta` or the distro package | `brew install git-delta` |
| `git` | `apt install git` | distro package | `brew install git` |

The installer reads `ID`, `ID_LIKE` and `VERSION_ID` from `/etc/os-release`
and prints the matching hint. It never runs the command.

### Preflight

Every run, including `--check` and `--dry-run`, starts with a read-only
preflight:

* source checkouts and files must be readable;
* every target, backup and cache path is resolved and must stay inside the
  target home, so nothing is written through a symlink that points outside;
* the nearest existing parent directory must be writable and searchable;
* required tools are checked (`git`, `delta`, `bat`/`batcat`, `starship`,
  `code`/`codium`, `dconf`/`gsettings`);
* a local conflict blocks only that component; an unusable or unsafe target
  home blocks every component.

The target home is created only after the confirmation. A summary with
planned, skipped, blocked and manual items is printed before any write.

### Dependencies and selection

* `delta` requires both `git` and `delta`; the include sets `pager` and
  `diffFilter`, so it is not written if `delta` is missing.
* `bat`/`batcat` is optional for the theme files; the cache is rebuilt only
  when `bat` or `batcat` is present and the files changed.
* `starship` may be missing: the config can be prepared, with a note that it
  is not usable yet. `--only starship` treats a missing binary as a block.
* `vscode` requires `code` or `codium` and a readable
  `42vibes-theme-*.vsix`.
* GNOME Terminal is touched only with `gnome-terminal`, `dconf`,
  `gsettings`, an existing `org.gnome.Terminal.ProfilesList` schema and a
  real graphical session; never with `--home`.
* Missing terminal variants are not an error. Alacritty, WezTerm and
  xfce4-terminal are always manual hints.

With `--only`, a blocked requested component stops the whole run before the
first write and exits 1. Without `--only` (default or `--all`), blocked
components are skipped, the rest is installed, and the run exits 1 at the end.

### Starship activation

The installer writes the Starship config but never edits shell rc files and
never runs `eval`. Add one line yourself:

```sh
# ~/.bashrc
eval "$(starship init bash)"
```

For zsh use `eval "$(starship init zsh)"` in `~/.zshrc`. On macOS the login
shell reads `~/.bash_profile` or `~/.profile`; make sure that file sources
`~/.bashrc`. `$SHELL` only shows the configured login shell, not the shell
that is actually running. The installer only searches common rc files for an
existing `starship init` line (plain text, no execution) and reports it.

### No Nerd Font required

The palette deliberately avoids Nerd Font glyphs, so no patched font is
required. The README of the individual projects documents the exact symbol
choices.

### `--check` and `--dry-run`

* `--check` runs the preflight only: status, blocked items and remedies. It
  writes nothing, does not clone, does not build caches and does not create
  the target home. Exit 0 if everything selected is ready, 1 if anything is
  blocked.
* `--dry-run` runs the preflight and prints the planned changes (the same
  `would ...` lines as an install), but writes nothing, clones nothing and
  builds no cache.

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | ready (`--check`) or completed without blocked components |
| 1 | blocked, partial success, or aborted |
| 2 | usage error, including a write run without a TTY and without `--yes` |

### Order of operations

1. Parse flags and select components.
2. Run the read-only preflight and print the status table.
3. Print the summary (planned / skipped / blocked / manual) and remedies.
4. In `--check` mode, stop here.
5. Ask for confirmation (skipped by `--yes`, not needed for `--dry-run`).
6. Create the target home.
7. Write the ready components and print the final summary.

## Quick start

```sh
# Status and remedies only; writes nothing and creates no home
./install-all.sh --check

# Install the default set (opencode, vim, starship, bat, delta)
./install-all.sh

# Everything safe, including kitty/foot/tmux/ghostty config updates
./install-all.sh --all --yes

# Preview only; writes nothing, clones nothing, creates no backups
./install-all.sh --all --dry-run

# Only Vim
./install-all.sh --only vim --yes

# Terminal integrations only
./install-all.sh --only terminal --yes
```

Without `--yes` the installer asks once before writing. A write run without a
TTY requires `--yes` (otherwise exit 2). `--check` and `--dry-run` never ask
and never write.

## Components

| Component | Source | Target | Method |
| --- | --- | --- | --- |
| `opencode` | `42vibes-opencode/themes/42vibes.json` | `~/.config/opencode/themes/42vibes.json` | Symlink (copy with `--copy`). Restart OpenCode fully; `/reload` is not enough. |
| `vim` | `42vibes-vim/colors/42vibes.vim` | `~/.vim/colors/42vibes.vim` | Symlink (copy with `--copy`). If `~/.vim` does not exist and `$XDG_CONFIG_HOME/vim` does, `$XDG_CONFIG_HOME/vim/colors/42vibes.vim` is used instead. |
| `starship` | `42vibes-bash/starship.toml` | `~/.config/starship.toml` | Copy with backup. |
| `bat` | `42vibes-bash/bat/42vibes.tmTheme`, `42vibes-light.tmTheme` | `~/.config/bat/themes/` | Copy with backup, then `bat cache --build` if `bat` or `batcat` is available. |
| `delta` | `42vibes-bash/delta.gitconfig` | `git config --global include.path` | `git config --global --add include.path <path>`, only if not already present. |
| `terminal` | `42vibes-terminal/` | Kitty, foot, tmux, Ghostty, GNOME Terminal | Include lines with marker `# 42vibes`; GNOME profile via `apply.sh`. Alacritty/WezTerm/xfce4-terminal are manual. |
| `vscode` | `42vibes-vscode/` | VS Code / VSCodium | Only with `--only vscode`. Requires `code`/`codium` and a readable VSIX; otherwise the preflight blocks the run with a remedy. No npm install in this repo. |

### Terminal details

| Terminal | Target | Behavior |
| --- | --- | --- |
| Kitty | `~/.config/kitty/kitty.conf` | Appends `# 42vibes` and `include <path>/kitty/42vibes.conf`. |
| foot | `~/.config/foot/foot.ini` | Appends `# 42vibes` and `include=<path>/foot/42vibes.ini`. |
| tmux | `~/.tmux.conf` | Appends `# 42vibes` and `source-file <path>/tmux/42vibes.conf`. Run `tmux kill-server` before the next server start. |
| Ghostty | `~/.config/ghostty/config` | Appends `# 42vibes` and `config-file = <path>/ghostty/42vibes.conf`. |
| GNOME Terminal | dconf profile | Runs `gnome-terminal/apply.sh dark` when `gnome-terminal`, `dconf` and `gsettings` are available. Existing profiles are kept. |
| Alacritty | `~/.config/alacritty/alacritty.toml` | **Not modified.** Import snippet below. |
| WezTerm | `~/.config/wezterm/wezterm.lua` | **Not modified.** Lua snippet below. |
| xfce4-terminal | `~/.config/xfce4/terminal/terminalrc` | **Not modified.** Migration risk; manual steps below. |

`--only terminal` configures only terminals that are detected (binary on
`PATH` or an existing config directory/file). `--all` is the reproducible
"configure all include-based terminals" mode: it also writes the Kitty, foot,
tmux and Ghostty includes when those programs are not currently on `PATH`.
GNOME Terminal is still only touched when it is installed. With `--home`,
the system-wide GNOME dconf profile is never written; the installer prints
the manual `apply.sh` command instead.

### Firefox and VS Code

Firefox themes are loaded manually through `about:debugging#/runtime/this-firefox`
→ *Load Temporary Add-on* (see `../42vibes-firefox`). The installer does not
touch browser profiles. VS Code is opt-in (`--only vscode`) and only installs an
existing VSIX.

### Manual terminal steps

Alacritty (Alacritty >= 0.13), in `~/.config/alacritty/alacritty.toml`:

```toml
import = ["/path/to/42vibes-terminal/alacritty/42vibes.toml"]
```

WezTerm, in `~/.config/wezterm/wezterm.lua`:

```lua
local vibes = dofile("/path/to/42vibes-terminal/wezterm/42vibes.lua")
config.colors = vibes
```

xfce4-terminal: close **all** windows first (the file is rewritten on exit),
then back up and copy the template:

```sh
cp ~/.config/xfce4/terminal/terminalrc ~/.config/xfce4/terminal/terminalrc.bak
cp /path/to/42vibes-terminal/xfce4-terminal/terminalrc \
   ~/.config/xfce4/terminal/terminalrc
```

Since xfce4-terminal 1.1.0 settings live in xfconf. An existing
`terminalrc` is migrated once on first start and is not read again
afterwards. After that migration, set the colors through the GUI
(*Edit → Preferences → Colors*) or `xfconf-query`, with the terminal closed.

The installer prints these snippets whenever the `terminal` component runs,
but never edits those files.

## Flags

| Flag | Meaning |
| --- | --- |
| `--check` | Preflight only: status and remedies. No writes, clone, cache build or home creation. |
| `--dry-run` | Preflight plus planned actions. No writes, clone, cache build or backups. |
| `--yes` | Do not ask for confirmation. Mandatory for write runs without a TTY. |
| `--only <list>` | Comma-separated components: `opencode,vim,starship,bat,delta,terminal,vscode`. |
| `--all` | All standard components including `terminal`. `vscode` remains opt-in. |
| `--home <dir>` | Target home directory. Defaults to `$HOME`; intended for tests. |
| `--copy` | Copy the OpenCode theme and Vim colorscheme instead of symlinking them. |
| `--clone` | Clone missing sibling checkouts from `https://github.com/42vibes/<repo>.git`. Off by default. |
| `--help`, `-h` | Print usage and exit 0. |

Default selection: `opencode,vim,starship,bat,delta`. `terminal` is only
enabled by `--all` or an explicit `--only terminal`. `vscode` is only enabled
by `--only vscode`.

## Backups and idempotence

* Every existing file that would be overwritten is backed up next to itself
  as `<file>.bak.YYYYMMDDTHHMMSSZ` (UTC). If that name already exists, a
  numeric suffix is added.
* Symlinks are backed up as symlinks. Regular files keep their content and
  timestamps.
* Existing includes are detected by their exact line. A second run prints
  `already configured` / `already up to date` and writes nothing.
* `--dry-run` and `--check` route through the same preflight but perform no
  `mkdir`, `cp`, `ln`, `git config`, `bat cache` or `apply.sh` call. They also
  create no backups. `--check` stops after the status output and never
  creates the target home.
* New files are created without a backup, because there is nothing to
  preserve.
* A second run is a no-op for unchanged files and includes. Backups are only
  created when a file is actually replaced.

## VS Code

VS Code is never part of `--all`. Use it explicitly:

```sh
./install-all.sh --only vscode --yes
```

If a `42vibes-theme-*.vsix` already exists in `../42vibes-vscode` and
`code`/`codium` is installed, the installer runs `--install-extension` after
the global confirmation. If either is missing, the preflight blocks the run
(exit 1) and prints the remedy; nothing is installed. It does not build
packages and does not run `npm install`. To build one yourself:

```sh
cd ../42vibes-vscode
npx @vscode/vsce package
```

## Uninstall

There is no uninstall script; the installer is intentionally reversible by
hand.

1. Remove the symlinks/copied files listed in the component table.
2. Restore backups by moving them back, for example:

   ```sh
   mv ~/.config/kitty/kitty.conf.bak.20260101T120000Z ~/.config/kitty/kitty.conf
   ```

3. Or delete the managed block from config files:

   ```text
   # 42vibes
   include /path/to/42vibes-terminal/kitty/42vibes.conf
   ```

   The same marker is used in `foot.ini`, `.tmux.conf` and the Ghostty
   config.
4. Remove the delta include if it is still present:

   ```sh
   git config --global --unset-all include.path /path/to/42vibes-bash/delta.gitconfig
   ```

5. Remove `~/.config/bat/themes/42vibes*.tmTheme` and run
   `bat cache --build`.
6. GNOME Terminal profiles created by `apply.sh` live in dconf. Remove the
   profile under
   `/org/gnome/terminal/legacy/profiles:/:<uuid>/` and its UUID from
   `org.gnome.Terminal.ProfilesList list` if you no longer want it.

## Development

```sh
make check
```

`make check` runs `sh -n`, `bash -n` and `tests/check.sh`. The test suite also
runs under `dash` and `bash`, uses hermetic fake checkouts and a fake `PATH`
to cover ready, blocked and missing-binary cases, verifies that `--check` and
`--dry-run` write nothing, checks read-only homes and symlink escapes, tests
the no-TTY rule, and runs a real install twice to prove that no backups or
include lines are duplicated. No test writes to the real `$HOME`; all state
lives in a temporary directory.

## License

MIT, Copyright 2026 42vibes. See [LICENSE](LICENSE).
