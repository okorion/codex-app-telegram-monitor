param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env"),
    [switch]$SupportBundle,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "codex-monitor-common.ps1")

$taskPath = "\Codex\"
$monitorTaskName = "Ensure Codex App Running at 9AM"
$listenerTaskName = "Codex Telegram Command Listener"
$watchdogTaskName = "Codex Telegram Command Listener Watchdog"
$offsetFile = Join-Path $PSScriptRoot "state\telegram-command-offset.txt"
$heartbeatFile = Join-Path $PSScriptRoot "state\telegram-command-listener-heartbeat.txt"
$logFile = Join-Path $PSScriptRoot "logs\telegram-command-listener.log"

function New-DiagnosticRow {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail,
        [string]$Fix = ""
    )

    return [PSCustomObject]@{
        Name = $Name
        Status = $Status
        Detail = $Detail
        Fix = $Fix
    }
}

function Get-TaskDiagnostic {
    param([Parameter(Mandatory = $true)][string]$TaskName)

    $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    if (!$task) {
        return New-DiagnosticRow -Name $TaskName -Status "FAIL" -Detail "예약 작업이 없습니다." -Fix "install_all.ps1 또는 해당 install 스크립트를 실행하세요."
    }

    $info = Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath $taskPath
    $usesEnv = @(@($task.Actions) | Where-Object { $_.Arguments -like "*$EnvFile*" }).Count -gt 0
    $status = if ($usesEnv) { "OK" } else { "WARN" }
    $detail = "State=$($task.State); NextRun=$($info.NextRunTime); LastRun=$($info.LastRunTime); LastResult=$($info.LastTaskResult); Env=$usesEnv"
    $fix = if ($usesEnv) { "" } else { "예약 작업이 이 repo의 .env 파일을 가리키도록 다시 설치하세요." }
    return New-DiagnosticRow -Name $TaskName -Status $status -Detail $detail -Fix $fix
}

function Get-HeartbeatDiagnostic {
    $heartbeatAt = Read-CodexListenerHeartbeat -Path $heartbeatFile
    if ($null -eq $heartbeatAt) {
        return New-DiagnosticRow -Name "Listener heartbeat" -Status "WARN" -Detail "Heartbeat 파일이 없거나 읽을 수 없습니다." -Fix "command listener 작업을 시작하거나 다시 설치하세요."
    }

    $ageSeconds = [math]::Max(0, [int]((Get-Date) - $heartbeatAt).TotalSeconds)
    $staleSeconds = Get-CodexIntEnvOrDefault -Name "CODEX_HEARTBEAT_STALE_SECONDS" -DefaultValue 120 -MinValue 30
    $status = if ($ageSeconds -le $staleSeconds) { "OK" } else { "WARN" }
    $fix = if ($status -eq "OK") { "" } else { "ensure_command_listener_running.ps1을 실행하거나 command listener를 다시 설치하세요." }
    return New-DiagnosticRow -Name "Listener heartbeat" -Status $status -Detail "Last=$($heartbeatAt.ToString("yyyy-MM-dd HH:mm:ss")); Age=${ageSeconds}s; StaleAfter=${staleSeconds}s" -Fix $fix
}

function Format-DiagnosticRows {
    param([Parameter(Mandatory = $true)][object[]]$Rows)

    $lines = @()
    foreach ($row in $Rows) {
        $lines += "[$($row.Status)] $($row.Name) - $($row.Detail)"
        if (![string]::IsNullOrWhiteSpace($row.Fix)) {
            $lines += "      Fix: $($row.Fix)"
        }
    }
    return $lines
}

function Get-RedactedEnvKeys {
    return @(
        "TELEGRAM_BOT_TOKEN",
        "TELEGRAM_CHAT_ID",
        "TELEGRAM_PERSONAL_CHAT_ID",
        "TELEGRAM_ALLOWED_CHAT_IDS",
        "TELEGRAM_COMMAND_ALLOWED_CHAT_IDS",
        "TELEGRAM_START_ALLOWED_CHAT_IDS",
        "CODEX_MONITOR_TITLE",
        "CODEX_DEVICE_NAME",
        "CODEX_APP_USER_MODEL_ID",
        "CODEX_PROCESS_PATH_PATTERN",
        "CODEX_LOG_MAX_BYTES",
        "CODEX_LOG_KEEP_FILES",
        "CODEX_HEARTBEAT_STALE_SECONDS"
    )
}

function Get-RedactedEnvSummary {
    param([hashtable]$EnvValues)

    foreach ($key in (Get-RedactedEnvKeys)) {
        $value = if ($EnvValues.ContainsKey($key)) { $EnvValues[$key] } else { "" }
        if ($key -like "TELEGRAM_*") {
            if ([string]::IsNullOrWhiteSpace($value)) {
                "$key=<missing>"
            } else {
                "$key=<redacted>"
            }
        } else {
            "$key=$(ConvertTo-CodexRedactedText -Text $value)"
        }
    }
}

function Get-RedactedEnvObject {
    param([hashtable]$EnvValues)

    $result = [ordered]@{}
    foreach ($key in (Get-RedactedEnvKeys)) {
        $value = if ($EnvValues.ContainsKey($key)) { $EnvValues[$key] } else { "" }
        if ($key -like "TELEGRAM_*") {
            $result[$key] = if ([string]::IsNullOrWhiteSpace($value)) { "<missing>" } else { "<redacted>" }
        } else {
            $result[$key] = ConvertTo-CodexRedactedText -Text $value
        }
    }

    return $result
}

function Get-ConfiguredAllowedChatIds {
    param(
        [hashtable]$EnvValues,
        [Parameter(Mandatory = $true)][string]$PrimaryKey,
        [AllowNull()][string[]]$Fallback = @()
    )

    if (![string]::IsNullOrWhiteSpace($EnvValues[$PrimaryKey])) {
        return Split-CodexChatIds -Value $EnvValues[$PrimaryKey]
    }

    if ($Fallback.Count -gt 0) {
        return @($Fallback | Select-Object -Unique)
    }

    $chatIds = @()
    if (![string]::IsNullOrWhiteSpace($EnvValues["TELEGRAM_PERSONAL_CHAT_ID"])) {
        $chatIds += $EnvValues["TELEGRAM_PERSONAL_CHAT_ID"]
    }
    if (![string]::IsNullOrWhiteSpace($EnvValues["TELEGRAM_CHAT_ID"])) {
        $chatIds += $EnvValues["TELEGRAM_CHAT_ID"]
    }

    return @($chatIds | Select-Object -Unique)
}

$toolVersion = Get-CodexToolVersion -Root $PSScriptRoot
$generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$envExists = Test-Path -LiteralPath $EnvFile
$envValues = Read-CodexDotEnvKeys -Path $EnvFile
if ($envExists) {
    Import-CodexDotEnv -Path $EnvFile
}

$tokenPresent = ![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_BOT_TOKEN"])
$chatPresent = ![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_CHAT_ID"]) -or ![string]::IsNullOrWhiteSpace($envValues["TELEGRAM_PERSONAL_CHAT_ID"])
$allowedChatIds = Get-ConfiguredAllowedChatIds -EnvValues $envValues -PrimaryKey "TELEGRAM_ALLOWED_CHAT_IDS"
$commandAllowedChatIds = Get-ConfiguredAllowedChatIds -EnvValues $envValues -PrimaryKey "TELEGRAM_COMMAND_ALLOWED_CHAT_IDS" -Fallback $allowedChatIds
$startAllowedChatIds = Get-ConfiguredAllowedChatIds -EnvValues $envValues -PrimaryKey "TELEGRAM_START_ALLOWED_CHAT_IDS" -Fallback $commandAllowedChatIds
$botReachable = if ($tokenPresent) { Test-CodexTelegramBot -Token $envValues["TELEGRAM_BOT_TOKEN"] } else { $false }
$envProtected = Test-CodexEnvFileProtected -Path $EnvFile

$settings = if ($envExists) { Resolve-CodexAppSettings } else { @{ AppUserModelId = ""; ProcessPathPattern = $script:CodexDefaultProcessPathPattern } }
$detection = Get-CodexDetectionSummary -ProcessPathPattern $settings.ProcessPathPattern
$matchingProcessCount = $detection.MatchingProcessCount
$logExists = Test-Path -LiteralPath $logFile
$logSize = if ($logExists) { (Get-Item -LiteralPath $logFile).Length } else { 0 }
$lastLogLines = if ($logExists) { @(Get-Content -LiteralPath $logFile -Tail 10 | ForEach-Object { ConvertTo-CodexRedactedText -Text $_ }) } else { @() }

$rows = @()
$rows += New-DiagnosticRow -Name "Tool version" -Status "OK" -Detail $toolVersion
$rows += New-DiagnosticRow -Name ".env" -Status $(if ($envExists) { "OK" } else { "FAIL" }) -Detail $(if ($envExists) { "있음" } else { "없음" }) -Fix $(if ($envExists) { "" } else { "configure-codex-telegram.ps1을 실행하세요." })
$rows += New-DiagnosticRow -Name ".env ACL" -Status $(if ($envProtected) { "OK" } else { "WARN" }) -Detail $(if ($envProtected) { "보호됨" } else { "보호되지 않음" }) -Fix $(if ($envProtected) { "" } else { "protect_env_file.ps1을 실행하세요." })
$rows += New-DiagnosticRow -Name "Telegram token" -Status $(if ($tokenPresent) { "OK" } else { "FAIL" }) -Detail $(if ($tokenPresent) { "있음" } else { "없음" }) -Fix $(if ($tokenPresent) { "" } else { "configure-codex-telegram.ps1을 실행하세요." })
$rows += New-DiagnosticRow -Name "Telegram chat" -Status $(if ($chatPresent) { "OK" } else { "FAIL" }) -Detail $(if ($chatPresent) { "설정됨" } else { "없음" }) -Fix $(if ($chatPresent) { "" } else { "bot에게 /start를 보낸 뒤 configure-codex-telegram.ps1을 다시 실행하세요." })
$rows += New-DiagnosticRow -Name "Telegram API" -Status $(if ($botReachable) { "OK" } else { "FAIL" }) -Detail $(if ($botReachable) { "연결 가능" } else { "연결 불가" }) -Fix $(if ($botReachable) { "" } else { "bot token과 네트워크 연결을 확인하세요." })
$allowedChatStatus = if ($allowedChatIds.Count -gt 0 -and $commandAllowedChatIds.Count -gt 0 -and $startAllowedChatIds.Count -gt 0) { "OK" } else { "WARN" }
$allowedChatFix = if ($allowedChatStatus -eq "OK") { "" } else { "그룹 또는 여러 채팅을 사용할 때 TELEGRAM_ALLOWED_CHAT_IDS, TELEGRAM_COMMAND_ALLOWED_CHAT_IDS, TELEGRAM_START_ALLOWED_CHAT_IDS를 설정하세요." }
$rows += New-DiagnosticRow -Name "허용 채팅" -Status $allowedChatStatus -Detail "알림=$($allowedChatIds.Count); 명령=$($commandAllowedChatIds.Count); 실행=$($startAllowedChatIds.Count)" -Fix $allowedChatFix
$rows += Get-TaskDiagnostic -TaskName $monitorTaskName
$rows += Get-TaskDiagnostic -TaskName $listenerTaskName
$rows += Get-TaskDiagnostic -TaskName $watchdogTaskName
$rows += Get-HeartbeatDiagnostic
$rows += New-DiagnosticRow -Name "Codex StartApps" -Status $(if ($detection.StartAppCount -gt 0) { "OK" } else { "WARN" }) -Detail "후보=$($detection.StartAppCount)" -Fix $(if ($detection.StartAppCount -gt 0) { "" } else { "Codex 실행이 안 되면 CODEX_APP_USER_MODEL_ID를 수동 설정하세요." })
$rows += New-DiagnosticRow -Name "Codex Appx package" -Status $(if ($detection.AppxPackageCount -gt 0) { "OK" } else { "WARN" }) -Detail "후보=$($detection.AppxPackageCount)"
$rows += New-DiagnosticRow -Name "Codex process" -Status $(if ($matchingProcessCount -gt 0) { "OK" } else { "WARN" }) -Detail "일치=$matchingProcessCount; 전체Codex=$($detection.CodexProcessCount); 패턴=$($settings.ProcessPathPattern)" -Fix $(if ($matchingProcessCount -gt 0) { "" } else { "Codex를 시작하거나 CODEX_PROCESS_PATH_PATTERN을 수동 설정하세요." })
$rows += New-DiagnosticRow -Name "Listener log" -Status $(if ($logExists) { "OK" } else { "WARN" }) -Detail $(if ($logExists) { "$logSize bytes" } else { "없음" })

$failed = @($rows | Where-Object { $_.Status -eq "FAIL" }).Count
$warned = @($rows | Where-Object { $_.Status -eq "WARN" }).Count
$overall = if ($failed -gt 0) { "FAIL" } elseif ($warned -gt 0) { "WARN" } else { "OK" }

if ($Json) {
    $jsonObject = [ordered]@{
        generatedAt = $generatedAt
        toolVersion = $toolVersion
        overall = $overall
        rows = @($rows | ForEach-Object {
            [ordered]@{
                name = $_.Name
                status = $_.Status
                detail = ConvertTo-CodexRedactedText -Text $_.Detail
                fix = ConvertTo-CodexRedactedText -Text $_.Fix
            }
        })
        environment = Get-RedactedEnvObject -EnvValues $envValues
        codexDetection = [ordered]@{
            startAppCount = $detection.StartAppCount
            startApps = @($detection.StartApps | ForEach-Object { [ordered]@{ name = $_.Name; appId = $_.AppID } })
            appxPackageCount = $detection.AppxPackageCount
            appxPackages = @($detection.AppxPackages | ForEach-Object { [ordered]@{ name = $_.Name; version = [string]$_.Version; packageFullName = $_.PackageFullName } })
            codexProcessCount = $detection.CodexProcessCount
            matchingProcessCount = $detection.MatchingProcessCount
            processPathPattern = ConvertTo-CodexRedactedText -Text $settings.ProcessPathPattern
            processes = @($detection.Processes | ForEach-Object { [ordered]@{ id = $_.Id; path = ConvertTo-CodexRedactedText -Text $_.Path } })
        }
        files = [ordered]@{
            envFileExists = $envExists
            envFileAclProtected = $envProtected
            listenerLogExists = $logExists
            listenerLogSizeBytes = $logSize
            recentListenerLogs = $lastLogLines
        }
        system = [ordered]@{
            powerShell = [string]$PSVersionTable.PSVersion
            os = [Environment]::OSVersion.VersionString
            computerName = $env:COMPUTERNAME
        }
    }

    $jsonObject | ConvertTo-Json -Depth 8
    if ($overall -eq "FAIL") {
        exit 2
    }
    exit 0
}

$output = @(
    "Codex App Telegram Monitor 진단",
    "생성 시각: $generatedAt",
    "Tool version: $toolVersion",
    "전체 결과: $overall",
    ""
)
$output += Format-DiagnosticRows -Rows $rows

if ($SupportBundle) {
    $output += ""
    $output += "환경 요약 (redacted):"
    $output += Get-RedactedEnvSummary -EnvValues $envValues
    $output += ""
    $output += "Codex 감지:"
    $output += "StartApps:"
    $output += @($detection.StartApps | ForEach-Object { "  Name=$($_.Name); AppID=$($_.AppID)" })
    $output += "Appx packages:"
    $output += @($detection.AppxPackages | ForEach-Object { "  Name=$($_.Name); Version=$($_.Version); PackageFullName=$($_.PackageFullName)" })
    $output += "Processes:"
    $output += @($detection.Processes | ForEach-Object { "  Id=$($_.Id); Path=$(ConvertTo-CodexRedactedText -Text $_.Path)" })
    $output += ""
    $output += "최근 listener 로그 (redacted):"
    $output += $lastLogLines
    $output += ""
    $output += "System:"
    $output += "PowerShell=$($PSVersionTable.PSVersion)"
    $output += "OS=$([Environment]::OSVersion.VersionString)"
    $output += "ComputerName=$env:COMPUTERNAME"
}

($output | ForEach-Object { ConvertTo-CodexRedactedText -Text $_ }) -join "`n"

if ($overall -eq "FAIL") {
    exit 2
}
