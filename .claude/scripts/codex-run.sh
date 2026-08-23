#!/bin/bash
# .harness/codex-runs/*.json(run record)の一覧・検収・状態更新。
#
#   .claude/scripts/codex-run.sh list [--all]
#   .claude/scripts/codex-run.sh show <id>
#   .claude/scripts/codex-run.sh accept <id>
#   .claude/scripts/codex-run.sh set-status <id> <status>
#
# §12.6 の回復手順の最後(record の status を実態に合わせて更新し、
# accepted の判定に進む)を成立させる。
#
# 終了コード(delegate-codex.sh の契約とは別系統。取り違えないこと):
#   0 成功
#   1 対象が無い・値が不正
#   2 使い方の誤り
#
# 参照: docs/template-dev/codex-delegation-plan.md §12.6
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$ROOT" ]; then
  echo "codex-run: git リポジトリの外では実行できません" >&2
  exit 2
fi
cd "$ROOT" || exit 2

RUN_DIR=".harness/codex-runs"

usage() {
  cat >&2 <<'USAGE'
使い方: .claude/scripts/codex-run.sh <subcommand> [args]

  list [--all]          未検収(accepted != true)の record を一覧する。--all で全件
  show <id>              record を丸ごと出す
  accept <id>             accepted を true にする
  set-status <id> <status>  status を差し替える
                          (running / completed / blocked / failed /
                           rate-limited / unavailable / interrupted / discarded)
USAGE
}

# $1=json ファイル $2=キー名。無い/null は空文字列を返す。
# delegate-codex.sh と同一の実装(2 箇所・十数行のため共有ファイルは作らない)。
rec_field() {
  local _out=""
  if command -v jq >/dev/null 2>&1; then
    # `// empty` は false も捨ててしまう(accepted: false が「キー無し」と
    # 区別できなくなり sed 経路と食い違う)。null のときだけ空を返す。
    _out="$(jq -r --arg k "$2" '.[$k] | if . == null then empty else . end' "$1" 2>/dev/null)"
  else
    # クォートされていない値(pid 等)では `[^"]*` が末尾のカンマまで飲み込む。
    # 剥がさないと pid が "82711," になり kill -0 が必ず失敗する。
    _out="$(sed -n "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\},\{0,1\}[[:space:]]*$/\1/p" "$1" | head -1)"
    _out="${_out%"${_out##*[![:space:]]}"}"
    _out="${_out%,}"
    _out="${_out%"${_out##*[![:space:]]}"}"
  fi
  [ "$_out" = "null" ] && _out=""
  printf '%s' "$_out"
}

find_record() {
  local _id="$1" _f
  # id は record のファイル名になる。/ や .. を含むものは受け付けない
  # (RUN_DIR の外の .json を読み書きできてしまうため)。
  case "$_id" in
    '' | */* | *..*) return 1 ;;
  esac
  [ -d "$RUN_DIR" ] || return 1
  _f="$RUN_DIR/$_id.json"
  [ -f "$_f" ] || return 1
  printf '%s' "$_f"
}

cmd_list() {
  local _all="${1:-}"
  local _found=0
  local _f _id _mode _status _branch _accepted _steering _target _pid _cur_branch _line

  [ -d "$RUN_DIR" ] || {
    echo "未検収の Codex 委託はありません"
    exit 0
  }

  _cur_branch="$(git branch --show-current 2>/dev/null || true)"

  for _f in "$RUN_DIR"/*.json; do
    [ -f "$_f" ] || continue
    _accepted="$(rec_field "$_f" accepted)"
    if [ "$_all" != "--all" ] && [ "$_accepted" = "true" ]; then
      continue
    fi
    _found=1
    _id="$(rec_field "$_f" id)"
    _mode="$(rec_field "$_f" mode)"
    _status="$(rec_field "$_f" status)"
    _branch="$(rec_field "$_f" branch)"
    _steering="$(rec_field "$_f" steering)"
    _target="$(rec_field "$_f" target)"

    if [ "$_status" = "running" ]; then
      _pid="$(rec_field "$_f" pid)"
      if [ -z "$_pid" ] || ! kill -0 "$_pid" 2>/dev/null; then
        _status="running(プロセス不在)"
      fi
    fi

    _line="$_id  mode=$_mode  status=$_status  branch=$_branch  accepted=$_accepted  ${_steering:-$_target}"
    if [ -n "$_branch" ] && [ -n "$_cur_branch" ] && [ "$_branch" != "$_cur_branch" ]; then
      _line="$_line [別ブランチ]"
    fi
    echo "$_line"
  done

  if [ "$_found" -eq 0 ]; then
    echo "未検収の Codex 委託はありません"
  fi
  exit 0
}

cmd_show() {
  local _id="${1:-}" _f
  if [ -z "$_id" ]; then
    echo "codex-run: show には id が必要です" >&2
    exit 2
  fi
  _f="$(find_record "$_id")" || {
    echo "codex-run: record が見つかりません: $_id" >&2
    exit 1
  }
  cat "$_f"
  exit 0
}

# $1=file $2=key $3=raw-json-value $4=trailing-comma(既定 ",")
write_field() {
  local _file="$1" _key="$2" _val="$3" _comma="${4-,}"
  local _tmp="$_file.tmp.$$"
  local _bak="$_file.bak"

  if command -v jq >/dev/null 2>&1; then
    jq --argjson v "$_val" --arg k "$_key" '.[$k] = $v' "$_file" >"$_tmp" 2>/dev/null || {
      rm -f "$_tmp"
      return 1
    }
  else
    sed "s|^\([[:space:]]*\"$_key\"[[:space:]]*:[[:space:]]*\).*\$|\1$_val$_comma|" "$_file" >"$_tmp" || {
      rm -f "$_tmp"
      return 1
    }
  fi

  cp "$_file" "$_bak"
  mv "$_tmp" "$_file"

  # 妥当性確認。jq があれば本物のパーサで見る。無い環境でも「無検査で
  # バックアップを捨てる」のは避ける — sed 経路こそ壊れる余地が大きい。
  # 括弧の対応までは見ないが、丸ごと空・先頭/末尾が壊れた・キーが消えた、
  # という壊れ方はここで捕まえて復元できる。
  if command -v jq >/dev/null 2>&1; then
    if ! jq -e . "$_file" >/dev/null 2>&1; then
      mv "$_bak" "$_file"
      return 1
    fi
  else
    if [ ! -s "$_file" ] ||
      ! head -1 "$_file" | grep -q '^[[:space:]]*{' ||
      ! tail -1 "$_file" | grep -q '^[[:space:]]*}' ||
      ! grep -q "\"$_key\"[[:space:]]*:" "$_file"; then
      mv "$_bak" "$_file"
      return 1
    fi
  fi
  rm -f "$_bak"
  return 0
}

cmd_accept() {
  local _id="${1:-}" _f
  if [ -z "$_id" ]; then
    echo "codex-run: accept には id が必要です" >&2
    exit 2
  fi
  _f="$(find_record "$_id")" || {
    echo "codex-run: record が見つかりません: $_id" >&2
    exit 1
  }
  # accepted は write_record が書く JSON の最後のフィールド。
  # sed 経路は末尾カンマを常に付けるため、末尾フィールドではカンマ無しにする。
  if ! write_field "$_f" accepted true ""; then
    echo "codex-run: record の更新に失敗しました(JSON が壊れている可能性): $_f" >&2
    exit 1
  fi
  echo "accepted: $_id"
  exit 0
}

cmd_set_status() {
  local _id="${1:-}" _new="${2:-}" _f
  local _valid="running completed blocked failed rate-limited unavailable interrupted discarded"

  if [ -z "$_id" ] || [ -z "$_new" ]; then
    echo "codex-run: set-status には id と status が必要です" >&2
    exit 2
  fi

  case " $_valid " in
    *" $_new "*) ;;
    *)
      echo "codex-run: 不正な status です: $_new(有効値: $_valid)" >&2
      exit 1
      ;;
  esac

  _f="$(find_record "$_id")" || {
    echo "codex-run: record が見つかりません: $_id" >&2
    exit 1
  }

  if ! write_field "$_f" status "\"$_new\""; then
    echo "codex-run: record の更新に失敗しました(JSON が壊れている可能性): $_f" >&2
    exit 1
  fi
  echo "status=$_new: $_id"
  exit 0
}

SUBCOMMAND="${1:-}"
[ $# -ge 1 ] && shift

case "$SUBCOMMAND" in
  list) cmd_list "${1:-}" ;;
  show) cmd_show "${1:-}" ;;
  accept) cmd_accept "${1:-}" ;;
  set-status) cmd_set_status "${1:-}" "${2:-}" ;;
  *)
    usage
    exit 2
    ;;
esac
