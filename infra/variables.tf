variable "admin_ipv4_cidr" {
  type        = string
  description = "Public IPv4 CIDR allowed to SSH"
}

variable "github_pat" {
  type      = string
  sensitive = false
}

variable "ssh_private_key_path" {
  type        = string
  sensitive   = false
  description = "Path to private SSH key"
}

variable "ssh_public_key_path" {
  type        = string
  sensitive   = false
  description = "Path to public SSH key"
}

variable "github_repo" {
  type = string
}

variable "dropbox_env_path" {
  type        = string
  description = "Local path to the dropbox.env"
}