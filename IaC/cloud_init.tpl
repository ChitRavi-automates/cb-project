#cloud-config
package_update: true
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
  - echo "Provisioning node ${node_index} (control=${is_control}, init=${is_init}, private_ip=${private_ip})"
  - |
    # Use public bootstrap URL for K3S_URL so it matches current cert SANs; but force k3s to bind/advertise private IP
    # node_taint is passed from Terraform; when empty it adds no taint flag, otherwise it contains the --node-taint argument
    if [ "${is_control}" = "true" ]; then
      if [ "${is_init}" = "true" ]; then
        echo "Bootstrapping k3s (cluster-init) on this init control"
        curl -sfL https://get.k3s.io | K3S_TOKEN="${k3s_token}" INSTALL_K3S_EXEC="server --cluster-init --node-ip ${private_ip} --advertise-address ${private_ip} --node-name ${project_name}-control-${node_index} ${node_taint}" sh -
      else
        echo "Starting k3s server and joining to ${server_url} (will advertise ${private_ip})"
        curl -sfL https://get.k3s.io | K3S_TOKEN="${k3s_token}" INSTALL_K3S_EXEC="server --server ${server_url} --node-ip ${private_ip} --advertise-address ${private_ip} --node-name ${project_name}-control-${node_index} ${node_taint}" sh -
      fi
    else
      echo "Installing k3s agent and joining to ${server_url} (node-ip ${private_ip})"
      curl -sfL https://get.k3s.io | K3S_URL="${server_url}" K3S_TOKEN="${k3s_token}" K3S_NODE_IP="${private_ip}" sh -
    fi
  - |
    # NOTE: remove_taints=true will remove control-plane/master taints after join (keeps behavior configurable)
    if [ "${remove_taints}" = "true" ] && [ "${is_control}" = "true" ]; then
      for i in $(seq 1 40); do
        if /usr/local/bin/kubectl get nodes >/dev/null 2>&1; then break; fi
        sleep 5
      done
      /usr/local/bin/kubectl taint nodes --all node-role.kubernetes.io/master- || true
      /usr/local/bin/kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
    fi
final_message: "Provisioning finished"
