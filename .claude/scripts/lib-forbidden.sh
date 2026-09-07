# shellcheck shell=bash
# 委託禁止領域の単一ソース(汎用項目)と、出口検査が使う判定ヘルパー。
#
# **source 専用。** 実行ビットは付けない(shebang も付けない)。
# 命名規約: .claude/scripts/lib-*.sh は source 専用。CI(ci.yml の harness-integrity)と
# SessionStart hook が、この名前のファイルに **実行ビットが無いこと・shebang が無いこと**
# を機械検査する(#45 §10)。単体で起動する実体を lib- で始まる名前にしないこと。
# 利用側: .claude/scripts/delegate-codex.sh
#
# **source した瞬間に走るコードを含む**(PROJECT_FORBIDDEN_PATHS の抽出)。呼び出し側は
#   1) 入口検査0(find / grep / sed の存在確認)を通し、2) $AGENTS を代入してから
# source すること。source 位置の前後関係が防御の一部になっている理由は
# delegate-codex.sh 側の該当ブロックのコメントに書いてある(#86)。
#
# forbidden_files() は $RUN_DIR / $REC / $LOG / $LAST を**呼び出し時**に読む。定義は
# ここでよいが、呼ぶのは run record を組み立てた後(delegate-codex.sh の「事前
# スナップショット」以降)であること。
#
# フェイル方針: **呼び出し側でフェイルクローズ**(理由は delegate-codex.sh の source 位置)。
#
# 委託禁止領域に入るか: 入る。FORBIDDEN_PATHS の ".claude/scripts/" がディレクトリ単位
# なので(#40)、このファイルは追加作業なしで出口検査・縮退検査の対象になる。
#
# 実行中の書き換えハザード: delegate-codex.sh は起動直後に自身と lib-*.sh を一時
# ディレクトリへコピーして exec する(#15 / #86)。委託中に元ファイルが書き換わっても、
# 走っているプロセスが読む定義は変わらない。

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
#   1. 実行される実体      … scripts/ hooks/ settings.json settings.local.json .husky/ .github/workflows/
#   2. 注入される実体      … rules/ CLAUDE.md AGENTS.md .mcp.json
#   3. 全層が読む判定データ … branch-policy.json
# rules/ をディレクトリ単位にしたのは scripts/ と同じ理由。lead/ と mode/ だけを個別列挙すると
# CLAUDE.md 経由で全サブエージェントに載る spec-driven.md が漏れ、ファイルが増えるたびに
# 同じ漏れを繰り返す。rules/ への正当な追記はもともと司令塔の仕事(context-management.md
# 「ルールを追記するときの置き場所」)なので、委託の余地はほぼ狭まらない。
#
# .husky/ をディレクトリ単位にしたのも同じ理由(Issue #80)。core.hooksPath が指すのは
# .husky/_ で、git が実際に起動するのは .husky/_/pre-commit → .husky/_/h → sh -e
# ".husky/pre-commit" の順。守られていた .husky/pre-commit はチェーンの末端でしかなく、
# 入口側の .husky/_/ は .husky/_/.gitignore = "*" で git 追跡外のため、内容ハッシュ方式の
# この検査以外に見る層が無かった。.husky/_/h は人間や Claude が git commit を叩くたびに
# ホスト上・サンドボックス外で走るので、性質は package.json のライフサイクルと同じ。
# .claude/settings.local.json も同系統(gitignore 済み・hooks を定義できる・次のセッション
# 開始時にホストで走る)なので、settings.json と対で持つ。
#
# 末尾が / のものはディレクトリ配下すべてが対象。
#
# 配列末尾の .harness/codex-runs/ は列挙は残すが、出口検査の内容ハッシュ比較
# (forbidden_snapshot() / forbidden_files())の対象からは外してある。検収状態
# (record の accepted / status)は出口検査の record_state_snapshot() が別に見る(#81)。
FORBIDDEN_PATHS=(
  ".claude/scripts/"
  ".claude/hooks/"
  ".claude/settings.json"
  ".claude/settings.local.json"
  ".claude/branch-policy.json"
  ".claude/rules/"
  ".husky/"
  ".claude/codex-denylist.txt"
  "AGENTS.md"
  "CLAUDE.md"
  ".mcp.json"
  ".github/workflows/"
  ".codex/"
  ".harness/mode"
  ".harness/codex-runs/"
)

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

# 禁止領域の実ファイルを列挙する(内容ハッシュ比較 forbidden_snapshot() が使う)。
#
# .harness/codex-runs/ はここでは**列挙しない**(#81)。守りたいのは「委託先が既存
# record の accepted / status を書き換えないこと」= 検収状態であって、ディレクトリが
# 1 バイトも変わらないことではない。内容ハッシュ方式はこの目的に対して過剰で、
# 意図された並行運用(read-only の explore / review は入口検査5 を通らず並行できる)と
# 衝突していた。並行 explore / review が起動時に status=running の record を書き、
# 終了時に record 全体を書き直すだけで、正常に完了した impl がここで「委託禁止領域が
# 変更されました」として failed / exit 2 になっていた(Issue #81 / B1)。
# 検収状態は record_state_snapshot() が別に見る(層が消えたのではなく移った)。
# FORBIDDEN_PATHS の配列自体からは外していない(--print-forbidden の出力・
# CLAUDE.md / AGENTS.md の記述・check-forbidden-paths-doc.sh の照合・5-5b の
# pathspec は現状のまま)。
#
# 今回の委託自身が書く 3 ファイル(run record・生ログ・last message)は当然変わるので
# 除外する。除外しないと全ての impl 委託が必ず違反になる。この除外は末尾の
# grep -Fxv で行っており、上の case の RUN_DIR 除外(第 1 層)を通り抜けて拾われた
# 場合(固有パスに .harness/ のような親ディレクトリが書かれ、find が配下を辿った場合)
# の第 2 層として意味を持つので残す。
forbidden_files() {
  local _p _d
  # 汎用項目(FORBIDDEN_PATHS)と AGENTS.md から抽出したプロジェクト固有パスの両方を見る。
  # 抽出側が空でも汎用項目が必ず走ることを保証しているのは ${arr[@]+"${arr[@]}"} の形
  # (set -u の下で空配列を安全に展開する)であって、配列の並び順ではない。順序は
  # 読みやすさのために「汎用が先」にしてあるだけで、入れ替えても結果は変わらない。
  for _p in "${FORBIDDEN_PATHS[@]}" ${PROJECT_FORBIDDEN_PATHS[@]+"${PROJECT_FORBIDDEN_PATHS[@]}"}; do
    # #81: run record ディレクトリだけはハッシュ比較の対象外(関数上のコメント参照)。
    # 末尾スラッシュの有無を吸収して比較する。AGENTS.md 由来の固有パスに
    # 同じディレクトリが書かれていた場合もここで落ちる。
    case "${_p%/}" in
      "$RUN_DIR") continue ;;
    esac
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
#   1. .harness/mode は .gitignore 済みで git diff にも
#      git ls-files --others --exclude-standard にも出ない
#      (.harness/codex-runs/ も同様に git 追跡外だが、ここでは対象外なので別層
#      record_state_snapshot() が見る。#81)
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
#   - .harness/codex-runs/ は対象外(#81)。検収状態は record_state_snapshot() が見る
forbidden_snapshot() {
  local _f _h _i _batch_ok
  local -a _files=() _hashes=()

  # sort -u なのは重複を畳むため(汎用項目とマーカー内の項目は重なる。ディレクトリ指定と
  # その配下ファイルの二重指定も起こりうる)。重複行が残ると、出口検査の違反抽出
  # (sort | uniq -u)が「2 回現れる行」として違反パスを取りこぼす。
  while IFS= read -r _f; do
    _files+=("$_f")
  done < <(forbidden_files | LC_ALL=C sort -u)
  [ "${#_files[@]}" -gt 0 ] || return 0

  # バッチ化(#65): git hash-object --stdin-paths なら全ファイルを 1 プロセスで畳める。
  # 委託の前後 2 回走り、.harness/codex-runs/ の件数に線形だったプロセス起動が消える。
  # (このディレクトリ自体は #81 で対象外になった。ここの記述は #65 当時の経緯)
  #
  # **フォールバックを必ず残す。** --stdin-paths は 1 ファイルでも失敗すると
  # そこで die して残りを処理しない = 現行の「1 ファイルずつ握りつぶして UNREADABLE」
  # と挙動が変わる。挙動が変わると「改ざんが差分ゼロで通る」側に倒れうるので、
  # **出力行数が入力行数と一致したときだけバッチ結果を採用**し、それ以外は
  # 従来どおり 1 ファイルずつ回す。速い経路は最適化、正しさは従来経路が持つ。
  #
  # 先頭が " のパスをバッチに乗せないのは、git hash-object --stdin-paths が
  # `"` で始まる行を C クォート文字列として unquote するため(別のパスをハッシュしうる)。
  # 該当があればバッチ自体を諦めて 1 ファイルずつに落とす。
  _batch_ok=1
  for _f in "${_files[@]}"; do
    case "$_f" in '"'*) _batch_ok=0; break ;; esac
  done

  if [ "$_batch_ok" = 1 ]; then
    while IFS= read -r _h; do
      _hashes+=("$_h")
    done < <(printf '%s\n' "${_files[@]}" | git hash-object --stdin-paths 2>/dev/null)
    if [ "${#_hashes[@]}" -eq "${#_files[@]}" ]; then
      for _i in "${!_files[@]}"; do
        printf '%s %s\n' "${_hashes[$_i]}" "${_files[$_i]}"
      done
      return 0
    fi
  fi

  # フォールバック: 1 ファイルずつ。失敗は握りつぶして UNREADABLE(前後で同じ扱いになる)。
  for _f in "${_files[@]}"; do
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
