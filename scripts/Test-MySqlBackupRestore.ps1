[CmdletBinding()]
param(
    [string]$OutputDirectory = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $OutputDirectory) {
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmssZ")
    $OutputDirectory = Join-Path $RepoRoot "evidence\backup-$stamp"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "kubectl is required."
}

$pod = & kubectl -n cnas get pods -l app=mysql -o "jsonpath={.items[0].metadata.name}"
if ($LASTEXITCODE -ne 0 -or -not $pod) {
    throw "No MySQL Pod was found in namespace cnas."
}

& kubectl -n cnas wait --for=condition=Ready "pod/$pod" --timeout=120s
if ($LASTEXITCODE -ne 0) {
    throw "MySQL Pod '$pod' is not ready."
}

$backupPath = Join-Path $OutputDirectory "mydb.sql"
$dumpCommand = 'export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"; exec mysqldump -h 127.0.0.1 -uroot --single-transaction --routines --triggers --set-gtid-purged=OFF mydb'
$dumpLines = & kubectl -n cnas exec $pod -- /bin/sh -c $dumpCommand 2>&1 | ForEach-Object { $_.ToString() }
if ($LASTEXITCODE -ne 0) {
    throw "mysqldump failed:`n$($dumpLines -join "`n")"
}
$dumpText = ($dumpLines -join "`n") + "`n"
[System.IO.File]::WriteAllText($backupPath, $dumpText, (New-Object System.Text.UTF8Encoding($false)))

if ((Get-Item -LiteralPath $backupPath).Length -lt 100) {
    throw "Backup file is unexpectedly small: $backupPath"
}
if ($dumpText -notmatch "(?m)^CREATE TABLE") {
    throw "Backup does not contain a CREATE TABLE statement."
}

$hash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash.ToLowerInvariant()
@(
    "createdUtc=$((Get-Date).ToUniversalTime().ToString('o'))",
    "sourcePod=$pod",
    "sourceDatabase=mydb",
    "backupBytes=$((Get-Item -LiteralPath $backupPath).Length)",
    "sha256=$hash"
) | Set-Content -Path (Join-Path $OutputDirectory "backup-metadata.txt") -Encoding UTF8

Write-Host "PASS: logical backup created and structurally validated." -ForegroundColor Green
Write-Host "Backup: $backupPath"
Write-Host "SHA-256: $hash"
