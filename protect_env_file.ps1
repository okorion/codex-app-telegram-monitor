param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env")
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "codex-monitor-common.ps1")

Protect-CodexEnvFile -Path $EnvFile
"환경 파일 ACL 보호 완료: $EnvFile"
