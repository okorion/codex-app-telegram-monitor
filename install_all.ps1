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
    Write-Host "설치 요약"
    foreach ($step in $stepResults) {
        Write-Host "[$($step.Status)] $($step.Name) - $($step.Detail)"
        if ($step.Status -eq "FAIL" -and ![string]::IsNullOrWhiteSpace($step.NextCommand)) {
            Write-Host "      다음 명령: $($step.NextCommand)"
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
        Add-StepResult -Name $Name -Status "OK" -Detail "완료"
    } catch {
        Add-StepResult -Name $Name -Status "FAIL" -Detail $_.Exception.Message -NextCommand $NextCommand
        Write-StepSummary
        throw
    }
}

function Invoke-PreflightChecks {
    Write-Host ""
    Write-Host "==> 사전 점검"

    $powerShellOk = $PSVersionTable.PSVersion -ge [version]"5.1"
    Add-StepResult `
        -Name "사전 점검: PowerShell" `
        -Status $(if ($powerShellOk) { "OK" } else { "FAIL" }) `
        -Detail "버전 $($PSVersionTable.PSVersion)" `
        -NextCommand "Windows PowerShell 5.1 이상에서 실행하세요."

    $scheduledTaskCommand = Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue
    Add-StepResult `
        -Name "사전 점검: Task Scheduler cmdlet" `
        -Status $(if ($scheduledTaskCommand) { "OK" } else { "FAIL" }) `
        -Detail $(if ($scheduledTaskCommand) { "사용 가능" } else { "없음" }) `
        -NextCommand "ScheduledTasks PowerShell module이 있는 Windows에서 실행하세요."

    $executionPolicyRows = @(Get-ExecutionPolicy -List)
    $blockedPolicies = @($executionPolicyRows | Where-Object {
        $_.Scope -in @("MachinePolicy", "UserPolicy", "LocalMachine", "CurrentUser", "Process") -and
        $_.ExecutionPolicy -in @("Restricted", "AllSigned")
    })
    $policyStatus = if ($blockedPolicies.Count -gt 0) { "WARN" } else { "OK" }
    $policyDetail = ($executionPolicyRows | ForEach-Object { "$($_.Scope)=$($_.ExecutionPolicy)" }) -join "; "
    Add-StepResult `
        -Name "사전 점검: Execution policy" `
        -Status $policyStatus `
        -Detail $policyDetail

    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    Add-StepResult `
        -Name "사전 점검: git" `
        -Status $(if ($gitCommand) { "OK" } else { "WARN" }) `
        -Detail $(if ($gitCommand) { "사용 가능" } else { "없음; update.ps1의 git pull은 동작하지 않습니다" })

    $codexStartApps = @(Get-CodexStartAppCandidates)
    Add-StepResult `
        -Name "사전 점검: Codex StartApps 감지" `
        -Status $(if ($codexStartApps.Count -gt 0) { "OK" } else { "WARN" }) `
        -Detail "후보=$($codexStartApps.Count)"

    $failed = @($stepResults | Where-Object { ($_.Name -like "Preflight:*" -or $_.Name -like "사전 점검:*") -and $_.Status -eq "FAIL" })
    if ($failed.Count -gt 0) {
        throw "사전 점검에 실패했습니다. 위 설치 요약을 확인하세요."
    }
}

try {
    Invoke-PreflightChecks

    if (!$SkipConfigure) {
        if (Test-Path -LiteralPath $envFile) {
            Write-Host "기존 .env를 찾았습니다. 현재 Telegram 설정을 유지합니다."
            Add-StepResult -Name "Telegram 설정" -Status "OK" -Detail "기존 .env 유지"
        } else {
            Invoke-Step -Name "Telegram 설정" -NextCommand "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\configure-codex-telegram.ps1" -ScriptBlock {
                powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "configure-codex-telegram.ps1")
            }
        }
    } else {
        Add-StepResult -Name "Telegram 설정" -Status "WARN" -Detail "-SkipConfigure로 건너뜀"
    }

    if (!(Test-Path -LiteralPath $envFile)) {
        throw "Codex Telegram .env가 없습니다. configure-codex-telegram.ps1을 먼저 실행하세요."
    }

    if (!$SkipEnvFileAcl) {
        Invoke-Step -Name "로컬 .env ACL 보호" -NextCommand "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\protect_env_file.ps1" -ScriptBlock {
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "protect_env_file.ps1")
        }
    } else {
        Add-StepResult -Name "로컬 .env ACL 보호" -Status "WARN" -Detail "-SkipEnvFileAcl로 건너뜀"
    }

    if (!$SkipBotCommandMenu) {
        Invoke-Step -Name "Telegram 명령 메뉴 등록" -NextCommand "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register_bot_commands.ps1" -ScriptBlock {
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "register_bot_commands.ps1")
        }
    } else {
        Add-StepResult -Name "Telegram 명령 메뉴 등록" -Status "WARN" -Detail "-SkipBotCommandMenu로 건너뜀"
    }

    if (!$SkipTelegramTest) {
        Invoke-Step -Name "Telegram 테스트 메시지 전송" -NextCommand "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\telegram-test.ps1" -ScriptBlock {
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "telegram-test.ps1")
        }
    } else {
        Add-StepResult -Name "Telegram 테스트 메시지 전송" -Status "WARN" -Detail "-SkipTelegramTest로 건너뜀"
    }

    if (!$SkipDailyMonitor) {
        Invoke-Step -Name "매일 09:00 monitor 설치" -NextCommand "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_task.ps1" -ScriptBlock {
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "install_task.ps1")
        }
    } else {
        Add-StepResult -Name "매일 09:00 monitor 설치" -Status "WARN" -Detail "-SkipDailyMonitor로 건너뜀"
    }

    if (!$SkipCommandListener) {
        Invoke-Step -Name "Telegram command listener 설치" -NextCommand "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_command_listener_task.ps1" -ScriptBlock {
            powershell.exe `
                -NoProfile `
                -ExecutionPolicy Bypass `
                -File (Join-Path $PSScriptRoot "install_command_listener_task.ps1") `
                -SkipEnvFileAcl `
                -SkipBotCommandMenu
        }
    } else {
        Add-StepResult -Name "Telegram command listener 설치" -Status "WARN" -Detail "-SkipCommandListener로 건너뜀"
    }

    Invoke-Step -Name "상태 점검" -NextCommand "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\health-check.ps1" -ScriptBlock {
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "health-check.ps1")
    }

    Write-StepSummary
    Write-Host ""
    Write-Host "설치가 완료되었습니다."
    Write-Host "다음 확인: Codex bot에 /p, /s, /o를 순서대로 보내세요."
} catch {
    if ($stepResults.Count -eq 0 -or $stepResults[$stepResults.Count - 1].Status -ne "FAIL") {
        Add-StepResult -Name "설치" -Status "FAIL" -Detail $_.Exception.Message -NextCommand "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -SupportBundle"
        Write-StepSummary
    }
    Write-Host ""
    Write-Host "문제 해결용 명령:"
    Write-Host "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -SupportBundle"
    throw
}
