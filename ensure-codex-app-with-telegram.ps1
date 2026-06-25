param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env"),
    [switch]$DryRun,
    [switch]$TelegramTest
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "codex-monitor-common.ps1")

function Send-MonitorTelegramMessage {
    param([Parameter(Mandatory = $true)][string]$Message)

    $chatId = Get-CodexNotificationChatId
    Send-CodexTelegramMessage -ChatId $chatId -Message $Message -DryRun:$DryRun
}

Import-CodexDotEnv -Path $EnvFile
$codexSettings = Resolve-CodexAppSettings
$codexAppUserModelId = $codexSettings.AppUserModelId
$codexProcessPathPattern = $codexSettings.ProcessPathPattern
$messageTitle = Get-CodexMessageTitle
$deviceName = Get-CodexDeviceName
$checkedAt = Get-Date

if ($TelegramTest) {
    $message = @(
        "<b>$(ConvertTo-CodexTelegramHtml $messageTitle)</b>",
        "",
        "<b>알림 테스트: ✅ 정상</b>",
        "대상: Codex App",
        "PC: $(ConvertTo-CodexTelegramHtml $deviceName)",
        "결과: 전용 텔레그램 봇 연결 정상",
        "",
        "Processed at: $(ConvertTo-CodexTelegramHtml $checkedAt.ToString("yyyy-MM-dd HH:mm:ss"))"
    ) -join "`n"

    Send-MonitorTelegramMessage -Message $message
    exit 0
}

$before = @(Get-CodexAppProcesses -ProcessPathPattern $codexProcessPathPattern)
$wasRunning = $before.Count -gt 0

if (!$wasRunning) {
    Start-CodexApp -AppUserModelId $codexAppUserModelId
    Start-Sleep -Seconds 8
}

$after = @(Get-CodexAppProcesses -ProcessPathPattern $codexProcessPathPattern)
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
    "<b>$(ConvertTo-CodexTelegramHtml $messageTitle)</b>",
    "",
    "<b>점검 결과: $statusIcon $badge</b>",
    "대상: Codex App",
    "PC: $(ConvertTo-CodexTelegramHtml $deviceName)",
    "앱 실행 상태: $(ConvertTo-CodexTelegramHtml $appState)"
)

if (![string]::IsNullOrWhiteSpace($noticeLine)) {
    $messageLines += ""
    $messageLines += "안내: $(ConvertTo-CodexTelegramHtml $noticeLine)"
}

$messageLines += ""
$messageLines += "Checked at: $(ConvertTo-CodexTelegramHtml $checkedAt.ToString("yyyy-MM-dd HH:mm:ss"))"

if (!$isRunning) {
    $messageLines += ""
    $messageLines += "프로세스: $($after.Count)개"
}

$message = $messageLines -join "`n"

Send-MonitorTelegramMessage -Message $message
