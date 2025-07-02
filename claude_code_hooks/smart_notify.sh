#!/bin/bash

# Claude Code スマート通知スクリプト
# transcript履歴を解析してタスクサマリーを生成

# 標準入力からJSONを読み取り
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | grep -o '"transcript_path":"[^"]*"' | cut -d'"' -f4)
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)

# プロジェクト名を取得
PROJECT_DIR="${PWD##*/}"

# transcript履歴からツール使用回数を集計
if [ -f "$TRANSCRIPT_PATH" ]; then
    TOOL_SUMMARY=$(grep -o '"name":"[^"]*"' "$TRANSCRIPT_PATH" | cut -d'"' -f4 | sort | uniq -c | head -5)
    TOTAL_LINES=$(wc -l < "$TRANSCRIPT_PATH")

    # サマリーを取得（最初の行）
    SUMMARY=$(head -1 "$TRANSCRIPT_PATH" | grep -o '"summary":"[^"]*"' | cut -d'"' -f4)
else
    TOOL_SUMMARY="履歴ファイルなし"
    TOTAL_LINES=0
    SUMMARY="不明"
fi

# Slack通知メッセージを作成
MESSAGE="🎯 Claude Codeセッション完了

📁 プロジェクト: $PROJECT_DIR
📋 タスク: ${SUMMARY:-"タスク実行"}
📊 操作数: ${TOTAL_LINES}行

🔧 使用ツール:
$TOOL_SUMMARY"

# Slack通知を送信
if [ -n "$SLACK_WEBHOOK_URL" ]; then
    # JSONエスケープ用の処理
    ESCAPED_MESSAGE=$(echo "$MESSAGE" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

    curl -s -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"$ESCAPED_MESSAGE\"}" \
        "$SLACK_WEBHOOK_URL"
fi
