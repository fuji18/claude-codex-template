#!/bin/bash
# PreToolUse(Bash) hook: 破壊的コマンドのパターン検査(第二防衛線)。
# permissions.deny は前方一致のみのため、引数順の違い(git push origin --force)や
# パイプ・サブシェル内の危険コマンドはここで検査する。
# パターンはプロジェクトの実態に合わせて追加・削除してよい(/harness-setup で拡張)。
#
# 注意: これは文字列パターンによるベストエフォートの防衛線であり、サンドボックスではない。
# 変数展開・bash -c・eval 等による迂回は原理的に防げない。本当の境界は
# permission mode と実行環境の隔離(devcontainer / リモート環境)が担う。
set -uo pipefail

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

# コマンド位置(行頭・パイプ・;・&&・||・サブシェル・コマンド置換の直後)に限定する接頭辞。
# これが無いと引用符の中に現れただけの文字列にも一致し、
# `grep "git push --force" docs/` のような調査コマンドがブロックされる。
# `(` は $(...) とサブシェルを、バッククォートは `...` 形式のコマンド置換を拾うために含める。
# なお `bash -c "..."` / eval 経由の迂回は依然として検出できない(冒頭の注意書きのとおり、
# これはベストエフォートの防衛線であってサンドボックスではない)。
C='(^|[;&|(`]|&&|\|\|)[[:space:]]*'

# コマンド・引数の終端。空白と行末に加え、区切り文字と閉じ引用符・閉じバッククォートを含める。
# これが無いと `` `git push -f` `` のように閉じバッククォートが直後に来る形を取りこぼす。
E="([[:space:]]|[;&|)\`\"']|\$)"

patterns=(
  # rm -rf 系でルート・ホーム全体を対象にするもの(/* と ~/* も含む)
  "${C}rm[[:space:]]+-[^[:space:]]*r[^[:space:]]*[[:space:]]+(/|~/?)(\*)?${E}"
  # force push(引数順を問わない。--force-with-lease は許可)。
  # `git push -f origin main` のように -f が第一引数に来る形も拾うため、
  # 「push とフラグの間に他の引数があってもなくても」一致する形にする
  "${C}git[[:space:]]+push([[:space:]]+[^[:space:]]+)*[[:space:]]+--force${E}"
  "${C}git[[:space:]]+push([[:space:]]+[^[:space:]]+)*[[:space:]]+-f${E}"
  # force push の refspec 構文(git push origin +main)
  "${C}git[[:space:]]+push[[:space:]]+[^[:space:]]+[[:space:]]+\+[^[:space:]]"
  # 履歴の書き換え(/commit コマンドの禁止事項をハーネスでも保証する)
  "${C}git[[:space:]]+commit[[:space:]]+.*--amend"
  # パッケージ公開
  "${C}(npm|pnpm|yarn)[[:space:]]+publish"
  # 破壊的 SQL。SQL 文は文書・コード中の文字列として現れる頻度が高いため、
  # DB クライアント経由の実行に限定する(スキーマ定義ファイルの grep で誤爆しない)
  "${C}(psql|mysql|mariadb|sqlite3|mongosh|prisma|npx[[:space:]]+prisma)[[:space:]].*(DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)|TRUNCATE[[:space:]]+TABLE)"
)

for p in "${patterns[@]}"; do
  if printf '%s' "$cmd" | grep -qE "$p"; then
    echo "block-dangerous-cmds.sh: 危険パターン '$p' にマッチしたためブロックしました。本当に必要な操作なら、理由をユーザーに説明して承認を得てください。" >&2
    exit 2
  fi
done

exit 0
