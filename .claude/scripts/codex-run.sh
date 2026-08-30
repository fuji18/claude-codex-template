#!/bin/bash
# .harness/codex-runs/*.json(run record)の一覧・検収・状態更新。
#
#   .claude/scripts/codex-run.sh list [--all]
#   .claude/scripts/codex-run.sh pending
#   .claude/scripts/codex-run.sh show <id>
#   .claude/scripts/codex-run.sh accept <id>
#   .claude/scripts/codex-run.sh set-status <id> <status>
#   .claude/scripts/codex-run.sh prune [--dry-run] [--keep N] [--include-unaccepted]
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
  pending               SessionStart 注入用に未検収 record を整形して出す(無ければ何も出さない)
  show <id>              record を丸ごと出す
  accept <id>             accepted を true にする
  set-status <id> <status>  status を差し替える
                          (running / completed / blocked / failed /
                           rate-limited / unavailable / interrupted / discarded)
  prune [options]       検収済みの古い run record を 3 点セットで削除する
                          --dry-run              消さずに対象を表示する
                          --keep N               新しい順に N 本は残す(既定 20)
                          --include-unaccepted   未検収(accepted != true)も対象にする
                        実行中(status=running かつ pid 生存)は常に残す
USAGE
}

# run record のフィールド読み出し(rec_field)は delegate-codex.sh と共有する(#45)。
# こちらは自己コピー exec を持たないので、リポジトリ内のパスをそのまま読む。
LIB_RECORD="$ROOT/.claude/scripts/lib-record.sh"
if [ ! -f "$LIB_RECORD" ]; then
  echo "codex-run: $LIB_RECORD が見つかりません(run record を読めないため中止します)。" >&2
  exit 2
fi
# shellcheck source=lib-record.sh
. "$LIB_RECORD"

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

# SessionStart hook 用。未検収 record を「現在地」ブロックに貼れる形で出す。
# 見つからなければ**何も出さない**(list と違い「ありません」も出さない。
# 注入先はセッションのコンテキストであり、無い情報に行を使わない)。
cmd_pending() {
  local _f _id _mode _status _branch _steering _target _summary _log _pid _started _ended
  local _cur_branch _now _start_epoch _stale _out="" _count=0

  [ -d "$RUN_DIR" ] || exit 0

  _cur_branch="$(git branch --show-current 2>/dev/null || true)"
  _now="$(date -u +%s 2>/dev/null || echo 0)"

  for _f in "$RUN_DIR"/*.json; do
    [ -f "$_f" ] || continue
    [ "$(rec_field "$_f" accepted)" = "true" ] && continue

    _id="$(rec_field "$_f" id)"
    _mode="$(rec_field "$_f" mode)"
    _status="$(rec_field "$_f" status)"
    _branch="$(rec_field "$_f" branch)"
    _steering="$(rec_field "$_f" steering)"
    _target="$(rec_field "$_f" target)"
    _summary="$(rec_field "$_f" summary)"
    # summary は複数行になりうる(delegate-codex.sh は成果実在確認の警告を
    # 改行込みで追記する)。そのまま出すと 2 行目以降がラベルもインデントも
    # 失った裸の行になり、注入先の「現在地」ブロックの構造が壊れる。
    # 1 行に潰す(情報は落とさない)。
    _summary="$(printf '%s' "$_summary" | tr '\n' ' ')"
    _log="$(rec_field "$_f" log)"
    _started="$(rec_field "$_f" startedAt)"
    _ended="$(rec_field "$_f" endedAt)"

    # status=running は信用しすぎない(§3.4)。スクリプトが終了時に書く値なので、
    # レート上限・OOM・端末切断で殺されると running のまま残る。
    if [ "$_status" = "running" ]; then
      _pid="$(rec_field "$_f" pid)"
      if [ -z "$_pid" ] || ! kill -0 "$_pid" 2>/dev/null; then
        _status="running(プロセス不在 = 異常終了の可能性。tasklist.md と git diff で実態を確認せよ)"
      fi
    fi

    # 7 日以上前の未検収は「古い記録」として調子を落とす(§3.4)。消さずに、
    # 現役の警告と区別する。毎セッション同じ警告が出続けると読まれなくなる。
    # `date -u -d` は GNU date 専用。非 GNU 環境(macOS 等)では _start_epoch が
    # 空になり「古い記録」判定が働かないだけで済む(フェイルセーフ側に倒れる)。
    _stale=0
    if [ "$_now" != "0" ] && [ -n "$_started" ]; then
      _start_epoch="$(date -u -d "$_started" +%s 2>/dev/null || true)"
      if [ -n "$_start_epoch" ] && [ "$((_now - _start_epoch))" -gt 604800 ]; then
        _stale=1
      fi
    fi

    _count=$((_count + 1))
    _out="${_out}  - ${_id} / mode=${_mode} / 対象 ${_steering:-$_target}"
    [ "$_stale" = "1" ] && _out="${_out}(古い記録: 7 日以上前)"
    if [ -n "$_branch" ] && [ -n "$_cur_branch" ] && [ "$_branch" != "$_cur_branch" ]; then
      _out="${_out} [別ブランチ: ${_branch}]"
    fi
    _out="${_out}"$'\n'"    状態: ${_status}${_started:+(${_started}${_ended:+ → ${_ended}})}"$'\n'
    _out="${_out}    サマリー: ${_summary:-なし}"$'\n'
    _out="${_out}    ログ: ${_log:-なし}"$'\n'

    # 行動を促すのは「今のブランチの・古くない」委託だけにする(§3.4)。
    # 別ブランチ・古い記録にまで手順を出すと、警告そのものが読み飛ばされる。
    if [ "$_stale" = "0" ] && { [ -z "$_branch" ] || [ -z "$_cur_branch" ] || [ "$_branch" = "$_cur_branch" ]; }; then
      _out="${_out}    → 検収を通したら \`bash .claude/scripts/codex-run.sh accept ${_id}\`"$'\n'
    fi
  done

  [ "$_count" -eq 0 ] && exit 0

  echo "- Codex 委託(未検収): ${_count} 件"
  printf '%s' "$_out"
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

# run record の 3 点セット(<id>.json / <id>.log / <id>.last.txt)をまとめて削除する。
# 自動実行はしない(人間が明示的に叩く)。run record は「会話に依存しない状態の正」で、
# 勝手に消えると検収漏れが静かに発生するため。
#
# 既定で残すもの:
#   - 新しい順に --keep N 本(既定 20)
#   - accepted != true の record(未検収 = 検収キュー。--include-unaccepted で対象に入る)
#   - status=running かつ pid 生存(実行中。--include-unaccepted でも消さない)
#
# 新旧はファイル名(RUN_ID = YYYYMMDD-HHMMSS-PID)の辞書順で判定する。delegate-codex.sh が
# 必ずこの形で採番するため、startedAt を読むより安く、jq の有無にも date の実装にも依存しない。
cmd_prune() {
  local _dry=0 _keep=20 _unaccepted=0
  local _files=() _f _id _status _accepted _pid _skip
  local _rank=0 _cand=0 _removed=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) _dry=1 ;;
      --include-unaccepted) _unaccepted=1 ;;
      --keep)
        shift
        _keep="${1:-}"
        ;;
      --keep=*) _keep="${1#--keep=}" ;;
      *)
        echo "codex-run: prune の不明なオプションです: $1" >&2
        usage
        exit 2
        ;;
    esac
    shift
  done

  case "$_keep" in
    '' | *[!0-9]*)
      echo "codex-run: --keep には 0 以上の整数を指定してください: $_keep" >&2
      exit 1
      ;;
  esac

  [ -d "$RUN_DIR" ] || {
    echo "削除対象の record はありません"
    exit 0
  }

  # 逆順に並べて「新しい順」にする。glob の並びはロケール依存なので sort に任せる。
  # マッチが 0 件のときは glob 文字列がそのまま来るため [ -f ] で落とす。
  while IFS= read -r _f; do
    [ -f "$_f" ] || continue
    _files+=("$_f")
  done < <(printf '%s\n' "$RUN_DIR"/*.json | LC_ALL=C sort -r)

  for _f in "${_files[@]+"${_files[@]}"}"; do
    _rank=$((_rank + 1))
    _id="${_f##*/}"
    _id="${_id%.json}"

    # find_record と同じ理由の防御。id はこの後 rm のパスになる。
    case "$_id" in
      '' | */* | *..*)
        echo "スキップ: $_id(不正な id)" >&2
        continue
        ;;
    esac

    _status="$(rec_field "$_f" status)"
    _accepted="$(rec_field "$_f" accepted)"
    _skip=""

    if [ "$_rank" -le "$_keep" ]; then
      _skip="直近 ${_keep} 本"
    elif [ "$_accepted" != "true" ] && [ "$_unaccepted" -eq 0 ]; then
      _skip="未検収"
    elif [ "$_status" = "running" ]; then
      _pid="$(rec_field "$_f" pid)"
      # 非数値は「pid 不明」に正規化する(kill -0 はエラーで失敗するため)。
      # 判定不能な running は「実行中かもしれない」側に倒して残す — record が壊れている・
      # 強制終了で running のまま残った、という状況こそ #29 の背景であり、ここを削除に
      # 倒すと検収前の record が静かに消える。保護の向きを delegate-codex.sh 5-5
      # (再入防止)と揃える。
      case "$_pid" in '' | *[!0-9]*) _pid="" ;; esac
      if [ -z "$_pid" ] || kill -0 "$_pid" 2>/dev/null; then
        _skip="実行中(pid=${_pid:-不明})"
      fi
    fi

    if [ -n "$_skip" ]; then
      [ "$_dry" -eq 1 ] && echo "残す: $_id  ($_skip)"
      continue
    fi

    _cand=$((_cand + 1))
    if [ "$_dry" -eq 1 ]; then
      echo "削除候補: $_id  (status=${_status:-不明} accepted=${_accepted:-不明})"
      continue
    fi

    # 3 点セット単位。片方だけ残さない(log だけ残ると出口検査のハッシュ対象に残り続ける)。
    rm -f -- "$RUN_DIR/$_id.json" "$RUN_DIR/$_id.log" "$RUN_DIR/$_id.last.txt"
    _removed=$((_removed + 1))
  done

  if [ "$_dry" -eq 1 ]; then
    if [ "$_cand" -eq 0 ]; then
      echo "削除対象の record はありません"
    else
      echo "削除候補: ${_cand} 件(--dry-run のため削除していません)"
    fi
  else
    if [ "$_removed" -eq 0 ]; then
      echo "削除対象の record はありません"
    else
      echo "削除: ${_removed} 件"
    fi
  fi
  exit 0
}

SUBCOMMAND="${1:-}"
[ $# -ge 1 ] && shift

case "$SUBCOMMAND" in
  list) cmd_list "${1:-}" ;;
  pending) cmd_pending ;;
  show) cmd_show "${1:-}" ;;
  accept) cmd_accept "${1:-}" ;;
  set-status) cmd_set_status "${1:-}" "${2:-}" ;;
  prune) cmd_prune "$@" ;;
  *)
    usage
    exit 2
    ;;
esac
