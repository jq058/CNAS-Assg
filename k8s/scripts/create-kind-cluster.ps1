$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = (Resolve-Path (Join-Path $scriptDirectory '..\..')).Path
$kindNodeImage = 'kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5'
$minimumKindVersion = [version]'0.32.0'

if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
    throw 'Required command is missing: kind'
}

$kindVersionOutput = (& kind version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $kindVersionOutput -notmatch 'v(?<version>\d+\.\d+\.\d+)') {
    throw "Unable to determine the installed Kind version from: $kindVersionOutput"
}

$installedKindVersion = [version]$Matches.version
if ($installedKindVersion -lt $minimumKindVersion) {
    throw "Kind v$minimumKindVersion or newer is required; found v$installedKindVersion."
}

$clusters = @(& kind get clusters)
if ($clusters -notcontains 'cnas-cluster') {
    & kind create cluster --config (Join-Path $repositoryRoot 'kind-cluster.yaml') --image $kindNodeImage
    if ($LASTEXITCODE -ne 0) { throw 'Kind cluster creation failed.' }
} else {
    Write-Host 'Using existing cnas-cluster; no cluster was deleted or recreated.'
    & kubectl config use-context kind-cnas-cluster *> $null
}

& (Join-Path $scriptDirectory 'install-platform.ps1')
