#!/bin/bash
# ローカル CLI 用のチケット自動進行ループ(人間がターミナルで 1 回叩けば、あとは放置できる)。
#
# 1 周 = autopilot-next.sh の判定 1 回 + 必要なら `claude -p` 1 回。
# `claude -p` は毎回新しいプロセスなので、チケットごとの /clear を人手で挟む必要がない。
# レビュー・CI 待ちの間はシェルが眠るだけで Claude を起動しない(枠を消費しない)。
#
# 司令塔セッションの中でループさせないのは、1 セッションで複数チケットを回すと
# 調査・実装ログが毎ターン再送され続けるため(.claude/rules/lead/context-management.md)。
#
# 使い方:
#   bash .claude/scripts/autopilot-loop.sh --dry-run     # 判定と起動予定のコマンドだけ表示して終わる
#   bash .claude/scripts/autopilot-loop.sh --background  # 裏で起動する(ログ: .harness/autopilot.log)
#   bash .claude/scripts/autopilot-loop.sh --log         # ログを追う(Ctrl-C でログ表示だけ終わる)
#   bash .claude/scripts/autopilot-loop.sh --stop        # 裏の実行を止める
#   bash .claude/scripts/autopilot-loop.sh               # 前面で実行する
#
# 全体管理 Issue(`autopilot` ラベル): 判定のたびに全チケットの状態を書き出し、
#   本文の「一時停止」にチェックが入っていれば新規着手も修復もせずに待つ。人手が要る停止は
#   そこにコメントされる(実体は autopilot-board.sh。`.claude/autopilot.json` の board: false で無効)
#
# ハーネスモード:
#   normal — /next-ticket が計画 → 委託 → 検収 → PR まで 1 回の claude -p で行う
#   econ   — 枠を温存する 3 段: claude -p で計画だけ(/next-ticket N --plan-only)→ このスクリプトが
#            delegate-codex.sh impl を直接叩く(Claude を起動しない)→ claude -p で draft PR だけ
#            (/ship-ticket N)。検収は CI に委ねる(.claude/rules/mode/econ.md)
#   degraded — 止まる(Claude が動かない前提のモード)
#
# 環境変数(設定ファイル .claude/autopilot.json より優先):
#   AUTOPILOT_POLL_SECONDS  待機時の再判定間隔(既定 300)
#   AUTOPILOT_MAX_RUNS      claude -p を起動する回数の上限(既定 20)
#   AUTOPILOT_CLAUDE_ARGS   claude に渡す引数(既定 "--permission-mode acceptEdits")
#   AUTOPILOT_NOTIFY_CMD    停止時に理由を引数に実行するコマンド(例: 'notify-send autopilot')
#
# 止まる条件(人間に返す。全体管理 Issue にコメントされる): モードが degraded / 他チケットの
#   未コミット変更 / 判定の失敗 / 同じ対象が 2 周続けて進まない / 別セッションの作業らしい
#   in-progress / econ で Codex が使えない・失敗・package.json のライフサイクル差分 /
#   blocked / done / 起動回数の上限
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 2

LOGF=.harness/autopilot.log
PIDF=.harness/autopilot.pid

DRY=0
case "${1:-}" in
  --dry-run) DRY=1 ;;
  --background)
    if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
      echo "既に実行中(pid $(cat "$PIDF"))。止めるには --stop"; exit 1
    fi
    mkdir -p .harness
    nohup bash "$0" >>"$LOGF" 2>&1 </dev/null &
    echo $! >"$PIDF"
    echo "autopilot を裏で起動した(pid $!)。ログ: bash $0 --log / 停止: bash $0 --stop"
    exit 0
    ;;
  --stop)
    if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
      # ループ本体と、その子(claude -p / sleep)をまとめて止める
      pkill -TERM -P "$(cat "$PIDF")" 2>/dev/null
      kill "$(cat "$PIDF")" 2>/dev/null && echo "停止した(pid $(cat "$PIDF"))"
      rm -f "$PIDF"
    else
      echo "実行中の autopilot は無い"; rm -f "$PIDF"
    fi
    exit 0
    ;;
  --log) exec tail -n 50 -F "$LOGF" ;;
  "") ;;
  -h | --help) sed -n '2,40p' "$0"; exit 0 ;;
  *) echo "autopilot-loop.sh: 不明な引数: $1" >&2; exit 2 ;;
esac

CONF=.claude/autopilot.json
conf() { [ -f "$CONF" ] && jq -r --arg k "$1" 'if has($k) then .[$k] else empty end' "$CONF" 2>/dev/null; } # // は false を値なし扱いにするので使わない
POLL="${AUTOPILOT_POLL_SECONDS:-$(conf pollSeconds)}"; POLL="${POLL:-300}"
MAX_RUNS="${AUTOPILOT_MAX_RUNS:-$(conf maxRuns)}"; MAX_RUNS="${MAX_RUNS:-20}"
CLAUDE_ARGS="${AUTOPILOT_CLAUDE_ARGS:---permission-mode acceptEdits}"
BOARD=1
[ "$(conf board)" = false ] && BOARD=0
# 0 や不正値だと sleep が即失敗し、REST を叩き続ける tight loop になる
case "$POLL" in '' | *[!0-9]* | 0) echo "autopilot-loop.sh: pollSeconds は 1 以上の整数にする: $POLL" >&2; exit 2 ;; esac
case "$MAX_RUNS" in '' | *[!0-9]* | 0) echo "autopilot-loop.sh: maxRuns は 1 以上の整数にする: $MAX_RUNS" >&2; exit 2 ;; esac

log() { printf '[autopilot %s] %s\n' "$(date '+%m-%d %H:%M:%S')" "$*"; }

# 全体管理 Issue の操作。失敗しても進行は止めない(表示層が落ちて本体が止まるのは逆)
board() {
  [ "$BOARD" = 1 ] && [ "$DRY" = 0 ] || return 1
  bash .claude/scripts/autopilot-board.sh "$@" 2>&1 >/dev/null | sed 's/^/  (board) /' >&2
  return "${PIPESTATUS[0]}"
}
board_sync() { [ -n "${J:-}" ] && printf '%s' "$J" | board sync --status "$1"; }
board_paused() { [ "$BOARD" = 1 ] && [ "$DRY" = 0 ] && bash .claude/scripts/autopilot-board.sh paused 2>/dev/null; }

stop() {
  log "停止: $1"
  if [ "$DRY" = 0 ]; then
    board_sync "🔴 停止 — $1"
    board notify "🔴 **autopilot が停止しました**

$1

再開: \`bash .claude/scripts/autopilot-loop.sh --background\`" || true
    printf '\a'
  fi
  rm -f "$PIDF" 2>/dev/null
  exit "${2:-1}"
}

command -v jq >/dev/null 2>&1 || stop "jq が見つからない" 2
if [ "$DRY" = 0 ]; then
  command -v claude >/dev/null 2>&1 || stop "claude CLI が見つからない" 2
fi
trap 'log "割り込みで終了"; rm -f "$PIDF" 2>/dev/null; exit 130' INT TERM

RUNS=0
LAST_KEY=""

run_claude() { # $1=プロンプト
  RUNS=$((RUNS + 1))
  [ "$RUNS" -le "$MAX_RUNS" ] || stop "起動回数の上限($MAX_RUNS)に達した。続けるなら再起動する" 0
  log "起動 $RUNS/$MAX_RUNS: claude -p \"$1\""
  # shellcheck disable=SC2086 # CLAUDE_ARGS は意図的に単語分割する
  claude -p "$1" $CLAUDE_ARGS || stop "claude -p が失敗した($1)"
}

# チケット N のブランチ(この作業ツリーで切ったもの)を返す
ticket_branch() {
  git for-each-ref --format='%(refname:short)' refs/heads/ | grep -E "issue${1}(-|$)" | head -1
}
ticket_steering() {
  find .steering -maxdepth 1 -type d -name "*-issue${1}-*" 2>/dev/null | sort | tail -1
}

# package.json のライフサイクル系(scripts / lint-staged / prepare)が HEAD から変わったか。
# CI が回す npm test 自体が委託成果になるため、econ でも人間の目視を飛ばさない(econ.md 5)
lifecycle_changed() {
  [ -f package.json ] || return 1
  local before after
  local base mb
  # 比較の基準は HEAD ではなく base との分岐点(途中で commit 済みの委託成果も見落とさない)
  base="$(jq -r '.baseBranch // "main"' .claude/branch-policy.json 2>/dev/null || echo main)"
  mb="$(git merge-base HEAD "origin/$base" 2>/dev/null || echo HEAD)"
  before="$(git show "$mb:package.json" 2>/dev/null | jq -S '{scripts, "lint-staged", prepare: .scripts.prepare}' 2>/dev/null)"
  after="$(jq -S '{scripts, "lint-staged", prepare: .scripts.prepare}' package.json 2>/dev/null)"
  [ "$before" != "$after" ]
}

# econ の 1 チケット: 段階を実態(steering・tasklist・終了コード)から判定して 1 段だけ進める
econ_step() { # $1=Issue 番号
  local n="$1" dir br rc
  br="$(ticket_branch "$n")"
  [ -n "$br" ] && [ "$(git branch --show-current)" != "$br" ] && { git switch -q "$br" || stop "#$n のブランチ $br に移れない"; }
  dir="$(ticket_steering "$n")"
  if [ -z "$dir" ] || [ ! -f "$dir/design.md" ] || ! grep -q '<!-- status: ready -->' "$dir/design.md"; then
    run_claude "/next-ticket $n --plan-only"
    return
  fi
  if grep -qE '^[[:space:]]*- \[ \]' "$dir/tasklist.md" 2>/dev/null; then
    log "Codex に委託: $dir"
    bash .claude/scripts/delegate-codex.sh impl "$dir/"
    rc=$?
    case "$rc" in
      0) ;; # 次の周で tasklist が閉じていれば ship に進む
      1 | 5) run_claude "/next-ticket $n --plan-only" ;; # 判断待ち / 計画未完成 → design.md を直す
      3) stop "Codex が使えない(exit 3)。econ では Sonnet fork に自動で落とさない(枠を使うため)。Codex を直すか、通常モードに戻して /next-ticket $n" ;;
      4) log "Codex のレート上限(exit 4)。${POLL}s 待って再開する"; sleep "$POLL"; KEEP_GOING=1 ;; # 待っただけなので「進まなかった」に数えない
      *) stop "Codex への委託が失敗した(exit $rc / $dir)。.harness/codex-runs/ のログを確認する" ;;
    esac
    return
  fi
  if lifecycle_changed; then
    stop "#$n: package.json の scripts / lint-staged / prepare が変わっている。目視してから /ship-ticket $n を実行する(econ.md 5)"
  fi
  run_claude "/ship-ticket $n"
}

while :; do
  MODE="$(bash .claude/scripts/harness-mode.sh 2>/dev/null || echo normal)"
  case "$MODE" in
    normal | econ) ;;
    *) stop "ハーネスモードが $MODE(Claude が動かない前提のモード。自動進行しない)" ;;
  esac

  J="$(bash .claude/scripts/autopilot-next.sh)" || { J=""; stop "判定に失敗した(autopilot-next.sh の stderr を参照)" 2; }
  # 要約は取得済みの JSON から作る(REST を 2 回叩かない / 2 回の結果がずれない)
  printf '%s' "$J" | bash .claude/scripts/autopilot-next.sh --format-summary | sed 's/^/  /'

  if board_paused; then
    board_sync "⏸ 一時停止中(全体管理 Issue のチェックを外すと再開)"
    log "一時停止中。${POLL}s 後に再確認する"
    LAST_KEY=""
    sleep "$POLL"
    continue
  fi

  ACTION="$(printf '%s' "$J" | jq -r .action)"
  TARGET="$(printf '%s' "$J" | jq -r '.target // empty')"

  # 1 ローカル作業ツリーは同時に 1 チケットしか扱えない。PR 未作成の in-progress のうち、
  # この作業ツリーにブランチがあるもの(= 前回の実行が PR まで届かなかった自分の作業)を最優先で再開する
  OWN_STALLED=""
  for s in $(printf '%s' "$J" | jq -r '.stalled[]'); do
    if [ -n "$(ticket_branch "$s")" ]; then OWN_STALLED="$s"; break; fi
  done

  # 未コミット変更は「再開するチケット自身のブランチ上」なら続きとして扱う(Codex の部分成果・
  # 途中で終わった claude -p)。それ以外は誰の変更か分からないので止まる
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    if [ -z "$OWN_STALLED" ] || [ "$(git branch --show-current)" != "$(ticket_branch "$OWN_STALLED")" ]; then
      [ "$DRY" = 1 ] && log "(dry-run) 作業ツリーに未コミットの変更がある。本番ではここで停止する" ||
        stop "作業ツリーに未コミットの変更がある($(git branch --show-current))。再開中のチケットのものではないので触らない"
    fi
  fi

  if [ -n "$OWN_STALLED" ]; then
    KEY="resume:$OWN_STALLED:$(git rev-parse HEAD 2>/dev/null):$(git status --porcelain 2>/dev/null | git hash-object --stdin | cut -c1-8)"
    STATUS="🟢 実行中 — #$OWN_STALLED を再開"
  else
    case "$ACTION" in
      fix) KEY="fix:$TARGET:$(printf '%s' "$J" | jq -r '.attention[0].reasons | join(",")')"; STATUS="🟢 実行中 — PR #$TARGET を修復" ;;
      start) KEY="start:$TARGET"; STATUS="🟢 実行中 — #$TARGET に着手" ;;
      wait)
        # 別セッションの作業らしい stalled(この作業ツリーにブランチが無い)は、枠を食ったまま
        # 進まない可能性があるので知らせる。ただし待機は続ける(別セッションが進めているかもしれない)
        OTHER="$(printf '%s' "$J" | jq -r '.stalled | map("#\(.)") | join(", ")')"
        if [ "$DRY" = 1 ]; then log "(dry-run) ${POLL}s 待って再判定する"; exit 0; fi
        board_sync "👀 レビュー・CI 待ち${OTHER:+(別セッションで実装中: $OTHER)}"
        log "レビュー・CI 待ち。${POLL}s 後に再判定する"
        LAST_KEY=""
        sleep "$POLL"
        continue
        ;;
      blocked)
        OTHER="$(printf '%s' "$J" | jq -r '.stalled | map("#\(.)") | join(", ")')"
        if [ -n "$OTHER" ]; then
          stop "$OTHER が in-progress だが PR が無く、この作業ツリーにブランチも無い。別のセッションが実装中か確認し、中断なら in-progress を外す"
        fi
        stop "着手できるチケットが無い(依存が閉じない)。全体管理 Issue の「依存待ち」を確認する" 0
        ;;
      manual)
        stop "残りは autopilot:manual のチケットだけ($(printf '%s' "$J" | jq -r '.manual | map("#\(.)") | join(", ")'))。通常モードで /next-ticket [番号] を回す" 0
        ;;
      done)
        board_sync "✅ 完了 — open のチケットが無い"
        log "open のチケットが無い。/sync-docs と次フェーズ(P1)の計画を検討する"
        [ "$DRY" = 0 ] && board notify "✅ 全チケットが完了しました。/sync-docs と次フェーズ(P1)の計画を検討してください" || true
        rm -f "$PIDF" 2>/dev/null
        exit 0
        ;;
      *) stop "未知の action: $ACTION" 2 ;;
    esac
  fi

  # 前の周と同じ対象・同じ状態のまま = 進められなかった。同じ起動を繰り返さない
  if [ "$KEY" = "$LAST_KEY" ]; then
    stop "前回の実行後も状態が変わっていない(${KEY%%:*} #${OWN_STALLED:-$TARGET})。人間の判断が要る"
  fi

  if [ "$DRY" = 1 ]; then
    if [ "$ACTION" = fix ] && [ -z "$OWN_STALLED" ]; then
      log "(dry-run) 起動予定: claude -p \"/fix-pr $TARGET\" $CLAUDE_ARGS"
    elif [ "$MODE" = econ ]; then
      log "(dry-run) econ: #${OWN_STALLED:-$TARGET} を 計画(claude -p)→ 委託(delegate-codex.sh)→ draft PR(claude -p)の段階で 1 段進める"
    else
      log "(dry-run) 起動予定: claude -p \"/next-ticket ${OWN_STALLED:-$TARGET}\" $CLAUDE_ARGS"
    fi
    exit 0
  fi

  board_sync "$STATUS"
  if [ "$ACTION" = fix ] && [ -z "$OWN_STALLED" ]; then
    run_claude "/fix-pr $TARGET"
  elif [ "$MODE" = econ ]; then
    econ_step "${OWN_STALLED:-$TARGET}"
  else
    # 指定チケットが PR 未作成の in-progress なら /next-ticket が再開経路に入る
    run_claude "/next-ticket ${OWN_STALLED:-$TARGET}"
  fi
  if [ "${KEEP_GOING:-0}" = 1 ]; then LAST_KEY=""; else LAST_KEY="$KEY"; fi
  KEEP_GOING=0
done
