#!/bin/bash
# ハーネスモード(normal / econ / degraded)の唯一の読み取り経路。
#
#   bash .claude/scripts/harness-mode.sh
#     → normal / econ / degraded のいずれか 1 行を stdout に出す(必ず有効値)
#
# 読む順序は固定する(§2.2): CODEX_HARNESS_MODE > .harness/mode > normal。
# 読み手が 2 系統(Claude の SessionStart / Codex 側の delegate-codex.sh・AGENTS.md)
# あるため、判定の実体をここに集約する。どちらかだけが古い規則で動いても
# 誰も気づかないのが、このリポジトリで繰り返し起きている事故の形。
#
# 不正な値は normal に倒し、警告は stderr に出す(呼び出し側の stdout を汚さない)。
# 終了コードは常に 0。モードの読み取りで作業が止まる方が害が大きい。
#
# 参照: docs/template-dev/codex-delegation-plan.md §2.2
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[ -n "$ROOT" ] && cd "$ROOT" 2>/dev/null

MODE="${CODEX_HARNESS_MODE:-}"
if [ -z "$MODE" ] && [ -f .harness/mode ]; then
  # 前後の空白と改行をすべて落とす。人間が echo で書くファイルなので、
  # 改行の有無や末尾スペースに挙動を依存させない。
  MODE="$(tr -d '[:space:]' <.harness/mode 2>/dev/null || true)"
fi
[ -n "$MODE" ] || MODE="normal"

case "$MODE" in
  normal | econ | degraded) ;;
  *)
    echo "⚠️ ハーネスモードの値が不正: '$MODE'(.harness/mode か CODEX_HARNESS_MODE)。normal として扱う。有効値: normal / econ / degraded" >&2
    MODE="normal"
    ;;
esac

printf '%s\n' "$MODE"
exit 0
