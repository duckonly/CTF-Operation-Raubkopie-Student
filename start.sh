#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
DOCKER_READY_TIMEOUT_SECONDS="${DOCKER_READY_TIMEOUT_SECONDS:-120}"

docker_compose_available() {
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1
}

docker_engine_ready() {
  docker info >/dev/null 2>&1
}

wait_for_docker_engine() {
  timeout_seconds="$1"
  elapsed=0

  printf "Warte auf Docker Desktop"
  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    if docker_engine_ready; then
      echo ""
      return 0
    fi
    printf "."
    sleep 2
    elapsed=$((elapsed + 2))
  done
  echo ""
  return 1
}

start_docker_desktop_if_available() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Darwin)
      if command -v open >/dev/null 2>&1; then
        echo "Docker CLI gefunden, aber Docker Desktop antwortet noch nicht. Starte Docker Desktop ..."
        open -ga Docker >/dev/null 2>&1 || open -a Docker >/dev/null 2>&1 || return 1
        return 0
      fi
      ;;
    Linux)
      # Docker Desktop/Engine startup on Linux is distribution-specific and may
      # require privileges. Avoid sudo/system changes; fall back to Podman or a
      # clear error below.
      return 1
      ;;
  esac

  return 1
}

try_docker_compose() {
  if ! docker_compose_available; then
    return 1
  fi

  if docker_engine_ready; then
    COMPOSE_MODE="docker"
    COMPOSE_BIN="docker"
    return 0
  fi

  if start_docker_desktop_if_available && wait_for_docker_engine "$DOCKER_READY_TIMEOUT_SECONDS"; then
    COMPOSE_MODE="docker"
    COMPOSE_BIN="docker"
    return 0
  fi

  echo "Hinweis: Docker ist installiert, aber der Docker-Daemon ist nicht bereit."
  return 1
}

ensure_podman_machine() {
  if ! command -v podman >/dev/null 2>&1; then
    return 0
  fi

  # On macOS/Windows, Podman needs a VM. Start or initialize it before
  # probing `podman compose`; otherwise compose detection fails too early.
  if podman machine list >/dev/null 2>&1; then
    podman machine start >/dev/null 2>&1 || podman machine init >/dev/null 2>&1 || true
    podman machine start >/dev/null 2>&1 || true
  fi
}

resolve_compose_bin() {
  if try_docker_compose; then
    return 0
  fi

  ensure_podman_machine

  if command -v podman >/dev/null 2>&1 \
    && podman info >/dev/null 2>&1 \
    && podman compose version >/dev/null 2>&1; then
    COMPOSE_MODE="podman"
    COMPOSE_BIN="podman"
    return 0
  fi

  if command -v podman >/dev/null 2>&1 \
    && podman info >/dev/null 2>&1 \
    && command -v podman-compose >/dev/null 2>&1; then
    COMPOSE_MODE="podman-compose"
    COMPOSE_BIN="$(command -v podman-compose)"
    return 0
  fi

  echo "FEHLER: Kein Compose-Backend gefunden."
  echo "Installiere Docker Desktop oder Podman Desktop. Wenn Docker Desktop installiert ist, öffne es einmal manuell und starte dieses Skript erneut."
  exit 1
}

run_compose() {
  case "$COMPOSE_MODE" in
    docker|podman)
      "$COMPOSE_BIN" compose "$@"
      ;;
    podman-compose)
      "$COMPOSE_BIN" "$@"
      ;;
  esac
}

generate_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import secrets; print(secrets.token_hex(16))'
    return 0
  fi

  if command -v python >/dev/null 2>&1; then
    python -c 'import secrets; print(secrets.token_hex(16))'
    return 0
  fi

  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]'
    return 0
  fi

  echo "FEHLER: Konnte kein zufälliges CTF_SECRET generieren."
  exit 1
}

ensure_env_file() {
  if [ ! -f "$ENV_FILE" ]; then
    cp .env.example "$ENV_FILE"
    echo "'.env' wurde aus '.env.example' erstellt."
  fi

  current_secret="$(grep '^CTF_SECRET=' "$ENV_FILE" 2>/dev/null | head -n 1 | cut -d= -f2- || true)"
  if [ -z "$current_secret" ] || [ "$current_secret" = "ERSETZE_MICH_MIT_EINEM_ZUFAELLIGEN_GEHEIMNIS" ]; then
    new_secret="$(generate_secret)"
    awk -v value="$new_secret" '
      BEGIN { replaced = 0 }
      /^CTF_SECRET=/ { print "CTF_SECRET=" value; replaced = 1; next }
      { print }
      END { if (!replaced) print "CTF_SECRET=" value }
    ' "$ENV_FILE" > "$ENV_FILE.tmp"
    mv "$ENV_FILE.tmp" "$ENV_FILE"
    echo "CTF_SECRET wurde automatisch gesetzt."
  fi

  current_image="$(grep '^WEB_IMAGE=' "$ENV_FILE" 2>/dev/null | head -n 1 | cut -d= -f2- || true)"
  template_image="$(grep '^WEB_IMAGE=' "$SCRIPT_DIR/.env.example" 2>/dev/null | head -n 1 | cut -d= -f2- || true)"
  update_image=0
  if [ -n "$template_image" ] && [ "$current_image" != "$template_image" ]; then
    case "$current_image" in
      ""|ghcr.io/duckonly/operation-raubkopie-student:git-*|ghcr.io/duckonly/operation-raubkopie-student:latest)
        update_image=1
        ;;
    esac
  fi

  if [ "$update_image" = "1" ]; then
    awk -v value="$template_image" '
      BEGIN { replaced = 0 }
      /^WEB_IMAGE=/ { print "WEB_IMAGE=" value; replaced = 1; next }
      { print }
      END { if (!replaced) print "WEB_IMAGE=" value }
    ' "$ENV_FILE" > "$ENV_FILE.tmp"
    mv "$ENV_FILE.tmp" "$ENV_FILE"
    echo "WEB_IMAGE wurde aus .env.example übernommen."
    current_image="$template_image"
  fi

  if [ -z "$current_image" ]; then
    echo "FEHLER: WEB_IMAGE ist leer. Nutze ein exportiertes Student-Release oder setze WEB_IMAGE in .env."
    exit 1
  fi
}

cd "$SCRIPT_DIR"

resolve_compose_bin
ensure_env_file

if [ "$COMPOSE_MODE" = "podman" ] || [ "$COMPOSE_MODE" = "podman-compose" ]; then
  ensure_podman_machine
fi

echo "Lade aktuelles Challenge-Image (einmalig kann das etwas dauern)..."
if ! run_compose pull; then
  echo "Hinweis: Image-Pull nicht möglich (offline oder Registry nicht erreichbar)."
  echo "Falls ein passendes lokales Image vorhanden ist, wird es verwendet."
fi
run_compose up -d

# Ports wie Compose aufloesen: eine gesetzte Shell-Umgebungsvariable hat Vorrang
# vor .env, sonst .env, sonst der Standard. So bleiben Readiness-Check und
# ausgegebene URLs konsistent mit den tatsaechlich veroeffentlichten Ports.
web_port="${WEB_PORT:-8080}"
helper_port="${HELPER_PORT:-8081}"
if [ -f .env ]; then
  if [ -z "${WEB_PORT:-}" ]; then
    line="$(grep '^WEB_PORT=' .env || true)"
    [ -n "$line" ] && web_port="${line#WEB_PORT=}"
  fi
  if [ -z "${HELPER_PORT:-}" ]; then
    line="$(grep '^HELPER_PORT=' .env || true)"
    [ -n "$line" ] && helper_port="${line#HELPER_PORT=}"
  fi
fi

# Auf Bereitschaft warten (die Datenbank braucht beim ersten Start ~30 Sekunden).
ready=0
if command -v curl >/dev/null 2>&1; then
  printf "Starte Dienste"
  wait_i=0
  while [ "$wait_i" -lt 60 ]; do
    if curl -fsS "http://localhost:${web_port}/index.php" >/dev/null 2>&1 \
      && curl -fsS "http://localhost:${helper_port}/submit.php" >/dev/null 2>&1; then
      ready=1
      break
    fi
    printf "."
    sleep 2
    wait_i=$((wait_i + 1))
  done
  echo ""
fi

echo ""
case "$COMPOSE_MODE" in
  docker|podman)
    echo "Verwendet: $COMPOSE_BIN compose"
    logs_hint="$COMPOSE_BIN compose logs"
    ;;
  podman-compose)
    echo "Verwendet: $COMPOSE_BIN"
    logs_hint="$COMPOSE_BIN logs"
    ;;
esac
echo "Webseite: http://localhost:${web_port}"
echo "Helper-Portal: http://localhost:${helper_port}"
if [ "$ready" = "0" ] && command -v curl >/dev/null 2>&1; then
  echo "Hinweis: Die Dienste antworten noch nicht. Beim ersten Start kann die Datenbank ~30s brauchen; lade die Seite gleich neu. Logs: '$logs_hint'."
fi
echo "Stoppen mit: ./stop.sh"
