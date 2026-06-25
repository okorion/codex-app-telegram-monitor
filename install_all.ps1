param(
    [switch]$SkipConfigure,
    [switch]$SkipTelegramTest,
    [switch]$SkipDailyMonitor,
    [switch]$SkipCommandListener,
    [switch]$SkipEnvFileAcl,
    [switch]$SkipBotCommandMenu
)

$ErrorActionPreference = "Stop"

$envFile = Join-Path $PSScriptRoot ".env"

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
    )

    Write-Host ""
    Write-Host "==> $Name"
    & $ScriptBlock
}

if (!$SkipConfigure) {
    if (Test-Path -LiteralPath $envFile) {
        Write-Host "Existing .env found. Keeping current Telegram configuration."
    } else {
        Invoke-Step -Name "Configure Telegram" -ScriptBlock {
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "configure-codex-telegram.ps1")
        }
    }
}

if (!(Test-Path -LiteralPath $envFile)) {
    throw "Codex Telegram .env is missing. Run configure-codex-telegram.ps1 first."
}

if (!$SkipEnvFileAcl) {
    Invoke-Step -Name "Protect local .env ACL" -ScriptBlock {
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "protect_env_file.ps1")
    }
}

if (!$SkipBotCommandMenu) {
    Invoke-Step -Name "Register Telegram command menu" -ScriptBlock {
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "register_bot_commands.ps1")
    }
}

if (!$SkipTelegramTest) {
    Invoke-Step -Name "Send Telegram test message" -ScriptBlock {
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "telegram-test.ps1")
    }
}

if (!$SkipDailyMonitor) {
    Invoke-Step -Name "Install daily 09:00 monitor" -ScriptBlock {
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "install_task.ps1")
    }
}

if (!$SkipCommandListener) {
    Invoke-Step -Name "Install Telegram command listener" -ScriptBlock {
        powershell.exe `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File (Join-Path $PSScriptRoot "install_command_listener_task.ps1") `
            -SkipEnvFileAcl `
            -SkipBotCommandMenu
    }
}

Invoke-Step -Name "Health check" -ScriptBlock {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "health-check.ps1")
}
