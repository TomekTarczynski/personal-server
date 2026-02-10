#!/usr/bin/env bash
set -euo pipefail

SECRETS_ENV="/etc/personal-server/personal-server.env"
[ -f "$SECRETS_ENV" ] || { echo "Missing secrets env: $SECRETS_ENV" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$SECRETS_ENV"
set +a

COMPOSE_FILE="${COMPOSE_FILE:-/opt/personal-server/compose.yaml}"

sudo cloud-init status --wait

docker compose -f "$COMPOSE_FILE" pull
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans