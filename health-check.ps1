$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "codex-monitor-common.ps1")

$envFile = Join-Path $PSScriptRoot ".env"
$monitorTaskName = "Ensure Codex App Running at 9AM"
$listenerTaskName = "Codex Telegram Command Listener"
$watchdogTaskName = "Codex Telegram Command Listener Watchdog"
$taskPath = "\Codex\"
$offsetFile = Join-Path $PSScriptRoot "state\telegram-command-offset.txt"
$heartbeatFile = Join-Path $PSScriptRoot "state\telegram-command-listener-heartbeat.txt"
$logFile = Join-Path $PSScriptRoot "logs\telegram-command-listener.log"
$toolVersion = Get-CodexToolVersion -Root $PSScriptRoot

function Get-TaskHealth {
    param(
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$TaskPath,
        [Parameter(Mandatory = $true)][string]$EnvFile
    )

    $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
    if (!$task) {
        return [PSCustomObject]@{
            Exists = $false
            UsesCodexEnv = $false
            State = $null
            NextRunTime = $null
            LastRunTime = $null
            LastTaskResult = $null
        }
    }

    $info = Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath $TaskPath
    $matchingActions = @(@($task.Actions) | Where-Object { $_.Arguments -like "*$EnvFile*" })
    $usesCodexEnv = $matchingActions.Count -gt 0

    return [PSCustomObject]@{
        Exists = $true
        UsesCodexEnv = $usesCodexEnv
        State = $task.State
        NextRunTime = $info.NextRunTime
        LastRunTime = $info.LastRunTime
        LastTaskResult = $info.LastTaskResult
    }
}

$envValues = Read-CodexDotEnvKeys -Path $envFile
$tokenPresent = ![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_BOT_TOKEN"])
$chatPresent = ![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_CHAT_ID"]) -or ![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_PERSONAL_CHAT_ID"])
$allowedChatIds = @()
if (![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_ALLOWED_CHAT_IDS"])) {
    $allowedChatIds = Split-CodexChatIds -Value $envValues["TELEGRAM_ALLOWED_CHAT_IDS"]
} else {
    $fallbackChatIds = @()
    if (![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_PERSONAL_CHAT_ID"])) {
        $fallbackChatIds += $envValues["TELEGRAM_PERSONAL_CHAT_ID"]
    }
    if (![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_CHAT_ID"])) {
        $fallbackChatIds += $envValues["TELEGRAM_CHAT_ID"]
    }
    $allowedChatIds = @($fallbackChatIds | Select-Object -Unique)
}

$commandAllowedChatIds = @()
if (![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_COMMAND_ALLOWED_CHAT_IDS"])) {
    $commandAllowedChatIds = Split-CodexChatIds -Value $envValues["TELEGRAM_COMMAND_ALLOWED_CHAT_IDS"]
} else {
    $commandAllowedChatIds = $allowedChatIds
}

$botReachable = Test-CodexTelegramBot -Token $envValues["TELEGRAM_BOT_TOKEN"]
$envFileProtected = Test-CodexEnvFileProtected -Path $envFile
$monitorTask = Get-TaskHealth -TaskName $monitorTaskName -TaskPath $taskPath -EnvFile $envFile
$listenerTask = Get-TaskHealth -TaskName $listenerTaskName -TaskPath $taskPath -EnvFile $envFile
$watchdogTask = Get-TaskHealth -TaskName $watchdogTaskName -TaskPath $taskPath -EnvFile $envFile
$heartbeatAt = Read-CodexListenerHeartbeat -Path $heartbeatFile
$heartbeatStaleSeconds = 120
if (![string]::IsNullOrWhiteSpace($envValues["CODEX_HEARTBEAT_STALE_SECONDS"])) {
    [int]::TryParse($envValues["CODEX_HEARTBEAT_STALE_SECONDS"], [ref]$heartbeatStaleSeconds) | Out-Null
}
$heartbeatAgeSeconds = if ($null -ne $heartbeatAt) { [math]::Max(0, [int]((Get-Date) - $heartbeatAt).TotalSeconds) } else { $null }
$heartbeatFresh = $null -ne $heartbeatAgeSeconds -and $heartbeatAgeSeconds -le $heartbeatStaleSeconds
$logFileSizeBytes = if (Test-Path -LiteralPath $logFile) { (Get-Item -LiteralPath $logFile).Length } else { 0 }
$deviceName = if (![string]::IsNullOrWhiteSpace($envValues["CODEX_DEVICE_NAME"]) -and $envValues["CODEX_DEVICE_NAME"] -ne "auto") {
    $envValues["CODEX_DEVICE_NAME"]
} else {
    $env:COMPUTERNAME
}

[PSCustomObject]@{
    ToolVersion = $toolVersion
    EnvFile = $envFile
    EnvFileExists = Test-Path -LiteralPath $envFile
    EnvFileAclProtected = $envFileProtected
    DeviceName = $deviceName
    TelegramBotTokenPresent = $tokenPresent
    TelegramChatIdPresent = $chatPresent
    TelegramAllowedChatIdsCount = $allowedChatIds.Count
    TelegramCommandAllowedChatIdsCount = $commandAllowedChatIds.Count
    TelegramBotReachable = $botReachable
    MonitorTaskExists = $monitorTask.Exists
    MonitorTaskUsesCodexEnv = $monitorTask.UsesCodexEnv
    MonitorTaskState = $monitorTask.State
    MonitorTaskNextRunTime = $monitorTask.NextRunTime
    CommandListenerTaskExists = $listenerTask.Exists
    CommandListenerTaskUsesCodexEnv = $listenerTask.UsesCodexEnv
    CommandListenerTaskState = $listenerTask.State
    CommandListenerLastRunTime = $listenerTask.LastRunTime
    CommandListenerLastTaskResult = $listenerTask.LastTaskResult
    CommandListenerWatchdogTaskExists = $watchdogTask.Exists
    CommandListenerWatchdogUsesCodexEnv = $watchdogTask.UsesCodexEnv
    CommandListenerWatchdogState = $watchdogTask.State
    CommandListenerWatchdogNextRunTime = $watchdogTask.NextRunTime
    CommandListenerWatchdogLastRunTime = $watchdogTask.LastRunTime
    CommandListenerWatchdogLastTaskResult = $watchdogTask.LastTaskResult
    CommandListenerOffsetFileExists = Test-Path -LiteralPath $offsetFile
    CommandListenerHeartbeatFileExists = Test-Path -LiteralPath $heartbeatFile
    CommandListenerHeartbeatAt = if ($heartbeatAt) { $heartbeatAt.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
    CommandListenerHeartbeatAgeSeconds = $heartbeatAgeSeconds
    CommandListenerHeartbeatFresh = $heartbeatFresh
    CommandListenerLogFileExists = Test-Path -LiteralPath $logFile
    CommandListenerLogSizeBytes = $logFileSizeBytes
} | Format-List

if (!$tokenPresent -or !$chatPresent) {
    exit 2
}

if ($monitorTask.Exists -and !$monitorTask.UsesCodexEnv) {
    exit 3
}

if ($listenerTask.Exists -and !$listenerTask.UsesCodexEnv) {
    exit 4
}

if ($watchdogTask.Exists -and !$watchdogTask.UsesCodexEnv) {
    exit 5
}

if (!$envFileProtected) {
    exit 6
}
