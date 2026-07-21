[CmdletBinding()]
param(
    [switch]$BuildImage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path $PSScriptRoot).Path
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Test-CommandAvailable {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        $script:errors.Add("Required command '$Name' is not available on PATH.")
        return $false
    }
    return $true
}

function Invoke-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    Write-Host "Checking $Description..." -ForegroundColor Cyan
    try {
        & $Action
        Write-Host "PASS: $Description" -ForegroundColor Green
    }
    catch {
        $script:errors.Add("$Description`: $($_.Exception.Message)")
        Write-Host "FAIL: $Description" -ForegroundColor Red
    }
}

Push-Location $repoRoot
try {
    if (-not (Test-CommandAvailable -Name "docker")) {
        throw "Docker is required."
    }

    Invoke-Check -Description "Docker daemon connectivity" -Action {
        & docker info --format '{{.ServerVersion}}' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Docker Desktop is not running." }
    }

    Invoke-Check -Description "Docker Compose v2" -Action {
        & docker compose version | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Docker Compose v2 is unavailable." }
    }

    $requiredFiles = @(
        "Dockerfile",
        "docker-compose.yml",
        ".dockerignore",
        ".env.example",
        "php-app/index.php",
        "php-app/create.php",
        "php-app/update.php",
        "php-app/delete.php",
        "php-app/livez.php",
        "php-app/readyz.php"
    )
    Invoke-Check -Description "repository file layout" -Action {
        $missing = $requiredFiles | Where-Object { -not (Test-Path -LiteralPath $_) }
        if ($missing) { throw "Missing: $($missing -join ', ')" }
    }

    if (-not (Test-Path -LiteralPath ".env")) {
        $warnings.Add(".env is absent. Copy .env.example to .env and replace every placeholder before starting Compose.")
    }

    $dockerfile = Get-Content -LiteralPath "Dockerfile" -Raw
    Invoke-Check -Description "non-root unprivileged container configuration" -Action {
        if ($dockerfile -notmatch '(?m)^USER\s+www-data\s*$') { throw "Dockerfile must run as www-data." }
        if ($dockerfile -notmatch '(?m)^EXPOSE\s+8080\s*$') { throw "Dockerfile must expose unprivileged port 8080." }
        if ($dockerfile -notmatch '(?m)^HEALTHCHECK\s') { throw "Dockerfile has no HEALTHCHECK." }
    }

    $temporaryValues = @{
        DB_PASSWORD = $env:DB_PASSWORD
        MYSQL_ROOT_PASSWORD = $env:MYSQL_ROOT_PASSWORD
        REDIS_PASSWORD = $env:REDIS_PASSWORD
    }
    try {
        if (-not $env:DB_PASSWORD) { $env:DB_PASSWORD = "validation-only-not-a-secret" }
        if (-not $env:MYSQL_ROOT_PASSWORD) { $env:MYSQL_ROOT_PASSWORD = "validation-only-not-a-secret" }
        if (-not $env:REDIS_PASSWORD) { $env:REDIS_PASSWORD = "validation-only-not-a-secret" }

        Invoke-Check -Description "Docker Compose rendering" -Action {
            & docker compose config --quiet
            if ($LASTEXITCODE -ne 0) { throw "docker compose config failed." }
        }
    }
    finally {
        $env:DB_PASSWORD = $temporaryValues.DB_PASSWORD
        $env:MYSQL_ROOT_PASSWORD = $temporaryValues.MYSQL_ROOT_PASSWORD
        $env:REDIS_PASSWORD = $temporaryValues.REDIS_PASSWORD
    }

    if ($BuildImage) {
        $tag = "cnas-php-app:validation-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
        try {
            Invoke-Check -Description "application image build" -Action {
                & docker build --tag $tag .
                if ($LASTEXITCODE -ne 0) { throw "docker build failed." }
            }
        }
        finally {
            & docker image rm --force $tag *> $null
        }
    }
    else {
        $warnings.Add("Image build was skipped. Re-run with -BuildImage before submission.")
    }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "Validation summary" -ForegroundColor Cyan
foreach ($warning in $warnings) {
    Write-Host "WARN: $warning" -ForegroundColor Yellow
}
foreach ($errorMessage in $errors) {
    Write-Host "ERROR: $errorMessage" -ForegroundColor Red
}

if ($errors.Count -gt 0) {
    exit 1
}

Write-Host "PASS: Docker repository validation completed with $($warnings.Count) warning(s)." -ForegroundColor Green
exit 0
