#!/bin/bash
# push 先のブランチがポリシーに沿っているかを検査する(.husky/pre-push から呼ばれる)。
#
# 保護ブランチの検査(check-protected-branch.sh)は「コミット」を止めるが、push は見ない。
# `git push origin HEAD:main` は作業ブランチ上から実行できるため、コミット側の層をすべて
# 素通りする。PreToolUse hook は Claude 経由にしか効かないので、ベンダー非依存の
# git hook 層で宛先の ref 名そのものを見る。
#
# 入力: 標準入力に pre-push の行 `<local ref> <local sha> <remote ref> <remote sha>`
# 判定(refs/heads/ 宛てのみ。タグ等は対象外):
#   - 宛先が protectedBranches        … 違反(削除も含む)
#   - 削除(local sha が全 0)          … 通す
#   - 宛先が allowedPrefixes に前方一致しない … 違反(CI の branch-policy で必ず落ちる名前)
# 終了コード:
#   0 … 問題なし(ポリシーや jq が無い構成も含む。フェイルオープン)
#   1 … 違反あり(理由は標準エラーへ)
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] && cd "$ROOT" 2>/dev/null || true

POLICY=".claude/branch-policy.json"
[ -f "$POLICY" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

FOUND=0
while read -r _local_ref local_sha remote_ref _remote_sha; do
  case "$remote_ref" in
    refs/heads/*) ;;
    *) continue ;;
  esac
  branch="${remote_ref#refs/heads/}"

  if jq -e --arg b "$branch" '(.protectedBranches // []) | index($b)' "$POLICY" >/dev/null 2>&1; then
    echo "check-push-policy.sh: 保護ブランチ '$branch' への直接 push はできません($POLICY の protectedBranches)。作業ブランチを push して PR を出してください。" >&2
    FOUND=1
    continue
  fi

  # 削除は保護ブランチ以外なら通す(マージ済みブランチの掃除を止めない)
  case "$local_sha" in
    *[!0]*) ;;
    *) continue ;;
  esac

  if ! jq -e --arg b "$branch" '[(.allowedPrefixes // [])[] | select(. as $p | $b | startswith($p))] | length > 0' "$POLICY" >/dev/null 2>&1; then
    ALLOWED="$(jq -r '(.allowedPrefixes // []) | join(", ")' "$POLICY" 2>/dev/null)"
    echo "check-push-policy.sh: ブランチ名 '$branch' がポリシーの接頭辞に一致しません(許可: $ALLOWED)。この名前の PR は CI の branch-policy で落ちます。ポリシーに沿った名前のブランチを切って push してください。" >&2
    FOUND=1
  fi
done

exit "$FOUND"
