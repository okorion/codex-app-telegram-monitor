# Security

Codex App Telegram Monitor controls a local desktop app through a Telegram bot. Treat the bot token and chat IDs as sensitive.

## Threat Model

- Anyone with the bot token can call Telegram Bot API methods as that bot.
- Anyone in an allowed command chat can request Codex App actions supported by this tool.
- Telegram long polling does not expose a local HTTP server, but the local PC still needs outbound network access to Telegram.
- Group chats increase the number of people who can see bot messages and potentially send commands.

## Recommended Defaults

- Use a dedicated bot for this automation.
- Prefer one bot token per active PC.
- Keep command access in a personal chat unless group control is intentionally needed.
- Set `TELEGRAM_COMMAND_ALLOWED_CHAT_IDS` explicitly.
- Keep `.env` ignored by Git and protected with `protect_env_file.ps1`.
- Share only `diagnose.ps1 -SupportBundle` output when asking for support.

## If A Token Is Exposed

1. Open `@BotFather` in Telegram.
2. Rotate the token for the affected bot.
3. Run `configure-codex-telegram.ps1` again with the new token.
4. Reinstall or restart the listener with `install_all.ps1 -SkipConfigure`.
5. Check `/p` and `/h` in Telegram.

## Reporting Security Issues

Do not open a public issue containing secrets. Open a minimal issue without tokens or chat IDs, or rotate the token first and then share only redacted diagnostic output.
