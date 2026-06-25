# Codex App Telegram Monitor

Windows PowerShell tools for checking, notifying, and remotely starting the Codex desktop app through a dedicated Telegram bot.

![Codex App Telegram Monitor overview](assets/codex-app-telegram-monitor-overview.png)

## Recommended First-Time Setup

1. Create a dedicated Telegram bot with `@BotFather` and copy the bot token.
2. Clone this repository on the Windows PC.
3. Run the all-in-one installer, `install_all.ps1`.
4. Paste the bot token when PowerShell asks for it.
5. Send `/start` to the new bot in Telegram.
6. Return to PowerShell and press Enter.
7. After install completes, test `/p`, `/s`, and `/o` in Telegram.

```powershell
git clone https://github.com/okorion/codex-app-telegram-monitor.git
cd codex-app-telegram-monitor
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1
```

`install_all.ps1` configures `.env`, protects `.env` ACLs, registers the Telegram command menu, sends a test message, installs the 09:00 daily monitor, installs the command listener, installs the watchdog, and runs a health check.

## Control Conditions

After setup, you can control Codex App from Telegram when these conditions are true:

- The PC is powered on.
- The Windows user is logged in.
- The PC is not asleep.
- The PC can reach Telegram API over the internet.
- The `Codex Telegram Command Listener` scheduled task is running.
- The Telegram chat is included in the allowed chat ID settings in `.env`.
- Codex desktop app is installed on the PC.

This tool uses Telegram long polling. It does not need an inbound port or webhook server. It cannot start a GUI app when the PC is powered off, asleep, or no Windows user is logged in.

## Telegram Commands

Send these commands in an authorized bot chat:

| Short | Full command | Purpose |
| --- | --- | --- |
| `/p` | `/ping` | Check whether the command listener is responding. |
| `/s` | `/codex_status` | Check whether Codex App is currently running. |
| `/o` | `/codex_on` | Start Codex App remotely. Sends a request message first, then a final `OK` or `WARN`. |
| `/h` | `/codex_health` | Check Telegram, scheduler, listener, heartbeat, log, and `.env` ACL status. |
| `/v` | `/codex_version` | Show Codex App detection details, package version, and process paths. |
| `/l` | `/codex_logs` | Show recent listener logs. Defaults to 20 lines. |
| `/l 30` | `/codex_logs 30` | Show a specific number of recent log lines. Accepted range is 5 to 50. |
| `/m` | `/help` | Show the command list. |

In private chats, some natural-language messages are also supported, such as `codex status`, `codex start`, and Korean equivalents. In groups and supergroups, the listener responds only to `/` commands or messages that mention the bot, so ordinary group conversation does not trigger help replies.

## GUI Settings Tool

The GUI is optional. The console installer is usually easiest for first-time setup. Use the GUI when editing an existing `.env` or when console input is inconvenient.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\configure-codex-telegram-gui.ps1
```

The GUI can:

- Save `Telegram bot token`
- Edit notification, command-allowed, and start-allowed chat IDs
- Detect the latest chat ID through Telegram `getUpdates`
- Send a Telegram test message from the GUI
- Edit device name and message title
- Save `.env` and protect its ACL
- Run diagnostics

Chat ID detection requires sending `/start` or another message to the bot first. The GUI temporarily stops the local command listener while detecting the chat ID and starts it again afterward. If another PC is polling with the same bot token, Telegram may still return `409 Conflict`; in that case, stop the other listener or use one bot token per PC. If you saved `.env` from the GUI first, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1 -SkipConfigure
```

## Feature Summary

| Area | What it does |
| --- | --- |
| Daily monitor | At 09:00, checks whether Codex App is running. If it is not running, starts it and sends the result to Telegram. |
| Remote control | Lets an authorized Telegram chat start Codex App with `/o` or `/codex_on`. |
| Status checks | Reports running status, process count, app version, scheduler state, listener heartbeat, and recent logs. |
| Mobile shortcuts | Registers one-letter Telegram commands, such as `/o`, `/s`, `/h`, `/v`, `/l`, `/p`, and `/m`. |
| Watchdog | Checks every 5 minutes whether the command listener task is running and starts it again if needed. |
| Local security | Keeps secrets in ignored `.env`, protects `.env` ACLs, separates command/start-allowed chats, and redacts sensitive log content. |
| Multi-PC use | Supports per-PC display names and recommends one bot token per active PC because Telegram long polling is token-wide. |

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
- A personal chat with the bot.

## Install Options

Useful installer switches:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1 -SkipTelegramTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1 -SkipDailyMonitor
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1 -SkipCommandListener
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1 -SkipEnvFileAcl
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1 -SkipBotCommandMenu
```

Manual setup commands:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\configure-codex-telegram.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\telegram-test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\telegram-test.ps1 -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_task.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_command_listener_task.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register_bot_commands.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\protect_env_file.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\health-check.ps1
```

## Diagnostics And Support

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -SupportBundle
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -Json
```

Use `-SupportBundle` when opening a GitHub issue. Use `-Json` when another tool should parse the diagnostic result. Both outputs redact Telegram tokens, chat IDs, and common local user paths.

See [SUPPORT.en.md](SUPPORT.en.md) for support details.

## Updating

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\update.ps1
```

`update.ps1` pulls the latest repository changes, keeps the existing `.env`, refreshes scheduled tasks, restarts the listener task when installed, and runs diagnostics.

Manual update:

```powershell
git pull
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_all.ps1 -SkipConfigure -SkipTelegramTest
```

## Example Telegram Messages

![Telegram message examples](assets/telegram-message-examples.svg)

Status OK:

```text
Codex app monitor test

상태 확인 결과: ✅ OK
대상: Codex App
PC: DESKTOP-NAME
현재 실행 상태: 실행 중
프로세스: 1개

Processed at: 2026-06-25 12:00:00
```

Remote start flow:

```text
원격 실행 요청: ▶️ STARTED
대상: Codex App
PC: DESKTOP-NAME
실행 전 상태: 미실행
현재 실행 상태: 실행 확인 중
프로세스: 확인 중

최종 확인 결과: ✅ OK
대상: Codex App
PC: DESKTOP-NAME
현재 실행 상태: 실행 중
프로세스: 1개
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
TELEGRAM_START_ALLOWED_CHAT_IDS=
CODEX_MONITOR_TITLE=Codex app monitor test
CODEX_DEVICE_NAME=auto
CODEX_APP_USER_MODEL_ID=auto
CODEX_PROCESS_PATH_PATTERN=auto
CODEX_LOG_MAX_BYTES=1048576
CODEX_LOG_KEEP_FILES=5
CODEX_HEARTBEAT_STALE_SECONDS=120
CODEX_POLLING_CONFLICT_STALE_SECONDS=3600
```

`TELEGRAM_ALLOWED_CHAT_IDS` accepts comma, semicolon, or whitespace separated chat IDs. When it is empty, the listener falls back to `TELEGRAM_PERSONAL_CHAT_ID` and `TELEGRAM_CHAT_ID`.

`TELEGRAM_COMMAND_ALLOWED_CHAT_IDS` controls which chats may run commands. When it is empty, it falls back to `TELEGRAM_ALLOWED_CHAT_IDS`.

`TELEGRAM_START_ALLOWED_CHAT_IDS` controls which command-authorized chats may start Codex App with `/o` or `/codex_on`. When it is empty, it falls back to `TELEGRAM_COMMAND_ALLOWED_CHAT_IDS`.

`CODEX_DEVICE_NAME` appears in Telegram messages. Use a short friendly name when you run the monitor on more than one PC.

When `CODEX_APP_USER_MODEL_ID=auto`, the listener tries to detect Codex with `Get-StartApps`. When detection fails, it falls back to `OpenAI.Codex_2p2nqsd0c76g0!App`.

When `CODEX_PROCESS_PATH_PATTERN=auto`, the scripts use `*\OpenAI.Codex_*\app\Codex.exe`.

`CODEX_LOG_MAX_BYTES` and `CODEX_LOG_KEEP_FILES` control local listener log rotation. The default keeps five rotated files after the current log reaches 1 MB.

`CODEX_HEARTBEAT_STALE_SECONDS` controls when `/codex_health` reports the listener heartbeat as stale.

`CODEX_POLLING_CONFLICT_STALE_SECONDS` controls how far back `/h`, `diagnose.ps1`, and `health-check.ps1` treat Telegram polling conflict logs as current. The default is 3600 seconds.

## Multiple PCs

Telegram `getUpdates` long polling is best used with one active PC per bot token. If you install this monitor on multiple PCs, create a separate Telegram bot for each PC, or ensure only one PC uses a given bot token at a time. If two listeners poll with the same token, Telegram can return `409 Conflict`; `/h`, `diagnose.ps1`, and `health-check.ps1` surface this when it appears in listener logs within the configured time window.

Set a distinct `CODEX_DEVICE_NAME` on each PC so Telegram messages clearly show which computer handled the command.

Recommended multi-PC setup:

```text
PC A -> Telegram bot A -> CODEX_DEVICE_NAME=Home-PC
PC B -> Telegram bot B -> CODEX_DEVICE_NAME=Office-PC
```

## Scheduled Tasks

The installer scripts create these Windows Task Scheduler entries:

```text
\Codex\Ensure Codex App Running at 9AM
\Codex\Codex Telegram Command Listener
\Codex\Codex Telegram Command Listener Watchdog
```

The command listener starts at user logon and keeps polling Telegram while the Windows user session is active. The watchdog checks every 5 minutes and starts the listener task again if it is not running.

## Uninstall

Remove scheduled tasks while keeping `.env`, logs, and state:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall_all.ps1
```

Delete local configuration and runtime files only when you intentionally want a full cleanup:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall_all.ps1 -RemoveEnv -RemoveLogs -RemoveState
```

Remove individual tasks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall_task.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall_command_listener_task.ps1
```

## Security Notes

- Do not commit `.env`.
- Treat `TELEGRAM_BOT_TOKEN` and chat IDs as sensitive.
- Use a dedicated Telegram bot for this automation.
- Prefer one dedicated bot token per PC.
- Set `TELEGRAM_START_ALLOWED_CHAT_IDS` more narrowly than command chats if some chats should only inspect status.
- `protect_env_file.ps1` restricts `.env` ACL inheritance and grants access to the current user, SYSTEM, and local Administrators.
- Rotate the bot token in `@BotFather` if it is ever exposed.
- The listener uses Telegram long polling and does not expose a local HTTP server.
- `/codex_logs` redacts token-like values and common local user paths before sending logs to Telegram.

For a fuller security model, see [SECURITY.en.md](SECURITY.en.md).

## Releases

GitHub Releases can be used for downloadable ZIP packages. A tag named `vX.Y.Z` triggers the Release workflow, validates `VERSION`, and publishes a tracked-file ZIP archive. Release notes use only the matching version section from `CHANGELOG.md`. See [RELEASE.en.md](RELEASE.en.md).

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

Run the dry-run checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\telegram-test.ps1 -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ensure-codex-app-with-telegram.ps1 -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register_bot_commands.ps1 -DryRun
```

Run Pester tests when Pester 5 is available:

```powershell
Invoke-Pester -Path .\tests
```

## Language

[한국어](README.md) | English
