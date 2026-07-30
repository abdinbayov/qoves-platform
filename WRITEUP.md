# QOVES Platform — Writeup

## 1. Run It

**Prerequisites (macOS)**
```bash
brew install minikube kubectl kubeseal
# Docker Desktop must be running
```

**Stand it up**
```bash
git clone https://github.com/abdinbayov/qoves-platform.git
cd qoves-platform
chmod +x bootstrap.sh && ./bootstrap.sh
```

The script does three things that cannot live in git: starts minikube with Cilium, installs ArgoCD, and registers the root Application. Everything else is reconciled by ArgoCD from this repo.

**Repo layout**
```
apps/           # ArgoCD app-of-apps (root + child Applications)
manifests/
  django-api/   # Deployment, Service, Ingress, HPA, PDB, NetworkPolicy, SealedSecret, migration Job
  postgres/     # StatefulSet, PVC, Service, NetworkPolicy, SealedSecret
  monitoring/   # PrometheusRule, ServiceMonitor, Grafana SealedSecret
app/            # Django source
Dockerfile
bootstrap.sh
```

**GitOps flow — making a change**
```bash
vim manifests/django-api/hpa.yaml   # e.g. raise minReplicas
git add . && git commit -m "feat: raise minReplicas" && git push
# ArgoCD detects the diff and reconciles within ~30s — no kubectl apply
```

**macOS ingress access** (after bootstrap)
```bash
echo '127.0.0.1 qoves.local' | sudo tee -a /etc/hosts
minikube tunnel   # keep running in a separate terminal
curl http://qoves.local/
curl http://qoves.local/healthz
curl http://qoves.local/metrics
```

---

## 2. Decisions

**CNI: Cilium**
minikube's default (kindnet) accepts NetworkPolicy objects but never enforces them — a silent false sense of security. Calico enforces correctly and is a valid choice. Cilium was chosen because its eBPF datapath also enables `hubble observe` for live flow visibility, making it straightforward to prove that policies are actually blocking traffic during the walkthrough.

**Secrets: Sealed Secrets**
SOPS+age is a reasonable alternative but requires an ArgoCD plugin for decryption at sync time. External Secrets Operator with Vault is the production answer but adds a Vault cluster to the scope. Sealed Secrets is the simplest fully-local, fully-declarative option: `kubeseal` encrypts against the in-cluster controller's public key, the ciphertext is committed, and the plaintext never touches git. The trade-off is that the controller's private key becomes a single point of failure — its backup is called out in production gaps.

**Postgres: Raw StatefulSet**
CloudNativePG handles failover, connection pooling, and scheduled backups automatically and is the right production choice. A raw StatefulSet was used here because it maps 1:1 to the concepts under test (PVC lifecycle, headless service, pod ordering) without operator abstraction. The migration path is replacing the StatefulSet with a CloudNativePG `Cluster` CRD.

**HPA scaling signal: CPU (with caveats)**
CPU is a weak signal for an I/O-bound API whose bottleneck is database round-trips — a pod can be saturated waiting on Postgres while CPU stays low. The CPU HPA satisfies the requirement because `metrics-server` is available out of the box. In production the right signal is request rate (`django_http_requests_total` via KEDA + Prometheus scaler) or P99 latency, which scales before users notice degradation rather than after CPU already spikes.

---

## 3. What Minikube Did For Me

| minikube provides | On real bare metal |
|---|---|
| Control plane bootstrap | `kubeadm init`, TLS cert distribution, etcd on 3 nodes |
| CNI install | `helm install cilium` with explicit pod CIDR and kube-proxy replacement |
| Ingress load-balancing | MetalLB (L2) or hardware LB in front of ingress-nginx |
| Storage provisioner | Rook-Ceph, NFS provisioner, or local-path-provisioner (no replication) |
| etcd | 3–5 dedicated etcd nodes, snapshot backups to object storage on a cron |

---

## 4. Production Gaps

| Gap | Production answer |
|---|---|
| Single Postgres pod | CloudNativePG with streaming replication and automated failover |
| No etcd backup | `etcdctl snapshot save` to S3 on a cron; restore procedure tested quarterly |
| Sealed Secrets key unprotected | Back up the controller private key to Vault or a cloud secret store on day 0 |
| No TLS on ingress | cert-manager + Let's Encrypt; TLS termination at the ingress controller |
| CPU-based HPA | KEDA with Prometheus scaler on request rate or latency |
| No image signing | Cosign + Kyverno admission policy to reject unsigned images |
| No upgrade strategy for Postgres | CloudNativePG handles rolling minor upgrades; major upgrades need a blue/green |
| Single cluster | Separate control and data-plane clusters; Cilium Cluster Mesh for cross-cluster services |

---

## 5. Runbook: Database Pod Dies

**Alert fires:** `DjangoApiDatabaseUnreachable` — `/healthz` returning 503 for 2 minutes.

**Step 1 — Confirm**
```bash
kubectl get pods -n postgres
kubectl describe pod postgres-0 -n postgres   # look for OOMKilled, missing PVC
```

**Step 2 — Check the PVC**
```bash
kubectl get pvc -n postgres
# Bound → data is safe, pod is just restarting
# Lost  → node deleted with data; escalate immediately
```

**Step 3 — Let the StatefulSet self-heal**
```bash
kubectl rollout status statefulset/postgres -n postgres --timeout=120s
```

**Step 4 — Verify recovery**
```bash
curl http://qoves.local/healthz   # expect {"status":"ok"} 200
```

**Step 5 — If pod keeps OOMKilling, fix via git**
```bash
vim manifests/postgres/statefulset.yaml   # raise limits.memory
git add . && git commit -m "fix: raise postgres memory limit" && git push
# ArgoCD syncs; StatefulSet rolls the new spec
```

**Step 6 — Post-incident**
```bash
kubectl exec -n postgres postgres-0 -- df -h /var/lib/postgresql/data
# If >80% full: raise PVC size (requires allowVolumeExpansion: true on StorageClass)
```
