# Troubleshooting

## Verify Cluster

```bash
kubectl get nodes
```

## Verify Network

```bash
ping 192.168.178.80
```

## Verify API

```bash
kubectl --server=https://192.168.178.85:6443 get --raw=/readyz
```
