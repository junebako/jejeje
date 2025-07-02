#!/bin/bash

# Claude Code スマート通知スクリプト
# transcript履歴を解析してタスクサマリーを生成

set -euo pipefail

# 標準入力からJSONを読み取り
INPUT=$(cat)

# JSONから値を抽出
TRANSCRIPT_PATH=$(echo "$INPUT" | grep -o '"transcript_path":"[^"]*"' | cut -d'"' -f4)
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)

# プロジェクト名を取得
PROJECT_DIR="${PWD##*/}"

# transcript履歴を解析
if [ -f "$TRANSCRIPT_PATH" ] && [ -s "$TRANSCRIPT_PATH" ]; then
    # ツール使用回数を集計
    TOOL_SUMMARY=$(grep -o '"name":"[^"]*"' "$TRANSCRIPT_PATH" | cut -d'"' -f4 | sort | uniq -c | sort -nr | head -5 | sed 's/^ *\([0-9]*\) \(.*\)/  \1回: \2/')

    # メッセージ数をカウント（"messages"配列の要素数を概算）
    MESSAGE_COUNT=$(grep -c '"role":' "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")

    # 最後のユーザーメッセージを取得（タスクの概要として）
    SUMMARY=$(grep '"role":"user"' "$TRANSCRIPT_PATH" | tail -1 | grep -o '"content":"[^"]*"' | cut -d'"' -f4 | head -c 100)
    if [ ${#SUMMARY} -eq 100 ]; then
        SUMMARY="${SUMMARY}..."
    fi

    if [ -z "$TOOL_SUMMARY" ]; then
        TOOL_SUMMARY="  ツール使用なし"
    fi
    if [ -z "$SUMMARY" ]; then
        SUMMARY="タスク実行"
    fi
else
    TOOL_SUMMARY="  履歴ファイルなし"
    MESSAGE_COUNT=0
    SUMMARY="不明"
fi

# 現在時刻を取得
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Slack通知メッセージを作成
MESSAGE="🎯 Claude Codeセッション完了

📁 プロジェクト: $PROJECT_DIR
📋 タスク: ${SUMMARY:-"タスク実行"}
💬 メッセージ数: ${MESSAGE_COUNT}件
🕐 完了時刻: $TIMESTAMP

🔧 使用ツール:
$TOOL_SUMMARY"

# Slack通知を送信
if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
    # JSONエスケープ用の処理
    ESCAPED_MESSAGE=$(echo "$MESSAGE" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

    # curl でSlackに送信
    HTTP_STATUS=$(curl -s -w "%{http_code}" -o /dev/null \
        -X POST \
        -H 'Content-type: application/json' \
        --data "{\"text\":\"$ESCAPED_MESSAGE\"}" \
        "$SLACK_WEBHOOK_URL")

    if [ "$HTTP_STATUS" = "200" ]; then
        echo "✅ Slack通知送信成功" >&2
    else
        echo "❌ Slack通知送信失敗 (HTTP $HTTP_STATUS)" >&2
    fi
else
    echo "ℹ️  SLACK_WEBHOOK_URL が設定されていません" >&2
fi

# デバッグ情報（環境変数 CLAUDE_HOOK_DEBUG が設定されている場合）
if [ -n "${CLAUDE_HOOK_DEBUG:-}" ]; then
    echo "🐛 デバッグ情報:" >&2
    echo "  SESSION_ID: $SESSION_ID" >&2
    echo "  TRANSCRIPT_PATH: $TRANSCRIPT_PATH" >&2
    echo "  MESSAGE_COUNT: $MESSAGE_COUNT" >&2
fi
