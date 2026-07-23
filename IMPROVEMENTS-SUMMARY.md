# Current implementation summary

The hardened coursework design improves the original repository in these areas:

- secure PHP CRUD behavior with validation, CSRF protection, prepared statements, encoded output, safe browser headers, and friendly failure pages;
- non-root Apache/PHP on port 8080, read-only runtime filesystems, authenticated Redis sessions, and dependency-aware readiness;
- one-control-plane/three-worker Kind topology with Calico NetworkPolicy enforcement;
- Kong Gateway API HTTPS routing, redirect, rate limiting, and correlation IDs;
- versioned database migrations, persistent MySQL/Redis, logical backup, and isolated restore validation;
- topology spreading, HPA, PDB, probes, rolling deployment, and continuity testing;
- restricted Pod Security and Kyverno controls for root, privilege, resources, and mutable tags;
- Prometheus, Grafana, Alertmanager, Loki, Alloy, and MySQL monitoring;
- Jenkins lint, test, Trivy, SBOM, immutable image, exact deployment, smoke check, and guarded rollback;
- evidence scripts that capture raw results, metadata, exit codes, timestamps, and hashes.

The architecture also states what is not solved: Kind remains one physical-host failure domain; MySQL and Redis are single replicas; local storage and TLS are coursework-grade; and image signing is not yet implemented.

Read [README.md](README.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), and [docs/DEMO-RUNBOOK.md](docs/DEMO-RUNBOOK.md) for the current source of truth.
