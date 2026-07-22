[CmdletBinding()]
param(
    [string]$EvidenceDirectory = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ManifestPath = Join-Path $RepoRoot "tests\k8s\load-balancing-job.yaml"
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
$marker = "cnas-lb-$stamp-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
if (-not $EvidenceDirectory) {
    $EvidenceDirectory = Join-Path $RepoRoot "evidence\load-balancing-$stamp"
}
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "kubectl is required."
}

$started = (Get-Date).ToUniversalTime()
$sinceTime = $started.ToString("yyyy-MM-ddTHH:mm:ssZ")
$manifest = [System.IO.File]::ReadAllText($ManifestPath).Replace("__MARKER__", $marker)

& kubectl -n cnas delete job cnas-load-balancing-test --ignore-not-found=true *> $null
$manifest | & kubectl apply -f -
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create the load-balancing test Job."
}

& kubectl -n cnas wait --for=condition=complete job/cnas-load-balancing-test --timeout=120s
$jobExit = $LASTEXITCODE
& kubectl -n cnas logs job/cnas-load-balancing-test |
    Tee-Object -FilePath (Join-Path $EvidenceDirectory "gateway-client.log")
if ($jobExit -ne 0) {
    & kubectl -n cnas describe job cnas-load-balancing-test
    throw "The gateway request Job failed."
}

Start-Sleep -Seconds 2
$pods = @(& kubectl -n cnas get pods -l app=php-app -o "jsonpath={range .items[*]}{.metadata.name}{'\n'}{end}" |
    Where-Object { $_ })
if ($pods.Count -lt 2) {
    throw "At least two ready PHP Pods are required to prove load distribution."
}

$distribution = New-Object System.Collections.Generic.List[object]
foreach ($pod in $pods) {
    $lines = @(& kubectl -n cnas logs $pod -c php-app --since-time=$sinceTime 2>&1 |
        Where-Object { $_.ToString().Contains($marker) } |
        ForEach-Object { $_.ToString() })
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read access logs from PHP Pod '$pod'."
    }
    [System.IO.File]::WriteAllLines(
        (Join-Path $EvidenceDirectory "$pod-marker-requests.log"),
        [string[]]$lines,
        (New-Object System.Text.UTF8Encoding($false))
    )
    $distribution.Add([pscustomobject]@{
        pod = $pod
        markedRequests = $lines.Count
    })
}

$distribution | Export-Csv -Path (Join-Path $EvidenceDirectory "backend-distribution.csv") -NoTypeInformation -Encoding UTF8
$reachedBackends = @($distribution | Where-Object { $_.markedRequests -gt 0 }).Count
$observedRequests = ($distribution | Measure-Object -Property markedRequests -Sum).Sum

@(
    "startedUtc=$($started.ToString('o'))",
    "marker=$marker",
    "gateway=https://kong-gateway-proxy.kong.svc.cluster.local/",
    "requested=50",
    "observedInAccessLogs=$observedRequests",
    "distinctPhpBackends=$reachedBackends"
) | Set-Content -Path (Join-Path $EvidenceDirectory "SUMMARY.txt") -Encoding UTF8

$distribution | Format-Table -AutoSize
if ($reachedBackends -lt 2) {
    throw "Only $reachedBackends PHP backend recorded the marked Gateway requests. Load distribution was not proved. Evidence: $EvidenceDirectory"
}
if ($observedRequests -lt 50) {
    throw "Only $observedRequests of 50 marked requests appeared in PHP access logs. Evidence is incomplete."
}

Write-Host "PASS: $observedRequests marked requests traversed Kong and reached $reachedBackends distinct PHP Pods." -ForegroundColor Green
Write-Host "Evidence written to: $EvidenceDirectory"
