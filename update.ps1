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
    Invoke-UpdateStep -Name "Pull latest repository changes" -ScriptBlock {
        $git = Get-Command git.exe -ErrorAction SilentlyContinue
        if (!$git) {
            throw "git.exe is not available. Re-run with -SkipGitPull after updating the files manually."
        }

        git -C $PSScriptRoot pull --ff-only
        if ($LASTEXITCODE -ne 0) {
            throw "git pull --ff-only failed."
        }
    }
}

if (!$SkipInstall) {
    Invoke-UpdateStep -Name "Refresh scheduled tasks and local protection" -ScriptBlock {
        powershell.exe `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File (Join-Path $PSScriptRoot "install_all.ps1") `
            -SkipConfigure `
            -SkipTelegramTest
    }
}

if (!$SkipRestartListener) {
    Invoke-UpdateStep -Name "Restart command listener task" -ScriptBlock {
        $task = Get-ScheduledTask -TaskName $listenerTaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
        if (!$task) {
            Write-Host "Command listener task is not installed. Skipping restart."
            return
        }

        Stop-ScheduledTask -TaskName $listenerTaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
        Start-ScheduledTask -TaskName $listenerTaskName -TaskPath $taskPath
    }
}

Invoke-UpdateStep -Name "Run diagnostics" -ScriptBlock {
    powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File (Join-Path $PSScriptRoot "diagnose.ps1")
}

Write-Host ""
Write-Host "Update complete."
Write-Host "Recommended Telegram checks: send /p, then /s, then /o to the Codex bot."
