param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env"),
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "codex-monitor-common.ps1")

Import-CodexDotEnv -Path $EnvFile

if ($DryRun) {
    Get-CodexTelegramBotCommandDefinitions |
        ForEach-Object { "/$($_.command) - $($_.description)" }
    exit 0
}

Set-CodexTelegramBotCommands
"Telegram command menu registered."
