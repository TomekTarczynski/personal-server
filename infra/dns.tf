data "hcloud_zone" "main" {
    name = "tomekt.cloud"
}

resource "hcloud_zone_rrset" "root_a" {
    zone    = data.hcloud_zone.main.id
    name    = "@"
    type    = "A"

    records = [
        {
            value   = hcloud_server.vm.ipv4_address
            comment = "vm"
        }
    ]
}

resource "hcloud_zone_rrset" "www_a" {
    zone    = data.hcloud_zone.main.id
    name    = "www"
    type    = "A"

    records = [
        {
            value   = hcloud_server.vm.ipv4_address
            comment = "vm"
        }
    ]
}