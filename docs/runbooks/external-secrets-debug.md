```markdown
# Runbook: ExternalSecret Debug

## Check ExternalSecret

```bash
kubectl get externalsecret -A
kubectl describe externalsecret <name> -n <namespace>
