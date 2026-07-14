# Runbook: Argo CD App OutOfSync

## Symptoms
argocd app get <app-name>
argocd app diff <app-name>
argocd app resources <app-name>

Common causes

Git has changed but app is not synced
Live resource was manually modified
Controller added runtime fields
Argo CD is trying to process non-manifest files
App source path is wrong

argocd app get <app-name> --hard-refresh
argocd app diff <app-name>
argocd app sync <app-name>
