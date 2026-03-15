# Auto-Updater

Die Skripte im Ordner `Setup/` prüfen automatisch, ob eine neuere Version des Repositories auf GitHub verfügbar ist, und laden diese bei Bedarf herunter. Sie unterstützen sowohl Branch-Tracking als auch GitHub Releases und funktionieren mit privaten Repositories über einen Personal Access Token.

## Konfiguration

Beide Skripte verwenden dieselben Variablen am Anfang der Datei:

| Variable | Beschreibung |
| --- | --- |
| `GITHUB_OWNER` | GitHub-Benutzername oder Organisation |
| `GITHUB_REPO` | Name des Repositories |
| `GITHUB_BRANCH` | Zu verfolgender Branch (Standard: `main`) |
| `INSTALL_PATH` | Lokaler Zielpfad für die extrahierten Dateien |
| `VERSION_FILE` | Datei, die den zuletzt bekannten Commit-SHA oder Tag speichert |
| `LOG_FILE` | Pfad zur Logdatei |
| `USE_RELEASES` | `true` = neuestes Release verfolgen, `false` = Branch-Commits verfolgen |
| `GITHUB_TOKEN` | Personal Access Token (erforderlich für private Repos) |

> **Hinweis:** Ein GitHub Personal Access Token ist erforderlich. Erstelle einen unter *GitHub → Settings → Developer settings → Personal access tokens* mit mindestens dem Scope `repo` (privat) bzw. `public_repo` (öffentlich).

---

## Setup — Windows

### 1. Skripte platzieren

Kopiere `update.ps1` an den Pfad, der in `$ScriptPath` innerhalb von `setup-task.ps1` definiert ist (Standard: `C:\Tools\github-updater\update.ps1`).

### 2. Konfiguration anpassen

Öffne `update.ps1` und trage deine Werte ein:

```powershell
$GITHUB_OWNER  = "dein-benutzername"
$GITHUB_REPO   = "AutoDarts"
$GITHUB_BRANCH = "main"
$INSTALL_PATH  = "C:\Tools\MyApp"
$GITHUB_TOKEN  = "ghp_dein_token_hier"
```

### 3. Geplante Aufgabe registrieren

Führe `setup-task.ps1` einmalig als Administrator aus. Dadurch wird ein Task-Scheduler-Eintrag namens `GitHubAutoUpdater` erstellt, der `update.ps1` bei jeder Anmeldung unter dem SYSTEM-Konto ausführt.

```powershell
# Als Administrator ausführen
.\Setup\setup-task.ps1
```

Um die Aufgabe später zu entfernen:

```powershell
Unregister-ScheduledTask -TaskName "GitHubAutoUpdater" -Confirm:$false
```

### Windows-Logs

Die Logs werden in den unter `$LOG_FILE` definierten Pfad geschrieben (Standard: `$INSTALL_PATH\updater.log`).

---

## Setup — Linux

### 1. Skripte platzieren (Linux)

```bash
sudo mkdir -p /opt/github-updater
sudo cp Setup/update.sh /opt/github-updater/update.sh
sudo chmod +x /opt/github-updater/update.sh
```

### 2. Konfiguration anpassen (Linux)

Öffne `/opt/github-updater/update.sh` und trage deine Werte ein:

```bash
GITHUB_OWNER="dein-benutzername"
GITHUB_REPO="AutoDarts"
GITHUB_BRANCH="main"
INSTALL_PATH="/opt/myapp"
GITHUB_TOKEN="ghp_dein_token_hier"
```

### 3. systemd-Service installieren

```bash
sudo cp Setup/github-updater.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable github-updater.service
sudo systemctl start github-updater.service   # optional: sofort ausführen
```

Der Service wird einmalig pro Boot ausgeführt, sobald das Netzwerk verfügbar ist.

### Linux-Logs

```bash
# systemd-Journal
journalctl -u github-updater.service -f

# Logdatei
cat /var/log/github-updater.log
```

### Abhängigkeiten

`curl` und `tar` müssen installiert sein. `rsync` wird automatisch verwendet, sofern vorhanden (empfohlen für zuverlässigeres Kopieren).

---

## So funktioniert der Updater

1. Ruft die GitHub-API auf, um den neuesten Commit-SHA (oder Release-Tag bei `USE_RELEASES=true`) abzurufen.
2. Vergleicht ihn mit der lokal gespeicherten Version in `VERSION_FILE`.
3. Bei einer Abweichung wird das Repository als ZIP/Tarball heruntergeladen, entpackt und der Inhalt nach `INSTALL_PATH` kopiert.
4. Die neue Version-ID wird in `VERSION_FILE` gespeichert.
5. Alle Schritte werden mit Zeitstempel protokolliert.
