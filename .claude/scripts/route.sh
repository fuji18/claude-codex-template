#!/bin/bash
# 工程ごとの担当AI(実装・レビュー)を決める唯一の判定経路。
#
#   bash .claude/scripts/route.sh <stage> [--issue N] [--set <工程>=<担当>]... [--explain]
#     stage   : implement(実装)| review(レビュー)
#     stdout  : codex | claude:sonnet | claude:opus | claude:haiku のいずれか 1 行
#     --explain を付けると、どの指定から決まったかを stderr に 1 行出す
#
# 優先順位(上が勝つ):
#   1. --set(コマンドの記載。例: /next-ticket 12 実装=sonnet レビュー=codex)
#   2. Issue 本文の「## 担当AI」節のチェック(- [x] 実装: Codex など)
#   3. Issue の delegate:codex ラベル(実装だけ。旧来の指定方法)
#   4. .claude/routing.json(プロジェクトの既定)
#   5. 既定値(実装 = codex / レビュー = sonnet)
#
# レビューの auto は「実装したのとは別のベンダー」に解決する(Codex が実装したら
# Claude Sonnet、Claude が実装したら Codex)。同じベンダーの自己レビューは第二意見に
# ならないため(.claude/rules/lead/review-policy.md)。
#
# このスクリプトは「誰に任せるか」を決めるだけで、委託はしない。Codex が使えない
# (delegate-codex.sh が exit 3)ときに Claude へ落とすのは、従来どおり呼び出し側の役目。
# 委託禁止領域に触れるかどうかも、従来どおり delegate-codex.sh の入口・出口検査が見る。
#
# 終了コード: 0 = 決定 / 2 = 指定が不正(未知の担当名・同じ工程に 2 つチェック)/ 64 = 使い方の誤り
#
# 別の入力手段(クラウドで gh が使えないとき等): --issue-body-file <path> と
# --issue-labels <a,b,...> で Issue の本文とラベルを直接渡せる。
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" 2>/dev/null || true

usage() {
  echo "使い方: route.sh <implement|review> [--issue N] [--set 工程=担当]... [--explain]" >&2
  exit 64
}

STAGE=""
ISSUE=""
BODY_FILE=""
LABELS=""
EXPLAIN=0
SETS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --issue-body-file) BODY_FILE="${2:-}"; shift 2 ;;
    --issue-labels) LABELS="${2:-}"; shift 2 ;;
    --set) SETS+=("${2:-}"); shift 2 ;;
    --explain) EXPLAIN=1; shift ;;
    -*) usage ;;
    *) [ -z "$STAGE" ] && STAGE="$1" || usage; shift ;;
  esac
done

# 工程名の正規化(日本語・略記を受ける)
norm_stage() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    implement | impl | 実装) echo implement ;;
    review | レビュー) echo review ;;
    *) echo "" ;;
  esac
}
STAGE="$(norm_stage "$STAGE")"
[ -n "$STAGE" ] || usage

# 担当名の正規化。不正なら空を返す
norm_value() {
  local v
  v="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:space:]]+/ /g')"
  case "$v" in
    codex) echo codex ;;
    sonnet | claude:sonnet | "claude sonnet" | claude) echo claude:sonnet ;;
    opus | claude:opus | "claude opus") echo claude:opus ;;
    haiku | claude:haiku | "claude haiku") echo claude:haiku ;;
    auto | 自動) echo auto ;;
    *) echo "" ;;
  esac
}

die_invalid() { echo "❌ $1" >&2; exit 2; }

# --- 1. --set ---
from_set() { # $1=stage → 値(未指定なら空)
  local s k v out=""
  for s in "${SETS[@]+"${SETS[@]}"}"; do
    k="${s%%=*}"; v="${s#*=}"
    [ "$s" = "$k" ] && die_invalid "--set の形式が不正: '$s'(工程=担当 の形で指定する)"
    [ "$(norm_stage "$k")" = "$1" ] || continue
    out="$(norm_value "$v")"
    [ -n "$out" ] || die_invalid "担当名が不正: '$v'(codex / sonnet / opus / haiku / auto)"
  done
  printf '%s' "$out"
}

# --- 2/3. Issue ---
ISSUE_BODY=""
ISSUE_LABELS=""
load_issue() {
  if [ -n "$BODY_FILE" ]; then
    ISSUE_BODY="$(cat "$BODY_FILE" 2>/dev/null || true)"
    ISSUE_LABELS="$LABELS"
  elif [ -n "$ISSUE" ]; then
    local json
    # REST で取る(GraphQL が 403 になるクラウドセッションでも動くように。autopilot-next.sh と同じ方針)
    local repo
    # shellcheck source=lib-github.sh
    repo="$( . "$(dirname "${BASH_SOURCE[0]}")/lib-github.sh" 2>/dev/null && gh_resolve_repo)" || repo="{owner}/{repo}"
    if json="$(gh api "repos/$repo/issues/$ISSUE" 2>/dev/null)"; then
      ISSUE_BODY="$(printf '%s' "$json" | jq -r '.body // ""')"
      ISSUE_LABELS="$(printf '%s' "$json" | jq -r '[.labels[].name] | join(",")')"
    else
      echo "⚠️ Issue #$ISSUE を取得できなかった(gh が使えない?)。Issue のチェックとラベルは見ずに決める。クラウドでは --issue-body-file / --issue-labels で渡す" >&2
    fi
  else
    ISSUE_LABELS="$LABELS"
  fi
}

from_issue_checks() { # $1=stage → 値(未指定なら空)。同じ工程に 2 つ以上チェックがあれば exit 2
  [ -n "$ISSUE_BODY" ] || return 0
  local section line key val found="" count=0
  # 「担当AI」見出しから次の見出しまで
  section="$(printf '%s\n' "$ISSUE_BODY" | tr -d '\r' | awk '
    /^#+[[:space:]]*担当 ?AI/ { on=1; next }
    on && /^#+[[:space:]]/ { exit }
    on { print }' | sed 's/：/:/g')"
  # 全角コロンは上で半角に寄せる(ブラケット式にマルチバイトを入れると、C ロケールでは
  # バイト単位の集合になり「レビュー」の「ー」が誤って弾かれる)
  while IFS= read -r line; do
    # - [x] 実装: Codex
    [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+\[[xX]\][[:space:]]+([^:]+):[[:space:]]*(.+)$ ]] || continue
    key="$(norm_stage "$(printf '%s' "${BASH_REMATCH[1]}" | sed -E 's/[[:space:]]+$//')")"
    [ "$key" = "$1" ] || continue
    val="$(norm_value "${BASH_REMATCH[2]}")"
    [ -n "$val" ] || die_invalid "Issue の担当AI欄の担当名が不正: '${BASH_REMATCH[2]}'"
    count=$((count + 1)); found="$val"
  done <<<"$section"
  [ "$count" -le 1 ] || die_invalid "Issue の担当AI欄で「$( [ "$1" = implement ] && echo 実装 || echo レビュー )」に $count 個チェックが付いている。1 つにする"
  printf '%s' "$found"
}

from_label() { # $1=stage
  [ "$1" = implement ] || return 0
  printf ',%s,' "$ISSUE_LABELS" | grep -q ',delegate:codex,' && printf 'codex'
}

# --- 4. routing.json ---
from_config() { # $1=stage
  [ -f .claude/routing.json ] || return 0
  local v
  v="$(jq -r --arg s "$1" '.[$s] // empty' .claude/routing.json 2>/dev/null)" || return 0
  [ -n "$v" ] || return 0
  local n; n="$(norm_value "$v")"
  [ -n "$n" ] || die_invalid ".claude/routing.json の $1 が不正: '$v'"
  printf '%s' "$n"
}

default_of() { [ "$1" = implement ] && echo codex || echo claude:sonnet; }

resolve() { # $1=stage → "値<TAB>出典"
  local v
  v="$(from_set "$1")" || exit $?
  [ -n "$v" ] && { printf '%s\tコマンドの記載\n' "$v"; return; }
  v="$(from_issue_checks "$1")" || exit $?
  [ -n "$v" ] && { printf '%s\tIssue のチェック\n' "$v"; return; }
  v="$(from_label "$1")"
  [ -n "$v" ] && { printf '%s\tdelegate:codex ラベル\n' "$v"; return; }
  v="$(from_config "$1")" || exit $?
  [ -n "$v" ] && { printf '%s\t.claude/routing.json\n' "$v"; return; }
  printf '%s\t既定値\n' "$(default_of "$1")"
}

load_issue

R="$(resolve "$STAGE")" || exit $?
VALUE="${R%%$'\t'*}"
SOURCE="${R#*$'\t'}"

if [ "$VALUE" = auto ]; then
  [ "$STAGE" = review ] || die_invalid "auto はレビューにだけ指定できる"
  IR="$(resolve implement)" || exit $?
  IMPL="${IR%%$'\t'*}"
  [ "$IMPL" = auto ] && IMPL=codex
  if [ "$IMPL" = codex ]; then VALUE=claude:sonnet; else VALUE=codex; fi
  SOURCE="$SOURCE(auto: 実装 = $IMPL の別ベンダー)"
fi

[ "$EXPLAIN" = 1 ] && echo "$STAGE = $VALUE(出典: $SOURCE)" >&2
printf '%s\n' "$VALUE"
exit 0
