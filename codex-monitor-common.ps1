$script:CodexDefaultAppUserModelId = "OpenAI.Codex_2p2nqsd0c76g0!App"
$script:CodexDefaultProcessPathPattern = "*\OpenAI.Codex_*\app\Codex.exe"
$script:CodexDefaultMessageTitle = "Codex app monitor test"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Import-CodexDotEnv {
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

function Read-CodexDotEnvKeys {
    param([Parameter(Mandatory = $true)][string]$Path)

    $result = @{}
    if (!(Test-Path -LiteralPath $Path)) {
        return $result
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') {
            $result[$matches[1]] = $matches[2].Trim()
        }
    }

    return $result
}

function Get-CodexEnvOrDefault {
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

function Get-CodexIntEnvOrDefault {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$DefaultValue,
        [int]$MinValue = 1
    )

    $value = [Environment]::GetEnvironmentVariable($Name, "Process")
    $parsed = 0
    if ([string]::IsNullOrWhiteSpace($value) -or ![int]::TryParse($value, [ref]$parsed) -or $parsed -lt $MinValue) {
        return $DefaultValue
    }

    return $parsed
}

function Get-CodexInt64EnvOrDefault {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int64]$DefaultValue,
        [int64]$MinValue = 1
    )

    $value = [Environment]::GetEnvironmentVariable($Name, "Process")
    $parsed = [int64]0
    if ([string]::IsNullOrWhiteSpace($value) -or ![int64]::TryParse($value, [ref]$parsed) -or $parsed -lt $MinValue) {
        return $DefaultValue
    }

    return $parsed
}

function Test-CodexAutoConfigValue {
    param([AllowNull()][string]$Value)

    return [string]::IsNullOrWhiteSpace($Value) -or $Value.Trim().ToLowerInvariant() -eq "auto"
}

function ConvertTo-CodexTelegramHtml {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    return $Text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")
}

function ConvertFrom-CodexSecureStringPlainText {
    param([Parameter(Mandatory = $true)][SecureString]$SecureValue)

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Split-CodexChatIds {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @($Value -split "[,;\s]+" | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Get-CodexDeviceName {
    $configured = [Environment]::GetEnvironmentVariable("CODEX_DEVICE_NAME", "Process")
    if (Test-CodexAutoConfigValue -Value $configured) {
        if (![string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) {
            return $env:COMPUTERNAME
        }

        return "Windows PC"
    }

    return $configured
}

function Get-CodexMessageTitle {
    return Get-CodexEnvOrDefault -Name "CODEX_MONITOR_TITLE" -DefaultValue $script:CodexDefaultMessageTitle
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

    if (Test-CodexAutoConfigValue -Value $configuredAppId) {
        if ($startApp -and ![string]::IsNullOrWhiteSpace($startApp.AppID)) {
            $resolvedAppId = $startApp.AppID
        } else {
            $resolvedAppId = $script:CodexDefaultAppUserModelId
        }
    } else {
        $resolvedAppId = $configuredAppId
    }

    if (Test-CodexAutoConfigValue -Value $configuredPathPattern) {
        $resolvedPathPattern = $script:CodexDefaultProcessPathPattern
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

function Get-CodexAppProcesses {
    param([Parameter(Mandatory = $true)][string]$ProcessPathPattern)

    return Get-Process -Name Codex -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $_.Path -like $ProcessPathPattern
            } catch {
                $false
            }
        }
}

function Start-CodexApp {
    param([Parameter(Mandatory = $true)][string]$AppUserModelId)

    Start-Process explorer.exe "shell:AppsFolder\$AppUserModelId"
}

function Get-CodexTelegramToken {
    $token = [Environment]::GetEnvironmentVariable("TELEGRAM_BOT_TOKEN", "Process")
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Telegram configuration is missing TELEGRAM_BOT_TOKEN."
    }

    return $token
}

function Get-CodexNotificationChatId {
    $chatId = [Environment]::GetEnvironmentVariable("TELEGRAM_PERSONAL_CHAT_ID", "Process")
    if ([string]::IsNullOrWhiteSpace($chatId)) {
        $chatId = [Environment]::GetEnvironmentVariable("TELEGRAM_CHAT_ID", "Process")
    }

    if ([string]::IsNullOrWhiteSpace($chatId)) {
        throw "Telegram configuration is missing TELEGRAM_CHAT_ID."
    }

    return $chatId
}

function Get-CodexAllowedChatIds {
    $allowed = [Environment]::GetEnvironmentVariable("TELEGRAM_ALLOWED_CHAT_IDS", "Process")
    if (![string]::IsNullOrWhiteSpace($allowed)) {
        return Split-CodexChatIds -Value $allowed
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

function Get-CodexCommandAllowedChatIds {
    $allowed = [Environment]::GetEnvironmentVariable("TELEGRAM_COMMAND_ALLOWED_CHAT_IDS", "Process")
    if (![string]::IsNullOrWhiteSpace($allowed)) {
        return Split-CodexChatIds -Value $allowed
    }

    return Get-CodexAllowedChatIds
}

function Test-CodexChatIdAllowed {
    param(
        [Parameter(Mandatory = $true)][string]$ChatId,
        [Parameter(Mandatory = $true)][string[]]$AllowedChatIds
    )

    return $AllowedChatIds -contains $ChatId
}

function Invoke-CodexTelegramApi {
    param(
        [Parameter(Mandatory = $true)][string]$MethodName,
        [hashtable]$Payload = @{},
        [AllowNull()][string]$Token = $null,
        [int]$TimeoutSec = 30
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        $Token = Get-CodexTelegramToken
    }

    $uri = "https://api.telegram.org/bot$Token/$MethodName"
    $body = $Payload | ConvertTo-Json -Depth 8 -Compress

    return Invoke-RestMethod `
        -Method Post `
        -Uri $uri `
        -ContentType "application/json; charset=utf-8" `
        -Body $body `
        -TimeoutSec $TimeoutSec
}

function Send-CodexTelegramMessage {
    param(
        [Parameter(Mandatory = $true)][string]$ChatId,
        [Parameter(Mandatory = $true)][string]$Message,
        [switch]$DryRun,
        [int]$TimeoutSec = 30
    )

    if ($DryRun) {
        Write-Output $Message
        return
    }

    Invoke-CodexTelegramApi -MethodName "sendMessage" -Payload @{
        chat_id = $ChatId
        text = $Message
        parse_mode = "HTML"
        disable_web_page_preview = $true
    } -TimeoutSec $TimeoutSec | Out-Null
}

function Test-CodexTelegramBot {
    param([AllowNull()][string]$Token)

    try {
        Invoke-CodexTelegramApi -MethodName "getMe" -Payload @{} -Token $Token -TimeoutSec 15 | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Get-CodexTelegramBotCommandDefinitions {
    return @(
        @{ command = "o"; description = "Start Codex app" },
        @{ command = "s"; description = "Check Codex app status" },
        @{ command = "h"; description = "Check monitor health" },
        @{ command = "v"; description = "Show Codex app version" },
        @{ command = "l"; description = "Show recent listener logs" },
        @{ command = "p"; description = "Ping command listener" },
        @{ command = "m"; description = "Show command help" }
    )
}

function Set-CodexTelegramBotCommands {
    param(
        [AllowNull()][string]$Token = $null,
        [switch]$DryRun
    )

    $commands = @(Get-CodexTelegramBotCommandDefinitions)
    if ($DryRun) {
        return $commands
    }

    Invoke-CodexTelegramApi -MethodName "setMyCommands" -Payload @{
        commands = $commands
        scope = @{ type = "default" }
    } -Token $Token -TimeoutSec 15 | Out-Null
}

function Ensure-CodexDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Rotate-CodexLogFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int64]$MaxBytes = 1048576,
        [int]$KeepFiles = 5
    )

    if (!(Test-Path -LiteralPath $Path)) {
        return
    }

    $file = Get-Item -LiteralPath $Path
    if ($file.Length -lt $MaxBytes) {
        return
    }

    for ($index = $KeepFiles - 1; $index -ge 1; $index--) {
        $source = "$Path.$index"
        $target = "$Path.$($index + 1)"
        if (Test-Path -LiteralPath $source) {
            if (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Force
            }
            Move-Item -LiteralPath $source -Destination $target -Force
        }
    }

    $archive = "$Path.1"
    if (Test-Path -LiteralPath $archive) {
        Remove-Item -LiteralPath $archive -Force
    }
    Move-Item -LiteralPath $Path -Destination $archive -Force
}

function Write-CodexLog {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message,
        [int64]$MaxBytes = 1048576,
        [int]$KeepFiles = 5
    )

    $directory = Split-Path -Parent $Path
    Ensure-CodexDirectory -Path $directory
    Rotate-CodexLogFile -Path $Path -MaxBytes $MaxBytes -KeepFiles $KeepFiles

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -LiteralPath $Path -Encoding UTF8 -Value "[$timestamp] $Message"
}

function Save-CodexListenerHeartbeat {
    param([Parameter(Mandatory = $true)][string]$Path)

    $directory = Split-Path -Parent $Path
    Ensure-CodexDirectory -Path $directory
    Set-Content -LiteralPath $Path -Encoding ASCII -Value (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

function Read-CodexListenerHeartbeat {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (!(Test-Path -LiteralPath $Path)) {
        return $null
    }

    $raw = (Get-Content -LiteralPath $Path -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    try {
        return [datetime]::ParseExact($raw, "yyyy-MM-dd HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return $null
    }
}

function Get-CodexAgeText {
    param([AllowNull()][Nullable[datetime]]$Timestamp)

    if ($null -eq $Timestamp) {
        return "unknown"
    }

    $seconds = [math]::Max(0, [int]((Get-Date) - $Timestamp).TotalSeconds)
    if ($seconds -lt 60) {
        return "$seconds sec ago"
    }

    $minutes = [int][math]::Floor($seconds / 60)
    if ($minutes -lt 60) {
        return "$minutes min ago"
    }

    $hours = [int][math]::Floor($minutes / 60)
    return "$hours hr ago"
}

function Protect-CodexEnvFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (!(Test-Path -LiteralPath $Path)) {
        throw "Env file not found: $Path"
    }

    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $grantSids = @($currentSid, "S-1-5-18", "S-1-5-32-544")

    & icacls.exe $Path /inheritance:r | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to disable inherited ACLs on env file."
    }

    foreach ($sid in $grantSids) {
        $ace = "*${sid}:F"
        & icacls.exe $Path /grant:r $ace | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to set ACL on env file for SID $sid."
        }
    }
}

function Test-CodexEnvFileProtected {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (!(Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $acl = Get-Acl -LiteralPath $Path
        return $acl.AreAccessRulesProtected
    } catch {
        return $false
    }
}
