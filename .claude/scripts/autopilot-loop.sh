#!/bin/bash
# ローカル CLI 用のチケット自動進行ループ(人間がターミナルで叩く)。
#
# 1 周 = autopilot-next.sh の判定 1 回 + 必要なら `claude -p` 1 回。
# `claude -p` は毎回新しいプロセスなので、チケットごとの /clear を人手で挟む必要がない。
# レビュー・CI 待ちの間はシェルが眠るだけで Claude を起動しない(枠を消費しない)。
#
# 司令塔セッションの中でループさせないのは、1 セッションで複数チケットを回すと
# 調査・実装ログが毎ターン再送され続けるため(.claude/rules/lead/context-management.md)。
#
# 使い方:
#   bash .claude/scripts/autopilot-loop.sh            # 実行
#   bash .claude/scripts/autopilot-loop.sh --dry-run  # 判定と起動予定のコマンドだけ表示して終わる
#
# 環境変数(設定ファイル .claude/autopilot.json より優先):
#   AUTOPILOT_POLL_SECONDS  待機時の再判定間隔(既定 300)
#   AUTOPILOT_MAX_RUNS      claude -p を起動する回数の上限(既定 20)
#   AUTOPILOT_CLAUDE_ARGS   claude に渡す引数(既定 "--permission-mode acceptEdits")
#
# 止まる条件(人間に返す): モードが normal 以外 / 作業ツリーが汚れている / 判定の失敗 /
#   同じ対象が 2 周続けて進まない(start 直後に PR 未作成なら 1 度だけ再開を試み、それでも
#   進まなければ止まる) / 別セッションの作業らしい in-progress / blocked / done / 起動回数の上限
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 2

DRY=0
case "${1:-}" in
  --dry-run) DRY=1 ;;
  "") ;;
  -h | --help) sed -n '2,24p' "$0"; exit 0 ;;
  *) echo "autopilot-loop.sh: 不明な引数: $1" >&2; exit 2 ;;
esac

CONF=.claude/autopilot.json
conf() { [ -f "$CONF" ] && jq -r --arg k "$1" '.[$k] // empty' "$CONF" 2>/dev/null; }
POLL="${AUTOPILOT_POLL_SECONDS:-$(conf pollSeconds)}"; POLL="${POLL:-300}"
MAX_RUNS="${AUTOPILOT_MAX_RUNS:-$(conf maxRuns)}"; MAX_RUNS="${MAX_RUNS:-20}"
CLAUDE_ARGS="${AUTOPILOT_CLAUDE_ARGS:---permission-mode acceptEdits}"
# 0 や不正値だと sleep が即失敗し、REST を叩き続ける tight loop になる
case "$POLL" in '' | *[!0-9]* | 0) echo "autopilot-loop.sh: pollSeconds は 1 以上の整数にする: $POLL" >&2; exit 2 ;; esac
case "$MAX_RUNS" in '' | *[!0-9]* | 0) echo "autopilot-loop.sh: maxRuns は 1 以上の整数にする: $MAX_RUNS" >&2; exit 2 ;; esac

log() { printf '[autopilot %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
stop() { log "停止: $*"; exit "${2:-1}"; }

command -v jq >/dev/null 2>&1 || stop "jq が見つからない" 2
if [ "$DRY" = 0 ]; then
  command -v claude >/dev/null 2>&1 || stop "claude CLI が見つからない" 2
fi

RUNS=0
LAST_KEY=""
while :; do
  MODE="$(bash .claude/scripts/harness-mode.sh 2>/dev/null || echo normal)"
  [ "$MODE" = normal ] || stop "ハーネスモードが $MODE(自動進行はモード A 専用。econ / degraded は枠を温存するモード)"

  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    [ "$DRY" = 1 ] && log "(dry-run) 作業ツリーに未コミットの変更がある。本番ではここで停止する" ||
      stop "作業ツリーに未コミットの変更がある(前回の claude -p が途中で終わった可能性。/status で確認する)"
  fi

  J="$(bash .claude/scripts/autopilot-next.sh)" || stop "判定に失敗した(autopilot-next.sh の stderr を参照)" 2
  # 要約は取得済みの JSON から作る(REST を 2 回叩かない / 2 回の結果がずれない)
  printf '%s' "$J" | bash .claude/scripts/autopilot-next.sh --format-summary | sed 's/^/  /'

  ACTION="$(printf '%s' "$J" | jq -r .action)"
  TARGET="$(printf '%s' "$J" | jq -r '.target // empty')"
  STALLED="$(printf '%s' "$J" | jq -r '.stalled[0] // empty')"

  # 1 ローカル作業ツリーは同時に 1 チケットしか扱えない。PR 未作成の in-progress
  # (= 前回の実行が PR まで届かなかった)を最優先で再開する
  PROMPT=""
  KEY=""
  if [ -n "$STALLED" ]; then
    # この作業ツリーで切ったブランチがあるときだけ再開する。無ければ別のセッション
    # (対話・別ワークツリー・クラウドの子)が実装中の可能性があり、二重に進めてしまう
    if ! git for-each-ref --format='%(refname:short)' refs/heads/ | grep -Eq "issue${STALLED}(-|$)"; then
      stop "#$STALLED は in-progress だが PR が無く、この作業ツリーにブランチも無い。別のセッションが実装中か確認し、中断なら in-progress を外す"
    fi
    PROMPT="/next-ticket $STALLED" # 指定チケットが PR 未作成の in-progress なら /next-ticket が再開経路に入る
    KEY="resume:$STALLED"
  else
    case "$ACTION" in
      fix) PROMPT="/fix-pr $TARGET"; KEY="fix:$TARGET:$(printf '%s' "$J" | jq -r '.attention[0].reasons | join(",")')" ;;
      start) PROMPT="/next-ticket $TARGET"; KEY="start:$TARGET" ;;
      wait)
        if [ "$DRY" = 1 ]; then log "(dry-run) ${POLL}s 待って再判定する"; exit 0; fi
        log "レビュー・CI 待ち。${POLL}s 後に再判定する(Ctrl-C で終了)"
        LAST_KEY=""
        sleep "$POLL"
        continue
        ;;
      blocked) stop "着手できるチケットが無い(依存が閉じない)。上の「依存待ち」を確認する" 0 ;;
      done) log "open のチケットが無い。/sync-docs と次フェーズ(P1)の計画を検討する"; exit 0 ;;
      *) stop "未知の action: $ACTION" 2 ;;
    esac
  fi

  # 前の周と同じ対象・同じ状態のまま = claude -p が進められなかった。同じ起動を繰り返さない
  if [ "$KEY" = "$LAST_KEY" ]; then
    stop "前回の実行後も状態が変わっていない($KEY)。人間の判断が要る"
  fi

  if [ "$DRY" = 1 ]; then
    log "(dry-run) 起動予定: claude -p \"$PROMPT\" $CLAUDE_ARGS"
    exit 0
  fi

  RUNS=$((RUNS + 1))
  [ "$RUNS" -le "$MAX_RUNS" ] || stop "起動回数の上限($MAX_RUNS)に達した" 0

  log "起動 $RUNS/$MAX_RUNS: claude -p \"$PROMPT\""
  # shellcheck disable=SC2086 # CLAUDE_ARGS は意図的に単語分割する
  if ! claude -p "$PROMPT" $CLAUDE_ARGS; then
    stop "claude -p が失敗した($PROMPT)"
  fi
  LAST_KEY="$KEY"
done
