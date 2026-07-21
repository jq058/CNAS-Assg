[CmdletBinding()]
param(
    [switch]$SkipNetworkPolicy,
    [switch]$SkipPolicyTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TestDirectory = Join-Path $RepoRoot "tests\k8s"

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    Write-Host "> $Command $($Arguments -join ' ')" -ForegroundColor DarkGray
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $Command $($Arguments -join ' ')"
    }
}

function Invoke-TestJob {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Manifest,
        [int]$TimeoutSeconds = 180
    )

    Write-Host "`nRunning $Name..." -ForegroundColor Cyan
    & kubectl -n cnas delete job $Name --ignore-not-found=true *> $null
    Invoke-Checked -Command "kubectl" -Arguments @("apply", "-f", $Manifest)

    & kubectl -n cnas wait "--for=condition=complete" "job/$Name" "--timeout=${TimeoutSeconds}s"
    $exitCode = $LASTEXITCODE
    & kubectl -n cnas logs "job/$Name" --all-containers=true
    if ($exitCode -ne 0) {
        & kubectl -n cnas describe "job/$Name"
        throw "$Name did not complete successfully."
    }
}

function Assert-PolicyRejection {
    param(
        [Parameter(Mandatory = $true)][string]$Manifest,
        [Parameter(Mandatory = $true)][string]$ExpectedPolicy,
        [switch]$AllowPodSecurity
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $result = & kubectl apply --dry-run=server -f $Manifest 2>&1 | ForEach-Object { $_.ToString() }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $text = $result -join "`n"
    if ($exitCode -eq 0) {
        throw "Expected policy '$ExpectedPolicy' to reject '$Manifest', but the API server accepted it."
    }
    if ($text -match [regex]::Escape($ExpectedPolicy)) {
        Write-Host "PASS: Kyverno policy $ExpectedPolicy rejected $([System.IO.Path]::GetFileName($Manifest))." -ForegroundColor Green
        return
    }
    if ($AllowPodSecurity -and $text -match '(?i)podsecurity|pod security|violates podsecurity') {
        Write-Host "PASS: Pod Security Admission rejected $([System.IO.Path]::GetFileName($Manifest)) before the overlapping Kyverno policy was evaluated." -ForegroundColor Green
        return
    }
    else {
        throw "'$Manifest' was rejected, but not by expected policy '$ExpectedPolicy'. Output:`n$text"
    }
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "kubectl is required."
}

Write-Host "Checking application readiness..." -ForegroundColor Cyan
Invoke-Checked -Command "kubectl" -Arguments @("-n", "cnas", "rollout", "status", "deployment/php-app", "--timeout=180s")
Invoke-Checked -Command "kubectl" -Arguments @("-n", "cnas", "rollout", "status", "statefulset/mysql", "--timeout=180s")
Invoke-Checked -Command "kubectl" -Arguments @("-n", "cnas", "get", "endpoints", "php-service", "mysql-service")

Invoke-TestJob -Name "cnas-smoke-test" -Manifest (Join-Path $TestDirectory "smoke-job.yaml")
& (Join-Path $PSScriptRoot "Test-LoadBalancing.ps1")
Invoke-TestJob -Name "cnas-gateway-controls-test" -Manifest (Join-Path $TestDirectory "gateway-controls-job.yaml") -TimeoutSeconds 180

if (-not $SkipNetworkPolicy) {
    Invoke-TestJob -Name "cnas-network-policy-test" -Manifest (Join-Path $TestDirectory "network-policy-job.yaml") -TimeoutSeconds 90
}
else {
    Write-Warning "NetworkPolicy enforcement test skipped. This should not be skipped for final evidence."
}

if (-not $SkipPolicyTests) {
    Write-Host "`nChecking Kyverno admission controls with server-side dry runs..." -ForegroundColor Cyan
    Assert-PolicyRejection -Manifest (Join-Path $TestDirectory "policy-deny-latest.yaml") -ExpectedPolicy "cnas-disallow-latest-tag"
    Assert-PolicyRejection -Manifest (Join-Path $TestDirectory "policy-require-resources.yaml") -ExpectedPolicy "cnas-require-resources"
    Assert-PolicyRejection -Manifest (Join-Path $TestDirectory "policy-require-nonroot.yaml") -ExpectedPolicy "cnas-require-run-as-non-root" -AllowPodSecurity
    Assert-PolicyRejection -Manifest (Join-Path $TestDirectory "policy-disallow-privileged.yaml") -ExpectedPolicy "cnas-restricted-containers" -AllowPodSecurity
}
else {
    Write-Warning "Kyverno policy tests skipped. This should not be skipped for final evidence."
}

Write-Host "`nChecking observability resources..." -ForegroundColor Cyan
Invoke-Checked -Command "kubectl" -Arguments @("-n", "monitoring", "get", "prometheus,alertmanager,probes,prometheusrules")
Invoke-Checked -Command "kubectl" -Arguments @("-n", "monitoring", "rollout", "status", "deployment/alloy", "--timeout=180s")
Invoke-Checked -Command "kubectl" -Arguments @("-n", "cnas", "rollout", "status", "deployment/mysql-exporter", "--timeout=180s")

Write-Host "`nPASS: readiness, HTTP routing, security controls, and observability checks completed." -ForegroundColor Green
Write-Host "Run Invoke-LoadTest.ps1 and Invoke-FailoverTest.ps1 -Execute separately for scaling and resilience evidence."
