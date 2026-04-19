# Claude Code Stats Reporter - Windows セットアップ
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$installDir = Join-Path $env:USERPROFILE ".claude-stats-reporter"
$taskName = "ClaudeCodeStatsReporter"

Write-Host "=== Claude Code Stats Reporter セットアップ ===" -ForegroundColor Cyan
Write-Host ""

# 既存インストールの確認
if (Test-Path $installDir) {
    Write-Host "既存のインストールが見つかりました: $installDir"
    $overwrite = Read-Host "上書きしますか？ (y/N)"
    if ($overwrite -ne "y" -and $overwrite -ne "Y") {
        Write-Host "中止しました。"
        exit 0
    }
}

# USERNAME の入力
$inputUsername = Read-Host "表示名を入力してください (例: taro)"
if ([string]::IsNullOrWhiteSpace($inputUsername)) {
    Write-Host "エラー: 表示名は必須です。" -ForegroundColor Red
    exit 1
}

# ENDPOINT_URL の入力
Write-Host ""
Write-Host "GAS のウェブアプリ URL を入力してください。"
Write-Host "（Apps Script > デプロイ > ウェブアプリ で取得できます）"
$inputEndpoint = Read-Host "URL"
if ([string]::IsNullOrWhiteSpace($inputEndpoint)) {
    Write-Host "エラー: URL は必須です。" -ForegroundColor Red
    exit 1
}

# インストールディレクトリ作成
New-Item -ItemType Directory -Path $installDir -Force | Out-Null

# config.ps1 作成
$configContent = @"
`$USERNAME = "$inputUsername"
`$ENDPOINT_URL = "$inputEndpoint"
"@
$configContent | Out-File -FilePath (Join-Path $installDir "config.ps1") -Encoding UTF8

# report.ps1 をコピー
Copy-Item -Path (Join-Path $scriptDir "report.ps1") -Destination (Join-Path $installDir "report.ps1") -Force

Write-Host ""
Write-Host "ファイルを配置しました: $installDir"

# タスクスケジューラに登録
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$installDir\report.ps1`""

$trigger = New-ScheduledTaskTrigger -Daily -At "09:30"

$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "Claude Code の利用状況を GAS に送信" | Out-Null

Write-Host "タスクスケジューラに登録しました（毎日 9:30 に自動実行）"

Write-Host ""
Write-Host "=== セットアップ完了 ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "手動で実行する場合:"
Write-Host "  powershell -File $installDir\report.ps1"
Write-Host ""
Write-Host "ログの確認:"
Write-Host "  Get-Content $installDir\last_run.log"
