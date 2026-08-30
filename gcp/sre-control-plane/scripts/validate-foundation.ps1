[CmdletBinding()]
param(
    [switch]$BuildContainer
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
$terraformDir = Join-Path $repoRoot "gcp/sre-control-plane/terraform"

Push-Location $terraformDir
try {
    terraform fmt -check -recursive
    terraform init -backend=false
    terraform validate
}
finally {
    Pop-Location
}

if ($BuildContainer) {
    docker build --tag sre-control-plane:local-check $repoRoot
}
