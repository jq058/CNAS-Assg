$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = (Resolve-Path (Join-Path $scriptDirectory '..\..')).Path
foreach ($commandName in @('kubectl', 'openssl')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Required command is missing: $commandName"
    }
}

& kubectl apply -f (Join-Path $repositoryRoot 'k8s\00-namespace.yaml')
if ($LASTEXITCODE -ne 0) { throw 'Unable to create the cnas namespace.' }

$certificateDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("cnas-tls-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $certificateDirectory | Out-Null

try {
    $certificatePath = Join-Path $certificateDirectory 'tls.crt'
    $privateKeyPath = Join-Path $certificateDirectory 'tls.key'
    & openssl req -x509 -newkey rsa:2048 -sha256 -nodes `
        -days 30 `
        -keyout $privateKeyPath `
        -out $certificatePath `
        -subj '/CN=cnas.local' `
        -addext 'subjectAltName=DNS:cnas.local'
    if ($LASTEXITCODE -ne 0) { throw 'OpenSSL certificate generation failed.' }

    $tlsManifest = & kubectl -n cnas create secret tls cnas-local-tls `
        --cert=$certificatePath `
        --key=$privateKeyPath `
        --dry-run=client `
        -o yaml
    $tlsManifest | & kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { throw 'Unable to configure cnas-local-tls.' }
} finally {
    Remove-Item -LiteralPath $privateKeyPath, $certificatePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $certificateDirectory -Force -ErrorAction SilentlyContinue
}

Write-Host 'Local self-signed TLS Secret created. Use a trusted issuer outside the coursework Kind cluster.'
