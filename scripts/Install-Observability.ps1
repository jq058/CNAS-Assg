[CmdletBinding()]
param(
    [string]$KubeContext = "",
    [switch]$SkipMysqlExporter
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$KubePrometheusStackVersion = "86.0.0"
$BlackboxExporterVersion = "11.15.1"
$LokiVersion = "18.5.1"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ObservabilityDirectory = Join-Path $RepoRoot "k8s\observability"

function Assert-Command {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found on PATH."
    }
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    Write-Host "> $Command $($Arguments -join ' ')" -ForegroundColor DarkGray
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Command $($Arguments -join ' ')"
    }
}

function New-RandomPassword {
    param([int]$Length = 32)

    $alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
    $bytes = New-Object byte[] $Length
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }

    return -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
}

function Test-SecretExists {
    param(
        [Parameter(Mandatory = $true)][string]$Namespace,
        [Parameter(Mandatory = $true)][string]$Name
    )

    # Windows PowerShell 5.1 can promote native stderr to an ErrorRecord when
    # ErrorActionPreference is Stop. A missing Secret is expected here, so run
    # this existence probe with native errors suppressed and inspect its exit
    # code explicitly.
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "SilentlyContinue"
        & kubectl -n $Namespace get secret $Name -o name 1>$null 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Apply-SecretFromFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Namespace,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][hashtable]$Files
    )

    $arguments = @("-n", $Namespace, "create", "secret", "generic", $Name)
    foreach ($key in ($Files.Keys | Sort-Object)) {
        $arguments += "--from-file=$key=$($Files[$key])"
    }
    $arguments += @("--dry-run=client", "-o", "yaml")

    $secretYaml = & kubectl @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to render Secret '$Namespace/$Name'."
    }
    $secretYaml | & kubectl apply -f -
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to apply Secret '$Namespace/$Name'."
    }
}

Assert-Command -Name "kubectl"
Assert-Command -Name "helm"

if ($KubeContext) {
    Invoke-Checked -Command "kubectl" -Arguments @("config", "use-context", $KubeContext)
}

Invoke-Checked -Command "kubectl" -Arguments @("cluster-info")
Invoke-Checked -Command "kubectl" -Arguments @("apply", "-f", (Join-Path $ObservabilityDirectory "00-namespace.yaml"))

if (-not (& kubectl get namespace cnas -o name 2>$null)) {
    throw "Namespace 'cnas' is missing. Deploy the CNAS application before installing observability."
}

$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("cnas-observability-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

try {
    if (-not (Test-SecretExists -Namespace "monitoring" -Name "cnas-grafana-admin")) {
        $adminUserPath = Join-Path $temporaryDirectory "admin-user"
        $adminPasswordPath = Join-Path $temporaryDirectory "admin-password"
        [System.IO.File]::WriteAllText($adminUserPath, "admin")
        [System.IO.File]::WriteAllText($adminPasswordPath, (New-RandomPassword))
        Apply-SecretFromFiles -Namespace "monitoring" -Name "cnas-grafana-admin" -Files @{
            "admin-user" = $adminUserPath
            "admin-password" = $adminPasswordPath
        }
        Write-Host "Created a random Grafana administrator password in Secret monitoring/cnas-grafana-admin."
    }

    if (-not $SkipMysqlExporter) {
        $exporterPassword = $null
        if (Test-SecretExists -Namespace "cnas" -Name "mysql-exporter-secret") {
            $encodedPassword = & kubectl -n cnas get secret mysql-exporter-secret -o "jsonpath={.data.password}"
            if ($LASTEXITCODE -ne 0 -or -not $encodedPassword) {
                throw "Secret cnas/mysql-exporter-secret exists but has no 'password' key."
            }
            $exporterPassword = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedPassword))
        }
        else {
            $exporterPassword = New-RandomPassword
        }
        if ($exporterPassword -notmatch '^[A-Za-z0-9]{24,128}$') {
            throw "The existing MySQL exporter password must contain 24-128 ASCII letters or digits so it can be provisioned safely. Delete cnas/mysql-exporter-secret and rerun the installer to generate one."
        }

        $exporterPasswordPath = Join-Path $temporaryDirectory "mysql-exporter-password"
        $exporterConfigPath = Join-Path $temporaryDirectory "config.my.cnf"
        [System.IO.File]::WriteAllText($exporterPasswordPath, $exporterPassword)
        [System.IO.File]::WriteAllText(
            $exporterConfigPath,
            "[client]`nuser=exporter`npassword=$exporterPassword`nhost=mysql-service`nport=3306`n"
        )
        Apply-SecretFromFiles -Namespace "cnas" -Name "mysql-exporter-secret" -Files @{
            "password" = $exporterPasswordPath
            "config.my.cnf" = $exporterConfigPath
        }

        # Root access is deliberately used only over the local Unix socket in
        # the existing MySQL container. The exporter password travels over
        # stdin and is never placed in process arguments or a repository file.
        $mysqlPod = & kubectl -n cnas get pod -l app=mysql -o "jsonpath={.items[0].metadata.name}"
        if ($LASTEXITCODE -ne 0 -or -not $mysqlPod) {
            throw "No MySQL Pod was found for local exporter-user provisioning."
        }
        Invoke-Checked -Command "kubectl" -Arguments @(
            "-n", "cnas", "wait", "--for=condition=Ready", "pod/$mysqlPod", "--timeout=180s"
        )
        $exporterSql = @"
CREATE USER IF NOT EXISTS 'exporter'@'%' IDENTIFIED BY '$exporterPassword' WITH MAX_USER_CONNECTIONS 3;
ALTER USER 'exporter'@'%' IDENTIFIED BY '$exporterPassword' WITH MAX_USER_CONNECTIONS 3;
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';
FLUSH PRIVILEGES;
"@
        $exporterSql | & kubectl -n cnas exec -i $mysqlPod -c mysql -- /bin/sh -c 'export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"; exec mysql -uroot'
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to provision the least-privilege MySQL exporter account through the local MySQL socket."
        }
        Write-Host "Provisioned the MySQL exporter account through a local, non-network root connection."
    }

    Invoke-Checked -Command "helm" -Arguments @(
        "repo", "add", "prometheus-community",
        "https://prometheus-community.github.io/helm-charts",
        "--force-update"
    )
    Invoke-Checked -Command "helm" -Arguments @(
        "repo", "add", "grafana-community",
        "https://grafana-community.github.io/helm-charts",
        "--force-update"
    )
    Invoke-Checked -Command "helm" -Arguments @("repo", "update")

    Invoke-Checked -Command "helm" -Arguments @(
        "upgrade", "--install", "monitoring", "prometheus-community/kube-prometheus-stack",
        "--version", $KubePrometheusStackVersion,
        "--namespace", "monitoring",
        "--values", (Join-Path $ObservabilityDirectory "kube-prometheus-stack-values.yaml"),
        "--atomic", "--wait", "--timeout", "15m"
    )
    Invoke-Checked -Command "helm" -Arguments @(
        "upgrade", "--install", "loki", "grafana-community/loki",
        "--version", $LokiVersion,
        "--namespace", "monitoring",
        "--values", (Join-Path $ObservabilityDirectory "loki-values.yaml"),
        "--atomic", "--wait", "--timeout", "10m"
    )
    Invoke-Checked -Command "helm" -Arguments @(
        "upgrade", "--install", "blackbox", "prometheus-community/prometheus-blackbox-exporter",
        "--version", $BlackboxExporterVersion,
        "--namespace", "monitoring",
        "--values", (Join-Path $ObservabilityDirectory "blackbox-values.yaml"),
        "--atomic", "--wait", "--timeout", "10m"
    )

    Invoke-Checked -Command "kubectl" -Arguments @("apply", "-f", (Join-Path $ObservabilityDirectory "alloy.yaml"))
    Invoke-Checked -Command "kubectl" -Arguments @("apply", "-f", (Join-Path $ObservabilityDirectory "probes.yaml"))
    Invoke-Checked -Command "kubectl" -Arguments @("apply", "-f", (Join-Path $ObservabilityDirectory "prometheus-rules.yaml"))
    Invoke-Checked -Command "kubectl" -Arguments @("apply", "-f", (Join-Path $ObservabilityDirectory "grafana-dashboard.yaml"))

    if (-not $SkipMysqlExporter) {
        Invoke-Checked -Command "kubectl" -Arguments @("apply", "-f", (Join-Path $ObservabilityDirectory "mysql-exporter.yaml"))
        Invoke-Checked -Command "kubectl" -Arguments @(
            "-n", "cnas", "rollout", "status", "deployment/mysql-exporter", "--timeout=180s"
        )
    }

    Invoke-Checked -Command "kubectl" -Arguments @(
        "-n", "monitoring", "rollout", "status", "deployment/alloy", "--timeout=180s"
    )
}
finally {
    if (Test-Path $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}

Write-Host ""
Write-Host "Observability installation completed." -ForegroundColor Green
Write-Host "Grafana:    kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80"
Write-Host "Prometheus: kubectl -n monitoring port-forward svc/monitoring-prometheus 9090:9090"
Write-Host "Grafana password (do not paste it into the report):"
Write-Host "`$encoded = kubectl -n monitoring get secret cnas-grafana-admin -o 'jsonpath={.data.admin-password}'; [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(`$encoded))"
Write-Host "Next: .\scripts\Invoke-CnasValidation.ps1"
