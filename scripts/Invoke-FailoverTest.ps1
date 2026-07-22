[CmdletBinding()]
param(
    [switch]$Execute,
    [string]$EvidenceDirectory = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Manifest = Join-Path $RepoRoot "tests\k8s\continuity-job.yaml"

if (-not $Execute) {
    Write-Host "Dry run only. This test will:"
    Write-Host "  1. Start 60 requests through php-service."
    Write-Host "  2. Delete one exact php-app Pod."
    Write-Host "  3. Verify zero failed requests and wait for a replacement replica."
    Write-Host "Re-run with -Execute to perform the controlled Pod deletion."
    return
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "kubectl is required."
}

if (-not $EvidenceDirectory) {
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmssZ")
    $EvidenceDirectory = Join-Path $RepoRoot "evidence\failover-$stamp"
}
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null

& kubectl -n cnas rollout status deployment/php-app --timeout=180s
if ($LASTEXITCODE -ne 0) {
    throw "php-app is not healthy before the test."
}

$baselinePods = & kubectl -n cnas get pods -l app=php-app -o "jsonpath={range .items[*]}{.metadata.name}{'|'}{.metadata.uid}{'|'}{.spec.nodeName}{'\n'}{end}"
$baselinePodLines = @($baselinePods -split "`n" | Where-Object { $_ })
if ($baselinePodLines.Count -eq 0) {
    throw "No php-app Pod was found."
}
$baselineUids = @($baselinePodLines | ForEach-Object { ($_ -split '\|')[1] })
$pod = ($baselinePodLines[0] -split '\|')[0]
$uid = ($baselinePodLines[0] -split '\|')[1]
$node = & kubectl -n cnas get pod $pod -o "jsonpath={.spec.nodeName}"
$baselineReady = & kubectl -n cnas get deployment php-app -o "jsonpath={.status.readyReplicas}"
if (-not $pod -or -not $uid) {
    throw "No php-app Pod was found."
}

$started = (Get-Date).ToUniversalTime()
@(
    "startedUtc=$($started.ToString('o'))",
    "deletedPod=$pod",
    "deletedUid=$uid",
    "deletedPodNode=$node",
    "baselineReadyReplicas=$baselineReady"
) | Set-Content -Path (Join-Path $EvidenceDirectory "test-metadata.txt") -Encoding UTF8

& kubectl -n cnas delete job cnas-continuity-test --ignore-not-found=true *> $null
& kubectl apply -f $Manifest
if ($LASTEXITCODE -ne 0) {
    throw "Could not create the continuity test Job."
}

& kubectl -n cnas wait --for=condition=Ready pod -l app.kubernetes.io/name=cnas-continuity-test --timeout=60s
if ($LASTEXITCODE -ne 0) {
    & kubectl -n cnas describe job cnas-continuity-test
    throw "Continuity test Pod did not become ready."
}

Write-Host "Deleting controlled target Pod $pod on node $node..." -ForegroundColor Yellow
$deleteRequested = (Get-Date).ToUniversalTime()
& kubectl -n cnas delete pod $pod --wait=false
if ($LASTEXITCODE -ne 0) {
    throw "Failed to delete the selected Pod."
}
"deleteRequestedUtc=$($deleteRequested.ToString('o'))" | Add-Content -Path (Join-Path $EvidenceDirectory "test-metadata.txt") -Encoding UTF8

& kubectl -n cnas rollout status deployment/php-app --timeout=180s
if ($LASTEXITCODE -ne 0) {
    throw "php-app did not recover to the desired replica count."
}
$recovered = (Get-Date).ToUniversalTime()
$recoverySeconds = [Math]::Round(($recovered - $deleteRequested).TotalSeconds, 1)

& kubectl -n cnas wait --for=condition=complete job/cnas-continuity-test --timeout=120s
$continuityExit = $LASTEXITCODE
& kubectl -n cnas logs job/cnas-continuity-test | Tee-Object -FilePath (Join-Path $EvidenceDirectory "continuity.log")

$currentPods = & kubectl -n cnas get pods -l app=php-app -o "jsonpath={range .items[*]}{.metadata.name}{'|'}{.metadata.uid}{'|'}{.spec.nodeName}{'\n'}{end}"
$replacement = @($currentPods -split "`n" | Where-Object {
    $_ -and $baselineUids -notcontains (($_ -split '\|')[1])
}) | Select-Object -First 1
if (-not $replacement) {
    throw "The Deployment recovered, but no new Pod UID was found relative to the baseline."
}
$totalSeconds = [Math]::Round(((Get-Date).ToUniversalTime() - $started).TotalSeconds, 1)
@(
    "completedUtc=$((Get-Date).ToUniversalTime().ToString('o'))",
    "recoveredUtc=$($recovered.ToString('o'))",
    "recoverySeconds=$recoverySeconds",
    "totalTestSeconds=$totalSeconds",
    "replacement=$replacement"
) | Add-Content -Path (Join-Path $EvidenceDirectory "test-metadata.txt") -Encoding UTF8

& kubectl -n cnas get pods -l app=php-app -o wide | Out-File -FilePath (Join-Path $EvidenceDirectory "pods-after.txt") -Encoding UTF8
& kubectl -n cnas get endpoints php-service -o yaml | Out-File -FilePath (Join-Path $EvidenceDirectory "service-endpoints-after.yaml") -Encoding UTF8

if ($continuityExit -ne 0) {
    & kubectl -n cnas describe job cnas-continuity-test
    throw "At least one Service request failed during Pod replacement. See $EvidenceDirectory."
}

Write-Host "PASS: one Pod was replaced in ${recoverySeconds}s and all continuity requests succeeded." -ForegroundColor Green
Write-Host "Evidence written to: $EvidenceDirectory"
Write-Host "This test proves Pod self-healing only; it does not prove MySQL or physical-host high availability."
