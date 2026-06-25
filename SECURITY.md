# 보안

[English](SECURITY.en.md)

Codex App Telegram Monitor는 Telegram 봇을 통해 로컬 데스크톱 앱을 제어합니다. Bot token과 chat ID는 민감정보로 취급하세요.

## 위협 모델

- bot token을 가진 사람은 해당 봇으로 Telegram Bot API를 호출할 수 있습니다.
- 허용된 명령 채팅에 있는 사람은 이 도구가 지원하는 Codex App 동작을 요청할 수 있습니다.
- Telegram long polling은 로컬 HTTP 서버를 외부에 노출하지 않지만, PC에서 Telegram으로 나가는 네트워크 접근은 필요합니다.
- 그룹 채팅은 봇 메시지를 볼 수 있거나 명령을 보낼 수 있는 사람의 수를 늘립니다.
- 상태 확인 명령을 실행할 수 있는 채팅이 곧바로 로컬 데스크톱 앱 실행까지 허용받아야 하는 것은 아닙니다.

## 권장 기본값

- 이 자동화에는 전용 Telegram 봇을 사용하세요.
- active PC마다 별도 bot token을 사용하는 것을 권장합니다.
- 그룹 제어가 꼭 필요하지 않다면 개인 채팅에서만 명령을 허용하세요.
- `TELEGRAM_COMMAND_ALLOWED_CHAT_IDS`를 명시적으로 설정하세요.
- Codex App 실행 권한은 `TELEGRAM_START_ALLOWED_CHAT_IDS`에 가능한 한 좁게 설정하세요.
- `.env`는 Git에서 제외하고 `protect_env_file.ps1`로 ACL을 보호하세요.
- 지원 요청 시에는 `diagnose.ps1 -SupportBundle` 출력만 공유하세요.

## Token이 노출된 경우

1. Telegram에서 `@BotFather`를 엽니다.
2. 영향을 받은 봇의 token을 rotate합니다.
3. 새 token으로 `configure-codex-telegram.ps1`을 다시 실행합니다.
4. `install_all.ps1 -SkipConfigure`로 listener를 다시 설치하거나 재시작합니다.
5. Telegram에서 `/p`와 `/h`를 확인합니다.

노출된 token을 그룹에서 사용했다면 listener를 다시 시작하기 전에 `TELEGRAM_ALLOWED_CHAT_IDS`, `TELEGRAM_COMMAND_ALLOWED_CHAT_IDS`, `TELEGRAM_START_ALLOWED_CHAT_IDS`도 함께 점검하세요.

## 보안 이슈 보고

민감정보가 포함된 공개 issue를 열지 마세요. Token이나 chat ID 없이 최소 정보만 적거나, 먼저 token을 rotate한 뒤 redaction된 진단 출력만 공유하세요.
