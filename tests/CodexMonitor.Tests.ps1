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
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable("TELEGRAM_ALLOWED_CHAT_IDS", $script:previousAllowed, "Process")
        [Environment]::SetEnvironmentVariable("TELEGRAM_COMMAND_ALLOWED_CHAT_IDS", $script:previousCommandAllowed, "Process")
        [Environment]::SetEnvironmentVariable("TELEGRAM_START_ALLOWED_CHAT_IDS", $script:previousStartAllowed, "Process")
        [Environment]::SetEnvironmentVariable("TELEGRAM_CHAT_ID", $script:previousChatId, "Process")
        [Environment]::SetEnvironmentVariable("TELEGRAM_PERSONAL_CHAT_ID", $script:previousPersonalChatId, "Process")
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
        Get-CodexTelegramCommandType -Text "코덱스 앱 켜줘" | Should -Be "start"
        Get-CodexTelegramCommandType -Text "codex 점검" | Should -Be "health"
        Get-CodexTelegramCommandType -Text "hello" | Should -Be "unknown"
    }

    It "detects whether group messages explicitly target the bot" {
        Test-CodexTelegramMessageTargetsBot -Text "/s" -BotUsername "codex_manager_bot" | Should -BeTrue
        Test-CodexTelegramMessageTargetsBot -Text "/s@codex_manager_bot" -BotUsername "codex_manager_bot" | Should -BeTrue
        Test-CodexTelegramMessageTargetsBot -Text "codex status @codex_manager_bot" -BotUsername "codex_manager_bot" | Should -BeTrue
        Test-CodexTelegramMessageTargetsBot -Text "codex status" -BotUsername "codex_manager_bot" | Should -BeFalse
    }

    It "detects Telegram getUpdates conflict text" {
        Test-CodexTelegramConflictText -Text "Conflict: terminated by other getUpdates request; make sure that only one bot instance is running" | Should -BeTrue
        Test-CodexTelegramConflictText -Text "409 Conflict: another polling request is active" | Should -BeTrue
        Test-CodexTelegramConflictText -Text "The operation timed out" | Should -BeFalse
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
}
