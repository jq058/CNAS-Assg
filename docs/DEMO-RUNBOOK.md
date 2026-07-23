# CNAS validation and demonstration runbook

This runbook turns the assignment claims into repeatable checks and raw evidence. Run it from the repository root against a disposable Kind cluster. Record the Git commit, cluster context, command, timestamp, expected outcome, and actual outcome. Do not claim a pass when a command fails, and do not fabricate screenshots.

## 1. Preconditions

- `kubectl` is connected to the intended Kind cluster.
- Helm 3 is installed for the observability stack.
- The `cnas` application, Kong Gateway, Kyverno policies, metrics-server, and a NetworkPolicy-capable CNI are deployed.
- The application image uses an immutable version or digest rather than `latest`.
- `php-app`, `mysql`, and Kong are ready before validation begins.

Confirm the target before making changes:

```powershell
kubectl config current-context
kubectl get nodes -o wide
kubectl -n cnas get pods -o wide
kubectl -n kong get pods -o wide
```

The default Kind `kindnet` networking does not enforce Kubernetes NetworkPolicy. Install and verify the CNI selected by the project before presenting the NetworkPolicy test as evidence.

## 2. Install observability

The installer uses these pinned Helm chart versions:

| Component | Chart/version |
|---|---|
| Prometheus Operator, Prometheus, Alertmanager, Grafana, kube-state-metrics and node-exporter | `prometheus-community/kube-prometheus-stack` `86.0.0` |
| Loki | `grafana-community/loki` `18.5.1` |
| Alloy log collector | Container `grafana/alloy:v1.16.1` |
| MySQL exporter | Container `prom/mysqld-exporter:v0.19.0` |

Install the stack:

```powershell
.\scripts\Install-Observability.ps1
```

The script generates—not commits—random Grafana and MySQL exporter credentials. It creates a least-privilege MySQL monitoring account, deploys the exporters, and waits for readiness.

Open Grafana locally:

```powershell
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

In another PowerShell window, retrieve the generated password without putting it in the report:

```powershell
$encoded = kubectl -n monitoring get secret cnas-grafana-admin -o 'jsonpath={.data.admin-password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

The dashboard **CNAS Application, Gateway, MySQL and Cluster Overview** covers:

- internal application and external gateway availability;
- HTTP response time;
- desired/current HPA replicas;
- PHP CPU, memory, and restarts;
- MySQL availability, connections, query rate, and PVC utilization;
- consolidated workload logs from Loki.

Prometheus rules alert on application/gateway outages, missing replicas, repeated restarts, prolonged maximum HPA scale, MySQL failure or connection pressure, low storage, pending PVCs, and NotReady nodes.

## 3. Baseline validation

Run all readiness, route, NetworkPolicy, Kyverno, and observability checks:

```powershell
.\scripts\Invoke-CnasValidation.ps1
```

Expected results:

| Check | Expected outcome |
|---|---|
| Deployment and StatefulSet readiness | All desired replicas are ready |
| Service health | `readyz.php` reports ready |
| Gateway route | HTTPS Kong route with `Host: cnas.local` returns the application |
| Gateway controls | HTTP redirects to HTTPS, responses contain `X-Request-ID`, and excess traffic receives HTTP 429 |
| Gateway-to-backend load balancing | 50 uniquely marked HTTPS requests appear in Apache access logs for at least two distinct PHP Pods |
| MySQL isolation | An untrusted Pod cannot connect to port 3306 |
| Admission negative tests | Latest-tag and resource fixtures are rejected by their named Kyverno policies; overlapping root/privileged controls may be rejected earlier by Pod Security Admission |
| Observability | Prometheus, Alertmanager, Alloy, and MySQL exporter are ready |

Admission tests use server-side dry runs, so deliberately invalid Pods are never created. The script reports whether Kyverno or Pod Security Admission performed the rejection. The normal smoke, load, and continuity Jobs include non-root security contexts, dropped capabilities, immutable image tags, and CPU/memory limits.

If the NetworkPolicy test can reach MySQL, treat that as a failed control. Do not describe the YAML alone as enforced security; fix the CNI or policy and rerun the test.

## 4. CI smoke test

Jenkins can call the Linux-compatible test after a successful rollout:

```bash
bash ./scripts/ci-smoke-test.sh
```

The script waits for the application and database, then creates a Kyverno-compliant Job. It verifies:

1. application readiness through the ClusterIP Service;
2. application routing through Kong HTTPS;
3. create, read, update, and delete through HTTPS Kong with a persisted Secure session cookie;
4. cleanup of the test record.

Environment overrides are available for `NAMESPACE`, `SERVICE_URL`, `GATEWAY_URL`, `GATEWAY_HOST`, and `ROLLOUT_TIMEOUT`. The Kind gateway uses a self-signed demonstration certificate, so the internal gateway check disables certificate verification. Production must use a trusted certificate and must not use this exception.

## 5. Scaling exercise

```powershell
.\scripts\Invoke-LoadTest.ps1
```

The resource-limited load Job makes concurrent requests for three minutes while the script records current replicas, desired replicas, and CPU utilization every ten seconds. A pass requires HPA to scale above `minReplicas`. Evidence is written below `evidence/load-<UTC timestamp>/`.

If no scale-out occurs, inspect all three prerequisites instead of increasing traffic blindly:

```powershell
kubectl top pods -n cnas
kubectl describe hpa php-app-hpa -n cnas
kubectl get apiservice v1beta1.metrics.k8s.io
```

After the test, wait for the configured stabilization window and capture scale-down evidence as well.

## 6. Resilience exercise

Preview the controlled action:

```powershell
.\scripts\Invoke-FailoverTest.ps1
```

Run it only in the demonstration cluster:

```powershell
.\scripts\Invoke-FailoverTest.ps1 -Execute
```

The script sends 60 requests through the Service, deletes one exact PHP Pod, waits for the Deployment to replace it, and fails if any request fails. Evidence records the deleted Pod UID/node, recovery time, request log, replacement Pod, and final Service endpoints.

This proves application Pod self-healing and Service continuity. It does **not** prove physical-host high availability, because all Kind nodes run on one host, and it does not make the single-replica MySQL StatefulSet highly available.

## 7. Backup and restore exercise

Create and structurally validate a consistent logical backup:

```powershell
.\scripts\Test-MySqlBackupRestore.ps1
```

Prove restorability in an isolated temporary database, then automatically remove it:

```powershell
.\scripts\Test-MySqlBackupRestore.ps1 -ExecuteRestoreTest
```

The evidence includes backup size, SHA-256 digest, source Pod, timestamp, and restored row count. The SQL dump contains assignment data, so review and redact personal data before sharing it.

## 8. Alert exercises

Safely test the alert pipeline without causing an application outage:

```powershell
kubectl -n monitoring create configmap cnas-alert-drill
Start-Sleep -Seconds 45
kubectl -n monitoring get prometheusrule cnas-application-alerts
```

Confirm `CnasAlertPipelineDrill` is firing in Prometheus or Alertmanager, take a truthful timestamped screenshot, then clear the drill:

```powershell
kubectl -n monitoring delete configmap cnas-alert-drill
```

This validates rule evaluation and Alertmanager delivery only. Use the failover and load exercises for real workload behavior. For production, configure a tested notification receiver; the local stack intentionally keeps alerts inside Alertmanager.

## 9. Collect auditable evidence

After completing the exercises:

```powershell
.\scripts\Collect-Evidence.ps1 -IncludeApplicationLogs
```

The collector writes raw command output, metadata, command exit codes, live Prometheus queries, policy reports, events, workload placement, and SHA-256 checksums under `evidence/<UTC timestamp>/`. Kubernetes Secret objects are deliberately excluded.

Before adding evidence to the assignment report:

- verify every command exit code and explain failures;
- redact student names, email addresses, tokens, credentials, and irrelevant browser chrome;
- caption each screenshot with the requirement, command, expected outcome, actual outcome, and interpretation;
- include the tested Git commit and timestamp;
- keep source evidence unchanged and hash it with the supplied `SHA256SUMS.txt`.

## 10. Evidence-to-requirement map

| Assignment capability | Best evidence |
|---|---|
| Load balancing | `backend-distribution.csv` and per-Pod marked Apache access-log lines from `Test-LoadBalancing.ps1`, plus Pod-placement output |
| Scalability | `hpa-history.csv`, HPA events, and Grafana HPA/CPU panels |
| Resilience | failover metadata, replacement UID, recovery time, and zero-failure request log |
| Security | Kyverno rejection messages, NetworkPolicy denial, TLS gateway result, and image scan output |
| Monitoring | Grafana dashboard panels, Prometheus target health, and tested alerts |
| Auditing | Loki logs/events, Jenkins build record, immutable image digest, evidence metadata and hashes |
| Data recovery | logical backup digest and successful isolated restore result |
| CI/CD | Jenkins log containing rollout and `ci-smoke-test.sh` CRUD pass |

## Honest limitations of the Kind profile

- Prometheus, Alertmanager, Loki, and Grafana use ephemeral local storage to conserve laptop resources; their data does not survive cluster recreation.
- Loki authentication is disabled inside the local cluster.
- The gateway probe accepts the Kind self-signed certificate.
- Prometheus and Loki run one replica each.
- MySQL remains a single-replica data-tier failure point unless a replicated database or managed service is added.
- Kind worker nodes are containers on one machine, so they do not protect against host failure.

State these constraints plainly in the report and distinguish a local architecture demonstration from a production-ready design.
