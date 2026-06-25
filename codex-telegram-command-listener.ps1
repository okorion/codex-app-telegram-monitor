param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env"),
    [int]$PollSeconds = 2,
    [int]$TelegramTimeoutSeconds = 25,
    [switch]$Once,
    [switch]$InitializeOffset,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "codex-monitor-common.ps1")

$StateDir = Join-Path $PSScriptRoot "state"
$LogDir = Join-Path $PSScriptRoot "logs"
$OffsetFile = Join-Path $StateDir "telegram-command-offset.txt"
$HeartbeatFile = Join-Path $StateDir "telegram-command-listener-heartbeat.txt"
$LogFile = Join-Path $LogDir "telegram-command-listener.log"
$MonitorTaskName = "Ensure Codex App Running at 9AM"
$ListenerTaskName = "Codex Telegram Command Listener"
$WatchdogTaskName = "Codex Telegram Command Listener Watchdog"
$TaskPath = "\Codex\"
$CodexAppUserModelId = $script:CodexDefaultAppUserModelId
$CodexProcessPathPattern = $script:CodexDefaultProcessPathPattern
$MessageTitle = $script:CodexDefaultMessageTitle
$DeviceName = "Windows PC"

function Ensure-LocalFolders {
    Ensure-CodexDirectory -Path $StateDir
    Ensure-CodexDirectory -Path $LogDir
}

function Get-LogMaxBytes {
    return Get-CodexInt64EnvOrDefault -Name "CODEX_LOG_MAX_BYTES" -DefaultValue 1048576 -MinValue 1024
}

function Get-LogKeepFiles {
    return Get-CodexIntEnvOrDefault -Name "CODEX_LOG_KEEP_FILES" -DefaultValue 5 -MinValue 1
}

function Write-ListenerLog {
    param([Parameter(Mandatory = $true)][string]$Message)

    Ensure-LocalFolders
    Write-CodexLog `
        -Path $LogFile `
        -Message $Message `
        -MaxBytes (Get-LogMaxBytes) `
        -KeepFiles (Get-LogKeepFiles)
}

function Save-ListenerHeartbeat {
    Save-CodexListenerHeartbeat -Path $HeartbeatFile
}

function Get-ListenerHeartbeatStatus {
    $heartbeatAt = Read-CodexListenerHeartbeat -Path $HeartbeatFile
    $staleSeconds = Get-CodexIntEnvOrDefault -Name "CODEX_HEARTBEAT_STALE_SECONDS" -DefaultValue 120 -MinValue 30

    if ($null -eq $heartbeatAt) {
        return @{
            Exists = $false
            Timestamp = $null
            TimestampText = "Missing"
            AgeText = "unknown"
            AgeSeconds = $null
            Fresh = $false
            StaleSeconds = $staleSeconds
        }
    }

    $ageSeconds = [math]::Max(0, [int]((Get-Date) - $heartbeatAt).TotalSeconds)
    return @{
        Exists = $true
        Timestamp = $heartbeatAt
        TimestampText = $heartbeatAt.ToString("yyyy-MM-dd HH:mm:ss")
        AgeText = Get-CodexAgeText -Timestamp $heartbeatAt
        AgeSeconds = $ageSeconds
        Fresh = $ageSeconds -le $staleSeconds
        StaleSeconds = $staleSeconds
    }
}

function Test-AllowedChatId {
    param([Parameter(Mandatory = $true)][string]$ChatId)

    return Test-CodexChatIdAllowed -ChatId $ChatId -AllowedChatIds @(Get-CodexCommandAllowedChatIds)
}

function Send-TelegramMessage {
    param(
        [Parameter(Mandatory = $true)][string]$ChatId,
        [Parameter(Mandatory = $true)][string]$Message
    )

    Send-CodexTelegramMessage -ChatId $ChatId -Message $Message -DryRun:$DryRun
}

function Get-CodexAppProcessList {
    return @(Get-CodexAppProcesses -ProcessPathPattern $CodexProcessPathPattern)
}

function Wait-CodexAppRunning {
    param(
        [int]$TimeoutSeconds = 60,
        [int]$IntervalSeconds = 2
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $processes = Get-CodexAppProcessList
        if ($processes.Count -gt 0) {
            return @{
                Badge = "OK"
                Icon = "✅"
                CurrentState = "실행 중"
                Notice = "Codex 앱 자동 실행이 완료되었습니다."
                ProcessCount = $processes.Count
            }
        }

        if ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds $IntervalSeconds
        }
    } while ((Get-Date) -lt $deadline)

    $finalProcesses = Get-CodexAppProcessList
    if ($finalProcesses.Count -gt 0) {
        return @{
            Badge = "OK"
            Icon = "✅"
            CurrentState = "실행 중"
            Notice = "Codex 앱 자동 실행이 완료되었습니다."
            ProcessCount = $finalProcesses.Count
        }
    }

    return @{
        Badge = "WARN"
        Icon = "⚠️"
        CurrentState = "미실행"
        ProcessCount = 0
    }
}

function Invoke-CodexRemoteStart {
    param([Parameter(Mandatory = $true)][string]$ChatId)

    $before = Get-CodexAppProcessList
    if ($before.Count -gt 0) {
        $alreadyRunning = @{
            Badge = "OK"
            Icon = "✅"
            BeforeState = "실행 중"
            CurrentState = "실행 중"
            ProcessCount = $before.Count
        }
        Send-TelegramMessage -ChatId $ChatId -Message (New-ResultMessage -ResultLabel "원격 실행 결과" -Result $alreadyRunning)
        return
    }

    if ($DryRun) {
        $dryRunResult = @{
            Badge = "DRY-RUN"
            Icon = "ℹ️"
            BeforeState = "미실행"
            CurrentState = "미실행"
            ProcessCount = 0
        }
        Send-TelegramMessage -ChatId $ChatId -Message (New-ResultMessage -ResultLabel "원격 실행 결과" -Result $dryRunResult)
        return
    }

    try {
        Start-CodexApp -AppUserModelId $CodexAppUserModelId
    } catch {
        $failedRequest = @{
            Badge = "WARN"
            Icon = "⚠️"
            BeforeState = "미실행"
            CurrentState = "미실행"
            ProcessCount = 0
        }
        Send-TelegramMessage -ChatId $ChatId -Message (New-ResultMessage -ResultLabel "원격 실행 요청" -Result $failedRequest)
        Write-ListenerLog "Codex start request failed: $($_.Exception.Message)"
        return
    }

    $startRequested = @{
        Badge = "STARTED"
        Icon = "▶️"
        BeforeState = "미실행"
        CurrentState = "실행 확인 중"
        ProcessCount = $null
    }
    Send-TelegramMessage -ChatId $ChatId -Message (New-ResultMessage -ResultLabel "원격 실행 요청" -Result $startRequested)

    $finalResult = Wait-CodexAppRunning -TimeoutSeconds 60 -IntervalSeconds 2
    Send-TelegramMessage -ChatId $ChatId -Message (New-ResultMessage -ResultLabel "최종 확인 결과" -Result $finalResult)
}

function Get-CodexStatus {
    $processes = Get-CodexAppProcessList
    if ($processes.Count -gt 0) {
        return @{
            Badge = "OK"
            Icon = "✅"
            CurrentState = "실행 중"
            ProcessCount = $processes.Count
        }
    }

    return @{
        Badge = "WARN"
        Icon = "⚠️"
        CurrentState = "미실행"
        ProcessCount = 0
    }
}

function Get-TaskHealth {
    param([Parameter(Mandatory = $true)][string]$TaskName)

    $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
    if (!$task) {
        return @{
            Exists = $false
            UsesEnvFile = $false
            State = "Missing"
            NextRunTime = $null
            LastRunTime = $null
            LastTaskResult = $null
        }
    }

    $info = Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath $TaskPath
    $matchingActions = @(@($task.Actions) | Where-Object { $_.Arguments -like "*$EnvFile*" })
    return @{
        Exists = $true
        UsesEnvFile = $matchingActions.Count -gt 0
        State = [string]$task.State
        NextRunTime = $info.NextRunTime
        LastRunTime = $info.LastRunTime
        LastTaskResult = $info.LastTaskResult
    }
}

function ConvertTo-StatusIcon {
    param([bool]$Value)

    if ($Value) {
        return "✅"
    }

    return "⚠️"
}

function ConvertTo-TaskSummary {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][hashtable]$Task
    )

    if (!$Task.Exists) {
        return "$Label`: ⚠️ Missing"
    }

    $envState = if ($Task.UsesEnvFile) { "env OK" } else { "env mismatch" }
    return "$Label`: ✅ $($Task.State), $envState"
}

function ConvertTo-HeartbeatSummary {
    param([Parameter(Mandatory = $true)][hashtable]$Heartbeat)

    if (!$Heartbeat.Exists) {
        return "Listener heartbeat: ⚠️ Missing"
    }

    $icon = ConvertTo-StatusIcon -Value $Heartbeat.Fresh
    $state = if ($Heartbeat.Fresh) { "Fresh" } else { "Stale" }
    return "Listener heartbeat: $icon $state, $($Heartbeat.TimestampText) ($($Heartbeat.AgeText))"
}

function New-HealthMessage {
    $tokenPresent = ![string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable("TELEGRAM_BOT_TOKEN", "Process"))
    $allowedChatIds = @(Get-CodexAllowedChatIds)
    $commandAllowedChatIds = @(Get-CodexCommandAllowedChatIds)
    $monitorTask = Get-TaskHealth -TaskName $MonitorTaskName
    $listenerTask = Get-TaskHealth -TaskName $ListenerTaskName
    $watchdogTask = Get-TaskHealth -TaskName $WatchdogTaskName
    $offsetFileExists = Test-Path -LiteralPath $OffsetFile
    $heartbeat = Get-ListenerHeartbeatStatus
    $botReachable = Test-CodexTelegramBot
    $envProtected = Test-CodexEnvFileProtected -Path $EnvFile
    $logFileExists = Test-Path -LiteralPath $LogFile
    $logFileSize = if ($logFileExists) { (Get-Item -LiteralPath $LogFile).Length } else { 0 }
    $heartbeatOk = $heartbeat.Exists -and $heartbeat.Fresh
    $overallOk = $tokenPresent -and
        $allowedChatIds.Count -gt 0 -and
        $commandAllowedChatIds.Count -gt 0 -and
        $botReachable -and
        $envProtected -and
        $monitorTask.Exists -and
        $monitorTask.UsesEnvFile -and
        $listenerTask.Exists -and
        $listenerTask.UsesEnvFile -and
        $watchdogTask.Exists -and
        $watchdogTask.UsesEnvFile -and
        $heartbeatOk
    $now = Get-Date

    return @(
        "<b>$(ConvertTo-CodexTelegramHtml $MessageTitle)</b>",
        "",
        "<b>Health Check: $(ConvertTo-StatusIcon -Value $overallOk) $(if ($overallOk) { "OK" } else { "WARN" })</b>",
        "대상: Codex App",
        "PC: $(ConvertTo-CodexTelegramHtml $DeviceName)",
        "Bot token: $(ConvertTo-StatusIcon -Value $tokenPresent) $(if ($tokenPresent) { "Present" } else { "Missing" })",
        "Bot API: $(ConvertTo-StatusIcon -Value $botReachable) $(if ($botReachable) { "Reachable" } else { "Unavailable" })",
        "Notification chats: $($allowedChatIds.Count)개",
        "Command chats: $($commandAllowedChatIds.Count)개",
        "Env ACL: $(ConvertTo-StatusIcon -Value $envProtected) $(if ($envProtected) { "Protected" } else { "Needs protection" })",
        (ConvertTo-TaskSummary -Label "Daily monitor" -Task $monitorTask),
        (ConvertTo-TaskSummary -Label "Command listener" -Task $listenerTask),
        (ConvertTo-TaskSummary -Label "Watchdog" -Task $watchdogTask),
        "Offset file: $(ConvertTo-StatusIcon -Value $offsetFileExists) $(if ($offsetFileExists) { "Present" } else { "Missing" })",
        (ConvertTo-HeartbeatSummary -Heartbeat $heartbeat),
        "Log file: $(ConvertTo-StatusIcon -Value $logFileExists) $(if ($logFileExists) { "$logFileSize bytes" } else { "Missing" })",
        "",
        "Processed at: $(ConvertTo-CodexTelegramHtml $now.ToString("yyyy-MM-dd HH:mm:ss"))"
    ) -join "`n"
}

function New-VersionMessage {
    $startApp = Get-CodexStartApp
    $package = Get-CodexAppxPackage
    $processes = Get-CodexAppProcessList
    $now = Get-Date

    $lines = @(
        "<b>$(ConvertTo-CodexTelegramHtml $MessageTitle)</b>",
        "",
        "<b>Codex Version</b>",
        "대상: Codex App",
        "PC: $(ConvertTo-CodexTelegramHtml $DeviceName)",
        "실행 상태: $(if ($processes.Count -gt 0) { "실행 중" } else { "미실행" })",
        "프로세스: $($processes.Count)개",
        "App ID: $(ConvertTo-CodexTelegramHtml $CodexAppUserModelId)",
        "Process pattern: $(ConvertTo-CodexTelegramHtml $CodexProcessPathPattern)"
    )

    if ($startApp) {
        $lines += "Start menu name: $(ConvertTo-CodexTelegramHtml $startApp.Name)"
    }

    if ($package) {
        $lines += "Package name: $(ConvertTo-CodexTelegramHtml $package.Name)"
        $lines += "Package version: $(ConvertTo-CodexTelegramHtml ([string]$package.Version))"
    } else {
        $lines += "Package version: 확인 안 됨"
    }

    if ($processes.Count -gt 0) {
        $paths = @($processes | Select-Object -ExpandProperty Path -Unique | Select-Object -First 3)
        foreach ($path in $paths) {
            $lines += "Process path: $(ConvertTo-CodexTelegramHtml $path)"
        }
    }

    $lines += ""
    $lines += "Processed at: $(ConvertTo-CodexTelegramHtml $now.ToString("yyyy-MM-dd HH:mm:ss"))"

    return $lines -join "`n"
}

function ConvertTo-RedactedLogLine {
    param([AllowNull()][string]$Line)

    if ($null -eq $Line) {
        return ""
    }

    $redacted = $Line
    $redacted = $redacted -replace 'bot[0-9]{6,}:[A-Za-z0-9_-]{20,}', 'bot<redacted>'
    $redacted = $redacted -replace '[0-9]{6,}:[A-Za-z0-9_-]{20,}', '<telegram-token-redacted>'
    $redacted = $redacted -replace 'gho_[A-Za-z0-9_]+', 'gho_<redacted>'
    $redacted = $redacted -replace '(TELEGRAM_(BOT_TOKEN|CHAT_ID|PERSONAL_CHAT_ID|ALLOWED_CHAT_IDS|COMMAND_ALLOWED_CHAT_IDS)\s*=\s*)\S+', '$1<redacted>'
    $redacted = $redacted -replace 'C:\\Users\\[^\\\s]+\\Documents\\Codex\\[^\s<]+', '<local-codex-path>'
    $redacted = $redacted -replace 'C:\\Users\\[^\\\s]+\\AppData\\[^\s<]+', '<local-appdata-path>'
    return $redacted
}

function Get-RequestedLogLineCount {
    param([AllowNull()][string]$Text)

    $count = 20
    if (![string]::IsNullOrWhiteSpace($Text) -and $Text -match '^/(?:codex_logs|logs|l)(?:@[A-Za-z0-9_]+)?\s+(\d+)') {
        $count = [int]$matches[1]
    }

    if ($count -lt 5) {
        return 5
    }
    if ($count -gt 50) {
        return 50
    }

    return $count
}

function New-LogsMessage {
    param([int]$Count = 20)

    $now = Get-Date
    if (!(Test-Path -LiteralPath $LogFile)) {
        return @(
            "<b>$(ConvertTo-CodexTelegramHtml $MessageTitle)</b>",
            "",
            "<b>Listener Logs</b>",
            "대상: Codex App",
            "PC: $(ConvertTo-CodexTelegramHtml $DeviceName)",
            "로그 파일이 없습니다.",
            "",
            "Processed at: $(ConvertTo-CodexTelegramHtml $now.ToString("yyyy-MM-dd HH:mm:ss"))"
        ) -join "`n"
    }

    $logText = ((Get-Content -LiteralPath $LogFile -Tail $Count | ForEach-Object { ConvertTo-RedactedLogLine -Line $_ }) -join "`n")
    if ($logText.Length -gt 3000) {
        $logText = $logText.Substring($logText.Length - 3000)
    }

    return @(
        "<b>$(ConvertTo-CodexTelegramHtml $MessageTitle)</b>",
        "",
        "<b>Listener Logs</b>",
        "대상: Codex App",
        "PC: $(ConvertTo-CodexTelegramHtml $DeviceName)",
        "Lines: $Count",
        "",
        "<pre>$(ConvertTo-CodexTelegramHtml $logText)</pre>",
        "",
        "Processed at: $(ConvertTo-CodexTelegramHtml $now.ToString("yyyy-MM-dd HH:mm:ss"))"
    ) -join "`n"
}

function New-PingMessage {
    $now = Get-Date
    $heartbeat = Get-ListenerHeartbeatStatus

    return @(
        "<b>$(ConvertTo-CodexTelegramHtml $MessageTitle)</b>",
        "",
        "<b>Listener Ping: ✅ OK</b>",
        "대상: Codex App",
        "PC: $(ConvertTo-CodexTelegramHtml $DeviceName)",
        "마지막 polling: $($heartbeat.TimestampText) ($($heartbeat.AgeText))",
        "",
        "Processed at: $(ConvertTo-CodexTelegramHtml $now.ToString("yyyy-MM-dd HH:mm:ss"))"
    ) -join "`n"
}

function New-ResultMessage {
    param(
        [Parameter(Mandatory = $true)][string]$ResultLabel,
        [Parameter(Mandatory = $true)][hashtable]$Result
    )

    $now = Get-Date
    $lines = @(
        "<b>$(ConvertTo-CodexTelegramHtml $MessageTitle)</b>",
        "",
        "<b>$ResultLabel`: $($Result.Icon) $($Result.Badge)</b>",
        "대상: Codex App",
        "PC: $(ConvertTo-CodexTelegramHtml $DeviceName)"
    )

    if (![string]::IsNullOrWhiteSpace([string]$Result.BeforeState)) {
        $lines += "실행 전 상태: $(ConvertTo-CodexTelegramHtml $Result.BeforeState)"
    }

    $lines += "현재 실행 상태: $(ConvertTo-CodexTelegramHtml $Result.CurrentState)"
    if ($null -eq $Result.ProcessCount) {
        $lines += "프로세스: 확인 중"
    } else {
        $lines += "프로세스: $($Result.ProcessCount)개"
    }

    if (![string]::IsNullOrWhiteSpace([string]$Result.Notice)) {
        $lines += ""
        $lines += "안내: $(ConvertTo-CodexTelegramHtml $Result.Notice)"
    }

    $lines += ""
    $lines += "Processed at: $(ConvertTo-CodexTelegramHtml $now.ToString("yyyy-MM-dd HH:mm:ss"))"

    if ($null -ne $Result.ProcessCount -and $Result.ProcessCount -eq 0) {
        $lines += ""
        $lines += "확인 필요: Codex 앱이 실행되지 않았습니다."
    }

    return $lines -join "`n"
}

function New-HelpMessage {
    return @(
        "<b>$(ConvertTo-CodexTelegramHtml $MessageTitle)</b>",
        "",
        "<b>사용 가능한 명령</b>",
        "/o - Codex 앱 실행",
        "/s - 실행 상태 확인",
        "/h - 설정 및 스케줄러 상태 확인",
        "/v - Codex 앱 버전 및 감지 정보",
        "/l [count] - 최근 리스너 로그 확인",
        "/p - 리스너 응답 확인",
        "/m - 명령 목록 보기",
        "",
        "<b>전체 명령</b>",
        "/codex_on, /codex_status, /codex_health",
        "/codex_version, /codex_logs, /ping, /help"
    ) -join "`n"
}

function Get-CommandType {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return "ignore"
    }

    $trimmed = $Text.Trim()
    $lower = $trimmed.ToLowerInvariant()
    $lower = $lower -replace '^/([a-z0-9_]+)@[a-z0-9_]+', '/$1'

    if ($lower -match '^/(start|help|m)$' -or
        $lower -match '^/(start|help|m)@[a-z0-9_]+$') {
        return "help"
    }

    if ($lower -match '^/(codex_on|codex_start|startcodex|o)$' -or
        $lower -match '^/(codex_on|codex_start|startcodex|o)@[a-z0-9_]+$' -or
        $lower -in @("codex on", "codex start", "codex run", "codex 실행") -or
        $trimmed -match '^(코덱스|Codex|codex)( 앱)?\s*(켜|켜기|실행|시작)(해줘|해주세요)?$') {
        return "start"
    }

    if ($lower -match '^/(codex_status|status|s)$' -or
        $lower -match '^/(codex_status|status|s)@[a-z0-9_]+$' -or
        $lower -in @("codex status", "codex 상태") -or
        $trimmed -match '^(코덱스|Codex|codex)( 앱)?\s*(상태|확인|체크)$') {
        return "status"
    }

    if ($lower -match '^/(codex_health|health|h)$' -or
        $lower -match '^/(codex_health|health|h)@[a-z0-9_]+$' -or
        $lower -in @("codex health", "codex 헬스", "codex 점검")) {
        return "health"
    }

    if ($lower -match '^/(codex_version|version|v)$' -or
        $lower -match '^/(codex_version|version|v)@[a-z0-9_]+$' -or
        $lower -in @("codex version", "codex 버전")) {
        return "version"
    }

    if ($lower -match '^/(codex_logs|logs|l)(\s+\d+)?$' -or
        $lower -match '^/(codex_logs|logs|l)@[a-z0-9_]+(\s+\d+)?$') {
        return "logs"
    }

    if ($lower -match '^/(ping|p)$' -or
        $lower -match '^/(ping|p)@[a-z0-9_]+$') {
        return "ping"
    }

    return "unknown"
}

function Read-Offset {
    Ensure-LocalFolders
    if (!(Test-Path -LiteralPath $OffsetFile)) {
        return $null
    }

    $value = (Get-Content -LiteralPath $OffsetFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    try {
        return [int64]$value
    } catch {
        Write-ListenerLog "Invalid Telegram offset file. Reinitializing offset."
        return $null
    }
}

function Save-Offset {
    param([Parameter(Mandatory = $true)][int64]$Offset)

    Ensure-LocalFolders
    Set-Content -LiteralPath $OffsetFile -Encoding ASCII -Value $Offset
}

function Receive-TelegramUpdates {
    param(
        [AllowNull()][Nullable[int64]]$Offset,
        [int]$TimeoutSeconds
    )

    $payload = @{
        timeout = $TimeoutSeconds
        limit = 25
        allowed_updates = @("message")
    }

    if ($null -ne $Offset) {
        $payload.offset = $Offset
    }

    $response = Invoke-CodexTelegramApi `
        -MethodName "getUpdates" `
        -Payload $payload `
        -TimeoutSec ($TimeoutSeconds + 15)

    if (!$response.ok) {
        throw "Telegram getUpdates failed."
    }

    Save-ListenerHeartbeat
    return @($response.result)
}

function Initialize-TelegramOffset {
    $updates = Receive-TelegramUpdates -Offset $null -TimeoutSeconds 0
    if ($updates.Count -eq 0) {
        Save-Offset -Offset 0
        Write-ListenerLog "Initialized Telegram offset: 0"
        return
    }

    $latest = ($updates | Measure-Object -Property update_id -Maximum).Maximum
    $nextOffset = [int64]$latest + 1
    Save-Offset -Offset $nextOffset
    Write-ListenerLog "Initialized Telegram offset: $nextOffset"
}

function Handle-TelegramUpdate {
    param([Parameter(Mandatory = $true)]$Update)

    if ($null -eq $Update.message -or $null -eq $Update.message.chat) {
        return
    }

    $chatId = [string]$Update.message.chat.id
    if (!(Test-AllowedChatId -ChatId $chatId)) {
        Write-ListenerLog "Ignored message from unauthorized chat."
        return
    }

    $commandType = Get-CommandType -Text $Update.message.text
    switch ($commandType) {
        "help" {
            Send-TelegramMessage -ChatId $chatId -Message (New-HelpMessage)
        }
        "start" {
            Invoke-CodexRemoteStart -ChatId $chatId
        }
        "status" {
            $result = Get-CodexStatus
            Send-TelegramMessage -ChatId $chatId -Message (New-ResultMessage -ResultLabel "상태 확인 결과" -Result $result)
        }
        "health" {
            Send-TelegramMessage -ChatId $chatId -Message (New-HealthMessage)
        }
        "version" {
            Send-TelegramMessage -ChatId $chatId -Message (New-VersionMessage)
        }
        "logs" {
            $count = Get-RequestedLogLineCount -Text $Update.message.text
            Send-TelegramMessage -ChatId $chatId -Message (New-LogsMessage -Count $count)
        }
        "ping" {
            Send-TelegramMessage -ChatId $chatId -Message (New-PingMessage)
        }
        "unknown" {
            Send-TelegramMessage -ChatId $chatId -Message (New-HelpMessage)
        }
    }
}

Ensure-LocalFolders
Import-CodexDotEnv -Path $EnvFile
$codexSettings = Resolve-CodexAppSettings
$CodexAppUserModelId = $codexSettings.AppUserModelId
$CodexProcessPathPattern = $codexSettings.ProcessPathPattern
$MessageTitle = Get-CodexMessageTitle
$DeviceName = Get-CodexDeviceName

if ($InitializeOffset) {
    Initialize-TelegramOffset
    exit 0
}

$offset = Read-Offset
if ($null -eq $offset) {
    Initialize-TelegramOffset
    $offset = Read-Offset
}

Write-ListenerLog "Command listener started."
Save-ListenerHeartbeat

while ($true) {
    try {
        $updates = Receive-TelegramUpdates -Offset $offset -TimeoutSeconds $TelegramTimeoutSeconds
        foreach ($update in $updates) {
            try {
                Handle-TelegramUpdate -Update $update
            } catch {
                Write-ListenerLog "Update handling failed: $($_.Exception.Message)"
            } finally {
                $offset = [int64]$update.update_id + 1
                Save-Offset -Offset $offset
            }
        }
    } catch {
        Write-ListenerLog "Polling failed: $($_.Exception.Message)"
        if ($Once) {
            throw
        }

        Start-Sleep -Seconds 10
    }

    if ($Once) {
        break
    }

    Start-Sleep -Seconds $PollSeconds
}
