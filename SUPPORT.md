# Support

Before opening an issue, run the redacted diagnostic report:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -SupportBundle
```

Include the output in the issue. The report redacts Telegram tokens, chat IDs, and common local user paths.

## Useful Details To Include

- Which command failed.
- Windows version and PowerShell version.
- Whether Codex App can be opened manually.
- Whether the Telegram bot received `/start`.
- The output of `diagnose.ps1 -SupportBundle`.

## Do Not Include

- Telegram bot token.
- Real chat IDs.
- Screenshots that reveal private Telegram chats.
- Full local user paths if they are not already redacted.
