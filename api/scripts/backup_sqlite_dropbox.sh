#!/usr/bin/env bash
set -euo pipefail

# config
DATA_ROOT="${DATA_ROOT:-/DATA_BACKUP}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/personal-server}"
TS="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
ARCHIVE_BASENAME="DATA-${TS}.tar.gz"
ARCHIVE_PATH="${BACKUP_DIR}/${ARCHIVE_BASENAME}"
DROPBOX_PATH="${DROPBOX_PATH:-/personal-server}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "${BACKUP_DIR}"

echo "[0/4] Get short-lived access token via refresh token"
DROPBOX_ACCESS_TOKEN="$(./dropbox_get_token.sh)"

echo "[1/4] Create archive"
tar -C "${DATA_ROOT}" \
  -czf "${ARCHIVE_PATH}" \
  .

echo "[2/4] Upload file to dropbox"
# IMPORTANT: /2/files/upload is intended for files under 150MB; larger files should use upload sessions. :contentReference[oaicite:0]{index=0}
FILE_SIZE="$(stat -c%s "${ARCHIVE_PATH}")"
LIMIT="$((150 * 1024 * 1024))"

if [ "${FILE_SIZE}" -le "${LIMIT}" ]; then
  RESP="$(mktemp)"
  HTTP_CODE="$(curl -sS -o "$RESP" -w "%{http_code}" -X POST https://content.dropboxapi.com/2/files/upload \
    --header "Authorization: Bearer ${DROPBOX_ACCESS_TOKEN}" \
    --header "Dropbox-API-Arg: {\"path\": \"${DROPBOX_PATH}/${ARCHIVE_BASENAME}\", \"mode\": \"add\"}" \
    --header "Content-Type: application/octet-stream" \
    --data-binary @"${ARCHIVE_PATH}")"

  if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
    echo "Dropbox upload failed (HTTP $HTTP_CODE):"
    cat "$RESP"
    echo
    rm -f "$RESP"
    exit 1
  fi
  rm -f "$RESP"
else
  echo "Archive >150MB, need upload sessions (recommended). :contentReference[oaicite:1]{index=1}"
  echo "Implement /files/upload_session/* here."
  exit 1
fi

echo "[3/4] Cleanup local archive"
rm -f "${ARCHIVE_PATH}"

echo "[4/4] Backup completed: ${ARCHIVE_BASENAME}"