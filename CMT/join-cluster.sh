#!/usr/bin/env bash
# Non-interactive helper: fetch token from bootstrap and run the Ansible playbook.
# Use this from your laptop (not the servers). Expects ssh key at ~/.ssh/chris-new
set -euo pipefail

BOOTSTRAP_IP="157.90.231.202"
SSH_KEY="$HOME/.ssh/chris-new"
PLAYDIR="$HOME/cb/CMT"

cd "${PLAYDIR}"

echo "Fetching k3s node-token from bootstrap ${BOOTSTRAP_IP}..."
TOKEN=$(ssh -i "${SSH_KEY}" root@"${BOOTSTRAP_IP}" 'sudo cat /var/lib/rancher/k3s/server/node-token' 2>/dev/null || true)

if [ -z "${TOKEN}" ]; then
  echo "ERROR: token empty; ensure bootstrap is up and token file exists at /var/lib/rancher/k3s/server/node-token" >&2
  exit 1
fi

echo "Running ansible-playbook with token (non-interactive)"
# If you use ansible-vault for secrets, add --ask-vault-pass or use environment ANSIBLE_VAULT_PASSWORD_FILE
ansible-playbook -i inventory.ini site.yaml --extra-vars "k3s_token=${TOKEN}"
