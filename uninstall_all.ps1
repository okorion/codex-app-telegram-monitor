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
        Write-Host "Missing, skipped: $Path"
        return
    }

    $root = (Resolve-Path -LiteralPath $PSScriptRoot).Path
    $target = (Resolve-Path -LiteralPath $Path).Path
    if (!$target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove path outside repository: $target"
    }

    Remove-Item -LiteralPath $target -Recurse -Force
    Write-Host "Removed: $target"
}

Invoke-UninstallStep -Name "Remove daily monitor task" -ScriptBlock {
    powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File (Join-Path $PSScriptRoot "uninstall_task.ps1")
}

Invoke-UninstallStep -Name "Remove command listener and watchdog tasks" -ScriptBlock {
    powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File (Join-Path $PSScriptRoot "uninstall_command_listener_task.ps1")
}

if ($RemoveEnv) {
    Invoke-UninstallStep -Name "Remove local .env" -ScriptBlock {
        Remove-RepoLocalPath -Path (Join-Path $PSScriptRoot ".env")
    }
} else {
    Write-Host ""
    Write-Host "[KEEP] .env retained. Pass -RemoveEnv to delete it."
}

if ($RemoveLogs) {
    Invoke-UninstallStep -Name "Remove logs" -ScriptBlock {
        Remove-RepoLocalPath -Path (Join-Path $PSScriptRoot "logs")
    }
} else {
    Write-Host "[KEEP] logs retained. Pass -RemoveLogs to delete them."
}

if ($RemoveState) {
    Invoke-UninstallStep -Name "Remove state" -ScriptBlock {
        Remove-RepoLocalPath -Path (Join-Path $PSScriptRoot "state")
    }
} else {
    Write-Host "[KEEP] state retained. Pass -RemoveState to delete it."
}

Write-Host ""
Write-Host "Uninstall complete."
