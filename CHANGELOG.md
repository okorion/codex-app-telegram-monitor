# 변경 기록

Codex App Telegram Monitor의 주요 변경 사항을 기록합니다.

## 0.6.0 - 2026-06-25

- GitHub Release workflow를 재실행해도 기존 release를 안전하게 갱신하도록 `gh release edit` 및 `gh release upload --clobber` 경로를 추가했습니다.
- release archive 검증을 `test_release_archive.ps1`로 분리하고 일반 CI에서도 ZIP 필수/금지 파일과 SHA256 checksum 생성을 dry-run으로 확인하도록 추가했습니다.
- 그룹 채팅에서 알 수 없는 명령은 기본적으로 help를 보내지 않고 무시하도록 변경하고, 필요 시 `CODEX_GROUP_UNKNOWN_COMMAND_SHOW_HELP=true`로 되돌릴 수 있게 했습니다.
- watchdog이 listener 재시작 후 heartbeat를 다시 읽어 결과 출력에 재확인된 heartbeat 상태를 표시하도록 개선했습니다.
- 로컬 로그 파일에 쓰기 전에 token-like 값과 일반적인 로컬 사용자 경로를 redaction하도록 강화했습니다.
- boolean env 파싱, 로컬 로그 redaction, 그룹 unknown 명령 처리 테스트를 추가했습니다.

## 0.5.0 - 2026-06-25

- 그룹 채팅에서 `/s@other_bot`처럼 다른 봇을 명시한 명령에는 Codex 관리봇이 반응하지 않도록 target 판별을 강화했습니다.
- `codex status @codex_manager_bot`처럼 bot mention이 붙은 자연어형 명령도 정상적으로 해석하도록 개선했습니다.
- watchdog이 listener task의 `Running` 상태뿐 아니라 heartbeat freshness까지 확인하고, heartbeat가 없거나 오래되면 listener를 재시작하도록 개선했습니다.
- `.env`, listener 로그, heartbeat, offset, `VERSION` 읽기에 명시적 UTF-8/ASCII 인코딩을 적용해 Windows PowerShell 환경의 한글 깨짐 가능성을 줄였습니다.
- GitHub Release workflow에 수동 실행, tag 검증, release archive 필수/금지 파일 검증, SHA256 checksum 산출물을 추가했습니다.
- UTF-8 dotenv, 다른 봇 mention 무시, Telegram 메시지 포맷 회귀 테스트를 추가했습니다.

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
