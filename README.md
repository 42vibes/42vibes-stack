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

## Requirements

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
`https://github.com/42vibes/<repo>.git` into the sibling path.

You can point the installer at another source parent with
`VIBES_SOURCE_ROOT=/path/to/checkouts`.

## Quick start

```sh
# Install the default set (opencode, vim, starship, bat, delta)
./install-all.sh

# Everything safe, including kitty/foot/tmux/ghostty config updates
./install-all.sh --all --yes

# Preview only; writes nothing, creates no backups
./install-all.sh --all --dry-run

# Only Vim
./install-all.sh --only vim --yes

# Terminal integrations only
./install-all.sh --only terminal --yes
```

Without `--yes` the installer asks once before writing. `--dry-run` never
asks and never writes.

## Components

| Component | Source | Target | Method |
| --- | --- | --- | --- |
| `opencode` | `42vibes-opencode/themes/42vibes.json` | `~/.config/opencode/themes/42vibes.json` | Symlink (copy with `--copy`). Restart OpenCode fully; `/reload` is not enough. |
| `vim` | `42vibes-vim/colors/42vibes.vim` | `~/.vim/colors/42vibes.vim` | Symlink (copy with `--copy`). If `~/.vim` does not exist and `$XDG_CONFIG_HOME/vim` does, `$XDG_CONFIG_HOME/vim/colors/42vibes.vim` is used instead. |
| `starship` | `42vibes-bash/starship.toml` | `~/.config/starship.toml` | Copy with backup. |
| `bat` | `42vibes-bash/bat/42vibes.tmTheme`, `42vibes-light.tmTheme` | `~/.config/bat/themes/` | Copy with backup, then `bat cache --build` if `bat` is on `PATH`. |
| `delta` | `42vibes-bash/delta.gitconfig` | `git config --global include.path` | `git config --global --add include.path <path>`, only if not already present. |
| `terminal` | `42vibes-terminal/` | Kitty, foot, tmux, Ghostty, GNOME Terminal | Include lines with marker `# 42vibes`; GNOME profile via `apply.sh`. Alacritty/WezTerm/xfce4-terminal are manual. |
| `vscode` | `42vibes-vscode/` | VS Code / VSCodium | Only with `--only vscode`. Installs an existing VSIX if `code`/`codium` is present; otherwise prints the `npx @vscode/vsce package` hint. No npm install in this repo. |

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
| `--dry-run` | Show every planned action, create no files and no backups. |
| `--yes` | Do not ask for confirmation. |
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
* `--dry-run` routes through the same checks but performs no `mkdir`, `cp`,
  `ln`, `git config`, `bat cache` or `apply.sh` call. It also creates no
  backups.
* New files are created without a backup, because there is nothing to
  preserve.

## VS Code

VS Code is never part of `--all`. Use it explicitly:

```sh
./install-all.sh --only vscode --yes
```

If a `42vibes-theme-*.vsix` already exists in `../42vibes-vscode` and
`code`/`codium` is installed, the installer offers to run
`--install-extension`. It does not build packages and does not run `npm
install`. To build one yourself:

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

`make check` runs `sh -n`, `bash -n`, a dry-run into a temporary home and
verifies that the dry run created nothing. No test writes to the real
`$HOME`.

## License

MIT, Copyright 2026 42vibes. See [LICENSE](LICENSE).
