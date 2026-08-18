#!/bin/bash
# PreToolUse(Edit|Write) hook: 実装フェーズを司令塔(メインセッション)が直接やることを防ぐ。
#
# 実装フェーズは implement-ticket スキル(context: fork / model: sonnet)に委譲する運用のため、
# 司令塔が自分で実装コードを書き始めると、最も高いモデルで最も長いログを積むことになる。
# コマンド定義の散文だけでは守られないので、ここで機械的に止める。
#
# 判定に使う事実:
#   - フックはサブエージェント内でも発火し、その場合のみ入力 JSON に agent_id が載る
#     → agent_id が無い = メインスレッド(司令塔)からの編集
#   - .steering/ の最新ディレクトリに design.md があり tasklist.md に未完了が残っている
#     = 実装フェーズが進行中
#
# ブロックしないもの(意図的):
#   - サブエージェント(implementer 等)からの編集
#   - .steering/ / docs/ / .claude/ / .github/ への編集
#     → fork が「判断待ち」で戻ったとき、司令塔が design.md を直す動線を残すため
#   - tasklist が全て [x] の状態(= 検収フェーズ)。code-reviewer の指摘対応は司令塔が直接行う
#   - tasklist.md に <!-- main-edit-ok --> がある場合(テンプレート自体の改修など、
#     司令塔が実装するのが正しい作業のための脱出弁)
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# サブエージェントからの編集は素通し(agent_id はサブエージェント内でのみ存在する)
AGENT_ID="$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null || true)"
[ -n "$AGENT_ID" ] && exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[ -z "$FILE" ] && exit 0

# プロジェクトルートからの相対パスに正規化する
REL="${FILE#"$(pwd)/"}"

# 計画・ドキュメント・ハーネスの編集は司令塔の仕事なので通す
case "$REL" in
  .steering/* | docs/* | .claude/* | .github/* | /*) exit 0 ;;
esac

# 最新のステアリングディレクトリだけを見る(放置された過去の tasklist で止めないため)。
# 選定規則は latest-steering.sh に集約する(fork・SessionStart と同じ結果になることが要件)
# bash 経由で呼ぶ(実行権限が落ちてもフェイルオープンにならないようにする)
LATEST="$(bash .claude/scripts/latest-steering.sh 2>/dev/null || true)"
[ -z "$LATEST" ] && exit 0
[ -f "${LATEST}design.md" ] || exit 0
[ -f "${LATEST}tasklist.md" ] || exit 0

# 脱出弁
grep -q '<!-- main-edit-ok -->' "${LATEST}tasklist.md" 2>/dev/null && exit 0

# 未完了タスクが残っている = 実装フェーズ進行中
if grep -qE '^[[:space:]]*- \[ \]' "${LATEST}tasklist.md" 2>/dev/null; then
  cat >&2 <<EOF
check-implementation-phase.sh: 実装フェーズ進行中(${LATEST}tasklist.md に未完了タスクあり)のため、
メインセッションからの $REL の編集をブロックしました。

実装は implement-ticket スキル(Sonnet の fork)に委譲してください:
  Skill('implement-ticket') を ${LATEST} を対象に呼ぶ

例外的にメインセッションで実装すべき作業(テンプレート自体の改修など)の場合は、
${LATEST}tasklist.md に <!-- main-edit-ok --> を追記してください。
EOF
  exit 2
fi

exit 0
