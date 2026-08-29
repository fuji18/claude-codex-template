#!/usr/bin/env bash
# チケット完了時の記録漏れ(CHANGELOG / decisions.jsonl)を機械的に検出する。
#
# なぜこの層に置くか: この 2 つの記録は散文の運用ルールだけでは 2 度守られなかった
# (CHANGELOG は 4 回連続 → 8 回連続と再発が悪化し、decisions.jsonl は検収フローから
# 外れた分岐で欠落した)。CI は Claude の枠を消費しない(.claude/rules/lead/review-policy.md)
# ため、機械的に判定できる部分はここに寄せる。
#
# 入力はすべて環境変数。CI(.github/workflows/record-hygiene.yml)からも手元からも
# 同じ形で渡せるようにしてあり、このスクリプト自身は gh にもネットワークにも依存しない
# (PR の事実を集めるのは呼び出し側の責務)。
#
#   CHANGED_FILES  改行区切りの変更パス一覧(リポジトリルート相対)
#   PR_LABELS      改行区切りの PR ラベル名
#   TICKET_ISSUES  改行区切りの Issue 番号。本 PR がクローズし、かつ ticket ラベルが
#                  付いているものだけを呼び出し側が絞り込んで渡す
#
# 出力は 1 行 1 件の "ERROR|メッセージ" / "NOTICE|メッセージ"。
# ERROR が 1 件でもあれば exit 1、無ければ exit 0。
#
# set -e は使わない。違反を数え上げてから終了コードを決めるため。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

CHANGELOG_PATH="docs/template-dev/CHANGELOG.md"
DECISIONS_PATH=".harness/decisions.jsonl"
CHANGELOG_ESCAPE_LABEL="no-changelog"
DECISIONS_ESCAPE_LABEL="no-decision-record"

# CHANGELOG の追記を要求する変更対象。末尾が / のものはディレクトリ配下すべてを指す。
#
# ここは .claude/template-manifest.json の owned / merge に載っている「面」と対応させる。
# 基準は「/sync-template で取り込む側が [manual] 項目に気づけなければ困るか」であって、
# ディレクトリの見た目ではない。.github/ 全体ではなく .github/workflows/ に絞るのは、
# manifest に載っているのがワークフロー 5 本だけだからで、ISSUE_TEMPLATE 等は対象外。
#
# manifest から動的に生成はしない。manifest の構造変更に検査が引きずられる方が高くつく。
# owned / merge に新しい面を足すときは、この配列も同時に直す(2 箇所の手作業で足りる)。
CHANGELOG_TRIGGERS=(".claude/" ".husky/" ".codex/" ".github/workflows/" "AGENTS.md")

CHANGED_FILES="${CHANGED_FILES:-}"
PR_LABELS="${PR_LABELS:-}"
TICKET_ISSUES="${TICKET_ISSUES:-}"

errors=0

emit_error() {
  printf 'ERROR|%s\n' "$1"
  errors=$((errors + 1))
}

emit_notice() {
  printf 'NOTICE|%s\n' "$1"
}

has_label() {
  printf '%s\n' "$PR_LABELS" | grep -qxF "$1"
}

changed_contains() {
  printf '%s\n' "$CHANGED_FILES" | grep -qxF "$1"
}

# --- 検査1: CHANGELOG の記載漏れ ---
# while はヒアストリングで回す(パイプにすると subshell になり triggered が残らない)。
triggered=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  for p in "${CHANGELOG_TRIGGERS[@]}"; do
    case "$p" in
      */) case "$f" in "$p"*) triggered="$f" ;; esac ;;
      *) [ "$f" = "$p" ] && triggered="$f" ;;
    esac
    [ -n "$triggered" ] && break
  done
  [ -n "$triggered" ] && break
done <<< "$CHANGED_FILES"

if [ -n "$triggered" ]; then
  if changed_contains "$CHANGELOG_PATH"; then
    :
  elif has_label "$CHANGELOG_ESCAPE_LABEL"; then
    emit_notice "CHANGELOG 検査はラベル '${CHANGELOG_ESCAPE_LABEL}' によりスキップされました(検出した変更: ${triggered})"
  else
    emit_error "テンプレート同期の対象(${triggered})を変更していますが ${CHANGELOG_PATH} が更新されていません。/sync-template は syncedAt 以降の日付見出しだけを読むため、ここが欠けると取り込む側は [manual] 項目に気づけません。追記が不要な変更(リバート・誤字修正など)ならラベル '${CHANGELOG_ESCAPE_LABEL}' を付けてください"
  fi
fi

# --- 検査2: decisions.jsonl の記載漏れ ---
while IFS= read -r n; do
  [ -n "$n" ] || continue
  if has_label "$DECISIONS_ESCAPE_LABEL"; then
    emit_notice "decisions.jsonl 検査(#${n})はラベル '${DECISIONS_ESCAPE_LABEL}' によりスキップされました"
    continue
  fi
  if [ ! -f "${REPO_ROOT}/${DECISIONS_PATH}" ]; then
    emit_error "${DECISIONS_PATH} がありません(#${n} の委託判断を記録できません)"
    continue
  fi
  # "issue":29 が "issue":295 に誤マッチしないよう、直後を , か } に限定する
  if ! grep -Eq "\"issue\"[[:space:]]*:[[:space:]]*${n}[[:space:]]*[,}]" "${REPO_ROOT}/${DECISIONS_PATH}"; then
    emit_error "この PR は ticket #${n} をクローズしますが、${DECISIONS_PATH} に \"issue\": ${n} の行がありません。.claude/rules/lead/delegation-policy.md「実測の記録」に従い、PR を出す前に 1 行追記してください(往復回数と検収の指摘数は検収時点で確定しています)。記録が不要な場合はラベル '${DECISIONS_ESCAPE_LABEL}' を付けてください"
  fi
done <<< "$TICKET_ISSUES"

[ "$errors" -eq 0 ] || exit 1
exit 0
