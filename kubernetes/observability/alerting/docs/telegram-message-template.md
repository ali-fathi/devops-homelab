# Telegram Alert Template

🔥 CRITICAL ALERT

Cluster:
{{ .CommonLabels.cluster }}

Alert:
{{ .CommonLabels.alertname }}

Severity:
{{ .CommonLabels.severity }}

Namespace:
{{ .CommonLabels.namespace }}

Started:
{{ .StartsAt }}

Description:
{{ .CommonAnnotations.description }}

Status:
{{ .Status }}

Dashboard:
{{ .GeneratorURL }}
