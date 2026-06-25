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
$stepResults = New-Object System.Collections.Generic.List[object]

function Add-StepResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail,
        [string]$NextCommand = ""
    )

    $stepResults.Add([PSCustomObject]@{
        Name = $Name
        Status = $Status
        Detail = $Detail
        NextCommand = $NextCommand
    }) | Out-Null
}

function Write-StepSummary {
    Write-Host ""
    Write-Host "Install summary"
    foreach ($step in $stepResults) {
        Write-Host "[$($step.Status)] $($step.Name) - $($step.Detail)"
        if ($step.Status -eq "FAIL" -and ![string]::IsNullOrWhiteSpace($step.NextCommand)) {
            Write-Host "      Next: $($step.NextCommand)"
        }
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [string]$NextCommand = ""
    )

    Write-Host ""
    Write-Host "==> $Name"
    try {
        & $ScriptBlock
        Add-StepResult -Name $Name -Status "OK" -Detail "Completed"
    } catch {
        Add-StepResult -Name $Name -Status "FAIL" -Detail $_.Exception.Message -NextCommand $NextCommand
        Write-StepSummary
        throw
    }
}

try {
    if (!$SkipConfigure) {
        if (Test-Path -LiteralPath $envFile) {
            Write-Host "Existing .env found. Keeping current Telegram configuration."
            Add-StepResult -Name "Configure Telegram" -Status "OK" -Detail "Existing .env kept"
        } else {
            Invoke-Step -Name "Configure Telegram" -NextCommand "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\configure-codex-telegram.ps1" -ScriptBlock {
                powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "configure-codex-telegram.ps1")
            }
        }
    } else {
        Add-StepResult -Name "Configure Telegram" -Status "WARN" -Detail "Skipped by -SkipConfigure"
    }

    if (!(Test-Path -LiteralPath $envFile)) {
        throw "Codex Telegram .env is missing. Run configure-codex-telegram.ps1 first."
    }

    if (!$SkipEnvFileAcl) {
        Invoke-Step -Name "Protect local .env ACL" -NextCommand "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\protect_env_file.ps1" -ScriptBlock {
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "protect_env_file.ps1")
        }
    } else {
        Add-StepResult -Name "Protect local .env ACL" -Status "WARN" -Detail "Skipped by -SkipEnvFileAcl"
    }

    if (!$SkipBotCommandMenu) {
        Invoke-Step -Name "Register Telegram command menu" -NextCommand "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register_bot_commands.ps1" -ScriptBlock {
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "register_bot_commands.ps1")
        }
    } else {
        Add-StepResult -Name "Register Telegram command menu" -Status "WARN" -Detail "Skipped by -SkipBotCommandMenu"
    }

    if (!$SkipTelegramTest) {
        Invoke-Step -Name "Send Telegram test message" -NextCommand "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\telegram-test.ps1" -ScriptBlock {
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "telegram-test.ps1")
        }
    } else {
        Add-StepResult -Name "Send Telegram test message" -Status "WARN" -Detail "Skipped by -SkipTelegramTest"
    }

    if (!$SkipDailyMonitor) {
        Invoke-Step -Name "Install daily 09:00 monitor" -NextCommand "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_task.ps1" -ScriptBlock {
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "install_task.ps1")
        }
    } else {
        Add-StepResult -Name "Install daily 09:00 monitor" -Status "WARN" -Detail "Skipped by -SkipDailyMonitor"
    }

    if (!$SkipCommandListener) {
        Invoke-Step -Name "Install Telegram command listener" -NextCommand "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_command_listener_task.ps1" -ScriptBlock {
            powershell.exe `
                -NoProfile `
                -ExecutionPolicy Bypass `
                -File (Join-Path $PSScriptRoot "install_command_listener_task.ps1") `
                -SkipEnvFileAcl `
                -SkipBotCommandMenu
        }
    } else {
        Add-StepResult -Name "Install Telegram command listener" -Status "WARN" -Detail "Skipped by -SkipCommandListener"
    }

    Invoke-Step -Name "Health check" -NextCommand "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\health-check.ps1" -ScriptBlock {
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "health-check.ps1")
    }

    Write-StepSummary
    Write-Host ""
    Write-Host "Install complete."
    Write-Host "Next Telegram checks: send /p, then /s, then /o to the Codex bot."
} catch {
    if ($stepResults.Count -eq 0 -or $stepResults[$stepResults.Count - 1].Status -ne "FAIL") {
        Add-StepResult -Name "Install" -Status "FAIL" -Detail $_.Exception.Message -NextCommand "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -SupportBundle"
        Write-StepSummary
    }
    Write-Host ""
    Write-Host "Troubleshooting command:"
    Write-Host "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -SupportBundle"
    throw
}
