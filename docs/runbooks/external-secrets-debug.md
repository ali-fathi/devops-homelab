# Runbook: External Secrets Debug

This runbook explains how to debug `ExternalSecret`, `SecretStore`, and `ClusterSecretStore` issues.

Use this runbook when a Kubernetes Secret is not created or not updated by External Secrets Operator.

---

## Common Symptoms

```text
ExternalSecret not Ready
SecretSyncedError
Secret does not exist
Secret value is outdated
Application pod cannot read secret
Argo CD shows ExternalSecret OutOfSync
```

---

## Key Concepts

External Secrets Operator syncs secrets from an external provider into Kubernetes Secrets.

In this homelab, the external provider is usually:

```text
Azure Key Vault
```

Typical flow:

```text
Azure Key Vault
  -> ClusterSecretStore
  -> ExternalSecret
  -> Kubernetes Secret
  -> Application Pod
```

---

## Step 1: Check ExternalSecret Status

List all ExternalSecrets:

```bash
kubectl get externalsecret -A
```

Check a specific ExternalSecret:

```bash
kubectl get externalsecret <name> -n <namespace>
```

Example:

```bash
kubectl get externalsecret garmin-secrets -n garmin
```

Describe it:

```bash
kubectl describe externalsecret <name> -n <namespace>
```

Example:

```bash
kubectl describe externalsecret garmin-secrets -n garmin
```

Expected healthy condition:

```text
Type: Ready
Status: True
Reason: SecretSynced
```

---

## Step 2: Check Generated Kubernetes Secret

Check whether the target Kubernetes Secret exists:

```bash
kubectl get secret <secret-name> -n <namespace>
```

Example:

```bash
kubectl get secret garmin-secrets -n garmin
```

If the Secret exists, check metadata:

```bash
kubectl describe secret garmin-secrets -n garmin
```

Do not print secret values unless absolutely necessary.

If you must check keys only:

```bash
kubectl get secret garmin-secrets -n garmin -o jsonpath='{.data}' | jq keys
```

---

## Step 3: Check ClusterSecretStore

List stores:

```bash
kubectl get clustersecretstore
```

Describe Azure Key Vault store:

```bash
kubectl describe clustersecretstore azure-keyvault
```

Expected:

```text
Ready=True
```

If the store is not ready, check provider authentication, Key Vault URL, tenant ID, client ID, or referenced credentials.

---

## Step 4: Check External Secrets Operator Pods

Check pods:

```bash
kubectl get pods -n external-secrets-system
```

Expected:

```text
external-secrets pod Running
```

Check logs:

```bash
kubectl logs -n external-secrets-system deployment/external-secrets --since=30m
```

Search for errors:

```bash
kubectl logs -n external-secrets-system deployment/external-secrets --since=30m | grep -i error
```

---

## Step 5: Force ExternalSecret Refresh

Force refresh by annotating the ExternalSecret:

```bash
kubectl annotate externalsecret <name> \
  -n <namespace> \
  force-sync="$(date +%s)" \
  --overwrite
```

Example:

```bash
kubectl annotate externalsecret garmin-secrets \
  -n garmin \
  force-sync="$(date +%s)" \
  --overwrite
```

Then check status again:

```bash
kubectl describe externalsecret garmin-secrets -n garmin
```

---

## Step 6: Check Azure Key Vault Secret Names

Compare the ExternalSecret manifest keys with Azure Key Vault secret names.

Example manifest:

```yaml
remoteRef:
  key: garmin-connect-email
```

Azure Key Vault must contain:

```text
garmin-connect-email
```

If using Azure CLI:

```bash
az keyvault secret list \
  --vault-name <vault-name> \
  --query "[].name" \
  -o table
```

---

## Step 7: Check Garmin ExternalSecret

Garmin ExternalSecret path:

```text
kubernetes/applications/garmin/external-secret-garmin.yaml
```

Check manifest:

```bash
cat kubernetes/applications/garmin/external-secret-garmin.yaml
```

Expected target:

```yaml
target:
  name: garmin-secrets
```

Expected store:

```yaml
secretStoreRef:
  name: azure-keyvault
  kind: ClusterSecretStore
```

Check live resource:

```bash
kubectl describe externalsecret garmin-secrets -n garmin
```

Check generated Secret:

```bash
kubectl get secret garmin-secrets -n garmin
```

---

## Step 8: Argo CD OutOfSync but ExternalSecret Healthy

Sometimes Argo CD shows:

```text
ExternalSecret OutOfSync
Health: Healthy
```

This can happen when External Secrets Operator adds default fields such as:

```yaml
conversionStrategy: Default
decodingStrategy: None
metadataPolicy: None
```

Fix by adding those defaults to Git under each `remoteRef`.

Example:

```yaml
remoteRef:
  key: garmin-connect-email
  conversionStrategy: Default
  decodingStrategy: None
  metadataPolicy: None
```

Then commit and sync:

```bash
git add kubernetes/applications/garmin/external-secret-garmin.yaml
git commit -m "Fix Garmin ExternalSecret drift"
git push origin main
argocd app sync garmin
```

---

## Step 9: Common Error Messages

### Access denied

Possible causes:

```text
Wrong Azure service principal
Missing Key Vault permissions
Wrong tenant ID
Wrong client secret
Wrong Key Vault access policy or RBAC
```

### Secret not found

Possible causes:

```text
Wrong remoteRef key
Secret missing in Azure Key Vault
Wrong Key Vault name or URL
```

### ClusterSecretStore not ready

Possible causes:

```text
Provider auth problem
Referenced Kubernetes Secret missing
Wrong namespace for auth secret
Invalid provider configuration
```

---

## Recovery Checklist

```text
[ ] ExternalSecret exists.
[ ] ExternalSecret Ready=True.
[ ] Target Kubernetes Secret exists.
[ ] ClusterSecretStore Ready=True.
[ ] External Secrets Operator pod is Running.
[ ] Operator logs show no recent errors.
[ ] Azure Key Vault contains referenced keys.
[ ] Application pods can read generated Secret.
```

---

## Useful Commands

```bash
kubectl get externalsecret -A
kubectl describe externalsecret <name> -n <namespace>
kubectl get secret <secret-name> -n <namespace>
kubectl get clustersecretstore
kubectl describe clustersecretstore azure-keyvault
kubectl logs -n external-secrets-system deployment/external-secrets --since=30m
```