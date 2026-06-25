param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env"),
    [int]$PollSeconds = 2,
    [int]$TelegramTimeoutSeconds = 25,
    [switch]$Once,
    [switch]$InitializeOffset,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$StateDir = Join-Path $PSScriptRoot "state"
$LogDir = Join-Path $PSScriptRoot "logs"
$OffsetFile = Join-Path $StateDir "telegram-command-offset.txt"
$LogFile = Join-Path $LogDir "telegram-command-listener.log"
$CodexAppUserModelId = "OpenAI.Codex_2p2nqsd0c76g0!App"
$CodexProcessPathPattern = "*\OpenAI.Codex_*\app\Codex.exe"
$MessageTitle = "Codex app monitor test"
$MonitorTaskName = "Ensure Codex App Running at 9AM"
$ListenerTaskName = "Codex Telegram Command Listener"
$WatchdogTaskName = "Codex Telegram Command Listener Watchdog"
$TaskPath = "\Codex\"

function Ensure-LocalFolders {
    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-ListenerLog {
    param([Parameter(Mandatory = $true)][string]$Message)

    Ensure-LocalFolders
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -LiteralPath $LogFile -Encoding UTF8 -Value "[$timestamp] $Message"
}

function Import-DotEnv {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (!(Test-Path -LiteralPath $Path)) {
        throw "Env file not found: $Path"
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') {
            continue
        }

        $name = $matches[1]
        $value = $matches[2].Trim()
        if ($value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2).Replace('\"', '"')
        } elseif ($value.StartsWith("'") -and $value.EndsWith("'")) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

function Get-EnvOrDefault {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$DefaultValue
    )

    $value = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $DefaultValue
    }

    return $value
}

function Test-AutoConfigValue {
    param([AllowNull()][string]$Value)

    return [string]::IsNullOrWhiteSpace($Value) -or $Value.Trim().ToLowerInvariant() -eq "auto"
}

function ConvertTo-TelegramHtml {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    return $Text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")
}

function Get-CodexStartApp {
    try {
        return Get-StartApps |
            Where-Object { $_.AppID -like "OpenAI.Codex*" -or $_.Name -like "*Codex*" } |
            Select-Object -First 1
    } catch {
        return $null
    }
}

function Get-CodexAppxPackage {
    try {
        return Get-AppxPackage -Name "OpenAI.Codex*" -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending |
            Select-Object -First 1
    } catch {
        return $null
    }
}

function Resolve-CodexAppSettings {
    $configuredAppId = [Environment]::GetEnvironmentVariable("CODEX_APP_USER_MODEL_ID", "Process")
    $configuredPathPattern = [Environment]::GetEnvironmentVariable("CODEX_PROCESS_PATH_PATTERN", "Process")
    $startApp = Get-CodexStartApp

    if (Test-AutoConfigValue -Value $configuredAppId) {
        if ($startApp -and ![string]::IsNullOrWhiteSpace($startApp.AppID)) {
            $resolvedAppId = $startApp.AppID
        } else {
            $resolvedAppId = $CodexAppUserModelId
        }
    } else {
        $resolvedAppId = $configuredAppId
    }

    if (Test-AutoConfigValue -Value $configuredPathPattern) {
        $resolvedPathPattern = $CodexProcessPathPattern
    } else {
        $resolvedPathPattern = $configuredPathPattern
    }

    return @{
        AppUserModelId = $resolvedAppId
        ProcessPathPattern = $resolvedPathPattern
        StartAppName = if ($startApp) { $startApp.Name } else { $null }
        StartAppId = if ($startApp) { $startApp.AppID } else { $null }
    }
}

function Get-TelegramToken {
    $token = [Environment]::GetEnvironmentVariable("TELEGRAM_BOT_TOKEN", "Process")
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Telegram configuration is missing TELEGRAM_BOT_TOKEN."
    }

    return $token
}

function Get-AllowedChatIds {
    $allowed = [Environment]::GetEnvironmentVariable("TELEGRAM_ALLOWED_CHAT_IDS", "Process")
    if (![string]::IsNullOrWhiteSpace($allowed)) {
        return @($allowed -split "[,;\s]+" | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }

    $chatIds = @()
    $personalChatId = [Environment]::GetEnvironmentVariable("TELEGRAM_PERSONAL_CHAT_ID", "Process")
    $defaultChatId = [Environment]::GetEnvironmentVariable("TELEGRAM_CHAT_ID", "Process")
    if (![string]::IsNullOrWhiteSpace($personalChatId)) {
        $chatIds += $personalChatId
    }
    if (![string]::IsNullOrWhiteSpace($defaultChatId)) {
        $chatIds += $defaultChatId
    }

    $chatIds = @($chatIds | Select-Object -Unique)
    if ($chatIds.Count -eq 0) {
        throw "Telegram configuration is missing TELEGRAM_CHAT_ID."
    }

    return $chatIds
}

function Test-AllowedChatId {
    param([Parameter(Mandatory = $true)][string]$ChatId)

    return (Get-AllowedChatIds) -contains $ChatId
}

function Invoke-TelegramApi {
    param(
        [Parameter(Mandatory = $true)][string]$MethodName,
        [Parameter(Mandatory = $true)][hashtable]$Payload,
        [int]$TimeoutSec = 30
    )

    $token = Get-TelegramToken
    $uri = "https://api.telegram.org/bot$token/$MethodName"
    $body = $Payload | ConvertTo-Json -Depth 6 -Compress

    return Invoke-RestMethod `
        -Method Post `
        -Uri $uri `
        -ContentType "application/json; charset=utf-8" `
        -Body $body `
        -TimeoutSec $TimeoutSec
}

function Send-TelegramMessage {
    param(
        [Parameter(Mandatory = $true)][string]$ChatId,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($DryRun) {
        Write-Output $Message
        return
    }

    Invoke-TelegramApi -MethodName "sendMessage" -Payload @{
        chat_id = $ChatId
        text = $Message
        parse_mode = "HTML"
        disable_web_page_preview = $true
    } | Out-Null
}

function Get-CodexAppProcesses {
    return Get-Process -Name Codex -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -like $CodexProcessPathPattern }
}

function Wait-CodexAppRunning {
    param(
        [int]$TimeoutSeconds = 60,
        [int]$IntervalSeconds = 2
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $processes = @(Get-CodexAppProcesses)
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

    $finalProcesses = @(Get-CodexAppProcesses)
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

    $before = @(Get-CodexAppProcesses)
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
        Start-Process explorer.exe "shell:AppsFolder\$CodexAppUserModelId"
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
    $processes = @(Get-CodexAppProcesses)
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

function Test-TelegramBot {
    try {
        $response = Invoke-TelegramApi -MethodName "getMe" -Payload @{} -TimeoutSec 15
        return [bool]$response.ok
    } catch {
        return $false
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

function New-HealthMessage {
    $tokenPresent = ![string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable("TELEGRAM_BOT_TOKEN", "Process"))
    $allowedChatIds = @(Get-AllowedChatIds)
    $monitorTask = Get-TaskHealth -TaskName $MonitorTaskName
    $listenerTask = Get-TaskHealth -TaskName $ListenerTaskName
    $watchdogTask = Get-TaskHealth -TaskName $WatchdogTaskName
    $offsetFileExists = Test-Path -LiteralPath $OffsetFile
    $botReachable = Test-TelegramBot
    $overallOk = $tokenPresent -and
        $allowedChatIds.Count -gt 0 -and
        $botReachable -and
        $monitorTask.Exists -and
        $monitorTask.UsesEnvFile -and
        $listenerTask.Exists -and
        $listenerTask.UsesEnvFile -and
        $watchdogTask.Exists -and
        $watchdogTask.UsesEnvFile
    $now = Get-Date

    return @(
        "<b>$(ConvertTo-TelegramHtml $MessageTitle)</b>",
        "",
        "<b>Health Check: $(ConvertTo-StatusIcon -Value $overallOk) $(if ($overallOk) { "OK" } else { "WARN" })</b>",
        "대상: Codex App",
        "Bot token: $(ConvertTo-StatusIcon -Value $tokenPresent) $(if ($tokenPresent) { "Present" } else { "Missing" })",
        "Bot API: $(ConvertTo-StatusIcon -Value $botReachable) $(if ($botReachable) { "Reachable" } else { "Unavailable" })",
        "Allowed chats: $($allowedChatIds.Count)개",
        (ConvertTo-TaskSummary -Label "Daily monitor" -Task $monitorTask),
        (ConvertTo-TaskSummary -Label "Command listener" -Task $listenerTask),
        (ConvertTo-TaskSummary -Label "Watchdog" -Task $watchdogTask),
        "Offset file: $(ConvertTo-StatusIcon -Value $offsetFileExists) $(if ($offsetFileExists) { "Present" } else { "Missing" })",
        "",
        "Processed at: $(ConvertTo-TelegramHtml $now.ToString("yyyy-MM-dd HH:mm:ss"))"
    ) -join "`n"
}

function New-VersionMessage {
    $startApp = Get-CodexStartApp
    $package = Get-CodexAppxPackage
    $processes = @(Get-CodexAppProcesses)
    $now = Get-Date

    $lines = @(
        "<b>$(ConvertTo-TelegramHtml $MessageTitle)</b>",
        "",
        "<b>Codex Version</b>",
        "대상: Codex App",
        "실행 상태: $(if ($processes.Count -gt 0) { "실행 중" } else { "미실행" })",
        "프로세스: $($processes.Count)개",
        "App ID: $(ConvertTo-TelegramHtml $CodexAppUserModelId)",
        "Process pattern: $(ConvertTo-TelegramHtml $CodexProcessPathPattern)"
    )

    if ($startApp) {
        $lines += "Start menu name: $(ConvertTo-TelegramHtml $startApp.Name)"
    }

    if ($package) {
        $lines += "Package name: $(ConvertTo-TelegramHtml $package.Name)"
        $lines += "Package version: $(ConvertTo-TelegramHtml ([string]$package.Version))"
    } else {
        $lines += "Package version: 확인 안 됨"
    }

    if ($processes.Count -gt 0) {
        $paths = @($processes | Select-Object -ExpandProperty Path -Unique | Select-Object -First 3)
        foreach ($path in $paths) {
            $lines += "Process path: $(ConvertTo-TelegramHtml $path)"
        }
    }

    $lines += ""
    $lines += "Processed at: $(ConvertTo-TelegramHtml $now.ToString("yyyy-MM-dd HH:mm:ss"))"

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
    $redacted = $redacted -replace '(TELEGRAM_(BOT_TOKEN|CHAT_ID|PERSONAL_CHAT_ID|ALLOWED_CHAT_IDS)\s*=\s*)\S+', '$1<redacted>'
    return $redacted
}

function Get-RequestedLogLineCount {
    param([AllowNull()][string]$Text)

    $count = 20
    if (![string]::IsNullOrWhiteSpace($Text) -and $Text -match '^/codex_logs(?:@[A-Za-z0-9_]+)?\s+(\d+)') {
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
            "<b>$(ConvertTo-TelegramHtml $MessageTitle)</b>",
            "",
            "<b>Listener Logs</b>",
            "대상: Codex App",
            "로그 파일이 없습니다.",
            "",
            "Processed at: $(ConvertTo-TelegramHtml $now.ToString("yyyy-MM-dd HH:mm:ss"))"
        ) -join "`n"
    }

    $logText = ((Get-Content -LiteralPath $LogFile -Tail $Count | ForEach-Object { ConvertTo-RedactedLogLine -Line $_ }) -join "`n")
    if ($logText.Length -gt 3000) {
        $logText = $logText.Substring($logText.Length - 3000)
    }

    return @(
        "<b>$(ConvertTo-TelegramHtml $MessageTitle)</b>",
        "",
        "<b>Listener Logs</b>",
        "대상: Codex App",
        "Lines: $Count",
        "",
        "<pre>$(ConvertTo-TelegramHtml $logText)</pre>",
        "",
        "Processed at: $(ConvertTo-TelegramHtml $now.ToString("yyyy-MM-dd HH:mm:ss"))"
    ) -join "`n"
}

function New-ResultMessage {
    param(
        [Parameter(Mandatory = $true)][string]$ResultLabel,
        [Parameter(Mandatory = $true)][hashtable]$Result
    )

    $now = Get-Date
    $lines = @(
        "<b>$(ConvertTo-TelegramHtml $MessageTitle)</b>",
        "",
        "<b>$ResultLabel`: $($Result.Icon) $($Result.Badge)</b>",
        "대상: Codex App"
    )

    if (![string]::IsNullOrWhiteSpace([string]$Result.BeforeState)) {
        $lines += "실행 전 상태: $(ConvertTo-TelegramHtml $Result.BeforeState)"
    }

    $lines += "현재 실행 상태: $(ConvertTo-TelegramHtml $Result.CurrentState)"
    if ($null -eq $Result.ProcessCount) {
        $lines += "프로세스: 확인 중"
    } else {
        $lines += "프로세스: $($Result.ProcessCount)개"
    }

    if (![string]::IsNullOrWhiteSpace([string]$Result.Notice)) {
        $lines += ""
        $lines += "안내: $(ConvertTo-TelegramHtml $Result.Notice)"
    }

    $lines += ""
    $lines += "Processed at: $(ConvertTo-TelegramHtml $now.ToString("yyyy-MM-dd HH:mm:ss"))"

    if ($null -ne $Result.ProcessCount -and $Result.ProcessCount -eq 0) {
        $lines += ""
        $lines += "확인 필요: Codex 앱이 실행되지 않았습니다."
    }

    return $lines -join "`n"
}

function New-HelpMessage {
    return @(
        "<b>$(ConvertTo-TelegramHtml $MessageTitle)</b>",
        "",
        "<b>사용 가능한 명령</b>",
        "/codex_on - Codex 앱 실행",
        "/codex_status - 실행 상태 확인",
        "/codex_health - 설정 및 스케줄러 상태 확인",
        "/codex_version - Codex 앱 버전 및 감지 정보",
        "/codex_logs [count] - 최근 리스너 로그 확인",
        "/help - 명령 목록 보기"
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

    if ($lower -match '^/(start|help)$') {
        return "help"
    }

    if ($lower -match '^/(codex_on|codex_start|startcodex)$' -or
        $lower -in @("codex on", "codex start", "codex run", "codex 실행") -or
        $trimmed -match '^(코덱스|Codex|codex)( 앱)?\s*(켜|켜기|실행|시작)(해줘|해주세요)?$') {
        return "start"
    }

    if ($lower -match '^/(codex_status|status)$' -or
        $lower -in @("codex status", "codex 상태") -or
        $trimmed -match '^(코덱스|Codex|codex)( 앱)?\s*(상태|확인|체크)$') {
        return "status"
    }

    if ($lower -match '^/(codex_health|health)$' -or
        $lower -in @("codex health", "codex 헬스", "codex 점검")) {
        return "health"
    }

    if ($lower -match '^/(codex_version|version)$' -or
        $lower -in @("codex version", "codex 버전")) {
        return "version"
    }

    if ($lower -match '^/(codex_logs|logs)(\s+\d+)?$' -or
        $lower -match '^/(codex_logs|logs)@[a-z0-9_]+(\s+\d+)?$') {
        return "logs"
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

    return [int64]$value
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

    $response = Invoke-TelegramApi `
        -MethodName "getUpdates" `
        -Payload $payload `
        -TimeoutSec ($TimeoutSeconds + 15)

    if (!$response.ok) {
        throw "Telegram getUpdates failed."
    }

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
        "unknown" {
            Send-TelegramMessage -ChatId $chatId -Message (New-HelpMessage)
        }
    }
}

Ensure-LocalFolders
Import-DotEnv -Path $EnvFile
$codexSettings = Resolve-CodexAppSettings
$CodexAppUserModelId = $codexSettings.AppUserModelId
$CodexProcessPathPattern = $codexSettings.ProcessPathPattern
$MessageTitle = Get-EnvOrDefault -Name "CODEX_MONITOR_TITLE" -DefaultValue $MessageTitle

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
