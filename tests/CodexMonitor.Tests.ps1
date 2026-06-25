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
