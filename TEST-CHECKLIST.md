# Evidence checklist

Use this checklist with [docs/DEMO-RUNBOOK.md](docs/DEMO-RUNBOOK.md).

## Source and local application

- [ ] Record the tested Git commit.
- [ ] Docker Compose renders without secrets committed.
- [ ] Application image builds as non-root on port 8080.
- [ ] PHP lint and all unit tests pass.
- [ ] Compose web, MySQL, and Redis become healthy.
- [ ] Create, read, update, delete, duplicate-email, and invalid-input behavior are observed.
- [ ] Liveness and dependency readiness behave differently during a dependency failure.

## Kubernetes platform

- [ ] One control plane and three Kind workers are Ready.
- [ ] Calico is installed and default kindnet is disabled.
- [ ] Kong, Gateway API, Kyverno, and Metrics Server are Ready.
- [ ] Runtime credentials and TLS were bootstrapped outside Git.
- [ ] Versioned database migration completes.
- [ ] Three PHP replicas are ready and spread across workers where capacity permits.
- [ ] MySQL and Redis persistence is demonstrated without claiming data-tier HA.

## Security and resilience

- [ ] HTTPS route, HTTP redirect, request ID, and rate limiting are observed.
- [ ] Untrusted MySQL access is denied by NetworkPolicy.
- [ ] Allowed gateway, PHP, data, DNS, monitoring, and validation flows succeed.
- [ ] Insecure admission fixtures are rejected by Kyverno or Pod Security as documented.
- [ ] A PHP Pod is deleted, replaced, and requests continue without failure.
- [ ] A rolling update and rollback are demonstrated.
- [ ] HPA scales above the minimum under measured load and later scales down.

## Monitoring, recovery, and delivery

- [ ] Prometheus targets are healthy and the Grafana dashboard has live data.
- [ ] Loki contains scoped application/gateway/platform logs.
- [ ] A safe alert drill fires and clears.
- [ ] MySQL backup has a timestamp and SHA-256 digest.
- [ ] Backup restores successfully into an isolated temporary database.
- [ ] Jenkins shows lint, test, scan, SBOM, immutable push, rollout, and smoke stages.
- [ ] Running Deployment annotations and image match the Git commit/build.
- [ ] Evidence files include commands, exit codes, timestamps, actual outcomes, and hashes.
- [ ] Personal data and credentials are redacted before report submission.
- [ ] Limitations are stated honestly.
