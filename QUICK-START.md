# Quick start

Use this page for a fast local check. Use [the demonstration runbook](docs/DEMO-RUNBOOK.md) for graded Kubernetes evidence.

## Docker Compose

Prerequisite: Docker Desktop with Compose v2.

~~~powershell
Copy-Item .env.example .env
~~~

Open .env and replace all three password placeholders with different long random values. Then run:

~~~powershell
docker compose up -d --build
docker compose ps
curl.exe http://localhost:8080/livez.php
curl.exe http://localhost:8080/readyz.php
~~~

Open http://localhost:8080 and verify create, read, update, and delete.

Keep the data and stop:

~~~powershell
docker compose down
~~~

Erase the local database/session volumes only when a clean reset is intended:

~~~powershell
docker compose down -v
~~~

## Kubernetes coursework environment

Prerequisites: Docker Desktop, Kind, kubectl, Helm 3, and PowerShell 7.

~~~powershell
.\k8s\scripts\create-kind-cluster.ps1

$env:DB_USER = "cnasuser"
$env:DB_PASSWORD = "<strong-database-password>"
$env:MYSQL_ROOT_PASSWORD = "<different-root-password>"
$env:REDIS_PASSWORD = "<different-redis-password>"

.\k8s\scripts\bootstrap-secrets.ps1
.\k8s\scripts\bootstrap-local-tls.ps1

docker build -t jqii/cnas-php-app:bootstrap .
kind load docker-image jqii/cnas-php-app:bootstrap --name cnas-cluster
kubectl apply -k k8s

kubectl -n cnas wait --for=condition=complete job/db-migration-v2 --timeout=300s
kubectl -n cnas rollout status deployment/php-app --timeout=300s
kubectl -n cnas get pods -o wide
~~~

Add 127.0.0.1 cnas.local to the workstation hosts file, then open https://cnas.local. The local certificate is self-signed by design.

Read [the platform runbook](k8s/PLATFORM.md) for the platform safeguards and [the demonstration runbook](docs/DEMO-RUNBOOK.md) for security, scaling, resilience, monitoring, backup/restore, and evidence checks.
