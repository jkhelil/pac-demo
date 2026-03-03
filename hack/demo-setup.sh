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

echo "==> Configuring Tekton Chains (OCI + in-toto + deep inspection for image signing)..."
kubectl -n tekton-chains patch configmap chains-config --type=merge -p '{"data":{
  "artifacts.oci.storage": "oci",
  "artifacts.pipelinerun.format": "in-toto",
  "artifacts.pipelinerun.storage": "oci",
  "artifacts.pipelinerun.enable-deep-inspection": "true",
  "artifacts.taskrun.format": "in-toto",
  "artifacts.taskrun.storage": "oci"
}}' 2>/dev/null || true

if ! kubectl get secret signing-secrets -n tekton-chains &>/dev/null; then
  echo "==> Generating Tekton Chains signing secret (cosign)..."
  COSIGN_PASSWORD="${COSIGN_PASSWORD:-password}" cosign generate-key-pair k8s://tekton-chains/signing-secrets
else
  echo "==> Signing secret already exists in tekton-chains, skipping."
fi

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

echo "==> Installing Pipeline (config/build-and-push-pipeline.yaml) in $NS..."
kubectl apply -f config/build-and-push-pipeline.yaml -n "$NS"

# Chains (and Kubernetes) expect registry auth as type dockerconfigjson: that is the only type
# that gets mounted as ~/.docker/config.json in pods (imagePullSecrets). Chains uses the
# pipeline SA's credentials to push attestations to OCI; cosign/crane use the same format.
DOCKER_CONFIG="${DOCKER_CONFIG:-$HOME/.docker/config.json}"
if [[ -f "$DOCKER_CONFIG" ]]; then
  echo "==> Creating ghcr-configjson from $DOCKER_CONFIG (for Chains + pipeline SA)..."
  kubectl -n "$NS" create secret docker-registry ghcr-configjson \
    --from-file=.dockerconfigjson="$DOCKER_CONFIG" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$NS" patch serviceaccount pipeline -p '{"imagePullSecrets": [{"name": "ghcr-configjson"}]}' 2>/dev/null || true
  kubectl -n "$NS" patch serviceaccount pipeline -p '{"secrets": [{"name": "ghcr-configjson"}]}' 2>/dev/null || true
  echo "==> Linked ghcr-configjson to service account pipeline in $NS."
else
  echo "==> Skipping ghcr-configjson: $DOCKER_CONFIG not found. Run 'docker login ghcr.io' or create secret manually for Chains attestation push."
fi

if [[ -n "${GHCR_PAT:-}" ]]; then
  GITHUB_USER="${GITHUB_USER:-${GHCR_USERNAME:-}}"
  GHCR_EMAIL="${GHCR_EMAIL:-${EMAIL:-noreply@example.com}}"
  if [[ -z "$GITHUB_USER" ]]; then
    echo "==> Skipping ghcr-creds: set GITHUB_USER (or GHCR_USERNAME) and re-run, or create the secret manually."
  else
    # Buildah task expects the file to be named config.json (not .dockerconfigjson)
    AUTH_B64="$(echo -n "${GITHUB_USER}:${GHCR_PAT}" | base64)"
    DOCKER_JSON="{\"auths\":{\"ghcr.io\":{\"username\":\"${GITHUB_USER}\",\"password\":\"${GHCR_PAT}\",\"auth\":\"${AUTH_B64}\"}}}"
    kubectl create secret generic ghcr-creds -n "$NS" \
      --from-literal=config.json="$DOCKER_JSON" \
      --dry-run=client -o yaml | kubectl apply -f -
    echo "==> Registry secret ghcr-creds created in $NS (config.json for buildah)."
    # Link secret to pipeline service account (imagePullSecrets + secrets for pod access)
    kubectl -n "$NS" patch serviceaccount pipeline -p '{"imagePullSecrets": [{"name": "ghcr-creds"}]}' 2>/dev/null || true
    kubectl -n "$NS" patch serviceaccount pipeline -p '{"secrets": [{"name": "ghcr-creds"}]}' 2>/dev/null || true
    echo "==> Linked ghcr-creds to service account pipeline in $NS."
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
