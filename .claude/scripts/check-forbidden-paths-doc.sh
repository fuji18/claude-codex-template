#!/bin/bash
# 委託禁止領域の単一ソース(delegate-codex.sh の FORBIDDEN_PATHS = 汎用項目)と
# .claude/rules/lead/delegation-policy.md の一覧のずれを**双方向・完全一致**で検出する。
#
# 呼び出し元:
#   - .github/workflows/ci.yml の harness-integrity ジョブ … ::warning:: に変換(ジョブは赤にしない)
#
# 背景: 禁止領域の単一ソースは 2 系統(delegate-codex.sh の FORBIDDEN_PATHS = 汎用項目 /
# AGENTS.md §4 のマーカー = プロジェクト固有パス)。判断材料として司令塔にのみ注入される
# .claude/rules/lead/delegation-policy.md の「委託禁止領域(パス一覧)」節は、汎用項目だけの
# 写しであり、手動同期のため直し漏れが起きる(#64 / #83)。
#
# 警告に留める理由: 照合先の delegation-policy.md はテンプレート所有ファイル
#(/sync-template の同期対象)だが、マーカーを持たない旧版を抱えた下流プロジェクトも
# ありうる。そうした構成で CI を赤くしないため、ここでは警告に留める(#83)。
#
# 出力: ずれている項目を 1 行ずつ標準出力へ。装飾(::warning::)は呼び出し側の責任
#       (check-record-hygiene.sh / check-guard-integrity.sh と同じ分業)。
# 終了コード:
#   0 … ずれ無し(または検査対象外の構成)
#   1 … ずれがある
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] && cd "$ROOT" 2>/dev/null || true

DELEGATE=".claude/scripts/delegate-codex.sh"
DOC=".claude/rules/lead/delegation-policy.md"
BEGIN='<!-- forbidden-paths -->'
END='<!-- /forbidden-paths -->'

FOUND=0
note() { echo "$1"; FOUND=1; }

# 委託経路そのものが無い構成(Codex を使わないプロジェクト)、または
# 照合先のドキュメントが無い構成では検査しない(フェイルオープン)。
[ -f "$DELEGATE" ] || exit 0
[ -f "$DOC" ] || exit 0

FORBIDDEN_LIST="$(bash "$DELEGATE" --print-forbidden generic 2>/dev/null || true)"
if [ -z "$FORBIDDEN_LIST" ]; then
  note "$DELEGATE --print-forbidden generic が委託禁止領域を返さない。$DOC との照合が行えない"
  exit "$FOUND"
fi

# マーカーが両方揃っていることを確認する。片方だけ、または両方無い場合は
# パス単位の検査をしない(マーカーを持たない旧版の delegation-policy.md を抱えた
# 下流プロジェクトで検査を成立させないため)。
BEGIN_LINE="$(grep -nF -- "$BEGIN" "$DOC" | head -1 | cut -d: -f1)"
END_LINE="$(grep -nF -- "$END" "$DOC" | head -1 | cut -d: -f1)"
if [ -z "$BEGIN_LINE" ] || [ -z "$END_LINE" ]; then
  note "$DOC に $BEGIN / $END のマーカーが揃っていない。委託禁止領域の記述ずれを検査できない"
  exit "$FOUND"
fi

# マーカー行の間から表の行だけを取り出し、第 1 セル(パス)を抽出する。
# grep -o '`[^`]*`' ではなく awk でセル分割するのは、理由列にもバックティックで
# 囲んだ語(コマンド名など)が混ざるため、第 1 セルだけを見る必要があるから。
SECTION_RAW="$(sed -n "$((BEGIN_LINE + 1)),$((END_LINE - 1))p" "$DOC")"
SECTION_LIST="$(printf '%s\n' "$SECTION_RAW" | awk -F'|' 'NF >= 3 { print $2 }' |
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' |
  while IFS= read -r _cell; do
    case "$_cell" in
    '`'*'`')
      # 前後のバックティックを剥がす
      _cell="${_cell#\`}"
      _cell="${_cell%\`}"
      [ -n "$_cell" ] && printf '%s\n' "$_cell"
      ;;
    esac
  done)"

if [ -z "$SECTION_LIST" ]; then
  note "$DOC の $BEGIN 〜 $END の間に表の行が見つからない。委託禁止領域の記述ずれを検査できない"
  exit "$FOUND"
fi

# 末尾のワイルドカードを外してから照合する。AGENTS.md §4 は src/auth/ と src/auth/**
# の両方の書き方を許しており(delegate-codex.sh の forbidden_files() と同じ解釈)、
# 表記ゆれだけで誤検知になるのを避ける。
NORM_FORBIDDEN="$(printf '%s\n' "$FORBIDDEN_LIST" | sed 's/\*\{1,2\}$//' | LC_ALL=C sort -u)"
NORM_SECTION="$(printf '%s\n' "$SECTION_LIST" | sed 's/\*\{1,2\}$//' | LC_ALL=C sort -u)"

# 完全一致で双方向に比較する(grep -qF は使わない。部分一致だと .husky/ が
# .husky/pre-commit に一致してしまい、ずれを見逃す。#83 の回帰対象)。
while IFS= read -r _p; do
  [ -n "$_p" ] || continue
  _hit=0
  while IFS= read -r _s; do
    [ "$_p" = "$_s" ] && _hit=1 && break
  done <<<"$NORM_SECTION"
  if [ "$_hit" -eq 0 ]; then
    note "委託禁止領域 '$_p' が $DOC の一覧に書かれていない。FORBIDDEN_PATHS にパスを足したら、この表も同時に更新すること"
  fi
done <<<"$NORM_FORBIDDEN"

while IFS= read -r _s; do
  [ -n "$_s" ] || continue
  _hit=0
  while IFS= read -r _p; do
    [ "$_s" = "$_p" ] && _hit=1 && break
  done <<<"$NORM_FORBIDDEN"
  if [ "$_hit" -eq 0 ]; then
    note "$DOC の一覧にある '$_s' が delegate-codex.sh の FORBIDDEN_PATHS に無い。表に書いただけでは機械的な保護は掛からない(#80 はこの向きの乖離だった)"
  fi
done <<<"$NORM_SECTION"

exit "$FOUND"
