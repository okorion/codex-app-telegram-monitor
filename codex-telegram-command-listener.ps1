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

function ConvertTo-TelegramHtml {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    return $Text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")
}

function Get-TelegramToken {
    $token = [Environment]::GetEnvironmentVariable("TELEGRAM_BOT_TOKEN", "Process")
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Telegram configuration is missing TELEGRAM_BOT_TOKEN."
    }

    return $token
}

function Get-AllowedChatId {
    $chatId = [Environment]::GetEnvironmentVariable("TELEGRAM_PERSONAL_CHAT_ID", "Process")
    if ([string]::IsNullOrWhiteSpace($chatId)) {
        $chatId = [Environment]::GetEnvironmentVariable("TELEGRAM_CHAT_ID", "Process")
    }

    if ([string]::IsNullOrWhiteSpace($chatId)) {
        throw "Telegram configuration is missing TELEGRAM_CHAT_ID."
    }

    return $chatId
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
        "점검 대상: Codex 앱"
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
    $allowedChatId = [string](Get-AllowedChatId)
    if ($chatId -ne $allowedChatId) {
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
        "unknown" {
            Send-TelegramMessage -ChatId $chatId -Message (New-HelpMessage)
        }
    }
}

Ensure-LocalFolders
Import-DotEnv -Path $EnvFile
$CodexAppUserModelId = Get-EnvOrDefault -Name "CODEX_APP_USER_MODEL_ID" -DefaultValue $CodexAppUserModelId
$CodexProcessPathPattern = Get-EnvOrDefault -Name "CODEX_PROCESS_PATH_PATTERN" -DefaultValue $CodexProcessPathPattern
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
