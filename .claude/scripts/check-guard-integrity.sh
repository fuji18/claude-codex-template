#!/bin/bash
# ベンダー非依存ガードレール(.husky/* → check-protected-branch.sh)が生きているかを検査する。
#
# 呼び出し元:
#   - .claude/hooks/session-start.sh … 早期警告(Claude セッション開始時)
#   - .github/workflows/ci.yml       … 最終検証(クライアント非依存・Claude を一度も起動しなくても効く)
#   - .claude/rules/mode/degraded.md … モード C 復帰時の検収(degraded サブコマンド)
#   - .claude/scripts/delegate-codex.sh … impl 入口検査 5-3(hooks-path サブコマンド)
#
# 両者で判定がずれないよう、実体はこのファイルだけに置く
# (check-protected-branch.sh / latest-steering.sh と同じ思想)。
#
# 出力: 壊れている項目を 1 行ずつ標準出力へ。装飾(⚠️ / ::error::)は呼び出し側の責任。
# 終了コード:
#   0 … 健全(または検査対象外の構成)
#   1 … 壊れている項目がある
#   2 … 使い方の誤り(未知のサブコマンド)
set -uo pipefail

# ---------- サブコマンド ----------
#
# 引数なし   … 既存の自壊検知(SessionStart hook / CI の harness-integrity が呼ぶ)
# degraded   … 上記に加えて、モード C(縮退)復帰時のガードレール健全性検査
# hooks-path … core.hooksPath の判定だけを行う(delegate-codex.sh 入口検査 5-3 が呼ぶ)。
#              5-3 が独自に「空 or 実在しない」だけを見ていたため D1 より緩く、実在する
#              無関係なディレクトリを素通ししていた(#59)。判定の実体をここに集約する。
#
# 分けている理由はコストではなく誤検知。縮退検査は「作業ツリーの .git と縮退中コミット」を
# 見る検査で、CI の fresh checkout では core.hooksPath が未設定・.git/hooks/ が sample だけ
# なのが正常。既定に混ぜると harness-integrity ジョブが恒常的に赤くなる。
SUBCOMMAND="${1:-default}"
case "$SUBCOMMAND" in
  default | degraded | hooks-path) ;;
  *)
    echo "使い方: check-guard-integrity.sh [degraded|hooks-path]" >&2
    exit 2
    ;;
esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] && cd "$ROOT" 2>/dev/null

GUARD=".claude/scripts/check-protected-branch.sh"
POLICY=".claude/branch-policy.json"

FOUND=0
note() { echo "$1"; FOUND=1; }

# core.hooksPath が husky を指しているかの判定の実体。
#
# 呼び出し元は 2 つあり、同じ結果になることが要件(#59):
#   - 下の D1(degraded サブコマンド)      … モード C 復帰時の検収
#   - hooks-path サブコマンド              … delegate-codex.sh 入口検査 5-3
# かつては 5-3 が「空 or 実在しないディレクトリ」だけを見ており、実在する無関係な
# ディレクトリを指す core.hooksPath を素通ししていた。
#
# 値を .husky と決め打ちで比較しない。husky v9 が設定するのは .husky/_。
# 空・実在しないディレクトリ・.husky 配下以外は、いずれも「git hook 層が無い」状態。
#
# husky を使う構成かどうかのガードは呼び出し側ではなくこの中に置く。外に出すと
# 呼び出し元ごとに条件がずれ、このチケットが潰した分散をそのまま再生産する。
# USES_HUSKY を参照するため、その決定より後にだけ呼ぶこと。
#
# 比較は前方一致で行い、絶対パスの正規化はしない。husky v9 が設定するのは常に相対パス
# (.husky/_)で、絶対パスになる正規の経路が無い。仮に絶対パスが設定されていれば
# 「.husky 配下以外」と報告するが、倒れる先は安全側(5-3 は exit 3 で委託を止めるだけ)。
# realpath による正規化は可搬性とシンボリックリンクの分岐を増やすので入れない(#59)。
check_hooks_path() {
  [ "$USES_HUSKY" = yes ] || return 0

  local _hooks_path
  _hooks_path="$(git config --get core.hooksPath 2>/dev/null || true)"
  if [ -z "$_hooks_path" ]; then
    note "core.hooksPath が未設定。.husky/ のフックが一切動かない(npm ci での有効化漏れか、縮退中の書き換えを疑う)"
  elif [ ! -d "$_hooks_path" ]; then
    note "core.hooksPath が実在しないディレクトリ($_hooks_path)を指している。git hook 層が無効になっている"
  else
    case "$_hooks_path" in
      .husky | .husky/*) ;;
      *) note "core.hooksPath が .husky 配下以外($_hooks_path)を指している。ベンダー非依存の git hook 層が迂回されている" ;;
    esac
  fi
}

# --- 1) 単一ソースの空洞化 ---
# 保護ブランチ検査の全層(PreToolUse hook / .husky/* / CI の branch-policy ジョブ)は
# いずれも protectedBranches という同じ配列を読む。ここが空になると全層が同時に、
# かつ「正常に動作したうえで素通し」という形で無効化される。層の数では防げない唯一の経路。
#
# 「空」以外にも、全層が正常動作したまま保護が消える書き換えが 2 つある(#59)。
# #56 で branch-policy.json を委託禁止領域に入れて委託経路は塞いだが、人間の手による
# 誤編集には効かないため機械的に検出する。スキーマ検証一般には広げない —
# 「保護が空洞化する」パターンだけに絞る。
#
# hooks-path サブコマンドでは回さない。5-3 は標準出力をそのままエラーメッセージに
# 載せるため、ポリシーの指摘が混ざると「git hook が無効」という説明と食い違う。
if [ "$SUBCOMMAND" != hooks-path ] && [ -f "$POLICY" ] && command -v jq >/dev/null 2>&1; then
  if ! jq -e '(.protectedBranches // []) | length > 0' "$POLICY" >/dev/null 2>&1; then
    note "$POLICY の protectedBranches が空。保護ブランチ検査が全層(PreToolUse / .husky/* / CI)で素通しになる"
  else
    # 1-a) baseBranch が保護されているか。
    # baseBranch は PR のマージ先 = 成果物が積まれる幹。ここが protectedBranches に
    # 無いと、check-protected-branch.sh は「保護ブランチではない」と正しく判定した
    # うえで直接コミットを通す。protectedBranches を ["develop"] に差し替える改変が
    # 典型で、全層が緑のまま main への直コミットが解禁される。
    # protectedBranches が空のときは上の指摘で足りるので else 側でだけ見る。
    _base="$(jq -r '.baseBranch // "main"' "$POLICY" 2>/dev/null || echo main)"
    jq -e --arg b "$_base" '(.protectedBranches // []) | index($b)' "$POLICY" >/dev/null 2>&1 ||
      note "$POLICY の baseBranch($_base)が protectedBranches に含まれていない。PR のマージ先が無防備になり、全層が正常動作したまま直接コミットを通す"
  fi

  # 1-b) allowedPrefixes が保護ブランチ名そのものを許可していないか。
  # CI の branch-policy ジョブは PR の head ブランチ名を startswith で照合するため、
  # 保護ブランチ名に前方一致する接頭辞(例: "main"、あるいは空文字列)が 1 つでも
  # 入ると、保護ブランチから出した PR がブランチ名検査を通過する。
  # CI と同じ演算(startswith)で見る。完全一致だけを見ると "mai" や "" を取り逃す。
  while IFS="$(printf '\t')" read -r _pb _ap; do
    [ -n "$_pb" ] || continue
    note "$POLICY の allowedPrefixes に保護ブランチ '$_pb' へ前方一致する接頭辞 '${_ap}' がある。保護ブランチから出した PR が CI の branch-policy のブランチ名検査を通過する"
  done < <(jq -r '(.allowedPrefixes // []) as $ap | (.protectedBranches // [])[] | . as $b | $ap[] | . as $prefix | select($b | startswith($prefix)) | "\($b)\t\($prefix)"' "$POLICY" 2>/dev/null)
fi

# --- 2) husky を使う構成か ---
# テンプレートはスタック非依存なので、husky を持たない構成(Python / Go 等)では
# git hook 層の検査自体を行わない。ただし判定を「.husky/ があるか」だけにしてはいけない:
# フックごと消えると検査がスキップされ、層が完全消滅した最悪のケースが最も静かに通る。
# package.json の依存も見て「husky を使うはずの構成なのにフックが無い」を検知する。
USES_HUSKY=no
[ -d .husky ] && USES_HUSKY=yes
if [ "$USES_HUSKY" = no ] && [ -f package.json ] && command -v jq >/dev/null 2>&1; then
  jq -e '(.devDependencies.husky // .dependencies.husky) != null' package.json >/dev/null 2>&1 && USES_HUSKY=yes
fi
if [ "$USES_HUSKY" = no ] && [ "$SUBCOMMAND" != degraded ]; then
  exit "$FOUND"
fi

# --- 2.5) hooks-path サブコマンドはここで終わる ---
# 見るのは core.hooksPath だけ。呼び出し元(入口検査 5-3)は「git hook が有効か」を
# 判定したいのであって、.husky/pre-commit の中身(検査 3・4)は関知しない。
# 混ぜると 5-3 が本来の理由と違う指摘で exit 3 を返す。
if [ "$SUBCOMMAND" = hooks-path ]; then
  check_hooks_path
  exit "$FOUND"
fi

if [ "$USES_HUSKY" = yes ]; then
  # --- 3) 判定の実体があるか ---
  [ -f "$GUARD" ] ||
    note "$GUARD が存在しない。保護ブランチへの直接コミットを止めるベンダー非依存の層(Codex・手動 git に効く唯一の層)が失われている"

  # --- 4) 各フックが実際に呼んでいるか ---
  # 呼び出しとみなすのは「コメントでない行」からの bash / sh / source 起動だけ。
  # 単なる文字列一致だと、呼び出し行をコメントアウトしても検査が通ってしまう
  # (説明コメントにファイル名が出てくるだけで緑になる)。
  INVOKE_RE='^[^#]*(bash|sh|source|\.)[[:space:]]+"?(\$GUARD|[^"]*check-protected-branch\.sh)"?'

  # pre-commit         … git commit / git commit --amend
  # prepare-commit-msg … git revert / git cherry-pick(pre-commit は発火しない)
  for h in pre-commit prepare-commit-msg; do
    case "$h" in
      pre-commit) covers="git commit / git commit --amend" ;;
      *)          covers="git revert / git cherry-pick" ;;
    esac
    if [ ! -f ".husky/$h" ]; then
      note ".husky/$h が存在しない。保護ブランチ上の $covers が素通しになる"
    elif ! grep -qE "$INVOKE_RE" ".husky/$h"; then
      note ".husky/$h が $GUARD を呼んでいない(呼び出しがコメントアウトされている可能性)。保護ブランチ上の $covers が素通しになる"
    fi
  done
fi

[ "$SUBCOMMAND" = degraded ] || exit "$FOUND"

# ============================================================
# 以下はモード C(縮退)復帰時の検査(degraded サブコマンドのみ)
# ============================================================
#
# 縮退モードは delegate-codex.sh を通らない唯一の経路で、入口検査も出口検査も掛からない。
# さらに .git を writable_roots に渡す設計のため、委託先自身が husky 層を無効化できる。
# 復帰時の検収でここを機械的に確かめる(根拠: docs/template-dev/codex-delegation-plan.md §2.3)。

# --- D1) core.hooksPath が husky を指しているか ---
#
# 判定の実体は上の check_hooks_path()。hooks-path サブコマンド(= delegate-codex.sh
# 入口検査 5-3)と同じ関数を通ることが要件(#59)。
check_hooks_path

# --- D2) .git/hooks/ に直書きされたフックが無いか ---
#
# core.hooksPath が .husky/_ を指している間 .git/hooks/ は参照されないが、hooksPath を
# 戻す 1 行と組み合わせれば有効になる。置かれていること自体を異常として扱う。
# git 同梱の *.sample と、実行権の無いファイルは除く。
#
# `git rev-parse --git-path hooks` は使わない — これは core.hooksPath を尊重して
# その値をそのまま返すため、hooksPath が .husky/_ を指す健全な状態でも
# 「.husky/_ 配下の正規フックが直書きされている」という誤検知になる(実測)。
# 常に物理的な .git/hooks/ を見るために --git-dir から手で組み立てる。
GIT_DIR="$(git rev-parse --git-dir 2>/dev/null || true)"
GIT_HOOKS_DIR=""
[ -n "$GIT_DIR" ] && GIT_HOOKS_DIR="$GIT_DIR/hooks"
if [ -n "$GIT_HOOKS_DIR" ] && [ -d "$GIT_HOOKS_DIR" ]; then
  while IFS= read -r _h; do
    [ -n "$_h" ] || continue
    note "$_h が直書きされている(git 同梱の *.sample 以外の実行可能フック)。core.hooksPath を戻すだけで .husky/ を迂回できる状態"
  done < <(find "$GIT_HOOKS_DIR" -maxdepth 1 -type f -perm -u+x ! -name '*.sample' 2>/dev/null | LC_ALL=C sort)
fi

# --- D2.5) .git/config にホストコマンド実行ベクタが仕込まれていないか ---
#
# 縮退モードは .git を writable_roots に渡す = .git/config を丸ごと書ける唯一の経路。
# D1 は core.hooksPath という 1 キーしか見ないが、config には「次に人間や Claude が git を
# 叩いた瞬間にホストコマンドを実行する」キーが他にもある。とくに core.fsmonitor は
# git status で発火するため、復帰検収(D1〜D3)より先に走り得る。
#
# 倒し方は D1/D2 と同じ「報告のみ」。対象キーには正当な用途もあるため停止はしない
# (この検査はセキュリティ境界ではなく検出と報告。docs/template-dev/codex-delegation-plan.md §2.3)。
#
# 検査範囲はローカル設定のみ。縮退中の Codex が書けるのがローカルだけであることに加え、
# devcontainer は --global / --system に credential.helper の `!` 形式を既定で置いており、
# 混ぜると平常運用で必ず誤爆する(実測)。
#
# 対象キーは網羅リストではなく、.git/config 単体で完結する既知の主要ベクタに絞った閉リスト。
# 増減は設計判断(.steering/20260831-issue58-git-config-vectors/design.md 判断4)を経由すること。
#
# alias.* は `!` 形式(shell 実行)だけを対象にする。git は組み込みサブコマンドを上書きする
# エイリアスを無視するため(実測: alias.status に `!` 形式を仕込んでも git status は本来の動作)、
# `!` の無いエイリアスは既存コマンドの乗っ取り経路にならない。
#
# 値は改行を含み得るので -z(NUL 区切りの key\nvalue)で読む。改行区切りだと 1 レコードが割れる。
while IFS= read -r -d '' _rec; do
  [ -n "$_rec" ] || continue
  _key="${_rec%%$'\n'*}"
  case "$_rec" in
    *$'\n'*) _val="${_rec#*$'\n'}" ;;
    *) _val="" ;;
  esac

  _why=""
  case "$_key" in
    core.fsmonitor) _why="git status 等のたびに実行される" ;;
    core.sshcommand) _why="push / fetch のたびに実行される" ;;
    core.pager) _why="log / diff 等のたびに実行される" ;;
    credential.helper | credential.*.helper) _why="push / fetch の認証時に実行される" ;;
    filter.*.clean | filter.*.smudge) _why="add / checkout のたびに実行される" ;;
    include.path | includeif.*.path) _why="別ファイルの設定を取り込む(実行ベクタの間接注入)" ;;
    core.editor | sequence.editor) _why="git commit(-m 無し)/ rebase -i のときに実行される" ;;
    core.gitproxy) _why="プロキシ経由の接続時に実行される" ;;
    url.*.insteadof | url.*.pushinsteadof) _why="fetch / push / clone の URL を書き換える(ext::sh 形式でコマンド実行になり得る)" ;;
    diff.*.command) _why="git diff のたびに実行される(.gitattributes 経由)" ;;
    merge.*.driver) _why="マージ解決のたびに実行される(.gitattributes 経由)" ;;
    alias.*)
      case "$_val" in
        '!'*) _why="git <alias> 実行時に shell が走る" ;;
      esac
      ;;
  esac
  [ -n "$_why" ] || continue

  _shown="${_val%%$'\n'*}"
  [ "${#_shown}" -le 120 ] || _shown="${_shown:0:120}…"
  note ".git/config(local)に $_key=$_shown が設定されている($_why)。縮退中に仕込まれたものでないか値を確認すること"
done < <(git config --local --list -z 2>/dev/null)

# --- D3) 縮退中コミットの差分が委託禁止領域に触れていないか ---
#
# 縮退中のコミットは Codex-authored トレーラーで自分を名乗る(.codex/skills/
# degraded-mode-ticket/SKILL.md §3)。禁止領域の一覧は delegate-codex.sh が単一ソースで、
# --print-forbidden から受け取る(配列を複製しない)。
#
# 検査範囲: 既定は branch-policy.json の baseBranch(origin/ 付きを優先)から HEAD まで。
# ベースが解決できないときは HEAD の全履歴を見る(実測 0.185s / 84 コミット)。
# GUARD_DEGRADED_RANGE で上書きできる(再現テスト用)。
DELEGATE=".claude/scripts/delegate-codex.sh"

DEGRADED_RANGE="${GUARD_DEGRADED_RANGE:-}"
if [ -z "$DEGRADED_RANGE" ]; then
  BASE=""
  if [ -f "$POLICY" ] && command -v jq >/dev/null 2>&1; then
    BASE="$(jq -r '.baseBranch // empty' "$POLICY" 2>/dev/null || true)"
  fi
  if [ -n "$BASE" ]; then
    for _ref in "origin/$BASE" "$BASE"; do
      if git rev-parse --verify --quiet "$_ref" >/dev/null 2>&1; then
        DEGRADED_RANGE="$_ref..HEAD"
        break
      fi
    done
  fi
  [ -n "$DEGRADED_RANGE" ] || DEGRADED_RANGE="HEAD"
fi

FORBIDDEN_LIST=""
if [ -f "$DELEGATE" ]; then
  FORBIDDEN_LIST="$(bash "$DELEGATE" --print-forbidden 2>/dev/null || true)"
fi

if [ -z "$FORBIDDEN_LIST" ]; then
  note "$DELEGATE --print-forbidden が委託禁止領域を返さない。縮退中コミットの差分検査が行えない"
else
  # 一覧の各行を Codex-authored コミットの変更パスに当てる。
  # 末尾 /** /* /  はディレクトリ配下すべて、それ以外は完全一致(delegate-codex.sh の
  # forbidden_files() と同じ解釈)。
  is_forbidden() {
    local _path="$1" _p _d
    while IFS= read -r _p; do
      [ -n "$_p" ] || continue
      case "$_p" in
        */\*\* | */\*)
          _d="${_p%/*}"
          case "$_path" in "$_d"/*) return 0 ;; esac
          ;;
        */) case "$_path" in "$_p"*) return 0 ;; esac ;;
        *) [ "$_path" = "$_p" ] && return 0 ;;
      esac
    done <<EOF_FORBIDDEN
$FORBIDDEN_LIST
EOF_FORBIDDEN
    return 1
  }

  while IFS= read -r _sha; do
    [ -n "$_sha" ] || continue
    while IFS= read -r _f; do
      [ -n "$_f" ] || continue
      is_forbidden "$_f" &&
        note "縮退中のコミット $_sha が委託禁止領域 $_f を変更している。マージ前に内容を確認すること(delegate-codex.sh の出口検査が掛かっていない経路)"
    done < <(git show --pretty=format: --name-only "$_sha" 2>/dev/null)
  done < <(git log --grep='Codex-authored' --format='%h' "$DEGRADED_RANGE" 2>/dev/null)
fi

# --- D4) 縮退中コミットが package.json を変更していないか ---
#
# モード C は delegate-codex.sh を通らないため、出口検査の同種の警告
# (scripts / lint-staged / prepare の差分)が 1 度も走らない。ここが唯一の層になる。
#
# 判定は「Codex-authored コミットが package.json を変更したか」までで、節の中身までは
# 見ない。このスクリプトは jq を必須にしていないうえ、報告先の人間はどのみち
# git diff を読む必要があるため。D1/D2/D3 と同じく報告のみで停止しない。
#
# git log を D3 と重複して回しているのは意図的。共有化には D3 のループ本体を書き換える
# 必要があり、実測 0.185s / 84 コミットに対して security-critical な差分を広げる方が高い。
while IFS= read -r _sha; do
  [ -n "$_sha" ] || continue
  if git show --pretty=format: --name-only "$_sha" 2>/dev/null | grep -Fxq 'package.json'; then
    note "縮退中のコミット $_sha が package.json を変更している。scripts / lint-staged / prepare に差分が無いか git diff で確認すること(検収でホスト上・ネットワーク有効で実行される。codex-delegation-plan.md §9)"
  fi
done < <(git log --grep='Codex-authored' --format='%h' "$DEGRADED_RANGE" 2>/dev/null)

exit "$FOUND"
