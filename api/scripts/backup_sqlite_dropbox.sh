#!/usr/bin/env bash
set -euo pipefail

# config
DB_PATH="${DB_PATH:-/data/sqlite.db}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/personal-server}"
TS="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
ARCHIVE="sqlite-${TS}.db"
DROPBOX_PATH="${DROPBOX_PATH:-/personal-server}"

mkdir -p "${BACKUP_DIR}"

echo "[0/3] Get short-lived access token via refresh token"

TOKEN_RESP="$(mktemp)"
TOKEN_HTTP_CODE="$(curl -sS -o "$TOKEN_RESP" -w "%{http_code}" \
  -u "${DROPBOX_APP_KEY}:${DROPBOX_APP_SECRET}" \
  -d "grant_type=refresh_token" \
  -d "refresh_token=${DROPBOX_REFRESH_TOKEN}" \
  https://api.dropboxapi.com/oauth2/token)"

if [ "$TOKEN_HTTP_CODE" -lt 200 ] || [ "$TOKEN_HTTP_CODE" -ge 300 ]; then
  echo "Dropbox token refresh failed (HTTP $TOKEN_HTTP_CODE):"
  cat "$TOKEN_RESP"
  echo
  rm -f "$TOKEN_RESP"
  exit 1
fi

# Parse access_token (no jq dependency)
DROPBOX_ACCESS_TOKEN="$(python3 - <<PY
import json
with open("${TOKEN_RESP}", "r", encoding="utf-8") as f:
    print(json.load(f)["access_token"])
PY
)"
rm -f "$TOKEN_RESP"

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