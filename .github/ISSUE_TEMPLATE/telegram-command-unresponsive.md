---
name: Telegram 명령 미응답
about: /p, /s, /o 같은 Telegram 명령이 응답하지 않는 문제를 제보합니다
title: "[Telegram 명령] "
labels: telegram-command
assignees: ""
---

## 어떤 명령이 응답하지 않나요?

예: `/p`, `/s`, `/o`, `/h`, `/v`, `/l`

## 기대한 동작

어떤 Telegram 메시지가 와야 한다고 예상했는지 적어 주세요.

## 실제 동작

응답 없음, WARN 메시지, 지연 응답 등 실제로 본 내용을 적어 주세요.

## 진단 출력

아래 명령을 실행하세요.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -SupportBundle
```

redaction된 출력을 여기에 붙여 주세요.

## 확인한 내용

- listener task 상태가 `Running`인가요?
- `/h` 또는 `diagnose.ps1`에서 heartbeat가 `Fresh`인가요?
- `Telegram polling conflict`가 `WARN`인가요? 그렇다면 같은 bot token을 쓰는 다른 PC 또는 listener가 있나요?
- 명령을 보낸 채팅이 `TELEGRAM_COMMAND_ALLOWED_CHAT_IDS`에 포함되어 있나요?
- `/o` 문제라면 `TELEGRAM_START_ALLOWED_CHAT_IDS`도 확인했나요?
