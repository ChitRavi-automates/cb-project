#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./get-kubeconfig.sh                # tries default control nodes
#   ./get-kubeconfig.sh 157.90.231.202 # tries the single IP you pass
#
# Requirements:
# - private key at ~/.ssh/chris-new (or change KEY variable below)
# - ssh/scp available
# - network access to node(s)
# - you may need to run: eval "$(ssh-agent -s)"; ssh-add ~/.ssh/chris-new

KEY="${HOME}/.ssh/chris-new"
OUTDIR="./kubeconfigs"
RETRIES_PER_HOST=5
SLEEP_BETWEEN_RETRIES=6

# default hosts (edit/override by passing IPs as arguments)
DEFAULT_HOSTS=(157.90.231.202 49.13.236.108 46.224.58.97)

HOSTS=("${@:-${DEFAULT_HOSTS[@]}}")

mkdir -p "${OUTDIR}"

for host in "${HOSTS[@]}"; do
  echo "==> trying host: ${host}"
  success=false

  for attempt in $(seq 1 "${RETRIES_PER_HOST}"); do
    echo "  attempt ${attempt}/${RETRIES_PER_HOST}..."
    # quick ssh check (no command) with timeout
    if timeout 10s ssh -o BatchMode=yes -o ConnectTimeout=8 -o IdentitiesOnly=yes -i "${KEY}" -o StrictHostKeyChecking=no root@"${host}" true 2>/dev/null; then
      echo "  SSH to ${host} ok"
      success=true
      break
    fi
    echo "  SSH failed, sleeping ${SLEEP_BETWEEN_RETRIES}s..."
    sleep "${SLEEP_BETWEEN_RETRIES}"
  done

  if [ "${success}" = "true" ]; then
    destfile="${OUTDIR}/k3s-${host}.yaml"
    echo "  copying /etc/rancher/k3s/k3s.yaml -> ${destfile}"
    if scp -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "${KEY}" -o StrictHostKeyChecking=no root@"${host}":/etc/rancher/k3s/k3s.yaml "${destfile}"; then
      # change local server endpoint from 127.0.0.1 to the node's public IP
      # handle both plain 127.0.0.1 and qualified 127.0.0.1:6443
      sed -i.bak -E "s/127\.0\.0\.1([:])?/${host}\1/g" "${destfile}" || true
      chmod 600 "${destfile}"
      echo
      echo "SUCCESS: kubeconfig saved to ${destfile}"
      echo "You can use it with:"
      echo "  export KUBECONFIG=\"$(pwd)/${destfile}\""
      echo "  kubectl get nodes -o wide"
      exit 0
    else
      echo "  scp failed from ${host} (permission or missing file)."
      # If k3s not installed or file path differs, try common alternate path for kubeconfig:
      alt="/var/lib/rancher/k3s/server/node-token"
      echo "  (optional) check remote /etc/rancher/k3s/k3s.yaml presence:"
      ssh -o ConnectTimeout=8 -o IdentitiesOnly=yes -i "${KEY}" -o StrictHostKeyChecking=no root@"${host}" "ls -l /etc/rancher/k3s/k3s.yaml || true"
    fi
  else
    echo "  all attempts failed for ${host}"
  fi
done

echo
echo "No host accepted your key or had the kubeconfig file at /etc/rancher/k3s/k3s.yaml."
echo "Options:"
echo " - Ensure your local private key ${KEY} is correct and loaded: eval \"\$(ssh-agent -s)\"; ssh-add ${KEY}"
echo " - If SSH is blocked, follow the Rescue flow to insert your public key into /root/.ssh/authorized_keys on the node."
echo " - You can also run this script with the single target IP: ./get-kubeconfig.sh 157.90.231.202"
exit 2
