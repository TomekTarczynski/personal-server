#!/usr/bin/env bash
set -euo pipefail

TOKEN_RESP="$(mktemp)"
cleanup() { rm -f "$TOKEN_RESP" || true; }
trap cleanup EXIT

HTTP_CODE="$(curl -sS -o "$TOKEN_RESP" -w "%{http_code}" \
  -u "${DROPBOX_APP_KEY}:${DROPBOX_APP_SECRET}" \
  -d "grant_type=refresh_token" \
  -d "refresh_token=${DROPBOX_REFRESH_TOKEN}" \
  https://api.dropboxapi.com/oauth2/token)"

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
  echo "Dropbox token refresh failed (HTTP $HTTP_CODE):"
  cat "$TOKEN_RESP" >&2
  exit 1
fi

# print access_token
python3 - <<'PY' "$TOKEN_RESP"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    print(json.load(f)["access_token"])
PY