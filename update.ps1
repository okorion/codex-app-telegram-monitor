param(
    [switch]$SkipGitPull,
    [switch]$SkipInstall,
    [switch]$SkipRestartListener
)

$ErrorActionPreference = "Stop"

$taskPath = "\Codex\"
$listenerTaskName = "Codex Telegram Command Listener"

function Invoke-UpdateStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
    )

    Write-Host ""
    Write-Host "==> $Name"
    & $ScriptBlock
}

if (!$SkipGitPull) {
    Invoke-UpdateStep -Name "최신 repository 변경 가져오기" -ScriptBlock {
        $git = Get-Command git.exe -ErrorAction SilentlyContinue
        if (!$git) {
            throw "git.exe를 찾을 수 없습니다. 파일을 수동으로 업데이트한 뒤 -SkipGitPull로 다시 실행하세요."
        }

        git -C $PSScriptRoot pull --ff-only
        if ($LASTEXITCODE -ne 0) {
            throw "git pull --ff-only에 실패했습니다."
        }
    }
}

if (!$SkipInstall) {
    Invoke-UpdateStep -Name "예약 작업과 로컬 보호 설정 갱신" -ScriptBlock {
        powershell.exe `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File (Join-Path $PSScriptRoot "install_all.ps1") `
            -SkipConfigure `
            -SkipTelegramTest
    }
}

if (!$SkipRestartListener) {
    Invoke-UpdateStep -Name "command listener 작업 재시작" -ScriptBlock {
        $task = Get-ScheduledTask -TaskName $listenerTaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
        if (!$task) {
            Write-Host "command listener 작업이 설치되어 있지 않습니다. 재시작을 건너뜁니다."
            return
        }

        Stop-ScheduledTask -TaskName $listenerTaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
        Start-ScheduledTask -TaskName $listenerTaskName -TaskPath $taskPath
    }
}

Invoke-UpdateStep -Name "진단 실행" -ScriptBlock {
    powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File (Join-Path $PSScriptRoot "diagnose.ps1")
}

Write-Host ""
Write-Host "업데이트가 완료되었습니다."
Write-Host "권장 Telegram 확인: Codex bot에 /p, /s, /o를 순서대로 보내세요."
