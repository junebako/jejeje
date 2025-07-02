#!/bin/bash

# Claude Code スマート通知スクリプト
# transcript履歴を解析してタスクサマリーを生成

set -eo pipefail

# 標準入力からJSONを読み取り
INPUT=$(cat)

# デバッグ用にINPUTを保存（環境変数が設定されている場合）
if [ -n "${CLAUDE_HOOK_DEBUG:-}" ]; then
    DEBUG_DIR="${PWD}/claude_debug"
    mkdir -p "$DEBUG_DIR"
    TIMESTAMP_DEBUG=$(date '+%Y%m%d_%H%M%S')
    echo "$INPUT" > "${DEBUG_DIR}/hook_input_${TIMESTAMP_DEBUG}.json"
    echo "🐛 INPUT保存: ${DEBUG_DIR}/hook_input_${TIMESTAMP_DEBUG}.json" >&2
fi

# JSONから値を抽出（jqを使用してより堅牢に）
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")

# プロジェクト名を取得
PROJECT_DIR="${PWD##*/}"

# transcript履歴を解析
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] && [ -s "$TRANSCRIPT_PATH" ]; then
    # デバッグ用にtranscriptもコピー
    if [ -n "${CLAUDE_HOOK_DEBUG:-}" ]; then
        cp "$TRANSCRIPT_PATH" "${DEBUG_DIR}/transcript_${TIMESTAMP_DEBUG}.jsonl" 2>/dev/null || true
        echo "🐛 Transcript保存: ${DEBUG_DIR}/transcript_${TIMESTAMP_DEBUG}.jsonl" >&2
    fi
    # ツール使用回数を集計
    TOOL_NAMES=$(grep -o '"name":"[^"]*"' "$TRANSCRIPT_PATH" 2>/dev/null | cut -d'"' -f4 | sort | uniq -c | sort -nr || echo "")
    if [ -n "$TOOL_NAMES" ]; then
        TOOL_SUMMARY=$(echo "$TOOL_NAMES" | sed 's/^ *\([0-9]*\) \(.*\)/  \1回: \2/' | head -5)
    else
        TOOL_SUMMARY="  ツール使用なし"
    fi

    # メッセージ数をカウント（JSONLの行数）
    MESSAGE_COUNT=$(wc -l < "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")

    # 最初のユーザーメッセージを取得（初期タスクとして）
    FIRST_USER_LINE=$(grep '"role":"user"' "$TRANSCRIPT_PATH" 2>/dev/null | head -1 || echo "")
    if [ -n "$FIRST_USER_LINE" ]; then
        # jqを使用してより正確にJSONを解析
        FIRST_USER_MSG=$(echo "$FIRST_USER_LINE" | jq -r '.content // empty' 2>/dev/null || echo "")
    else
        FIRST_USER_MSG=""
    fi

    # 実行された操作を検出してサマリー作成
    FILE_OPS=""
    if grep -q '"name":"Read"' "$TRANSCRIPT_PATH" 2>/dev/null; then
        READ_COUNT=$(grep -c '"name":"Read"' "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
        [ "$READ_COUNT" -gt 0 ] && FILE_OPS="${FILE_OPS}📖${READ_COUNT}回読取 "
    fi
    if grep -q '"name":"Edit"' "$TRANSCRIPT_PATH" 2>/dev/null; then
        EDIT_COUNT=$(grep -c '"name":"Edit"' "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
        [ "$EDIT_COUNT" -gt 0 ] && FILE_OPS="${FILE_OPS}✏️${EDIT_COUNT}回編集 "
    fi
    if grep -q '"name":"Write"' "$TRANSCRIPT_PATH" 2>/dev/null; then
        WRITE_COUNT=$(grep -c '"name":"Write"' "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
        [ "$WRITE_COUNT" -gt 0 ] && FILE_OPS="${FILE_OPS}📝${WRITE_COUNT}回作成 "
    fi
    if grep -q '"name":"Bash"' "$TRANSCRIPT_PATH" 2>/dev/null; then
        BASH_COUNT=$(grep -c '"name":"Bash"' "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
        [ "$BASH_COUNT" -gt 0 ] && FILE_OPS="${FILE_OPS}⚡${BASH_COUNT}回実行 "
    fi

    # タスクサマリーを構築
    if [ -n "$FIRST_USER_MSG" ]; then
        if [ ${#FIRST_USER_MSG} -gt 120 ]; then
            SUMMARY="${FIRST_USER_MSG:0:120}..."
        else
            SUMMARY="$FIRST_USER_MSG"
        fi
    else
        SUMMARY="タスク実行"
    fi

    if [ -z "$TOOL_SUMMARY" ]; then
        TOOL_SUMMARY="  ツール使用なし"
    fi
else
    TOOL_SUMMARY="  履歴ファイルなし"
    MESSAGE_COUNT=0
    SUMMARY="不明"
    FILE_OPS=""
fi

# 現在時刻を取得
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Slack通知メッセージを作成（attachments形式）
# メイン色を決定（ファイル操作の有無で色分け）
if [ -n "$FILE_OPS" ]; then
    ATTACHMENT_COLOR="good"  # 緑色：作業完了
else
    ATTACHMENT_COLOR="#36a64f"  # 青緑：情報のみ
fi

# ツールサマリーを整形
FORMATTED_TOOLS=$(echo "$TOOL_SUMMARY" | sed 's/^  //' | tr '\n' ' | ' | sed 's/ | $//')

# attachments用のJSONを構築
ATTACHMENT_JSON="{
    \"color\": \"$ATTACHMENT_COLOR\",
    \"title\": \"🎯 Claude Codeセッション完了\",
    \"fields\": [
        {
            \"title\": \"📁 プロジェクト\",
            \"value\": \"$PROJECT_DIR\",
            \"short\": true
        },
        {
            \"title\": \"💬 メッセージ数\",
            \"value\": \"${MESSAGE_COUNT}件\",
            \"short\": true
        },
        {
            \"title\": \"📋 タスク内容\",
            \"value\": \"${SUMMARY:-"タスク実行"}\",
            \"short\": false
        }"

# ファイル操作がある場合は追加
if [ -n "$FILE_OPS" ]; then
    ATTACHMENT_JSON="$ATTACHMENT_JSON,
        {
            \"title\": \"📊 実行内容\",
            \"value\": \"$FILE_OPS\",
            \"short\": false
        }"
fi

# ツール使用情報を追加
ATTACHMENT_JSON="$ATTACHMENT_JSON,
        {
            \"title\": \"🔧 使用ツール\",
            \"value\": \"$FORMATTED_TOOLS\",
            \"short\": false
        }
    ],
    \"footer\": \"Claude Code Hook\",
    \"ts\": $(date +%s)
}"

# Slack通知を送信
if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
    # attachments形式でSlackに送信（jqを使用してより安全に）
    PAYLOAD=$(jq -n --argjson attachment "$ATTACHMENT_JSON" '{attachments: [$attachment]}')

    # curl でSlackに送信（エラーレスポンスも取得）
    TEMP_FILE=$(mktemp)
    HTTP_STATUS=$(curl -s -w "%{http_code}" -o "$TEMP_FILE" \
        -X POST \
        -H 'Content-type: application/json' \
        --data "$PAYLOAD" \
        "$SLACK_WEBHOOK_URL" 2>/dev/null || echo "000")

    if [ "$HTTP_STATUS" = "200" ]; then
        echo "✅ Slack通知送信成功" >&2
    else
        echo "❌ Slack通知送信失敗 (HTTP $HTTP_STATUS)" >&2
        if [ -s "$TEMP_FILE" ] && [ -n "${CLAUDE_HOOK_DEBUG:-}" ]; then
            echo "🐛 エラーレスポンス: $(cat "$TEMP_FILE")" >&2
        fi
    fi
    rm -f "$TEMP_FILE" 2>/dev/null || true
else
    echo "ℹ️  SLACK_WEBHOOK_URL が設定されていません" >&2
fi

# デバッグ情報（環境変数 CLAUDE_HOOK_DEBUG が設定されている場合）
if [ -n "${CLAUDE_HOOK_DEBUG:-}" ]; then
    echo "🐛 デバッグ情報:" >&2
    echo "  SESSION_ID: ${SESSION_ID:-"(取得失敗)"}" >&2
    echo "  TRANSCRIPT_PATH: ${TRANSCRIPT_PATH:-"(取得失敗)"}" >&2
    echo "  MESSAGE_COUNT: ${MESSAGE_COUNT:-"0"}" >&2
    echo "  PROJECT_DIR: $PROJECT_DIR" >&2
    echo "  FIRST_USER_MSG: ${FIRST_USER_MSG:-"(取得失敗)"}" >&2
    echo "  FILE_OPS: ${FILE_OPS:-"(なし)"}" >&2
fi
