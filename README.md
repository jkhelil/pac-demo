# PAC Demo (Go REST API)

Simple but non-trivial Go app for Pipelines-as-Code demo:
- Endpoints: `/healthz`, `/version`, `/greet?name=NAME`, `POST /calc/sum` with `{"numbers":[...]}`.
- Built with Tekton via PAC on PRs; scans with Trivy (source+image) and Snyk (code).

## Local build

```bash
make test
make build
make docker-build IMG=ghcr.io/jkhelil/pac-demo:dev
```

## Kind + Tekton + PAC quick notes

1) Create cluster and install Tekton (pipelines, chains, dashboard) and PAC per docs:
- Getting started: https://pipelinesascode.com/docs/install/getting-started/

2) Create namespace and secrets (adjust values):

```bash
kubectl create ns pac-demo-pipelines
kubectl -n pac-demo-pipelines create secret docker-registry ghcr-creds \
  --docker-server=ghcr.io \
  --docker-username=jkhelil \
  --docker-password=$GHCR_PAT \
  --docker-email=YOUR_EMAIL

kubectl -n pac-demo-pipelines create secret generic snyk-token \
  --from-literal=SNYK_TOKEN='YOUR_SNYK_TOKEN'
```

3) Link repo to PAC in `pac-demo-pipelines`:

```bash
tkn pac create repository
```

4) Open a PR; watch PipelineRun on Tekton Dashboard and via CLI:

```bash
# dashboard typically forwarded on localhost:9097
tkn pr list -n pac-demo-pipelines
tkn pr logs -f <name> -n pac-demo-pipelines
```

Image is pushed to `ghcr.io/jkhelil/pac-demo:<short-sha>` on success.

