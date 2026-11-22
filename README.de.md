# 42vibes Stack-Installer

[English](README.md) · **Deutsch**

Ein sicherer Installer für die sechs 42vibes-Projekte: OpenCode, Vim,
Starship, bat, delta und die Terminal-Profile (dazu optional die
VS-Code-Erweiterung). Er installiert die Farbpalette in bestehende Tools,
sichert jede überschriebene Datei und erzeugt beim zweiten Lauf keine
doppelten Include-Zeilen.

Der Installer läuft unter Linux und macOS (`/bin/sh`, bash-3.2-kompatibel).
Er installiert nichts global und ändert nichts außerhalb des Ziel-Homes.
Netzwerkzugriff gibt es nur mit explizitem `--clone`.

## Voraussetzungen

Standardmäßig werden benachbarte Checkouts erwartet:

```text
../42vibes-opencode
../42vibes-vim
../42vibes-bash
../42vibes-terminal
../42vibes-vscode
```

Fehlt ein Checkout, gibt der Installer den passenden `git clone`-Befehl aus
und überspringt die Komponente. Automatisch geklont wird nie. Mit `--clone`
kann ein fehlender Checkout von `https://github.com/42vibes/<repo>.git` in
den benachbarten Pfad geklont werden.

Ein anderer Quellordner lässt sich über
`VIBES_SOURCE_ROOT=/pfad/zu/checkouts` setzen.

## Schnellstart

```sh
# Standardsatz installieren (opencode, vim, starship, bat, delta)
./install-all.sh

# Alles Sichere, inklusive kitty/foot/tmux/ghostty-Konfiguration
./install-all.sh --all --yes

# Nur anzeigen; schreibt nichts, legt keine Backups an
./install-all.sh --all --dry-run

# Nur Vim
./install-all.sh --only vim --yes

# Nur Terminal-Integrationen
./install-all.sh --only terminal --yes
```

Ohne `--yes` fragt der Installer einmal vor dem Schreiben nach. `--dry-run`
fragt nie und schreibt nie.

## Komponenten

| Komponente | Quelle | Ziel | Methode |
| --- | --- | --- | --- |
| `opencode` | `42vibes-opencode/themes/42vibes.json` | `~/.config/opencode/themes/42vibes.json` | Symlink (mit `--copy` als Kopie). OpenCode danach vollständig neu starten; `/reload` reicht nicht. |
| `vim` | `42vibes-vim/colors/42vibes.vim` | `~/.vim/colors/42vibes.vim` | Symlink (mit `--copy` als Kopie). Existiert `~/.vim` nicht und `$XDG_CONFIG_HOME/vim` schon, wird `$XDG_CONFIG_HOME/vim/colors/42vibes.vim` verwendet. |
| `starship` | `42vibes-bash/starship.toml` | `~/.config/starship.toml` | Kopie mit Backup. |
| `bat` | `42vibes-bash/bat/42vibes.tmTheme`, `42vibes-light.tmTheme` | `~/.config/bat/themes/` | Kopie mit Backup, danach `bat cache --build`, falls `bat` im `PATH` liegt. |
| `delta` | `42vibes-bash/delta.gitconfig` | `git config --global include.path` | `git config --global --add include.path <pfad>`, nur wenn noch nicht enthalten. |
| `terminal` | `42vibes-terminal/` | Kitty, foot, tmux, Ghostty, GNOME Terminal | Include-Zeilen mit Marker `# 42vibes`; GNOME-Profil über `apply.sh`. Alacritty/WezTerm/xfce4-terminal sind manuell. |
| `vscode` | `42vibes-vscode/` | VS Code / VSCodium | Nur mit `--only vscode`. Installiert eine vorhandene VSIX, wenn `code`/`codium` da ist; sonst Hinweis auf `npx @vscode/vsce package`. Kein npm-Install in diesem Repo. |

### Terminal-Details

| Terminal | Ziel | Verhalten |
| --- | --- | --- |
| Kitty | `~/.config/kitty/kitty.conf` | Hängt `# 42vibes` und `include <pfad>/kitty/42vibes.conf` an. |
| foot | `~/.config/foot/foot.ini` | Hängt `# 42vibes` und `include=<pfad>/foot/42vibes.ini` an. |
| tmux | `~/.tmux.conf` | Hängt `# 42vibes` und `source-file <pfad>/tmux/42vibes.conf` an. Vor dem nächsten Serverstart `tmux kill-server` ausführen. |
| Ghostty | `~/.config/ghostty/config` | Hängt `# 42vibes` und `config-file = <pfad>/ghostty/42vibes.conf` an. |
| GNOME Terminal | dconf-Profil | Führt `gnome-terminal/apply.sh dark` aus, wenn `gnome-terminal`, `dconf` und `gsettings` vorhanden sind. Bestehende Profile bleiben erhalten. |
| Alacritty | `~/.config/alacritty/alacritty.toml` | **Wird nicht geändert.** Import-Snippet siehe unten. |
| WezTerm | `~/.config/wezterm/wezterm.lua` | **Wird nicht geändert.** Lua-Snippet siehe unten. |
| xfce4-terminal | `~/.config/xfce4/terminal/terminalrc` | **Wird nicht geändert.** Migrationsrisiko; manuelle Schritte unten. |

`--only terminal` konfiguriert nur erkannte Terminals (Binary im `PATH` oder
vorhandenes Konfigurationsverzeichnis/-datei). `--all` ist der reproduzierbare
Modus „alle Include-fähigen Terminals konfigurieren“: Auch Kitty, foot, tmux
und Ghostty werden eingetragen, wenn die Programme gerade nicht im `PATH`
liegen. GNOME Terminal wird weiterhin nur angefasst, wenn es installiert ist.
Mit `--home` wird das systemweite GNOME-dconf-Profil nie geschrieben; der
Installer gibt stattdessen den manuellen `apply.sh`-Befehl aus.

### Manuelle Terminal-Schritte

Alacritty (Alacritty >= 0.13), in `~/.config/alacritty/alacritty.toml`:

```toml
import = ["/pfad/zu/42vibes-terminal/alacritty/42vibes.toml"]
```

WezTerm, in `~/.config/wezterm/wezterm.lua`:

```lua
local vibes = dofile("/pfad/zu/42vibes-terminal/wezterm/42vibes.lua")
config.colors = vibes
```

xfce4-terminal: zuerst **alle** Fenster schließen (die Datei wird beim
Beenden neu geschrieben), dann sichern und die Vorlage kopieren:

```sh
cp ~/.config/xfce4/terminal/terminalrc ~/.config/xfce4/terminal/terminalrc.bak
cp /pfad/zu/42vibes-terminal/xfce4-terminal/terminalrc \
   ~/.config/xfce4/terminal/terminalrc
```

Seit xfce4-terminal 1.1.0 liegen die Einstellungen in xfconf. Eine
vorhandene `terminalrc` wird beim ersten Start einmalig migriert und danach
nicht mehr gelesen. Nach der Migration die Farben über die GUI
(*Bearbeiten → Einstellungen → Farben*) oder `xfconf-query` setzen, während
das Terminal geschlossen ist.

Der Installer gibt diese Snippets aus, sobald die Komponente `terminal`
läuft, bearbeitet die Dateien aber nie.

## Flags

| Flag | Bedeutung |
| --- | --- |
| `--dry-run` | Jede geplante Aktion anzeigen, keine Dateien und keine Backups anlegen. |
| `--yes` | Nicht nach Bestätigung fragen. |
| `--only <liste>` | Kommagetrennte Komponenten: `opencode,vim,starship,bat,delta,terminal,vscode`. |
| `--all` | Alle Standardkomponenten inklusive `terminal`. `vscode` bleibt opt-in. |
| `--home <dir>` | Ziel-Home. Standard ist `$HOME`; gedacht für Tests. |
| `--copy` | OpenCode-Theme und Vim-Farbdatei kopieren statt verlinken. |
| `--clone` | Fehlende benachbarte Checkouts von `https://github.com/42vibes/<repo>.git` klonen. Standard: aus. |
| `--help`, `-h` | Hilfe ausgeben und mit Exit 0 beenden. |

Standardauswahl: `opencode,vim,starship,bat,delta`. `terminal` wird nur
durch `--all` oder ein explizites `--only terminal` aktiviert. `vscode` nur
durch `--only vscode`.

## Backups und Idempotenz

* Jede vorhandene Datei, die überschrieben würde, wird direkt daneben als
  `<datei>.bak.YYYYMMDDTHHMMSSZ` (UTC) gesichert. Existiert dieser Name
  bereits, wird ein numerisches Suffix ergänzt.
* Symlinks werden als Symlinks gesichert. Reguläre Dateien behalten Inhalt
  und Zeitstempel.
* Vorhandene Includes werden über ihre exakte Zeile erkannt. Ein zweiter
  Lauf meldet `already configured` / `already up to date` und schreibt
  nichts.
* `--dry-run` nutzt dieselben Prüfungen, führt aber kein `mkdir`, `cp`,
  `ln`, `git config`, `bat cache` oder `apply.sh` aus. Es entstehen auch
  keine Backups.
* Neue Dateien werden ohne Backup angelegt, weil es nichts zu erhalten gibt.

## VS Code

VS Code ist nie Teil von `--all`. Explizit aufrufen:

```sh
./install-all.sh --only vscode --yes
```

Existiert bereits eine `42vibes-theme-*.vsix` in `../42vibes-vscode` und ist
`code`/`codium` installiert, bietet der Installer
`--install-extension` an. Er baut keine Pakete und führt kein `npm install`
aus. Selbst bauen:

```sh
cd ../42vibes-vscode
npx @vscode/vsce package
```

## Deinstallation

Ein Deinstallationsskript gibt es nicht; der Installer ist bewusst manuell
umkehrbar.

1. Symlinks/Kopien aus der Komponententabelle entfernen.
2. Backups zurückschieben, zum Beispiel:

   ```sh
   mv ~/.config/kitty/kitty.conf.bak.20260101T120000Z ~/.config/kitty/kitty.conf
   ```

3. Oder den verwalteten Block aus den Konfigurationsdateien löschen:

   ```text
   # 42vibes
   include /pfad/zu/42vibes-terminal/kitty/42vibes.conf
   ```

   Derselbe Marker steht in `foot.ini`, `.tmux.conf` und der
   Ghostty-Konfiguration.
4. Delta-Include entfernen, falls noch vorhanden:

   ```sh
   git config --global --unset-all include.path /pfad/zu/42vibes-bash/delta.gitconfig
   ```

5. `~/.config/bat/themes/42vibes*.tmTheme` löschen und
   `bat cache --build` ausführen.
6. Von `apply.sh` erzeugte GNOME-Terminal-Profile liegen in dconf. Profil
   unter `/org/gnome/terminal/legacy/profiles:/:<uuid>/` und die UUID aus
   `org.gnome.Terminal.ProfilesList list` entfernen, wenn es nicht bleiben
   soll.

## Entwicklung

```sh
make check
```

`make check` führt `sh -n`, `bash -n` und einen Dry-Run in ein temporäres
Home aus und prüft, dass der Dry-Run nichts angelegt hat. Kein Test schreibt
in das echte `$HOME`.

## Lizenz

MIT, Copyright 2026 42vibes. Siehe [LICENSE](LICENSE).
