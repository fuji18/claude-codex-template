#!/bin/bash
# チケット自動進行(autopilot)の判定: 「次に何をするか」を JSON 1 個で返す。
#
# /next-ticket・/autopilot(クラウドの司令塔)・autopilot-loop.sh(ローカル)の 3 経路が
# 同じ判定を使うための単一ソース。経路ごとに散文で選定規則を持たせると結果が割れる。
#
# GitHub へは REST(gh api)だけで触る。Claude Code on the web では GraphQL が 403 になり、
# gh issue list / gh pr list(GraphQL 経由)が使えないため。
#
# 使い方:
#   bash .claude/scripts/autopilot-next.sh            # JSON を出す
#   bash .claude/scripts/autopilot-next.sh --summary  # 人間向けの要約を出す
#   bash .claude/scripts/autopilot-next.sh --issues F --prs F [--details F]  # フィクスチャ(テスト用)
#     F はそれぞれ REST の issues 一覧 / pulls 一覧の JSON 配列。
#     --details は {"<PR番号>": {"mergeable_state":..,"checks":[conclusion..],"reviews":[{"user":..,"state":..}]}}
#
# action(上から最初に当たったもの):
#   fix     — 進行中の PR にコンフリクト / CI 失敗 / 変更要求がある(新規着手より先に直す)
#   start   — 空き枠があり、依存が解決済みのチケットがある
#   wait    — 進行中の作業がある(レビュー・CI 待ち)。空き枠が無い / 着手できるものが無い
#   blocked — open のチケットが残るが、依存が閉じず着手できない
#   done    — open のチケットが無い
#
# 終了コード: 0 = 判定成功 / 2 = 取得・解析の失敗
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 2

die() { echo "autopilot-next.sh: $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || die "jq が見つからない"

MODE=json
ISSUES_FILE=""
PRS_FILE=""
DETAILS_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --summary) MODE=summary ;;
    --issues) ISSUES_FILE="${2:-}"; shift ;;
    --prs) PRS_FILE="${2:-}"; shift ;;
    --details) DETAILS_FILE="${2:-}"; shift ;;
    -h | --help) sed -n '2,24p' "$0"; exit 0 ;;
    *) die "不明な引数: $1" ;;
  esac
  shift
done

# --- 設定(環境変数 > .claude/autopilot.json > 既定値) ---
CONF=.claude/autopilot.json
conf() { [ -f "$CONF" ] && jq -r --arg k "$1" '.[$k] // empty' "$CONF" 2>/dev/null; }
MAX_IN_FLIGHT="${AUTOPILOT_MAX_IN_FLIGHT:-$(conf maxInFlight)}"
MAX_IN_FLIGHT="${MAX_IN_FLIGHT:-2}"
case "$MAX_IN_FLIGHT" in '' | *[!0-9]*) die "maxInFlight が整数でない: $MAX_IN_FLIGHT" ;; esac

# --- データ取得 ---
# 本文を丸ごと持つと jq の引数長上限(ARG_MAX)を超えるため、一時ファイル経由で受け、
# 判定に要るフィールドだけに先に削る(本文は depends / Closes の照合にしか使わない)
TMP="$(mktemp -d)" || die "一時ディレクトリを作れない"
trap 'rm -rf "$TMP"' EXIT
FIXTURE=0
if [ -n "$ISSUES_FILE" ] || [ -n "$PRS_FILE" ]; then
  FIXTURE=1
  [ -f "$ISSUES_FILE" ] || die "--issues のファイルが無い: $ISSUES_FILE"
  [ -f "$PRS_FILE" ] || die "--prs のファイルが無い: $PRS_FILE"
  cp "$ISSUES_FILE" "$TMP/issues.raw"
  cp "$PRS_FILE" "$TMP/prs.raw"
  if [ -n "$DETAILS_FILE" ]; then cp "$DETAILS_FILE" "$TMP/details.json"; else echo '{}' >"$TMP/details.json"; fi
else
  command -v gh >/dev/null 2>&1 || die "gh が見つからない(--issues/--prs でフィクスチャを渡すこともできる)"
  REPO="${AUTOPILOT_REPO:-}"
  if [ -z "$REPO" ]; then
    # https://github.com/o/r(.git) / git@github.com:o/r.git / プロキシ経由の .../o/r のいずれも末尾 2 要素を取る
    URL="$(git remote get-url origin 2>/dev/null)" || die "origin が無い(AUTOPILOT_REPO=owner/repo で指定できる)"
    REPO="$(printf '%s' "$URL" | sed -E 's#\.git$##; s#^.*[:/]([^/:]+/[^/]+)$#\1#')"
  fi
  case "$REPO" in */*) ;; *) die "リポジトリを特定できない: $REPO" ;; esac
  gh api --paginate "repos/$REPO/issues?labels=ticket&state=all&per_page=100" >"$TMP/issues.pages" 2>/dev/null ||
    die "Issue 一覧を取得できない(gh auth status を確認する)"
  gh api --paginate "repos/$REPO/pulls?state=open&per_page=100" >"$TMP/prs.pages" 2>/dev/null ||
    die "PR 一覧を取得できない"
  # --paginate はページごとの配列を連結して出すので 1 本の配列にまとめる
  jq -s 'add // []' "$TMP/issues.pages" >"$TMP/issues.raw" 2>/dev/null || die "Issue 一覧が JSON でない"
  jq -s 'add // []' "$TMP/prs.pages" >"$TMP/prs.raw" 2>/dev/null || die "PR 一覧が JSON でない"
  echo '{}' >"$TMP/details.json"
fi

jq -e 'type == "array"' "$TMP/issues.raw" >/dev/null 2>&1 || die "Issue 一覧が JSON 配列でない"
jq -e 'type == "array"' "$TMP/prs.raw" >/dev/null 2>&1 || die "PR 一覧が JSON 配列でない"
jq -e 'type == "object"' "$TMP/details.json" >/dev/null 2>&1 || die "--details が JSON オブジェクトでない"

jq '[.[] | {number, state, title, pull_request,
            labels: [.labels[]? | (.name? // .)],
            deps: [(.body // "") | scan("depends:\\s*#(\\d+)"; "i") | .[0] | tonumber] | unique}]' \
  "$TMP/issues.raw" >"$TMP/issues.json" || die "Issue 一覧の整形に失敗した"
jq '[.[] | {number, draft: (.draft // false), head: (.head.ref // ""), sha: (.head.sha // ""),
            links: [(.body // "") | scan("(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\\s+#(\\d+)"; "i") | .[0] | tonumber] | unique}]' \
  "$TMP/prs.raw" >"$TMP/prs.json" || die "PR 一覧の整形に失敗した"

# --- 1 段目: チケットと PR の対応づけ(詳細取得の対象を絞るため先に計算する) ---
BASE="$(jq -n --slurpfile i "$TMP/issues.json" --slurpfile p "$TMP/prs.json" '
  def prio: .labels as $l
    | if ($l | index("P0")) then 0 elif ($l | index("P1")) then 1 elif ($l | index("P2")) then 2 else 3 end;

  $i[0] as $issues | $p[0] as $prs
  | ($issues | map(select(.pull_request == null))) as $t
  | ($t | map(select(.state == "open"))) as $open
  | ($t | map(select(.state == "closed") | .number)) as $closed
  | ($open | map(.number)) as $openNums
  | ($prs | map({number, draft, head, sha, issues: (.links | map(select(. as $n | $openNums | index($n))))})
         | map(select(.issues | length > 0))) as $tprs
  | ($tprs | map(.issues[]) | unique) as $withPr
  | ($open | map(select(.labels | index("in-progress")) | .number)) as $wip
  | (($wip + $withPr) | unique) as $inFlight
  | {
      open: ($open | map({number, title, priority: prio, deps})),
      closed: $closed,
      prs: $tprs,
      inFlight: $inFlight,
      stalled: ($wip - $withPr)
    }')" || die "Issue / PR の解析に失敗した"

# --- 依存先がチケット一覧に無い番号(ticket ラベル無しの Issue 等)の state を個別に引く ---
UNKNOWN="$(printf '%s' "$BASE" | jq -r '
  ([.open[].number] + .closed) as $known | [.open[].deps[]] | unique | map(select(. as $n | $known | index($n) | not)) | .[]')"
EXTRA_CLOSED='[]'
for n in $UNKNOWN; do
  if [ "$FIXTURE" = 1 ]; then
    continue # フィクスチャでは未知の依存 = 未解決として扱う
  fi
  st="$(gh api "repos/$REPO/issues/$n" --jq .state 2>/dev/null || true)"
  [ "$st" = "closed" ] && EXTRA_CLOSED="$(printf '%s' "$EXTRA_CLOSED" | jq --argjson n "$n" '. + [$n]')"
done

# --- 進行中 PR の状態(コンフリクト / CI / 変更要求)を引く ---
if [ "$FIXTURE" = 0 ]; then
  for pr in $(printf '%s' "$BASE" | jq -r '.prs[].number'); do
    sha="$(printf '%s' "$BASE" | jq -r --argjson p "$pr" '.prs[] | select(.number == $p) | .sha')"
    # mergeable_state は詳細エンドポイントでしか返らない。計算中は "unknown"(= 判定しない)
    ms="$(gh api "repos/$REPO/pulls/$pr" --jq '.mergeable_state // "unknown"' 2>/dev/null || echo unknown)"
    checks="$(gh api "repos/$REPO/commits/$sha/check-runs?per_page=100" --jq '[.check_runs[].conclusion]' 2>/dev/null || echo '[]')"
    reviews="$(gh api "repos/$REPO/pulls/$pr/reviews?per_page=100" --jq '[.[] | {user: .user.login, state}]' 2>/dev/null || echo '[]')"
    jq --arg p "$pr" --arg ms "$ms" --argjson c "$checks" --argjson r "$reviews" \
      '. + {($p): {mergeable_state: $ms, checks: $c, reviews: $r}}' "$TMP/details.json" >"$TMP/details.next" &&
      mv "$TMP/details.next" "$TMP/details.json"
  done
fi

# --- 2 段目: 判定 ---
RESULT="$(jq -n --argjson b "$BASE" --slurpfile dd "$TMP/details.json" --argjson extra "$EXTRA_CLOSED" \
  --argjson max "$MAX_IN_FLIGHT" '
  $dd[0] as $d
  | ($b.closed + $extra) as $closed
  | ($b.prs | map(. as $p | ($d[($p.number | tostring)] // {}) as $x
      | ([ (if ($x.mergeable_state // "") == "dirty" then "conflict" else empty end),
           (if ([$x.checks[]? | select(. == "failure" or . == "timed_out" or . == "cancelled" or . == "action_required")] | length) > 0
              then "ci_failed" else empty end),
           # レビュアーごとの最新の判定(COMMENTED は判定を上書きしない)
           (if ([$x.reviews[]? | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED")]
                 | group_by(.user) | map(last.state) | index("CHANGES_REQUESTED")) != null
              then "changes_requested" else empty end) ]) as $why
      | select($why | length > 0)
      | {pr: $p.number, issues: $p.issues, head: $p.head, draft: $p.draft, reasons: $why})) as $attention
  | ($b.open | map(select(.number as $n | $b.inFlight | index($n) | not))
      | map(select(all(.deps[]; . as $dep | $closed | index($dep))))
      | sort_by(.priority, .number)) as $ready
  | ([$max - ($b.inFlight | length), 0] | max) as $slots
  | (if ($attention | length) > 0 then "fix"
     elif $slots > 0 and ($ready | length) > 0 then "start"
     elif ($b.inFlight | length) > 0 then "wait"
     elif ($b.open | length) > 0 then "blocked"
     else "done" end) as $action
  | {
      action: $action,
      target: (if $action == "fix" then $attention[0].pr elif $action == "start" then $ready[0].number else null end),
      targets: (if $action == "start" then ($ready[:$slots] | map(.number)) else [] end),
      maxInFlight: $max,
      slots: $slots,
      inFlight: $b.inFlight,
      stalled: $b.stalled,
      attention: $attention,
      ready: ($ready | map({number, title, priority})),
      blocked: ($b.open | map(select(.number as $n | ($b.inFlight | index($n) | not) and ($ready | map(.number) | index($n) | not)))
                 | map({number, waitingOn: [.deps[] | select(. as $dep | $closed | index($dep) | not)]})),
      prs: ($b.prs | map({number, issues, head, draft})),
      openTickets: ($b.open | length)
    }')" || die "判定に失敗した"

if [ "$MODE" = summary ]; then
  printf '%s' "$RESULT" | jq -r '
    "action: \(.action)" + (if .target then " → #\(.target)" else "" end),
    "進行中: \(.inFlight | length)/\(.maxInFlight)(空き \(.slots))" +
      (if (.stalled | length) > 0 then " / PR 未作成の in-progress: \(.stalled | map("#\(.)") | join(", "))" else "" end),
    (if (.attention | length) > 0 then "要対応 PR: " + (.attention | map("#\(.pr)(\(.reasons | join(",")))") | join(", ")) else empty end),
    (if (.ready | length) > 0 then "着手可能: " + (.ready | map("#\(.number)") | join(", ")) else empty end),
    (if (.blocked | length) > 0 then "依存待ち: " + (.blocked | map("#\(.number)←\(.waitingOn | map("#\(.)") | join("+"))") | join(", ")) else empty end),
    "open チケット: \(.openTickets)"'
else
  printf '%s\n' "$RESULT"
fi
