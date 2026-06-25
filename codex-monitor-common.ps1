$script:CodexDefaultAppUserModelId = "OpenAI.Codex_2p2nqsd0c76g0!App"
$script:CodexDefaultProcessPathPattern = "*\OpenAI.Codex_*\app\Codex.exe"
$script:CodexDefaultMessageTitle = "Codex app monitor test"
$script:CodexDefaultToolVersion = "0.1.0"
$script:CodexDefaultPollingConflictStaleSeconds = 3600

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Import-CodexDotEnv {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (!(Test-Path -LiteralPath $Path)) {
        throw "환경 파일을 찾을 수 없습니다: $Path"
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

function Get-CodexTelegramCommandType {
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
        $trimmed -match '^(코덱스|Codex|codex)( 앱)?\s*(켜|켜기|실행|시작)(줘|주세요|해줘|해주세요)?$') {
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

function Test-CodexTelegramMessageTargetsBot {
    param(
        [AllowNull()][string]$Text,
        [AllowNull()][string]$BotUsername
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $trimmed = $Text.Trim()
    if ($trimmed.StartsWith("/")) {
        return $true
    }

    if (![string]::IsNullOrWhiteSpace($BotUsername)) {
        $escapedUsername = [regex]::Escape($BotUsername.TrimStart("@"))
        return $trimmed -match "(?i)(^|\s)@$escapedUsername(\b|$)"
    }

    return $false
}

function Test-CodexTelegramConflictText {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    return $Text -match '(?i)\b409\b.*\bconflict\b' -or
        $Text -match '(?i)terminated by other getUpdates request' -or
        ($Text -match '(?i)\bconflict\b' -and $Text -match '(?i)getUpdates|long polling|polling')
}

function Test-CodexTelegramConflictError {
    param([AllowNull()]$ErrorRecord)

    if ($null -eq $ErrorRecord) {
        return $false
    }

    $parts = New-Object System.Collections.Generic.List[string]
    $exception = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { $ErrorRecord.Exception } else { $ErrorRecord }
    if ($exception) {
        $parts.Add([string]$exception.Message) | Out-Null
        $response = $exception.Response
        if ($response -and $response.StatusCode) {
            $statusCode = [int]$response.StatusCode
            if ($statusCode -eq 409) {
                return $true
            }
            $parts.Add([string]$response.StatusCode) | Out-Null
        }
    }

    $parts.Add([string]$ErrorRecord) | Out-Null
    return Test-CodexTelegramConflictText -Text ($parts -join "`n")
}

function Get-CodexPollingConflictStaleSeconds {
    return Get-CodexIntEnvOrDefault `
        -Name "CODEX_POLLING_CONFLICT_STALE_SECONDS" `
        -DefaultValue $script:CodexDefaultPollingConflictStaleSeconds `
        -MinValue 60
}

function Get-CodexLogTimestamp {
    param([AllowNull()][string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line) -or $Line -notmatch '^\[(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]') {
        return $null
    }

    try {
        return [datetime]::ParseExact($matches.timestamp, "yyyy-MM-dd HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return $null
    }
}

function Test-CodexRecentTelegramConflict {
    param(
        [AllowNull()][object[]]$Lines,
        [int]$StaleSeconds = $script:CodexDefaultPollingConflictStaleSeconds,
        [datetime]$Now = (Get-Date)
    )

    if ($null -eq $Lines -or $Lines.Count -eq 0) {
        return $false
    }

    foreach ($line in $Lines) {
        $lineText = [string]$line
        if (!(Test-CodexTelegramConflictText -Text $lineText)) {
            continue
        }

        $timestamp = Get-CodexLogTimestamp -Line $lineText
        if ($null -eq $timestamp) {
            continue
        }

        $ageSeconds = [math]::Max(0, [int](($Now - $timestamp).TotalSeconds))
        if ($ageSeconds -le $StaleSeconds) {
            return $true
        }
    }

    return $false
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

function Get-CodexToolVersion {
    param([string]$Root = $PSScriptRoot)

    $versionFile = Join-Path $Root "VERSION"
    if (Test-Path -LiteralPath $versionFile) {
        $version = (Get-Content -LiteralPath $versionFile -Raw).Trim()
        if (![string]::IsNullOrWhiteSpace($version)) {
            return $version
        }
    }

    return $script:CodexDefaultToolVersion
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

function Get-CodexStartAppCandidates {
    try {
        return @(Get-StartApps |
            Where-Object { $_.AppID -like "OpenAI.Codex*" -or $_.Name -like "*Codex*" } |
            Select-Object -First 5)
    } catch {
        return @()
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

function Get-CodexAppxPackageCandidates {
    try {
        return @(Get-AppxPackage -Name "OpenAI.Codex*" -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending |
            Select-Object -First 5)
    } catch {
        return @()
    }
}

function Get-CodexProcessCandidates {
    try {
        return @(Get-Process -Name Codex -ErrorAction SilentlyContinue | Select-Object -First 10)
    } catch {
        return @()
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

function Get-CodexDetectionSummary {
    param([AllowNull()][string]$ProcessPathPattern = $script:CodexDefaultProcessPathPattern)

    $startApps = @(Get-CodexStartAppCandidates)
    $packages = @(Get-CodexAppxPackageCandidates)
    $processes = @(Get-CodexProcessCandidates)
    $matchingProcesses = @()
    if (![string]::IsNullOrWhiteSpace($ProcessPathPattern)) {
        $matchingProcesses = @($processes | Where-Object {
            try {
                $_.Path -like $ProcessPathPattern
            } catch {
                $false
            }
        })
    }

    return [PSCustomObject]@{
        StartAppCount = $startApps.Count
        StartApps = $startApps
        AppxPackageCount = $packages.Count
        AppxPackages = $packages
        CodexProcessCount = $processes.Count
        MatchingProcessCount = $matchingProcesses.Count
        Processes = $processes
        MatchingProcesses = $matchingProcesses
        ProcessPathPattern = $ProcessPathPattern
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

function ConvertTo-CodexRedactedText {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    $redacted = $Text
    $redacted = $redacted -replace 'bot[0-9]{6,}:[A-Za-z0-9_-]{20,}', 'bot<redacted>'
    $redacted = $redacted -replace '[0-9]{6,}:[A-Za-z0-9_-]{20,}', '<telegram-token-redacted>'
    $redacted = $redacted -replace 'gho_[A-Za-z0-9_]+', 'gho_<redacted>'
    $redacted = $redacted -replace '(TELEGRAM_(BOT_TOKEN|CHAT_ID|PERSONAL_CHAT_ID|ALLOWED_CHAT_IDS|COMMAND_ALLOWED_CHAT_IDS|START_ALLOWED_CHAT_IDS)\s*=\s*)\S+', '$1<redacted>'
    $redacted = $redacted -replace 'C:\\Users\\[^\\\s]+\\Documents\\Codex\\[^\s<]+', '<local-codex-path>'
    $redacted = $redacted -replace 'C:\\Users\\[^\\\s]+\\AppData\\[^\s<]+', '<local-appdata-path>'
    $redacted = $redacted -replace 'C:\\Users\\[^\\\s]+', '<local-user-path>'
    return $redacted
}

function Start-CodexApp {
    param([Parameter(Mandatory = $true)][string]$AppUserModelId)

    Start-Process explorer.exe "shell:AppsFolder\$AppUserModelId"
}

function Get-CodexTelegramToken {
    $token = [Environment]::GetEnvironmentVariable("TELEGRAM_BOT_TOKEN", "Process")
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Telegram 설정에 TELEGRAM_BOT_TOKEN이 없습니다."
    }

    return $token
}

function Get-CodexNotificationChatId {
    $chatId = [Environment]::GetEnvironmentVariable("TELEGRAM_PERSONAL_CHAT_ID", "Process")
    if ([string]::IsNullOrWhiteSpace($chatId)) {
        $chatId = [Environment]::GetEnvironmentVariable("TELEGRAM_CHAT_ID", "Process")
    }

    if ([string]::IsNullOrWhiteSpace($chatId)) {
        throw "Telegram 설정에 TELEGRAM_CHAT_ID가 없습니다."
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
        throw "Telegram 설정에 TELEGRAM_CHAT_ID가 없습니다."
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

function Get-CodexStartAllowedChatIds {
    $allowed = [Environment]::GetEnvironmentVariable("TELEGRAM_START_ALLOWED_CHAT_IDS", "Process")
    if (![string]::IsNullOrWhiteSpace($allowed)) {
        return Split-CodexChatIds -Value $allowed
    }

    return Get-CodexCommandAllowedChatIds
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
        @{ command = "o"; description = "Codex 앱 실행" },
        @{ command = "s"; description = "Codex 앱 상태 확인" },
        @{ command = "h"; description = "모니터 상태 점검" },
        @{ command = "v"; description = "Codex 앱 버전 확인" },
        @{ command = "l"; description = "최근 listener 로그 확인" },
        @{ command = "p"; description = "listener 응답 확인" },
        @{ command = "m"; description = "명령 도움말 보기" }
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
        return "알 수 없음"
    }

    $seconds = [math]::Max(0, [int]((Get-Date) - $Timestamp).TotalSeconds)
    if ($seconds -lt 60) {
        return "$seconds초 전"
    }

    $minutes = [int][math]::Floor($seconds / 60)
    if ($minutes -lt 60) {
        return "$minutes분 전"
    }

    $hours = [int][math]::Floor($minutes / 60)
    return "$hours시간 전"
}

function Protect-CodexEnvFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (!(Test-Path -LiteralPath $Path)) {
        throw "환경 파일을 찾을 수 없습니다: $Path"
    }

    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $grantSids = @($currentSid, "S-1-5-18", "S-1-5-32-544")

    & icacls.exe $Path /inheritance:r | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "환경 파일의 상속 ACL 해제에 실패했습니다."
    }

    foreach ($sid in $grantSids) {
        $ace = "*${sid}:F"
        & icacls.exe $Path /grant:r $ace | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "SID $sid에 대한 환경 파일 ACL 설정에 실패했습니다."
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
