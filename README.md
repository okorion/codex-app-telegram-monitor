# Codex App Telegram Monitor

Windows PowerShell scripts for managing the Codex desktop app through a dedicated Telegram bot.

The tool can:

- Send a daily Codex app status notification.
- Start Codex automatically at 09:00 if it is not running.
- Listen for Telegram commands from an authorized chat.
- Start Codex remotely from a phone with `/codex_on`.

It uses Telegram long polling. No inbound network port or webhook server is required.

## Requirements

- Windows with PowerShell 5.1 or later.
- Codex desktop app installed.
- A Telegram bot created with `@BotFather`.
- A personal chat with the bot. Send `/start` to the bot before configuration.

## Quick Start

Clone the repository:

```powershell
git clone https://github.com/okorion/codex-app-telegram-monitor.git
cd codex-app-telegram-monitor
```

Configure the Telegram bot token and chat ID:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\configure-codex-telegram.ps1
```

Send a test Telegram message:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\telegram-test.ps1
```

Preview the test message without sending it:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\telegram-test.ps1 -DryRun
```

Install the daily 09:00 monitor:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_task.ps1
```

Install the Telegram command listener:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_command_listener_task.ps1
```

Check the setup:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\health-check.ps1
```

## Telegram Commands

Send these messages to the configured bot chat:

```text
/codex_on
/codex_status
/help
```

`/codex_on` sends a start request first. If Codex was not running, the listener waits up to 60 seconds and then sends a final `OK` or `WARN` message.

The listener only accepts messages from the configured `TELEGRAM_CHAT_ID` or `TELEGRAM_PERSONAL_CHAT_ID`.

## Configuration

`configure-codex-telegram.ps1` creates a local `.env` file. This file contains secrets and is intentionally ignored by Git.

Supported `.env` values:

```dotenv
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
TELEGRAM_PERSONAL_CHAT_ID=
CODEX_MONITOR_TITLE=Codex app monitor test
CODEX_APP_USER_MODEL_ID=OpenAI.Codex_2p2nqsd0c76g0!App
CODEX_PROCESS_PATH_PATTERN=*\OpenAI.Codex_*\app\Codex.exe
```

If Codex is installed with a different app user model ID or process path on another computer, override `CODEX_APP_USER_MODEL_ID` or `CODEX_PROCESS_PATH_PATTERN` in `.env`.

## Scheduled Tasks

The installer scripts create these Windows Task Scheduler entries:

```text
\Codex\Ensure Codex App Running at 9AM
\Codex\Codex Telegram Command Listener
```

The command listener starts at user logon and keeps polling Telegram while the Windows user session is active. It cannot start GUI apps when the PC is powered off, asleep, or not logged in.

## Uninstall

Remove the daily monitor task:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall_task.ps1
```

Remove the Telegram command listener task:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall_command_listener_task.ps1
```

## Security Notes

- Do not commit `.env`.
- Treat `TELEGRAM_BOT_TOKEN` and chat IDs as sensitive.
- Use a dedicated Telegram bot for this automation.
- Rotate the bot token in `@BotFather` if it is ever exposed.
- The listener uses Telegram long polling and does not expose a local HTTP server.

## Validation

Parse-check all PowerShell scripts:

```powershell
$scripts = Get-ChildItem -Filter *.ps1
foreach ($script in $scripts) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) {
    throw "Parse failed: $($script.Name)"
  }
}
```
