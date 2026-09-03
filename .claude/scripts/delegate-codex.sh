#!/bin/bash
# Codex への委託経路(唯一の入口)。
#
#   .claude/scripts/delegate-codex.sh <mode> <target>
#
# 実装済みの 3 モード:
#   explore <調査指示 | ファイルパス>  … 広域コード探索。サマリーのみ返す(read-only)
#   review  <base-ref>                … 敵対的レビュー。指摘リストを返す(read-only)
#   impl    <.steering/[dir]>         … 実装フェーズの委託(workspace-write)
# fix-ci と --background は未実装。前者は本テンプレートの段階外、後者は「前景で 1 本ずつ」を
# 運用として選んだため(根拠: docs/template-dev/codex-delegation-plan.md §6)。
#
# 終了コード契約(司令塔はこの値だけを見て分岐する。推測しない):
#   0 完了                             → 検収へ
#   1 判断待ち                         → design.md に追記して再委託
#   2 失敗(タスク起因・使い方の誤り)  → 原因分析
#   3 Codex 利用不可(CLI 不在・未認証・依存未インストール)→ 恒久フォールバック
#   4 Codex 側のレート上限             → 一時フォールバック(待つ or Sonnet fork)
#   5 計画が未完成(impl の design.md が draft のまま)
#
# 割り込み(SIGINT / SIGTERM)では 130 / 143 を返す。これは 0〜5 の契約とは別枠で、
# 「委託の結果」ではなく「委託が中断された」ことを表す(run record は running のまま残る)。
#
# 3 と 4 を混ぜないこと。前者は環境の欠落(恒久)、後者は枠切れ(一時)で
# 回復手段が違う。
#
# フェイルオープンにしない(保護ブランチ検査とは方針が逆)。
# 保護ブランチ検査は止めるとコミットが不能になるためフェイルオープンだが、
# 委託は止めても作業が継続できる(Sonnet fork がある)。止めたコストが小さく、
# 通したコスト(枠の消費・機密の送信)が大きいので、非対称が逆向きになる。
#
# 出力はサマリーのみ。生ログは .harness/codex-runs/[id].log に落とす。
#
# 参照: docs/template-dev/codex-delegation-plan.md §3
set -uo pipefail

# ---------- 自己編集ハザード対策: 自身をコピーして exec ----------
#
# bash はスクリプトを逐次読み込みする。実行中に自分自身のファイルが書き換わると
# 次に読むオフセットがずれ、無関係な行で構文エラーになって死ぬ。委託先がハーネス層を
# 触るのはテンプレート開発では常態なので、起動直後に自身を一時ディレクトリへコピーし、
# そちらを exec して走る。以降どれだけ元ファイルが書き換わっても、読んでいるのは
# コピーなので影響がない(根拠: docs/template-dev/codex-delegation-plan.md §9)。
# 共有ファイル(lib-record.sh)も同じディレクトリへ一緒にコピーし、コピー側から source する。
#
# exec は PID もカレントディレクトリも変えないため、$$ を使う RUN_ID / run record の
# pid、および git rev-parse --show-toplevel 以下の相対パス参照は従来どおり成立する。
#
# 環境変数:
#   CODEX_DELEGATE_SELF_COPY    内部用。コピー先ディレクトリ(= 再入マーカー)。外から設定しない
#   CODEX_DELEGATE_NO_SELF_COPY =1 でコピーを行わない(再現テストが旧挙動を再現するための逃げ道)
#
# ここはフェイルオープンにする。機密送信やガードレールと違い、これは堅牢化の層であって
# 安全検査ではない。コピーに失敗しただけで委託を丸ごと止めるのは、通したコストより
# 止めたコストの方が大きい(入口検査群とは非対称の判断)。
if [ "${CODEX_DELEGATE_NO_SELF_COPY:-}" = "1" ]; then
  # 保護を切ったことは必ずログに残す。コピー失敗時は警告が出るのに、明示的な無効化だけが
  # 黙って通るのは非対称で危うい(シェルプロファイルや CI の環境変数に残っていても気づけない)。
  echo "delegate-codex: 警告 — CODEX_DELEGATE_NO_SELF_COPY=1 のため自己コピー保護を無効にしています(再現テスト以外では設定しないでください)。" >&2
elif [ -z "${CODEX_DELEGATE_SELF_COPY:-}" ]; then
  _self="${BASH_SOURCE[0]:-$0}"
  _copy_dir="$(mktemp -d 2>/dev/null || true)"
  if [ -n "$_copy_dir" ] && [ -d "$_copy_dir" ] &&
    cp "$_self" "$_copy_dir/delegate-codex.sh" 2>/dev/null; then
    # source する共有ファイル(lib-record.sh)も一緒に運ぶ。運ばないと、コピーを exec
    # しているのに実行中に読むファイルがリポジトリ側に残り、自己編集ハザード対策に
    # 穴が開く(委託先が実行中に書き換えられる)。
    # **ここはフェイルオープン**: 失敗しても委託は止めない。下の解決順が $ROOT へ
    # フォールバックし、警告を出す(design §1)。
    _self_dir="$(cd "$(dirname "$_self")" 2>/dev/null && pwd || true)"
    [ -n "$_self_dir" ] && cp "$_self_dir/lib-record.sh" "$_copy_dir/lib-record.sh" 2>/dev/null
    export CODEX_DELEGATE_SELF_COPY="$_copy_dir"
    # exec が失敗した場合、非対話シェルはその場で終了する(execfail 未設定。実測 exit 127)。
    # したがってマーカーを export したまま下のブロックへ抜ける経路は存在しない。
    exec bash "$_copy_dir/delegate-codex.sh" "$@"
  fi
  [ -n "$_copy_dir" ] && rm -rf "$_copy_dir"
  echo "delegate-codex: 警告 — 自身の一時コピーを作れませんでした。委託中にこのスクリプトが書き換わると異常終了します。" >&2
fi

if [ -n "${CODEX_DELEGATE_SELF_COPY:-}" ]; then
  SELF_COPY_DIR="$CODEX_DELEGATE_SELF_COPY"
  # 子プロセス(codex exec とその sandbox)の環境に漏らさない。
  unset CODEX_DELEGATE_SELF_COPY
  cleanup_self_copy() { [ -n "${SELF_COPY_DIR:-}" ] && rm -rf "$SELF_COPY_DIR"; }
  trap cleanup_self_copy EXIT
  # 既定では SIGINT / SIGTERM で EXIT トラップを通らずに死ぬ = 一時ディレクトリが残る。
  # exit を明示して EXIT トラップへ落とす(終了コードはシグナル既定の 128+n に揃える)。
  trap 'exit 130' INT
  trap 'exit 143' TERM
fi

EX_FAIL=2
EX_UNAVAIL=3
EX_RATELIMIT=4
EX_BLOCKED=1    # 判断待ち
EX_NOTREADY=5   # design.md が ready でない

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$ROOT" ]; then
  echo "delegate-codex: git リポジトリの外では実行できません" >&2
  exit "$EX_FAIL"
fi
cd "$ROOT" || exit "$EX_FAIL"

# ---------- run record 読み出しの共有関数 ----------
#
# rec_field() は codex-run.sh と共有する(#45)。過去に sed フォールバックの同じバグ
# (末尾カンマ)を 2 箇所で直した実績があり、複製を続けるコストの方が高いと判断した。
#
# **解決順は「自身の隣 → リポジトリ」**:
#   1) 自己コピー先の一時ディレクトリ(上のブロックが lib-record.sh も一緒に運ぶ)
#   2) $ROOT/.claude/scripts/(自己コピーが無効・失敗した経路のフォールバック)
# 1 を優先するのは、リポジトリ側から source すると「コピーを exec して自己編集から
# 守る」設計に穴が開くため(委託先が実行中に書き換えられる)。
#
# **見つからなければ止める(フェイルクローズ)。** rec_field は入口検査5-5(impl の
# 再入防止)が使う。未定義のまま進むと空文字列が返って検査が素通しするだけで、
# 失敗として現れない(design §1)。
_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
LIB_RECORD=""
for _cand in "${_lib_dir:+$_lib_dir/lib-record.sh}" "$ROOT/.claude/scripts/lib-record.sh"; do
  [ -n "$_cand" ] && [ -f "$_cand" ] && {
    LIB_RECORD="$_cand"
    break
  }
done
if [ -z "$LIB_RECORD" ]; then
  echo "delegate-codex: .claude/scripts/lib-record.sh が見つかりません(run record を読めないため中止します)。" >&2
  exit "$EX_FAIL"
fi
# shellcheck source=lib-record.sh
. "$LIB_RECORD"
if [ -n "${SELF_COPY_DIR:-}" ] && [ "$LIB_RECORD" != "$SELF_COPY_DIR/lib-record.sh" ]; then
  echo "delegate-codex: 警告 — lib-record.sh の一時コピーを使えていません。委託中にこのファイルが書き換わると異常終了します。" >&2
fi
unset _lib_dir _cand

# ---------- 引数 ----------

MODE="${1:-}"
[ $# -ge 1 ] && shift
TARGET="${1:-}"
[ $# -ge 1 ] && shift

usage() {
  cat >&2 <<'USAGE'
使い方: .claude/scripts/delegate-codex.sh <mode> <target>

  explore <調査指示 | ファイルパス>   広域コード探索(read-only)
  review  <base-ref>                 敵対的レビュー(read-only)
  impl <.steering/[dir]>             実装フェーズの委託(workspace-write)
  --print-forbidden                  委託禁止領域の一覧を 1 行 1 パスで出力(read-only)

環境変数:
  CODEX_HARNESS_MODE          ハーネスモードの上書き(既定は .harness/mode)
  CODEX_DELEGATE_ACK_SECRETS  機密ファイル検出時の承認(=1 で続行。承認付き再実行であって人間確認の保証ではない)
  CODEX_DELEGATE_ENV_ALLOW    委託先へ追加で渡す環境変数名(カンマ区切り。既定は許可リストのみ)
USAGE
}

case "$MODE" in
  explore | review | impl | --print-forbidden) ;;
  fix-ci)
    echo "delegate-codex: 'fix-ci' は本テンプレートでは未実装です" >&2
    exit "$EX_FAIL"
    ;;
  *)
    usage
    exit "$EX_FAIL"
    ;;
esac

if [ "$MODE" != "--print-forbidden" ] && [ -z "$TARGET" ]; then
  echo "delegate-codex: target が空です" >&2
  usage
  exit "$EX_FAIL"
fi

# 余剰オプションは黙って無視しない。「指定したのに効いていない」に
# 気づけないのが一番まずい。
if [ $# -gt 0 ]; then
  case "$1" in
    --background)
      echo "delegate-codex: --background は未実装です(委託は前景で 1 本ずつ。根拠: docs/template-dev/codex-delegation-plan.md §6)" >&2
      ;;
    *)
      echo "delegate-codex: 未知のオプション: $1" >&2
      ;;
  esac
  exit "$EX_FAIL"
fi

# ---------- 入口検査0: このスクリプトが依存する外部コマンド ----------
#
# find / grep が無いと下の機密チェックが「何も見つからなかった」と同じ形で
# 黙って通ってしまう。フェイルクローズと宣言した層が静かに素通しするのは、
# 層が無いことより悪い。ここで明示的に落とす。

for _cmd in find grep sed head tail tr sort uniq; do
  if ! command -v "$_cmd" >/dev/null 2>&1; then
    echo "delegate-codex: '$_cmd' が見つかりません。入口検査が成立しないため委託しません。" >&2
    exit "$EX_UNAVAIL"
  fi
done

# ---------- 委託禁止領域の定義(単一ソース) ----------
#
# 出口検査(§末尾)と --print-forbidden の両方がここを読む。入口検査より前に置くのは、
# --print-forbidden が codex CLI 不在でも応答できる必要があるため(入口検査4 に到達しない)。
#
# 入口検査が 5 系統あるのに出口が素通しだった穴を塞ぐ層。--sandbox workspace-write の
# Codex はワークツリー内なら禁止領域も書けてしまい、書かれた先の一部は**後でサンドボックスの
# 外で実行される**:
#   - AGENTS.md の <!-- verify-probe: ... --> は、次回委託時に入口検査3 がホスト上の
#     bash -c にそのまま渡す(サンドボックス内で 1 行書く → 次回起動でホスト実行)
#     形式検査(入口検査3)で「ホスト上で任意コマンドが走る」ことは防いでいるが、
#     AGENTS.md の規約本文の改ざんは依然この経路で検出できない。
#   - .husky/* / .claude/scripts/* / .claude/hooks/* はホストの git・Claude セッションが実行する
#   - .claude/settings.json は PreToolUse hook の定義そのもの(どのコマンドを止めるかの宣言)
#   - .github/workflows/* は非 fork PR で CLAUDE_CODE_OAUTH_TOKEN に触れる定義そのもの
#   - .claude/branch-policy.json は保護ブランチ検査の全 3 層(PreToolUse hook / .husky/* /
#     CI の branch-policy ジョブ)が読む**判定データ**。判定ロジックは一本化して守ってあるが、
#     データが書き換われば全層が「正常に動作したうえで素通し」する。層の数では防げない
#     (Issue #56 / S1)
#   - .claude/rules/* は SessionStart hook と CLAUDE.md 経由で、司令塔と全サブエージェントの
#     コンテキストへ本文がそのまま注入される。1 段落足すだけで恒久的な指示注入の足場になる
#   - CLAUDE.md も同じ性質(全エージェントに毎回ロードされる)
#   - .mcp.json は MCP サーバ定義 = セッション開始時のローカルプロセス起動指示
#   - .codex/ は Codex 側の設定(network_access 等)とモード C の手順書。「Codex 自身は
#     .codex/ に書けない」は codex-cli v0.149.0 の実測に依存した前提で、CLI 更新で崩れうる
#
# ここは**汎用項目**の単一ソース(全プロジェクトに配布される層)。プロジェクト固有パスの
# 単一ソースは AGENTS.md §4 の <!-- kickoff:delegation-forbidden-paths --> の中で、
# 起動直後に PROJECT_FORBIDDEN_PATHS へ抽出済み(Issue #28)。CLAUDE.md の同名の節は
# 説明に徹し、汎用項目の内容をここと一致させる。
# 3 箇所目のリストファイルを作らないのは、そのファイル自身を守る層がまた要るため。
# このスクリプトは起動直後に自身をコピーして exec するので、実行中のプロセスが読む
# この配列は委託先から書き換えられない。
#
# .claude/scripts/ と .claude/hooks/ を個別ファイルではなくディレクトリで指定しているのは、
# 「.github/workflows/ を守るなら、workflows が bash で呼ぶ判定の実体も同等に守る」線を
# 一貫させるため(Issue #40)。個別列挙にすると、判定スクリプトが 1 本増えるたびに同じ
# 漏れを繰り返す。実際 #37 で足した check-record-hygiene.sh は、冒頭に exit 0 を 1 行
# 書くだけで全 PR の記録漏れ検査を無効化できる状態のまま守られていなかった。
# .claude/ 全体をディレクトリごと禁止にはしない。skills/ commands/ agents/ docs/ の
# 定型追記まで止めると委託の余地が過剰に狭まる。対象は次の 3 系統に限る(Issue #56):
#   1. 実行される実体      … scripts/ hooks/ settings.json .husky/* .github/workflows/
#   2. 注入される実体      … rules/ CLAUDE.md AGENTS.md .mcp.json
#   3. 全層が読む判定データ … branch-policy.json
# rules/ をディレクトリ単位にしたのは scripts/ と同じ理由。lead/ と mode/ だけを個別列挙すると
# CLAUDE.md 経由で全サブエージェントに載る spec-driven.md が漏れ、ファイルが増えるたびに
# 同じ漏れを繰り返す。rules/ への正当な追記はもともと司令塔の仕事(context-management.md
# 「ルールを追記するときの置き場所」)なので、委託の余地はほぼ狭まらない。
#
# 末尾が / のものはディレクトリ配下すべてが対象。
FORBIDDEN_PATHS=(
  ".claude/scripts/"
  ".claude/hooks/"
  ".claude/settings.json"
  ".claude/branch-policy.json"
  ".claude/rules/"
  ".husky/pre-commit"
  ".husky/prepare-commit-msg"
  ".claude/codex-denylist.txt"
  "AGENTS.md"
  "CLAUDE.md"
  ".mcp.json"
  ".github/workflows/"
  ".codex/"
  ".harness/mode"
  ".harness/codex-runs/"
)

AGENTS="AGENTS.md"

# ---------- 出口検査の対象(プロジェクト固有パス)の抽出 ----------
#
# /kickoff フェーズ4 は AGENTS.md §4 のマーカー内へ、そのプロジェクトの実際の
# モジュールパス(認証・決済・データ移行など)を追記する。それを出口検査の対象に
# 加える(Issue #28)。スクリプト内の FORBIDDEN_PATHS は汎用項目の単一ソースとして
# そのまま残り、ここで抽出した分と**マージ**して使う。汎用項目は AGENTS.md から
# マーカーごと消されても消えない。
#
# ここで抽出する理由(プロンプト構築より前・codex exec より前):
#   委託先が実行中に AGENTS.md を書き換えても、その回の検査は開始時点のリストで
#   行われる必要がある。書き換えそのものは AGENTS.md(汎用項目)の内容ハッシュ差分
#   として別途検出される。
#
# 抽出はバックティック囲みの文字列すべて。実在しないもの(説明のために囲んだだけの
# 語や <!-- verify-probe: ... --> のような断片)は forbidden_files() の実在検査で
# 落ちるため、列挙結果に現れないだけで無害。
#
# フェイルオープンの条件: マーカーが片方しか無いとき。sed の範囲指定が末尾まで
# 走り、AGENTS.md 中の無関係なバックティック語まで禁止領域に化けて全委託が常に
# 失敗するため、警告だけ出して抽出しない(片方消しによる無効化は、AGENTS.md 自身の
# 改ざんとしてその回に検出される)。
PROJECT_FORBIDDEN_PATHS=()
_fp_start=0
_fp_end=0
grep -q '<!-- kickoff:delegation-forbidden-paths -->' "$AGENTS" 2>/dev/null && _fp_start=1
grep -q '<!-- /kickoff:delegation-forbidden-paths -->' "$AGENTS" 2>/dev/null && _fp_end=1

if [ "$_fp_start" = 1 ] && [ "$_fp_end" = 1 ]; then
  while IFS= read -r _fp_line; do
    [ -n "$_fp_line" ] && PROJECT_FORBIDDEN_PATHS+=("$_fp_line")
  done < <(
    sed -n '/<!-- kickoff:delegation-forbidden-paths -->/,/<!-- \/kickoff:delegation-forbidden-paths -->/p' "$AGENTS" 2>/dev/null |
      grep -o '`[^`]*`' | sed 's/^`//; s/`$//' | LC_ALL=C sort -u
  )
  unset _fp_line
elif [ "$_fp_start" = 1 ] || [ "$_fp_end" = 1 ]; then
  echo "delegate-codex: 警告 — AGENTS.md の <!-- kickoff:delegation-forbidden-paths --> マーカーが片方しかありません。プロジェクト固有パスの抽出をスキップします(汎用項目の検査は従来どおり働きます)。" >&2
fi
unset _fp_start _fp_end

# ---------- --print-forbidden: 一覧だけを出力して終了 ----------
#
# 他スクリプト(check-guard-integrity.sh degraded)が禁止領域の判定に使う出力口。
# 配列を複製させないために置く。ここが単一ソースであり続ける。
# 出力は 1 行 1 パス(末尾 / はディレクトリ配下すべて)。
if [ "$MODE" = "--print-forbidden" ]; then
  printf '%s\n' "${FORBIDDEN_PATHS[@]}"
  if [ "${#PROJECT_FORBIDDEN_PATHS[@]}" -gt 0 ]; then
    printf '%s\n' "${PROJECT_FORBIDDEN_PATHS[@]}"
  fi
  exit 0
fi

# ---------- 入口検査0-2: jq(委託モードのみ) ----------
#
# run record の読み書きは jq に一本化してある(#63 / lib-record.sh)。
# sed フォールバックを持たないので、jq が無い状態で先へ進むと入口検査5-5
# (impl の再入防止)が空文字列を受けて静かに素通しする。**ここで止める。**
#
# exit 3(Codex 利用不可)を返すのは、これが環境の欠落であってタスクの失敗では
# ないため。司令塔は恒久フォールバック(Sonnet fork)へ落ちる。
#
# **--print-forbidden より後に置くこと。** あちらは jq を 1 行も使わず、
# check-guard-integrity.sh degraded が禁止領域の単一ソースとして読む read-only
# 経路なので、jq 不在で巻き添えにしてはならない(#42 / #63 design §3-1)。
require_jq "delegate-codex" "$EX_UNAVAIL"

# ---------- 入口検査1: 機密ファイル ----------
#
# Codex の sandbox は「書き込み」の制限であり、読み取りの deny-list は
# 存在しない(§13 #7 で確定)。.gitignore されていてもディスク上にあれば
# 読めるため、委託は機密を委託先へ送りうる。
#
# この検査が守るのは **ワークツリー内だけ**(find . の走査範囲)。ホーム配下の
# 資格情報(~/.config/gh/hosts.yml・~/.claude/ など)は走査対象外で、sandbox 設定でも
# 読み取りを止められない。環境変数経由の漏れは codex exec の許可リスト(§2)で塞いだが、
# ファイルとして置かれた資格情報は依然として委託先から読める。ここは限界として受け入れ、
# 物理的な隔離(別コンテナ・別ユーザー実行)が要るなら別途判断する。
#
# 検出時の CODEX_DELEGATE_ACK_SECRETS=1 は「人間が確認した」ことの保証ではなく、
# **承認付き再実行**にすぎない。司令塔も Bash から付けて再実行できるため、
# 人間の目が入るかどうかは permission prompt の設定に依存する。
#
# 何を機密とみなすかはプロジェクト固有(§10.2)なので、パターンは
# .claude/codex-denylist.txt に外出しし、ここでは読むだけにする。

DENYLIST=".claude/codex-denylist.txt"

if [ ! -f "$DENYLIST" ]; then
  echo "delegate-codex: $DENYLIST がありません。機密チェックが成立しないため委託しません。" >&2
  exit "$EX_UNAVAIL"
fi

# find の式を denylist から組み立てる。
# / を含むパターンはパス一致、含まないパターンはファイル名一致。
FIND_EXPR=()
while IFS= read -r _line || [ -n "$_line" ]; do
  _line="${_line%%#*}"
  _line="$(printf '%s' "$_line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -z "$_line" ] && continue
  [ ${#FIND_EXPR[@]} -gt 0 ] && FIND_EXPR+=(-o)
  case "$_line" in
    */*) FIND_EXPR+=(-path "./$_line") ;;
    *) FIND_EXPR+=(-name "$_line") ;;
  esac
done <"$DENYLIST"

if [ ${#FIND_EXPR[@]} -eq 0 ]; then
  echo "delegate-codex: $DENYLIST に有効なパターンがありません。委託しません。" >&2
  exit "$EX_UNAVAIL"
fi

# -maxdepth は付けない。深い階層の .env を見逃すため。
# 代わりに node_modules / .git / .harness を prune して走査量を抑える。
SENSITIVE="$(
  find . \
    \( -name node_modules -o -name .git -o -name .harness \) -prune -o \
    \( "${FIND_EXPR[@]}" \) -type f -print 2>/dev/null |
    grep -Ev '\.(example|sample|template)$' |
    head -20
)"

if [ -n "$SENSITIVE" ]; then
  cat >&2 <<'MSG'
delegate-codex: ワークツリーに機密の可能性があるファイルがあります。

Codex の sandbox には読み取りの除外機能が無いため、これらは委託先へ
送られうる。内容を確認し、問題なければ承認して再実行してください:

  CODEX_DELEGATE_ACK_SECRETS=1 .claude/scripts/delegate-codex.sh ...

該当:
MSG
  echo "$SENSITIVE" | sed 's/^/  /' >&2
  if [ "${CODEX_DELEGATE_ACK_SECRETS:-}" != "1" ]; then
    exit "$EX_FAIL"
  fi
fi

# ---------- 入口検査2・3: AGENTS.md と依存の導通 ----------

if [ ! -f "$AGENTS" ]; then
  cat >&2 <<'MSG'
delegate-codex: AGENTS.md がありません。

Codex は CLAUDE.md も hooks も permissions も読みません。AGENTS.md が
規約の唯一の写像なので、これが無い状態では委託しません。
MSG
  exit "$EX_UNAVAIL"
fi

# 検査の機構はこのスクリプト、検査の中身は AGENTS.md 側に置く。
# delegate-codex.sh はテンプレート所有で全プロジェクトに配られるため、
# node_modules のようなスタック固有のものを決め打ちで見てはいけない。

# ---- 入口検査3 の許可リスト(プローブ形式) ----
#
# AGENTS.md は merge 区分でプロジェクトが書き換える面であり、かつ出口ハッシュ検査が
# 効かない経路(モード C / シグナルで出口検査に到達せず死んだ委託 / 人間の誤マージ)が
# 残る。ここで抽出した文字列は **ホスト上の bash -c にそのまま渡る**ため、
# 形式検査を掛けてからでないと実行しない。
#
# denylist(禁止文字を弾く)にはしない。クォート・展開・多バイト表現で必ず抜ける。
# 「許可した文字だけで構成され、許可したコマンドで始まり、導通確認トークンを含む」
# という許可リスト方式にする。

# 第 1 トークンとして許可する実行コマンド。
#
# **この環境で実測し「ワークツリーの設定ファイルに影響されない」ことを確認したものだけ**
# を載せる。<cmd> --version は「版を出して終わる」と思いがちだが、実際には
# ランチャーがカレントの設定を読んで実行するコード自体を差し替えるものがある:
#   yarn  .yarnrc の yarn-path で任意の JS に委譲する(実測で任意コード実行)
#   mvn   .mvn/jvm.config が JVM 起動オプションに渡る(-javaagent: で premain が走る)
#   pnpm  package.json の packageManager で corepack が別バージョンを取得・実行する
# この 3 つは外した。未インストールで実測できなかったもの(deno bun go cargo rustc
# dotnet php composer swift pip uv poetry bundle)も、検証できていない以上載せない。
#   python(python3 ではない)は外してある。実測できないうえ、Python 2 を指す環境では
#   P3 の根拠である -I(3.4 で追加)が無く、cwd の sys.path 挿入を止められない。
#
# **追加するときは必ず実測すること**: 作業ディレクトリに各処理系の設定ファイルと
# canary を書き出すスクリプトを置き、env -i PATH=... HOME=... bash -c '<cmd> --version'
# で canary が作られないこと・出力がシステム版と一致することを確認する(design §16.2)。
PROBE_ALLOWED_CMDS="node npm npx python3 ruby java rake gradle"

# いずれか 1 つを末尾に要求する導通確認トークン。
#
# **裸の `version`(ダッシュなし)と `-v` / `-V` / `--help` / `-h` は入れない。**
# 裸の version は多くの処理系で「位置引数 = 実行するスクリプトのパス / タスク名」と
# 解釈され、cd "$ROOT" した状態のプローブがリポジトリ直下の `version` という
# ファイルを実行してしまう(実測: node version で version というファイルの中身が走る。
# rake / gradle はファイル名の細工すら不要で Rakefile / build.gradle を評価する)。
# -v は多くのツールで verbose の意味になり、python3 -v は対話 REPL に落ちて委託が止まる。
# --help / -h は導通確認としての価値が無い割に cwd の設定を読む CLI が残る。
# `-version` はここに入れない。ruby / rake は -v + -e に分解して残り "rsion" を
# eval しようとして落ち、python3 は Unknown option になる(実測)。
# java だけは --version(Java 9+)も -version(従来形)も版を出して終わるので、
# `java -version` を下の完全一致特例で通す。
PROBE_VERIFY_TOKENS="--version"

# **形式検査で閉じられない残りのリスク**: プローブは cd "$ROOT" した状態で実行される。
# npx --no-install <pkg> は node_modules/.bin/<pkg> を解決するため、ワークツリーに
# 実行ファイルを置ける相手には、AGENTS.md を 1 文字も変えなくてもホスト実行の経路が
# 残る。これはプローブの正当な仕事(このプロジェクトのローカル依存の導通確認)と
# 表裏一体で、形式検査では原理的に閉じられない。空ディレクトリでの実行は
# npx --no-install が常に失敗するため採れない(実測)。ワークツリーの完全性は
# 出口ハッシュ検査・check-guard-integrity.sh degraded が受け持つ別の層。

# パッケージ名 / モジュール名の検査。正規表現に一致し、かつ `..` を含まないこと。
# 正規表現だけに頼らず `..` を独立に弾くのは多重防御 — 文字クラスの見落としが
# そのままパストラバーサルになった経緯(design §14)があるため。
_probe_name_ok() {
  case "$1" in
    *..*) return 1 ;;
  esac
  LC_ALL=C printf '%s' "$1" | grep -qE "$2"
}

# プローブ文字列が許可形式かを判定する。0 = 許可 / 1 = 不許可。
# 不許可の理由は標準出力に 1 行返す(呼び出し側が警告に埋め込む)。
probe_format_reason() {
  local probe="$1"
  local -a parts
  local n last

  # (a) 長さ上限。導通確認にこれ以上は要らない。
  if [ "${#probe}" -gt 200 ]; then
    echo "200 文字を超えています"
    return 1
  fi

  # (a2) 改行を含むものは弾く。以降の grep は行単位で判定するため、複数行のうち
  #      1 行だけが許可形式なら通過してしまう。現状の抽出は head -1 で単一行だが、
  #      「呼び出し側が単一行を渡す」という暗黙の前提に防御を預けない。
  case "$probe" in
    *$'\n'*)
      echo "改行を含んでいます"
      return 1
      ;;
  esac

  # (b) 文字とトークン区切りの制限。
  #     許可文字: 英数 . _ / @ = : + -
  #     区切りは半角スペース 1 個のみ(連続スペース・タブ・改行は不許可)。
  #     これによりシェルのメタ文字( ; | & $ ` ' " ( ) < > * ? \ ! ~ 改行 )が
  #     すべて構文上あらわれない = bash -c に渡してもコマンド連結・展開が起きない。
  if ! LC_ALL=C printf '%s' "$probe" |
    grep -qE '^[A-Za-z0-9][A-Za-z0-9._/@=:+-]*( [A-Za-z0-9._/@=:+-]+)*$'; then
    echo "許可されない文字またはトークン区切りが含まれています(許可: 英数 . _ / @ = : + - と半角スペース 1 個区切り)"
    return 1
  fi

  # (c) 全体が導通確認の固定形に一致すること。
  #     トークン単位の許可(第 1 トークン + どこかに --version)では不十分だった:
  #     npm install left-pad --version / pip install requests --version /
  #     go run example.com/evil --version がすべて通り、postinstall・setup.py・
  #     リモートモジュール取得を経由してホスト上で任意コードが走る(実測)。
  #     env -i はネットワークを塞がないので、これは実害のある経路。
  #
  #       P1  <cmd> <verify>                          node --version / java -version
  #       P2  npx --no-install <pkg> <verify>         npx --no-install eslint --version
  #       P3  python|python3 -I -m <module> <verify>  python3 -I -m pytest --version
  #
  #     (b) が空白 1 個区切りを保証しているので、単語分割でトークン化してよい。
  IFS=' ' read -r -a parts <<<"$probe"
  n="${#parts[@]}"
  last="${parts[$((n - 1))]}"

  # java だけは従来形の `java -version` も通す(実測で版を出して終わる)。
  # 他の処理系は -version を -v + -e に分解するため PROBE_VERIFY_TOKENS には入れない。
  if [ "$probe" = "java -version" ]; then
    return 0
  fi

  # 末尾は必ず導通確認トークン。「表示して終わる」以外を書けなくする。
  case " $PROBE_VERIFY_TOKENS " in
    *" $last "*) ;;
    *)
      echo "末尾は導通確認トークン(${PROBE_VERIFY_TOKENS// /, })である必要があります"
      return 1
      ;;
  esac

  if [ "$n" = 2 ]; then
    # P1
    case " $PROBE_ALLOWED_CMDS " in
      *" ${parts[0]} "*) return 0 ;;
      *)
        echo "許可されていないコマンドです: ${parts[0]}"
        return 1
        ;;
    esac
  fi

  if [ "$n" = 4 ]; then
    # P2: npx は --no-install 必須(ホスト側にはネットワークがあるため、
    #     外すとレジストリから取得して実行してしまう)
    if [ "${parts[0]}" = "npx" ] && [ "${parts[1]}" = "--no-install" ]; then
      # パッケージ名は npm の文法(@scope/name または name)に限る。
      # 旧: ^[A-Za-z0-9@][A-Za-z0-9._/@-]*$ は . と / を無制限に許したため
      # `docs/../../../../../../../bin/sh` が通り、ワークツリーの外の絶対パス実行ファイルを
      # 起動できた(実測で /bin/sh に到達)。/ を @scope/ の 1 回だけに縛る。
      if _probe_name_ok "${parts[2]}" '^(@[A-Za-z0-9][A-Za-z0-9._-]*/)?[A-Za-z0-9][A-Za-z0-9._-]*$'; then
        return 0
      fi
      echo "npx のパッケージ名が不正です: ${parts[2]}"
      return 1
    fi
  fi

  if [ "$n" = 5 ]; then
    # P3: python -I -m <module> <verify>
    #     -I は必須。付けないと python は cwd を sys.path の先頭に入れるため、
    #     リポジトリ直下に <module>.py を置くだけでホスト上の任意コード実行になる
    #     (実測: python3 -m evilmod --version でカレントの evilmod.py が走る。
    #      -I を付けると No module named evilmod で止まる)。
    if [ "${parts[0]}" = "python3" ] &&
      [ "${parts[1]}" = "-I" ] && [ "${parts[2]}" = "-m" ]; then
      if _probe_name_ok "${parts[3]}" '^[A-Za-z0-9_][A-Za-z0-9._]*$'; then
        return 0
      fi
      echo "python -I -m のモジュール名が不正です: ${parts[3]}"
      return 1
    fi
  fi

  echo "許可された形に一致しません(<cmd> <verify> / npx --no-install <pkg> <verify> / python -I -m <module> <verify> のいずれか)"
  return 1
}

# プローブに渡す環境(許可リスト方式)。#23 で codex exec に入れたものと同じ考え方だが、
# **意図的に狭い**。プローブは「バージョンを表示して終わる」固定形のコマンドであり、
# エージェント実行のようにロケール・プロキシ・CA を必要としない。
#   PATH    env 自身が bash を解決するのに要る。未設定時は最小の既定値を置く
#           (未設定のまま env -i すると bash すら見つからない)
#   HOME    npm / cargo / go のキャッシュ・設定探索元。無くても現行プローブは通るが、
#           他スタックのプローブが HOME 前提で落ちるのを避けるため残す
#   TMPDIR  一時ディレクトリを既定から外している環境向け
#   COREPACK_ENABLE_NETWORK=0  corepack が package.json の packageManager を見て
#                              別バージョンを取得・実行するのを止める(pnpm/yarn は
#                              許可リストから外したが、環境によっては npm/npx も
#                              corepack の shim になりうるため入れておく)
PROBE_ENV=("PATH=${PATH:-/usr/local/bin:/usr/bin:/bin}" "COREPACK_ENABLE_NETWORK=0")
for _pe in HOME TMPDIR; do
  [ -n "${!_pe+x}" ] && PROBE_ENV+=("$_pe=${!_pe}")
done
unset _pe

PROBE="$(sed -n 's/^[[:space:]]*<!--[[:space:]]*verify-probe:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*-->[[:space:]]*$/\1/p' "$AGENTS" | head -1)"

if [ -z "$PROBE" ]; then
  # AGENTS.md は merge 区分でプロジェクトが書き換える。マーカー未反映の
  # プロジェクトを止めないため、ここだけはフェイルオープン。
  echo "delegate-codex: 警告 — AGENTS.md に <!-- verify-probe: ... --> がありません。依存の導通確認をスキップします。" >&2
elif ! _probe_reason="$(probe_format_reason "$PROBE")"; then
  # 形式外は **実行せず** スキップする。AGENTS.md の改ざんが
  # ホスト上のコマンド実行に化ける経路をここで断つ。
  cat >&2 <<MSG
delegate-codex: 警告 — 検証プローブが許可形式に適合しないため実行しません: $PROBE
  理由: $_probe_reason

AGENTS.md の <!-- verify-probe: ... --> を許可形式に直してください(制約は AGENTS.md §2 に記載)。
意図しない書き換えの可能性がある場合は、委託を続ける前に git diff で AGENTS.md を確認してください。
依存の導通確認はスキップします(委託自体は続行します)。
MSG
else
  # 何が実行されるかを毎回目に見える形にする。ここを黙らせない。
  echo "delegate-codex: 検証プローブを実行します: $PROBE" >&2
  if ! env -i "${PROBE_ENV[@]}" bash -c "$PROBE" >/dev/null 2>&1; then
    cat >&2 <<MSG
delegate-codex: 検証プローブが失敗しました: $PROBE

依存が未インストールの可能性があります。Codex の sandbox はネットワーク
無効のため、この状態で委託すると何も完遂できないまま枠だけを消費します。
先に依存をインストールしてから再実行してください。

(プローブは env -i + 最小の環境変数で実行されます。親の環境変数に依存する
 プローブはここで失敗します。)
MSG
    exit "$EX_UNAVAIL"
  fi
fi
unset _probe_reason

# ---------- 入口検査4: Codex CLI ----------

if ! command -v codex >/dev/null 2>&1; then
  cat >&2 <<'MSG'
delegate-codex: codex コマンドが見つかりません(Codex 利用不可)。

司令塔は恒久フォールバック(Sonnet fork)に切り替えてください。
導入手順は docs/template-dev/codex-delegation-plan.md §11 の段階0。
MSG
  exit "$EX_UNAVAIL"
fi

# codex login status はログイン済みなら 0 を返す(公式が自動化向けに明記)。
# 事前に落とせば枠を一切消費しない。
if ! codex login status >/dev/null 2>&1; then
  cat >&2 <<'MSG'
delegate-codex: Codex が未認証です(Codex 利用不可)。

  codex login

を実行してから再委託してください。当面は Sonnet fork にフォールバック。
MSG
  exit "$EX_UNAVAIL"
fi

# ---------- JSON / run record ヘルパー(入口検査5 より前に置く) ----------
#
# RUN_DIR は再入判定(5-5)が run record を読むために、この位置で確定させる。
# mkdir -p は従来どおり run record 節で行う(ここではまだ作らない)。

RUN_DIR=".harness/codex-runs"

json_str() {
  # jq に任せる(入口検査0-2 で存在は保証済み)。ただし空を返させないこと —
  # record は状態の正なので、ここが空文字列を返すと `"summary": ,` のような
  # 壊れた JSON になり、「委託を挟んで /clear できる」という前提ごと崩れる。
  # 下のフォールバックは **jq 不在用ではなく jq がエラーを返したとき用**
  # (サマリーは 2000 バイトで切るため、末尾がマルチバイト文字の途中に
  #  なりうる。jq がそれを拒む場合に落ちる先)。
  local _out=""
  _out="$(printf '%s' "${1:-}" | jq -Rs . 2>/dev/null)"
  if [ -n "$_out" ]; then
    printf '%s' "$_out"
    return
  fi
  printf '"%s"' "$(printf '%s' "${1:-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\t' '  ')"
}

json_or_null() {
  if [ -z "${1:-}" ]; then printf 'null'; else json_str "$1"; fi
}

STEERING=""

# ---------- 入口検査5: impl 専用 ----------
#
# STEERING はグローバル変数として常に定義する(impl 以外では空文字列)。
# run record の steering フィールドがこれを使う。

if [ "$MODE" = "impl" ]; then
  # ---- 5-1: target がステアリングディレクトリであること ----
  STEERING="${TARGET#./}"
  STEERING="${STEERING%/}/"

  # target は `.steering/` 配下に限定する。run record の steering フィールドと
  # SessionStart の現在地判定(latest-steering.sh)が `.steering/` 前提のため、
  # 外のディレクトリを通すと状態管理が静かにずれる。
  #
  # `..` を先に弾くのは prefix 検査を素通りさせないため — `.steering/../foo/` は
  # 文字列として `.steering/*/` に一致してしまう。
  case "$STEERING" in
    *..*)
      echo "delegate-codex: impl の target に .. を含めることはできません: $STEERING" >&2
      exit "$EX_FAIL"
      ;;
    .steering/*/) ;;
    *)
      echo "delegate-codex: impl の target は .steering/ 配下のディレクトリである必要があります: $STEERING" >&2
      exit "$EX_FAIL"
      ;;
  esac

  DESIGN="${STEERING}design.md"
  TASKLIST="${STEERING}tasklist.md"

  if [ ! -d "$STEERING" ] || [ ! -f "$DESIGN" ] || [ ! -f "$TASKLIST" ]; then
    echo "delegate-codex: impl の target は design.md と tasklist.md を持つステアリングディレクトリである必要があります: $STEERING" >&2
    exit "$EX_FAIL"
  fi

  # ---- 5-2: design.md の完成マーカー(§2.5)----
  # draft = 拒否(exit 5)/ ready = 通す / 印なし = 通す(マーカー導入以前のものを止めない)
  # 空振り条件: 印が無い design.md は書きかけでも通る。implement-ticket スキルと
  # AGENTS.md §4 が同じ規則なので、経路によらず結果が一致することを優先している。
  if grep -q '<!-- status: draft -->' "$DESIGN"; then
    cat >&2 <<MSG
delegate-codex: $DESIGN が <!-- status: draft --> です(計画が未完成)。

書きかけの設計で Codex の枠を溶かさないため委託しません。司令塔が design.md を
書き切り、印を <!-- status: ready --> に変えてから再委託してください。
MSG
    exit "$EX_NOTREADY"
  fi
  if ! grep -q '<!-- status: ready -->' "$DESIGN"; then
    echo "delegate-codex: 警告 — $DESIGN に完成マーカーがありません。検査対象外として通します。" >&2
  fi

  # ---- 5-3: git hook が有効か ----
  # 保護ブランチへのコミットを止めるベンダー非依存の層が存在しない状態で
  # workspace-write の委託をしない。
  #
  # 判定の実体はここに書かない。check-guard-integrity.sh の hooks-path サブコマンドに
  # 委ねる(隣の 5-4 が check-protected-branch.sh に委ねているのと同じ形)。
  # かつてここに独自の条件を書いていたため、縮退復帰検査の D1 が見ている
  # 「.husky 配下かどうか」が抜け、実在する無関係なディレクトリを指す
  # core.hooksPath を素通ししていた(#59)。
  #
  # 空振り条件:
  #   - husky を使わない構成(Python/Go 等)ではサブコマンドが何も見ずに 0 を返す。
  #     git hook 層そのものが存在しないので判定できない
  #   - スクリプトが無い / hooks-path を知らない旧版(rc が 0・1 以外)のときは
  #     警告だけ出して素通しする。同期ずれで全委託を止めないため。この欠落は
  #     CI の harness-integrity ジョブ(同スクリプトを必ず実行する)が別途赤くする
  GUARD_INTEGRITY=".claude/scripts/check-guard-integrity.sh"
  if [ -f "$GUARD_INTEGRITY" ]; then
    HOOKS_PATH_ISSUES="$(bash "$GUARD_INTEGRITY" hooks-path 2>/dev/null)"
    case $? in
      0) ;;
      1)
        cat >&2 <<MSG
delegate-codex: git hook が無効です(Codex 利用不可)。

$HOOKS_PATH_ISSUES

husky が有効化されていないため、保護ブランチへのコミットを止めるベンダー非依存の
層が存在しません。sandbox はネットワーク無効なので Codex 自身では復旧できません。

  npm ci        (または npx husky)

を実行してから再委託してください。当面は Sonnet fork にフォールバック。
MSG
        exit "$EX_UNAVAIL"
        ;;
      *)
        echo "delegate-codex: 警告 — $GUARD_INTEGRITY hooks-path を実行できませんでした(古い版の可能性)。git hook の検査をスキップします。" >&2
        ;;
    esac
  fi

  # ---- 5-4: 保護ブランチ上で実装委託しない ----
  # 判定の実体は共有スクリプトに委ねる(hook・CI と同じ結果になることが要件)。
  # 空振り条件: check-protected-branch.sh は jq / ポリシーファイルが無いとき
  # フェイルオープン(exit 0)する。そこでは保護ブランチでも通る。
  if [ -f .claude/scripts/check-protected-branch.sh ] &&
    ! bash .claude/scripts/check-protected-branch.sh 2>/dev/null; then
    echo "delegate-codex: 保護ブランチ上では実装を委託しません。作業ブランチを切ってください。" >&2
    exit "$EX_FAIL"
  fi

  # ---- 5-5: 再入防止(impl の並行実行を 1 本に制限)----
  # delegation-policy.md の「並行数は 1 本まで(同一ワーキングツリーを共有するため)」を
  # 機械化する層。同じステアリングへの二重起動だけでなく、別ステアリングへの並行 impl も
  # 止める(ツリーを共有するため、片方の lint/format が他方の編集を巻き込む)。
  # 判定軸を steering 一致にしていたときはこの経路が素通りしていた。
  #
  # 空振り条件: explore / review は read-only でこの検査区画そのものを通らないため、
  # 従来どおり並行できる(意図した挙動)。
  # 誤検知の条件: 生存判定は pid のみを見るため、status=running のまま残った record の
  # pid を OS が別プロセスに再利用していると「実行中」と誤認して止める。判定軸が全
  # ステアリングに広がったぶん露出は増えた。止まったときは §12.6 の手順で record を
  # 実態に合わせる(`codex-run.sh set-status <id> <status>`)。
  _stale_ids=""
  if [ -d "$RUN_DIR" ]; then
    for _f in "$RUN_DIR"/*.json; do
      [ -f "$_f" ] || continue
      [ "$(rec_field "$_f" mode)" = "impl" ] || continue
      _st="$(rec_field "$_f" status)"
      [ "$_st" = "running" ] || continue
      _pid="$(rec_field "$_f" pid)"
      _rid="$(rec_field "$_f" id)"
      _rsteer="$(rec_field "$_f" steering)"
      # pid は数字でなければ「取れなかった」として扱う。kill -0 に非数字を渡すと
      # 引数エラーで必ず失敗し、実行中の委託を「プロセス不在」と誤認して素通しする。
      # rec_field 側でも直したが、この層でも明示的に落とす(検査が空振りする条件を減らす)。
      case "$_pid" in
        '' | *[!0-9]*) _pid="" ;;
      esac
      if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
        if [ "$_rsteer" = "$STEERING" ]; then
          echo "delegate-codex: 同じステアリングへの委託が実行中です(id=$_rid pid=$_pid)。二重起動しません。" >&2
        else
          echo "delegate-codex: 別のステアリングへの委託が実行中です(id=$_rid pid=$_pid steering=$_rsteer)。impl の並行数は 1 本までです。" >&2
        fi
        exit "$EX_FAIL"
      fi
      # プロセスが居ない running = 強制終了の疑い。止めはしないが必ず知らせる。
      echo "delegate-codex: 警告 — 過去の委託 $_rid が status=running のまま残っています(プロセス不在 = 強制終了の可能性)。" >&2
      echo "  回復手順は codex-delegation-plan.md §12.6。tasklist.md と git diff --stat を突き合わせてから続けてください。" >&2
      _stale_ids="${_stale_ids}${_stale_ids:+ }$_rid"
    done
  fi

  # ---- 5-5b: running 残置 record があるとき、禁止領域が dirty なら止める(Issue #46)----
  #
  # 出口検査(禁止領域の内容ハッシュを前後で比べる層)は、SIGINT / SIGTERM で
  # codex exec の途中に死ぬと到達しない。その状態で禁止領域が書き換わっていると、
  # 次回委託の BEFORE スナップショットが改ざん後の内容を「元からあったもの」として
  # 取り込み、以後その改ざんは恒久的に検出できない。status=running のまま残った
  # record がその唯一の手掛かりなので、人間が上の警告を読み飛ばしても効くように
  # 機械検査をここに置く。
  #
  # 止める側に倒す理由: 5-5 が pid 再利用の誤検知を「止める側」に倒している既存方針と
  # 揃える。通したコスト(改ざんの検出機会を恒久的に失う)が、止めたコスト
  # (record を実態に合わせる 1 コマンド)より大きい。
  #
  # 誤爆する条件(承知のうえ): 司令塔が禁止領域を正当に編集している最中に、過去の
  # running 残置 record が残っていると止まる。テンプレート自体の改修中は現実に起きる。
  # 解除は record を実態に合わせるだけでよく、編集中の差分を捨てる必要はない。残置
  # record を放置したまま委託を重ねる状態こそが塞ぎたい穴なので、この誤爆は「先に
  # record を始末させる」催促として機能する。
  #
  # 検査対象外: .harness/mode と .harness/codex-runs/ 配下。どちらも .gitignore 済みで、
  # git diff にも git ls-files --others --exclude-standard にも出ない(git 追跡外)。
  # ここでは見られないため、出口検査の内容ハッシュ比較だけが見る層として残る。
  #
  # 空振り条件: コミットが 1 つも無いリポジトリ(HEAD が無い)と、git 側が失敗した場合は
  # 確認できないため警告だけ出して通す。検査対象パスが空(正規化後に 1 件も残らない)場合も
  # 同様に確認できないため通す。PROJECT_FORBIDDEN_PATHS に `:` で始まる断片が入っていた場合は
  # その要素を捨てる(検査対象から外れるが、他の要素の検査は働く)。
  if [ -n "$_stale_ids" ]; then
    # pathspec は正規化してから渡す(#46 検収指摘)。PROJECT_FORBIDDEN_PATHS は AGENTS.md の
    # バックティック断片を無検証で抽出したものなので、git の magic pathspec(`:(exclude)...`)
    # が紛れ込みうる。混ざると他の一致結果ごと除外され、この検査が exit 0 のまま無音で
    # 空振りする(実測)。中断した委託が AGENTS.md に断片を仕込んでから死ねば、次回起動で
    # この検査自身が無効化される — 塞ごうとしている穴を検査が再現してしまう。
    # 末尾グロブの畳み方は forbidden_files() の case と同じ規則に揃える。揃えないと、
    # 出口検査が無視する変則グロブ(src/**/*.ts 等)を git が解釈し、保護対象でない
    # ファイルで誤ってブロックする。
    _forb_specs=()
    for _p in "${FORBIDDEN_PATHS[@]}" ${PROJECT_FORBIDDEN_PATHS[@]+"${PROJECT_FORBIDDEN_PATHS[@]}"}; do
      case "$_p" in
        :*) continue ;;
        */\*\* | */\*) _forb_specs+=("${_p%/*}") ;;
        *) _forb_specs+=("$_p") ;;
      esac
    done
    unset _p
    _forb_dirty=""
    if [ "${#_forb_specs[@]}" -gt 0 ] &&
      git rev-parse --verify -q HEAD >/dev/null 2>&1 &&
      _forb_diff="$(GIT_LITERAL_PATHSPECS=1 git diff HEAD --name-only -- "${_forb_specs[@]}" 2>/dev/null)" &&
      _forb_new="$(GIT_LITERAL_PATHSPECS=1 git ls-files --others --exclude-standard -- "${_forb_specs[@]}" 2>/dev/null)"; then
      _forb_dirty="$(
        printf '%s\n%s\n' "$_forb_diff" "$_forb_new" |
          grep -v '^[[:space:]]*$' | LC_ALL=C sort -u || true
      )"
    else
      echo "delegate-codex: 警告 — 禁止領域の差分を確認できませんでした(検査対象パスが空、コミットがまだ無い、または git が失敗)。出口検査の基準が汚染されていないか手で確認してください。" >&2
    fi
    if [ -n "$_forb_dirty" ]; then
      cat >&2 <<MSG
delegate-codex: 中断された委託(status=running のまま残った record: $_stale_ids)があり、
かつ委託禁止領域に未コミットの変更があります。

この状態で新しい委託を始めると、出口検査の基準(BEFORE スナップショット)がこの変更を
「元からあったもの」として取り込み、以後この変更を検出できなくなります。

  1. 差分を確認する:              git diff HEAD -- <該当パス>
  2. 意図しない変更は破棄する:    git checkout -- <該当パス>
  3. 残置 record を実態に合わせる:
       bash .claude/scripts/codex-run.sh set-status <id> failed

意図した編集(司令塔がハーネス層を改修中など)であれば 3 だけで通ります。差分を捨てる
必要はありません。回復手順の全文は docs/template-dev/codex-delegation-plan.md §12.6。

該当:
MSG
      printf '%s\n' "$_forb_dirty" | sed 's/^/  /' >&2
      exit "$EX_FAIL"
    fi
    unset _forb_dirty _forb_diff _forb_new _forb_specs
  fi
  unset _stale_ids
fi

# ---------- ハーネスモード ----------
#
# 読む順序は固定する: プロンプト経由の上書き > .harness/mode > normal。
# 判定の実体は harness-mode.sh に集約する(SessionStart hook と同じ結果になることが要件)。
# AGENTS.md 側にも同じ順序を書いてある(モード C はこの経路を通らないため)。
# スクリプトが消えていても委託自体は止めない(normal に倒す)。

HMODE=""
if [ -f .claude/scripts/harness-mode.sh ]; then
  HMODE="$(CODEX_HARNESS_MODE="${CODEX_HARNESS_MODE:-}" bash .claude/scripts/harness-mode.sh 2>/dev/null || true)"
fi
[ -n "$HMODE" ] || HMODE="normal"

# ---------- run record ----------
#
# §3.2: これが状態の正。会話に依存しないので、委託を挟んで /clear できる。

# pid を足すのは衝突回避。秒までしか持たない ID だと、同じ秒に始まった 2 本の
# 委託で log と record が無条件に上書きされる。impl は 5-5 が 1 本に制限するが、
# explore / review は入口検査5 を通らず並行できるのでこの経路が残る。
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$RUN_DIR" || exit "$EX_FAIL"

# run record は自動削除しない(§12.8)。溜まるほど出口検査の forbidden_snapshot() が
# .harness/codex-runs/ 配下を前後 2 回ハッシュするコストが線形に増えるため、閾値を
# 超えたら警告だけ出す。削除の判断は人間が行う(未検収の record は検収キューであり、
# 勝手に消えると検収漏れが静かに発生する)。
RUN_WARN_THRESHOLD=50
REC_COUNT="$(find "$RUN_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
if [ "${REC_COUNT:-0}" -gt "$RUN_WARN_THRESHOLD" ]; then
  echo "delegate-codex: run record が ${REC_COUNT} 件あります(閾値 ${RUN_WARN_THRESHOLD})。\`bash .claude/scripts/codex-run.sh prune --dry-run\` で整理を検討してください(委託は続行します)。" >&2
fi

LOG="$RUN_DIR/$RUN_ID.log"
REC="$RUN_DIR/$RUN_ID.json"
LAST="$RUN_DIR/$RUN_ID.last.txt"
BRANCH="$(git branch --show-current 2>/dev/null || true)"

STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ENDED_AT=""
CODEX_SESSION_ID=""

# $1=status $2=summary $3=error $4=resetAt $5=accepted(true/false。既定 false)
write_record() {
  # JSON にそのまま埋めるため true/false のリテラルに正規化する。
  # 呼び出し側の綴り間違いや空文字で record が壊れた JSON になるのを防ぐ。
  local _accepted
  case "${5:-false}" in
    true) _accepted=true ;;
    *) _accepted=false ;;
  esac
  cat >"$REC" <<JSON
{
  "id": $(json_str "$RUN_ID"),
  "mode": $(json_str "$MODE"),
  "target": $(json_str "$TARGET"),
  "steering": $(json_or_null "$STEERING"),
  "branch": $(json_str "$BRANCH"),
  "harnessMode": $(json_str "$HMODE"),
  "codexSessionId": $(json_or_null "$CODEX_SESSION_ID"),
  "pid": $$,
  "status": $(json_str "$1"),
  "startedAt": $(json_str "$STARTED_AT"),
  "endedAt": $(json_or_null "$ENDED_AT"),
  "resetAt": $(json_or_null "${4:-}"),
  "summary": $(json_or_null "${2:-}"),
  "error": $(json_or_null "${3:-}"),
  "log": $(json_str "$LOG"),
  "accepted": $_accepted
}
JSON
}

# $1=status $2=exit-code
emit() {
  printf '[codex:%s] status=%s id=%s exit=%s\n' "$MODE" "$1" "$RUN_ID" "$2"
  printf 'log: %s\n' "$LOG"
}

# ---------- プロンプト構築(参照渡し。内容は貼らない) ----------

if [ "$MODE" = "impl" ]; then
  PREAMBLE="あなたは実装フェーズ(--sandbox workspace-write)で起動されています。

まず $AGENTS を読み、そこに書かれた規約に従ってください。
現在のハーネスモード: $HMODE"
else
  PREAMBLE="あなたは読み取り専用(--sandbox read-only)で起動されています。ファイルの変更・コミットは行わないでください。

まず $AGENTS を読み、そこに書かれた規約に従ってください。
現在のハーネスモード: $HMODE"
fi

case "$MODE" in
  explore)
    if [ -f "$TARGET" ]; then
      TASK="次のファイルに書かれた調査指示に従ってください: $TARGET"
    else
      TASK="次の調査を行ってください: $TARGET"
    fi
    PROMPT="$PREAMBLE

$TASK

出力は次の形式の**サマリーのみ**にしてください(ファイル全文や長い引用を貼らない):
- 結論(3 行以内)
- 根拠(path:line の形式で最大 10 件)
- 残る不確実性(あれば 1 行)"
    ;;
  review)
    PROMPT="$PREAMBLE

git diff $TARGET...HEAD の差分を敵対的にレビューしてください。
差分もファイルも自分で読んでください(この指示には貼っていません)。

出力は次の形式の**指摘リストのみ**にしてください:
- [P0|P1|P2] path:line — 指摘の要旨(1 行)/ 失敗シナリオ(1 行)
指摘が無ければ「指摘なし」とだけ書いてください。"
    ;;
  impl)
    PROMPT="$PREAMBLE

対象のステアリングディレクトリ: $STEERING

${STEERING}design.md と ${STEERING}tasklist.md を読み、tasklist の未完了タスクを
先頭から 1 つずつ実装してください。内容はこの指示に貼っていません。自分で読んでください。

守ること:
- **1 タスク完了ごとに tasklist.md を - [x] へ更新する**(まとめ更新は禁止)。途中で
  停止しても別の実装者が続きから引き継げることが要件です
- design.md に書かれていない設計判断が必要になったら、推測せず停止して「判断待ち」で報告する
- 変更したファイルだけを対象に lint・型チェック・関連テストを回す(全体フォーマットは禁止)
- ネットワークは無効。新規依存の追加が必要になったら実装せず「判断待ち」で報告する
- コミットの可否は AGENTS.md のモード表に従う

**最後に、次のどれか 1 行を単独の行として出力してください。司令塔はこの行だけで分岐します:**
完了: tasklist N/M / 変更 K ファイル / lint・型・関連テスト pass
判断待ち: [何が決まっていないか] / [考えられる選択肢]
失敗: [何が起きたか] / [試したこと]"
    ;;
esac

# ---------- 実行 ----------
#
# sandbox は設定ファイルではなくフラグで渡す。CLI フラグは project config に
# 優先し、untrusted なプロジェクトでは .codex/ が丸ごと読まれないため、
# .codex/config.toml が効いている保証が無い(§7.2 / §9)。

SANDBOX="read-only"
[ "$MODE" = "impl" ] && SANDBOX="workspace-write"

# ---------- 出口検査(委託禁止領域)のヘルパー ----------
#
# 判定対象の配列(FORBIDDEN_PATHS / PROJECT_FORBIDDEN_PATHS)はスクリプト冒頭で定義済み。
# ここにはそれを使う関数だけを置く。

# 禁止領域の実ファイルを列挙する。今回の委託自身が書く 3 ファイル(run record・生ログ・
# last message)は当然変わるので除外する。除外しないと全ての impl 委託が必ず違反になる。
forbidden_files() {
  local _p _d
  # 汎用項目(FORBIDDEN_PATHS)と AGENTS.md から抽出したプロジェクト固有パスの両方を見る。
  # 抽出側が空でも汎用項目が必ず走ることを保証しているのは ${arr[@]+"${arr[@]}"} の形
  # (set -u の下で空配列を安全に展開する)であって、配列の並び順ではない。順序は
  # 読みやすさのために「汎用が先」にしてあるだけで、入れ替えても結果は変わらない。
  for _p in "${FORBIDDEN_PATHS[@]}" ${PROJECT_FORBIDDEN_PATHS[@]+"${PROJECT_FORBIDDEN_PATHS[@]}"}; do
    case "$_p" in
      # /kickoff の記入例は dir/** 形式(.claude/commands/kickoff.md)。dir/ と同じく
      # 配下すべてとして扱う。受けるのは末尾が /** または /* のものだけで、それ以外の
      # 変則的なグロブ(**/*.ext のような先頭グロブ、src/**/*.ts、dir/*/ 等)は解釈せず、
      # 下の catch-all で実在検査に落ちて無視される(誤検出はしないが保護もされない)。
      */\*\* | */\*)
        _d="${_p%/*}"
        [ -d "$_d" ] && find "$_d" -type f -print 2>/dev/null
        ;;
      */) [ -d "${_p%/}" ] && find "${_p%/}" -type f -print 2>/dev/null ;;
      *) [ -e "$_p" ] && printf '%s\n' "$_p" ;;
    esac
  done | grep -Fxv -e "$REC" -e "$LOG" -e "$LAST" || true
  # 戻り値は意図的に捨てる。grep -Fxv は除外後に 1 行も残らないと exit 1 を返し、
  # pipefail の下では関数全体が非ゼロになる。この関数は出力だけが意味を持つ。
}

# `<hash> <path>` を path 順に並べたスナップショット。git status 系ではなく内容ハッシュで
# 比べる理由は 3 つ:
#   1. .harness/mode と .harness/codex-runs/ は .gitignore 済みで git diff にも
#      git ls-files --others --exclude-standard にも出ない
#   2. モード C では Codex がコミットするため、作業ツリー比較だけでは取りこぼす
#   3. 委託前から dirty だったファイルを誤検出しない(内容が同じなら差分ゼロ)
#
# ハッシュに git hash-object を使うのは、git がこのスクリプトの動作前提であり
# (git リポジトリ外では冒頭で落とす)、追跡外・.gitignore 済みのファイルにも効くため。
#
# 空振り条件:
#   - AGENTS.md のマーカーが片方しか無いプロジェクトでは、固有パスの抽出をスキップする
#     (汎用項目の検査は働く)。また抽出結果のうち実在しないパスは列挙されない
#   - git hash-object が前後どちらの時点でも同じように失敗した場合、差分は検出できない
#   - explore / review は read-only なのでこの検査を行わない
#   - 割り込み(SIGINT / SIGTERM)で codex exec の途中に死んだ場合、この検査には到達しない。
#     その状態で改ざんが残っていると、次回委託の BEFORE スナップショットが改ざん後の内容を
#     基準に取るため以後検出できない。run record が status=running のまま残ることが唯一の
#     手掛かりになる(回復手順は codex-delegation-plan.md §12.6)
#   - .harness/codex-runs/ が溜まるほど前後 2 回のハッシュ計算コストが線形に増える。委託 1 本の
#     所要時間に対しては十分小さいため検査対象は絞り込まず、元を断つ側(手動の
#     `codex-run.sh prune`)で抑える。自動削除はしない(Issue #29 / §12.8)
forbidden_snapshot() {
  local _f _h
  # sort -u なのは重複を畳むため(汎用項目とマーカー内の項目は重なる。ディレクトリ指定と
  # その配下ファイルの二重指定も起こりうる)。重複行が残ると、出口検査の違反抽出
  # (sort | uniq -u)が「2 回現れる行」として違反パスを取りこぼす。
  forbidden_files | LC_ALL=C sort -u | while IFS= read -r _f; do
    _h="$(git hash-object -- "$_f" 2>/dev/null)"
    printf '%s %s\n' "${_h:-UNREADABLE}" "$_f"
  done
}

# ---- package.json のライフサイクル系差分(警告のみ)のヘルパー ----
#
# sandbox が守るのは委託の実行中だけで、検収で回す npm test / npm run lint /
# lint-staged は「委託成果をホスト上・ネットワーク有効で実行する」経路になる
# (codex-delegation-plan.md §9)。package.json は委託禁止領域に入れない判断なので
# (依存や scripts を触る正当な委託が多い)、ここは警告だけを出す層にする。
#
# ブロックしない理由: 正当な scripts 変更が普通にあり、止めると層そのものが無視される。
#
# ライフサイクル節だけを抜き出して比べる(prepare は scripts の中のキーなので
# scripts を見れば覆う)。jq は入口検査0-2 で保証済み(#63)。jq が失敗した場合だけ
# ファイル全体のハッシュに落ちる(依存追加でも鳴るが、警告しか出さない層なので
# 過検出側に倒す)。
#
# 空振り条件: package.json が無いプロジェクトでは常に空文字列になり、前後が一致して
# 何も出ない(Node 以外のスタックでは正しい挙動)。
lifecycle_snapshot() {
  [ -f package.json ] || return 0
  jq -S '{scripts: .scripts, "lint-staged": ."lint-staged"}' package.json 2>/dev/null ||
    git hash-object -- package.json 2>/dev/null || true
}

# ---- 事前スナップショット(exit 0 の裏取りに使う。impl 以外では取らない) ----

# --untracked-files=all は必須。既定の -unormal は新規の未追跡ディレクトリを
# `?? dir/` の 1 行に畳むため、そのディレクトリ配下に何ファイル作っても前後の
# スナップショットが一致し、成果のある委託を「成果物が確認できない」として
# failed / exit 2 に誤判定していた(Issue #27。実測は #20 の verification.md §3)。
# 走査量は増えるが .gitignore 済みディレクトリは辿らないため実測差は誤差
# (未追跡 5000 ファイルで約 +0.02 秒 / 呼び出し)。
#
# 既知の限界: これは status 行の比較であって内容の比較ではない。既にある未追跡
# ファイルへの「追記だけ」は前後とも同じ `?? path` 行になるため検出できない。
# 検出が必要になったら内容ハッシュ方式(forbidden_snapshot と同型)へ切り替える。
tree_snapshot() { git status --porcelain --untracked-files=all 2>/dev/null | LC_ALL=C sort; }
count_done() {
  local _n
  _n="$(grep -cE '^[[:space:]]*- \[[xX]\]' "$TASKLIST" 2>/dev/null)"
  printf '%s' "${_n:-0}"
}

if [ "$MODE" = "impl" ]; then
  TREE_BEFORE="$(tree_snapshot)"
  HEAD_BEFORE="$(git rev-parse HEAD 2>/dev/null || echo none)"
  DONE_BEFORE="$(count_done)"
  FORBIDDEN_BEFORE="$(forbidden_snapshot)"
  LIFECYCLE_BEFORE="$(lifecycle_snapshot)"
fi

# ---------- codex exec に渡す環境の組み立て(許可リスト方式) ----------
#
# 親の環境には LOCAL_GH_TOKEN / CLAUDE_CODE_MESSAGING_TOKEN 等の機密が乗っている。
# codex exec は env -i で起動し、許可リストに載った変数だけを明示的に渡す
# (実測・根拠: docs/template-dev/codex-delegation-plan.md §10.2)。
#
# 各変数を残す理由:
#   PATH                              codex 自身と sandbox 内のシェルが node / git / npx を解決するのに要る
#   HOME                               Codex の認証(~/.codex/auth.json)と設定の探索元
#   USER / LOGNAME / SHELL            sandbox 内でシェルを起こすツール群が参照する。無くても動くが削る利得が無い
#   TERM                               Codex の出力制御。--color never を渡しているが未設定だと警告が出る環境がある
#   LANG / LC_* / TZ                  文字コード・日付整形。委託先が生成するログの再現性に効く
#   TMPDIR                             sandbox が一時ファイルを書く先。既定から外している環境で必要
#   proxy 系 / SSL_CERT_* / NODE_EXTRA_CA_CERTS  プロキシ配下・社内 CA 環境で API 到達に必須(このリポジトリでは未設定)
#
# pnpm / corepack / npm_config_* 系は許可リストに含めていない(本リポジトリは npm 固定
# のため不要)。他のパッケージマネージャを使うプロジェクトで必要になったら
# CODEX_DELEGATE_ENV_ALLOW で追加する。
CODEX_ENV=()
_codex_env_add() {
  # 未設定は渡さない。空文字は「設定済みの空」として渡す。
  [ -n "${!1+x}" ] || return 0
  CODEX_ENV+=("$1=${!1}")
}

for _name in PATH HOME USER LOGNAME SHELL TERM LANG TZ TMPDIR \
  HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy \
  SSL_CERT_FILE SSL_CERT_DIR NODE_EXTRA_CA_CERTS; do
  _codex_env_add "$_name"
done

# 接頭辞マッチ: compgen -e はエクスポート済み変数名のみを列挙する(compgen -v は
# スクリプト内部のシェル変数まで拾うので使わない)。除外パターンを先に書くこと。
# CODEX_DELEGATE_* / CODEX_HARNESS_MODE はこのスクリプト自身の制御変数であり、
# 委託先に見せる意味が無い(特に CODEX_DELEGATE_ACK_SECRETS が子に渡ると
# 「承認済み」の事実が委託先から観測できてしまう)。
for _name in $(compgen -e); do
  case "$_name" in
    CODEX_DELEGATE_* | CODEX_HARNESS_MODE) continue ;;
    LC_* | CODEX_*) _codex_env_add "$_name" ;;
  esac
done

# 追加の逃げ道: CODEX_DELEGATE_ENV_ALLOW(加算のみ。全バイパスは用意しない)。
# 未知の環境で必要な変数が出たときに、スクリプトを編集せずに通せる。
if [ -n "${CODEX_DELEGATE_ENV_ALLOW:-}" ]; then
  echo "delegate-codex: 警告 — CODEX_DELEGATE_ENV_ALLOW により追加の環境変数を委託先へ渡します: $CODEX_DELEGATE_ENV_ALLOW" >&2
  _saved_ifs="$IFS"; IFS=','
  for _name in $CODEX_DELEGATE_ENV_ALLOW; do
    _name="$(printf '%s' "$_name" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$_name" ] && continue
    if ! printf '%s' "$_name" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$'; then
      echo "delegate-codex: 警告 — 変数名として不正なため無視します: $_name" >&2
      continue
    fi
    _codex_env_add "$_name"
  done
  IFS="$_saved_ifs"; unset _saved_ifs
fi
unset _name

write_record "running" "" "" ""

env -i "${CODEX_ENV[@]}" codex exec \
  --cd "$ROOT" \
  --sandbox "$SANDBOX" \
  --json \
  --color never \
  --output-last-message "$LAST" \
  "$PROMPT" >"$LOG" 2>&1
CODEX_EXIT=$?

CODEX_SESSION_ID="$(grep -Eo '"(thread_id|session_id|conversation_id)"[[:space:]]*:[[:space:]]*"[^"]+"' "$LOG" 2>/dev/null |
  head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
ENDED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---------- 出口判定 ----------
#
# 判定順は 上限 → 認証 → その他。認証パターン(401 等)は上限応答にも
# 混ざりうるため、上限を先に見る。
#
# ── 何を、どの範囲で見るか(重要)────────────────────────
#
# ログは --json の全イベント = Codex が読んだファイルの引用を含む。
# したがって「ログ全体を文言で検索する」と、レビュー対象のファイルに
# たまたま "quota" や "rate limit" と書かれているだけで上限と誤判定する。
# このスクリプト自身とハーネスの計画文書がまさにそれに当たり、
# 自分をレビュー対象にすると成功した委託が exit 4 に化けた(実測)。
#
# そこで範囲を 2 つに分ける:
#   - 成功(exit 0)したときは上限・認証の判定を一切しない。
#     完走してサマリーが出ている以上、上限では終わっていない。
#     仮に本文が上限に触れていても、そのサマリーは標準出力に出るので
#     人間・司令塔の目に入る = 見逃しても静かではない。
#   - 失敗(exit 非ゼロ)したときだけ判定する。ただし構造化識別子も
#     ログ全体には当てない — 委託先が読んだファイルの引用がイベントの中に
#     入るため、このリポジトリ自身(識別子を本文に含む)を読んだ委託が
#     タスク起因で失敗すると exit 4 に化ける(#62)。トップレベルの
#     エラーイベント行(error / turn.failed)だけに当てる。
#     緩い文言パターンはさらに狭く、末尾 20 行のうち "error" / "fail"
#     を含む行だけに当てる。末尾に絞るだけでは足りない — 失敗した委託の
#     末尾にも、Codex が読んだファイルの引用は来る。
#
# 「誤検知より見逃しの方が高くつく」という当初の判断は、見逃しが静かに
# 起きることを前提にしていた。成功時はそうではないので前提が成り立たない。

RATE_ID_RE='rate_limit_reached|usage_limit_reached|credits_depleted'
# 構造化識別子を当てる範囲。トップレベルのエラーイベント行だけに限定する。
# codex exec --json のイベントのうち、ファイル引用(aggregated_output / text)を
# 運ぶのは item.* だけで、error / turn.failed はエラーメッセージしか運ばない
# (v0.149.0 実測。design.md §1.2)。引用されたファイル内容は JSON 文字列の中で
# \" にエスケープされ行頭にも来ないため、行頭アンカーで確実に外れる。
# 外した側の失敗方向は「見逃し = exit 2」で安全側。生エラーは run record に残る。
RATE_EVENT_RE='^\{"type":"(error|turn\.failed)"'
# 検収指摘への回答(design.md §6。ロジックは変更していない):
# - item.completed にネストされた type:"error" は許可リストに入れない。判定は
#   CODEX_EXIT != 0 のとき、つまりターン失敗時だけに入るため、致命的な理由は
#   必ずトップレベルの turn.failed に載る(実測。item 内の type:"error" は
#   非致命の通知だった)。item.completed は aggregated_output でファイル引用も
#   運ぶため、足すとキー並び順に依存した脆い正規表現になる
# - RATE_TEXT_RE に識別子(アンダースコア表記)は足さない。RATE_TEXT_RE が当たる
#   ERR_ONLY(末尾 20 行の error/fail 行)にはファイル引用が来るため、識別子を
#   足すと #62 と同じ誤検知を窓を狭めただけで作り直すことになる
# - workspace_owner_* / workspace_member_* の変種は RATE_ID_RE に個別追加不要。
#   RATE_ID_RE はアンカーなしの部分一致なので、既に credits_depleted /
#   usage_limit_reached にそれぞれ一致する(v0.149.0 の実バイナリ文字列で確認済み)
RATE_TEXT_RE='rate limit|usage limit|quota|429'
AUTH_RE='unauthorized|not logged in|invalid_api_key|authentication_error|401'

ERR_TAIL="$(grep -Ev '^[[:space:]]*$' "$LOG" 2>/dev/null | tail -20)"
ERR3="$(printf '%s' "$ERR_TAIL" | tail -3 | tr '\n' ' ')"

# 緩い文言パターンは「エラーらしい行」だけに当てる。末尾 20 行に絞っても、
# Codex が読んだファイルの引用がそこに来ることはある(実測)。
ERR_ONLY="$(printf '%s' "$ERR_TAIL" | grep -Ei 'error|fail' || true)"
SUMMARY=""
# 2000B で切ってから無害化する(順序を逆にすると上限の挙動が変わる)。
# ここで落とすのは制御文字だけ。内容の検査・書き換えはしない(#61 スコープ外)。
[ -f "$LAST" ] && SUMMARY="$(untrusted_sanitize "$(head -c 2000 "$LAST")")"

# ---------- 出口検査: 委託禁止領域への差分 ----------
#
# 判定行(完了 / 判断待ち / 失敗)より前、かつ CODEX_EXIT の分岐より前に置く。
# 理由は 2 つある:
#   - 判断待ち・失敗で戻ってきた委託でも、禁止領域が書き換わっていれば脱出経路は
#     成立している。委託先の自己申告より優先して司令塔に見せる
#   - レート上限・認証失敗・異常終了(CODEX_EXIT != 0)の経路は無条件 exit なので、
#     この検査を後ろに置くと丸ごと素通しになる。「改ざんしてから上限に当たった」
#     セッションが rate-limited として静かに記録されるのが最悪のケース
#
# したがって出口検査は他のどの終了理由よりも優先する。上限で終わった委託であっても、
# 禁止領域が変わっていれば failed / exit 2 として返す(待って再委託ではなく、
# 差分の確認が先に必要なため)。
if [ "$MODE" = "impl" ]; then
  FORBIDDEN_AFTER="$(forbidden_snapshot)"
  if [ "$FORBIDDEN_AFTER" != "$FORBIDDEN_BEFORE" ]; then
    # 前後のスナップショットを合わせて「1 回しか出てこない行」を拾う。
    # 変更 = 旧ハッシュ行と新ハッシュ行が 1 本ずつ、追加/削除 = 片方だけ。
    # そこからパス部分だけを取り出して重複を畳む。
    VIOLATIONS="$(
      printf '%s\n%s\n' "$FORBIDDEN_BEFORE" "$FORBIDDEN_AFTER" |
        grep -v '^[[:space:]]*$' | LC_ALL=C sort | uniq -u |
        sed 's/^[^ ]* //' | LC_ALL=C sort -u
    )"
    VIOL_LINE="$(printf '%s' "$VIOLATIONS" | tr '\n' ' ')"
    VIOL_ERR="委託禁止領域が変更されました: $VIOL_LINE"
    # 非ゼロ終了と重なったときは、それも記録に残す(上限・認証失敗と区別できるように)。
    [ "$CODEX_EXIT" -ne 0 ] && VIOL_ERR="$VIOL_ERR (codex exit=$CODEX_EXIT / $ERR3)"
    SUMMARY="⚠️ 委託禁止領域が変更されました(出口検査): $VIOL_LINE

$SUMMARY"
    write_record "failed" "$SUMMARY" "$VIOL_ERR" ""
    emit "failed" "$EX_FAIL"
    cat >&2 <<'MSG'
delegate-codex: 委託禁止領域のファイルが変更されました(出口検査)。

これらはサンドボックスの外で実行される層(AGENTS.md の verify-probe / .husky/* /
.github/workflows/* / run record)です。委託の成果をそのまま採用しないでください。

  git diff -- <該当パス>

で内容を確認し、意図しない変更は破棄してから検収してください。

該当:
MSG
    printf '%s\n' "$VIOLATIONS" | sed 's/^/  /' >&2
    exit "$EX_FAIL"
  fi
fi

# ---------- 出口検査(警告のみ): package.json のライフサイクル系差分 ----------
#
# 禁止領域の検査と違い **ブロックしない**(判断 D-3 / codex-delegation-plan.md §9)。
# 位置は禁止領域検査の直後・CODEX_EXIT の分岐より前で、上限や失敗で終わった委託でも
# 警告が出るようにしてある。rate-limited の経路は SUMMARY を捨てる(write_record に
# 空文字列を渡す)ので、stderr にも同じ内容を書く。
if [ "$MODE" = "impl" ]; then
  LIFECYCLE_AFTER="$(lifecycle_snapshot)"
  if [ "$LIFECYCLE_AFTER" != "$LIFECYCLE_BEFORE" ]; then
    SUMMARY="⚠️ package.json のライフサイクル系(scripts / lint-staged / prepare)に差分があります。
/check を回す前に \`git diff -- package.json\` で内容を確認してください
(検収は委託成果をホスト上・ネットワーク有効で実行します。codex-delegation-plan.md §9)。

$SUMMARY"
    cat >&2 <<'MSG'
delegate-codex: 警告 — package.json のライフサイクル系(scripts / lint-staged / prepare)に
差分があります。これらは検収(npm test / npm run lint / lint-staged)がサンドボックスの
外で実行する経路です。/check を回す前に内容を確認してください:

  git diff -- package.json

これは警告です。委託は失敗にしていません。
MSG
  fi
fi

if [ "$CODEX_EXIT" -ne 0 ]; then
  if grep -Eqi "$RATE_EVENT_RE.*($RATE_ID_RE)" "$LOG" 2>/dev/null ||
    printf '%s' "$ERR_ONLY" | grep -Eqi "$RATE_TEXT_RE"; then
    RESET_AT="$(grep -Eo '"reset[_a-zA-Z]*"[[:space:]]*:[[:space:]]*"[^"]*"' "$LOG" 2>/dev/null | head -1 | sed 's/.*: *"\(.*\)"/\1/')"
    write_record "rate-limited" "" "$ERR3" "$RESET_AT"
    emit "rate-limited" "$EX_RATELIMIT"
    echo "Codex 側のレート上限です。待つか Sonnet fork にフォールバックしてください。" >&2
    [ -n "$RESET_AT" ] && echo "reset: $RESET_AT" >&2
    exit "$EX_RATELIMIT"
  fi

  if printf '%s' "$ERR_ONLY" | grep -Eqi "$AUTH_RE"; then
    write_record "unavailable" "" "$ERR3" ""
    emit "unavailable" "$EX_UNAVAIL"
    echo "Codex の認証に失敗しました(codex login)。恒久フォールバックへ。" >&2
    exit "$EX_UNAVAIL"
  fi
fi

if [ "$CODEX_EXIT" -ne 0 ]; then
  write_record "failed" "$SUMMARY" "$ERR3" ""
  emit "failed" "$EX_FAIL"
  untrusted_block "委託先ログ末尾(エラー)" "$ERR3" >&2
  exit "$EX_FAIL"
fi

if [ "$MODE" = "impl" ]; then
  # 報告フォーマット(AGENTS.md §7)の判定行。複数あれば最後のものを採る。
  # 全角コロンと箇条書きの接頭辞も拾う。日本語で書かせている以上、Codex が
  # 「判断待ち:」を全角や「- 判断待ち:」で返すことは十分ありうる。ここで
  # 取りこぼすと、正しく停止した判断待ち(差分が無いのが正常)が下の
  # 成果実在確認に落ちて exit 2 に化ける。
  VERDICT="$(grep -hE '^[[:space:]]*([-*+][[:space:]]*)?(\*\*)?(完了|判断待ち|失敗)(\*\*)?[:：]' "$LAST" 2>/dev/null | tail -1)"

  case "$VERDICT" in
    *判断待ち*)
      write_record "blocked" "$SUMMARY" "" ""
      emit "blocked" "$EX_BLOCKED"
      untrusted_block "委託先サマリー(判断待ち)" "$SUMMARY"
      exit "$EX_BLOCKED"
      ;;
    *失敗*)
      write_record "failed" "$SUMMARY" "" ""
      emit "failed" "$EX_FAIL"
      untrusted_block "委託先サマリー(失敗)" "$SUMMARY"
      exit "$EX_FAIL"
      ;;
  esac

  # ---- 成果の実在確認 ----
  # codex exec の exit 0 は「ターンが完了した」であってタスクの成否ではない
  # (段階0 の実測)。何も動いていない委託を検収に回さない。
  # 空振り条件: Codex が判定行を書かずに何かを 1 バイトでも変更した場合、
  # ここは通る。そのときの防衛線は司令塔の検収(code-reviewer + test-runner)。
  TREE_AFTER="$(tree_snapshot)"
  HEAD_AFTER="$(git rev-parse HEAD 2>/dev/null || echo none)"
  DONE_AFTER="$(count_done)"

  if [ "$TREE_AFTER" = "$TREE_BEFORE" ] &&
    [ "$HEAD_AFTER" = "$HEAD_BEFORE" ] &&
    [ "$DONE_AFTER" -le "$DONE_BEFORE" ]; then
    write_record "failed" "$SUMMARY" "exit 0 だが成果物が確認できない(作業ツリー・HEAD・tasklist のいずれも変化なし)" ""
    emit "failed" "$EX_FAIL"
    cat >&2 <<'MSG'
delegate-codex: Codex は正常終了しましたが、成果物が確認できません。
作業ツリー・HEAD・tasklist の進捗がいずれも変化していないため、失敗として扱います。
生ログで原因(sandbox の起動失敗など)を確認してください。
MSG
    exit "$EX_FAIL"
  fi

  if [ "$DONE_AFTER" -le "$DONE_BEFORE" ]; then
    SUMMARY="$SUMMARY

⚠️ tasklist.md の [x] が増えていません(変更はあります)。逐次更新がされていない
可能性があるため、進捗の判断は tasklist ではなく git diff --stat を根拠にしてください。"
  fi
fi

# read-only の委託(explore / review)は検収対象の成果物を残さない。
# サマリーは下の標準出力で司令塔に渡り切っており、あとから accept する対象が無い。
# accepted: false のまま残すと codex-run.sh pending が SessionStart のたびに
# 注入し続け、コンテキストを削るための委託がコンテキストを太らせる(Issue #22)。
ACCEPT_ON_COMPLETE=false
[ "$MODE" = "impl" ] || ACCEPT_ON_COMPLETE=true

write_record "completed" "$SUMMARY" "" "" "$ACCEPT_ON_COMPLETE"
emit "completed" 0
untrusted_block "委託先サマリー" "$SUMMARY"
exit 0
