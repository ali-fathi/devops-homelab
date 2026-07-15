# Homelab API

This is a small demo application used to learn CI/CD, container builds, image scanning, and registry publishing.

---

## Purpose

The app is intentionally simple.

It is used to test:

```text
Docker build
Trivy image scanning
GitHub Actions pipeline
GitHub Container Registry push
Future Harbor registry push
Future Argo CD deployment
Future progressive delivery with Argo Rollouts

GET /
GET /healthz
