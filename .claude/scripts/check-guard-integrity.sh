#!/bin/bash
# ベンダー非依存ガードレール(.husky/* → check-protected-branch.sh)が生きているかを検査する。
#
# 呼び出し元:
#   - .claude/hooks/session-start.sh … 早期警告(Claude セッション開始時)
#   - .github/workflows/ci.yml       … 最終検証(クライアント非依存・Claude を一度も起動しなくても効く)
#
# 両者で判定がずれないよう、実体はこのファイルだけに置く
# (check-protected-branch.sh / latest-steering.sh と同じ思想)。
#
# 出力: 壊れている項目を 1 行ずつ標準出力へ。装飾(⚠️ / ::error::)は呼び出し側の責任。
# 終了コード:
#   0 … 健全(または検査対象外の構成)
#   1 … 壊れている項目がある
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] && cd "$ROOT" 2>/dev/null

GUARD=".claude/scripts/check-protected-branch.sh"
POLICY=".claude/branch-policy.json"

FOUND=0
note() { echo "$1"; FOUND=1; }

# --- 1) 単一ソースの空洞化 ---
# 保護ブランチ検査の全層(PreToolUse hook / .husky/* / CI の branch-policy ジョブ)は
# いずれも protectedBranches という同じ配列を読む。ここが空になると全層が同時に、
# かつ「正常に動作したうえで素通し」という形で無効化される。層の数では防げない唯一の経路。
if [ -f "$POLICY" ] && command -v jq >/dev/null 2>&1; then
  jq -e '(.protectedBranches // []) | length > 0' "$POLICY" >/dev/null 2>&1 ||
    note "$POLICY の protectedBranches が空。保護ブランチ検査が全層(PreToolUse / .husky/* / CI)で素通しになる"
fi

# --- 2) husky を使う構成か ---
# テンプレートはスタック非依存なので、husky を持たない構成(Python / Go 等)では
# git hook 層の検査自体を行わない。ただし判定を「.husky/ があるか」だけにしてはいけない:
# フックごと消えると検査がスキップされ、層が完全消滅した最悪のケースが最も静かに通る。
# package.json の依存も見て「husky を使うはずの構成なのにフックが無い」を検知する。
USES_HUSKY=no
[ -d .husky ] && USES_HUSKY=yes
if [ "$USES_HUSKY" = no ] && [ -f package.json ] && command -v jq >/dev/null 2>&1; then
  jq -e '(.devDependencies.husky // .dependencies.husky) != null' package.json >/dev/null 2>&1 && USES_HUSKY=yes
fi
[ "$USES_HUSKY" = yes ] || exit "$FOUND"

# --- 3) 判定の実体があるか ---
[ -f "$GUARD" ] ||
  note "$GUARD が存在しない。保護ブランチへの直接コミットを止めるベンダー非依存の層(Codex・手動 git に効く唯一の層)が失われている"

# --- 4) 各フックが実際に呼んでいるか ---
# 呼び出しとみなすのは「コメントでない行」からの bash / sh / source 起動だけ。
# 単なる文字列一致だと、呼び出し行をコメントアウトしても検査が通ってしまう
# (説明コメントにファイル名が出てくるだけで緑になる)。
INVOKE_RE='^[^#]*(bash|sh|source|\.)[[:space:]]+"?(\$GUARD|[^"]*check-protected-branch\.sh)"?'

# pre-commit         … git commit / git commit --amend
# prepare-commit-msg … git revert / git cherry-pick(pre-commit は発火しない)
for h in pre-commit prepare-commit-msg; do
  case "$h" in
    pre-commit) covers="git commit / git commit --amend" ;;
    *)          covers="git revert / git cherry-pick" ;;
  esac
  if [ ! -f ".husky/$h" ]; then
    note ".husky/$h が存在しない。保護ブランチ上の $covers が素通しになる"
  elif ! grep -qE "$INVOKE_RE" ".husky/$h"; then
    note ".husky/$h が $GUARD を呼んでいない(呼び出しがコメントアウトされている可能性)。保護ブランチ上の $covers が素通しになる"
  fi
done

exit "$FOUND"
