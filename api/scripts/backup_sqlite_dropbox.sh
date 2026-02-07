#!/usr/bin/env bash
set -euo pipefail

# config
ENV_FILE="/etc/personal-server/dropbox.env"
DB_PATH="${DB_PATH:-/data/sqlite.db}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/personal-server}"
TS="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
ARCHIVE="sqlite-${TS}.db"
DROPBOX_PATH="/personal-server"

# Load access token to Dropbox
source "${ENV_FILE}"

mkdir -p "${BACKUP_DIR}"

echo "[1/3] Copy DB file"

sqlite3 "${DB_PATH}" ".backup '${BACKUP_DIR}/${ARCHIVE}'"

echo "[2/3] Upload file to dropbox"

RESP="$(mktemp)"
HTTP_CODE="$(curl -sS -o "$RESP" -w "%{http_code}" -X POST https://content.dropboxapi.com/2/files/upload \
  --header "Authorization: Bearer ${DROPBOX_TOKEN}" \
  --header "Dropbox-API-Arg: {\"path\": \"${DROPBOX_PATH}/${ARCHIVE}\", \"mode\": \"add\"}" \
  --header "Content-Type: application/octet-stream" \
  --data-binary @"${BACKUP_DIR}/${ARCHIVE}")"

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
  echo "Dropbox upload failed (HTTP $HTTP_CODE):"
  cat "$RESP"
  echo
  rm -f "$RESP"
  exit 1
fi

rm -f "$RESP"
echo "[3/3] Backup completed: ${ARCHIVE}"

rm -f "${BACKUP_DIR}/${ARCHIVE}"