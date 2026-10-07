#!/bin/bash
# autopilot の全体管理 Issue(ダッシュボード)を扱う。
#
# 状態の正は各チケットのラベル・PR のまま(autopilot-next.sh が毎回そこから判定する)。
# この Issue は「表示」と「操作(一時停止)」と「人手が要る停止の通知先」で、状態を二重に持たない。
# 本文は毎回判定結果から再生成するので、手で書き換えても一時停止のチェック以外は上書きされる。
#
#   ... | bash .claude/scripts/autopilot-board.sh sync [--status TEXT]
#       標準入力の判定 JSON(autopilot-next.sh の出力)で本文を更新する。無ければ作る。
#       内容が前回と同じなら書き込まない(5 分ごとの再判定で編集履歴を埋めない)
#   bash .claude/scripts/autopilot-board.sh paused   # 一時停止中なら exit 0、そうでなければ 1
#   bash .claude/scripts/autopilot-board.sh notify TEXT
#       全体管理 Issue にコメントし、AUTOPILOT_NOTIFY_CMD があれば TEXT を引数に実行する
#       (例: AUTOPILOT_NOTIFY_CMD='notify-send autopilot' / ntfy・Slack への curl を包んだスクリプト)
#   bash .claude/scripts/autopilot-board.sh url      # 全体管理 Issue の URL を出す
#   ... | bash .claude/scripts/autopilot-board.sh render [STATUS]  # GitHub に触らず本文だけ出す(確認用)
#
# 全体管理 Issue は `autopilot` ラベルの open Issue(番号が最小のもの)。`ticket` ラベルは付けない
# (付けると判定にチケットとして数えられる)。
#
# 終了コード: 0 成功 / 1 paused で「停止中でない」 / 2 取得・更新の失敗
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 2

die() { echo "autopilot-board.sh: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq が見つからない"
REPO=""
need_gh() {
  command -v gh >/dev/null 2>&1 || die "gh が見つからない"
  # shellcheck source=lib-github.sh
  . .claude/scripts/lib-github.sh 2>/dev/null || die "lib-github.sh が読めない"
  REPO="$(gh_resolve_repo)" || die "リポジトリを特定できない(AUTOPILOT_REPO=owner/repo で指定できる)"
}

LABEL=autopilot
MARK='<!-- autopilot-board -->'
PAUSE_OFF='- [ ] **一時停止**(チェックすると次の周から新規着手と PR 修復を止める。外すと再開)'
PAUSE_ON='- [x] **一時停止**(チェックすると次の周から新規着手と PR 修復を止める。外すと再開)'

# 全体管理 Issue の {number, body, html_url} を返す(無ければ空)
find_board() {
  gh api "repos/$REPO/issues?labels=$LABEL&state=open&per_page=100" \
    --jq '[.[] | select(.pull_request == null)] | sort_by(.number) | .[0] // empty | {number, body, html_url}' 2>/dev/null
}

is_paused() { printf '%s' "$1" | grep -qiE '^- \[x\] \*\*一時停止\*\*'; }

# 「最終更新」行を除いた本文(変化の有無の比較用)
strip_stamp() { printf '%s' "$1" | grep -v '^\*\*最終更新:\*\*'; }

render() { # $1=判定 JSON $2=状態テキスト $3=一時停止中か(1/0)
  local pause_line="$PAUSE_OFF"
  [ "$3" = 1 ] && pause_line="$PAUSE_ON"
  printf '%s' "$1" | jq -r --arg mark "$MARK" --arg status "$2" --arg pause "$pause_line" \
    --arg now "$(date '+%Y-%m-%d %H:%M')" '
    def esc: gsub("\\|"; "\\|") | gsub("\n"; " ");
    def row($icon; $n; $title; $state): "| \($icon) | #\($n) | \($title | esc) | \($state) |";
    . as $j
    | ($j.attention | map({key: (.issues[] | tostring), value: .}) | from_entries) as $att
    | ($j.prs | map({key: (.issues[] | tostring), value: .}) | from_entries) as $pr
    | ($j.ready | map(.number)) as $ready
    | ($j.blocked | map({key: (.number | tostring), value: .waitingOn}) | from_entries) as $blk
    | [
        $mark,
        "## 🤖 Autopilot",
        "",
        "**状態:** \($status)",
        "**最終更新:** \($now)",
        "**モード:** \($j.mode) / 同時進行 \($j.inFlight | length)/\($j.maxInFlight) / 残り \($j.openTickets) 件・完了 \($j.closedTickets | length) 件",
        "",
        "### 操作",
        "",
        $pause,
        "",
        "### チケット",
        "",
        "| | # | タイトル | 状態 |",
        "|---|---|---|---|",
        ($j.tickets | sort_by(.number) | .[] | .number as $n | ($n | tostring) as $k
          | if $att[$k] then row("🔧"; .number; .title; "PR #\($att[$k].pr) 要対応(\($att[$k].reasons | join(", ")))")
            elif $pr[$k] then row("👀"; .number; .title; "PR #\($pr[$k].number) " + (if $pr[$k].draft then "draft(ready 待ち)" else "レビュー待ち" end))
            elif ($j.stalled | index($n)) then row("🚧"; .number; .title; "実装中(PR 未作成)")
            elif ($ready | index($n)) then row("▶️"; .number; .title; "着手可能")
            elif (($j.manual // []) | index($n)) then row("🙋"; .number; .title; "手動で回す(autopilot:manual)")
            elif $blk[$k] then row("⏳"; .number; .title; "依存待ち: " + ($blk[$k] | map("#\(.)") | join(", ")))
            else row("・"; .number; .title; "—") end),
        "",
        (if ($j.closedTickets | length) > 0 then
          "<details><summary>✅ 完了 \($j.closedTickets | length) 件</summary>\n\n"
          + ($j.closedTickets | sort_by(.number) | map("- #\(.number) \(.title | esc)") | join("\n"))
          + "\n\n</details>"
         else empty end),
        "",
        "---",
        "_`autopilot-loop.sh` / `/autopilot` が判定のたびに自動更新します。手で変えてよいのは「一時停止」のチェックだけです(他は次の更新で上書きされます)。人手が要る停止はこの Issue にコメントされます。_"
      ] | join("\n")'
}

CMD="${1:-}"
shift || true
case "$CMD" in
  sync | paused | notify | url) need_gh ;;
esac
case "$CMD" in
  render) # GitHub に触らず本文だけ出す(確認・テスト用): ... | autopilot-board.sh render [STATUS]
    J="$(cat)"
    render "$J" "${1:-🟢 実行中}" 0
    ;;
  sync)
    STATUS="🟢 実行中"
    while [ $# -gt 0 ]; do
      case "$1" in
        --status) STATUS="${2:-}"; shift ;;
        *) die "不明な引数: $1" ;;
      esac
      shift
    done
    J="$(cat)"
    printf '%s' "$J" | jq -e '.action' >/dev/null 2>&1 || die "標準入力が判定 JSON でない"
    B="$(find_board)"
    if [ -z "$B" ]; then
      BODY="$(render "$J" "$STATUS" 0)" || die "本文の生成に失敗した"
      # ラベルが無ければ作る(既にあれば 422 になるだけなので無視する)
      gh api "repos/$REPO/labels" -f name="$LABEL" -f color=5319e7 -f description="autopilot の全体管理 Issue" >/dev/null 2>&1 || true
      jq -n --arg t "🤖 Autopilot ダッシュボード" --arg b "$BODY" --arg l "$LABEL" '{title: $t, body: $b, labels: [$l]}' |
        gh api "repos/$REPO/issues" --input - --jq .html_url || die "全体管理 Issue を作れない"
      exit 0
    fi
    NUM="$(printf '%s' "$B" | jq -r .number)"
    OLD="$(printf '%s' "$B" | jq -r '.body // ""')"
    P=0
    is_paused "$OLD" && P=1
    BODY="$(render "$J" "$STATUS" "$P")" || die "本文の生成に失敗した"
    if [ "$(strip_stamp "$OLD")" != "$(strip_stamp "$BODY")" ]; then
      jq -n --arg b "$BODY" '{body: $b}' | gh api -X PATCH "repos/$REPO/issues/$NUM" --input - >/dev/null ||
        die "全体管理 Issue を更新できない"
    fi
    ;;
  paused)
    B="$(find_board)"
    [ -n "$B" ] || exit 1
    is_paused "$(printf '%s' "$B" | jq -r '.body // ""')" && exit 0
    exit 1
    ;;
  notify)
    MSG="${*:-}"
    [ -n "$MSG" ] || die "notify にはメッセージが要る"
    if [ -n "${AUTOPILOT_NOTIFY_CMD:-}" ]; then
      # shellcheck disable=SC2086 # 利用者が書いたコマンド行を意図的に単語分割する
      ${AUTOPILOT_NOTIFY_CMD} "$MSG" >/dev/null 2>&1 || echo "autopilot-board.sh: AUTOPILOT_NOTIFY_CMD が失敗した" >&2
    fi
    B="$(find_board)"
    [ -n "$B" ] || exit 0 # 全体管理 Issue がまだ無い(初回の判定前に止まった)なら通知コマンドだけ
    NUM="$(printf '%s' "$B" | jq -r .number)"
    jq -n --arg b "$MSG" '{body: $b}' | gh api "repos/$REPO/issues/$NUM/comments" --input - >/dev/null ||
      die "コメントを投稿できない"
    ;;
  url)
    B="$(find_board)"
    [ -n "$B" ] || exit 1
    printf '%s' "$B" | jq -r .html_url
    ;;
  -h | --help | "") sed -n '2,23p' "$0" ;;
  *) die "不明なサブコマンド: $CMD" ;;
esac
