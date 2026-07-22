$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = (Resolve-Path (Join-Path $scriptDirectory '..\..')).Path

$calicoVersion = 'v3.32.1'
$gatewayApiVersion = 'v1.3.0'
$kongChartVersion = '0.24.0'
$kyvernoChartVersion = '3.8.2'
$metricsServerVersion = 'v0.8.1'

foreach ($commandName in @('kubectl', 'helm')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Required command is missing: $commandName"
    }
}

$currentContext = (& kubectl config current-context).Trim()
if ($currentContext -ne 'kind-cnas-cluster') {
    throw "Refusing to modify '$currentContext'. Select the kind-cnas-cluster context first."
}

$ErrorActionPreference = 'Continue'
& kubectl -n kube-system get daemonset kindnet *> $null
$kindnetExitCode = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($kindnetExitCode -eq 0) {
    throw 'This cluster uses kindnet. Recreate it with kind-cluster.yaml so Calico can enforce NetworkPolicy.'
}

Write-Host "Installing Calico $calicoVersion..."
& kubectl apply --server-side=true --force-conflicts -f "https://raw.githubusercontent.com/projectcalico/calico/$calicoVersion/manifests/calico.yaml"
if ($LASTEXITCODE -ne 0) { throw 'Calico installation failed.' }
& kubectl rollout status daemonset/calico-node -n kube-system --timeout=300s
& kubectl rollout status deployment/calico-kube-controllers -n kube-system --timeout=300s
& kubectl wait --for=condition=Ready nodes --all --timeout=300s

Write-Host "Installing Gateway API $gatewayApiVersion..."
& kubectl apply --server-side=true -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/$gatewayApiVersion/standard-install.yaml"
if ($LASTEXITCODE -ne 0) { throw 'Gateway API installation failed.' }

Write-Host "Installing Kong chart $kongChartVersion..."
& helm repo add kong https://charts.konghq.com --force-update
& helm repo update kong
& helm upgrade --install kong kong/ingress `
    --namespace kong `
    --create-namespace `
    --version $kongChartVersion `
    --values (Join-Path $repositoryRoot 'k8s\gateway\kong-values.yaml') `
    --wait `
    --timeout 10m
if ($LASTEXITCODE -ne 0) { throw 'Kong installation failed.' }

Write-Host "Installing Kyverno chart $kyvernoChartVersion..."
& helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update
& helm repo update kyverno
& helm upgrade --install kyverno kyverno/kyverno `
    --namespace kyverno `
    --create-namespace `
    --version $kyvernoChartVersion `
    --set admissionController.replicas=2 `
    --wait `
    --timeout 10m
if ($LASTEXITCODE -ne 0) { throw 'Kyverno installation failed.' }
& kubectl apply -f (Join-Path $repositoryRoot 'k8s\kyverno')
if ($LASTEXITCODE -ne 0) { throw 'Kyverno policy installation failed.' }

Write-Host "Installing Metrics Server $metricsServerVersion for HPA..."
& kubectl apply --server-side=true -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/$metricsServerVersion/components.yaml"
if ($LASTEXITCODE -ne 0) { throw 'Metrics Server installation failed.' }

$metricsArguments = & kubectl -n kube-system get deployment metrics-server -o "jsonpath={.spec.template.spec.containers[0].args}"
if ($metricsArguments -notmatch '--kubelet-insecure-tls') {
    # This local certificate exception is guarded by the Kind-context check.
    # Use a patch file because Windows PowerShell 5.1 can strip the embedded
    # JSON quotes when it passes a --patch argument to a native executable.
    $metricsPatchPath = Join-Path ([System.IO.Path]::GetTempPath()) ("metrics-server-" + [guid]::NewGuid().ToString("N") + ".json")
    try {
        [System.IO.File]::WriteAllText(
            $metricsPatchPath,
            '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]',
            (New-Object System.Text.UTF8Encoding($false))
        )
        & kubectl -n kube-system patch deployment metrics-server --type=json --patch-file $metricsPatchPath
        if ($LASTEXITCODE -ne 0) { throw 'Metrics Server Kind TLS patch failed.' }
    }
    finally {
        if (Test-Path -LiteralPath $metricsPatchPath) {
            Remove-Item -LiteralPath $metricsPatchPath -Force
        }
    }
}
& kubectl rollout status deployment/metrics-server -n kube-system --timeout=300s

Write-Host 'Platform prerequisites are ready. Bootstrap secrets/TLS, then run: kubectl apply -k k8s'
