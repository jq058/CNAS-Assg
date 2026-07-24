# Quick start

Use this page for a fast local check. Use [the demonstration runbook](docs/DEMO-RUNBOOK.md) for graded Kubernetes evidence.

## Kubernetes coursework environment

Prerequisites: Docker Desktop, Kind, kubectl, Helm 3, and PowerShell 7.

**Step 1 — Create the platform**

~~~powershell
.\k8s\scripts\create-kind-cluster.ps1
~~~

**Step 2 — Bootstrap secrets and TLS**

~~~powershell
$env:DB_USER = "cnasuser"
$env:DB_PASSWORD = "<strong-database-password>"
$env:MYSQL_ROOT_PASSWORD = "<different-root-password>"
$env:REDIS_PASSWORD = "<different-redis-password>"

.\k8s\scripts\bootstrap-secrets.ps1
.\k8s\scripts\bootstrap-local-tls.ps1
~~~

Add `127.0.0.1 cnas.local` to the workstation hosts file.

**Step 3 — Deploy via Jenkins**

Trigger a Jenkins pipeline build. The pipeline builds, scans, pushes, deploys, and verifies the application. See [docs/CI-CD.md](docs/CI-CD.md) for credential IDs and agent prerequisites.

**Step 4 — Install monitoring**

~~~powershell
.\scripts\Install-Observability.ps1
~~~

Read [the platform runbook](k8s/PLATFORM.md) for platform safeguards and [the demonstration runbook](docs/DEMO-RUNBOOK.md) for security, scaling, resilience, monitoring, backup, and evidence checks.
