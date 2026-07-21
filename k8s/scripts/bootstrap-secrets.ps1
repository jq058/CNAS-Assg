$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = (Resolve-Path (Join-Path $scriptDirectory '..\..')).Path
$requiredVariables = @('DB_USER', 'DB_PASSWORD', 'MYSQL_ROOT_PASSWORD', 'REDIS_PASSWORD')
$secretValues = @{}

foreach ($variableName in $requiredVariables) {
    $variableValue = [Environment]::GetEnvironmentVariable($variableName)
    if ([string]::IsNullOrWhiteSpace($variableValue)) {
        throw "Required environment variable is empty: $variableName"
    }
    if ($variableValue -match "[`r`n]") {
        throw "$variableName must not contain a newline."
    }
    $secretValues[$variableName] = $variableValue
}

& kubectl apply -f (Join-Path $repositoryRoot 'k8s\00-namespace.yaml')
if ($LASTEXITCODE -ne 0) { throw 'Unable to create the cnas namespace.' }

$secretManifest = @{
    apiVersion = 'v1'
    kind = 'Secret'
    metadata = @{
        name = 'cnas-secret'
        namespace = 'cnas'
    }
    type = 'Opaque'
    stringData = $secretValues
} | ConvertTo-Json -Depth 5

$secretManifest | & kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Unable to configure cnas-secret.' }

Write-Host 'Secret cnas/cnas-secret configured without writing credentials into the repository.'
