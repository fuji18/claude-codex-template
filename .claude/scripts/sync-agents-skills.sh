#!/bin/bash
# .claude/skills/ を単一ソースとして、Codex が読む .agents/skills/ を生成する。
#
#   bash .claude/scripts/sync-agents-skills.sh           → 生成(上書き)
#   bash .claude/scripts/sync-agents-skills.sh --check   → 乖離を 1 行ずつ出して exit 1
#   bash .claude/scripts/sync-agents-skills.sh --list    → 対象スキル名を 1 行ずつ出す
#
# 終了コード: 0 = 一致 / 1 = 乖離あり(--check)/ 64 = 使い方の誤り
#
# ── なぜ 2 箇所に要るのか ───────────────────────────────────
# Claude Code がスキルを読むのは .claude/skills/ と ~/.claude/skills/ だけで、
# Codex CLI が読むのは .agents/skills/(とユーザー階層)。同じスキルを両方から
# 使うには、どちらかを正にしてもう一方を機械的に追従させるしかない。
#
# シンボリックリンクでは解決しない。Windows ホスト + Linux devcontainer の構成では
# 片側で解決できず壊れる(実例: Linux 側で張られた node_modules/.bin のリンクを
# Windows の node が辿れず pre-commit が起動不能になった)。
#
# ── 正は .claude/skills/ ────────────────────────────────────
# .agents/ は生成物。直接編集しても次の生成で消える。生成物も git で追跡する
# (Codex は clone 直後のワークツリーから読むため、生成しないと届かない)。
# 乖離は CI(ci.yml の harness-integrity)が --check で機械的に止める。
#
# ── 対象はベンダー中立なスキルだけ ──────────────────────────
# Claude 固有の起動機構(context: fork・subagent・hooks・settings.json)を前提に
# するスキルは Codex で成立しない。description だけを見て選ばれると誤作動するので、
# 下の EXCLUDED で明示的に外す。足し引きはこの 1 箇所だけを直す。
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || exit 1

SRC_DIR=".claude/skills"
DEST_DIR=".agents/skills"
DEST_ROOT=".agents"

# 対象外のスキル(スキル名 — 外す理由)
#   implement-ticket — context: fork / agent: implementer という Claude 固有の起動機構が前提
#   harness-setup    — .claude/agents/ と settings.json・hooks を書き換える司令塔専用の作業
EXCLUDED="implement-ticket harness-setup"

usage() {
  echo "使い方: sync-agents-skills.sh [--check | --list]" >&2
  exit 64
}

MODE="generate"
case "${1:-}" in
  "") ;;
  --check) MODE="check" ;;
  --list) MODE="list" ;;
  *) usage ;;
esac
[ $# -le 1 ] || usage

is_excluded() {
  case " $EXCLUDED " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# 対象スキルに含まれるか。list_skills への `| grep -q` は使わない:
# grep -q が最初の一致で閉じると list_skills が SIGPIPE で落ち、pipefail が
# その 141 をパイプラインの結果にするため「一致したのに非ゼロ」になる(実測)。
is_target() {
  for t in $TARGETS; do
    [ "$t" = "$1" ] && return 0
  done
  return 1
}

# 対象スキル名を 1 行ずつ出す
list_skills() {
  [ -d "$SRC_DIR" ] || return 0
  for d in "$SRC_DIR"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    is_excluded "$name" && continue
    echo "$name"
  done
}

# .agents/README.md の中身(生成物なのでここが単一ソース)
readme_body() {
  cat <<'EOF'
# .agents/

**このディレクトリは生成物です。直接編集しないでください**(次の生成で消えます)。

`.claude/skills/` を単一ソースとして、Codex CLI が読む `.agents/skills/` を機械的に複製したものです。
Claude Code は `.claude/skills/` だけを、Codex CLI は `.agents/skills/` だけを読むため、同じスキルを
両方から使うには一方を正にしてもう一方を追従させる必要があります。

- 生成: `bash .claude/scripts/sync-agents-skills.sh`
- 検査: `bash .claude/scripts/sync-agents-skills.sh --check`(CI の `harness-integrity` が実行する)

スキルを足す・直すときは `.claude/skills/` 側を編集し、生成し直してコミットしてください。
EOF
}

TARGETS="$(list_skills)"

case "$MODE" in
  list)
    printf '%s\n' "$TARGETS"
    ;;

  generate)
    mkdir -p "$DEST_DIR" || exit 1
    # 対象から外れたスキルの残骸を消す(名前の変更・EXCLUDED への追加で発生する)
    if [ -d "$DEST_DIR" ]; then
      for d in "$DEST_DIR"/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        if ! is_target "$name"; then
          rm -rf "$d"
          echo "削除(対象外になったスキル): $DEST_DIR/$name"
        fi
      done
    fi
    for name in $TARGETS; do
      rm -rf "${DEST_DIR:?}/$name"
      cp -R "$SRC_DIR/$name" "$DEST_DIR/$name" || exit 1
    done
    readme_body > "$DEST_ROOT/README.md"
    echo "生成しました: $DEST_DIR($(printf '%s\n' "$TARGETS" | grep -c .) スキル)"
    ;;

  check)
    DRIFT=0
    if [ ! -d "$DEST_DIR" ]; then
      echo "$DEST_DIR が存在しません — bash .claude/scripts/sync-agents-skills.sh を実行してコミットしてください"
      exit 1
    fi
    # 生成されるべきスキルが揃っているか / 中身が一致しているか
    for name in $TARGETS; do
      if [ ! -d "$DEST_DIR/$name" ]; then
        echo "$DEST_DIR/$name が足りません(正: $SRC_DIR/$name)— 生成し直してコミットしてください"
        DRIFT=1
        continue
      fi
      if ! diff -r -q "$SRC_DIR/$name" "$DEST_DIR/$name" > /dev/null 2>&1; then
        echo "$DEST_DIR/$name が $SRC_DIR/$name と一致しません — .claude/skills/ 側を正として生成し直してください"
        DRIFT=1
      fi
    done
    # 正に無いものが残っていないか
    for d in "$DEST_DIR"/*/; do
      [ -d "$d" ] || continue
      name="$(basename "$d")"
      if ! is_target "$name"; then
        echo "$DEST_DIR/$name は対象外です(正に無いか EXCLUDED)— 生成し直して削除してください"
        DRIFT=1
      fi
    done
    if ! readme_body | diff -q - "$DEST_ROOT/README.md" > /dev/null 2>&1; then
      echo "$DEST_ROOT/README.md が生成内容と一致しません — 生成し直してください"
      DRIFT=1
    fi
    exit "$DRIFT"
    ;;
esac
