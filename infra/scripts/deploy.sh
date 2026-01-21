#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/personal-server}"
REPO_URL="${REPO_URL:?missing REPO_URL}"
GITHUB_PAT="${GITHUB_PAT:?missing GITHUB_PAT}"
COMPOSE_DIR="${COMPOSE_DIR:-$DEPLOY_DIR/deploy/nginx}"

sudo cloud-init status --wait

sudo apt-get update -y
sudo apt-get install -y git

sudo mkdir -p "$DEPLOY_DIR"
sudo chown "$USER":"$USER" "$DEPLOY_DIR"

# Askpass helper (keeps token out of git remote URL)
umask 077
cat > /tmp/gh-askpass.sh <<'EOF'
#!/bin/sh
case "$1" in
*Username*) echo "x-access-token" ;;
*Password*) echo "$GITHUB_PAT" ;;
*) echo "" ;;
esac
EOF
chmod 700 /tmp/gh-askpass.sh
export GIT_ASKPASS=/tmp/gh-askpass.sh
export GIT_TERMINAL_PROMPT=0

if [ ! -d "$DEPLOY_DIR/.git" ]; then
  git clone "$REPO_URL" "$DEPLOY_DIR"
else
  (cd "$DEPLOY_DIR" && git pull --ff-only)
fi

rm -f /tmp/gh-askpass.sh
unset GIT_ASKPASS GIT_TERMINAL_PROMPT
umask 022

# Permanent permission fix for bind-mounted html
sudo chmod a+X /opt /opt/personal-server /opt/personal-server/deploy /opt/personal-server/deploy/nginx || true
sudo chmod -R a+rX "$DEPLOY_DIR/deploy/nginx/html" || true

cd "$COMPOSE_DIR"
docker compose up -d --build --remove-orphans