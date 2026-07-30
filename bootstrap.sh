#!/usr/bin/env bash
# bootstrap.sh — one-time cluster setup (macOS + Docker Desktop).
# Everything AFTER this script is GitOps-managed via ArgoCD.
# Prerequisites: docker (Docker Desktop), minikube, kubectl, kubeseal, git
# Run: chmod +x bootstrap.sh && ./bootstrap.sh
set -euo pipefail

GITHUB_USERNAME="abdinbayov"
ARGOCD_VERSION="v2.11.3"
IMAGE_NAME="qoves-django-api"
IMAGE_TAG="1.0.0"

# ── 1. Cluster ────────────────────────────────────────────────────────────────
echo "==> 1. Start minikube with Cilium CNI"
# Cilium is required — minikube's default (kindnet) silently ignores NetworkPolicy.
# --nodes=2 gives a realistic multi-node setup; remove it for a single-node run.
minikube start \
  --driver=docker \
  --nodes=2 \
  --cni=cilium \
  --memory=4096 \
  --cpus=2 \
  --kubernetes-version=v1.30.0

echo "==> 2. Enable addons"
minikube addons enable ingress
minikube addons enable metrics-server

# ── 2. Image ──────────────────────────────────────────────────────────────────
echo "==> 3. Build image and load into minikube (works with multi-node)"
# Build using Docker Desktop's daemon, then load into all minikube nodes.
# minikube image load is compatible with multi-node; docker-env is not.
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .
minikube image load "${IMAGE_NAME}:${IMAGE_TAG}"

# ── 3. Sealed Secrets controller ─────────────────────────────────────────────
echo "==> 4. Install Sealed Secrets controller (bootstrap — controller install by hand is fine per requirements)"
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.3/controller.yaml
kubectl wait --for=condition=available --timeout=120s deployment/sealed-secrets-controller -n kube-system

# ── 4. ArgoCD ────────────────────────────────────────────────────────────────
echo "==> 5. Install ArgoCD (bootstrap only — all workloads are GitOps-managed after this)"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
echo "    Waiting for ArgoCD server to be ready..."
kubectl wait --for=condition=available --timeout=180s deployment/argocd-server -n argocd

# ── 4. Root Application ───────────────────────────────────────────────────────
echo "==> 6. Register the root ArgoCD Application"
# This single apply is the only imperative step — from here ArgoCD owns the cluster.
kubectl apply -f apps/root.yaml

# ── 5. Next steps ─────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo " Bootstrap complete. ArgoCD is now reconciling the stack."
echo "================================================================"
echo ""
echo " NEXT: Seal your secrets (run after 'sealed-secrets' app is Synced):"
echo ""
echo "   kubectl get app sealed-secrets -n argocd   # wait for Synced"
echo ""
echo "   Then run: ./seal-secrets.sh"
echo ""
echo " THEN: Open ingress access:"
echo "   a) In a separate terminal:  minikube tunnel"
echo "   b) echo '127.0.0.1 qoves.local' | sudo tee -a /etc/hosts"
echo ""
echo " TEST:"
echo "   curl http://qoves.local/"
echo "   curl http://qoves.local/healthz"
echo "   curl http://qoves.local/metrics"
echo ""
echo " ARGOCD UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Password: kubectl get secret argocd-initial-admin-secret -n argocd \\"
echo "     -o jsonpath='{.data.password}' | base64 -d && echo"
