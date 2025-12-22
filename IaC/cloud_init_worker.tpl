#cloud-config
package_update: true
package_upgrade: true
packages:
  - curl
  - jq
  - ca-certificates

write_files:
  - path: /etc/profile.d/k3s-env.sh
    content: |
      export K3S_TOKEN="${k3s_token}"
      export K3S_NODE_IP="${private_ip}"

runcmd:
  - echo "Provisioning worker node ${node_index} (joining to ${server_url}) private_ip=${private_ip}"
  - |
    # Ensure curl exists, then join the cluster as k3s agent
    if ! command -v curl >/dev/null 2>&1; then
      apt-get update -y || true
      apt-get install -y curl || true
    fi
    # If k3s agent is already installed, skip
    if systemctl is-active --quiet k3s-agent 2>/dev/null || [ -f /var/lib/rancher/k3s/agent/k3s-agent.env ]; then
      echo "k3s agent looks already installed"
      exit 0
    fi
    set -e
    # Use K3S_URL pointing at bootstrap public IP (server_url); pass private node ip so node advertises private address
    curl -sfL https://get.k3s.io | K3S_URL="${server_url}" K3S_TOKEN="${k3s_token}" K3S_NODE_IP="${private_ip}" sh -
  - echo "Worker provisioning finished"
final_message: "Worker provisioning finished"
