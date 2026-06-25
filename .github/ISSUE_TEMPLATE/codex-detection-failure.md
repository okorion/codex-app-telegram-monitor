---
name: Codex 감지 실패
about: Codex App 실행 또는 실행 상태 감지 문제를 제보합니다
title: "[Codex 감지] "
labels: codex-detection
assignees: ""
---

## 문제 설명

Codex App 실행이 안 되는 문제인지, 실행 중인데 감지되지 않는 문제인지, 둘 다인지 적어 주세요.

## 진단 출력

아래 명령을 실행하세요.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -SupportBundle
```

redaction된 출력을 여기에 붙여 주세요.

## 수동 확인

- Start menu에서 Codex App을 열 수 있나요?
- `/v`에서 StartApps 또는 Appx package 후보가 보이나요?
- `CODEX_APP_USER_MODEL_ID` 또는 `CODEX_PROCESS_PATH_PATTERN`을 직접 설정했나요?
