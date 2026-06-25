param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env")
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "codex-monitor-common.ps1")

$taskName = "Codex Telegram Command Listener"
$taskPath = "\Codex\"
$heartbeatFile = Join-Path $PSScriptRoot "state\telegram-command-listener-heartbeat.txt"
$watchdogLogFile = Join-Path $PSScriptRoot "logs\telegram-command-listener-watchdog.log"

function Write-WatchdogLog {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-CodexLog -Path $watchdogLogFile -Message $Message
}

function Get-WatchdogHeartbeatSnapshot {
    $heartbeatAt = Read-CodexListenerHeartbeat -Path $heartbeatFile
    $staleSeconds = Get-CodexIntEnvOrDefault -Name "CODEX_HEARTBEAT_STALE_SECONDS" -DefaultValue 120 -MinValue 30
    $ageSeconds = $null
    $fresh = $false
    if ($null -ne $heartbeatAt) {
        $ageSeconds = [math]::Max(0, [int]((Get-Date) - $heartbeatAt).TotalSeconds)
        $fresh = $ageSeconds -le $staleSeconds
    }

    return @{
        At = $heartbeatAt
        StaleSeconds = $staleSeconds
        AgeSeconds = $ageSeconds
        Fresh = $fresh
    }
}

if (Test-Path -LiteralPath $EnvFile) {
    Import-CodexDotEnv -Path $EnvFile
}

$heartbeat = Get-WatchdogHeartbeatSnapshot

$task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
if (!$task) {
    throw "예약 작업을 찾을 수 없습니다: $taskPath$taskName"
}

$restarted = $false
$restartReason = ""
if ($task.State -eq "Running" -and !$heartbeat.Fresh) {
    $restartReason = if ($null -eq $heartbeat.At) { "missing heartbeat" } else { "stale heartbeat ($($heartbeat.AgeSeconds)s > $($heartbeat.StaleSeconds)s)" }
    Write-WatchdogLog "Listener 작업은 Running이지만 $restartReason 상태라 재시작합니다."
    Stop-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-ScheduledTask -TaskName $taskName -TaskPath $taskPath
    Start-Sleep -Seconds 2
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath
    $restarted = $true
} elseif ($task.State -ne "Running") {
    $restartReason = "task state $($task.State)"
    Write-WatchdogLog "Listener 작업이 $($task.State) 상태라 시작합니다."
    Start-ScheduledTask -TaskName $taskName -TaskPath $taskPath
    Start-Sleep -Seconds 2
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath
    $restarted = $true
}

if ($restarted) {
    Start-Sleep -Seconds 5
    $heartbeat = Get-WatchdogHeartbeatSnapshot
}

$info = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath $taskPath

[PSCustomObject]@{
    TaskName = $task.TaskName
    TaskPath = $task.TaskPath
    State = $task.State
    LastRunTime = $info.LastRunTime
    LastTaskResult = $info.LastTaskResult
    HeartbeatAt = if ($heartbeat.At) { $heartbeat.At.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
    HeartbeatAgeSeconds = $heartbeat.AgeSeconds
    HeartbeatFresh = $heartbeat.Fresh
    HeartbeatStaleSeconds = $heartbeat.StaleSeconds
    Restarted = $restarted
    RestartReason = $restartReason
    EnvFile = $EnvFile
} | Format-List
