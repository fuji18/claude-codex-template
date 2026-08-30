# shellcheck shell=bash
# run record(.harness/codex-runs/*.json)を読むための共有関数。
#
# **source 専用。** 実行ビットは付けない(関数定義しか無い)。
# 命名規約: .claude/scripts/lib-*.sh は source 専用。CI(ci.yml の harness-integrity)と
# SessionStart hook が、この名前のファイルに **実行ビットが無いこと・shebang が無いこと**
# を機械検査する(#45 §10)。単体で起動する実体を lib- で始まる名前にしないこと。
# 利用側: .claude/scripts/delegate-codex.sh / .claude/scripts/codex-run.sh
#
# 委託禁止領域に入るか: 入る。FORBIDDEN_PATHS の ".claude/scripts/" がディレクトリ単位
# なので(#40)、このファイルは追加作業なしで出口検査・縮退検査の対象になる。
#
# 実行中の書き換えハザード: delegate-codex.sh は起動直後に自身を一時ディレクトリへ
# コピーして exec する(#15)。このファイルも同じ一時ディレクトリへ一緒にコピーされ、
# コピー側から source される。委託中に元ファイルが書き換わっても、走っている
# プロセスが読む rec_field は変わらない(design §1)。

# $1=json ファイル $2=キー名。無い/null は空文字列を返す。
#
# sed 経路は run record が「1 行 1 キー・値が 1 行に収まる」形式であることに依存する。
# #29 の検収で Minor として挙がったが、この形式で record を書いているのは
# delegate-codex.sh だけなので、既存の性質として受け入れている。
#
# sed フォールバックの既知の癖(検収で実測): クォートされていない値(pid / accepted など)
# では `[^"]*` が末尾のカンマまで飲み込む。"pid": 82711, → 82711, が返り、
# kill -0 "82711," が引数エラーで必ず失敗する = 再入防止(入口検査5-5)が jq 不在環境で
# 静かにフェイルオープンしていた。捕獲後に末尾のカンマと空白を必ず剥がす。
# クォートされた値は `[^"]*` が閉じ引用符で止まるためもともと影響を受けない。
rec_field() {
  local _out=""
  if command -v jq >/dev/null 2>&1; then
    # `// empty` は使わない。jq の // は false も falsy として捨てるため、
    # "accepted": false が「キーが無い」と区別できなくなり、sed 経路と
    # 結果が食い違う(実測)。null のときだけ空を返す形にする。
    _out="$(jq -r --arg k "$2" '.[$k] | if . == null then empty else . end' "$1" 2>/dev/null)"
  else
    _out="$(sed -n "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\},\{0,1\}[[:space:]]*$/\1/p" "$1" | head -1)"
    _out="${_out%"${_out##*[![:space:]]}"}"
    _out="${_out%,}"
    _out="${_out%"${_out##*[![:space:]]}"}"
  fi
  [ "$_out" = "null" ] && _out=""
  printf '%s' "$_out"
}
