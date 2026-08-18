#!/bin/bash
# PostToolUse(Edit|Write) async hook: TS/JS ファイルの編集後に lint と型チェックを走らせる。
# 連続編集でプロジェクト全体の eslint / tsc が並列に積み重ならないよう、
# 実行中はロックディレクトリで多重起動をスキップする(結果は先行プロセスが返す)。
set -uo pipefail

f="$(jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null)"
case "$f" in
  *.ts | *.tsx | *.js | *.mjs | *.cjs) ;;
  *) exit 0 ;;
esac

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

LOCK=".claude/.lint-on-edit.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

npm run --silent lint 2>&1 | tail -20
npm run --silent typecheck 2>&1 | tail -20
exit 0
