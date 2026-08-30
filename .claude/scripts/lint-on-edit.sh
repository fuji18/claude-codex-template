#!/bin/bash
# PostToolUse(Edit|Write) async hook: TS/JS ファイルの編集後に lint と型チェックを走らせる。
#
# 設計の根拠は .steering/20260829-issue44-lint-on-edit-scope/design.md。要点は 3 つ:
#   1. eslint は編集した 1 ファイルだけに掛ける。全体 lint は編集と無関係な既存エラーを
#      毎編集ごとにコンテキストへ載せ、ファイル数に比例して太る
#   2. tsc は全体を検査する(型は 1 ファイルでは決まらない)が、出力は編集ファイルの行だけ通し、
#      それ以外は件数 1 行に畳む
#   3. 多重起動は flock で待ち合わせる。自前の mkdir ロックには (a) 実行中に入った編集を
#      無検査で捨てる (b) 強制終了でロックが孤立する の 2 つの穴があり、(b) を塞ごうとすると
#      「残骸かどうかの判定」と「奪取」がアトミックにならず二重取得が起きる(実測で再現)。
#      flock はプロセスが死ねばカーネルが解放するので、この問題自体が消える。
set -uo pipefail

f="$(jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null)"
[ -n "$f" ] || exit 0
case "$f" in
  *.ts | *.tsx | *.js | *.mjs | *.cjs) ;;
  *) exit 0 ;;
esac

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

LOCK=".claude/.lint-on-edit.lock"
LOCK_WAIT=100   # settings.json の hook timeout(120s)の内側に収める
ESLINT="node_modules/.bin/eslint"
TSC="node_modules/.bin/tsc"

root="$(realpath . 2>/dev/null || printf '%s' "$PWD")"

# 編集ファイル 1 本を検査する。プロジェクト外・削除済みのパスは黙って捨てる。
run_checks() {
  local target="$1" abs="" rel="" out="" mine="" mine_count=0 total=0

  # シンボリックリンク経由で $PWD と字面が食い違うと無検査になるため正規化する
  abs="$(realpath "$target" 2>/dev/null || printf '%s' "$target")"
  case "$abs" in
    "$root"/*) rel="${abs#"$root"/}" ;;
    /*) return 0 ;;
    *) rel="$abs" ;;
  esac
  [ -f "$rel" ] || return 0

  # --no-warn-ignored: ignores 対象ファイルを編集したときの警告を出さない
  # --no-error-on-unmatched-pattern: 対象外パスでの定型エラー(exit 2)を出さない
  if [ -x "$ESLINT" ]; then
    "$ESLINT" --no-warn-ignored --no-error-on-unmatched-pattern "$rel" 2>&1 | tail -20
  fi

  # allowJs 無効のため、型プログラムに載るのは .ts / .tsx だけ
  case "$rel" in
    *.ts | *.tsx) ;;
    *) return 0 ;;
  esac
  [ -x "$TSC" ] || return 0

  out="$("$TSC" --noEmit 2>&1)" || true
  [ -n "$out" ] || return 0

  # 編集ファイルの行だけ通す(行頭一致。grep -F の部分一致では別ファイルを拾う)
  mine="$(printf '%s\n' "$out" | awk -v p="$rel(" 'index($0, p) == 1')"
  [ -z "$mine" ] || printf '%s\n' "$mine" | head -20

  total="$(printf '%s\n' "$out" | grep -c ': error TS' || true)"
  mine_count="$(printf '%s\n' "$mine" | grep -c ': error TS' || true)"
  if [ "$((total - mine_count))" -gt 0 ]; then
    echo "(このファイル以外に型エラー $((total - mine_count)) 件。全体は npm run typecheck で確認する)"
  fi
}

# 先行プロセスの完了を待ってから検査する(スキップしない = 連続編集でも取りこぼさない)。
# 待ちきれなければこの回は諦める。hook の timeout に食い込ませて SIGKILL されるより行儀がよく、
# 検査は常にその時点の内容を読むので、後続の編集で検査される。
if command -v flock >/dev/null 2>&1; then
  if { exec 9>"$LOCK"; } 2>/dev/null; then
    flock -w "$LOCK_WAIT" 9 || exit 0
  fi
fi

run_checks "$f"
exit 0
