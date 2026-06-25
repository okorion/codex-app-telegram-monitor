# Codex App Telegram Monitor

Windows PowerShell scripts for managing the Codex desktop app through a dedicated Telegram bot.

The tool can:

- Send a daily Codex App status notification.
- Start Codex automatically at 09:00 if it is not running.
- Listen for Telegram commands from authorized chats.
- Start Codex remotely from a phone with `/codex_on`.
- Report health, version, and recent listener logs through Telegram.

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

Run the guided installer:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1
```

The installer configures Telegram when `.env` is missing, sends a test message, installs the daily monitor, installs the command listener, installs a listener watchdog, and runs `health-check.ps1`.

Useful installer switches:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1 -SkipTelegramTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1 -SkipDailyMonitor
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1 -SkipCommandListener
```

## Manual Setup

Configure Telegram:

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

Install the Telegram command listener and watchdog:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_command_listener_task.ps1
```

Check the setup:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\health-check.ps1
```

## Telegram Commands

Send these messages to an authorized bot chat:

```text
/o
/s
/h
/v
/l
/l 30
/m
```

Full command names are also supported:

```text
/codex_on
/codex_status
/codex_health
/codex_version
/codex_logs
/codex_logs 30
/help
```

`/codex_on` sends a start request first. If Codex was not running, the listener waits up to 60 seconds and then sends a final `OK` or `WARN` message.

`/codex_health` reports bot, task scheduler, listener, watchdog, and offset-file status.

`/codex_version` reports Codex App detection details, package version when available, and running process paths.

`/codex_logs` sends recent listener logs. The default is 20 lines. The accepted range is 5 to 50 lines. Token-like values are redacted before sending.

Short aliases:

```text
/o = /codex_on
/s = /codex_status
/h = /codex_health
/v = /codex_version
/l = /codex_logs
/m = /help
```

## Configuration

`configure-codex-telegram.ps1` creates a local `.env` file. This file contains secrets and is intentionally ignored by Git.

Supported `.env` values:

```dotenv
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
TELEGRAM_PERSONAL_CHAT_ID=
TELEGRAM_ALLOWED_CHAT_IDS=
CODEX_MONITOR_TITLE=Codex app monitor test
CODEX_APP_USER_MODEL_ID=auto
CODEX_PROCESS_PATH_PATTERN=auto
```

`TELEGRAM_ALLOWED_CHAT_IDS` accepts comma, semicolon, or whitespace separated chat IDs. When it is empty, the listener falls back to `TELEGRAM_PERSONAL_CHAT_ID` and `TELEGRAM_CHAT_ID`.

When `CODEX_APP_USER_MODEL_ID=auto`, the listener tries to detect Codex with `Get-StartApps`. When detection fails, it falls back to `OpenAI.Codex_2p2nqsd0c76g0!App`.

When `CODEX_PROCESS_PATH_PATTERN=auto`, the scripts use `*\OpenAI.Codex_*\app\Codex.exe`.

## Scheduled Tasks

The installer scripts create these Windows Task Scheduler entries:

```text
\Codex\Ensure Codex App Running at 9AM
\Codex\Codex Telegram Command Listener
\Codex\Codex Telegram Command Listener Watchdog
```

The command listener starts at user logon and keeps polling Telegram while the Windows user session is active. The watchdog checks every 5 minutes and starts the listener task again if it is not running.

These scripts cannot start GUI apps when the PC is powered off, asleep, or not logged in.

## Uninstall

Remove the daily monitor task:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall_task.ps1
```

Remove the Telegram command listener and watchdog tasks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall_command_listener_task.ps1
```

## Security Notes

- Do not commit `.env`.
- Treat `TELEGRAM_BOT_TOKEN` and chat IDs as sensitive.
- Use a dedicated Telegram bot for this automation.
- Rotate the bot token in `@BotFather` if it is ever exposed.
- The listener uses Telegram long polling and does not expose a local HTTP server.
- `/codex_logs` redacts token-like values before sending logs to Telegram.

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
