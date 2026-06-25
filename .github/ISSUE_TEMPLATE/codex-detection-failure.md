---
name: Codex detection failure
about: Report Codex App launch or detection problems
title: "[Codex detection] "
labels: codex-detection
assignees: ""
---

## Problem

Describe whether Codex App cannot be launched, cannot be detected as running, or both.

Codex App 실행이 안 되는 문제인지, 실행 감지가 안 되는 문제인지, 둘 다인지 설명해 주세요.

## Diagnostic output

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -SupportBundle
```

Paste the redacted output here.

redaction된 출력을 여기에 붙여 넣어 주세요.

## Manual checks

- Can Codex App be opened from the Start menu?
- Does `/v` show any StartApps or Appx package candidates?
- Did you customize `CODEX_APP_USER_MODEL_ID` or `CODEX_PROCESS_PATH_PATTERN`?

## 수동 확인

- Start menu에서 Codex App을 열 수 있나요?
- `/v`에서 StartApps 또는 Appx package 후보가 보이나요?
- `CODEX_APP_USER_MODEL_ID` 또는 `CODEX_PROCESS_PATH_PATTERN`을 직접 설정했나요?
