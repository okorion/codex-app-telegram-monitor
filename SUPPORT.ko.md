# 지원

issue를 만들기 전에 redaction된 진단 리포트를 실행하세요.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -SupportBundle
```

출력을 issue에 포함하세요. 이 리포트는 Telegram token, chat ID, 일반적인 로컬 사용자 경로를 redaction합니다.

자동화된 지원 시스템이나 도구가 진단 결과를 파싱해야 한다면 아래 JSON 출력도 사용할 수 있습니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -Json
```

JSON 출력도 redaction됩니다.

## 함께 적으면 좋은 정보

- 실패한 명령
- Windows 버전과 PowerShell 버전
- Codex App을 수동으로 열 수 있는지 여부
- Telegram bot에게 `/start`를 보냈는지 여부
- 설치 또는 업데이트 후 `/p`, `/s`, `/o`를 테스트했는지 여부
- `diagnose.ps1 -SupportBundle` 출력

## 포함하지 말아야 할 정보

- Telegram bot token
- 실제 chat ID
- 개인 Telegram 채팅이 드러나는 스크린샷
- redaction되지 않은 전체 로컬 사용자 경로
