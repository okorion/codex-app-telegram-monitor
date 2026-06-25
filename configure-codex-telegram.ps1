param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env")
)

$ErrorActionPreference = "Stop"

function ConvertFrom-SecureStringPlainText {
    param([Parameter(Mandatory = $true)][SecureString]$SecureValue)

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Invoke-TelegramApi {
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$Method,
        [hashtable]$Query = @{}
    )

    $builder = [System.UriBuilder]::new("https://api.telegram.org/bot$Token/$Method")
    if ($Query.Count -gt 0) {
        $pairs = foreach ($item in $Query.GetEnumerator()) {
            "{0}={1}" -f [Uri]::EscapeDataString([string]$item.Key), [Uri]::EscapeDataString([string]$item.Value)
        }
        $builder.Query = ($pairs -join "&")
    }

    return Invoke-RestMethod -Method Get -Uri $builder.Uri
}

$secureToken = Read-Host "Telegram bot token from BotFather" -AsSecureString
$token = ConvertFrom-SecureStringPlainText -SecureValue $secureToken
if ([string]::IsNullOrWhiteSpace($token)) {
    throw "Bot token is required."
}

$me = Invoke-TelegramApi -Token $token -Method "getMe"
if (!$me.ok) {
    throw "Telegram getMe failed."
}

Write-Host "Bot token verified."
Write-Host "Send /start to the new Codex bot in Telegram, then press Enter here."
Read-Host | Out-Null

$updates = Invoke-TelegramApi -Token $token -Method "getUpdates" -Query @{ timeout = "1" }
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

$lines = @(
    "TELEGRAM_BOT_TOKEN=$token",
    "TELEGRAM_CHAT_ID=$($chat.id)",
    "TELEGRAM_PERSONAL_CHAT_ID=$($chat.id)",
    "TELEGRAM_ALLOWED_CHAT_IDS=$($chat.id)",
    "CODEX_MONITOR_TITLE=Codex app monitor test",
    "CODEX_APP_USER_MODEL_ID=auto",
    "CODEX_PROCESS_PATH_PATTERN=auto"
)

Set-Content -LiteralPath $EnvFile -Value $lines -Encoding UTF8
Write-Host "Codex Telegram env configured."
Write-Host "Saved: $EnvFile"
Write-Host "Chat ID was detected and saved."
