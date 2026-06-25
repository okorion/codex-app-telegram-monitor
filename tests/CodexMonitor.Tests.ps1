Describe "Codex monitor common helpers" {
    BeforeAll {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path $script:repoRoot "codex-monitor-common.ps1")
    }

    BeforeEach {
        $script:previousAllowed = [Environment]::GetEnvironmentVariable("TELEGRAM_ALLOWED_CHAT_IDS", "Process")
        $script:previousCommandAllowed = [Environment]::GetEnvironmentVariable("TELEGRAM_COMMAND_ALLOWED_CHAT_IDS", "Process")
        $script:previousStartAllowed = [Environment]::GetEnvironmentVariable("TELEGRAM_START_ALLOWED_CHAT_IDS", "Process")
        $script:previousChatId = [Environment]::GetEnvironmentVariable("TELEGRAM_CHAT_ID", "Process")
        $script:previousPersonalChatId = [Environment]::GetEnvironmentVariable("TELEGRAM_PERSONAL_CHAT_ID", "Process")
        $script:previousTitle = [Environment]::GetEnvironmentVariable("CODEX_MONITOR_TITLE", "Process")
        $script:previousGroupUnknownShowHelp = [Environment]::GetEnvironmentVariable("CODEX_GROUP_UNKNOWN_COMMAND_SHOW_HELP", "Process")
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable("TELEGRAM_ALLOWED_CHAT_IDS", $script:previousAllowed, "Process")
        [Environment]::SetEnvironmentVariable("TELEGRAM_COMMAND_ALLOWED_CHAT_IDS", $script:previousCommandAllowed, "Process")
        [Environment]::SetEnvironmentVariable("TELEGRAM_START_ALLOWED_CHAT_IDS", $script:previousStartAllowed, "Process")
        [Environment]::SetEnvironmentVariable("TELEGRAM_CHAT_ID", $script:previousChatId, "Process")
        [Environment]::SetEnvironmentVariable("TELEGRAM_PERSONAL_CHAT_ID", $script:previousPersonalChatId, "Process")
        [Environment]::SetEnvironmentVariable("CODEX_MONITOR_TITLE", $script:previousTitle, "Process")
        [Environment]::SetEnvironmentVariable("CODEX_GROUP_UNKNOWN_COMMAND_SHOW_HELP", $script:previousGroupUnknownShowHelp, "Process")
    }

    It "splits comma, semicolon, and whitespace separated chat IDs" {
        Split-CodexChatIds -Value "1,2; 3  2" | Should -Be @("1", "2", "3")
    }

    It "escapes Telegram HTML special characters" {
        ConvertTo-CodexTelegramHtml -Text '<Codex & "Telegram">' | Should -Be '&lt;Codex &amp; "Telegram"&gt;'
    }

    It "redacts Telegram tokens and chat ID env values" {
        $chatId = "123" + "456789"
        $token = $chatId + ":" + "abcdefghijklmnopqrstuvwxyzABCDE"
        $text = "TELEGRAM_START_ALLOWED_CHAT_IDS=$chatId token=$token"
        $redacted = ConvertTo-CodexRedactedText -Text $text

        $redacted | Should -Not -Match ([regex]::Escape($token))
        $redacted | Should -Match "TELEGRAM_START_ALLOWED_CHAT_IDS=<redacted>"
    }

    It "loads the tool version from VERSION" {
        Get-CodexToolVersion -Root $script:repoRoot | Should -Not -BeNullOrEmpty
    }

    It "defines the expected short Telegram commands" {
        $commands = @(Get-CodexTelegramBotCommandDefinitions | ForEach-Object { $_.command })
        $commands | Should -Contain "o"
        $commands | Should -Contain "s"
        $commands | Should -Contain "h"
        $commands | Should -Contain "v"
        $commands | Should -Contain "l"
        $commands | Should -Contain "p"
        $commands | Should -Contain "m"
    }

    It "maps short, full, and natural-language Telegram commands" {
        Get-CodexTelegramCommandType -Text "/o" | Should -Be "start"
        Get-CodexTelegramCommandType -Text "/codex_status" | Should -Be "status"
        Get-CodexTelegramCommandType -Text "/l 30" | Should -Be "logs"
        Get-CodexTelegramCommandType -Text "codex status @codex_manager_bot" | Should -Be "status"
        Get-CodexTelegramCommandType -Text "코덱스 앱 켜줘" | Should -Be "start"
        Get-CodexTelegramCommandType -Text "codex 점검" | Should -Be "health"
        Get-CodexTelegramCommandType -Text "hello" | Should -Be "unknown"
    }

    It "detects whether group messages explicitly target the bot" {
        Test-CodexTelegramMessageTargetsBot -Text "/s" -BotUsername "codex_manager_bot" | Should -BeTrue
        Test-CodexTelegramMessageTargetsBot -Text "/s@codex_manager_bot" -BotUsername "codex_manager_bot" | Should -BeTrue
        Test-CodexTelegramMessageTargetsBot -Text "/s@Codex_Manager_Bot" -BotUsername "codex_manager_bot" | Should -BeTrue
        Test-CodexTelegramMessageTargetsBot -Text "/s@other_bot" -BotUsername "codex_manager_bot" | Should -BeFalse
        Test-CodexTelegramMessageTargetsBot -Text "/s@other_bot" -BotUsername "" | Should -BeFalse
        Test-CodexTelegramMessageTargetsBot -Text "codex status @codex_manager_bot" -BotUsername "codex_manager_bot" | Should -BeTrue
        Test-CodexTelegramMessageTargetsBot -Text "codex status" -BotUsername "codex_manager_bot" | Should -BeFalse
    }

    It "reads UTF-8 dotenv values consistently" {
        $envFile = Join-Path $TestDrive "utf8.env"
        Set-Content -LiteralPath $envFile -Encoding UTF8 -Value @(
            "CODEX_MONITOR_TITLE=한글 제목",
            "CODEX_DEVICE_NAME=테스트 PC"
        )

        $keys = Read-CodexDotEnvKeys -Path $envFile
        Import-CodexDotEnv -Path $envFile

        $keys["CODEX_MONITOR_TITLE"] | Should -Be "한글 제목"
        Get-CodexMessageTitle | Should -Be "한글 제목"
        Get-CodexDeviceName | Should -Be "테스트 PC"
    }

    It "detects Telegram getUpdates conflict text" {
        Test-CodexTelegramConflictText -Text "Conflict: terminated by other getUpdates request; make sure that only one bot instance is running" | Should -BeTrue
        Test-CodexTelegramConflictText -Text "409 Conflict: another polling request is active" | Should -BeTrue
        Test-CodexTelegramConflictText -Text "The operation timed out" | Should -BeFalse
    }

    It "treats only recent Telegram polling conflicts as active" {
        $now = [datetime]"2026-06-25 12:00:00"
        $lines = @(
            "[2026-06-25 10:55:00] Telegram polling conflict: old getUpdates conflict",
            "[2026-06-25 11:59:00] Telegram polling conflict: recent getUpdates conflict"
        )

        Test-CodexRecentTelegramConflict -Lines $lines -StaleSeconds 3600 -Now $now | Should -BeTrue
        Test-CodexRecentTelegramConflict -Lines @($lines[0]) -StaleSeconds 3600 -Now $now | Should -BeFalse
    }

    It "redacts common local user paths" {
        $appDataPath = "C:\Users\alice\AppData\Local\Temp\sample.txt"
        $codexPath = "C:\Users\alice\Documents" + "\Codex\repo"
        $text = "log=$appDataPath repo=$codexPath"
        $redacted = ConvertTo-CodexRedactedText -Text $text

        $redacted | Should -Not -Match "alice"
        $redacted | Should -Match "<local-appdata-path>"
        $redacted | Should -Match "<local-codex-path>"
    }

    It "parses boolean environment values with defaults" {
        [Environment]::SetEnvironmentVariable("CODEX_GROUP_UNKNOWN_COMMAND_SHOW_HELP", "yes", "Process")
        Get-CodexBoolEnvOrDefault -Name "CODEX_GROUP_UNKNOWN_COMMAND_SHOW_HELP" -DefaultValue $false | Should -BeTrue

        [Environment]::SetEnvironmentVariable("CODEX_GROUP_UNKNOWN_COMMAND_SHOW_HELP", "off", "Process")
        Get-CodexBoolEnvOrDefault -Name "CODEX_GROUP_UNKNOWN_COMMAND_SHOW_HELP" -DefaultValue $true | Should -BeFalse

        [Environment]::SetEnvironmentVariable("CODEX_GROUP_UNKNOWN_COMMAND_SHOW_HELP", "not-a-bool", "Process")
        Get-CodexBoolEnvOrDefault -Name "CODEX_GROUP_UNKNOWN_COMMAND_SHOW_HELP" -DefaultValue $true | Should -BeTrue
    }

    It "redacts sensitive text before writing local logs" {
        $logPath = Join-Path $TestDrive "sample.log"
        $token = "123456789:" + "abcdefghijklmnopqrstuvwxyzABCDE"
        $chatIdLine = "TELEGRAM_CHAT_ID=" + "123456789"

        Write-CodexLog -Path $logPath -Message "token=$token $chatIdLine"
        $logText = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8

        $logText | Should -Not -Match ([regex]::Escape($token))
        $logText | Should -Match "<telegram-token-redacted>"
        $logText | Should -Match "TELEGRAM_CHAT_ID=<redacted>"
    }

    It "falls back start permissions to command permissions" {
        [Environment]::SetEnvironmentVariable("TELEGRAM_CHAT_ID", "111", "Process")
        [Environment]::SetEnvironmentVariable("TELEGRAM_ALLOWED_CHAT_IDS", "222", "Process")
        [Environment]::SetEnvironmentVariable("TELEGRAM_COMMAND_ALLOWED_CHAT_IDS", "333", "Process")
        [Environment]::SetEnvironmentVariable("TELEGRAM_START_ALLOWED_CHAT_IDS", $null, "Process")

        Get-CodexStartAllowedChatIds | Should -Be @("333")
    }

    It "uses explicit start permissions when configured" {
        [Environment]::SetEnvironmentVariable("TELEGRAM_CHAT_ID", "111", "Process")
        [Environment]::SetEnvironmentVariable("TELEGRAM_ALLOWED_CHAT_IDS", "222", "Process")
        [Environment]::SetEnvironmentVariable("TELEGRAM_COMMAND_ALLOWED_CHAT_IDS", "333", "Process")
        [Environment]::SetEnvironmentVariable("TELEGRAM_START_ALLOWED_CHAT_IDS", "444 555", "Process")

        Get-CodexStartAllowedChatIds | Should -Be @("444", "555")
    }
}

Describe "Codex Telegram listener helpers" {
    BeforeAll {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path $script:repoRoot "codex-telegram-command-listener.ps1") -LoadOnly -DryRun
    }

    BeforeEach {
        $script:MessageTitle = "Codex app monitor test"
        $script:DeviceName = "TEST-PC"
    }

    It "keeps the status result message format stable" {
        $message = New-ResultMessage -ResultLabel "상태 확인 결과" -Result @{
            Badge = "OK"
            Icon = "✅"
            CurrentState = "실행 중"
            ProcessCount = 1
        }

        $message | Should -Match "<b>Codex app monitor test</b>"
        $message | Should -Match "<b>상태 확인 결과: ✅ OK</b>"
        $message | Should -Match "대상: Codex App"
        $message | Should -Match "PC: .+"
        $message | Should -Match "현재 실행 상태: 실행 중"
        $message | Should -Match "프로세스: 1개"
        $message | Should -Match "Processed at: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"
        $message | Should -Not -Match "확인 필요"
    }

    It "keeps the warning result message format stable" {
        $message = New-ResultMessage -ResultLabel "최종 확인 결과" -Result @{
            Badge = "WARN"
            Icon = "⚠️"
            BeforeState = "미실행"
            CurrentState = "미실행"
            ProcessCount = 0
        }

        $message | Should -Match "<b>최종 확인 결과: ⚠️ WARN</b>"
        $message | Should -Match "실행 전 상태: 미실행"
        $message | Should -Match "현재 실행 상태: 미실행"
        $message | Should -Match "프로세스: 0개"
        $message | Should -Match "확인 필요: Codex 앱이 실행되지 않았습니다."
    }

    It "sends a dry-run result for the remote start flow" {
        $script:sentMessages = @()

        function Get-CodexAppProcessList {
            return @()
        }

        function Send-TelegramMessage {
            param(
                [Parameter(Mandatory = $true)][string]$ChatId,
                [Parameter(Mandatory = $true)][string]$Message
            )

            $script:sentMessages += [PSCustomObject]@{
                ChatId = $ChatId
                Message = $Message
            }
        }

        Invoke-CodexRemoteStart -ChatId "111"

        $script:sentMessages.Count | Should -Be 1
        $script:sentMessages[0].ChatId | Should -Be "111"
        $script:sentMessages[0].Message | Should -Match "DRY-RUN"
        $script:sentMessages[0].Message | Should -Match "현재 실행 상태"
    }

    It "ignores ordinary group messages that do not target the bot" {
        $script:sentMessages = @()
        $script:listenerLogs = @()
        $script:BotUsername = "codex_manager_bot"

        function Test-AllowedChatId {
            param([Parameter(Mandatory = $true)][string]$ChatId)
            return $true
        }

        function Send-TelegramMessage {
            param(
                [Parameter(Mandatory = $true)][string]$ChatId,
                [Parameter(Mandatory = $true)][string]$Message
            )

            $script:sentMessages += $Message
        }

        function Write-ListenerLog {
            param([Parameter(Mandatory = $true)][string]$Message)
            $script:listenerLogs += $Message
        }

        $update = [PSCustomObject]@{
            message = [PSCustomObject]@{
                text = "codex status"
                chat = [PSCustomObject]@{
                    id = 111
                    type = "group"
                }
            }
        }

        Handle-TelegramUpdate -Update $update

        $script:sentMessages.Count | Should -Be 0
        $script:listenerLogs -join "`n" | Should -Match "그룹 채팅의 일반 메시지"
    }

    It "ignores group commands addressed to another bot" {
        $script:sentMessages = @()
        $script:listenerLogs = @()
        $script:BotUsername = "codex_manager_bot"

        function Test-AllowedChatId {
            param([Parameter(Mandatory = $true)][string]$ChatId)
            return $true
        }

        function Send-TelegramMessage {
            param(
                [Parameter(Mandatory = $true)][string]$ChatId,
                [Parameter(Mandatory = $true)][string]$Message
            )

            $script:sentMessages += $Message
        }

        function Write-ListenerLog {
            param([Parameter(Mandatory = $true)][string]$Message)
            $script:listenerLogs += $Message
        }

        $update = [PSCustomObject]@{
            message = [PSCustomObject]@{
                text = "/s@other_bot"
                chat = [PSCustomObject]@{
                    id = 111
                    type = "group"
                }
            }
        }

        Handle-TelegramUpdate -Update $update

        $script:sentMessages.Count | Should -Be 0
        $script:listenerLogs -join "`n" | Should -Match "그룹 채팅의 일반 메시지"
    }

    It "ignores unknown group slash commands by default" {
        $script:sentMessages = @()
        $script:listenerLogs = @()
        $script:BotUsername = "codex_manager_bot"
        [Environment]::SetEnvironmentVariable("CODEX_GROUP_UNKNOWN_COMMAND_SHOW_HELP", $null, "Process")

        function Test-AllowedChatId {
            param([Parameter(Mandatory = $true)][string]$ChatId)
            return $true
        }

        function Send-TelegramMessage {
            param(
                [Parameter(Mandatory = $true)][string]$ChatId,
                [Parameter(Mandatory = $true)][string]$Message
            )

            $script:sentMessages += $Message
        }

        function Write-ListenerLog {
            param([Parameter(Mandatory = $true)][string]$Message)
            $script:listenerLogs += $Message
        }

        $update = [PSCustomObject]@{
            message = [PSCustomObject]@{
                text = "/foo"
                chat = [PSCustomObject]@{
                    id = 111
                    type = "group"
                }
            }
        }

        Handle-TelegramUpdate -Update $update

        $script:sentMessages.Count | Should -Be 0
        $script:listenerLogs -join "`n" | Should -Match "알 수 없는 명령"
    }

    It "can show help for unknown group commands when configured" {
        $script:sentMessages = @()
        $script:listenerLogs = @()
        $script:BotUsername = "codex_manager_bot"
        [Environment]::SetEnvironmentVariable("CODEX_GROUP_UNKNOWN_COMMAND_SHOW_HELP", "true", "Process")

        function Test-AllowedChatId {
            param([Parameter(Mandatory = $true)][string]$ChatId)
            return $true
        }

        function Send-TelegramMessage {
            param(
                [Parameter(Mandatory = $true)][string]$ChatId,
                [Parameter(Mandatory = $true)][string]$Message
            )

            $script:sentMessages += $Message
        }

        $update = [PSCustomObject]@{
            message = [PSCustomObject]@{
                text = "/foo"
                chat = [PSCustomObject]@{
                    id = 111
                    type = "group"
                }
            }
        }

        Handle-TelegramUpdate -Update $update

        $script:sentMessages.Count | Should -Be 1
        $script:sentMessages[0] | Should -Match "사용 가능한 명령"
    }

    It "shows polling conflict state in the health message" {
        function Get-CodexAllowedChatIds { @("111") }
        function Get-CodexCommandAllowedChatIds { @("111") }
        function Get-CodexStartAllowedChatIds { @("111") }
        function Get-TaskHealth {
            param([Parameter(Mandatory = $true)][string]$TaskName)
            return @{
                Exists = $true
                UsesEnvFile = $true
                State = "Ready"
            }
        }
        function Get-ListenerHeartbeatStatus {
            return @{
                Exists = $true
                Fresh = $true
                TimestampText = "2026-06-25 12:00:00"
                AgeText = "1초 전"
            }
        }
        function Test-CodexTelegramBot { return $true }
        function Test-CodexEnvFileProtected { return $true }
        function Test-RecentPollingConflict { return $true }

        [Environment]::SetEnvironmentVariable("TELEGRAM_BOT_TOKEN", "dummy", "Process")

        $message = New-HealthMessage

        $message | Should -Match "상태 점검: ⚠️ WARN"
        $message | Should -Match "Polling conflict: ⚠️ 최근 감지됨"
    }
}
