#!/usr/bin/env bash
set -euo pipefail

# config
ENV_FILE="/etc/personal-server/dropbox.env"
VOLUME_NAME="deploy_appdata"
BACKUP_DIR="/var/backups/personal-server"
DB_FILE="sqlite.db"
TS="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
ARCHIVE="sqlite-${TS}.db"
DROPBOX_PATH="/personal-server"

# Load access token to Dropbox
source "${ENV_FILE}"

mkdir -p "${BACKUP_DIR}"

echo "[1/3] Export db file from Docker volume"

docker run --rm \
  -v "${VOLUME_NAME}:/data:ro" \
  -v "${BACKUP_DIR}:/backup" \
  alpine \
  sh -c "cp /data/${DB_FILE} /backup/${ARCHIVE}"

echo "[2/3] Upload file to dropbox"

curl -sS -X POST https://content.dropboxapi.com/2/files/upload \
  --header "Authorization: Bearer ${DROPBOX_TOKEN}" \
  --header "Dropbox-API-Arg: {\"path\": \"${DROPBOX_PATH}/${ARCHIVE}\", \"mode\": \"add\"}" \
  --header "Content-Type: application/octet-stream" \
  --data-binary @"${BACKUP_DIR}/${ARCHIVE}" \
  > /dev/null

echo "[3/3] Backup completed: ${ARCHIVE}"