# 변경 기록

Codex App Telegram Monitor의 주요 변경 사항을 기록합니다.

## 0.4.0 - 2026-06-25

- polling conflict WARN이 오래된 로그 때문에 계속 남지 않도록 `CODEX_POLLING_CONFLICT_STALE_SECONDS` 시간 기준을 추가했습니다.
- `/h`, `diagnose.ps1`, `health-check.ps1`가 같은 polling conflict 시간 기준을 사용하도록 정리했습니다.
- GUI chat ID 감지 버튼이 로컬 command listener를 잠시 중지하고 감지 후 다시 시작하도록 개선했습니다.
- 콘솔 설정 스크립트도 chat ID 감지 중 로컬 listener를 잠시 중지하고, Telegram `409 Conflict` 발생 시 더 명확한 안내를 출력합니다.
- `SUPPORT.ko.md`를 기본 한국어 지원 문서와 충돌하지 않는 호환 안내 문서로 정리했습니다.
- polling conflict 시간 기준, 그룹 메시지 무시, `/h` conflict 표시 테스트를 추가했습니다.

## 0.3.0 - 2026-06-25

- GitHub Actions checkout을 v5로 올려 Node.js 20 deprecation 경고를 제거했습니다.
- GitHub Release notes가 전체 changelog 대신 현재 tag version 섹션만 사용하도록 개선했습니다.
- Telegram 그룹 채팅에서는 `/` 명령 또는 bot mention이 있는 메시지에만 반응하도록 변경해 일반 대화에 help 메시지가 나가는 일을 줄였습니다.
- Telegram `409 Conflict` / `getUpdates` polling 충돌을 listener 로그, `/h`, `diagnose.ps1`에서 더 명확히 진단하도록 개선했습니다.
- GUI 설정 도구에 chat ID 감지와 Telegram 테스트 메시지 전송 버튼을 추가했습니다.
- 명령 파싱, 그룹 메시지 타깃 판별, polling conflict 감지, redaction, `/o` dry-run 흐름 테스트를 추가했습니다.

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
