# Changelog

All notable changes to Codex App Telegram Monitor are documented here.

## 0.1.0 - 2026-06-25

- Added Telegram command listener for remote Codex App control.
- Added daily 09:00 monitor that starts Codex App when it is not running.
- Added one-letter Telegram commands: `/o`, `/s`, `/h`, `/v`, `/l`, `/p`, `/m`.
- Added listener watchdog, heartbeat reporting, log redaction, and log rotation.
- Added `.env` ACL protection and separate command-allowed chat configuration.
- Added English and Korean README files, overview image, and support diagnostics.
- Added `diagnose.ps1` for redacted support reports.
