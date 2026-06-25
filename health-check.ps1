$ErrorActionPreference = "Stop"

$envFile = Join-Path $PSScriptRoot ".env"
$monitorTaskName = "Ensure Codex App Running at 9AM"
$listenerTaskName = "Codex Telegram Command Listener"
$watchdogTaskName = "Codex Telegram Command Listener Watchdog"
$taskPath = "\Codex\"
$offsetFile = Join-Path $PSScriptRoot "state\telegram-command-offset.txt"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Read-DotEnvKeys {
    param([Parameter(Mandatory = $true)][string]$Path)

    $result = @{}
    if (!(Test-Path -LiteralPath $Path)) {
        return $result
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') {
            $result[$matches[1]] = $matches[2].Trim()
        }
    }

    return $result
}

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

function Test-TelegramBot {
    param([AllowNull()][string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $false
    }

    try {
        $response = Invoke-RestMethod -Method Get -Uri "https://api.telegram.org/bot$Token/getMe" -TimeoutSec 15
        return [bool]$response.ok
    } catch {
        return $false
    }
}

$envValues = Read-DotEnvKeys -Path $envFile
$tokenPresent = ![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_BOT_TOKEN"])
$chatPresent = ![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_CHAT_ID"]) -or ![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_PERSONAL_CHAT_ID"])
$allowedChatIds = @()
if (![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_ALLOWED_CHAT_IDS"])) {
    $allowedChatIds = @($envValues["TELEGRAM_ALLOWED_CHAT_IDS"] -split "[,;\s]+" | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
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
$botReachable = Test-TelegramBot -Token $envValues["TELEGRAM_BOT_TOKEN"]

$monitorTask = Get-TaskHealth -TaskName $monitorTaskName -TaskPath $taskPath -EnvFile $envFile
$listenerTask = Get-TaskHealth -TaskName $listenerTaskName -TaskPath $taskPath -EnvFile $envFile
$watchdogTask = Get-TaskHealth -TaskName $watchdogTaskName -TaskPath $taskPath -EnvFile $envFile

[PSCustomObject]@{
    EnvFile = $envFile
    EnvFileExists = Test-Path -LiteralPath $envFile
    TelegramBotTokenPresent = $tokenPresent
    TelegramChatIdPresent = $chatPresent
    TelegramAllowedChatIdsCount = $allowedChatIds.Count
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
