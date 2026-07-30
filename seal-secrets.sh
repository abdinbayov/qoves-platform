#!/usr/bin/env bash
# seal-secrets.sh — generate and seal all credentials.
# Run once after the sealed-secrets ArgoCD app is Synced.
# Raw secrets are written to /tmp and deleted immediately after sealing.
set -euo pipefail

echo "==> Generating credentials and sealing..."

DB_PASS=$(python3 -c "import secrets; print(secrets.token_urlsafe(20))")
APP_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(50))")
GRAFANA_PASS=$(python3 -c "import secrets; print(secrets.token_urlsafe(20))")

# Postgres credentials
cat > /tmp/pg-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
  namespace: postgres
stringData:
  username: bankuser
  password: "${DB_PASS}"
EOF

# Django API credentials (DATABASE_URL + Django SECRET_KEY)
cat > /tmp/db-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: django-api-db-credentials
  namespace: django-api
stringData:
  DATABASE_URL: "postgresql://bankuser:${DB_PASS}@postgres.postgres.svc.cluster.local:5432/bankdb"
  SECRET_KEY: "${APP_KEY}"
EOF

# Grafana admin credentials
cat > /tmp/grafana-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin-credentials
  namespace: monitoring
stringData:
  admin-user: admin
  admin-password: "${GRAFANA_PASS}"
EOF

kubeseal --format yaml < /tmp/pg-secret.yaml      > manifests/postgres/sealedsecret.yaml
kubeseal --format yaml < /tmp/db-secret.yaml      > manifests/django-api/sealedsecret.yaml
kubeseal --format yaml < /tmp/grafana-secret.yaml > manifests/monitoring/sealedsecret-grafana.yaml

rm /tmp/pg-secret.yaml /tmp/db-secret.yaml /tmp/grafana-secret.yaml

echo "==> Sealed. Committing ciphertext to git..."
git add manifests/postgres/sealedsecret.yaml \
        manifests/django-api/sealedsecret.yaml \
        manifests/monitoring/sealedsecret-grafana.yaml
git commit -m "chore: seal credentials (ciphertext only)"
git push

echo ""
echo " Done. ArgoCD will sync the SealedSecrets within ~30s."
echo " Watch: kubectl get app django-api -n argocd"
