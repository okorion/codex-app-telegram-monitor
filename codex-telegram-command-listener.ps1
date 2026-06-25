param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env"),
    [int]$PollSeconds = 2,
    [int]$TelegramTimeoutSeconds = 25,
    [switch]$Once,
    [switch]$InitializeOffset,
    [switch]$DryRun,
    [switch]$LoadOnly
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
$BotUsername = ""
$script:LastPollingConflictLoggedAt = $null

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
            TimestampText = "없음"
            AgeText = "알 수 없음"
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

function Test-StartAllowedChatId {
    param([Parameter(Mandatory = $true)][string]$ChatId)

    return Test-CodexChatIdAllowed -ChatId $ChatId -AllowedChatIds @(Get-CodexStartAllowedChatIds)
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
            State = "없음"
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
        return "$Label`: ⚠️ 없음"
    }

    $envState = if ($Task.UsesEnvFile) { "env OK" } else { "env mismatch" }
    return "$Label`: ✅ $($Task.State), $envState"
}

function ConvertTo-HeartbeatSummary {
    param([Parameter(Mandatory = $true)][hashtable]$Heartbeat)

    if (!$Heartbeat.Exists) {
        return "Listener heartbeat: ⚠️ 없음"
    }

    $icon = ConvertTo-StatusIcon -Value $Heartbeat.Fresh
    $state = if ($Heartbeat.Fresh) { "정상" } else { "오래됨" }
    return "Listener heartbeat: $icon $state, $($Heartbeat.TimestampText) ($($Heartbeat.AgeText))"
}

function Test-RecentPollingConflict {
    if (!(Test-Path -LiteralPath $LogFile)) {
        return $false
    }

    $recentLines = @(Get-Content -LiteralPath $LogFile -Tail 100 -ErrorAction SilentlyContinue)
    return Test-CodexRecentTelegramConflict `
        -Lines $recentLines `
        -StaleSeconds (Get-CodexPollingConflictStaleSeconds)
}

function New-HealthMessage {
    $tokenPresent = ![string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable("TELEGRAM_BOT_TOKEN", "Process"))
    $allowedChatIds = @(Get-CodexAllowedChatIds)
    $commandAllowedChatIds = @(Get-CodexCommandAllowedChatIds)
    $startAllowedChatIds = @(Get-CodexStartAllowedChatIds)
    $monitorTask = Get-TaskHealth -TaskName $MonitorTaskName
    $listenerTask = Get-TaskHealth -TaskName $ListenerTaskName
    $watchdogTask = Get-TaskHealth -TaskName $WatchdogTaskName
    $offsetFileExists = Test-Path -LiteralPath $OffsetFile
    $heartbeat = Get-ListenerHeartbeatStatus
    $botReachable = Test-CodexTelegramBot
    $envProtected = Test-CodexEnvFileProtected -Path $EnvFile
    $logFileExists = Test-Path -LiteralPath $LogFile
    $logFileSize = if ($logFileExists) { (Get-Item -LiteralPath $LogFile).Length } else { 0 }
    $pollingConflict = Test-RecentPollingConflict
    $heartbeatOk = $heartbeat.Exists -and $heartbeat.Fresh
    $overallOk = $tokenPresent -and
        $allowedChatIds.Count -gt 0 -and
        $commandAllowedChatIds.Count -gt 0 -and
        $startAllowedChatIds.Count -gt 0 -and
        $botReachable -and
        $envProtected -and
        $monitorTask.Exists -and
        $monitorTask.UsesEnvFile -and
        $listenerTask.Exists -and
        $listenerTask.UsesEnvFile -and
        $watchdogTask.Exists -and
        $watchdogTask.UsesEnvFile -and
        $heartbeatOk -and
        !$pollingConflict
    $now = Get-Date

    return @(
        "<b>$(ConvertTo-CodexTelegramHtml $MessageTitle)</b>",
        "",
        "<b>상태 점검: $(ConvertTo-StatusIcon -Value $overallOk) $(if ($overallOk) { "OK" } else { "WARN" })</b>",
        "대상: Codex App",
        "PC: $(ConvertTo-CodexTelegramHtml $DeviceName)",
        "Bot token: $(ConvertTo-StatusIcon -Value $tokenPresent) $(if ($tokenPresent) { "있음" } else { "없음" })",
        "Bot API: $(ConvertTo-StatusIcon -Value $botReachable) $(if ($botReachable) { "연결 가능" } else { "연결 불가" })",
        "알림 허용 채팅: $($allowedChatIds.Count)개",
        "명령 허용 채팅: $($commandAllowedChatIds.Count)개",
        "실행 허용 채팅: $($startAllowedChatIds.Count)개",
        "Env ACL: $(ConvertTo-StatusIcon -Value $envProtected) $(if ($envProtected) { "보호됨" } else { "보호 필요" })",
        (ConvertTo-TaskSummary -Label "Daily monitor" -Task $monitorTask),
        (ConvertTo-TaskSummary -Label "Command listener" -Task $listenerTask),
        (ConvertTo-TaskSummary -Label "Watchdog" -Task $watchdogTask),
        "Offset file: $(ConvertTo-StatusIcon -Value $offsetFileExists) $(if ($offsetFileExists) { "있음" } else { "없음" })",
        (ConvertTo-HeartbeatSummary -Heartbeat $heartbeat),
        "Polling conflict: $(ConvertTo-StatusIcon -Value (!$pollingConflict)) $(if ($pollingConflict) { "최근 감지됨" } else { "없음" })",
        "Conflict 기준: 최근 $([int][math]::Round((Get-CodexPollingConflictStaleSeconds) / 60))분",
        "Log file: $(ConvertTo-StatusIcon -Value $logFileExists) $(if ($logFileExists) { "$logFileSize bytes" } else { "없음" })",
        "",
        "Processed at: $(ConvertTo-CodexTelegramHtml $now.ToString("yyyy-MM-dd HH:mm:ss"))"
    ) -join "`n"
}

function New-StartDeniedMessage {
    $now = Get-Date

    return @(
        "<b>$(ConvertTo-CodexTelegramHtml $MessageTitle)</b>",
        "",
        "<b>원격 실행 권한: ⚠️ DENIED</b>",
        "대상: Codex App",
        "PC: $(ConvertTo-CodexTelegramHtml $DeviceName)",
        "",
        "안내: 이 채팅은 Codex App 실행 권한이 없습니다.",
        "설정: TELEGRAM_START_ALLOWED_CHAT_IDS",
        "",
        "Processed at: $(ConvertTo-CodexTelegramHtml $now.ToString("yyyy-MM-dd HH:mm:ss"))"
    ) -join "`n"
}

function New-VersionMessage {
    $startApp = Get-CodexStartApp
    $package = Get-CodexAppxPackage
    $processes = Get-CodexAppProcessList
    $toolVersion = Get-CodexToolVersion -Root $PSScriptRoot
    $detection = Get-CodexDetectionSummary -ProcessPathPattern $CodexProcessPathPattern
    $now = Get-Date

    $lines = @(
        "<b>$(ConvertTo-CodexTelegramHtml $MessageTitle)</b>",
        "",
        "<b>Codex 버전</b>",
        "대상: Codex App",
        "PC: $(ConvertTo-CodexTelegramHtml $DeviceName)",
        "Tool version: $(ConvertTo-CodexTelegramHtml $toolVersion)",
        "실행 상태: $(if ($processes.Count -gt 0) { "실행 중" } else { "미실행" })",
        "프로세스: $($processes.Count)개",
        "App ID: $(ConvertTo-CodexTelegramHtml $CodexAppUserModelId)",
        "Process pattern: $(ConvertTo-CodexTelegramHtml $CodexProcessPathPattern)",
        "StartApps candidates: $($detection.StartAppCount)개",
        "Appx package candidates: $($detection.AppxPackageCount)개",
        "Matching processes: $($detection.MatchingProcessCount)개"
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
    return ConvertTo-CodexRedactedText -Text $Line
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
            "<b>Listener 로그</b>",
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
        "<b>Listener 로그</b>",
        "대상: Codex App",
        "PC: $(ConvertTo-CodexTelegramHtml $DeviceName)",
        "줄 수: $Count",
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
        "<b>Listener 응답: ✅ OK</b>",
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

    return Get-CodexTelegramCommandType -Text $Text
}

function Get-BotUsername {
    try {
        $botInfo = Invoke-CodexTelegramApi -MethodName "getMe" -Payload @{} -TimeoutSec 15
        if ($botInfo.ok -and $botInfo.result -and ![string]::IsNullOrWhiteSpace($botInfo.result.username)) {
            return [string]$botInfo.result.username
        }
    } catch {
        Write-ListenerLog "Bot username 확인 실패: $($_.Exception.Message)"
    }

    return ""
}

function Get-PollingFailureRetryDelaySeconds {
    param([Parameter(Mandatory = $true)]$ErrorRecord)

    if (Test-CodexTelegramConflictError -ErrorRecord $ErrorRecord) {
        $now = Get-Date
        if ($null -eq $script:LastPollingConflictLoggedAt -or
            (($now - $script:LastPollingConflictLoggedAt).TotalMinutes -ge 5)) {
            Write-ListenerLog "Telegram polling conflict: 같은 bot token으로 다른 PC 또는 listener가 getUpdates를 사용 중입니다. active PC마다 별도 bot token을 쓰거나 다른 listener를 중지하세요."
            $script:LastPollingConflictLoggedAt = $now
        }

        return 30
    }

    Write-ListenerLog "Polling 실패: $($ErrorRecord.Exception.Message)"
    return 10
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
        Write-ListenerLog "Telegram offset 파일이 올바르지 않아 다시 초기화합니다."
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

    $chat = $Update.message.chat
    $chatId = [string]$chat.id
    if (!(Test-AllowedChatId -ChatId $chatId)) {
        Write-ListenerLog "허용되지 않은 채팅의 메시지를 무시했습니다."
        return
    }

    $chatType = [string]$chat.type
    $isPrivateChat = [string]::IsNullOrWhiteSpace($chatType) -or $chatType -eq "private"
    if (!$isPrivateChat -and !(Test-CodexTelegramMessageTargetsBot -Text $Update.message.text -BotUsername $BotUsername)) {
        Write-ListenerLog "그룹 채팅의 일반 메시지를 무시했습니다."
        return
    }

    $commandType = Get-CommandType -Text $Update.message.text
    switch ($commandType) {
        "help" {
            Send-TelegramMessage -ChatId $chatId -Message (New-HelpMessage)
        }
        "start" {
            if (!(Test-StartAllowedChatId -ChatId $chatId)) {
                Write-ListenerLog "명령은 허용되었지만 실행 권한이 없는 채팅의 Codex start 요청을 거부했습니다."
                Send-TelegramMessage -ChatId $chatId -Message (New-StartDeniedMessage)
                return
            }

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

if ($LoadOnly) {
    return
}

Ensure-LocalFolders
Import-CodexDotEnv -Path $EnvFile
$codexSettings = Resolve-CodexAppSettings
$CodexAppUserModelId = $codexSettings.AppUserModelId
$CodexProcessPathPattern = $codexSettings.ProcessPathPattern
$MessageTitle = Get-CodexMessageTitle
$DeviceName = Get-CodexDeviceName
$BotUsername = Get-BotUsername

if ($InitializeOffset) {
    Initialize-TelegramOffset
    exit 0
}

$offset = Read-Offset
if ($null -eq $offset) {
    Initialize-TelegramOffset
    $offset = Read-Offset
}

Write-ListenerLog "Command listener 시작됨."
Save-ListenerHeartbeat

while ($true) {
    try {
        $updates = Receive-TelegramUpdates -Offset $offset -TimeoutSeconds $TelegramTimeoutSeconds
        foreach ($update in $updates) {
            try {
                Handle-TelegramUpdate -Update $update
            } catch {
                Write-ListenerLog "Update 처리 실패: $($_.Exception.Message)"
            } finally {
                $offset = [int64]$update.update_id + 1
                Save-Offset -Offset $offset
            }
        }
    } catch {
        $retryDelaySeconds = Get-PollingFailureRetryDelaySeconds -ErrorRecord $_
        if ($Once) {
            throw
        }

        Start-Sleep -Seconds $retryDelaySeconds
    }

    if ($Once) {
        break
    }

    Start-Sleep -Seconds $PollSeconds
}
