# Changelog

All notable changes to Codex App Telegram Monitor are documented here.

## 0.2.0 - 2026-06-25

- Added `update.ps1` for one-command repository update, task refresh, listener restart, and diagnostics.
- Added `uninstall_all.ps1` for full task removal with opt-in local `.env`, logs, and state cleanup.
- Added optional Windows GUI configuration with `configure-codex-telegram-gui.ps1`.
- Added `diagnose.ps1 -Json` for machine-readable redacted diagnostics.
- Added `TELEGRAM_START_ALLOWED_CHAT_IDS` to separate remote-start permission from status/help/log commands.
- Added installer preflight checks for PowerShell, Task Scheduler cmdlets, execution policy, git, and Codex StartApps detection.
- Added Pester tests and CI execution.
- Added tag-based GitHub Release automation that publishes a tracked-file ZIP archive.
- Added anonymized Telegram message example artwork for README files.

## 0.1.0 - 2026-06-25

- Added Telegram command listener for remote Codex App control.
- Added daily 09:00 monitor that starts Codex App when it is not running.
- Added one-letter Telegram commands: `/o`, `/s`, `/h`, `/v`, `/l`, `/p`, `/m`.
- Added listener watchdog, heartbeat reporting, log redaction, and log rotation.
- Added `.env` ACL protection and separate command-allowed chat configuration.
- Added English and Korean README files, overview image, and support diagnostics.
- Added `diagnose.ps1` for redacted support reports.
