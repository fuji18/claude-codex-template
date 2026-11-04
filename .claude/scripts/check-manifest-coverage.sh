#!/bin/bash
# テンプレート本体で、追跡ファイルがすべて template-manifest.json のどれかの区分
# (owned / merge / never)に入っているかを検査する。
#
#   bash .claude/scripts/check-manifest-coverage.sh
#     → 未分類のファイルを 1 行ずつ stdout に出し、1 件でもあれば exit 1
#
# どの区分にも無いファイルは /sync-template の対象外になり、テンプレート側で
# 直しても下流プロジェクトに永久に届かない(.codex/ の一部が漏れていた実例がある)。
# 新しいファイルを足した PR で区分の追加漏れを機械的に止めるための検査。
#
# 下流プロジェクトでは実行しない(アプリ本体のファイルは未分類で正しい)。
# テンプレート本体かどうかは、origin(CI では GITHUB_REPOSITORY)と templateRepo の
# 比較で判定する。判定できない場合は検査せず exit 0(下流の CI を赤くしない)。
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[ -n "$ROOT" ] && cd "$ROOT" || exit 0

MANIFEST=".claude/template-manifest.json"
[ -f "$MANIFEST" ] || exit 0
command -v jq >/dev/null 2>&1 || { echo "jq が無いため manifest の網羅検査をスキップしました" >&2; exit 0; }

normalize() { # https://github.com/owner/repo(.git) → owner/repo(小文字)
  printf '%s' "$1" | sed -E 's#^(https://|git@)github\.com[/:]##; s#\.git$##' | tr '[:upper:]' '[:lower:]'
}

TEMPLATE="$(normalize "$(jq -r '.templateRepo // ""' "$MANIFEST")")"
if [ -n "${GITHUB_REPOSITORY:-}" ]; then
  SELF="$(normalize "$GITHUB_REPOSITORY")"
else
  SELF="$(normalize "$(git remote get-url origin 2>/dev/null || true)")"
fi
[ -n "$TEMPLATE" ] && [ "$SELF" = "$TEMPLATE" ] || exit 0

PATTERNS="$(jq -r '(.owned + .merge + .never)[]' "$MANIFEST")"

MISSING=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  hit=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      */) case "$f" in "$p"*) hit=1 ;; esac ;;
      *) [ "$f" = "$p" ] && hit=1 ;;
    esac
    [ "$hit" -eq 1 ] && break
  done <<<"$PATTERNS"
  if [ "$hit" -eq 0 ]; then
    echo "template-manifest.json のどの区分(owned / merge / never)にも入っていない: $f"
    MISSING=1
  fi
done < <(git ls-files)

exit "$MISSING"
