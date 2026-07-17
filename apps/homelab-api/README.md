# Homelab API

For the repository-wide platform study guide, read:

```text
docs/homelab-study-guide.md
```

This is a small demo application used to learn CI/CD, container builds, image scanning, container registry publishing, and later GitOps deployment.

The application is intentionally simple. The goal is not to build a complex service yet. The goal is to create a clean, repeatable DevOps workflow:

```text
source code
  -> container build
  -> security scan
  -> registry push
  -> future Kubernetes deployment
  -> future Argo CD management
```

---

## Purpose

The `homelab-api` app is used as a safe learning workload for Week 4 and later phases.

It is used to test:

```text
Docker build
GitHub Actions build workflow
Trivy image scanning
GitHub Container Registry publishing
Future Harbor registry publishing
Future Kubernetes deployment
Future Argo CD Application management
Future progressive delivery with Argo Rollouts
```

---

## Application Path

Repository path:

```text
apps/homelab-api
```

Expected files:

```text
apps/homelab-api/
├── app.py
├── Dockerfile
├── README.md
└── requirements.txt
```

---

## Application Runtime

The application is a Python Flask API.

It listens on:

```text
0.0.0.0:8080
```

Container port:

```text
8080
```

---

## Endpoints

### Root endpoint

```text
GET /
```

Expected response:

```json
{
  "app": "homelab-api",
  "status": "ok",
  "version": "dev"
}
```

---

### Health endpoint

```text
GET /healthz
```

Expected response:

```json
{
  "status": "healthy"
}
```

---

## Local Build

From the repository root:

```bash
docker build -t homelab-api:local apps/homelab-api
```

Expected result:

```text
Successfully tagged homelab-api:local
```

---

## Local Run

Run the container locally:

```bash
docker run --rm -p 8080:8080 homelab-api:local
```

Test from another terminal:

```bash
curl http://localhost:8080/
curl http://localhost:8080/healthz
```

Stop the container with:

```text
Ctrl+C
```

---

## GitHub Actions Build Workflow

The container build workflow is expected at:

```text
.github/workflows/homelab-api-build.yaml
```

The workflow should:

```text
Build the Docker image.
Scan the image with Trivy.
Push the image to GitHub Container Registry on main branch pushes.
Skip registry push for pull requests.
```

---

## Current Registry Target

Initial Week 4 registry target:

```text
ghcr.io/<github-owner>/homelab-api
```

Example expected image tags:

```text
ghcr.io/ali-fathi/homelab-api:<commit-sha>
ghcr.io/ali-fathi/homelab-api:latest
```

---

## Future Harbor Registry Target

After Harbor is deployed and tested, the future image target can become:

```text
harbor.greyneo.com/homelab/homelab-api:<tag>
```

This should be done only after Harbor login, push, pull, storage, and backup behavior are tested.

---

## Security Notes

This demo image is intentionally simple for learning.

Future hardening tasks:

```text
Run as non-root user.
Add container securityContext in Kubernetes manifests.
Add readOnlyRootFilesystem where possible.
Pin base image by digest.
Add image labels.
Generate SBOM.
Sign image with Cosign.
Scan image before push.
Make Trivy blocking after findings are understood.
```

---

## Current deployment status

The app is currently a CI/CD learning workload. Its GitHub Actions workflow builds, scans, and publishes the image to GHCR. It is not currently deployed by a Kubernetes Application or Argo CD Application in this repository.

## Future Kubernetes Deployment

This app is not deployed to Kubernetes yet.

Future Kubernetes path could be:

```text
kubernetes/applications/homelab-api
```

Future files could include:

```text
namespace.yaml
deployment.yaml
service.yaml
ingress.yaml or loadbalancer service yaml
README.md
```

For this homelab, any service that needs a dedicated LAN address should use MetalLB with an IP from the configured MetalLB pool.

---

## Future Argo CD Application

Future Argo CD Application path could be:

```text
kubernetes/gitops/argocd/applications/homelab-api.yaml
```

Recommended initial sync policy for a new app:

```yaml
syncPolicy:
  automated:
    enabled: true
    prune: false
    selfHeal: true
```

Keep pruning disabled until the app is stable and restore/rollback behavior is understood.

---

## Success Criteria for Week 4

The `homelab-api` Week 4 task is complete when:

```text
[ ] Dockerfile exists.
[ ] App builds locally.
[ ] App runs locally.
[ ] / endpoint responds.
[ ] /healthz endpoint responds.
[ ] GitHub Actions builds the image.
[ ] Trivy scans the image.
[ ] Image is pushed to GHCR from main branch.
[ ] Image can be pulled and run locally.
```

---

## Future Improvements

```text
Add unit tests.
Add pytest workflow.
Add Kubernetes manifests.
Deploy with Argo CD.
Publish to Harbor.
Add SBOM generation.
Add Cosign image signing.
Add Argo Rollouts canary deployment.
Add Grafana dashboard.
Add Prometheus health alert.
```
