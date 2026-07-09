# Check Argo CD
kubectl get pods -n argocd
kubectl get svc argocd-server -n argocd

# Login
argocd login 192.168.178.213 --username admin --password '<PASSWORD>' --insecure

# Apply GitOps resources
kubectl apply -f kubernetes/gitops/argocd/repositories/external-secret-git-repo.yaml
kubectl apply -f kubernetes/gitops/argocd/projects/homelab-platform-project.yaml
kubectl apply -f kubernetes/gitops/argocd/applications/garmin.yaml

# Commit and push
git add kubernetes/gitops/argocd
git commit -m "Bootstrap Argo CD GitOps with MetalLB access"
git push origin main

# Verify
argocd app list
argocd app get garmin
argocd app resources garmin
kubectl get pods -n garmin

# Argocd commands
argocd app list
argocd app get garmin
argocd app diff garmin
argocd app sync garmin
argocd app resources garmin

