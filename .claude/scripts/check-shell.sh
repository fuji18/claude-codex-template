#!/bin/bash
# シェルスクリプトの静的検査(shellcheck)の唯一の実行経路。
#
#   bash .claude/scripts/check-shell.sh          # 指摘を出す
#   bash .claude/scripts/check-shell.sh --list   # 検査対象のファイル一覧だけを出す
#
# 終了コード: 0 = 指摘なし / 1 = 指摘あり / 2 = 検査を実行できない(shellcheck が無い・対象が 0 件)
#
# 読み手が 2 系統(CI の harness-integrity ジョブ / 手元の `/check` と人間)あるため、
# 対象の選定と shellcheck の引数をここに集約する。CI だけが知っている引数があると
# 「手元では緑なのに CI で落ちる(逆もある)」状態になり、手元で先に見ることの意味が消える。
# このリポジトリで繰り返し起きている事故の形がこれ(判定が 2 箇所にある)。
#
# ハーネスの判定の実体 —— 委託の入口(delegate-codex.sh)・保護ブランチ判定
# (check-protected-branch.sh)・autopilot の選定(autopilot-next.sh)—— はほぼ全部シェルで、
# `bash -n` は構文エラーしか見ない。クォート漏れや cd 失敗の取りこぼしはここで止める。
#
# 深刻度を warning 以上に絞る理由: note にはこのリポジトリが**意図して**使っている書き方が
# 多く含まれる(set -e を発火させないための `A && B || C` = SC2015 / 共有ライブラリの
# source = SC1091)。全部拾うと鳴りっぱなしになり、「赤いのが普通」のゲートは誰も読まなくなる。
# 個別に抑止したいものは、その場に `# shellcheck disable=SCxxxx` と理由を書くこと。
# **ここの深刻度は下げない。**
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 2

die() { echo "check-shell.sh: $*" >&2; exit 2; }

MODE=run
case "${1:-}" in
  '') ;;
  --list) MODE=list ;;
  -h | --help)
    sed -n '2,7p' "$0"
    exit 0
    ;;
  *) die "不明な引数: $1(--list / --help)" ;;
esac

command -v git >/dev/null 2>&1 || die "git が見つからない"

# 追跡ファイルだけを見る。.husky/_/ は husky の生成物で git 追跡外、
# .steering/ は過去の作業記録(再現用スクリプト)なので修正対象にしない。
# .husky/pre-commit と .husky/prepare-commit-msg は拡張子が無いので別に拾う。
mapfile -t FILES < <(git ls-files | grep -E '\.sh$|^\.husky/[a-z-]+$' | grep -v '^\.steering/')

# 0 件を「指摘なし」に倒さない。テンプレートの .claude/scripts/*.sh は必ず追跡下にあるので、
# 空になるのは git ls-files が働いていないか、除外条件が壊れたとき。
# シェルを一切使わない構成のプロジェクトでは、CI のステップごと落とす(CHANGELOG に明記)。
[ "${#FILES[@]}" -gt 0 ] || die "検査対象のシェルスクリプトが 1 つも無い(git ls-files と除外条件を疑う)"

if [ "$MODE" = list ]; then
  printf '%s\n' "${FILES[@]}"
  exit 0
fi

command -v shellcheck >/dev/null 2>&1 ||
  die "shellcheck が見つからない(devcontainer なら .devcontainer/post_create.sh が入れる。手で入れるなら sudo apt-get install -y shellcheck)"

echo "検査対象: ${#FILES[@]} ファイル($(shellcheck --version | sed -n 2p))"

#   -x            source された共有ライブラリも追う
#   -P SCRIPTDIR  `# shellcheck source=` をスクリプト自身のディレクトリ基準で解決する
#                 (呼び出しはリポジトリルート相対で書かれているため、これが無いと
#                  lib-*.sh が毎回「追えない」で埋まる)
shellcheck -x -P SCRIPTDIR --severity=warning "${FILES[@]}"
