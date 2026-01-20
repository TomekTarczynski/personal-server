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
  public_key = file("C:/Users/Gobol/.ssh/id_ed25519.pub")
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