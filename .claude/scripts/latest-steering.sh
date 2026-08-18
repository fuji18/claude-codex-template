#!/bin/bash
# 最新のステアリングディレクトリを 1 つ標準出力に返す(無ければ何も出さずに終了)。
#
# 選定規則(hook・スキル・エージェントで同一であることが要件):
#   第一キー: ディレクトリ名の日付プレフィックス(先頭 8 桁 YYYYMMDD)の降順
#   第二キー: tasklist.md の mtime の降順(同日に複数の作業がある場合)
#
# 単純な `ls -1d .steering/*/ | sort -r | head -1` はディレクトリ名**全体**の降順に
# なるため、同日では機能名の文字順で決まってしまう(例: 20260812-fork-... が
# 20260812-add-... に勝つ)。実装フェーズのブロック判定と fork の実装対象が
# 別々のディレクトリを指すと、守りが効かないまま誤ったタスクリストを消化する。
#
# 第二キーにディレクトリの mtime を使わない理由: 古い作業の requirements.md を
# 1 つ直しただけでそのディレクトリが「最新」に化ける。進捗を表すのは tasklist.md の
# 更新なので、そこだけを見る。
#
# 日付プレフィックスを第一キーに置くのは、クローン直後に mtime が揃っても
# 順序が決定的になるようにするため。
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
[ -d .steering ] || exit 0

mtime() {
  # GNU coreutils / BSD(macOS)の両方に対応する
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

for d in .steering/*/; do
  [ -d "$d" ] || continue
  target="$d"
  [ -f "${d}tasklist.md" ] && target="${d}tasklist.md"
  name="${d#.steering/}"
  printf '%s\t%s\t%s\n' "${name:0:8}" "$(mtime "$target")" "$d"
done | sort -k1,1r -k2,2nr | head -1 | cut -f3
