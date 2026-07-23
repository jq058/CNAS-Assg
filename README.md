# CNAS cloud-native application

A secure PHP and MySQL CRUD application designed to demonstrate the CNAS assignment requirements with repeatable evidence. The repository contains a local Docker Compose profile, a multi-node Kind platform, Kubernetes security and resilience controls, observability, automated tests, and a gated Jenkins delivery pipeline.

## Architecture

~~~mermaid
flowchart LR
    user[User] -->|HTTPS| kong[Kong Gateway]
    kong --> service[PHP Service]
    service --> php1[PHP Pod 1]
    service --> php2[PHP Pod 2]
    service --> php3[PHP Pod 3]
    php1 --> mysql[(MySQL PVC)]
    php2 --> mysql
    php3 --> mysql
    php1 --> redis[(Redis sessions)]
    php2 --> redis
    php3 --> redis
    jenkins[Jenkins and Trivy] --> registry[Immutable image]
    registry --> php1
    prometheus[Prometheus and Grafana] -. metrics .-> service
    alloy[Alloy and Loki] -. logs .-> php1
~~~

The coursework profile uses:

- one Kind control-plane node and three worker nodes;
- Calico so NetworkPolicy is actually enforced;
- Kong and Kubernetes Gateway API for HTTPS, redirect, rate limiting, request IDs, and routing;
- three non-root PHP/Apache replicas on port 8080 with liveness and dependency-aware readiness probes;
- password-protected Redis for shared PHP sessions;
- MySQL as a StatefulSet with persistent storage, versioned schema migration, logical backups, and a restore test;
- HPA, topology spreading, rolling updates, and a PodDisruptionBudget;
- restricted Pod Security plus Kyverno admission policies;
- Prometheus, Alertmanager, Grafana, Loki, Alloy, and a MySQL exporter;
- Jenkins gates for linting, tests, Trivy scans, SBOM generation, immutable image delivery, smoke tests, and guarded rollback.

See [Architecture](docs/ARCHITECTURE.md) for trust boundaries, deployment decisions, requirement mapping, and honest limitations.

## Local Docker Compose check

Prerequisites: Docker Desktop with Compose v2.

1. Copy .env.example to .env.
2. Replace every placeholder password with a different long random value.
3. Start the stack.

~~~powershell
Copy-Item .env.example .env
docker compose up -d --build
docker compose ps
~~~

Open http://localhost:8080 and test create, read, update, and delete. The health endpoints are:

~~~powershell
curl.exe http://localhost:8080/livez.php
curl.exe http://localhost:8080/readyz.php
~~~

Stop the stack while keeping data:

~~~powershell
docker compose down
~~~

Only use docker compose down -v when you intentionally want to erase the local MySQL and Redis volumes.

## Automated application checks

Run the same dependency-free PHP suite used by CI:

~~~powershell
docker run --rm --entrypoint sh -v "${PWD}:/workspace:ro" -w /workspace php:8.2-cli-alpine -c "find php-app tests/php -name '*.php' -print0 | xargs -0 -n1 php -l && php tests/php/run.php"
~~~

The tests cover output encoding, validation, database field limits, UTF-8 handling, strict identifier parsing, and CSRF-token comparison.

## Kubernetes coursework profile

Prerequisites: Docker Desktop, Kind, kubectl, Helm 3, OpenSSL, and PowerShell 7 or Bash.

Create the pinned four-node cluster and install Calico, Gateway API, Kong, Kyverno, and Metrics Server:

~~~powershell
.\k8s\scripts\create-kind-cluster.ps1
~~~

Set strong runtime credentials in the current terminal and bootstrap them without writing a populated Secret manifest:

~~~powershell
$env:DB_USER = "cnasuser"
$env:DB_PASSWORD = "<strong-database-password>"
$env:MYSQL_ROOT_PASSWORD = "<different-root-password>"
$env:REDIS_PASSWORD = "<different-redis-password>"
.\k8s\scripts\bootstrap-secrets.ps1
.\k8s\scripts\bootstrap-local-tls.ps1
~~~

Build and load the local bootstrap image, then deploy the Kustomize base:

~~~powershell
docker build -t jqii/cnas-php-app:bootstrap .
kind load docker-image jqii/cnas-php-app:bootstrap --name cnas-cluster
kubectl apply -k k8s
kubectl -n cnas wait --for=condition=complete job/db-migration-v2 --timeout=300s
kubectl -n cnas rollout status deployment/php-app --timeout=300s
kubectl -n cnas get pods -o wide
~~~

For the local TLS demonstration, map cnas.local to 127.0.0.1 in the workstation hosts file, then open https://cnas.local. The certificate is intentionally self-signed for Kind only.

The platform scripts refuse to modify a cluster whose current context is not kind-cnas-cluster. Read [Kubernetes platform runbook](k8s/PLATFORM.md) before deployment.

## Evidence and marking demonstrations

Use the evidence-first [validation and demonstration runbook](docs/DEMO-RUNBOOK.md). It provides repeatable checks for:

- readiness, HTTPS gateway routing, redirect, request ID, and rate limiting;
- create/read/update/delete smoke behavior;
- Calico NetworkPolicy denial;
- Pod Security and Kyverno rejection tests;
- HPA scale-out and scale-down;
- Pod deletion, replacement, and request continuity;
- MySQL backup and restored via the CronJob;
- dashboard, log, and alert evidence;
- Git-to-image-to-running-Deployment traceability.

The collector stores command outputs, timestamps, exit codes, metadata, and SHA-256 hashes under the ignored evidence directory. It intentionally excludes Kubernetes Secrets. Never claim a result that was not observed, and redact personal data before adding evidence to the report.

## CI/CD

The [Jenkins guide](docs/CI-CD.md) lists agent prerequisites, exact credential IDs, pipeline gates, deployment traceability, and rollback boundaries. Jenkins builds one tag in the form build-number plus Git SHA, scans it, creates a CycloneDX SBOM, pushes that exact image, and verifies that exact image after rollout. It never publishes latest.

## Security highlights

- No populated Secret manifest is committed.
- PHP runs as www-data on unprivileged port 8080.
- Mutation routes require POST and a valid CSRF token.
- Database access uses prepared statements and strict validation.
- Browser output is encoded and security headers include CSP.
- Application containers drop Linux capabilities, prevent privilege escalation, and use a read-only root filesystem.
- Default-deny network policies allow only documented DNS, gateway, application, data, test, and monitoring flows.
- Images and chart/controller versions are pinned; CI rejects HIGH or CRITICAL scan findings.

## Deliberate limitations

This is an honest single-laptop coursework environment, not a production claim:

- Kind nodes are containers on one physical host.
- MySQL and Redis each have one replica.
- local persistent volumes are not multi-zone storage;
- local TLS is self-signed;
- Prometheus, Loki, and Grafana use low-resource ephemeral storage;
- image signing and admission-time signature verification remain stretch improvements.
- the coursework CRUD interface does not implement user authentication or role-based authorization;
- the application, migration, and backup tasks share one database identity instead of separate least-privilege accounts.

These boundaries are important in the report: the web tier demonstrates redundancy and recovery, while the complete system is not fully highly available.

## Repository guide

| Path | Purpose |
|---|---|
| php-app | PHP application, Apache configuration, health endpoints, and security controls |
| db | Local Compose initialization schema |
| k8s | Core manifests, Kustomize base, platform bootstrap, gateway, policies, and observability |
| tests/php | Fast application security and validation tests |
| tests/k8s | Smoke, load, continuity, network, and negative admission fixtures |
| scripts | Validation, evidence, load, failover, observability, and backup/restore tools |
| docs | Architecture, CI/CD, and demonstration runbooks |
| Jenkinsfile | DevSecOps build, scan, publish, deploy, verify, and rollback pipeline |

## Team ownership

| Member | Primary area |
|---|---|
| Ee Ting Li | Application, MySQL, Docker, and Compose |
| Lau Jia Qi | Kubernetes platform, services, gateway, scaling, and storage |
| Chee Hsiao En Samuela | CI/CD, security, policies, and secret handling |
| Janice Oh Shi Ting | Observability, validation evidence, demonstration, and report coordination |

The team should cross-review every area because the final demonstration and report depend on end-to-end behavior.
