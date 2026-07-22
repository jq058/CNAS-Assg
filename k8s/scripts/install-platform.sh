#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

CALICO_VERSION="v3.32.1"
GATEWAY_API_VERSION="v1.3.0"
KONG_CHART_VERSION="0.24.0"
KYVERNO_CHART_VERSION="3.8.2"
METRICS_SERVER_VERSION="v0.8.1"

for command_name in kubectl helm; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Required command is missing: ${command_name}" >&2
    exit 1
  }
done

current_context="$(kubectl config current-context)"
if [[ "${current_context}" != "kind-cnas-cluster" ]]; then
  echo "Refusing to modify '${current_context}'. Select the kind-cnas-cluster context first." >&2
  exit 1
fi

if kubectl -n kube-system get daemonset kindnet >/dev/null 2>&1; then
  echo "This cluster uses kindnet. Recreate it with kind-cluster.yaml so Calico can enforce NetworkPolicy." >&2
  exit 1
fi

echo "Installing Calico ${CALICO_VERSION}..."
kubectl apply --server-side=true --force-conflicts \
  -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"
kubectl rollout status daemonset/calico-node -n kube-system --timeout=300s
kubectl rollout status deployment/calico-kube-controllers -n kube-system --timeout=300s
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo "Installing Gateway API ${GATEWAY_API_VERSION}..."
kubectl apply --server-side=true \
  -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

echo "Installing Kong chart ${KONG_CHART_VERSION}..."
helm repo add kong https://charts.konghq.com --force-update
helm repo update kong
helm upgrade --install kong kong/ingress \
  --namespace kong \
  --create-namespace \
  --version "${KONG_CHART_VERSION}" \
  --values "${REPO_ROOT}/k8s/gateway/kong-values.yaml" \
  --wait \
  --timeout 10m

echo "Installing Kyverno chart ${KYVERNO_CHART_VERSION}..."
helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update
helm repo update kyverno
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --version "${KYVERNO_CHART_VERSION}" \
  --set admissionController.replicas=2 \
  --wait \
  --timeout 10m
kubectl apply -f "${REPO_ROOT}/k8s/kyverno"

echo "Installing Metrics Server ${METRICS_SERVER_VERSION} for HPA..."
kubectl apply \
  --server-side=true \
  --force-conflicts \
  --field-manager=cnas-platform \
  -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml"

metrics_args="$(kubectl -n kube-system get deployment metrics-server -o jsonpath='{.spec.template.spec.containers[0].args}')"
if [[ "${metrics_args}" != *"--kubelet-insecure-tls"* ]]; then
  # Kind kubelets use locally generated certificates. This exception is only
  # for the local Kind context guarded above, never for a production cluster.
  kubectl -n kube-system patch deployment metrics-server \
  --type=json \
  --field-manager=cnas-platform \
  --patch='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'fi
kubectl rollout status deployment/metrics-server -n kube-system --timeout=300s

echo "Platform prerequisites are ready. Bootstrap secrets/TLS, then run: kubectl apply -k k8s"
