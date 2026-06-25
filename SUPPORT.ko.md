# 지원

issue를 만들기 전에 redaction된 진단 리포트를 실행하세요.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -SupportBundle
```

출력을 issue에 포함하세요. 이 리포트는 Telegram token, chat ID, 일반적인 로컬 사용자 경로를 redaction합니다.

## 함께 적으면 좋은 정보

- 실패한 명령
- Windows 버전과 PowerShell 버전
- Codex App을 수동으로 열 수 있는지 여부
- Telegram bot에 `/start`를 보냈는지 여부
- `diagnose.ps1 -SupportBundle` 출력

## 포함하지 말아야 할 정보

- Telegram bot token
- 실제 chat ID
- 개인 Telegram 채팅이 보이는 스크린샷
- redaction되지 않은 전체 로컬 사용자 경로
