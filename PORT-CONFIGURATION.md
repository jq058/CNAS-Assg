# Port configuration

This is the current port map.

| Scope | Component | Port | Exposure |
|---|---|---:|---|
| Docker Compose host | PHP application | 8080 | http://localhost:8080 |
| Application container/Pod | Apache/PHP | 8080 | Internal, unprivileged |
| Kind host | Kong HTTP | 80 | Redirects to HTTPS |
| Kind host | Kong HTTPS | 443 | https://cnas.local |
| Kubernetes Service | php-service | 80 to target 8080 | Cluster-internal |
| Kubernetes Service | mysql | 3306 | Cluster-internal |
| Kubernetes Service | redis | 6379 | Cluster-internal |
| Local port-forward | Grafana | 3000 | Optional operator access |

The Kind port mappings are declared in kind-cluster.yaml. Kong NodePorts provide the host 80/443 mappings. Do not expose MySQL or Redis on the host.

If port 8080 is occupied locally, set a different host port before starting Compose, for example `$env:APP_PORT=18080`. Do not edit the Kubernetes container port to solve a host-only conflict.

See [k8s/PLATFORM.md](k8s/PLATFORM.md) for cluster access and [docs/DEMO-RUNBOOK.md](docs/DEMO-RUNBOOK.md) for verified endpoint checks.
