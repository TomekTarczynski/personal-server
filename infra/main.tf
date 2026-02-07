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

  provisioner "file" {
    source      = "${path.module}/scripts/deploy.sh"
    destination = "/tmp/deploy.sh"
  }

  provisioner "file" {
    source      = var.dropbox_env_path
    destination = "/tmp/dropbox.env"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo install -d -m 700 /etc/personal-server",
      "sudo install -m 600 /tmp/dropbox.env /etc/personal-server/dropbox.env",
      "rm -f /tmp/dropbox.env",
      "chmod 700 /tmp/deploy.sh",
      "REPO_URL='https://${var.github_repo}' GITHUB_PAT='${var.github_pat}' DEPLOY_DIR='/opt/personal-server' COMPOSE_DIR='/opt/personal-server/deploy' bash /tmp/deploy.sh",
      "rm -rf /tmp/deploy.sh"
    ]
  }
}