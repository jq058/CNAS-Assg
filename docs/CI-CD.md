# Jenkins CI/CD and DevSecOps pipeline

The committed `Jenkinsfile` builds one immutable application image and promotes that exact image through security checks and Kubernetes deployment. It deliberately does not push a `latest` tag.

## Jenkins agent prerequisites

The Jenkins agent needs:

- Docker Engine and Docker Compose v2;
- `kubectl` with Kustomize support;
- Helm and OpenSSL;
- Trivy;
- Bash, Git, and network access to Docker Hub and the Kubernetes API;
- the Docker Pipeline, Credentials Binding, Kubernetes CLI, Workspace Cleanup, and Pipeline plugins.

The target cluster must be created from `kind-cluster.yaml`. The pipeline runs the idempotent `k8s/scripts/install-platform.sh` before applying application resources. For the local Kind demonstration it also generates a short-lived, self-signed `cnas.local` TLS Secret. A real deployment must replace this with a certificate issued by a trusted CA or cert-manager.

## Required Jenkins credentials

Create these entries in Jenkins. Do not place the values in source control or pipeline parameters.

| Credential ID | Jenkins type | Purpose |
|---|---|---|
| `docker-hub-credentials` | Username with password | Push the application image. |
| `kubeconfig-cluster-secret` | Kubeconfig credential | Authenticate to the target cluster. |
| `cnas-db-credentials` | Username with password | Create/update the application database Secret used by runtime CRUD and versioned migrations. |
| `cnas-mysql-root-password` | Secret text | Initialize and administer the MySQL instance. |
| `cnas-redis-password` | Secret text | Authenticate the shared PHP session store. |

Jenkins masks the credential bindings, and the shell disables command tracing while generating `cnas-secret`. The pipeline logs only the Secret object's name, never its values.

## Pipeline gates

1. Checkout and record the twelve-character Git commit.
2. PHP syntax checks and repository unit tests in a clean PHP CLI container.
3. Docker Compose parsing and Kustomize rendering.
4. Trivy source, IaC, dependency, and secret scanning; HIGH/CRITICAL findings fail the build.
5. Build `${BUILD_NUMBER}-${GIT_SHA}` once.
6. Trivy image gate and CycloneDX SBOM generation.
7. Push only the immutable build tag.
8. Install or verify platform controllers and admission controls.
9. Inject runtime Secrets from Jenkins credentials.
10. Render a temporary Kustomize overlay containing the exact image tag and deploy it.
11. Wait for rollout, run smoke tests, and verify the running image string.
12. Archive the SBOM, rendered manifests, and test artefacts.

The Deployment is annotated with the Git SHA and image name so the running workload can be traced back to a Jenkins build. A failure before deployment does not touch a healthy release. A deployment or verification failure attempts a Kubernetes rollout undo.

## Traceability evidence

Use these commands during the demonstration:

```sh
kubectl get deployment php-app -n cnas \
  -o jsonpath='{.metadata.annotations.cnas\.assignment/git-sha}{"\n"}{.metadata.annotations.cnas\.assignment/image}{"\n"}'

kubectl rollout history deployment/php-app -n cnas

kubectl get pods -n cnas \
  -l app=php-app \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[?(@.name=="php-app")].image}{"\n"}{end}'
```

Capture the Jenkins build URL, Git commit, archived SBOM fingerprint, image tag, Deployment annotations, rollout revision, smoke-test result, and final Pod images in one evidence table.

## Deliberate limitations

- The pipeline produces an SBOM but does not yet sign images. Cosign signing and admission verification are a reasonable stretch goal.
- Jenkins controls application delivery; cluster creation and host-level Docker availability are external platform responsibilities.
- Automatic rollback can restore the previous application image, but it cannot reverse incompatible database migrations. Schema changes must use a separately tested, backward-compatible migration process.
- The coursework profile shares one database identity between runtime CRUD, migrations, and backups. Because it therefore has schema privileges, a production design should split these into separate least-privilege identities.
