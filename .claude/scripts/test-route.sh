#!/bin/bash
# route.sh(担当AIの判定)の動作確認。一時ディレクトリの中で完結する(gh・ネットワーク不要)。
#
#   bash .claude/scripts/test-route.sh
#     → 失敗した検査を 1 行ずつ出し、1 件でもあれば exit 1
set -uo pipefail

ROUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/route.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" && git init -q && mkdir -p .claude
export CLAUDE_PROJECT_DIR="$WORK"

FAILS=0
expect() { # 説明 期待値 引数...
  local desc="$1" want="$2"; shift 2
  local got; got="$(LC_ALL=C bash "$ROUTE" "$@" 2>/dev/null)"
  [ "$got" = "$want" ] || { echo "NG: $desc(期待 $want / 実際 ${got:-<空>})"; FAILS=1; }
}
expect_rc() { # 説明 期待終了コード 引数...
  local desc="$1" want="$2"; shift 2
  LC_ALL=C bash "$ROUTE" "$@" >/dev/null 2>&1
  local rc=$?
  [ "$rc" = "$want" ] || { echo "NG: $desc(期待 exit $want / 実際 exit $rc)"; FAILS=1; }
}

# --- 既定値 ---
expect "既定: 実装は Codex" codex implement
expect "既定: レビューは Sonnet" claude:sonnet review

# --- routing.json ---
printf '{ "implement": "sonnet", "review": "auto" }\n' > .claude/routing.json
expect "routing.json: 実装" claude:sonnet implement
expect "routing.json: レビュー auto → 実装(Claude)の別ベンダー = Codex" codex review

# --- ラベル ---
expect "delegate:codex ラベルは routing.json より優先" codex implement --issue-labels "ticket,delegate:codex"
expect "ラベルで実装が Codex なら auto レビューは Sonnet" claude:sonnet review --issue-labels "delegate:codex"

# --- Issue のチェック ---
cat > body.md <<'MD'
## 背景
- [x] 実装: Codex   ← 担当AI節の外なので無視される

## 担当AI

- [ ] 実装: Codex
- [x] 実装: Claude Opus
- [ ] レビュー: Codex
- [X] レビュー：Claude Haiku

## 受け入れ条件
- [x] 実装: Codex
MD
expect "Issue のチェック(担当AI節だけを見る)" claude:opus implement --issue-body-file body.md --issue-labels "delegate:codex"
expect "Issue のチェック(大文字 X・全角コロン)" claude:haiku review --issue-body-file body.md

cat > none.md <<'MD'
## 担当AI

- [ ] 実装: Codex
- [ ] 実装: Claude Sonnet
MD
expect "チェックなしなら routing.json" claude:sonnet implement --issue-body-file none.md

cat > dup.md <<'MD'
### 担当 AI
- [x] 実装: Codex
- [x] 実装: Claude Sonnet
MD
expect_rc "同じ工程に 2 つチェックがあれば exit 2" 2 implement --issue-body-file dup.md

# --- コマンドの記載 ---
expect "--set は Issue より優先(日本語の工程名)" codex implement --issue-body-file body.md --set 実装=codex
expect "--set の別名(impl / Claude Sonnet)" claude:sonnet implement --set "impl=Claude Sonnet"
expect "--set で実装を変えると auto レビューも追従" claude:sonnet review --set 実装=codex --set レビュー=auto
expect_rc "--set の担当名が不正なら exit 2" 2 implement --set 実装=gemini
expect_rc "auto は実装には指定できない" 2 implement --set 実装=auto
expect_rc "未知の工程は exit 64" 64 deploy

# --- 不正な routing.json ---
printf '{ "implement": "gpt" }\n' > .claude/routing.json
expect_rc "routing.json の担当名が不正なら exit 2" 2 implement

if [ "$FAILS" -eq 0 ]; then echo "route: all checks passed"; fi
exit "$FAILS"
