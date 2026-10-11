#!/bin/bash
# autopilot を始める前の事前チェック(読み取り専用。GitHub にもファイルにも書き込まない)。
#
# /autopilot が開始前に呼び、autopilot-loop.sh も起動時に呼ぶ(致命的な問題があれば起動しない)。
# 人間がターミナルで直接叩いてもよい:
#
#   bash .claude/scripts/autopilot-preflight.sh
#
# 出力: 1 項目 1 行の「✅ / ⚠️ / ❌ / ℹ️ 項目: 詳細」と、問題があれば次の行に「→ 直し方」。
#       最後の行は RESULT: ok | warn | ng | running
# 終了コード: 0 = 問題なし / 1 = 警告あり(始められるが確認したほうがよい) /
#             2 = 致命的(始めても止まる) / 3 = 既に実行中
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || {
  echo "❌ リポジトリ: git リポジトリの中で実行する"; echo "RESULT: ng"; exit 2
}

NG=0
WARN=0
ok() { printf '✅ %s\n' "$1"; }
info() { printf 'ℹ️  %s\n' "$1"; [ -n "${2:-}" ] && printf '   → %s\n' "$2"; return 0; }
warn() { WARN=1; printf '⚠️  %s\n' "$1"; [ -n "${2:-}" ] && printf '   → %s\n' "$2"; return 0; }
ng() { NG=1; printf '❌ %s\n' "$1"; [ -n "${2:-}" ] && printf '   → %s\n' "$2"; return 0; }

# --- 既に実行中か(実行中なら他の検査は不要) ---
PIDF=.harness/autopilot.pid
if [ -f "$PIDF" ]; then
  P="$(cat "$PIDF" 2>/dev/null)"
  if [ -n "$P" ] && kill -0 "$P" 2>/dev/null && ps -o args= -p "$P" 2>/dev/null | grep -q autopilot-loop; then
    info "autopilot は既に実行中(pid $P)" "様子: bash .claude/scripts/autopilot-loop.sh --log / 止める: --stop"
    echo "RESULT: running"
    exit 3
  fi
fi

# --- コマンド ---
MISSING=""
for c in git gh jq claude nohup; do command -v "$c" >/dev/null 2>&1 || MISSING="$MISSING $c"; done
if [ -n "$MISSING" ]; then
  ng "必要なコマンドが無い:$MISSING" "インストールしてから再実行する(claude は Claude Code CLI)"
else
  ok "必要なコマンド: git / gh / jq / claude / nohup"
  if claude auth status >/dev/null 2>&1; then
    ok "Claude: ログイン済み"
  else
    ng "Claude: ログインしていない(claude -p が起動直後に失敗する)" "claude を起動してログインする(claude auth login)"
  fi
fi
command -v jq >/dev/null 2>&1 || { echo "RESULT: ng"; exit 2; } # 以降の検査は jq 前提

# --- ハーネスモード ---
MODE="$(bash .claude/scripts/harness-mode.sh 2>/dev/null || echo normal)"
case "$MODE" in
  normal) ok "ハーネスモード: normal(計画 → 実装 → 検収 → PR を 1 チケット 1 回の claude -p で回す)" ;;
  econ) ok "ハーネスモード: econ(計画と draft PR だけ Claude、実装は Codex。検収は CI に委ねる)" ;;
  *) ng "ハーネスモード: $MODE(自動進行しないモード)" ".harness/mode を normal か econ に戻す(切り替えは人が判断する)" ;;
esac

# --- 設定ファイル ---
CONF=.claude/autopilot.json
if [ -f "$CONF" ]; then
  if ! jq -e . "$CONF" >/dev/null 2>&1; then
    ng "設定: $CONF が JSON として読めない" "構文を直す"
  else
    BAD=""
    for k in maxInFlight pollSeconds maxRuns; do
      v="$(jq -r --arg k "$k" 'if has($k) then .[$k] | tostring else "" end' "$CONF")"
      case "$v" in '' | *[!0-9]* | 0) [ -n "$v" ] && BAD="$BAD $k=$v" ;; esac
    done
    v="$(jq -r 'if (.econ | type) == "object" and (.econ | has("maxInFlight")) then .econ.maxInFlight | tostring else "" end' "$CONF")"
    case "$v" in '' | *[!0-9]* | 0) [ -n "$v" ] && BAD="$BAD econ.maxInFlight=$v" ;; esac
    if [ -n "$BAD" ]; then
      ng "設定: 1 以上の整数でない値がある:$BAD" "$CONF を直す"
    else
      ok "設定: $(jq -r '"同時進行 \(.maxInFlight // 2)(econ \(.econ.maxInFlight // 4))/ 待機間隔 \(.pollSeconds // 300) 秒 / 起動上限 \(.maxRuns // 20) 回"' "$CONF")"
    fi
  fi
else
  info "設定: $CONF が無いので既定値で動く(同時進行 2 / 待機 300 秒 / 起動上限 20 回)"
fi

# --- GitHub ---
# shellcheck source=lib-github.sh
. .claude/scripts/lib-github.sh 2>/dev/null
REPO="$(gh_resolve_repo 2>/dev/null || true)"
if [ -z "$REPO" ]; then
  ng "GitHub: origin からリポジトリを特定できない" "git remote -v を確認する(AUTOPILOT_REPO=owner/repo でも指定できる)"
elif ! LOGIN="$(gh api user --jq .login 2>/dev/null)"; then
  ng "GitHub: gh が認証されていない、または API に届かない" "gh auth login を実行する"
else
  PUSH="$(gh api "repos/$REPO" --jq '.permissions.push // false' 2>/dev/null || echo false)"
  if [ "$PUSH" = true ]; then
    ok "GitHub: $LOGIN として $REPO に書き込める"
  else
    ng "GitHub: $LOGIN は $REPO に書き込めない(PR・ラベル・全体管理 Issue が作れない)" "書き込み権限のあるアカウントで gh auth login する"
  fi
fi

# --- git の状態 ---
BASE="$(jq -r '.baseBranch // "main"' .claude/branch-policy.json 2>/dev/null || echo main)"
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  ng "作業ツリー: 未コミットの変更がある($(git status --porcelain | wc -l | tr -d ' ') 件)" "コミットするか退避(git stash)してから始める。ループは誰の変更か分からない変更を触らない"
else
  ok "作業ツリー: クリーン(現在のブランチ: $(git branch --show-current))"
fi
if git ls-remote --exit-code --heads origin "$BASE" >/dev/null 2>&1; then
  ok "ベースブランチ: origin/$BASE に届く"
else
  ng "ベースブランチ: origin/$BASE に届かない" ".claude/branch-policy.json の baseBranch と、git remote / ネットワークを確認する"
fi
if [ -f package.json ] && [ ! -d node_modules ]; then
  warn "依存: node_modules が無い(lint・テスト・コミット時のフックが動かない)" "npm ci を実行する"
fi

# --- 無人実行の許可 ---
# claude -p は対話できないので、許可されていない操作に当たるとそこで進めなくなる。
ARGS="${AUTOPILOT_CLAUDE_ARGS:---permission-mode acceptEdits}"
case "$ARGS" in
  *bypassPermissions* | *dangerously-skip-permissions*)
    warn "無人実行の許可: すべての操作を確認なしで許可する設定(AUTOPILOT_CLAUDE_ARGS=$ARGS)" "意図どおりなら問題ない。PreToolUse hook のガードは引き続き効く"
    ;;
  *)
    HAVE="$(jq -r '.permissions.allow[]?' .claude/settings.json .claude/settings.local.json 2>/dev/null)"
    # エントリに空白を含むものがあるので、1 行 1 エントリで照合する
    LACK=""
    while IFS= read -r p; do printf '%s\n' "$HAVE" | grep -qxF "$p" || LACK="$LACK, $p"; done <<'EOF'
Skill(commit)
Skill(steering)
Skill(implement-ticket)
Bash(git commit:*)
Bash(git push:*)
Bash(git switch:*)
Bash(git checkout -b:*)
Bash(git fetch:*)
Bash(git merge:*)
Bash(gh issue view:*)
Bash(gh issue edit:*)
Bash(gh issue comment:*)
Bash(gh pr create:*)
Bash(gh pr view:*)
Bash(gh pr checks:*)
Bash(gh run view:*)
Bash(bash .claude/scripts/autopilot-next.sh:*)
Bash(bash .claude/scripts/pr-feedback.sh:*)
Bash(bash .claude/scripts/harness-mode.sh:*)
Bash(bash .claude/scripts/delegate-codex.sh impl:*)
Bash(bash .claude/scripts/codex-run.sh list:*)
Bash(bash .claude/scripts/codex-run.sh show:*)
EOF
    if [ -n "$LACK" ]; then
      warn "無人実行の許可: .claude/settings.json の allow に無いもの: ${LACK#, }" "allow に足す(/sync-template で取り込める)。無いままだと claude -p がその操作で進めず、ループが「状態が変わっていない」で止まる"
    else
      ok "無人実行の許可: チケットを回すのに要る操作は allow 済み($ARGS)"
    fi
    ;;
esac

# --- Codex ---
CODEX_OK=1
if ! command -v codex >/dev/null 2>&1; then
  CODEX_OK=0; CODEX_WHY="codex コマンドが無い"
elif ! codex login status >/dev/null 2>&1; then
  CODEX_OK=0; CODEX_WHY="codex が未認証(codex login)"
fi
# 委託の入口検査1(機密ファイル)と同じ走査。ここに当たると委託は毎回 exit 2 で止まる
SENS=""
if [ -f .claude/codex-denylist.txt ]; then
  FIND_EXPR=()
  while IFS= read -r l || [ -n "$l" ]; do
    l="${l%%#*}"
    l="$(printf '%s' "$l" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$l" ] && continue
    [ ${#FIND_EXPR[@]} -gt 0 ] && FIND_EXPR+=(-o)
    case "$l" in */*) FIND_EXPR+=(-path "./$l") ;; *) FIND_EXPR+=(-name "$l") ;; esac
  done <.claude/codex-denylist.txt
  if [ ${#FIND_EXPR[@]} -gt 0 ]; then
    SENS="$(find . \( -name node_modules -o -name .git -o -name .harness \) -prune -o \( "${FIND_EXPR[@]}" \) -type f -print 2>/dev/null |
      grep -Ev '\.(example|sample|template)$' | head -5 | tr '\n' ' ')"
  fi
fi
if [ "$MODE" = econ ]; then
  # econ は実装を Codex にしか渡さない(Sonnet fork に落とさない)ので、使えなければ進めない
  if [ "$CODEX_OK" = 0 ]; then
    ng "Codex: $CODEX_WHY(econ は実装を Codex にだけ任せる)" "codex を導入・ログインするか、通常モードで回す"
  elif [ -n "$SENS" ]; then
    ng "Codex: 送信禁止に当たるファイルがある: $SENS(委託が毎回止まる)" "作業ツリーの外へ退避するか、.claude/codex-denylist.txt のパターンを見直す"
  else
    ok "Codex: 使える(ログイン済み・送信禁止ファイルなし)"
  fi
else
  if [ "$CODEX_OK" = 0 ]; then
    info "Codex: $CODEX_WHY。実装は Sonnet fork(Claude の枠)で行う"
  elif [ -n "$SENS" ]; then
    warn "Codex: 送信禁止に当たるファイルがある: $SENS。委託できず Sonnet fork(Claude の枠)で実装する" "Codex を使いたいなら退避する"
  else
    ok "Codex: 使える(実装は Codex に委託し、使えなければ Sonnet fork)"
  fi
fi

# --- チケット ---
if [ -n "$REPO" ] && J="$(bash .claude/scripts/autopilot-next.sh 2>/dev/null)"; then
  OPEN="$(printf '%s' "$J" | jq -r .openTickets)"
  ACTION="$(printf '%s' "$J" | jq -r .action)"
  SUM="$(printf '%s' "$J" | jq -r '"残り \(.openTickets) 件 / 着手可能 \(.ready | length) / 進行中 \(.inFlight | length)/\(.maxInFlight) / 依存待ち \(.blocked | length)"')"
  case "$ACTION" in
    start | fix) ok "チケット: $SUM(最初の動き: $( [ "$ACTION" = fix ] && echo "PR #$(printf '%s' "$J" | jq -r .target) の修復" || echo "#$(printf '%s' "$J" | jq -r .target) に着手"))" ;;
    wait) info "チケット: $SUM。いまはレビュー・CI 待ちなので、起動後しばらく待機する" ;;
    done) warn "チケット: open の ticket Issue が無い(やることが無い)" "/setup-tickets でチケットを作るか、ticket ラベルを確認する" ;;
    blocked) warn "チケット: $SUM。依存が閉じず着手できるものが無い" "bash .claude/scripts/autopilot-next.sh --summary で「依存待ち」を確認する" ;;
    manual) warn "チケット: 残りは autopilot:manual のものだけ" "通常モードで /next-ticket [番号] を回す" ;;
  esac
  OTHER="$(printf '%s' "$J" | jq -r '.stalled | map("#\(.)") | join(", ")')"
  if [ -n "$OTHER" ]; then
    MINE=""
    for s in $(printf '%s' "$J" | jq -r '.stalled[]'); do
      git for-each-ref --format='%(refname:short)' refs/heads/ | grep -Eq "(^|/|-)issue${s}-" && MINE="$MINE #$s"
    done
    if [ -n "$MINE" ]; then
      info "中断した作業:$MINE(この作業ツリーにブランチがある。最初に再開する)"
    else
      warn "PR の無い in-progress: $OTHER(この作業ツリーにブランチが無い = 別のセッションが実装中か、中断したまま)" "中断なら in-progress ラベルを外す。外さないと同時進行の枠を 1 つ使い続ける"
    fi
  fi
  [ "$(printf '%s' "$J" | jq -r '(.fetchErrors // []) | length')" -gt 0 ] &&
    warn "PR の詳細の一部を取得できなかった(判定が甘くなる)" "時間をおいて再実行する"
else
  [ -n "$REPO" ] && ng "チケット: 判定に失敗した" "bash .claude/scripts/autopilot-next.sh --summary を直接実行してエラーを見る"
fi

# --- 全体管理 Issue・通知 ---
if [ "$(jq -r 'if has("board") then .board | tostring else "true" end' "$CONF" 2>/dev/null || echo true)" = false ]; then
  info "全体管理 Issue: 使わない設定(board: false)。一時停止は --stop で行う"
elif [ -n "$REPO" ] && command -v gh >/dev/null 2>&1; then
  URL="$(bash .claude/scripts/autopilot-board.sh url 2>/dev/null || true)"
  if [ -n "$URL" ]; then
    info "全体管理 Issue: $URL(状態の確認・一時停止はここ)"
  else
    info "全体管理 Issue: まだ無い。起動後の最初の判定で autopilot ラベルの Issue を作る"
  fi
fi
if [ -n "${AUTOPILOT_NOTIFY_CMD:-}" ]; then
  ok "停止の通知: AUTOPILOT_NOTIFY_CMD を実行する"
else
  info "停止の通知: 全体管理 Issue へのコメントだけ(自分の投稿は自分に通知されない)" "手元で気づきたいなら AUTOPILOT_NOTIFY_CMD を設定する(手順書の「初回の準備」)"
fi

if [ "$NG" = 1 ]; then echo "RESULT: ng"; exit 2; fi
if [ "$WARN" = 1 ]; then echo "RESULT: warn"; exit 1; fi
echo "RESULT: ok"
exit 0
