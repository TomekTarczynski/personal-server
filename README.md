# personal-server

A minimal “disposable VM” web service deployed on **Hetzner Cloud**:

- **Nginx** serves static HTML and reverse-proxies `/api/*` to a **FastAPI** container
- **FastAPI** provides a small **SQLite-backed KV store**
- **Terraform** provisions the VM + firewall + DNS A records and runs a remote deploy script
- **Backups** are triggered via an API endpoint and uploaded to **Dropbox**

---

## Architecture

### Containers (Docker Compose)

- `nginx` (public, port **80**)
  - Serves static files from `deploy/nginx/html/`
  - Proxies `/api/` → `http://api:8000/`

- `api` (private, port **8000** inside the Docker network)
  - FastAPI app
  - SQLite DB file at `DB_PATH=/data/sqlite.db`
  - Persists `/data` via a named Docker volume (`appdata`)
  - Includes a Dropbox backup script and `sqlite3` CLI

### Persistence

- Docker named volume: `appdata`
- DB file inside volume: `/data/sqlite.db`
- DB schema created automatically on API startup:
  - `kv(k TEXT PRIMARY KEY, v TEXT NOT NULL, updated_at TEXT NOT NULL)`

### Network / security

Firewall (Hetzner):
- SSH **22** allowed only from `var.admin_ipv4_cidr`
- HTTP **80** open to the world
- HTTPS **443** open to the world (currently unused unless you add TLS termination)

Only Nginx is exposed publicly; the API is reachable through Nginx at `/api/*`.

---

## Repository layout

```
api/                       FastAPI app + Dockerfile + backup script
  scripts/
    backup_sqlite_dropbox.sh
deploy/                    docker compose + nginx config + static HTML
infra/                     Terraform + cloud-init + deploy script
  scripts/
    deploy.sh
infra/secrets/              placeholder for local-only secrets (not used by code directly)
```

---

## Components

### API (`api/`)

#### Image build (`api/Dockerfile`)
- Base: `python:3.12-slim`
- Installs: `bash`, `curl`, `ca-certificates`, `sqlite3`
- Copies:
  - `main.py` to `/app/main.py`
  - `api/scripts/*` to `/opt/scripts/*` and makes scripts executable

#### App (`api/main.py`)
Endpoints (served behind Nginx as `/api/...`):

- `GET /api/healthz` → `{"status":"ok"}`
- `GET /api/hello` → `{"message":"hello from fastapi"}`

KV store:
- `PUT /api/kv/{key}`  
  Body:
  ```json
  { "value": { "any": "json object" } }
  ```
  Upsert by primary key.

- `GET /api/kv/{key}`  
  Returns stored JSON object + timestamp; 404 if missing.

- `DELETE /api/kv/{key}`  
  Deletes key; 404 if missing.

- `GET /api/kv`  
  Lists keys and `updated_at`.

Backups:
- `POST /api/backup`  
  Runs a backup script inside the `api` container (default: `/opt/scripts/backup_sqlite_dropbox.sh`).
  - On success returns `{ "ok": true, "message": "...", "log_tail": "..." }`
  - On failure returns HTTP 500 with `stdout`/`stderr` tail and `returncode`

Environment variables used by the API:
- `PORT` (default `8000`)
- `DB_PATH` (default `/data/sqlite.db`)
- `BACKUP_SCRIPT` (default `/opt/scripts/backup_sqlite_dropbox.sh`)
- `BACKUP_DIR` (passed through to the backup script; see below)

#### Dependencies (`api/requirements.txt`)
- `fastapi==0.115.0`
- `uvicorn[standard]==0.30.6`
- `pydantic==2.8.2`

### Backup script (`api/scripts/backup_sqlite_dropbox.sh`)

Purpose:
- Creates a consistent SQLite backup using `sqlite3 ... .backup ...`
- Uploads the backup file to Dropbox using `curl`
- Deletes the local backup file after a successful upload (Dropbox is the durable storage)

Inputs:
- `DB_PATH` (default `/data/sqlite.db`)
- `BACKUP_DIR` (default `/var/backups/personal-server`)
- Dropbox token file: `/etc/personal-server/dropbox.env` (must exist in the container)

Expected `/etc/personal-server/dropbox.env` format:
```bash
DROPBOX_TOKEN="..."
```

Dropbox destination path:
- `DROPBOX_PATH="/personal-server"`

HTTP handling:
- Treats non-2xx responses as failures and prints the Dropbox error body.

### Web + reverse proxy (`deploy/`)

#### Docker Compose (`deploy/compose.yaml`)
- `nginx`:
  - Binds host port `80:80`
  - Mounts static HTML and Nginx config read-only
- `api`:
  - Builds from `../api`
  - Sets:
    - `PORT=8000`
    - `DB_PATH=/data/sqlite.db`
    - `BACKUP_DIR=/var/backups/personal-server`
  - Mounts:
    - `appdata:/data` (persistent SQLite)
    - `/etc/personal-server/dropbox.env:/etc/personal-server/dropbox.env:ro` (Dropbox token file from VM)
  - Exposes `8000` only to other containers

Notes:
- `BACKUP_DIR` is used as temporary storage for the generated `.db` file during upload.
- The script deletes the local archive after upload, so backups are only retained in Dropbox.

#### Nginx config (`deploy/nginx/default.conf`)
- Static files served from `/usr/share/nginx/html`
- Proxies `/api/*` to the FastAPI service

#### Static UI
- `deploy/nginx/html/index.html`  
  Landing page with quick links.
- `deploy/nginx/html/kv.html`  
  GUI for:
  - GET/PUT/DELETE/LIST keys
  - BACKUP (calls `POST /api/backup`)

---

## Local development / run

From repo root:

```bash
docker compose -f deploy/compose.yaml up -d --build
```

Open:
- `http://localhost/` (static index)
- `http://localhost/api/healthz`
- `http://localhost/kv.html`

Stop containers (keep data):
```bash
docker compose -f deploy/compose.yaml down
```

Stop containers and delete data:
```bash
docker compose -f deploy/compose.yaml down -v
```

---

## Cloud deployment (Hetzner Cloud via Terraform)

### What Terraform creates (`infra/`)
- `hcloud_ssh_key.me` from your local public key path
- `hcloud_firewall.main` (22 restricted, 80/443 open)
- `hcloud_server.vm` (Ubuntu 24.04, cx23, hel1) with `cloud-init.yaml`
- DNS A records (`@` and `www`) in an existing Hetzner DNS zone (`tomekt.cloud`)
- `null_resource.deploy` that:
  - Copies `infra/scripts/deploy.sh` to `/tmp/deploy.sh`
  - Copies your local `dropbox.env` to `/tmp/dropbox.env`
  - Installs it as `/etc/personal-server/dropbox.env` (mode 600)
  - Runs `deploy.sh` on the VM, cloning/pulling the repo and running Docker Compose

### Preconditions
- Hetzner Cloud API token available to Terraform (commonly via `HCLOUD_TOKEN`)
- DNS zone `tomekt.cloud` exists in Hetzner DNS (Terraform uses `data "hcloud_zone"`)
- You have locally:
  - SSH keypair (paths passed to Terraform)
  - GitHub PAT that can read the repo
  - Dropbox token file (`dropbox.env`)

### Required Terraform variables (`infra/variables.tf`)
- `admin_ipv4_cidr` – public IPv4 CIDR allowed to SSH (e.g. `203.0.113.10/32`)
- `github_repo` – repo in `host/owner/name(.git)` form, used as `https://${github_repo}`
- `github_pat` – token for git clone/pull
- `ssh_private_key_path` – path to private key (for Terraform SSH connection)
- `ssh_public_key_path` – path to public key (for Hetzner SSH key resource)
- `dropbox_env_path` – local path to `dropbox.env` (copied to VM)

Example `infra/terraform.tfvars` (DO NOT commit secrets):
```hcl
admin_ipv4_cidr      = "203.0.113.10/32"
github_repo          = "github.com/<your-user>/personal-server.git"
github_pat           = "<fine-grained-PAT-readonly>"
ssh_private_key_path = "C:/Users/<you>/.ssh/id_ed25519"
ssh_public_key_path  = "C:/Users/<you>/.ssh/id_ed25519.pub"
dropbox_env_path     = "C:/Users/<you>/secrets/dropbox.env"
```

Deploy:
```bash
cd infra
terraform init
terraform apply
```

Outputs:
- `ipv4_address`
- `ipv6_address`

### Deployment triggers
`null_resource.deploy` runs when the server ID changes (VM recreated). If you push new code and want to redeploy to the same VM, Terraform will not re-run the deploy step unless forced.

Options:
- SSH into the VM and run the update commands (see below)
- Force re-run:
  ```bash
  cd infra
  terraform taint null_resource.deploy
  terraform apply
  ```

---

## Updating the running service on the VM

SSH in:
```bash
ssh admin@<VM_IP>
```

Update and redeploy:
```bash
cd /opt/personal-server
git pull --ff-only

cd /opt/personal-server/deploy
docker compose up -d --build --remove-orphans
```

---

## Backups

### Trigger backup via API (recommended)
From a browser:
- Open `http://<YOUR_DOMAIN_OR_IP>/kv.html`
- Click **BACKUP**

Or via curl:
```bash
curl -sS -X POST http://<YOUR_DOMAIN_OR_IP>/api/backup
```

What happens:
- `/api/backup` runs `/opt/scripts/backup_sqlite_dropbox.sh` in the `api` container
- The script creates a point-in-time SQLite backup (`sqlite3 ... .backup ...`)
- Uploads to Dropbox under `/personal-server/sqlite-<timestamp>.db`
- Deletes the local backup file after upload

### Dropbox token location
Terraform installs the token on the VM:
- `/etc/personal-server/dropbox.env`

Docker Compose mounts it into the API container at the same path (read-only).

---

## Restore (manual)

This repository does not include an automated restore endpoint. A simple manual approach:

1) Download a backup `.db` file from Dropbox to the VM, e.g.:
   - `/tmp/sqlite-restore.db`

2) Stop containers:
```bash
cd /opt/personal-server/deploy
docker compose down
```

3) Copy restore DB into the named volume (`deploy_appdata` is the common default):
```bash
docker run --rm   -v deploy_appdata:/data   -v /tmp:/restore   alpine   sh -c "cp /restore/sqlite-restore.db /data/sqlite.db"
```

4) Start again:
```bash
cd /opt/personal-server/deploy
docker compose up -d
```

If the volume name differs, list volumes:
```bash
docker volume ls | grep appdata
```

---

## Operational commands

Logs:
```bash
cd /opt/personal-server/deploy
docker compose logs -f
```

Restart:
```bash
cd /opt/personal-server/deploy
docker compose restart
```

Health:
```bash
curl -sS http://localhost/api/healthz
curl -sS http://localhost/api/hello
```

Inspect DB file in the volume:
```bash
docker run --rm -v deploy_appdata:/data alpine sh -c "ls -lh /data/sqlite.db"
```

---

## Security notes

- No TLS is configured yet (port 443 is open but unused). Add TLS termination before exposing anything sensitive.
- The KV store is unauthenticated. Anyone who can reach the server can read/write/delete keys.
- `/api/backup` is also unauthenticated and triggers a Dropbox upload. If exposed publicly, it can be abused (DoS / API quota / unwanted uploads). Restrict access before relying on it.

---

## Known quirks

- `infra/scripts/deploy.sh` has a default `COMPOSE_DIR` that does not match this repo layout (`.../deploy/nginx`), but Terraform overrides it with:
  - `COMPOSE_DIR='/opt/personal-server/deploy'`

---

## Typical extensions

- Add HTTPS (ACME/Let’s Encrypt) and redirect HTTP → HTTPS
- Add authentication/authorization for `/api/*` (or at least for `/api/backup`)
- Add rate limiting at Nginx
- Pin Docker image tags
- Add a scheduled backup (cron/systemd timer) that calls `POST /api/backup` from localhost
