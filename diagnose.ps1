param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env"),
    [switch]$SupportBundle
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "codex-monitor-common.ps1")

$taskPath = "\Codex\"
$monitorTaskName = "Ensure Codex App Running at 9AM"
$listenerTaskName = "Codex Telegram Command Listener"
$watchdogTaskName = "Codex Telegram Command Listener Watchdog"
$offsetFile = Join-Path $PSScriptRoot "state\telegram-command-offset.txt"
$heartbeatFile = Join-Path $PSScriptRoot "state\telegram-command-listener-heartbeat.txt"
$logFile = Join-Path $PSScriptRoot "logs\telegram-command-listener.log"

function New-DiagnosticRow {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail,
        [string]$Fix = ""
    )

    return [PSCustomObject]@{
        Name = $Name
        Status = $Status
        Detail = $Detail
        Fix = $Fix
    }
}

function Get-TaskDiagnostic {
    param([Parameter(Mandatory = $true)][string]$TaskName)

    $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    if (!$task) {
        return New-DiagnosticRow -Name $TaskName -Status "FAIL" -Detail "Scheduled task is missing." -Fix "Run install_all.ps1 or the matching install script."
    }

    $info = Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath $taskPath
    $usesEnv = @(@($task.Actions) | Where-Object { $_.Arguments -like "*$EnvFile*" }).Count -gt 0
    $status = if ($usesEnv) { "OK" } else { "WARN" }
    $detail = "State=$($task.State); NextRun=$($info.NextRunTime); LastRun=$($info.LastRunTime); LastResult=$($info.LastTaskResult); Env=$usesEnv"
    $fix = if ($usesEnv) { "" } else { "Reinstall the task so it points to this repo .env file." }
    return New-DiagnosticRow -Name $TaskName -Status $status -Detail $detail -Fix $fix
}

function Get-HeartbeatDiagnostic {
    $heartbeatAt = Read-CodexListenerHeartbeat -Path $heartbeatFile
    if ($null -eq $heartbeatAt) {
        return New-DiagnosticRow -Name "Listener heartbeat" -Status "WARN" -Detail "Heartbeat file is missing or unreadable." -Fix "Start or reinstall the command listener task."
    }

    $ageSeconds = [math]::Max(0, [int]((Get-Date) - $heartbeatAt).TotalSeconds)
    $staleSeconds = Get-CodexIntEnvOrDefault -Name "CODEX_HEARTBEAT_STALE_SECONDS" -DefaultValue 120 -MinValue 30
    $status = if ($ageSeconds -le $staleSeconds) { "OK" } else { "WARN" }
    $fix = if ($status -eq "OK") { "" } else { "Run ensure_command_listener_running.ps1 or reinstall the command listener." }
    return New-DiagnosticRow -Name "Listener heartbeat" -Status $status -Detail "Last=$($heartbeatAt.ToString("yyyy-MM-dd HH:mm:ss")); Age=${ageSeconds}s; StaleAfter=${staleSeconds}s" -Fix $fix
}

function Format-DiagnosticRows {
    param([Parameter(Mandatory = $true)][object[]]$Rows)

    $lines = @()
    foreach ($row in $Rows) {
        $lines += "[$($row.Status)] $($row.Name) - $($row.Detail)"
        if (![string]::IsNullOrWhiteSpace($row.Fix)) {
            $lines += "      Fix: $($row.Fix)"
        }
    }
    return $lines
}

function Get-RedactedEnvSummary {
    param([hashtable]$EnvValues)

    $keys = @(
        "TELEGRAM_BOT_TOKEN",
        "TELEGRAM_CHAT_ID",
        "TELEGRAM_PERSONAL_CHAT_ID",
        "TELEGRAM_ALLOWED_CHAT_IDS",
        "TELEGRAM_COMMAND_ALLOWED_CHAT_IDS",
        "CODEX_MONITOR_TITLE",
        "CODEX_DEVICE_NAME",
        "CODEX_APP_USER_MODEL_ID",
        "CODEX_PROCESS_PATH_PATTERN",
        "CODEX_LOG_MAX_BYTES",
        "CODEX_LOG_KEEP_FILES",
        "CODEX_HEARTBEAT_STALE_SECONDS"
    )

    foreach ($key in $keys) {
        $value = if ($EnvValues.ContainsKey($key)) { $EnvValues[$key] } else { "" }
        if ($key -like "TELEGRAM_*") {
            if ([string]::IsNullOrWhiteSpace($value)) {
                "$key=<missing>"
            } else {
                "$key=<redacted>"
            }
        } else {
            "$key=$value"
        }
    }
}

$toolVersion = Get-CodexToolVersion -Root $PSScriptRoot
$envExists = Test-Path -LiteralPath $EnvFile
$envValues = Read-CodexDotEnvKeys -Path $EnvFile
if ($envExists) {
    Import-CodexDotEnv -Path $EnvFile
}

$tokenPresent = ![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_BOT_TOKEN"])
$chatPresent = ![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_CHAT_ID"]) -or ![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_PERSONAL_CHAT_ID"])
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

if (![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_COMMAND_ALLOWED_CHAT_IDS"])) {
    $commandAllowedChatIds = Split-CodexChatIds -Value $envValues["TELEGRAM_COMMAND_ALLOWED_CHAT_IDS"]
} else {
    $commandAllowedChatIds = $allowedChatIds
}
$botReachable = if ($tokenPresent) { Test-CodexTelegramBot -Token $envValues["TELEGRAM_BOT_TOKEN"] } else { $false }
$envProtected = Test-CodexEnvFileProtected -Path $EnvFile

$settings = if ($envExists) { Resolve-CodexAppSettings } else { @{ AppUserModelId = ""; ProcessPathPattern = $script:CodexDefaultProcessPathPattern } }
$detection = Get-CodexDetectionSummary -ProcessPathPattern $settings.ProcessPathPattern
$matchingProcessCount = $detection.MatchingProcessCount
$logExists = Test-Path -LiteralPath $logFile
$logSize = if ($logExists) { (Get-Item -LiteralPath $logFile).Length } else { 0 }
$lastLogLines = if ($logExists) { @(Get-Content -LiteralPath $logFile -Tail 10 | ForEach-Object { ConvertTo-CodexRedactedText -Text $_ }) } else { @() }

$rows = @()
$rows += New-DiagnosticRow -Name "Tool version" -Status "OK" -Detail $toolVersion
$rows += New-DiagnosticRow -Name ".env" -Status $(if ($envExists) { "OK" } else { "FAIL" }) -Detail $(if ($envExists) { "Found" } else { "Missing" }) -Fix $(if ($envExists) { "" } else { "Run configure-codex-telegram.ps1." })
$rows += New-DiagnosticRow -Name ".env ACL" -Status $(if ($envProtected) { "OK" } else { "WARN" }) -Detail $(if ($envProtected) { "Protected" } else { "Not protected" }) -Fix $(if ($envProtected) { "" } else { "Run protect_env_file.ps1." })
$rows += New-DiagnosticRow -Name "Telegram token" -Status $(if ($tokenPresent) { "OK" } else { "FAIL" }) -Detail $(if ($tokenPresent) { "Present" } else { "Missing" }) -Fix $(if ($tokenPresent) { "" } else { "Run configure-codex-telegram.ps1." })
$rows += New-DiagnosticRow -Name "Telegram chat" -Status $(if ($chatPresent) { "OK" } else { "FAIL" }) -Detail $(if ($chatPresent) { "Configured" } else { "Missing" }) -Fix $(if ($chatPresent) { "" } else { "Send /start to the bot and rerun configure-codex-telegram.ps1." })
$rows += New-DiagnosticRow -Name "Telegram API" -Status $(if ($botReachable) { "OK" } else { "FAIL" }) -Detail $(if ($botReachable) { "Reachable" } else { "Unavailable" }) -Fix $(if ($botReachable) { "" } else { "Check bot token and network access." })
$allowedChatStatus = if ($allowedChatIds.Count -gt 0 -and $commandAllowedChatIds.Count -gt 0) { "OK" } else { "WARN" }
$allowedChatFix = if ($allowedChatStatus -eq "OK") { "" } else { "Set TELEGRAM_ALLOWED_CHAT_IDS and TELEGRAM_COMMAND_ALLOWED_CHAT_IDS when using groups or multiple chats." }
$rows += New-DiagnosticRow -Name "Allowed chats" -Status $allowedChatStatus -Detail "Notification=$($allowedChatIds.Count); Command=$($commandAllowedChatIds.Count)" -Fix $allowedChatFix
$rows += Get-TaskDiagnostic -TaskName $monitorTaskName
$rows += Get-TaskDiagnostic -TaskName $listenerTaskName
$rows += Get-TaskDiagnostic -TaskName $watchdogTaskName
$rows += Get-HeartbeatDiagnostic
$rows += New-DiagnosticRow -Name "Codex StartApps" -Status $(if ($detection.StartAppCount -gt 0) { "OK" } else { "WARN" }) -Detail "Candidates=$($detection.StartAppCount)" -Fix $(if ($detection.StartAppCount -gt 0) { "" } else { "Set CODEX_APP_USER_MODEL_ID manually if Codex cannot be launched." })
$rows += New-DiagnosticRow -Name "Codex Appx package" -Status $(if ($detection.AppxPackageCount -gt 0) { "OK" } else { "WARN" }) -Detail "Candidates=$($detection.AppxPackageCount)"
$rows += New-DiagnosticRow -Name "Codex process" -Status $(if ($matchingProcessCount -gt 0) { "OK" } else { "WARN" }) -Detail "Matching=$matchingProcessCount; AnyCodex=$($detection.CodexProcessCount); Pattern=$($settings.ProcessPathPattern)" -Fix $(if ($matchingProcessCount -gt 0) { "" } else { "Start Codex or set CODEX_PROCESS_PATH_PATTERN manually." })
$rows += New-DiagnosticRow -Name "Listener log" -Status $(if ($logExists) { "OK" } else { "WARN" }) -Detail $(if ($logExists) { "$logSize bytes" } else { "Missing" })

$failed = @($rows | Where-Object { $_.Status -eq "FAIL" }).Count
$warned = @($rows | Where-Object { $_.Status -eq "WARN" }).Count
$overall = if ($failed -gt 0) { "FAIL" } elseif ($warned -gt 0) { "WARN" } else { "OK" }

$output = @(
    "Codex App Telegram Monitor diagnostics",
    "Generated at: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))",
    "Tool version: $toolVersion",
    "Overall: $overall",
    ""
)
$output += Format-DiagnosticRows -Rows $rows

if ($SupportBundle) {
    $output += ""
    $output += "Environment summary (redacted):"
    $output += Get-RedactedEnvSummary -EnvValues $envValues
    $output += ""
    $output += "Codex detection:"
    $output += "StartApps:"
    $output += @($detection.StartApps | ForEach-Object { "  Name=$($_.Name); AppID=$($_.AppID)" })
    $output += "Appx packages:"
    $output += @($detection.AppxPackages | ForEach-Object { "  Name=$($_.Name); Version=$($_.Version); PackageFullName=$($_.PackageFullName)" })
    $output += "Processes:"
    $output += @($detection.Processes | ForEach-Object { "  Id=$($_.Id); Path=$(ConvertTo-CodexRedactedText -Text $_.Path)" })
    $output += ""
    $output += "Recent listener logs (redacted):"
    $output += $lastLogLines
    $output += ""
    $output += "System:"
    $output += "PowerShell=$($PSVersionTable.PSVersion)"
    $output += "OS=$([Environment]::OSVersion.VersionString)"
    $output += "ComputerName=$env:COMPUTERNAME"
}

($output | ForEach-Object { ConvertTo-CodexRedactedText -Text $_ }) -join "`n"

if ($overall -eq "FAIL") {
    exit 2
}
