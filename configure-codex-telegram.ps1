param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env"),
    [switch]$SkipEnvFileAcl,
    [switch]$SkipBotCommandMenu
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "codex-monitor-common.ps1")

$taskPath = "\Codex\"
$listenerTaskName = "Codex Telegram Command Listener"

function Invoke-WithListenerPausedForTelegramPolling {
    param([Parameter(Mandatory = $true)][scriptblock]$Operation)

    $listenerTask = Get-ScheduledTask -TaskName $listenerTaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    $wasRunning = $listenerTask -and $listenerTask.State -eq "Running"

    if ($wasRunning) {
        Write-Host "Chat ID 감지를 위해 command listener를 잠시 중지합니다."
        Stop-ScheduledTask -TaskName $listenerTaskName -TaskPath $taskPath
        Start-Sleep -Seconds 3
    }

    try {
        & $Operation
    } finally {
        if ($wasRunning) {
            Start-ScheduledTask -TaskName $listenerTaskName -TaskPath $taskPath
            Write-Host "Command listener를 다시 시작했습니다."
        }
    }
}

$secureToken = Read-Host "BotFather에서 받은 Telegram bot token" -AsSecureString
$token = ConvertFrom-CodexSecureStringPlainText -SecureValue $secureToken
if ([string]::IsNullOrWhiteSpace($token)) {
    throw "Bot token은 필수입니다."
}

$me = Invoke-CodexTelegramApi -Token $token -MethodName "getMe"
if (!$me.ok) {
    throw "Telegram getMe 호출에 실패했습니다."
}

Write-Host "Bot token 확인 완료."
Write-Host "Telegram에서 새 Codex bot에게 /start를 보낸 뒤 여기에서 Enter를 누르세요."
Read-Host | Out-Null

try {
    $updates = Invoke-WithListenerPausedForTelegramPolling {
        Invoke-CodexTelegramApi `
            -Token $token `
            -MethodName "getUpdates" `
            -Payload @{ timeout = 1; allowed_updates = @("message", "my_chat_member") }
    }
} catch {
    if (Test-CodexTelegramConflictError -ErrorRecord $_) {
        throw "Telegram getUpdates conflict가 발생했습니다. 같은 bot token으로 실행 중인 다른 PC 또는 listener를 중지한 뒤 다시 실행하거나 PC마다 별도 bot token을 사용하세요."
    }

    throw
}
$chat = $updates.result |
    Sort-Object update_id -Descending |
    ForEach-Object {
        if ($_.message -and $_.message.chat -and $_.message.chat.id) {
            $_.message.chat
        } elseif ($_.my_chat_member -and $_.my_chat_member.chat -and $_.my_chat_member.chat.id) {
            $_.my_chat_member.chat
        }
    } |
    Select-Object -First 1

if ($null -eq $chat) {
    throw "Telegram 채팅을 감지하지 못했습니다. bot에게 /start를 보낸 뒤 이 스크립트를 다시 실행하세요."
}

$envDir = Split-Path -Parent $EnvFile
if (!(Test-Path -LiteralPath $envDir)) {
    New-Item -ItemType Directory -Path $envDir -Force | Out-Null
}

$deviceName = if (![string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { $env:COMPUTERNAME } else { "auto" }
$lines = @(
    "TELEGRAM_BOT_TOKEN=$token",
    "TELEGRAM_CHAT_ID=$($chat.id)",
    "TELEGRAM_PERSONAL_CHAT_ID=$($chat.id)",
    "TELEGRAM_ALLOWED_CHAT_IDS=$($chat.id)",
    "TELEGRAM_COMMAND_ALLOWED_CHAT_IDS=$($chat.id)",
    "TELEGRAM_START_ALLOWED_CHAT_IDS=$($chat.id)",
    "CODEX_MONITOR_TITLE=Codex app monitor test",
    "CODEX_DEVICE_NAME=$deviceName",
    "CODEX_APP_USER_MODEL_ID=auto",
    "CODEX_PROCESS_PATH_PATTERN=auto",
    "CODEX_LOG_MAX_BYTES=1048576",
    "CODEX_LOG_KEEP_FILES=5",
    "CODEX_HEARTBEAT_STALE_SECONDS=120",
    "CODEX_POLLING_CONFLICT_STALE_SECONDS=3600"
)

Set-Content -LiteralPath $EnvFile -Value $lines -Encoding UTF8

if (!$SkipEnvFileAcl) {
    Protect-CodexEnvFile -Path $EnvFile
    Write-Host "환경 파일 ACL 보호 완료."
}

if (!$SkipBotCommandMenu) {
    Set-CodexTelegramBotCommands -Token $token
    Write-Host "Telegram 명령 메뉴 등록 완료."
}

Write-Host "Codex Telegram 환경 설정 완료."
Write-Host "저장 위치: $EnvFile"
Write-Host "Chat ID를 감지해 저장했습니다."
