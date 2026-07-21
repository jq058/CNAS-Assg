[CmdletBinding()]
param(
    [string]$OutputDirectory = "",
    [switch]$ExecuteRestoreTest
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
    "sha256=$hash",
    "restoreTestRequested=$($ExecuteRestoreTest.IsPresent)"
) | Set-Content -Path (Join-Path $OutputDirectory "backup-metadata.txt") -Encoding UTF8

if ($ExecuteRestoreTest) {
    $temporaryDatabase = "cnas_restore_test_" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
    $created = $false
    try {
        $createCommand = "export MYSQL_PWD=`"`$MYSQL_ROOT_PASSWORD`"; exec mysql -h 127.0.0.1 -uroot -e 'CREATE DATABASE ``$temporaryDatabase``;'"
        & kubectl -n cnas exec $pod -- /bin/sh -c $createCommand
        if ($LASTEXITCODE -ne 0) {
            throw "Could not create temporary restore database '$temporaryDatabase'."
        }
        $created = $true

        $restoreCommand = "export MYSQL_PWD=`"`$MYSQL_ROOT_PASSWORD`"; exec mysql -h 127.0.0.1 -uroot $temporaryDatabase"
        $dumpText | & kubectl -n cnas exec -i $pod -- /bin/sh -c $restoreCommand
        if ($LASTEXITCODE -ne 0) {
            throw "Restore into temporary database '$temporaryDatabase' failed."
        }

        $verifyCommand = "export MYSQL_PWD=`"`$MYSQL_ROOT_PASSWORD`"; exec mysql -N -B -h 127.0.0.1 -uroot -e 'SELECT COUNT(*) FROM ``$temporaryDatabase``.users;'"
        $rowCount = & kubectl -n cnas exec $pod -- /bin/sh -c $verifyCommand
        if ($LASTEXITCODE -ne 0 -or $rowCount -notmatch '^\d+$') {
            throw "Restore validation query failed for '$temporaryDatabase'."
        }
        "temporaryDatabase=$temporaryDatabase`nrestoredUsers=$rowCount" |
            Set-Content -Path (Join-Path $OutputDirectory "restore-result.txt") -Encoding UTF8
        Write-Host "Restore validation succeeded with $rowCount row(s) in the temporary users table."
    }
    finally {
        if ($created) {
            $dropCommand = "export MYSQL_PWD=`"`$MYSQL_ROOT_PASSWORD`"; exec mysql -h 127.0.0.1 -uroot -e 'DROP DATABASE IF EXISTS ``$temporaryDatabase``;'"
            & kubectl -n cnas exec $pod -- /bin/sh -c $dropCommand
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Could not remove temporary database '$temporaryDatabase'. Remove it manually."
            }
        }
    }
}

Write-Host "PASS: logical backup created and structurally validated." -ForegroundColor Green
Write-Host "Backup: $backupPath"
Write-Host "SHA-256: $hash"
if (-not $ExecuteRestoreTest) {
    Write-Host "Re-run with -ExecuteRestoreTest to restore into a temporary database, verify it, and remove it."
}
