#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

ensure_podman_machine() {
  if ! command -v podman >/dev/null 2>&1; then
    return 0
  fi

  if podman machine list >/dev/null 2>&1; then
    podman machine start >/dev/null 2>&1 || true
  fi
}

if command -v docker >/dev/null 2>&1 \
  && docker compose version >/dev/null 2>&1 \
  && docker info >/dev/null 2>&1; then
  COMPOSE_MODE="docker"
  COMPOSE_BIN="docker"
else
  ensure_podman_machine

  if command -v podman >/dev/null 2>&1 \
    && podman info >/dev/null 2>&1 \
    && podman compose version >/dev/null 2>&1; then
    COMPOSE_MODE="podman"
    COMPOSE_BIN="podman"
  elif command -v podman >/dev/null 2>&1 \
    && podman info >/dev/null 2>&1 \
    && command -v podman-compose >/dev/null 2>&1; then
    COMPOSE_MODE="podman-compose"
    COMPOSE_BIN="$(command -v podman-compose)"
  else
    echo "FEHLER: Kein Compose-Backend gefunden."
    exit 1
  fi
fi

cd "$SCRIPT_DIR"
case "$COMPOSE_MODE" in
  docker|podman)
    "$COMPOSE_BIN" compose down
    ;;
  podman-compose)
    "$COMPOSE_BIN" down
    ;;
esac
echo "Challenge gestoppt."
