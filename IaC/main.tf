terraform {
  required_providers {
    hcloud   = { source = "hetznercloud/hcloud", version = "~> 1.48" }
    template = { source = "hashicorp/template", version = "~> 2.2" }
    null     = { source = "hashicorp/null", version = "~> 3.0" }
  }
  required_version = ">= 1.1.0"
}

provider "hcloud" {
  token = var.hcloud_token
}

# Use existing SSH key by name, or create one
data "hcloud_ssh_key" "existing" {
  count = var.use_existing_ssh_key ? 1 : 0
  name  = var.ssh_key_name
}

resource "hcloud_ssh_key" "me" {
  count      = var.use_existing_ssh_key ? 0 : 1
  name       = var.ssh_key_name
  public_key = var.ssh_public_key
}

locals {
  ssh_key_id = var.use_existing_ssh_key ? data.hcloud_ssh_key.existing[0].id : hcloud_ssh_key.me[0].id
}

# Private network + subnet
resource "hcloud_network" "k8s_net" {
  name     = "${var.project_name}-net"
  ip_range = var.network_cidr
}

resource "hcloud_network_subnet" "subnet" {
  network_id   = hcloud_network.k8s_net.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.subnet_cidr
}

# Firewall minimal rules (added etcd peer ports and allow from private network)
resource "hcloud_firewall" "k8s_fw" {
  name = "${var.project_name}-fw"

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "ssh"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "6443"
    source_ips  = ["0.0.0.0/0"]
    description = "kubernetes-api"
  }

  # allow etcd peer/client ports from the private network so control nodes communicate over project net
  # TEMPORARY: also include control public IPs to let a control-plane node join. REMOVE this change once join succeeds.
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "2379-2380"
    source_ips = [
      var.network_cidr,
    ]
    description = "etcd peer/client (private net + temp public allow)"
  }

  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "8472"
    source_ips  = [var.network_cidr]
    description = "flannel-vxlan"
  }
}

# ----------------------------
# Init control (index 0)
# ----------------------------
resource "hcloud_server" "control_init" {
  name         = "${var.project_name}-control-0"
  image        = var.image
  server_type  = var.server_type
  location     = var.location
  ssh_keys     = [local.ssh_key_id]
  firewall_ids = [hcloud_firewall.k8s_fw.id]

  user_data = templatefile("${path.module}/cloud_init.tpl", {
    node_index    = 0,
    is_control    = true,
    is_init       = true,
    project_name  = var.project_name,
    k3s_token     = var.k3s_token,
    server_url    = "https://127.0.0.1:6443",
    remove_taints = var.remove_control_taints,
    private_ip    = cidrhost(var.subnet_cidr, 10),
    node_taint    = var.remove_control_taints ? "" : "--node-taint 'node-role.kubernetes.io/control-plane=:NoSchedule'"
  })

  lifecycle {
    ignore_changes = [user_data]
  }
}
resource "hcloud_server_network" "init_net" {
  server_id  = hcloud_server.control_init.id
  network_id = hcloud_network.k8s_net.id
  ip         = cidrhost(var.subnet_cidr, 10)
}

resource "hcloud_firewall_attachment" "fw_attach_init" {
  firewall_id = hcloud_firewall.k8s_fw.id
  server_ids  = [hcloud_server.control_init.id]
}

# ----------------------------
# WAIT FOR APISERVER (prevents race condition)
# ----------------------------
resource "null_resource" "wait_for_apiserver" {
  triggers = {
    control_init_ip = hcloud_server.control_init.ipv4_address
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -e
      INIT_IP=${self.triggers.control_init_ip}
      echo "Waiting for kube-apiserver at $INIT_IP:6443 ..."
      # try up to 60 times (5 minutes)
      count=0
      until nc -z $INIT_IP 6443; do
        count=$((count+1))
        if [ "$count" -ge 60 ]; then
          echo "timed out waiting for $INIT_IP:6443" >&2
          exit 1
        fi
        sleep 5
      done
      echo "kube-apiserver appears to be listening on $INIT_IP:6443"
    EOT
    interpreter = ["bash", "-c"]
  }
}

# ----------------------------
# Additional control joiner nodes (control_count = total - 1)
# ----------------------------
resource "hcloud_server" "control" {
  count        = var.control_plane_count > 0 ? var.control_plane_count - 1 : 0
  name         = "${var.project_name}-control-${count.index + 1}"
  image        = var.image
  server_type  = var.server_type
  location     = var.location
  ssh_keys     = [local.ssh_key_id]
  firewall_ids = [hcloud_firewall.k8s_fw.id]

  user_data = templatefile("${path.module}/cloud_init.tpl", {
    node_index    = count.index + 1,
    is_control    = true,
    is_init       = false,
    project_name  = var.project_name,
    k3s_token     = var.k3s_token,
    server_url    = "https://${hcloud_server.control_init.ipv4_address}:6443",
    remove_taints = var.remove_control_taints,
    private_ip    = cidrhost(var.subnet_cidr, 11 + count.index),
    node_taint    = var.remove_control_taints ? "" : "--node-taint 'node-role.kubernetes.io/control-plane=:NoSchedule'"
  })

  depends_on = [
    hcloud_server.control_init,
    null_resource.wait_for_apiserver
  ]

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "hcloud_server_network" "control_net" {
  count      = var.control_plane_count > 0 ? var.control_plane_count - 1 : 0
  server_id  = hcloud_server.control[count.index].id
  network_id = hcloud_network.k8s_net.id
  ip         = cidrhost(var.subnet_cidr, 11 + count.index)
}

resource "hcloud_firewall_attachment" "fw_attach_control" {
  count       = var.control_plane_count > 0 ? var.control_plane_count - 1 : 0
  firewall_id = hcloud_firewall.k8s_fw.id
  server_ids  = [hcloud_server.control[count.index].id]
}

# ----------------------------
# Worker/agent nodes (created by Terraform if agent_count > 0)
# ----------------------------
resource "hcloud_server" "worker" {
  count        = var.agent_count
  name         = "${var.project_name}-worker-${count.index + 1}"
  image        = var.image
  server_type  = var.worker_type
  location     = var.location
  ssh_keys     = [local.ssh_key_id]
  firewall_ids = [hcloud_firewall.k8s_fw.id]

  user_data = templatefile("${path.module}/cloud_init_worker.tpl", {
    node_index   = count.index,
    project_name = var.project_name,
    k3s_token    = var.k3s_token,
    server_url   = "https://${hcloud_server.control_init.ipv4_address}:6443",
    private_ip   = cidrhost(var.subnet_cidr, 20 + count.index),
    node_taint   = "" # workers do not receive control-plane taint
  })

  depends_on = [
    hcloud_server.control_init,
    null_resource.wait_for_apiserver,
    hcloud_server.control
  ]

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "hcloud_server_network" "worker_net" {
  count      = var.agent_count
  server_id  = hcloud_server.worker[count.index].id
  network_id = hcloud_network.k8s_net.id
  ip         = cidrhost(var.subnet_cidr, 20 + count.index)
}

resource "hcloud_firewall_attachment" "fw_attach_worker" {
  count       = var.agent_count
  firewall_id = hcloud_firewall.k8s_fw.id
  server_ids  = [hcloud_server.worker[count.index].id]
}

# ----------------------------
# OUTPUTS
# ----------------------------
output "control_public_ips" {
  description = "Public IPv4 addresses of control-plane nodes (index 0 is init)"
  value = concat(
    [hcloud_server.control_init.ipv4_address],
    var.control_plane_count > 1 ? hcloud_server.control.*.ipv4_address : []
  )
}

output "worker_public_ips" {
  description = "Public IPs for workers (may be empty)"
  value       = length(hcloud_server.worker.*.ipv4_address) > 0 ? hcloud_server.worker.*.ipv4_address : []
}

output "control_private_ips" {
  description = "Private IPs assigned to control nodes"
  value = concat(
    [cidrhost(var.subnet_cidr, 10)],
    var.control_plane_count > 1 ? [for i in range(var.control_plane_count - 1) : cidrhost(var.subnet_cidr, 11 + i)] : []
  )
}
