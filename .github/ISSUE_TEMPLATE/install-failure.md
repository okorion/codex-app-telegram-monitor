---
name: 설치 실패
about: install_all.ps1 또는 초기 설정 실패를 제보합니다
title: "[설치] "
labels: install
assignees: ""
---

## 무엇이 실패했나요?

실패한 단계 또는 install summary를 붙여 주세요.

## 진단 출력

아래 명령을 실행하세요.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -SupportBundle
```

redaction된 출력을 여기에 붙여 주세요.

## 확인한 내용

- Telegram bot에게 `/start`를 보냈나요?
- Codex App을 수동으로 열 수 있나요?
- Windows 버전:
- PowerShell 버전:
