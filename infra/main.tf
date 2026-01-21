terraform {
  required_version = ">= 1.5"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.47"
    }
  }
}

provider "hcloud" {}

resource "hcloud_ssh_key" "me" {
  name       = "personal-server-key"
  public_key = file(var.ssh_public_key_path)
}

resource "hcloud_server" "vm" {
  name        = "personal-server"
  image       = "ubuntu-24.04"
  server_type = "cx23"
  location    = "hel1"
  ssh_keys    = [hcloud_ssh_key.me.id]

  firewall_ids = [hcloud_firewall.main.id]

  user_data = file("${path.module}/cloud-init.yaml")

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
}

resource "null_resource" "deploy" {
  depends_on = [hcloud_server.vm]

  triggers = {
    server_id = hcloud_server.vm.id
  }

  connection {
    type        = "ssh"
    host        = hcloud_server.vm.ipv4_address
    user        = "admin"
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "set -eu",
      "sudo cloud-init status --wait",

      "sudo apt-get update -y",
      "sudo apt-get install -y git",

      "DEPLOY_DIR=/opt/personal-server",
      "sudo mkdir -p $DEPLOY_DIR && sudo chown admin:admin $DEPLOY_DIR",

      "umask 077",
      "cat > /tmp/gh-askpass.sh <<'EOF'\n#!/bin/sh\ncase \"$1\" in\n*Username*) echo \"x-access-token\" ;;\n*Password*) echo \"${var.github_pat}\" ;;\n*) echo \"\" ;;\nesac\nEOF",
      "chmod 700 /tmp/gh-askpass.sh",
      "export GIT_ASKPASS=/tmp/gh-askpass.sh",
      "export GIT_TERMINAL_PROMPT=0",

      # NOTE: prefer var.github_repo_url and use it directly (see note above)
      "if [ ! -d $DEPLOY_DIR/.git ]; then git clone https://${var.github_repo} $DEPLOY_DIR; else (cd $DEPLOY_DIR && git pull --ff-only); fi",

      "rm -f /tmp/gh-askpass.sh",
      "unset GIT_ASKPASS GIT_TERMINAL_PROMPT",

      "sudo chmod a+X /opt /opt/personal-server /opt/personal-server/deploy /opt/personal-server/deploy/nginx",
      "sudo chmod -R a+rX $DEPLOY_DIR/deploy/nginx/html",

      "cd $DEPLOY_DIR/deploy/nginx",
      "docker compose up -d --build --remove-orphans",

      "git config --global --unset credential.helper || true",
      "rm -f ~/.git-credentials || true"
    ]
  }
}