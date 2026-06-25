param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env"),
    [switch]$DryRun,
    [switch]$TelegramTest
)

$ErrorActionPreference = "Stop"

$CodexAppUserModelId = "OpenAI.Codex_2p2nqsd0c76g0!App"
$CodexProcessPathPattern = "*\OpenAI.Codex_*\app\Codex.exe"
$MessageTitle = "Codex app monitor test"

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

function Send-TelegramMessage {
    param([Parameter(Mandatory = $true)][string]$Message)

    $token = [Environment]::GetEnvironmentVariable("TELEGRAM_BOT_TOKEN", "Process")
    $chatId = [Environment]::GetEnvironmentVariable("TELEGRAM_PERSONAL_CHAT_ID", "Process")
    if ([string]::IsNullOrWhiteSpace($chatId)) {
        $chatId = [Environment]::GetEnvironmentVariable("TELEGRAM_CHAT_ID", "Process")
    }

    if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($chatId)) {
        throw "Telegram configuration is missing TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID."
    }

    if ($DryRun) {
        Write-Output $Message
        return
    }

    $payload = @{
        chat_id = $chatId
        text = $Message
        parse_mode = "HTML"
        disable_web_page_preview = $true
    }

    $uri = "https://api.telegram.org/bot$token/sendMessage"
    Invoke-RestMethod -Method Post -Uri $uri -ContentType "application/json; charset=utf-8" -Body ($payload | ConvertTo-Json -Compress) | Out-Null
}

function Get-CodexAppProcesses {
    return Get-Process -Name Codex -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -like $CodexProcessPathPattern }
}

Import-DotEnv -Path $EnvFile
$CodexAppUserModelId = Get-EnvOrDefault -Name "CODEX_APP_USER_MODEL_ID" -DefaultValue $CodexAppUserModelId
$CodexProcessPathPattern = Get-EnvOrDefault -Name "CODEX_PROCESS_PATH_PATTERN" -DefaultValue $CodexProcessPathPattern
$MessageTitle = Get-EnvOrDefault -Name "CODEX_MONITOR_TITLE" -DefaultValue $MessageTitle

$checkedAt = Get-Date

if ($TelegramTest) {
    $message = @(
        "<b>$(ConvertTo-TelegramHtml $MessageTitle)</b>",
        "",
        "<b>알림 테스트: ✅ 정상</b>",
        "대상: Codex 앱 상태 점검 알림",
        "결과: 전용 텔레그램 봇 연결 정상",
        "",
        "Time: $(ConvertTo-TelegramHtml $checkedAt.ToString("yyyy-MM-dd HH:mm:ss"))"
    ) -join "`n"

    Send-TelegramMessage -Message $message
    exit 0
}

$before = @(Get-CodexAppProcesses)
$wasRunning = $before.Count -gt 0
$startAttempted = $false

if (!$wasRunning) {
    $startAttempted = $true
    Start-Process explorer.exe "shell:AppsFolder\$CodexAppUserModelId"
    Start-Sleep -Seconds 8
}

$after = @(Get-CodexAppProcesses)
$isRunning = $after.Count -gt 0

if ($wasRunning) {
    $badge = "OK"
    $appState = "실행 중"
    $noticeLine = $null
    $statusIcon = "✅"
} elseif ($isRunning) {
    $badge = "STARTED"
    $appState = "실행 중"
    $noticeLine = "Codex 앱이 미실행 상태여서 자동 실행했습니다."
    $statusIcon = "▶️"
} else {
    $badge = "WARN"
    $appState = "미실행"
    $noticeLine = $null
    $statusIcon = "⚠️"
}

$messageLines = @(
    "<b>$(ConvertTo-TelegramHtml $MessageTitle)</b>",
    "",
    "<b>점검 결과: $statusIcon $badge</b>",
    "점검 대상: Codex 앱",
    "앱 실행 상태: $(ConvertTo-TelegramHtml $appState)"
)

if (![string]::IsNullOrWhiteSpace($noticeLine)) {
    $messageLines += ""
    $messageLines += "안내: $(ConvertTo-TelegramHtml $noticeLine)"
}

$messageLines += ""
$messageLines += "Checked at: $(ConvertTo-TelegramHtml $checkedAt.ToString("yyyy-MM-dd HH:mm:ss"))"

if (!$isRunning) {
    $messageLines += ""
    $messageLines += "프로세스: $($after.Count)개"
}

$message = $messageLines -join "`n"

Send-TelegramMessage -Message $message
