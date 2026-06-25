param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env"),
    [switch]$SkipEnvFileAcl,
    [switch]$SkipBotCommandMenu
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "codex-monitor-common.ps1")

$secureToken = Read-Host "Telegram bot token from BotFather" -AsSecureString
$token = ConvertFrom-CodexSecureStringPlainText -SecureValue $secureToken
if ([string]::IsNullOrWhiteSpace($token)) {
    throw "Bot token is required."
}

$me = Invoke-CodexTelegramApi -Token $token -MethodName "getMe"
if (!$me.ok) {
    throw "Telegram getMe failed."
}

Write-Host "Bot token verified."
Write-Host "Send /start to the new Codex bot in Telegram, then press Enter here."
Read-Host | Out-Null

$updates = Invoke-CodexTelegramApi `
    -Token $token `
    -MethodName "getUpdates" `
    -Payload @{ timeout = 1; allowed_updates = @("message", "my_chat_member") }
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
    throw "No Telegram chat was detected. Send /start to the bot and run this script again."
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
    "CODEX_HEARTBEAT_STALE_SECONDS=120"
)

Set-Content -LiteralPath $EnvFile -Value $lines -Encoding UTF8

if (!$SkipEnvFileAcl) {
    Protect-CodexEnvFile -Path $EnvFile
    Write-Host "Env file ACL protected."
}

if (!$SkipBotCommandMenu) {
    Set-CodexTelegramBotCommands -Token $token
    Write-Host "Telegram command menu registered."
}

Write-Host "Codex Telegram env configured."
Write-Host "Saved: $EnvFile"
Write-Host "Chat ID was detected and saved."
