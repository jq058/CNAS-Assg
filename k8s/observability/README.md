# Observability profile

Install this profile with `scripts/Install-Observability.ps1`; do not add the directory directly to the core Kustomization. The Helm charts must install Prometheus Operator CRDs before the `Probe`, `ServiceMonitor`, and `PrometheusRule` resources are applied.

The profile supplies:

- Prometheus, Alertmanager, Grafana, kube-state-metrics and node-exporter;
- blackbox probes for the application readiness endpoint and Kong gateway;
- a least-privilege MySQL exporter account and ServiceMonitor;
- Loki with a non-root Alloy Kubernetes API log collector;
- a provisioned CNAS dashboard and actionable alert rules.

The Kind values favor low resource usage and 24-hour, ephemeral retention. See `docs/DEMO-RUNBOOK.md` for deployment, validation, evidence collection, and limitations.
