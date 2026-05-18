# CB Project — DevOps Exam

## Repository
- **GitHub repo:** https://github.com/ChitRavi-automates/cb-project
- **App source repo:** https://github.com/ChitRavi-automates/plan-it

## Live URLs
- **Application:** https://chitra-plan-it.chitra.doe24.chas-lab.dev
- **Grafana:** https://grafana.chitra.doe24.chas-lab.dev
- **ArgoCD:** https://argocd.chitra.doe24.chas-lab.dev

## Cluster
- 3 control plane nodes (NoSchedule taint — no workloads)
- 1 worker node (all workloads run here)
- k3s v1.33.5

## Stack
| Component | Tool |
|---|---|
| Infrastructure (IaC) | Terraform + Hetzner Cloud |
| Configuration Management | Ansible |
| GitOps | ArgoCD (app-of-apps pattern) |
| Ingress | Traefik (built-in k3s) |
| TLS | cert-manager + LetsEncrypt wildcard (DNS-01 via acme-dns) |
| Monitoring | kube-prometheus-stack (Prometheus + Grafana + Alertmanager) |
| Log collection | Loki + Promtail (DaemonSet on all nodes) |
| Secrets | Sealed Secrets |
| App packaging | Helm chart (individual) |
| CI/CD | GitHub Actions |
| Container registry | GitHub Container Registry (ghcr.io) |

## CI/CD Workflows
| Workflow | Trigger | Purpose |
|---|---|---|
| `provision.yml` | Manual (`workflow_dispatch`) | Provision Hetzner servers + install k3s |
| `deploy.yml` | Push to `k8s/**` on main | Trigger ArgoCD sync |

## Helm Chart (Individual Part)
- **Chart:** `k8s/chitra-plan-it-helm-chart`
- **Components:** Frontend (React), Backend (.NET), Database (SQL Server)
- **Images:** `ghcr.io/chitravi-automates/plan-it-frontend:latest`, `ghcr.io/chitravi-automates/plan-it-backend:latest`
- **Customizable values (5+):** `frontend.replicaCount`, `backend.replicaCount`, `frontend.image.tag`, `backend.image.tag`, `global.domain`, `database.persistence.size`, `database.persistence.storageClass`, `app.environment`

## Logging
- Promtail runs as DaemonSet on all 4 nodes
- Collects logs from all pods in all namespaces
- Ships to Loki
- Viewable in Grafana → Explore → Loki datasource

## Secrets Handling
- All secrets stored as Sealed Secrets in Git
- Encrypted with cluster keypair
- Keypair backed up in GitHub secret `SEALED_SECRETS_KEYPAIR`
- Auto-restored on fresh cluster via `provision.yml`

## Exam Day Steps
1. Update `HETZNER_TOKEN` GitHub secret with new token
2. Update `global.domain` in `values.yaml` with new domain
3. Run `provision.yml` workflow (paste worker IP if provided by teacher)
4. Re-register acme-dns for new domain, re-seal `acmedns-account-sealed.yaml`
5. Commit + push → `deploy.yml` triggers → ArgoCD syncs everything
