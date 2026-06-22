# Operation Raubkopie - Schnellstart

## Voraussetzung

**Docker Desktop**, **Docker Engine** oder **Podman/Podman Desktop** ist installiert. Das Startskript versucht Docker Desktop beziehungsweise die Podman Machine bei Bedarf automatisch zu starten.
Mehr Details und Podman-Hinweise stehen in `README.md`.

## In 3 Schritten

1. Repository klonen oder dieses Paket entpacken und einen Terminal/PowerShell im Ordner öffnen.
2. Starten:
   - **macOS / Linux:** `./start.sh`
   - **Windows:** `.\start.cmd`
3. Im Browser öffnen, sobald das Skript "bereit" meldet:
   - **Challenge:** <http://localhost:8080>
   - **Helper-Portal (Hints, Abgabe, Scoreboard):** <http://localhost:8081>

Das Startskript erledigt automatisch: `.env` anlegen, ein zufälliges `CTF_SECRET` setzen, Docker/Podman best-effort starten, das Image laden und warten, bis die Dienste antworten.

## Erste Schritte in der Challenge

1. Auf <http://localhost:8081/submit.php> ein **Team registrieren** (2-40 Zeichen, nur `A-Za-z0-9_-`).
2. Hinweise gibt es unter <http://localhost:8081/hints.php> (kosten Punkte).
3. Flags abgeben unter <http://localhost:8081/submit.php>, Stand sehen unter <http://localhost:8081/scoreboard.php>.

Flags sind pro Team einzigartig. Es zählt der Lösungsweg, nicht das Kopieren fremder Flags.

Die lokale Instanz hat genau einen aktiven Spielstand. Mehrere Browser werden automatisch demselben Team zugeordnet; Hints und Flag-Abgaben zählen dadurch überall zusammen. Für einen neuen Versuch bitte komplett zurücksetzen, nicht ein zweites Team anlegen.

## Stoppen und Zurücksetzen

- Stoppen: `./stop.sh` bzw. `.\stop.cmd`
- Kompletter Reset (löscht Fortschritt und DB): den beim Start ausgegebenen Backend-Befehl verwenden, z. B. `docker compose down -v` oder `podman compose down -v`, danach neu starten.

## Troubleshooting

- **"Kein Compose-Backend gefunden" / Pull schlägt fehl:** Docker Desktop, Docker Engine oder Podman installieren/starten und sicherstellen, dass Internet verfügbar ist. Das Image ist öffentlich, ein `docker login` ist nicht nötig.
- **Port 8080 oder 8081 belegt:** In `.env` `WEB_PORT` bzw. `HELPER_PORT` auf freie Ports ändern, dann neu starten.
- **macOS/Linux meldet "Permission denied" bei `./start.sh`:** `sh ./start.sh` ausführen oder einmalig `chmod +x start.sh stop.sh`.
- **Linux meldet Docker-Rechtefehler:** Docker-Dienst starten und prüfen, ob dein User Docker nutzen darf, z. B. über die Gruppe `docker`.
- **Windows blockiert PowerShell-Skripte:** `.\start.cmd` verwenden oder manuell `powershell -ExecutionPolicy Bypass -File .\start.ps1` ausführen.
- **Seite lädt direkt nach dem Start nicht:** Die Datenbank braucht beim ersten Start ca. 30 Sekunden. Das Startskript wartet automatisch; sonst kurz neu laden.
