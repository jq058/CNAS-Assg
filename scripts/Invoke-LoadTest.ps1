[CmdletBinding()]
param(
    [string]$EvidenceDirectory = "",
    [int]$TimeoutSeconds = 300,
    [switch]$AllowNoScaleOut
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Manifest = Join-Path $RepoRoot "tests\k8s\load-job.yaml"
if (-not $EvidenceDirectory) {
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmssZ")
    $EvidenceDirectory = Join-Path $RepoRoot "evidence\load-$stamp"
}
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$historyPath = Join-Path $EvidenceDirectory "hpa-history.csv"

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "kubectl is required."
}

& kubectl -n cnas get hpa php-app-hpa *> $null
if ($LASTEXITCODE -ne 0) {
    throw "HPA cnas/php-app-hpa is missing. Install metrics-server and deploy the HPA first."
}

$minimumReplicas = [int](& kubectl -n cnas get hpa php-app-hpa -o "jsonpath={.spec.minReplicas}")
$baselineReplicas = [int](& kubectl -n cnas get hpa php-app-hpa -o "jsonpath={.status.currentReplicas}")
if ($LASTEXITCODE -ne 0) {
    throw "Could not read the HPA baseline."
}

& kubectl -n cnas delete job cnas-load-test --ignore-not-found=true *> $null
& kubectl apply -f $Manifest
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create the load-test Job."
}

[System.IO.File]::WriteAllText(
    $historyPath,
    "timestampUtc,currentReplicas,desiredReplicas,currentCpu`n",
    (New-Object System.Text.UTF8Encoding($false))
)

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$maximumObserved = $baselineReplicas
$completed = $false

while ((Get-Date) -lt $deadline) {
    $timestamp = (Get-Date).ToUniversalTime().ToString("o")
    $current = & kubectl -n cnas get hpa php-app-hpa -o "jsonpath={.status.currentReplicas}"
    $desired = & kubectl -n cnas get hpa php-app-hpa -o "jsonpath={.status.desiredReplicas}"
    $cpu = & kubectl -n cnas get hpa php-app-hpa -o "jsonpath={.status.currentMetrics[0].resource.current.averageUtilization}"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read HPA status during the load test."
    }

    if ($current) {
        $maximumObserved = [Math]::Max($maximumObserved, [int]$current)
    }
    "$timestamp,$current,$desired,$cpu" | Add-Content -Path $historyPath -Encoding UTF8
    Write-Host "HPA: current=$current desired=$desired cpu=$cpu%"

    $jobStatus = & kubectl -n cnas get job cnas-load-test -o "jsonpath={.status.conditions[?(@.type=='Complete')].status}"
    if ($jobStatus -eq "True") {
        $completed = $true
        break
    }
    $failedStatus = & kubectl -n cnas get job cnas-load-test -o "jsonpath={.status.conditions[?(@.type=='Failed')].status}"
    if ($failedStatus -eq "True") {
        break
    }
    Start-Sleep -Seconds 10
}

& kubectl -n cnas logs job/cnas-load-test | Tee-Object -FilePath (Join-Path $EvidenceDirectory "load-generator.log")
& kubectl -n cnas describe hpa php-app-hpa | Out-File -FilePath (Join-Path $EvidenceDirectory "hpa-description.txt") -Encoding UTF8

if (-not $completed) {
    & kubectl -n cnas describe job cnas-load-test
    throw "The load-test Job did not complete within $TimeoutSeconds seconds."
}

if ($maximumObserved -le $minimumReplicas -and -not $AllowNoScaleOut) {
    throw "Load completed, but HPA never scaled above minReplicas=$minimumReplicas. Verify metrics-server, CPU requests, and load intensity. Evidence: $EvidenceDirectory"
}

Write-Host "PASS: load test completed; maximum observed replicas=$maximumObserved (baseline=$baselineReplicas)." -ForegroundColor Green
Write-Host "Evidence written to: $EvidenceDirectory"
