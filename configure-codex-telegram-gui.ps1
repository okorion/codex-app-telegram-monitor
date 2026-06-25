param(
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env")
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "codex-monitor-common.ps1")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$existing = Read-CodexDotEnvKeys -Path $EnvFile

function Get-ExistingValue {
    param([Parameter(Mandatory = $true)][string]$Key, [string]$Default = "")

    if ($existing.ContainsKey($Key)) {
        return $existing[$Key]
    }

    return $Default
}

function Add-Field {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Form]$Form,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][int]$Top,
        [string]$Value = "",
        [switch]$Password
    )

    $labelControl = New-Object System.Windows.Forms.Label
    $labelControl.Text = $Label
    $labelControl.Left = 16
    $labelControl.Top = $Top + 4
    $labelControl.Width = 190
    $Form.Controls.Add($labelControl)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Left = 210
    $textBox.Top = $Top
    $textBox.Width = 390
    $textBox.Text = $Value
    if ($Password) {
        $textBox.UseSystemPasswordChar = $true
    }
    $Form.Controls.Add($textBox)

    return $textBox
}

function Show-GuiException {
    param(
        [Parameter(Mandatory = $true)]$ErrorRecord,
        [Parameter(Mandatory = $true)][string]$Title
    )

    if (Test-CodexTelegramConflictError -ErrorRecord $ErrorRecord) {
        [System.Windows.Forms.MessageBox]::Show(
            "같은 bot token으로 다른 PC 또는 listener가 Telegram polling 중입니다.`n다른 listener를 중지한 뒤 다시 시도하거나 PC마다 별도 bot token을 사용하세요.",
            $Title
        ) | Out-Null
        return
    }

    [System.Windows.Forms.MessageBox]::Show($ErrorRecord.Exception.Message, $Title) | Out-Null
}

function Get-GuiBotToken {
    $token = $botToken.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Telegram bot token은 필수입니다."
    }

    return $token
}

function Get-LatestTelegramChatFromUpdates {
    param([Parameter(Mandatory = $true)][string]$Token)

    $response = Invoke-CodexTelegramApi `
        -Token $Token `
        -MethodName "getUpdates" `
        -Payload @{ timeout = 1; allowed_updates = @("message", "my_chat_member") } `
        -TimeoutSec 10

    if (!$response.ok) {
        throw "Telegram getUpdates 응답이 올바르지 않습니다."
    }

    $candidates = @(
        foreach ($update in @($response.result)) {
            $chat = $null
            if ($update.message -and $update.message.chat) {
                $chat = $update.message.chat
            } elseif ($update.my_chat_member -and $update.my_chat_member.chat) {
                $chat = $update.my_chat_member.chat
            }

            if ($chat) {
                $displayName = @($chat.title, $chat.username, $chat.first_name, $chat.last_name) |
                    Where-Object { ![string]::IsNullOrWhiteSpace([string]$_) } |
                    Select-Object -First 1

                [PSCustomObject]@{
                    Id = [string]$chat.id
                    Type = [string]$chat.type
                    Name = [string]$displayName
                    UpdateId = [int64]$update.update_id
                }
            }
        }
    )

    if ($candidates.Count -eq 0) {
        throw "chat ID를 찾지 못했습니다. Telegram에서 bot에게 /start 또는 메시지를 보낸 뒤 다시 시도하세요."
    }

    return $candidates | Sort-Object UpdateId -Descending | Select-Object -First 1
}

function Set-DetectedChatFields {
    param([Parameter(Mandatory = $true)]$DetectedChat)

    if ([string]::IsNullOrWhiteSpace($chatId.Text)) {
        $chatId.Text = $DetectedChat.Id
    }
    if ([string]::IsNullOrWhiteSpace($personalChatId.Text) -and
        ([string]::IsNullOrWhiteSpace($DetectedChat.Type) -or $DetectedChat.Type -eq "private")) {
        $personalChatId.Text = $DetectedChat.Id
    }
    if ([string]::IsNullOrWhiteSpace($allowedChats.Text)) {
        $allowedChats.Text = $DetectedChat.Id
    }
    if ([string]::IsNullOrWhiteSpace($commandChats.Text)) {
        $commandChats.Text = $DetectedChat.Id
    }
    if ([string]::IsNullOrWhiteSpace($startChats.Text)) {
        $startChats.Text = $DetectedChat.Id
    }
}

function Send-GuiTestMessage {
    $token = Get-GuiBotToken
    $targetChatId = if (![string]::IsNullOrWhiteSpace($personalChatId.Text)) {
        $personalChatId.Text.Trim()
    } else {
        $chatId.Text.Trim()
    }
    if ([string]::IsNullOrWhiteSpace($targetChatId)) {
        throw "테스트 메시지를 보낼 chat ID가 필요합니다."
    }

    $messageTitle = if ([string]::IsNullOrWhiteSpace($title.Text)) { "Codex app monitor test" } else { $title.Text.Trim() }
    $displayDeviceName = if ([string]::IsNullOrWhiteSpace($deviceName.Text) -or $deviceName.Text.Trim().ToLowerInvariant() -eq "auto") {
        if (![string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { $env:COMPUTERNAME } else { "Windows PC" }
    } else {
        $deviceName.Text.Trim()
    }
    $processedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    $message = @(
        "<b>$(ConvertTo-CodexTelegramHtml $messageTitle)</b>",
        "",
        "<b>GUI 테스트: ✅ OK</b>",
        "대상: Codex App",
        "PC: $(ConvertTo-CodexTelegramHtml $displayDeviceName)",
        "결과: GUI에서 Telegram 메시지 전송 성공",
        "",
        "Processed at: $(ConvertTo-CodexTelegramHtml $processedAt)"
    ) -join "`n"

    Invoke-CodexTelegramApi -Token $token -MethodName "sendMessage" -Payload @{
        chat_id = $targetChatId
        text = $message
        parse_mode = "HTML"
        disable_web_page_preview = $true
    } -TimeoutSec 15 | Out-Null
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Codex App Telegram Monitor 설정"
$form.StartPosition = "CenterScreen"
$form.Width = 700
$form.Height = 470
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$botToken = Add-Field -Form $form -Label "Telegram bot token" -Top 20 -Value (Get-ExistingValue -Key "TELEGRAM_BOT_TOKEN") -Password
$chatId = Add-Field -Form $form -Label "알림 chat ID" -Top 58 -Value (Get-ExistingValue -Key "TELEGRAM_CHAT_ID")
$personalChatId = Add-Field -Form $form -Label "개인 chat ID" -Top 96 -Value (Get-ExistingValue -Key "TELEGRAM_PERSONAL_CHAT_ID")
$allowedChats = Add-Field -Form $form -Label "알림 허용 채팅" -Top 134 -Value (Get-ExistingValue -Key "TELEGRAM_ALLOWED_CHAT_IDS")
$commandChats = Add-Field -Form $form -Label "명령 허용 채팅" -Top 172 -Value (Get-ExistingValue -Key "TELEGRAM_COMMAND_ALLOWED_CHAT_IDS")
$startChats = Add-Field -Form $form -Label "실행 허용 채팅" -Top 210 -Value (Get-ExistingValue -Key "TELEGRAM_START_ALLOWED_CHAT_IDS")
$deviceName = Add-Field -Form $form -Label "PC 표시 이름" -Top 248 -Value (Get-ExistingValue -Key "CODEX_DEVICE_NAME" -Default "auto")
$title = Add-Field -Form $form -Label "메시지 제목" -Top 286 -Value (Get-ExistingValue -Key "CODEX_MONITOR_TITLE" -Default "Codex app monitor test")

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = ".env 저장"
$saveButton.Left = 210
$saveButton.Top = 330
$saveButton.Width = 110
$form.Controls.Add($saveButton)

$detectChatButton = New-Object System.Windows.Forms.Button
$detectChatButton.Text = "chat ID 감지"
$detectChatButton.Left = 332
$detectChatButton.Top = 330
$detectChatButton.Width = 120
$form.Controls.Add($detectChatButton)

$testButton = New-Object System.Windows.Forms.Button
$testButton.Text = "테스트 전송"
$testButton.Left = 464
$testButton.Top = 330
$testButton.Width = 110
$form.Controls.Add($testButton)

$diagnoseButton = New-Object System.Windows.Forms.Button
$diagnoseButton.Text = "진단 실행"
$diagnoseButton.Left = 210
$diagnoseButton.Top = 370
$diagnoseButton.Width = 120
$form.Controls.Add($diagnoseButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "닫기"
$closeButton.Left = 342
$closeButton.Top = 370
$closeButton.Width = 110
$form.Controls.Add($closeButton)

$saveButton.Add_Click({
    try {
        if ([string]::IsNullOrWhiteSpace($botToken.Text)) {
            throw "Telegram bot token은 필수입니다."
        }
        if ([string]::IsNullOrWhiteSpace($chatId.Text) -and [string]::IsNullOrWhiteSpace($personalChatId.Text)) {
            throw "chat ID가 하나 이상 필요합니다."
        }

        $resolvedPersonalChatId = if ([string]::IsNullOrWhiteSpace($personalChatId.Text)) { $chatId.Text.Trim() } else { $personalChatId.Text.Trim() }
        $resolvedAllowedChats = if ([string]::IsNullOrWhiteSpace($allowedChats.Text)) { $resolvedPersonalChatId } else { $allowedChats.Text.Trim() }
        $resolvedCommandChats = if ([string]::IsNullOrWhiteSpace($commandChats.Text)) { $resolvedAllowedChats } else { $commandChats.Text.Trim() }
        $resolvedStartChats = if ([string]::IsNullOrWhiteSpace($startChats.Text)) { $resolvedCommandChats } else { $startChats.Text.Trim() }

        $lines = @(
            "TELEGRAM_BOT_TOKEN=$($botToken.Text.Trim())",
            "TELEGRAM_CHAT_ID=$($chatId.Text.Trim())",
            "TELEGRAM_PERSONAL_CHAT_ID=$resolvedPersonalChatId",
            "TELEGRAM_ALLOWED_CHAT_IDS=$resolvedAllowedChats",
            "TELEGRAM_COMMAND_ALLOWED_CHAT_IDS=$resolvedCommandChats",
            "TELEGRAM_START_ALLOWED_CHAT_IDS=$resolvedStartChats",
            "CODEX_MONITOR_TITLE=$($title.Text.Trim())",
            "CODEX_DEVICE_NAME=$($deviceName.Text.Trim())",
            "CODEX_APP_USER_MODEL_ID=$(Get-ExistingValue -Key "CODEX_APP_USER_MODEL_ID" -Default "auto")",
            "CODEX_PROCESS_PATH_PATTERN=$(Get-ExistingValue -Key "CODEX_PROCESS_PATH_PATTERN" -Default "auto")",
            "CODEX_LOG_MAX_BYTES=$(Get-ExistingValue -Key "CODEX_LOG_MAX_BYTES" -Default "1048576")",
            "CODEX_LOG_KEEP_FILES=$(Get-ExistingValue -Key "CODEX_LOG_KEEP_FILES" -Default "5")",
            "CODEX_HEARTBEAT_STALE_SECONDS=$(Get-ExistingValue -Key "CODEX_HEARTBEAT_STALE_SECONDS" -Default "120")"
        )

        $envDir = Split-Path -Parent $EnvFile
        if (!(Test-Path -LiteralPath $envDir)) {
            New-Item -ItemType Directory -Path $envDir -Force | Out-Null
        }
        Set-Content -LiteralPath $EnvFile -Encoding UTF8 -Value $lines
        Protect-CodexEnvFile -Path $EnvFile

        [System.Windows.Forms.MessageBox]::Show(".env를 저장하고 ACL을 보호했습니다.", "Codex App Telegram Monitor") | Out-Null
    } catch {
        Show-GuiException -ErrorRecord $_ -Title "저장 실패"
    }
})

$detectChatButton.Add_Click({
    try {
        $detectedChat = Get-LatestTelegramChatFromUpdates -Token (Get-GuiBotToken)
        Set-DetectedChatFields -DetectedChat $detectedChat
        $nameLine = if ([string]::IsNullOrWhiteSpace($detectedChat.Name)) { "" } else { "`n이름: $($detectedChat.Name)" }
        [System.Windows.Forms.MessageBox]::Show(
            "chat ID 감지 완료`nchat ID: $($detectedChat.Id)`nType: $($detectedChat.Type)$nameLine",
            "Codex App Telegram Monitor"
        ) | Out-Null
    } catch {
        Show-GuiException -ErrorRecord $_ -Title "chat ID 감지 실패"
    }
})

$testButton.Add_Click({
    try {
        Send-GuiTestMessage
        [System.Windows.Forms.MessageBox]::Show("테스트 메시지를 전송했습니다.", "Codex App Telegram Monitor") | Out-Null
    } catch {
        Show-GuiException -ErrorRecord $_ -Title "테스트 전송 실패"
    }
})

$diagnoseButton.Add_Click({
    try {
        Start-Process powershell.exe -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-NoExit",
            "-File", (Join-Path $PSScriptRoot "diagnose.ps1")
        )
    } catch {
        Show-GuiException -ErrorRecord $_ -Title "진단 실행 실패"
    }
})

$closeButton.Add_Click({
    $form.Close()
})

[void]$form.ShowDialog()
