# Loki LogQL Cheatsheet

This file contains useful LogQL queries for the homelab logging stack.

Grafana Alloy is the current Kubernetes log collector. Some older headings below retain the word `Promtail` because the queries and troubleshooting concepts were originally written for that collector; use Alloy Pods and Alloy configuration for current operations.

Stack:

```text
K3s
MetalLB
Longhorn
Prometheus
Grafana
Alertmanager
Loki
Grafana Alloy
Telegram Alerts
```

Grafana URL:

```text
http://192.168.178.212
```

Loki is normally accessed through Grafana:

```text
Grafana
  → Explore
  → Datasource: Loki
```

---

# 1. Basic LogQL Syntax

## Show all logs

```logql
{}
```

Use carefully. This can return a lot of logs.

---

## Show logs from one namespace

```logql
{namespace="monitoring"}
```

---

## Show logs from one pod

```logql
{pod="POD_NAME"}
```

Example:

```logql
{pod="monitoring-grafana-79765ff678-vw4dg"}
```

---

## Show logs from one container

```logql
{container="grafana"}
```

---

## Show logs from one node

```logql
{node_name="k3s-worker1"}
```

---

## Show logs from one namespace and container

```logql
{namespace="monitoring", container="grafana"}
```

---

# 2. Common Namespace Queries

## Monitoring stack logs

```logql
{namespace="monitoring"}
```

Useful for:

```text
Grafana
Prometheus
Alertmanager
kube-state-metrics
node-exporter
```

---

## Longhorn logs

```logql
{namespace="longhorn-system"}
```

Useful for:

```text
Longhorn Manager
Longhorn CSI
Longhorn UI
Longhorn Engine
Longhorn Replicas
```

---

## MetalLB logs

```logql
{namespace="metallb-system"}
```

Useful for:

```text
MetalLB controller
MetalLB speakers
LoadBalancer IP issues
ARP/L2 advertisement issues
```

---

## Kube-system logs

```logql
{namespace="kube-system"}
```

Useful for:

```text
CoreDNS
Traefik
Metrics server
K3s system components
```

---

## Logging stack logs

```logql
{namespace="logging"}
```

Useful for:

```text
Loki
Promtail
Loki gateway
Loki ruler
```

---

## Default namespace logs

```logql
{namespace="default"}
```

Useful for test applications and temporary workloads.

---

# 3. Error Search Queries

## All logs containing error

```logql
{} |= "error"
```

---

## Case-insensitive error search

```logql
{} |~ "(?i)error"
```

---

## Errors from monitoring namespace

```logql
{namespace="monitoring"} |~ "(?i)error"
```

---

## Errors from Longhorn

```logql
{namespace="longhorn-system"} |~ "(?i)error"
```

---

## Errors from logging stack

```logql
{namespace="logging"} |~ "(?i)error"
```

---

## Errors from kube-system

```logql
{namespace="kube-system"} |~ "(?i)error"
```

---

# 4. Warning Search Queries

## All warnings

```logql
{} |~ "(?i)warn|warning"
```

---

## Warnings from monitoring namespace

```logql
{namespace="monitoring"} |~ "(?i)warn|warning"
```

---

## Warnings from Longhorn

```logql
{namespace="longhorn-system"} |~ "(?i)warn|warning"
```

---

# 5. Failure Search Queries

## Failed or failure messages

```logql
{} |~ "(?i)failed|failure"
```

---

## Failed messages from Longhorn

```logql
{namespace="longhorn-system"} |~ "(?i)failed|failure"
```

---

## Failed messages from monitoring

```logql
{namespace="monitoring"} |~ "(?i)failed|failure"
```

---

# 6. Critical / Fatal / Panic Queries

## Critical logs

```logql
{} |~ "(?i)critical"
```

---

## Fatal logs

```logql
{} |~ "(?i)fatal"
```

---

## Panic logs

```logql
{} |~ "(?i)panic"
```

---

## Critical, fatal, or panic logs

```logql
{} |~ "(?i)critical|fatal|panic"
```

---

# 7. Timeout Queries

## Timeout logs

```logql
{} |~ "(?i)timeout|timed out"
```

---

## Timeout logs from monitoring

```logql
{namespace="monitoring"} |~ "(?i)timeout|timed out"
```

---

## Timeout logs from Longhorn

```logql
{namespace="longhorn-system"} |~ "(?i)timeout|timed out"
```

---

# 8. Kubernetes Failure Queries

## CrashLoopBackOff messages

```logql
{} |= "CrashLoopBackOff"
```

---

## ImagePullBackOff messages

```logql
{} |= "ImagePullBackOff"
```

---

## ErrImagePull messages

```logql
{} |= "ErrImagePull"
```

---

## OOMKilled messages

```logql
{} |~ "(?i)oom|oomkilled|out of memory"
```

---

## Permission denied messages

```logql
{} |~ "(?i)permission denied"
```

---

## Connection refused messages

```logql
{} |~ "(?i)connection refused"
```

---

## No route to host messages

```logql
{} |~ "(?i)no route to host"
```

---

## DNS failure messages

```logql
{} |~ "(?i)dns|lookup|no such host|server misbehaving"
```

---

# 9. Longhorn-Specific Queries

## All Longhorn logs

```logql
{namespace="longhorn-system"}
```

---

## Longhorn errors

```logql
{namespace="longhorn-system"} |~ "(?i)error"
```

---

## Longhorn degraded volume messages

```logql
{namespace="longhorn-system"} |~ "(?i)degraded"
```

---

## Longhorn replica messages

```logql
{namespace="longhorn-system"} |~ "(?i)replica"
```

---

## Longhorn volume attach/detach logs

```logql
{namespace="longhorn-system"} |~ "(?i)attach|detach"
```

---

## Longhorn disk pressure / space logs

```logql
{namespace="longhorn-system"} |~ "(?i)disk|space|capacity|storage"
```

---

## Longhorn CSI logs

```logql
{namespace="longhorn-system", pod=~".*csi.*"}
```

---

## Longhorn manager logs

```logql
{namespace="longhorn-system", pod=~".*longhorn-manager.*"}
```

---

## Longhorn UI logs

```logql
{namespace="longhorn-system", pod=~".*longhorn-ui.*"}
```

---

# 10. Monitoring Stack Queries

## Grafana logs

```logql
{namespace="monitoring", pod=~".*grafana.*"}
```

---

## Grafana errors

```logql
{namespace="monitoring", pod=~".*grafana.*"} |~ "(?i)error|failed|panic"
```

---

## Prometheus logs

```logql
{namespace="monitoring", pod=~".*prometheus.*"}
```

---

## Prometheus errors

```logql
{namespace="monitoring", pod=~".*prometheus.*"} |~ "(?i)error|failed|timeout"
```

---

## Alertmanager logs

```logql
{namespace="monitoring", pod=~".*alertmanager.*"}
```

---

## Alertmanager notification errors

```logql
{namespace="monitoring", pod=~".*alertmanager.*"} |~ "(?i)notify|notification|telegram|failed|error"
```

---

## Prometheus Operator logs

```logql
{namespace="monitoring", pod=~".*operator.*"}
```

---

## Prometheus Operator errors

```logql
{namespace="monitoring", pod=~".*operator.*"} |~ "(?i)error|failed|reconcile"
```

---

# 11. Loki / Promtail Queries

## Loki logs

```logql
{namespace="logging", pod=~".*loki.*"}
```

---

## Loki errors

```logql
{namespace="logging", pod=~".*loki.*"} |~ "(?i)error|failed|panic"
```

---

## Loki ruler logs

```logql
{namespace="logging", pod=~".*loki.*"} |~ "(?i)ruler|rule|alertmanager"
```

---

## Promtail logs

```logql
{namespace="logging", pod=~".*promtail.*"}
```

---

## Promtail errors

```logql
{namespace="logging", pod=~".*promtail.*"} |~ "(?i)error|failed|client|push"
```

---

## Promtail push errors

```logql
{namespace="logging", pod=~".*promtail.*"} |~ "(?i)final error sending batch|server returned|failed to send"
```

---

# 12. MetalLB Queries

## MetalLB logs

```logql
{namespace="metallb-system"}
```

---

## MetalLB controller logs

```logql
{namespace="metallb-system", pod=~".*controller.*"}
```

---

## MetalLB speaker logs

```logql
{namespace="metallb-system", pod=~".*speaker.*"}
```

---

## MetalLB errors

```logql
{namespace="metallb-system"} |~ "(?i)error|failed|timeout"
```

---

## MetalLB IP allocation logs

```logql
{namespace="metallb-system"} |~ "(?i)assign|allocated|address|pool"
```

---

# 13. Traefik Queries

## Traefik logs

```logql
{namespace="kube-system", pod=~".*traefik.*"}
```

---

## Traefik errors

```logql
{namespace="kube-system", pod=~".*traefik.*"} |~ "(?i)error|failed|timeout|bad gateway"
```

---

## HTTP 5xx logs

```logql
{namespace="kube-system", pod=~".*traefik.*"} |~ " 5[0-9][0-9] "
```

---

## HTTP 404 logs

```logql
{namespace="kube-system", pod=~".*traefik.*"} |~ " 404 "
```

---

# 14. Rate and Count Queries

## Count all error logs over 5 minutes by namespace

```logql
sum by(namespace) (
  count_over_time({namespace!=""} |~ "(?i)error" [5m])
)
```

---

## Count all warning logs over 5 minutes by namespace

```logql
sum by(namespace) (
  count_over_time({namespace!=""} |~ "(?i)warn|warning" [5m])
)
```

---

## Count failed logs over 5 minutes by pod

```logql
sum by(namespace, pod) (
  count_over_time({namespace!=""} |~ "(?i)failed|failure" [5m])
)
```

---

## Count timeout logs over 5 minutes by pod

```logql
sum by(namespace, pod) (
  count_over_time({namespace!=""} |~ "(?i)timeout|timed out" [5m])
)
```

---

## Count critical logs over 5 minutes by namespace

```logql
sum by(namespace) (
  count_over_time({namespace!=""} |~ "(?i)critical|fatal|panic" [5m])
)
```

---

## Error rate by namespace

```logql
sum by(namespace) (
  rate({namespace!=""} |~ "(?i)error" [5m])
)
```

---

## Error rate by pod

```logql
sum by(namespace, pod) (
  rate({namespace!=""} |~ "(?i)error" [5m])
)
```

---

# 15. Alert Testing Queries

Use these when testing Loki alert rules.

## Test if error logs exist

```logql
sum by(namespace, pod, container) (
  count_over_time({namespace!=""} |= "error" [5m])
)
```

---

## Test if critical logs exist

```logql
sum by(namespace, pod, container) (
  count_over_time({namespace!=""} |~ "(?i)critical|fatal|panic" [5m])
)
```

---

## Test Longhorn alert query

```logql
sum by(namespace, pod, container) (
  count_over_time(
    {namespace="longhorn-system"}
    |~ "(?i)error|failed|degraded|replica"
    [5m]
  )
)
```

---

## Test monitoring stack alert query

```logql
sum by(namespace, pod, container) (
  count_over_time(
    {namespace="monitoring"}
    |~ "(?i)error|failed|panic|exception"
    [5m]
  )
)
```

---

## Test logging stack alert query

```logql
sum by(namespace, pod, container) (
  count_over_time(
    {namespace="logging"}
    |~ "(?i)error|failed|panic|exception"
    [5m]
  )
)
```

---

# 16. Generate Test Logs

## Generate an error log

```bash
kubectl run loki-error-test \
  --image=busybox:1.36 \
  --restart=Never \
  -- sh -c 'echo "error: this is a Loki alert test"; sleep 300'
```

Query:

```logql
{pod="loki-error-test"}
```

Then:

```logql
{pod="loki-error-test"} |= "error"
```

Cleanup:

```bash
kubectl delete pod loki-error-test
```

---

## Generate a fatal log

```bash
kubectl run loki-fatal-test \
  --image=busybox:1.36 \
  --restart=Never \
  -- sh -c 'echo "fatal: this is a critical Loki alert test"; sleep 300'
```

Query:

```logql
{pod="loki-fatal-test"} |~ "(?i)fatal"
```

Cleanup:

```bash
kubectl delete pod loki-fatal-test
```

---

## Generate a timeout log

```bash
kubectl run loki-timeout-test \
  --image=busybox:1.36 \
  --restart=Never \
  -- sh -c 'echo "timeout: upstream service timed out"; sleep 300'
```

Query:

```logql
{pod="loki-timeout-test"} |~ "(?i)timeout|timed out"
```

Cleanup:

```bash
kubectl delete pod loki-timeout-test
```

---

# 17. Recommended Alerts Based on Queries

## Warning: Error burst

```logql
sum by(namespace, pod, container) (
  count_over_time({namespace!=""} |~ "(?i)error" [5m])
) > 5
```

---

## Critical: Fatal or panic log

```logql
sum by(namespace, pod, container) (
  count_over_time({namespace!=""} |~ "(?i)fatal|panic|critical" [5m])
) > 0
```

---

## Warning: Timeout logs

```logql
sum by(namespace, pod, container) (
  count_over_time({namespace!=""} |~ "(?i)timeout|timed out" [5m])
) > 3
```

---

## Critical: Longhorn error logs

```logql
sum by(namespace, pod, container) (
  count_over_time(
    {namespace="longhorn-system"}
    |~ "(?i)error|failed|degraded|replica"
    [5m]
  )
) > 0
```

---

## Warning: Monitoring stack errors

```logql
sum by(namespace, pod, container) (
  count_over_time(
    {namespace="monitoring"}
    |~ "(?i)error|failed|panic|exception"
    [5m]
  )
) > 0
```

---

## Warning: Logging stack errors

```logql
sum by(namespace, pod, container) (
  count_over_time(
    {namespace="logging"}
    |~ "(?i)error|failed|panic|exception"
    [5m]
  )
) > 0
```

---

# 18. Best Practices

## Use low-cardinality labels

Good labels:

```text
namespace
pod
container
node_name
app
```

Avoid using labels like:

```text
request_id
user_id
session_id
trace_id
full_url
timestamp
```

High-cardinality labels can make Loki slower and more expensive.

---

## Start broad, then narrow

Start with:

```logql
{namespace="monitoring"}
```

Then narrow:

```logql
{namespace="monitoring", pod=~".*grafana.*"} |= "error"
```

---

## Avoid alerting on every single error

This can be noisy:

```logql
{} |= "error"
```

Better:

```logql
sum by(namespace, pod, container) (
  count_over_time({namespace!=""} |~ "(?i)error" [5m])
) > 5
```

---

## Use critical alerts only for severe patterns

Good critical patterns:

```text
fatal
panic
critical
degraded
replica failure
out of memory
```

---

## Use warning alerts for repeated patterns

Good warning patterns:

```text
error burst
timeout burst
failed requests
repeated retries
```

---

# 19. Troubleshooting Queries

## Is Promtail collecting logs?

```logql
{namespace="logging", pod=~".*promtail.*"}
```

---

## Is Loki producing logs?

```logql
{namespace="logging", pod=~".*loki.*"}
```

---

## Are logs arriving from all namespaces?

```logql
sum by(namespace) (
  count_over_time({namespace!=""} [5m])
)
```

---

## Are logs arriving from all nodes?

```logql
sum by(node_name) (
  count_over_time({node_name!=""} [5m])
)
```

---

## Which namespace is producing most logs?

```logql
topk(10,
  sum by(namespace) (
    count_over_time({namespace!=""} [5m])
  )
)
```

---

## Which pod is producing most logs?

```logql
topk(10,
  sum by(namespace, pod) (
    count_over_time({namespace!=""} [5m])
  )
)
```

---

## Which pod is producing most errors?

```logql
topk(10,
  sum by(namespace, pod) (
    count_over_time({namespace!=""} |~ "(?i)error" [5m])
  )
)
```

---

# 20. Useful kubectl Commands

## Check Loki

```bash
kubectl get pods -n logging
```

---

## Check Promtail

```bash
kubectl get daemonset -n logging
```

---

## Check Loki logs

```bash
kubectl logs -n logging statefulset/loki
```

---

## Check Promtail logs

```bash
kubectl logs -n logging daemonset/promtail
```

---

## Check Loki services

```bash
kubectl get svc -n logging
```

---

## Check Loki PVC

```bash
kubectl get pvc -n logging
```

---

## Check Loki events

```bash
kubectl get events -n logging --sort-by=.metadata.creationTimestamp
```

---

# Summary

This cheatsheet helps with:

```text
Debugging applications
Searching errors
Investigating alerts
Monitoring Longhorn logs
Monitoring Prometheus/Grafana logs
Testing Loki alert rules
Finding noisy pods
Finding failing workloads
Building LogQL-based alerts
```

Loki + Promtail + Grafana gives the homelab a searchable logging platform.

Loki Ruler + Alertmanager + Telegram turns important log patterns into real-time notifications.
