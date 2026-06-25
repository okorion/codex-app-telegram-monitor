param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env")
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "codex-monitor-common.ps1")

Protect-CodexEnvFile -Path $EnvFile
"Protected env file ACL: $EnvFile"
