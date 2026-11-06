#!/bin/bash
# project-sync.sh の動作確認。一時ディレクトリの中で完結する(gh・ネットワーク不要)。
#
# 検証するのは **GitHub に触らない部分**:
#   - Status の決定(--resolve-status)。board 同期の判断の実体はここに集約してある
#   - 設定の読み込み(ラベル名の差し替え・壊れた JSON)
#   - 引数と未設定時の扱い(PROJECT_URL が無ければ何もせず exit 0)
# 実ボードへの反映(GraphQL)はトークンと board が要るので CI では検証しない。
#
#   bash .claude/scripts/test-project-sync.sh
#     → 失敗した検査を 1 行ずつ出し、1 件でもあれば exit 1
set -uo pipefail

SYNC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/project-sync.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" && mkdir -p .claude || exit 1
export CLAUDE_PROJECT_DIR="$WORK"
CONF="$WORK/.claude/project-sync.json"

FAILS=0

# 説明 期待する status  issue の JSON  [open PR 一覧の JSON]
status_is() {
  local desc="$1" want="$2" issue="$3" prs="${4:-}" got
  printf '%s' "$issue" >"$WORK/issue.json"
  if [ -n "$prs" ]; then
    printf '%s' "$prs" >"$WORK/prs.json"
    got="$(LC_ALL=C bash "$SYNC" --resolve-status --issue "$WORK/issue.json" --prs "$WORK/prs.json" 2>/dev/null)"
  else
    got="$(LC_ALL=C bash "$SYNC" --resolve-status --issue "$WORK/issue.json" 2>/dev/null)"
  fi
  [ "$got" = "$want" ] || {
    echo "NG: $desc(期待 $want / 実際 ${got:-<空>})"
    FAILS=1
  }
}
# 説明 期待する終了コード 引数...
expect_rc() {
  local desc="$1" want="$2"
  shift 2
  LC_ALL=C bash "$SYNC" "$@" >/dev/null 2>&1
  local rc=$?
  [ "$rc" = "$want" ] || {
    echo "NG: $desc(期待 exit $want / 実際 exit $rc)"
    FAILS=1
  }
}

OPEN_PLAIN='{"number":7,"state":"open","labels":[]}'
OPEN_WIP='{"number":7,"state":"open","labels":[{"name":"ticket"},{"name":"in-progress"}]}'
OPEN_WIP_STR='{"number":7,"state":"open","labels":["ticket","in-progress"]}'
CLOSED='{"number":7,"state":"closed","labels":[{"name":"ticket"},{"name":"in-progress"}]}'

pr() { # $1=本文 $2=head のリポジトリ $3=state  → open PR 一覧(配列)の JSON
  printf '[{"number":10,"state":"%s","body":"%s","head":{"repo":{"full_name":"%s"}},"base":{"repo":{"full_name":"o/r"}}}]' \
    "$3" "$1" "$2"
}

# --- Status の 4 分岐 ---
status_is "ラベルも PR も無い → todo" todo "$OPEN_PLAIN"
status_is "in-progress ラベル(オブジェクト形) → inProgress" inProgress "$OPEN_WIP"
status_is "in-progress ラベル(文字列形) → inProgress" inProgress "$OPEN_WIP_STR"
status_is "closed は PR やラベルより優先 → done" "done" "$CLOSED" "$(pr "Closes #7" o/r open)" # done はクォート必須
status_is "紐づく open PR → inReview" inReview "$OPEN_WIP" "$(pr "Closes #7" o/r open)"

# --- Closes の書き方 ---
status_is "fixes(小文字・複数形)も拾う" inReview "$OPEN_PLAIN" "$(pr "fixes #7" o/r open)"
status_is "Resolved: も拾う" inReview "$OPEN_PLAIN" "$(pr "Resolved: #7" o/r open)"
status_is "本文の途中にあっても拾う" inReview "$OPEN_PLAIN" "$(pr "作業内容\\n\\nCloses #7\\n" o/r open)"
status_is "別の Issue を閉じる PR は紐づかない" todo "$OPEN_PLAIN" "$(pr "Closes #8" o/r open)"
status_is "#7 を含むだけ(close 系の語が無い)は紐づかない" todo "$OPEN_PLAIN" "$(pr "see #7" o/r open)"

# --- 信頼の境界 ---
status_is "fork の PR は紐づけない(ラベルも無ければ todo)" todo "$OPEN_PLAIN" "$(pr "Closes #7" x/r open)"
status_is "fork の PR は紐づけない(ラベルがあれば inProgress)" inProgress "$OPEN_WIP" "$(pr "Closes #7" x/r open)"
status_is "closed の PR は紐づけない" inProgress "$OPEN_WIP" "$(pr "Closes #7" o/r closed)"
status_is "PR 一覧が空でも落ちない" todo "$OPEN_PLAIN" "[]"

# --- 設定 ---
printf '{"inProgressLabel":"wip"}\n' >"$CONF"
status_is "inProgressLabel を差し替えられる" inProgress '{"number":7,"state":"open","labels":["wip"]}' ""
status_is "差し替えると既定のラベルは効かない" todo "$OPEN_WIP_STR" ""

printf '{ これは JSON ではない }\n' >"$CONF"
expect_rc "壊れた設定は exit 2" 2 --resolve-status --issue "$WORK/issue.json"
rm -f "$CONF"

# --- 引数と未設定時 ---
expect_rc "サブコマンド無しは exit 2" 2
expect_rc "不明な引数は exit 2" 2 --wat
expect_rc "--resolve-status に --issue が無ければ exit 2" 2 --resolve-status
expect_rc "存在しないフィクスチャは exit 2" 2 --resolve-status --issue "$WORK/none.json"
expect_rc "PROJECT_URL 未設定なら何もせず exit 0" 0 sync-issue 1
export PROJECT_URL="https://example.com/not-a-project"
expect_rc "PROJECT_URL の形が違えば exit 2" 2 sync-issue 1
unset PROJECT_URL

if [ "$FAILS" -eq 0 ]; then echo "project-sync: all checks passed"; fi
exit "$FAILS"
