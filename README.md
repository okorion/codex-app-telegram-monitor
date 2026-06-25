# Codex App Telegram Monitor

Windows PowerShell scripts for managing the Codex desktop app through a dedicated Telegram bot.

![Codex App Telegram Monitor overview](assets/codex-app-telegram-monitor-overview.png)

The tool can:

- Send a daily Codex App status notification.
- Start Codex automatically at 09:00 if it is not running.
- Listen for Telegram commands from authorized chats.
- Start Codex remotely from a phone with `/codex_on`.
- Report health, version, listener heartbeat, and recent listener logs through Telegram.
- Register short Telegram bot commands for quick mobile use.

It uses Telegram long polling. No inbound network port or webhook server is required.

## Feature Summary

| Area | What it does |
| --- | --- |
| Daily monitor | At 09:00, checks whether Codex App is running. If it is not running, starts it and sends the result to Telegram. |
| Remote control | Lets an authorized Telegram chat start Codex App with `/o` or `/codex_on`. |
| Status checks | Reports running status, process count, app version, scheduler state, listener heartbeat, and recent logs. |
| Mobile shortcuts | Registers one-letter Telegram commands, such as `/o`, `/s`, `/h`, `/v`, `/l`, `/p`, and `/m`. |
| Watchdog | Checks every 5 minutes whether the command listener task is running and starts it again if needed. |
| Local security | Keeps secrets in ignored `.env`, protects `.env` ACLs, separates command-allowed chats, and redacts sensitive log content. |
| Multi-PC use | Supports per-PC display names and documents the one-bot-token-per-active-PC long-polling limitation. |

## How It Works

```text
Phone Telegram chat
  -> Telegram Bot API long polling
  -> Windows Task Scheduler listener
  -> Codex App start/status/version/log actions
  -> Telegram result message
```

Separate scheduled tasks handle the daily 09:00 monitor and the listener watchdog:

```text
09:00 daily task -> check Codex App -> start if needed -> send Telegram result
5 min watchdog  -> check listener task -> restart listener task if needed
```

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

The installer configures Telegram when `.env` is missing, protects the local `.env` ACL, registers the Telegram command menu, sends a test message, installs the daily monitor, installs the command listener, installs a listener watchdog, and runs `health-check.ps1`.

Useful installer switches:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1 -SkipTelegramTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1 -SkipDailyMonitor
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1 -SkipCommandListener
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1 -SkipEnvFileAcl
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1 -SkipBotCommandMenu
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

Register or refresh the Telegram command menu:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register_bot_commands.ps1
```

Protect the local `.env` file ACL:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\protect_env_file.ps1
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
/p
/m
```

Command reference:

| Short | Full command | Purpose |
| --- | --- | --- |
| `/o` | `/codex_on` | Start Codex App remotely. Sends a request message first, then a final `OK` or `WARN`. |
| `/s` | `/codex_status` | Check whether Codex App is currently running. |
| `/h` | `/codex_health` | Check Telegram, scheduler, listener, heartbeat, log, and `.env` ACL status. |
| `/v` | `/codex_version` | Show Codex App detection details, package version, and process paths. |
| `/l` | `/codex_logs` | Show recent listener logs. Defaults to 20 lines. |
| `/l 30` | `/codex_logs 30` | Show a specific number of recent log lines. Accepted range is 5 to 50. |
| `/p` | `/ping` | Confirm that the command listener is responding. |
| `/m` | `/help` | Show the command list. |

Full command names are also supported:

```text
/codex_on
/codex_status
/codex_health
/codex_version
/codex_logs
/codex_logs 30
/ping
/help
```

`/codex_on` sends a start request first. If Codex was not running, the listener waits up to 60 seconds and then sends a final `OK` or `WARN` message.

`/codex_health` reports bot, task scheduler, listener, watchdog, offset-file, heartbeat, log, and `.env` ACL status.

`/codex_version` reports Codex App detection details, package version when available, and running process paths.

`/codex_logs` sends recent listener logs. The default is 20 lines. The accepted range is 5 to 50 lines. Token-like values are redacted before sending.

`/ping` quickly confirms that the command listener is responding and reports the latest polling heartbeat.

Short aliases:

```text
/o = /codex_on
/s = /codex_status
/h = /codex_health
/v = /codex_version
/l = /codex_logs
/p = /ping
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
TELEGRAM_COMMAND_ALLOWED_CHAT_IDS=
CODEX_MONITOR_TITLE=Codex app monitor test
CODEX_DEVICE_NAME=auto
CODEX_APP_USER_MODEL_ID=auto
CODEX_PROCESS_PATH_PATTERN=auto
CODEX_LOG_MAX_BYTES=1048576
CODEX_LOG_KEEP_FILES=5
CODEX_HEARTBEAT_STALE_SECONDS=120
```

`TELEGRAM_ALLOWED_CHAT_IDS` accepts comma, semicolon, or whitespace separated chat IDs. When it is empty, the listener falls back to `TELEGRAM_PERSONAL_CHAT_ID` and `TELEGRAM_CHAT_ID`.

`TELEGRAM_COMMAND_ALLOWED_CHAT_IDS` controls which chats may run commands. When it is empty, it falls back to `TELEGRAM_ALLOWED_CHAT_IDS`.

`CODEX_DEVICE_NAME` appears in Telegram messages. Use a short friendly name when you run the monitor on more than one PC.

When `CODEX_APP_USER_MODEL_ID=auto`, the listener tries to detect Codex with `Get-StartApps`. When detection fails, it falls back to `OpenAI.Codex_2p2nqsd0c76g0!App`.

When `CODEX_PROCESS_PATH_PATTERN=auto`, the scripts use `*\OpenAI.Codex_*\app\Codex.exe`.

`CODEX_LOG_MAX_BYTES` and `CODEX_LOG_KEEP_FILES` control local listener log rotation. The default keeps five rotated files after the current log reaches 1 MB.

`CODEX_HEARTBEAT_STALE_SECONDS` controls when `/codex_health` reports the listener heartbeat as stale.

## Multiple PCs

Telegram `getUpdates` long polling is best used with one active PC per bot token. If you install this monitor on multiple PCs, create a separate Telegram bot for each PC, or ensure only one PC uses a given bot token at a time.

Set a distinct `CODEX_DEVICE_NAME` on each PC so Telegram messages clearly show which computer handled the command.

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
- Prefer one dedicated bot token per PC.
- `protect_env_file.ps1` restricts `.env` ACL inheritance and grants access to the current user, SYSTEM, and local Administrators.
- Rotate the bot token in `@BotFather` if it is ever exposed.
- The listener uses Telegram long polling and does not expose a local HTTP server.
- `/codex_logs` redacts token-like values and common local user paths before sending logs to Telegram.

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
