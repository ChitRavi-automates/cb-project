variable "hcloud_token" {
  description = "Hetzner Cloud API token. Do NOT commit; set in CI or export HCLOUD_TOKEN/TF_VAR_hcloud_token."
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key content (ssh-ed25519 ...). Provide via CI variable TF_VAR_ssh_public_key."
  type        = string
  sensitive   = true
}

variable "ssh_key_name" {
  description = "Name for SSH key in Hetzner (or match existing key name)"
  type        = string
  default     = "group5-ssh"
}

variable "use_existing_ssh_key" {
  description = "If true, Terraform will reference an existing Hetzner key by name instead of creating it"
  type        = bool
  default     = true
}

variable "project_name" {
  type    = string
  default = "cb-project"
}

variable "location" {
  type    = string
  default = "nbg1"
}

variable "image" {
  type    = string
  default = "ubuntu-22.04"
}

variable "control_plane_count" {
  description = "Number of control-plane nodes (total). Set to 3 to get 3 control plane nodes."
  type        = number
  default     = 3
}

variable "agent_count" {
  description = "Number of worker nodes to create via Terraform. You can keep 0 and add external worker later."
  type        = number
  default     = 1
}

variable "server_type" {
  type    = string
  default = "cx31"
}

variable "worker_type" {
  type    = string
  default = "cx21"
}

variable "network_cidr" {
  type    = string
  default = "10.100.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.100.0.0/24"
}

variable "network_zone" {
  type    = string
  default = "eu-central"
}

variable "k3s_token" {
  description = "k3s join token. Provide TF_VAR_k3s_token in CI or let post-provisioning export it."
  type        = string
  sensitive   = true
  default     = ""
}

variable "remove_control_taints" {
  description = "Whether bootstrapping should remove control taints. Set to false to keep NoSchedule on control nodes."
  type        = bool
  default     = false
}
