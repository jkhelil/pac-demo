#!/usr/bin/env bash
# Automate Kind + Tekton + Dashboard + (optional) PAC for the pac-demo.
# Run from repo root: ./hack/demo-setup.sh
# Optional: INSTALL_PAC=1 ./hack/demo-setup.sh to also install Pipelines as Code.
# Optional: set GHCR_PAT + GITHUB_USER (and SNYK_TOKEN) to create registry/Snyk secrets in pac-demo namespace.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TEKTON_PIPELINE_URL="${TEKTON_PIPELINE_URL:-https://infra.tekton.dev/tekton-releases/pipeline/latest/release.yaml}"
TEKTON_CHAINS_URL="${TEKTON_CHAINS_URL:-https://infra.tekton.dev/tekton-releases/chains/latest/release.yaml}"
TEKTON_DASHBOARD_URL="${TEKTON_DASHBOARD_URL:-https://infra.tekton.dev/tekton-releases/dashboard/latest/release.yaml}"
PAC_RELEASE_URL="${PAC_RELEASE_URL:-https://raw.githubusercontent.com/openshift-pipelines/pipelines-as-code/stable/release.k8s.yaml}"

KIND_CLUSTER_NAME="tekton-cluster"
if kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER_NAME"; then
  echo "==> Kind cluster '$KIND_CLUSTER_NAME' already exists, skipping creation."
else
  echo "==> Creating Kind cluster (config/kind.yaml)..."
  kind create cluster --config config/kind.yaml
fi

echo "==> Installing Tekton Pipeline..."
kubectl apply --filename "$TEKTON_PIPELINE_URL"

echo "==> Installing Tekton Chains..."
kubectl apply --filename "$TEKTON_CHAINS_URL"

echo "==> Installing Tekton Dashboard..."
kubectl apply --filename "$TEKTON_DASHBOARD_URL"

echo "==> Applying dashboard NodePort (config/dashboard-nodeport.yaml)..."
kubectl apply -f config/dashboard-nodeport.yaml

echo "==> Waiting for Tekton Pipeline controller to be ready..."
kubectl wait --for=condition=Available deployment/tekton-pipelines-controller -n tekton-pipelines --timeout=120s 2>/dev/null || true
kubectl wait --for=condition=Available deployment/tekton-pipelines-webhook -n tekton-pipelines --timeout=120s 2>/dev/null || true

if [[ "${INSTALL_PAC:-0}" == "1" ]]; then
  echo "==> Installing Pipelines as Code (PAC)..."
  kubectl apply -f "$PAC_RELEASE_URL"
  echo "==> Waiting for PAC controller to be ready..."
  kubectl wait --for=condition=Available deployment/pipelines-as-code-controller -n pipelines-as-code --timeout=120s 2>/dev/null || true
  echo "==> PAC installed. Use 'tkn pac bootstrap' or configure webhook + 'tkn pac create repository' to link this repo."
else
  echo "==> Skipping PAC install. To install: INSTALL_PAC=1 $0"
fi

NS="${PAC_DEMO_NS:-pac-demo}"
echo ""
echo "==> Creating namespace and pipeline resources (namespace: $NS)..."

kubectl create namespace "$NS" 2>/dev/null || true
kubectl create serviceaccount pipeline -n "$NS" 2>/dev/null || true

if [[ -n "${GHCR_PAT:-}" ]]; then
  GITHUB_USER="${GITHUB_USER:-${GHCR_USERNAME:-}}"
  GHCR_EMAIL="${GHCR_EMAIL:-${EMAIL:-noreply@example.com}}"
  if [[ -z "$GITHUB_USER" ]]; then
    echo "==> Skipping ghcr-creds: set GITHUB_USER (or GHCR_USERNAME) and re-run, or create the secret manually."
  else
    kubectl create secret docker-registry ghcr-creds -n "$NS" \
      --docker-server=ghcr.io \
      --docker-username="$GITHUB_USER" \
      --docker-password="$GHCR_PAT" \
      --docker-email="${GHCR_EMAIL}" \
      --dry-run=client -o yaml | kubectl apply -f -
    echo "==> Registry secret ghcr-creds created in $NS."
  fi
else
  echo "==> Skipping ghcr-creds: set GHCR_PAT (and GITHUB_USER) then re-run or create the secret manually."
fi

if [[ -n "${SNYK_TOKEN:-}" ]]; then
  kubectl create secret generic snyk-token -n "$NS" \
    --from-literal=SNYK_TOKEN="$SNYK_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "==> Snyk secret snyk-token created in $NS."
else
  echo "==> Skipping snyk-token: set SNYK_TOKEN then re-run or create the secret manually."
fi

echo ""
echo "==> Demo cluster ready."
echo "    Dashboard NodePort: http://127.0.0.1.nip.io:30097 (see config/dashboard-nodeport.yaml)"
echo ""
echo "Next steps:"
echo "  1. Link repo to PAC:   tkn pac bootstrap"
echo "  2. Push or open a PR to trigger pipelines; watch: tkn pr list -n $NS && tkn pr logs -f <name> -n $NS"
