#!/bin/bash
# Claude Code Stats Reporter - macOS/Linux セットアップ
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.claude-stats-reporter"
PLIST_NAME="com.llm-monitor.claude-stats"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"

echo "=== Claude Code Stats Reporter セットアップ ==="
echo ""

# 既存インストールの確認
if [[ -d "$INSTALL_DIR" ]]; then
    echo "既存のインストールが見つかりました: $INSTALL_DIR"
    read -rp "上書きしますか？ (y/N): " overwrite
    if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
        echo "中止しました。"
        exit 0
    fi
fi

# USERNAME の入力
read -rp "表示名を入力してください (例: taro): " input_username
if [[ -z "$input_username" ]]; then
    echo "エラー: 表示名は必須です。"
    exit 1
fi

# ENDPOINT_URL の入力
echo ""
echo "GAS のウェブアプリ URL を入力してください。"
echo "（Apps Script > デプロイ > ウェブアプリ で取得できます）"
read -rp "URL: " input_endpoint
if [[ -z "$input_endpoint" ]]; then
    echo "エラー: URL は必須です。"
    exit 1
fi

# インストールディレクトリ作成
mkdir -p "$INSTALL_DIR"

# config 作成
cat > "$INSTALL_DIR/config" << EOF
USERNAME="$input_username"
ENDPOINT_URL="$input_endpoint"
EOF

# report.sh をコピー
cp "$SCRIPT_DIR/report.sh" "$INSTALL_DIR/report.sh"
chmod +x "$INSTALL_DIR/report.sh"

echo ""
echo "ファイルを配置しました: $INSTALL_DIR"

# macOS の場合のみ LaunchAgent を設定
if [[ "$(uname)" == "Darwin" ]]; then
    # 既存の LaunchAgent をアンロード
    if launchctl list | grep -q "$PLIST_NAME" 2>/dev/null; then
        launchctl unload "$PLIST_PATH" 2>/dev/null || true
    fi

    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${INSTALL_DIR}/report.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>9</integer>
        <key>Minute</key>
        <integer>30</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>${INSTALL_DIR}/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${INSTALL_DIR}/stderr.log</string>
</dict>
</plist>
PLIST

    launchctl load "$PLIST_PATH"
    echo "LaunchAgent を登録しました（毎日 9:30 に自動実行）"
fi

echo ""
echo "=== セットアップ完了 ==="
echo ""
echo "手動で実行する場合:"
echo "  bash $INSTALL_DIR/report.sh"
echo ""
echo "ログの確認:"
echo "  cat $INSTALL_DIR/last_run.log"
