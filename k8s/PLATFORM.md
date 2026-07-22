# Kubernetes platform runbook

This environment uses a four-node Kind cluster (one control plane and three
workers), Calico for enforceable NetworkPolicy, Kong Gateway with Gateway API,
Kyverno admission policies, and Metrics Server for HPA. All dependency versions
are pinned in `k8s/scripts/install-platform.*` and `k8s/gateway/kong-values.yaml`.
Kind v0.32.0 or newer is required, and the Kubernetes node image is pinned by
digest in `k8s/scripts/create-kind-cluster.*` for reproducible cluster creation.

## 1. Create or prepare the cluster

The convenience script creates the cluster only when it does not already exist;
it never deletes an existing cluster.

```bash
bash ./k8s/scripts/create-kind-cluster.sh
```

```powershell
.\k8s\scripts\create-kind-cluster.ps1
```

If the cluster already exists, run `install-platform` directly. The installer
refuses to touch any context other than `kind-cnas-cluster` and refuses clusters
created with kindnet because kindnet does not enforce NetworkPolicy.

## 2. Bootstrap runtime credentials

Set four strong, distinct environment variables: `DB_USER`, `DB_PASSWORD`,
`MYSQL_ROOT_PASSWORD`, and `REDIS_PASSWORD`. Then run the matching script:

```bash
bash ./k8s/scripts/bootstrap-secrets.sh
```

```powershell
.\k8s\scripts\bootstrap-secrets.ps1
```

The scripts stream the Secret to the Kubernetes API. No populated Secret file is
stored in the repository. In a hosted environment, replace this local bootstrap
with an external secret manager and enable Kubernetes Secret encryption at rest.

## 3. Bootstrap local TLS

For the coursework Kind cluster, generate a 30-day self-signed certificate:

```bash
bash ./k8s/scripts/bootstrap-local-tls.sh
```

```powershell
.\k8s\scripts\bootstrap-local-tls.ps1
```

Add `127.0.0.1 cnas.local` to the workstation hosts file. A real deployment must
use a trusted issuer such as cert-manager with an organisational or public CA.

## 4. Deploy and verify

For a local deployment which is not driven by Jenkins, build and load the
explicit bootstrap image first. Jenkins instead overrides this image with its
immutable `<build-number>-<git-sha>` tag through a Kustomize overlay.

```bash
docker build -t jqii/cnas-php-app:bootstrap .
kind load docker-image jqii/cnas-php-app:bootstrap --name cnas-cluster
```

```bash
kubectl apply -k k8s
kubectl -n cnas wait --for=condition=complete job/db-migration-v2 --timeout=300s
kubectl -n cnas rollout status statefulset/mysql --timeout=300s
kubectl -n cnas rollout status deployment/redis --timeout=300s
kubectl -n cnas rollout status deployment/php-app --timeout=300s
kubectl -n cnas get gateway,httproute,hpa,pods
curl -k https://cnas.local/livez.php
curl -k https://cnas.local/readyz.php
```

HTTP requests are redirected to HTTPS. Kong adds `X-Request-ID`, writes access
logs to stdout, and rate-limits requests. The open-source local rate-limit policy
keeps a counter per Kong replica, so it demonstrates enforcement but is not a
globally exact distributed quota.

## Honest resilience boundaries

- Pod spreading places the three PHP replicas across workers when capacity is
  available, but all Kind nodes are containers on one physical host.
- MySQL and Redis are deliberately single-replica stateful dependencies. Their
  persistent volumes survive a Pod restart, but they are not multi-node HA.
- The MySQL CronJob creates daily logical backups with seven-day retention on a
  separate PVC. A production design also needs off-cluster backups and a tested
  restore procedure.
- Database migration Jobs are immutable and versioned (`db-migration-v2`, then
  `v3`, and so on). Every schema change must add a new migration rather than
  editing or expecting Kubernetes to rerun an already-completed Job.
- The PDB protects voluntary disruptions only. It does not prevent abrupt node
  or host failures.
