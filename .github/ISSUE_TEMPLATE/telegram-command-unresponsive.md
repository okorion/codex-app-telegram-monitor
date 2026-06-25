---
name: Telegram command unresponsive
about: Report Telegram commands that do not receive a response
title: "[Telegram] "
labels: telegram
assignees: ""
---

## Command

Which command did you send? Example: `/p`, `/s`, `/o`.

어떤 명령을 보냈나요? 예: `/p`, `/s`, `/o`.

## Diagnostic output

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -SupportBundle
```

Paste the redacted output here.

redaction된 출력을 여기에 붙여 넣어 주세요.

## Checks

- Did the bot receive `/start`?
- Is `Codex Telegram Command Listener` running in Task Scheduler?
- Are you sending the command from an allowed chat?

## 확인 사항

- bot에 `/start`를 보냈나요?
- Task Scheduler에서 `Codex Telegram Command Listener`가 실행 중인가요?
- 허용된 채팅에서 명령을 보내고 있나요?
