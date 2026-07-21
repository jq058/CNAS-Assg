[CmdletBinding()]
param(
    [string]$OutputDirectory = "",
    [switch]$IncludeApplicationLogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $OutputDirectory) {
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmssZ")
    $OutputDirectory = Join-Path $RepoRoot "evidence\$stamp"
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "kubectl is required to collect cluster evidence."
}

$commandLog = New-Object System.Collections.Generic.List[object]

function Save-CommandOutput {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $safeName = $Name -replace '[^A-Za-z0-9_.-]', '_'
    $path = Join-Path $OutputDirectory "$safeName.txt"
    $started = (Get-Date).ToUniversalTime()
    $previousPreference = $ErrorActionPreference
    $global:LASTEXITCODE = 0
    try {
        $ErrorActionPreference = "Continue"
        $lines = & $Command @Arguments 2>&1 | ForEach-Object { $_.ToString() }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($null -eq $lines) {
        $lines = @()
    }
    [System.IO.File]::WriteAllLines($path, [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))

    $commandLog.Add([pscustomobject]@{
        name = $Name
        command = "$Command $($Arguments -join ' ')"
        startedUtc = $started.ToString("o")
        exitCode = $exitCode
        file = [System.IO.Path]::GetFileName($path)
    })

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "Evidence command failed: $Command $($Arguments -join ' '). See $path"
    }
}

function Save-PrometheusQuery {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Query
    )

    $encoded = [System.Uri]::EscapeDataString($Query)
    $path = "/api/v1/namespaces/monitoring/services/http:monitoring-prometheus:9090/proxy/api/v1/query?query=$encoded"
    Save-CommandOutput -Name "prometheus-$Name" -Command "kubectl" -Arguments @("get", "--raw", $path) -AllowFailure
}

$context = (& kubectl config current-context 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $context) {
    throw "No active Kubernetes context is available."
}

Save-CommandOutput -Name "01-kubectl-version" -Command "kubectl" -Arguments @("version", "-o", "yaml")
Save-CommandOutput -Name "02-cluster-info" -Command "kubectl" -Arguments @("cluster-info")
Save-CommandOutput -Name "03-nodes-wide" -Command "kubectl" -Arguments @("get", "nodes", "-o", "wide")
Save-CommandOutput -Name "04-cnas-workloads" -Command "kubectl" -Arguments @("-n", "cnas", "get", "all", "-o", "wide")
Save-CommandOutput -Name "05-monitoring-workloads" -Command "kubectl" -Arguments @("-n", "monitoring", "get", "all", "-o", "wide")
Save-CommandOutput -Name "06-gateway-classes" -Command "kubectl" -Arguments @(
    "get", "gatewayclasses.gateway.networking.k8s.io", "-o", "wide"
) -AllowFailure
Save-CommandOutput -Name "07-cnas-gateway-routes-hpa-pdb" -Command "kubectl" -Arguments @(
    "-n", "cnas", "get", "gateways.gateway.networking.k8s.io,httproutes.gateway.networking.k8s.io,kongplugins.configuration.konghq.com,hpa,pdb", "-o", "wide"
)
Save-CommandOutput -Name "08-cnas-network-policies" -Command "kubectl" -Arguments @(
    "-n", "cnas", "get", "networkpolicy", "-o", "yaml"
)
Save-CommandOutput -Name "09-cnas-events" -Command "kubectl" -Arguments @(
    "-n", "cnas", "get", "events", "--sort-by=.metadata.creationTimestamp"
) -AllowFailure
Save-CommandOutput -Name "10-monitoring-events" -Command "kubectl" -Arguments @(
    "-n", "monitoring", "get", "events", "--sort-by=.metadata.creationTimestamp"
) -AllowFailure
Save-CommandOutput -Name "11-observability-targets" -Command "kubectl" -Arguments @(
    "get", "servicemonitors,podmonitors,probes,prometheusrules", "-A", "-o", "wide"
) -AllowFailure
Save-CommandOutput -Name "12-kyverno-policies" -Command "kubectl" -Arguments @(
    "get", "clusterpolicies.kyverno.io", "-o", "wide"
) -AllowFailure
Save-CommandOutput -Name "13-policy-reports" -Command "kubectl" -Arguments @(
    "get", "policyreports.wgpolicyk8s.io", "-A", "-o", "yaml"
) -AllowFailure
Save-CommandOutput -Name "14-pod-placement" -Command "kubectl" -Arguments @(
    "-n", "cnas", "get", "pods", "-o", "custom-columns=NAME:.metadata.name,WORKLOAD:.metadata.labels.app,NODE:.spec.nodeName,PHASE:.status.phase,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount"
)
Save-CommandOutput -Name "15-rollout-history-php" -Command "kubectl" -Arguments @(
    "-n", "cnas", "rollout", "history", "deployment/php-app"
)
Save-CommandOutput -Name "16-hpa-description" -Command "kubectl" -Arguments @(
    "-n", "cnas", "describe", "hpa", "php-app-hpa"
) -AllowFailure

if (Get-Command helm -ErrorAction SilentlyContinue) {
    Save-CommandOutput -Name "17-helm-releases" -Command "helm" -Arguments @("list", "-A") -AllowFailure
}

Save-PrometheusQuery -Name "app-availability" -Query 'probe_success{service="php-app"}'
Save-PrometheusQuery -Name "gateway-availability" -Query 'probe_success{service="gateway"}'
Save-PrometheusQuery -Name "mysql-up" -Query 'mysql_up{namespace="cnas"}'
Save-PrometheusQuery -Name "ready-replicas" -Query 'kube_deployment_status_replicas_available{namespace="cnas",deployment="php-app"}'
Save-PrometheusQuery -Name "hpa-current" -Query 'kube_horizontalpodautoscaler_status_current_replicas{namespace="cnas",horizontalpodautoscaler="php-app-hpa"}'
Save-PrometheusQuery -Name "active-alerts" -Query 'ALERTS{alertstate="firing"}'

$lokiPath = "/api/v1/namespaces/monitoring/services/http:loki-gateway:80/proxy/loki/api/v1/labels"
Save-CommandOutput -Name "loki-labels" -Command "kubectl" -Arguments @("get", "--raw", $lokiPath) -AllowFailure

if ($IncludeApplicationLogs) {
    $pods = & kubectl -n cnas get pods -l app=php-app -o "jsonpath={range .items[*]}{.metadata.name}{'`n'}{end}"
    foreach ($pod in ($pods -split "`n" | Where-Object { $_ })) {
        Save-CommandOutput -Name "log-$pod" -Command "kubectl" -Arguments @(
            "-n", "cnas", "logs", $pod, "-c", "php-app", "--tail=500", "--timestamps=true"
        ) -AllowFailure
    }
}

$gitCommit = "unknown"
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitCommit = (& git -C $RepoRoot rev-parse HEAD 2>$null)
    Save-CommandOutput -Name "git-status" -Command "git" -Arguments @("-C", $RepoRoot, "status", "--short") -AllowFailure
}

$metadata = [ordered]@{
    collectedUtc = (Get-Date).ToUniversalTime().ToString("o")
    kubeContext = $context
    gitCommit = $gitCommit
    collector = "scripts/Collect-Evidence.ps1"
    note = "Generated from live commands. Secrets and Secret manifests are intentionally excluded."
}
$metadata | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $OutputDirectory "metadata.json") -Encoding UTF8
$commandLog | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $OutputDirectory "commands.json") -Encoding UTF8

$summaryLines = @(
    "# CNAS validation evidence",
    "",
    "Collected (UTC): $($metadata.collectedUtc)",
    "Kubernetes context: $context",
    "Git commit: $gitCommit",
    "",
    "This directory contains raw command output captured from the live cluster. It does not contain fabricated screenshots or results.",
    "Secrets are intentionally excluded. Review logs for personal data before sharing them.",
    "",
    "## Command results",
    "",
    "| Evidence | Exit code | File |",
    "|---|---:|---|"
)
foreach ($entry in $commandLog) {
    $summaryLines += "| $($entry.name) | $($entry.exitCode) | $($entry.file) |"
}
[System.IO.File]::WriteAllLines(
    (Join-Path $OutputDirectory "SUMMARY.md"),
    [string[]]$summaryLines,
    (New-Object System.Text.UTF8Encoding($false))
)

$hashLines = Get-ChildItem -LiteralPath $OutputDirectory -File |
    Where-Object { $_.Name -ne "SHA256SUMS.txt" } |
    Sort-Object Name |
    ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $($_.Name)"
    }
[System.IO.File]::WriteAllLines(
    (Join-Path $OutputDirectory "SHA256SUMS.txt"),
    [string[]]$hashLines,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Evidence written to: $OutputDirectory" -ForegroundColor Green
Write-Host "Attach only reviewed evidence to the report; do not include secrets or unredacted personal data."
