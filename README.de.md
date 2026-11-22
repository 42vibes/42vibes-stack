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

## Voraussetzungen und Preflight

### Quell-Checkouts

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
den benachbarten Pfad geklont werden. `--check` und `--dry-run` klonen nie.

Ein anderer Quellordner lässt sich über
`VIBES_SOURCE_ROOT=/pfad/zu/checkouts` setzen.

### Installationsmatrix

Der Installer installiert keine Pakete und ruft nie `sudo` auf. Was fehlt,
installierst du selbst. Debian 13+ und Ubuntu 25.04+ sind die ersten
Versionen mit einem `starship`-Paket; ältere Systeme nutzen das
Install-Skript oder Homebrew.

| Werkzeug | Debian 13+ / Ubuntu 25.04+ | Anderes Linux | macOS |
| --- | --- | --- | --- |
| `starship` | `apt install starship` | `curl -sS https://starship.rs/install.sh \| sh` oder `brew install starship` | `brew install starship` |
| `bat` | `apt install bat` (Binary heißt auf Debian `batcat`) | `apt install bat` oder das Distributionspaket | `brew install bat` |
| `delta` | `apt install git-delta` | `cargo install git-delta` oder das Distributionspaket | `brew install git-delta` |
| `git` | `apt install git` | Distributionspaket | `brew install git` |

Der Installer liest `ID`, `ID_LIKE` und `VERSION_ID` aus `/etc/os-release`
und gibt den passenden Hinweis aus. Ausgeführt wird der Befehl nie.

### Preflight

Jeder Lauf, auch `--check` und `--dry-run`, beginnt mit einem
schreibfreien Preflight:

* Quell-Checkouts und Dateien müssen lesbar sein;
* jeder Ziel-, Backup- und Cachepfad wird aufgelöst und muss im Ziel-Home
  bleiben, damit nichts durch einen Symlink nach außen geschrieben wird;
* der nächste existierende Elternordner muss schreib- und suchbar sein;
* benötigte Werkzeuge werden geprüft (`git`, `delta`, `bat`/`batcat`,
  `starship`, `code`/`codium`, `dconf`/`gsettings`);
* ein lokaler Konflikt blockiert nur die Komponente; ein unbrauchbares oder
  unsicheres Ziel-Home blockiert alles.

Das Ziel-Home wird erst nach der Bestätigung angelegt. Vor jedem Schreiben
erscheint eine Zusammenfassung mit geplanten, übersprungenen, blockierten und
manuellen Punkten.

### Abhängigkeiten und Auswahl

* `delta` braucht `git` und `delta`; das Include setzt `pager` und
  `diffFilter` und wird ohne `delta` nicht geschrieben.
* `bat`/`batcat` ist für die Theme-Dateien optional; der Cache wird nur neu
  gebaut, wenn `bat` oder `batcat` vorhanden ist und sich Dateien geändert
  haben.
* `starship` darf fehlen: Die Config kann vorbereitet werden, mit dem
  Hinweis, dass sie noch nicht nutzbar ist. `--only starship` behandelt ein
  fehlendes Binary als Block.
* `vscode` braucht `code` oder `codium` und ein lesbares
  `42vibes-theme-*.vsix`.
* GNOME Terminal wird nur mit `gnome-terminal`, `dconf`, `gsettings`, einem
  vorhandenen Schema `org.gnome.Terminal.ProfilesList` und einer echten
  grafischen Sitzung angefasst; nie mit `--home`.
* Fehlende Terminalvarianten sind kein Fehler. Alacritty, WezTerm und
  xfce4-terminal bleiben immer manuelle Hinweise.

Mit `--only` bricht eine blockierte angeforderte Komponente den gesamten Lauf
vor dem ersten Schreiben ab und endet mit Exit 1. Ohne `--only` (Standard
oder `--all`) werden blockierte Komponenten übersprungen, der Rest wird
installiert, und der Lauf endet am Ende mit Exit 1.

### Starship-Aktivierung

Der Installer schreibt die Starship-Config, bearbeitet aber nie
Shell-RC-Dateien und führt kein `eval` aus. Eine Zeile selbst ergänzen:

```sh
# ~/.bashrc
eval "$(starship init bash)"
```

Für zsh in `~/.zshrc`: `eval "$(starship init zsh)"`. Unter macOS liest die
Login-Shell `~/.bash_profile` oder `~/.profile`; diese Datei muss
`~/.bashrc` einbinden. `$SHELL` zeigt nur die konfigurierte Login-Shell, nicht
die tatsächlich laufende Shell. Der Installer sucht nur per Textsuche in
üblichen RC-Dateien nach einer vorhandenen `starship init`-Zeile (ohne
Ausführung) und meldet sie.

### Keine Nerd Font nötig

Die Palette vermeidet bewusst Nerd-Font-Glyphen, daher ist kein gepatchter
Font nötig. Die READMEs der Einzelprojekte dokumentieren die genauen
Symbolentscheidungen.

### `--check` und `--dry-run`

* `--check` führt nur den Preflight aus: Status, blockierte Punkte und
  Abhilfe. Es schreibt nichts, klont nicht, baut keinen Cache und legt das
  Ziel-Home nicht an. Exit 0, wenn alles Ausgewählte bereit ist, sonst 1.
* `--dry-run` führt den Preflight aus und zeigt die geplanten Änderungen
  (dieselben `would ...`-Zeilen wie bei einer Installation), schreibt aber
  nichts, klont nichts und baut keinen Cache.

### Exit-Codes

| Code | Bedeutung |
| --- | --- |
| 0 | bereit (`--check`) oder ohne blockierte Komponenten abgeschlossen |
| 1 | blockiert, Teilerfolg oder abgebrochen |
| 2 | Aufruffehler, auch ein Schreiblauf ohne TTY und ohne `--yes` |

### Reihenfolge

1. Flags auswerten und Komponenten auswählen.
2. Schreibfreien Preflight ausführen und die Statustabelle ausgeben.
3. Zusammenfassung (geplant / übersprungen / blockiert / manuell) und
   Abhilfe ausgeben.
4. Im `--check`-Modus hier beenden.
5. Nach Bestätigung fragen (`--yes` überspringt das, `--dry-run` braucht es
   nicht).
6. Ziel-Home anlegen.
7. Bereite Komponenten schreiben und die Abschluss-Zusammenfassung ausgeben.

## Schnellstart

```sh
# Nur Status und Abhilfe; schreibt nichts und legt kein Home an
./install-all.sh --check

# Standardsatz installieren (opencode, vim, starship, bat, delta)
./install-all.sh

# Alles Sichere, inklusive kitty/foot/tmux/ghostty-Konfiguration
./install-all.sh --all --yes

# Nur anzeigen; schreibt nichts, klont nichts, legt keine Backups an
./install-all.sh --all --dry-run

# Nur Vim
./install-all.sh --only vim --yes

# Nur Terminal-Integrationen
./install-all.sh --only terminal --yes
```

Ohne `--yes` fragt der Installer einmal vor dem Schreiben nach. Ein
Schreiblauf ohne TTY braucht `--yes` (sonst Exit 2). `--check` und
`--dry-run` fragen nie und schreiben nie.

## Komponenten

| Komponente | Quelle | Ziel | Methode |
| --- | --- | --- | --- |
| `opencode` | `42vibes-opencode/themes/42vibes.json` | `~/.config/opencode/themes/42vibes.json` | Symlink (mit `--copy` als Kopie). OpenCode danach vollständig neu starten; `/reload` reicht nicht. |
| `vim` | `42vibes-vim/colors/42vibes.vim` | `~/.vim/colors/42vibes.vim` | Symlink (mit `--copy` als Kopie). Existiert `~/.vim` nicht und `$XDG_CONFIG_HOME/vim` schon, wird `$XDG_CONFIG_HOME/vim/colors/42vibes.vim` verwendet. |
| `starship` | `42vibes-bash/starship.toml` | `~/.config/starship.toml` | Kopie mit Backup. |
| `bat` | `42vibes-bash/bat/42vibes.tmTheme`, `42vibes-light.tmTheme` | `~/.config/bat/themes/` | Kopie mit Backup, danach `bat cache --build`, falls `bat` oder `batcat` verfügbar ist. |
| `delta` | `42vibes-bash/delta.gitconfig` | `git config --global include.path` | `git config --global --add include.path <pfad>`, nur wenn noch nicht enthalten. |
| `terminal` | `42vibes-terminal/` | Kitty, foot, tmux, Ghostty, GNOME Terminal | Include-Zeilen mit Marker `# 42vibes`; GNOME-Profil über `apply.sh`. Alacritty/WezTerm/xfce4-terminal sind manuell. |
| `vscode` | `42vibes-vscode/` | VS Code / VSCodium | Nur mit `--only vscode`. Braucht `code`/`codium` und ein lesbares VSIX; sonst blockiert der Preflight den Lauf mit Abhilfe. Kein npm-Install in diesem Repo. |

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

### Firefox und VS Code

Firefox-Themes werden manuell über `about:debugging#/runtime/this-firefox` →
*Temporäres Add-on laden* eingebunden (siehe `../42vibes-firefox`). Der
Installer fasst Browser-Profile nicht an. VS Code ist opt-in (`--only vscode`)
und installiert nur ein bereits vorhandenes VSIX.

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
| `--check` | Nur Preflight: Status und Abhilfe. Keine Writes, kein Klonen, kein Cache-Build, kein Home-Anlegen. |
| `--dry-run` | Preflight plus geplante Aktionen. Keine Writes, kein Klonen, kein Cache-Build, keine Backups. |
| `--yes` | Nicht nach Bestätigung fragen. Pflicht für Schreibläufe ohne TTY. |
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
* `--dry-run` und `--check` nutzen dieselben Preflight-Prüfungen, führen aber
  kein `mkdir`, `cp`, `ln`, `git config`, `bat cache` oder `apply.sh` aus. Es
  entstehen auch keine Backups. `--check` beendet nach der Statusausgabe und
  legt das Ziel-Home nie an.
* Neue Dateien werden ohne Backup angelegt, weil es nichts zu erhalten gibt.
* Ein zweiter Lauf ist für unveränderte Dateien und Includes ein No-op.
  Backups entstehen nur, wenn eine Datei wirklich ersetzt wird.

## VS Code

VS Code ist nie Teil von `--all`. Explizit aufrufen:

```sh
./install-all.sh --only vscode --yes
```

Existiert bereits eine `42vibes-theme-*.vsix` in `../42vibes-vscode` und ist
`code`/`codium` installiert, führt der Installer nach der globalen
Bestätigung `--install-extension` aus. Fehlt eines davon, blockiert der
Preflight den Lauf (Exit 1) und gibt die Abhilfe aus; installiert wird
nichts. Er baut keine Pakete und führt kein `npm install` aus. Selbst bauen:

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

`make check` führt `sh -n`, `bash -n` und `tests/check.sh` aus. Die
Testsuite läuft zusätzlich unter `dash` und `bash`, nutzt hermetische
Fake-Checkouts und einen Fake-`PATH` für die Fälle bereit, blockiert und
fehlende Binaries, prüft dass `--check` und `--dry-run` nichts schreiben,
testet schreibgeschützte Homes und Symlink-Ausbrüche, prüft die
No-TTY-Regel und führt eine echte Installation zweimal aus, um zu belegen,
dass keine Backups oder Include-Zeilen doppelt entstehen. Kein Test schreibt
in das echte `$HOME`; alle Zustände liegen in einem temporären Verzeichnis.

## Lizenz

MIT, Copyright 2026 42vibes. Siehe [LICENSE](LICENSE).
