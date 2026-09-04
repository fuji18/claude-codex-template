#!/bin/bash
# 委託禁止領域の単一ソース(delegate-codex.sh)と CLAUDE.md の説明節のずれを検出する。
#
# 呼び出し元:
#   - .github/workflows/ci.yml の harness-integrity ジョブ … ::warning:: に変換(ジョブは赤にしない)
#
# 背景: 禁止領域の単一ソースは 2 系統(delegate-codex.sh の FORBIDDEN_PATHS = 汎用項目 /
# AGENTS.md §4 のマーカー = プロジェクト固有パス)。CLAUDE.md「Codex への委託禁止領域(パス)」
# 節は司令塔が振り分けを判断するための説明で、手動同期のため 3 箇所目の直し漏れが起きる(#64)。
#
# 警告に留める理由: CLAUDE.md はプロジェクト所有ファイルで、説明文の書き方に自由度がある。
# 機械検査で表現を縛ると文書が硬直する。自動生成もしない(プロジェクト側の追記と衝突する)。
#
# 出力: ずれている項目を 1 行ずつ標準出力へ。装飾(::warning::)は呼び出し側の責任
#       (check-record-hygiene.sh / check-guard-integrity.sh と同じ分業)。
# 終了コード:
#   0 … ずれ無し(または検査対象外の構成)
#   1 … ずれがある
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] && cd "$ROOT" 2>/dev/null

DELEGATE=".claude/scripts/delegate-codex.sh"
MEMORY="CLAUDE.md"
HEADING="### Codex への委託禁止領域"

FOUND=0
note() { echo "$1"; FOUND=1; }

# 委託経路そのものが無い構成(Codex を使わないプロジェクト)では検査しない
[ -f "$DELEGATE" ] || exit 0
[ -f "$MEMORY" ] || exit 0

FORBIDDEN_LIST="$(bash "$DELEGATE" --print-forbidden 2>/dev/null || true)"
if [ -z "$FORBIDDEN_LIST" ]; then
  note "$DELEGATE --print-forbidden が委託禁止領域を返さない。$MEMORY との照合が行えない"
  exit "$FOUND"
fi

# CLAUDE.md の該当節だけを取り出す。節が見つからないときはパス単位の検査をしない
# (節名はプロジェクト所有ファイルの記述であり改名されうる。全パスを未記載として
#  報告すると警告が十数行出て意味を失う)。
SECTION="$(awk -v h="$HEADING" 'index($0, h) == 1 { f = 1; next } f && /^#+ / { exit } f' "$MEMORY")"
if [ -z "$SECTION" ]; then
  note "$MEMORY に「$HEADING」節が見つからない。委託禁止領域の記述ずれを検査できない(節を改名したなら check-forbidden-paths-doc.sh の HEADING も直すこと)"
  exit "$FOUND"
fi

# 末尾のワイルドカードを外してから照合する。AGENTS.md §4 は src/auth/ と src/auth/**
# の両方の書き方を許しており(delegate-codex.sh の forbidden_files() と同じ解釈)、
# CLAUDE.md 側が別の書き方をしているだけで誤検知になるのを避ける。
while IFS= read -r _p; do
  [ -n "$_p" ] || continue
  # 実在しないものは検査しない。AGENTS.md のマーカー内は散文もバックティックで囲むため、
  # 抽出結果に `delegate-codex.sh` や <!-- verify-probe: ... --> のような非パスが混ざる
  # (delegate-codex.sh 側も forbidden_files() で同じ実在検査をしている)。
  # 裏を返すと「まだ存在しないパスを FORBIDDEN_PATHS に足した」ケースは検知できない。
  # 警告層としては許容する。
  [ -e "$_p" ] || continue
  printf '%s\n' "$SECTION" | grep -qF -- "$_p" && continue
  note "委託禁止領域 '$_p' が $MEMORY の「$HEADING」節に書かれていない。単一ソース($DELEGATE の FORBIDDEN_PATHS / AGENTS.md §4)にパスを足したら、この節の説明も同時に更新すること"
done < <(printf '%s\n' "$FORBIDDEN_LIST" | sed 's/\*\{1,2\}$//' | LC_ALL=C sort -u)

exit "$FOUND"
