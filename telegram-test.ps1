param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "ensure-codex-app-with-telegram.ps1"
$envFile = Join-Path $PSScriptRoot ".env"

$arguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath,
    "-EnvFile", $envFile,
    "-TelegramTest"
)

if ($DryRun) {
    $arguments += "-DryRun"
}

& powershell.exe @arguments
