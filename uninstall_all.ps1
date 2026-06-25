param(
    [switch]$RemoveEnv,
    [switch]$RemoveLogs,
    [switch]$RemoveState
)

$ErrorActionPreference = "Stop"

function Invoke-UninstallStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
    )

    Write-Host ""
    Write-Host "==> $Name"
    & $ScriptBlock
}

function Remove-RepoLocalPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (!(Test-Path -LiteralPath $Path)) {
        Write-Host "없어서 건너뜀: $Path"
        return
    }

    $root = (Resolve-Path -LiteralPath $PSScriptRoot).Path
    $target = (Resolve-Path -LiteralPath $Path).Path
    if (!$target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "repository 밖의 경로는 삭제하지 않습니다: $target"
    }

    Remove-Item -LiteralPath $target -Recurse -Force
    Write-Host "삭제됨: $target"
}

Invoke-UninstallStep -Name "daily monitor 작업 제거" -ScriptBlock {
    powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File (Join-Path $PSScriptRoot "uninstall_task.ps1")
}

Invoke-UninstallStep -Name "command listener 및 watchdog 작업 제거" -ScriptBlock {
    powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File (Join-Path $PSScriptRoot "uninstall_command_listener_task.ps1")
}

if ($RemoveEnv) {
    Invoke-UninstallStep -Name "로컬 .env 제거" -ScriptBlock {
        Remove-RepoLocalPath -Path (Join-Path $PSScriptRoot ".env")
    }
} else {
    Write-Host ""
    Write-Host "[유지] .env를 보존했습니다. 삭제하려면 -RemoveEnv를 지정하세요."
}

if ($RemoveLogs) {
    Invoke-UninstallStep -Name "logs 제거" -ScriptBlock {
        Remove-RepoLocalPath -Path (Join-Path $PSScriptRoot "logs")
    }
} else {
    Write-Host "[유지] logs를 보존했습니다. 삭제하려면 -RemoveLogs를 지정하세요."
}

if ($RemoveState) {
    Invoke-UninstallStep -Name "state 제거" -ScriptBlock {
        Remove-RepoLocalPath -Path (Join-Path $PSScriptRoot "state")
    }
} else {
    Write-Host "[유지] state를 보존했습니다. 삭제하려면 -RemoveState를 지정하세요."
}

Write-Host ""
Write-Host "제거가 완료되었습니다."
