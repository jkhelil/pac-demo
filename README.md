# PAC Demo (Go REST API)

Simple but non-trivial Go app for Pipelines-as-Code demo:
- Endpoints: `/healthz`, `/version`, `/greet?name=NAME`, `POST /calc/sum` with `{"numbers":[...]}`.
- Built with Tekton via PAC on **pull_request** and **push** to `main`; scans with Trivy (source+image) and Snyk (code).

## Local build

```bash
make test
make build
make docker-build IMG=ghcr.io/jkhelil/pac-demo:dev
```

## Kind + Tekton + PAC quick notes

1) Create cluster and install Tekton (pipelines, chains, dashboard) and PAC per docs:
- Getting started: https://pipelinesascode.com/docs/install/getting-started/

2) **Secrets: create them in the cluster (not in GitHub).**  
   GitHub Secrets are for Actions only; PAC runs in Kubernetes and reads secrets from the pipeline namespace.

   Create namespace and pipeline secrets:

```bash
kubectl create ns pac-demo

# Registry auth for pushing images (ghcr.io)
kubectl -n pac-demo create secret docker-registry ghcr-creds \
  --docker-server=ghcr.io \
  --docker-username=YOUR_GITHUB_USER \
  --docker-password=$GHCR_PAT \
  --docker-email=YOUR_EMAIL

# Snyk token for code scan task
kubectl -n pac-demo create secret generic snyk-token \
  --from-literal=SNYK_TOKEN='YOUR_SNYK_TOKEN'
```

   **Private repo:** PAC needs credentials to clone. When you run `tkn pac create repository`, you can point it to a Kubernetes secret containing a GitHub PAT or GitHub App credential; that secret is also created in the cluster. Public repos need no clone secret.

3) Link repo to PAC in `pac-demo`:

```bash
tkn pac create repository
```

4) Pipelines (in `.tekton/`):
   - **pull_request**: `pipelinerun-pull-request.yaml` — runs on PRs targeting `main`; image tag `pr-<revision>`.
   - **push**: `pipelinerun-push.yaml` — runs on push to `main`; image tag `<revision>`.

5) **How to test**

   **Pre-flight** (same namespace you used for secrets and `tkn pac create repository`):

   ```bash
   export NS=pac-demo   # or pac-demo-pipelines

   # Repo is linked and controller sees it
   tkn pac repository list -n $NS
   ```

   **Test 1 – Push pipeline**

   - Push a commit to `main` (or push a new branch and merge to `main`).
   - PAC should create a PipelineRun from `.tekton/pipelinerun-push.yaml`.
   - Image will be tagged with the commit SHA: `ghcr.io/jkhelil/pac-demo:<revision>`.

   **Test 2 – Pull request pipeline**

   - Open a PR targeting `main`.
   - PAC should create a PipelineRun from `.tekton/pipelinerun-pull-request.yaml`.
   - Image will be tagged `ghcr.io/jkhelil/pac-demo:pr-<revision>`.

   **Watch runs and logs**

   ```bash
   tkn pr list -n $NS
   tkn pr logs -f <pipelinerun-name> -n $NS
   ```

   Tekton Dashboard (if installed): forward the dashboard port (often 9097) and open the UI to see runs and logs.

   **Verify**

   - Check run status: `tkn pr describe <name> -n $NS`
   - Confirm image exists: `docker pull ghcr.io/jkhelil/pac-demo:<tag>` (or use the registry UI).
   - On GitHub: PAC posts status/comments on the commit or PR if configured.

   Images: **PR** → `ghcr.io/jkhelil/pac-demo:pr-<revision>`; **push to main** → `ghcr.io/jkhelil/pac-demo:<revision>`.

