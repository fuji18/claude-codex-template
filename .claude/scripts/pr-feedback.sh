#!/bin/bash
# PR のレビュー・コメントのうち、**信頼できる書き手のものだけ**を JSON 1 個で返す(読み取り専用)。
#
# /fix-pr は無人で push まで進む経路なので、PR 上の文章がそのまま指示として読まれると
# プロンプトインジェクションの入口になる。公開リポジトリでは誰でも PR にコメント・レビューを書けるため、
# 散文の「従うのは書き込み権限のある人だけ」に頼らず、**信頼できない書き手の本文はそもそも渡さない**。
#
# 信頼する書き手:
#   - author_association が OWNER / MEMBER / COLLABORATOR(= 書き込み権限相当)
#   - .claude/autopilot.json の trustedBots に載った Bot(既定: claude[bot] / github-actions[bot])。
#     GitHub App はインストールされたリポジトリにしか書けないため、Bot 種別 + 名前の一致で足りる
# 信頼しない書き手の本文は出さず、件数と書き手の名前だけを出す(人間が気づけるように)。
#
# GitHub へは REST(gh api)だけで触る(Claude Code on the web では GraphQL が 403 になるため)。
# REST はスレッドの解決状態を返さないので、レビューコメントは in_reply_to でスレッドを辿る。
#
# 使い方:
#   bash .claude/scripts/pr-feedback.sh [PR番号]
#
# 終了コード: 0 = 成功 / 2 = 引数・取得・解析の失敗(取得に失敗したまま「指摘なし」に倒さない)
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 2

die() { echo "pr-feedback.sh: $*" >&2; exit 2; }

PR="${1:-}"
case "$PR" in '' | *[!0-9]*) die "PR 番号を数字で渡す(例: bash .claude/scripts/pr-feedback.sh 42)" ;; esac

command -v jq >/dev/null 2>&1 || die "jq が見つからない"
command -v gh >/dev/null 2>&1 || die "gh が見つからない"
# shellcheck source=lib-github.sh
. .claude/scripts/lib-github.sh 2>/dev/null || die "lib-github.sh が読めない"
REPO="$(gh_resolve_repo)" || die "リポジトリを特定できない(AUTOPILOT_REPO=owner/repo で指定できる)"

CONF=.claude/autopilot.json
BOTS='["claude[bot]","github-actions[bot]"]'
if [ -f "$CONF" ] && jq -e '.trustedBots | type == "array"' "$CONF" >/dev/null 2>&1; then
  BOTS="$(jq -c '.trustedBots' "$CONF")"
fi

TMP="$(mktemp -d)" || die "一時ディレクトリを作れない"
trap 'rm -rf "$TMP"' EXIT

fetch() { # $1=パス $2=出力名
  gh api --paginate "repos/$REPO/$1?per_page=100" >"$TMP/$2.pages" 2>/dev/null || die "取得できない: $1"
  jq -s 'add // []' "$TMP/$2.pages" >"$TMP/$2.json" 2>/dev/null || die "JSON でない: $1"
}
fetch "pulls/$PR/reviews" reviews
fetch "pulls/$PR/comments" review_comments
fetch "issues/$PR/comments" comments

jq -n --argjson bots "$BOTS" \
  --slurpfile r "$TMP/reviews.json" --slurpfile rc "$TMP/review_comments.json" --slurpfile c "$TMP/comments.json" '
  def trusted:
    ((.author_association // "NONE") as $a | ["OWNER", "MEMBER", "COLLABORATOR"] | index($a) != null)
    or ((.user.type // "") == "Bot" and ((.user.login // "") as $l | $bots | index($l) != null));
  def who: {user: (.user.login // null), association: (.author_association // null)};

  ($r[0] | map(select(.state != "PENDING"))) as $reviews
  | {
      pr: '"$PR"',
      reviews: ($reviews | map(select(trusted) | who + {id, state, commit_id, body: (.body // "")})),
      reviewComments: ($rc[0] | map(select(trusted)
        | who + {id, in_reply_to_id, path, line: (.line // .original_line), commit_id, body: (.body // "")})),
      comments: ($c[0] | map(select(trusted) | who + {id, body: (.body // "")})),
      untrusted: (($reviews + $rc[0] + $c[0]) | map(select(trusted | not)) as $u
        | {count: ($u | length), users: ($u | map(.user.login // "(不明)") | unique)})
    }' || die "整形に失敗した"
