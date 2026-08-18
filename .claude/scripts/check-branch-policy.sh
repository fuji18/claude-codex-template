#!/bin/bash
# PreToolUse(Bash) hook: ブランチ戦略からの乖離を検査する。
# リモートセッション(Claude Code on the web / アプリ)ではブランチをプラットフォームが
# 先に作るため、散文のルール(CLAUDE.md・コマンド md)だけでは規約が守られないことがある。
# hook はローカル・リモートを問わず同じ .claude/branch-policy.json を参照するため、
# クライアントによらず同じ判定になる。
#
# 検査するのは「名前」ではなく「どこへ PR するか / どこにコミットするか」:
#   1) 保護ブランチ(main / develop)上での git commit
#   2) --base 無し、またはポリシー外の base を指定した gh pr create
#
# 注意: block-dangerous-cmds.sh と同じく文字列パターンによるベストエフォート。
# 最終的な砦は CI の branch-policy ジョブ(.github/workflows/ci.yml)が担う。
set -uo pipefail

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

POLICY=".claude/branch-policy.json"
[ -f "$POLICY" ] && [ -x "$(command -v jq)" ] || exit 0

# コマンド位置(行頭・パイプ・;・&&・||・サブシェル・コマンド置換の直後)に限定する接頭辞。
# これが無いと、引用符の中に現れただけの文字列にも一致してしまい、
# `grep "gh pr create" docs/` のような調査コマンドがブロックされる。
# `(` は $(...) とサブシェルを、バッククォートは `...` 形式のコマンド置換を拾うために含める。
CMD_START='(^|[;&|(`]|&&|\|\|)[[:space:]]*'

BASE="$(jq -r '.baseBranch // "main"' "$POLICY" 2>/dev/null || echo main)"
RELEASE_BASE="$(jq -r '.releaseBase // "main"' "$POLICY" 2>/dev/null || echo main)"
CUR="$(git branch --show-current 2>/dev/null || true)"

# --- 1) 保護ブランチへの直接コミット ---
if printf '%s' "$cmd" | grep -qE "${CMD_START}git[[:space:]]+commit([[:space:]]|$)"; then
  if [ -n "$CUR" ] && jq -e --arg b "$CUR" '.protectedBranches // [] | index($b)' "$POLICY" >/dev/null 2>&1; then
    echo "check-branch-policy.sh: 保護ブランチ '$CUR' への直接コミットはポリシーで禁止されています(.claude/branch-policy.json)。作業ブランチを切ってからコミットしてください。" >&2
    exit 2
  fi
fi

# --- 2) gh pr create の base 検査 ---
if printf '%s' "$cmd" | grep -qE "${CMD_START}gh[[:space:]]+pr[[:space:]]+create"; then
  # リリース系ブランチ(develop / release/* / hotfix/*)からの PR は releaseBase(main)が正
  expected="$BASE"
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$CUR" in "$p"*) expected="$RELEASE_BASE" ;; esac
  done < <(jq -r '.releasePrefixes // [] | .[]' "$POLICY" 2>/dev/null)

  if ! printf '%s' "$cmd" | grep -qE '(--base|-B)[[:space:]=]'; then
    echo "check-branch-policy.sh: gh pr create に --base がありません。ポリシー上のベースブランチは '$expected' です(.claude/branch-policy.json)。--base $expected を明示してください。" >&2
    exit 2
  fi

  actual="$(printf '%s' "$cmd" | grep -oE '(--base|-B)[[:space:]=]+[^[:space:]]+' | head -1 | sed -E 's/^(--base|-B)[[:space:]=]+//' | tr -d "\"'")"
  if [ -n "$actual" ] && [ "$actual" != "$expected" ]; then
    # ポリシー上のベースが存在しないリポジトリ(develop 未作成等)では誤検知になるため、
    # 実在を確認したうえでのみブロックする
    if git show-ref --verify -q "refs/remotes/origin/$expected" || git show-ref --verify -q "refs/heads/$expected"; then
      echo "check-branch-policy.sh: PR のベースが '$actual' ですが、ポリシー上は '$expected' です(.claude/branch-policy.json)。アプリ(リモートセッション)は既定ブランチ起点でセッションを作るため、base の指定漏れが起きやすい点に注意してください。意図的に変更する場合はユーザーの承認を得てください。" >&2
      exit 2
    fi
  fi
fi

exit 0
