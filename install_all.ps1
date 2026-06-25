param(
    [switch]$SkipConfigure,
    [switch]$SkipTelegramTest,
    [switch]$SkipDailyMonitor,
    [switch]$SkipCommandListener,
    [switch]$SkipEnvFileAcl,
    [switch]$SkipBotCommandMenu
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "codex-monitor-common.ps1")

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

function Invoke-PreflightChecks {
    Write-Host ""
    Write-Host "==> Preflight checks"

    $powerShellOk = $PSVersionTable.PSVersion -ge [version]"5.1"
    Add-StepResult `
        -Name "Preflight: PowerShell" `
        -Status $(if ($powerShellOk) { "OK" } else { "FAIL" }) `
        -Detail "Version $($PSVersionTable.PSVersion)" `
        -NextCommand "Install or run with Windows PowerShell 5.1 or later."

    $scheduledTaskCommand = Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue
    Add-StepResult `
        -Name "Preflight: Task Scheduler cmdlets" `
        -Status $(if ($scheduledTaskCommand) { "OK" } else { "FAIL" }) `
        -Detail $(if ($scheduledTaskCommand) { "Available" } else { "Missing" }) `
        -NextCommand "Run on Windows with ScheduledTasks PowerShell module available."

    $executionPolicyRows = @(Get-ExecutionPolicy -List)
    $blockedPolicies = @($executionPolicyRows | Where-Object {
        $_.Scope -in @("MachinePolicy", "UserPolicy", "LocalMachine", "CurrentUser", "Process") -and
        $_.ExecutionPolicy -in @("Restricted", "AllSigned")
    })
    $policyStatus = if ($blockedPolicies.Count -gt 0) { "WARN" } else { "OK" }
    $policyDetail = ($executionPolicyRows | ForEach-Object { "$($_.Scope)=$($_.ExecutionPolicy)" }) -join "; "
    Add-StepResult `
        -Name "Preflight: Execution policy" `
        -Status $policyStatus `
        -Detail $policyDetail

    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    Add-StepResult `
        -Name "Preflight: git" `
        -Status $(if ($gitCommand) { "OK" } else { "WARN" }) `
        -Detail $(if ($gitCommand) { "Available" } else { "Missing; update.ps1 git pull will not work" })

    $codexStartApps = @(Get-CodexStartAppCandidates)
    Add-StepResult `
        -Name "Preflight: Codex StartApps detection" `
        -Status $(if ($codexStartApps.Count -gt 0) { "OK" } else { "WARN" }) `
        -Detail "Candidates=$($codexStartApps.Count)"

    $failed = @($stepResults | Where-Object { $_.Name -like "Preflight:*" -and $_.Status -eq "FAIL" })
    if ($failed.Count -gt 0) {
        throw "Preflight checks failed. See Install summary above."
    }
}

try {
    Invoke-PreflightChecks

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
