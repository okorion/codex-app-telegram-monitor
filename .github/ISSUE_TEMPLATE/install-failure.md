---
name: Install failure
about: Report a setup or install_all.ps1 failure
title: "[Install] "
labels: install
assignees: ""
---

## What failed?

Describe the failed step or paste the install summary.

어떤 설치 단계가 실패했는지 적거나 install summary를 붙여 넣어 주세요.

## Diagnostic output

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -SupportBundle
```

Paste the redacted output here.

redaction된 출력을 여기에 붙여 넣어 주세요.

## Notes

- Did you send `/start` to the Telegram bot?
- Can Codex App be opened manually?
- Windows version:
- PowerShell version:

## 참고

- Telegram bot에 `/start`를 보냈나요?
- Codex App을 수동으로 열 수 있나요?
- Windows 버전:
- PowerShell 버전:
