#!/bin/bash
# ベンダー非依存ガードレール(.husky/* → check-protected-branch.sh)が生きているかを検査する。
#
# 呼び出し元:
#   - .claude/hooks/session-start.sh … 早期警告(Claude セッション開始時)
#   - .github/workflows/ci.yml       … 最終検証(クライアント非依存・Claude を一度も起動しなくても効く)
#   - .claude/rules/mode/degraded.md … モード C 復帰時の検収(degraded サブコマンド)
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
# 引数なし … 既存の自壊検知(SessionStart hook / CI の harness-integrity が呼ぶ)
# degraded … 上記に加えて、モード C(縮退)復帰時のガードレール健全性検査
#
# 分けている理由はコストではなく誤検知。縮退検査は「作業ツリーの .git と縮退中コミット」を
# 見る検査で、CI の fresh checkout では core.hooksPath が未設定・.git/hooks/ が sample だけ
# なのが正常。既定に混ぜると harness-integrity ジョブが恒常的に赤くなる。
SUBCOMMAND="${1:-default}"
case "$SUBCOMMAND" in
  default | degraded) ;;
  *)
    echo "使い方: check-guard-integrity.sh [degraded]" >&2
    exit 2
    ;;
esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] && cd "$ROOT" 2>/dev/null

GUARD=".claude/scripts/check-protected-branch.sh"
POLICY=".claude/branch-policy.json"

FOUND=0
note() { echo "$1"; FOUND=1; }

# --- 1) 単一ソースの空洞化 ---
# 保護ブランチ検査の全層(PreToolUse hook / .husky/* / CI の branch-policy ジョブ)は
# いずれも protectedBranches という同じ配列を読む。ここが空になると全層が同時に、
# かつ「正常に動作したうえで素通し」という形で無効化される。層の数では防げない唯一の経路。
if [ -f "$POLICY" ] && command -v jq >/dev/null 2>&1; then
  jq -e '(.protectedBranches // []) | length > 0' "$POLICY" >/dev/null 2>&1 ||
    note "$POLICY の protectedBranches が空。保護ブランチ検査が全層(PreToolUse / .husky/* / CI)で素通しになる"
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
# 値を .husky と決め打ちで比較しない。husky v9 が設定するのは .husky/_。
# 空・実在しないディレクトリ・.husky 配下以外は、いずれも「git hook 層が無い」状態。
if [ "$USES_HUSKY" = yes ]; then
  HOOKS_PATH="$(git config --get core.hooksPath 2>/dev/null || true)"
  if [ -z "$HOOKS_PATH" ]; then
    note "core.hooksPath が未設定。.husky/ のフックが一切動かない(npm ci での有効化漏れか、縮退中の書き換えを疑う)"
  elif [ ! -d "$HOOKS_PATH" ]; then
    note "core.hooksPath が実在しないディレクトリ($HOOKS_PATH)を指している。git hook 層が無効になっている"
  else
    case "$HOOKS_PATH" in
      .husky | .husky/*) ;;
      *) note "core.hooksPath が .husky 配下以外($HOOKS_PATH)を指している。ベンダー非依存の git hook 層が迂回されている" ;;
    esac
  fi
fi

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

exit "$FOUND"
