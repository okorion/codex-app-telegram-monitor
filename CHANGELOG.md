# 변경 기록

Codex App Telegram Monitor의 주요 변경 사항을 기록합니다.

## 0.2.0 - 2026-06-25

- 한 번의 명령으로 repository update, 예약 작업 갱신, listener 재시작, 진단을 실행하는 `update.ps1`를 추가했습니다.
- 예약 작업 전체 제거와 선택적 `.env`, logs, state 정리를 지원하는 `uninstall_all.ps1`를 추가했습니다.
- `configure-codex-telegram-gui.ps1`로 Windows GUI 설정 도구를 추가했습니다.
- 기계가 읽을 수 있는 redaction 진단 출력인 `diagnose.ps1 -Json`을 추가했습니다.
- 상태/도움말/로그 명령 권한과 원격 실행 권한을 분리하는 `TELEGRAM_START_ALLOWED_CHAT_IDS`를 추가했습니다.
- PowerShell, Task Scheduler cmdlet, execution policy, git, Codex StartApps 감지를 확인하는 installer preflight를 추가했습니다.
- Pester 테스트와 CI 실행을 추가했습니다.
- tag 기반 GitHub Release 자동화를 추가했습니다.
- README용 익명화된 Telegram 메시지 예시 이미지를 추가했습니다.

## 0.1.0 - 2026-06-25

- Codex App 원격 제어용 Telegram command listener를 추가했습니다.
- Codex App이 실행 중이 아니면 매일 09:00에 실행하는 monitor를 추가했습니다.
- `/o`, `/s`, `/h`, `/v`, `/l`, `/p`, `/m` 한 글자 Telegram 명령을 추가했습니다.
- listener watchdog, heartbeat 보고, log redaction, log rotation을 추가했습니다.
- `.env` ACL 보호와 command-allowed chat 설정 분리를 추가했습니다.
- 영어/한국어 README, overview image, 지원 진단 문서를 추가했습니다.
- redaction된 지원 리포트용 `diagnose.ps1`을 추가했습니다.
