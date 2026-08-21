#!/bin/bash
# 保護ブランチ上にいるかを判定する共有スクリプト(ベンダー非依存)。
#
# 呼び出し元:
#   - .husky/pre-commit                      … git hook。Claude / Codex / 人手を問わず効く
#   - .claude/scripts/check-branch-policy.sh … Claude の PreToolUse hook
#
# 両者が同じ判定になることが要件のため、ルールの実体はこのファイルだけに置く
# (latest-steering.sh を hook・fork・スキルで共有しているのと同じ思想)。
#
# 終了コード:
#   0 … コミットしてよい / 判定できない(フェイルオープン)
#   1 … 現在のブランチが保護ブランチ
#
# フェイルオープンにする理由: ポリシーファイルや jq が無い環境で commit 不能に
# しないため。最終的な砦は CI の branch-policy ジョブ(.github/workflows/ci.yml)。
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] || exit 0
cd "$ROOT" || exit 0

POLICY=".claude/branch-policy.json"
[ -f "$POLICY" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# detached HEAD(rebase / bisect 中など)は空を返す → 判定しない。
# なお merge / revert / cherry-pick 中は detached にならずブランチに留まるため、
# ここではなく呼び出し元(.husky/prepare-commit-msg)が出所を見て判別する。
CUR="$(git branch --show-current 2>/dev/null || true)"
[ -n "$CUR" ] || exit 0

# index() は見つからなければ null を返し、jq -e が非ゼロで終わる
jq -e --arg b "$CUR" '.protectedBranches // [] | index($b)' "$POLICY" >/dev/null 2>&1 || exit 0

cat >&2 <<MSG
保護ブランチ '$CUR' への直接コミットはポリシーで禁止されています($POLICY)。
作業ブランチを切ってからコミットしてください:

  git switch -c feature/[作業名]
MSG
exit 1
