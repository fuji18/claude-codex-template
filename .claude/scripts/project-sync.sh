#!/bin/bash
# GitHub Projects(v2)へのダッシュボード同期。チケット Issue を board に載せ、
# Status(Todo / In Progress / In Review / Done)と Priority を開発サイクルに合わせて動かす。
#
# **Project は表示専用。** 状態の正は Issue のラベルと PR のままで、ここは何も決めない
# (autopilot-board.sh の全体管理 Issue と同じ方針。状態を二重に持たない)。
# 自動進行の判定 autopilot-next.sh は REST だけで動く必要がある(Claude Code on the web では
# GraphQL が 403 になる)ため、GraphQL が要る Projects を判定経路には入れない。
#
# 使い方:
#   bash .claude/scripts/project-sync.sh sync-issue N      # Issue 1 件を同期する
#   bash .claude/scripts/project-sync.sh sync-pr N         # PR の Closes #N を辿って各 Issue を同期する
#   bash .claude/scripts/project-sync.sh backfill [--all]  # ticket ラベルの Issue をまとめて投入する
#                                                          # (既定は open のみ。--all で closed も)
#   bash .claude/scripts/project-sync.sh --check           # 設定・権限・名前の照合結果を出す(書き込まない)
#   bash .claude/scripts/project-sync.sh --resolve-status --issue F [--prs F]
#       フィクスチャで Status の決定だけを出す(GitHub に触らない。テスト用)。
#       F はそれぞれ REST の issue 1 件 / pulls 一覧(配列)の JSON。
#
# 設定:
#   PROJECT_URL        board の URL。https://github.com/users/<login>/projects/<番号> か
#                      https://github.com/orgs/<org>/projects/<番号>。
#                      未設定なら .claude/project-sync.json の .projectUrl を使う。
#                      どちらも空なら**何もせず exit 0**(テンプレートから作った直後に赤くしない)
#   PROJECT_SYNC_TOKEN Projects への書き込み権限を持つトークン。classic PAT なら project + repo scope。
#                      **GITHUB_TOKEN は Projects にアクセスできない**(GitHub docs に明記)。
#                      未設定なら手元の gh の認証をそのまま使う(人間が backfill を回す経路)
#   .claude/project-sync.json  ラベル名と Status / Priority の名前候補(board の命名はプロジェクト固有)
#
# Status の決め方(イベント種別は見ない = 冪等。取りこぼしや順序の入れ替わりで board がずれない):
#   closed                            → done
#   Closes #N で紐づく open PR がある  → inReview(draft も含む。econ は draft で積む運用)
#   in-progress ラベルがある           → inProgress
#   それ以外                           → todo
#   fork の PR は紐づけない(autopilot-next.sh の untrustedPrs と同じ境界)
#
# done になるのは Issue が closed になったときだけ。GitHub の `Closes #N` は
# **既定ブランチへのマージでしか Issue を自動クローズしない**ので、baseBranch を develop に
# している構成では、feature → develop のマージ時点では done にならず inProgress に戻る
# (in-progress ラベルが残っている限り)。done はリリース PR が main に入った時点で付く。
#
# 終了コード: 0 = 成功 / 未設定でスキップ / 2 = 設定・取得・更新の失敗
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 2

SELF=project-sync.sh
die() {
  echo "$SELF: $*" >&2
  exit 2
}
warn() { echo "$SELF: $*" >&2; }
note() { echo "$SELF: $*"; }

command -v jq >/dev/null 2>&1 || die "jq が見つからない"

CONF=.claude/project-sync.json
TMPFILES=()
cleanup() {
  local f
  for f in ${TMPFILES[@]+"${TMPFILES[@]}"}; do [ -n "$f" ] && rm -f "$f"; done
}
trap cleanup EXIT
mktmp() {
  local f
  f="$(mktemp)" || die "一時ファイルを作れない"
  TMPFILES+=("$f")
  printf '%s' "$f"
}

# --- 引数 ---
MODE=""
ARG_NUMBER=""
BACKFILL_ALL=0
FIX_ISSUE=""
FIX_PRS=""
while [ $# -gt 0 ]; do
  case "$1" in
    sync-issue | sync-pr)
      MODE="$1"
      ARG_NUMBER="${2:-}"
      shift
      ;;
    backfill) MODE=backfill ;;
    --all) BACKFILL_ALL=1 ;;
    --check) MODE=check ;;
    --resolve-status) MODE=resolve-status ;;
    --issue)
      FIX_ISSUE="${2:-}"
      shift
      ;;
    --prs)
      FIX_PRS="${2:-}"
      shift
      ;;
    -h | --help)
      sed -n '2,40p' "$0"
      exit 0
      ;;
    *) die "不明な引数: $1" ;;
  esac
  shift
done
[ -n "$MODE" ] || die "サブコマンドを指定する(sync-issue / sync-pr / backfill / --check / --resolve-status)"

# --- 設定の読み込み ---
if [ -f "$CONF" ]; then
  jq -e . "$CONF" >/dev/null 2>&1 || die "$CONF が JSON として読めない"
fi

conf_str() { # $1=キー $2=既定値
  local v=""
  [ -f "$CONF" ] &&
    v="$(jq -r --arg k "$1" 'if (.[$k] | type) == "string" then .[$k] else empty end' "$CONF" 2>/dev/null)"
  if [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' "$2"; fi
}
# $1 = 自分で書く定数の jq 式(利用者の入力は入れない) / $2 = 既定の JSON 配列
conf_arr() {
  local v=""
  [ -f "$CONF" ] &&
    v="$(jq -c "($1) as \$v | if (\$v | type) == \"array\" and (\$v | all(type == \"string\")) then \$v else empty end" "$CONF" 2>/dev/null)"
  if [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' "$2"; fi
}
priority_keys() {
  [ -f "$CONF" ] || return 0
  jq -r '(.priority // {}) | keys_unsorted | .[]' "$CONF" 2>/dev/null
}
priority_candidates() { # $1=優先度のキー(ラベル名)
  local v=""
  [ -f "$CONF" ] &&
    v="$(jq -c --arg k "$1" '(.priority[$k]) as $v | if ($v | type) == "array" and ($v | all(type == "string")) then $v else empty end' "$CONF" 2>/dev/null)"
  if [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' '[]'; fi
}

TICKET_LABEL="$(conf_str ticketLabel ticket)"
INPROGRESS_LABEL="$(conf_str inProgressLabel in-progress)"
STATUS_FIELD_NAMES="$(conf_arr '.statusField' '["Status"]')"
PRIORITY_FIELD_NAMES="$(conf_arr '.priorityField' '["Priority"]')"
STATUS_TODO="$(conf_arr '.status.todo' '["Todo"]')"
STATUS_INPROGRESS="$(conf_arr '.status.inProgress' '["In Progress"]')"
STATUS_INREVIEW="$(conf_arr '.status.inReview' '["In Review"]')"
STATUS_DONE="$(conf_arr '.status.done' '["Done"]')"

status_candidates() { # $1=status キー → 候補の JSON 配列
  case "$1" in
    todo) printf '%s' "$STATUS_TODO" ;;
    inProgress) printf '%s' "$STATUS_INPROGRESS" ;;
    inReview) printf '%s' "$STATUS_INREVIEW" ;;
    done) printf '%s' "$STATUS_DONE" ;;
    *) printf '%s' '[]' ;;
  esac
}

# --- Status の決定(ここだけは GitHub に触らない = フィクスチャで検証できる) ---
# $1 = issue JSON のファイル / $2 = open PR 一覧 JSON のファイル(空文字なら PR なし扱い)
decide_status() {
  local issue_file="$1" prs_file="${2:-}" prs_arg='[]'
  if [ -n "$prs_file" ] && [ -f "$prs_file" ]; then
    prs_arg="$(jq -c 'if type == "array" then . else [] end' "$prs_file" 2>/dev/null)" ||
      die "PR 一覧の JSON を読めない: $prs_file"
  fi
  jq -r --argjson prs "$prs_arg" --arg ipl "$INPROGRESS_LABEL" '
    . as $i
    | ($i.number) as $n
    | if ($i.state // "open") == "closed" then "done"
      else
        # fork の PR は紐づけない。本文に Closes #N と書くだけで外部の人が board を動かせてはならない
        ([ $prs[]
           | select((.state // "open") == "open")
           | select((.head.repo.full_name // "") != ""
                    and (.head.repo.full_name // "") == (.base.repo.full_name // ""))
           | ((.body // "")
              | [ match("\\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\\s+#(\\d+)"; "gi")
                  | .captures[0].string | tonumber ])
           | select(index($n) != null)
         ] | length) as $linked
        | if $linked > 0 then "inReview"
          elif ([ $i.labels[]? | (if type == "object" then .name else . end) ] | index($ipl) != null)
            then "inProgress"
          else "todo"
          end
      end' "$issue_file" 2>/dev/null || die "Status を決定できない: $issue_file"
}

if [ "$MODE" = resolve-status ]; then
  [ -n "$FIX_ISSUE" ] || die "--resolve-status には --issue FILE が要る"
  [ -f "$FIX_ISSUE" ] || die "issue のフィクスチャが無い: $FIX_ISSUE"
  decide_status "$FIX_ISSUE" "$FIX_PRS"
  exit 0
fi

# --- board の場所(未設定なら GitHub に触る前に抜ける) ---
PROJECT_URL="${PROJECT_URL:-$(conf_str projectUrl '')}"
if [ -z "$PROJECT_URL" ]; then
  note "PROJECT_URL が未設定のため何もしない(board 同期は無効)"
  exit 0
fi

OWNER_ROOT=""
case "$PROJECT_URL" in
  *://*/users/*/projects/*) OWNER_ROOT=user ;;
  *://*/orgs/*/projects/*) OWNER_ROOT=organization ;;
  *) die "PROJECT_URL の形が違う(https://github.com/{users|orgs}/<name>/projects/<番号>): $PROJECT_URL" ;;
esac
OWNER_LOGIN="$(printf '%s' "$PROJECT_URL" | sed -E 's#^.*/(users|orgs)/([^/]+)/projects/.*$#\2#')"
PROJECT_NUMBER="$(printf '%s' "$PROJECT_URL" | sed -E 's#^.*/projects/([0-9]+).*$#\1#')"
[ -n "$OWNER_LOGIN" ] || die "PROJECT_URL から owner を取れない: $PROJECT_URL"
case "$PROJECT_NUMBER" in '' | *[!0-9]*) die "PROJECT_URL から project 番号を取れない: $PROJECT_URL" ;; esac

# --- ここから先は GitHub に触る ---
command -v gh >/dev/null 2>&1 || die "gh が見つからない"
# shellcheck source=lib-github.sh
. .claude/scripts/lib-github.sh 2>/dev/null || die "lib-github.sh が読めない"
REPO="$(gh_resolve_repo)" || die "リポジトリを特定できない(AUTOPILOT_REPO=owner/repo で指定できる)"

# REST は Actions の GITHUB_TOKEN で足りる。Projects(GraphQL)だけが PAT を要る
REST_TOKEN="${GITHUB_TOKEN:-}"
PROJECT_TOKEN="${PROJECT_SYNC_TOKEN:-}"

rest() { # REST_TOKEN が空なら手元の gh 認証をそのまま使う
  if [ -n "$REST_TOKEN" ]; then GH_TOKEN="$REST_TOKEN" gh api "$@"; else gh api "$@"; fi
}
gql() {
  if [ -n "$PROJECT_TOKEN" ]; then GH_TOKEN="$PROJECT_TOKEN" gh api graphql "$@"; else gh api graphql "$@"; fi
}

# --- Project とフィールドの解決(1 回の実行で 1 度だけ引く) ---
PROJECT_ID=""
PROJECT_FIELDS=""
STATUS_FIELD_ID=""
STATUS_FIELD_JSON=""
PRIORITY_FIELD_JSON=""

# board の列名はプロジェクトごとに違うので、候補の順に大小文字と前後空白を無視して照合する
NORM_DEF='
  def norm: (. // "") | ascii_downcase | gsub("^[[:space:]]+|[[:space:]]+$"; "");
'
PICK_FIELD='
    ($c | map(norm)) as $want
    | [ .fields.nodes[]? | select(.name != null) ] as $fs
    | (first($want[] as $w | ($fs[] | select((.name | norm) == $w)))) // empty'

resolve_project() {
  [ -n "$PROJECT_ID" ] && return 0
  local out
  out="$(gql -f login="$OWNER_LOGIN" -F number="$PROJECT_NUMBER" -f query="
    query(\$login: String!, \$number: Int!) {
      $OWNER_ROOT(login: \$login) {
        projectV2(number: \$number) {
          id
          title
          fields(first: 50) {
            nodes { ... on ProjectV2SingleSelectField { id name options { id name } } }
          }
        }
      }
    }" --jq ".data.$OWNER_ROOT.projectV2" 2>&1)" ||
    die "Project を取得できない($PROJECT_URL)。PROJECT_SYNC_TOKEN に Projects の権限があるか確認する(classic PAT なら project scope。GITHUB_TOKEN は Projects にアクセスできない): $out"
  { [ -n "$out" ] && [ "$out" != null ]; } || die "Project が見つからない: $PROJECT_URL"

  PROJECT_FIELDS="$out"
  PROJECT_ID="$(jq -r '.id // empty' <<<"$out")"
  [ -n "$PROJECT_ID" ] || die "Project の ID を取れない: $PROJECT_URL"

  STATUS_FIELD_JSON="$(jq -c --argjson c "$STATUS_FIELD_NAMES" "$NORM_DEF$PICK_FIELD" <<<"$out")" ||
    STATUS_FIELD_JSON=""
  [ -n "$STATUS_FIELD_JSON" ] ||
    die "Status フィールドが board に無い(候補: $STATUS_FIELD_NAMES)。$CONF の statusField を board の列名に合わせる"
  STATUS_FIELD_ID="$(jq -r '.id' <<<"$STATUS_FIELD_JSON")"

  # Priority フィールドが無いのは正常(優先度列を作らない運用がある)
  PRIORITY_FIELD_JSON="$(jq -c --argjson c "$PRIORITY_FIELD_NAMES" "$NORM_DEF$PICK_FIELD" <<<"$out")" ||
    PRIORITY_FIELD_JSON=""
}

option_id() { # $1=フィールドの JSON $2=候補の JSON 配列 → option id(無ければ空)
  jq -r --argjson c "$2" "$NORM_DEF"'
    ($c | map(norm)) as $want
    | [ .options[]? ] as $os
    | ((first($want[] as $w | ($os[] | select((.name | norm) == $w)))) | .id) // empty' <<<"$1" 2>/dev/null
}

add_item() { # $1=content の node ID → item ID(既にあれば既存の item ID が返る = 冪等)
  gql -f project="$PROJECT_ID" -f content="$1" -f query='
    mutation($project: ID!, $content: ID!) {
      addProjectV2ItemById(input: { projectId: $project, contentId: $content }) { item { id } }
    }' --jq '.data.addProjectV2ItemById.item.id' 2>&1
}

set_select() { # $1=item ID $2=field ID $3=option ID
  gql -f project="$PROJECT_ID" -f item="$1" -f field="$2" -f option="$3" -f query='
    mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
      updateProjectV2ItemFieldValue(
        input: { projectId: $project, itemId: $item, fieldId: $field,
                 value: { singleSelectOptionId: $option } }
      ) { projectV2Item { id } }
    }' --jq '.data.updateProjectV2ItemFieldValue.projectV2Item.id' 2>&1
}

# --- open PR 一覧(Closes #N の照合用。1 回の実行で 1 度だけ引く) ---
PRS_CACHE=""
ensure_prs() {
  [ -n "$PRS_CACHE" ] && return 0
  PRS_CACHE="$(mktmp)"
  rest "repos/$REPO/pulls?state=open&per_page=100" \
    --jq '[.[] | {number, state, body, head: {repo: {full_name: (.head.repo.full_name // "")}}, base: {repo: {full_name: (.base.repo.full_name // "")}}}]' \
    >"$PRS_CACHE" 2>/dev/null || die "open PR の一覧を取得できない($REPO)"
}

# --- Issue 1 件の同期 ---
sync_issue() {
  local n="$1" issue_file status opt item prio_key prio_opt k
  case "$n" in '' | *[!0-9]*) die "Issue 番号が数字でない: $n" ;; esac

  issue_file="$(mktmp)"
  rest "repos/$REPO/issues/$n" \
    --jq '{number, state, node_id, pull_request: (.pull_request // null), labels: [.labels[]? | .name]}' \
    >"$issue_file" 2>/dev/null || die "Issue #$n を取得できない($REPO)"

  if [ "$(jq -r '.pull_request // "null"' "$issue_file")" != null ]; then
    note "#$n は PR なのでスキップ(board に載せるのは Issue だけ)"
    return 0
  fi
  if ! jq -e --arg l "$TICKET_LABEL" '[.labels[]?] | index($l) != null' "$issue_file" >/dev/null 2>&1; then
    note "#$n は $TICKET_LABEL ラベルが無いのでスキップ"
    return 0
  fi

  if [ "$(jq -r '.state // "open"' "$issue_file")" = closed ]; then
    status="$(decide_status "$issue_file" '')"
  else
    ensure_prs
    status="$(decide_status "$issue_file" "$PRS_CACHE")"
  fi

  resolve_project

  local content_id
  content_id="$(jq -r '.node_id // empty' "$issue_file")"
  [ -n "$content_id" ] || die "Issue #$n の node_id を取れない"

  item="$(add_item "$content_id")"
  case "$item" in
    PVTI_*) : ;;
    *) die "#$n を board に追加できない: $item" ;;
  esac

  opt="$(option_id "$STATUS_FIELD_JSON" "$(status_candidates "$status")")"
  if [ -z "$opt" ]; then
    warn "#$n: Status '$status' に対応する列が board に無いので Status は変えない(候補: $(status_candidates "$status"))"
  else
    set_select "$item" "$STATUS_FIELD_ID" "$opt" >/dev/null || die "#$n の Status を設定できない"
    note "#$n → Status=$status"
  fi

  # 優先度ラベル → Priority フィールド(フィールドが無いのは正常。警告も出さない)
  if [ -n "$PRIORITY_FIELD_JSON" ]; then
    prio_key=""
    for k in $(priority_keys); do
      if jq -e --arg l "$k" '[.labels[]?] | index($l) != null' "$issue_file" >/dev/null 2>&1; then
        prio_key="$k"
        break
      fi
    done
    if [ -n "$prio_key" ]; then
      prio_opt="$(option_id "$PRIORITY_FIELD_JSON" "$(priority_candidates "$prio_key")")"
      if [ -n "$prio_opt" ]; then
        set_select "$item" "$(jq -r '.id' <<<"$PRIORITY_FIELD_JSON")" "$prio_opt" >/dev/null ||
          warn "#$n の Priority を設定できない(Status は反映済み)"
      else
        warn "#$n: 優先度 '$prio_key' に対応する選択肢が board に無い"
      fi
    fi
  fi
  return 0
}

# --- PR から辿る ---
sync_pr() {
  local n="$1" pr_file nums i
  case "$n" in '' | *[!0-9]*) die "PR 番号が数字でない: $n" ;; esac
  pr_file="$(mktmp)"
  rest "repos/$REPO/pulls/$n" \
    --jq '{number, body, head: {repo: {full_name: (.head.repo.full_name // "")}}, base: {repo: {full_name: (.base.repo.full_name // "")}}}' \
    >"$pr_file" 2>/dev/null || die "PR #$n を取得できない($REPO)"

  if ! jq -e '(.head.repo.full_name != "") and (.head.repo.full_name == .base.repo.full_name)' "$pr_file" >/dev/null 2>&1; then
    note "PR #$n は fork からなので board に反映しない"
    return 0
  fi

  nums="$(jq -r '(.body // "")
    | [ match("\\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\\s+#(\\d+)"; "gi")
        | .captures[0].string ] | unique | .[]' "$pr_file" 2>/dev/null)"
  if [ -z "$nums" ]; then
    note "PR #$n の本文に Closes #N が無いので対象なし"
    return 0
  fi
  for i in $nums; do sync_issue "$i"; done
}

# --- まとめて投入 ---
backfill() {
  local state=open list i
  [ "$BACKFILL_ALL" = 1 ] && state=all
  # --paginate で全ページを辿る(進行中のプロジェクトに投入するとき 100 件で切れないように)。
  # --jq はページごとに適用されるため、ページ内で sort した番号が行ごとに連なって出る。
  list="$(rest --paginate "repos/$REPO/issues?labels=$TICKET_LABEL&state=$state&per_page=100" \
    --jq '[.[] | select(.pull_request == null) | .number] | sort | .[]' 2>/dev/null)" ||
    die "$TICKET_LABEL ラベルの Issue を一覧できない($REPO)"
  if [ -z "$list" ]; then
    note "$TICKET_LABEL ラベルの Issue が無い(state=$state)"
    return 0
  fi
  for i in $list; do sync_issue "$i"; done
}

# --- 設定の疎通確認(書き込まない) ---
check() {
  local k opt
  note "repo: $REPO"
  note "project: $PROJECT_URL($OWNER_ROOT=$OWNER_LOGIN / number=$PROJECT_NUMBER)"
  if [ -n "$PROJECT_TOKEN" ]; then
    note "token: PROJECT_SYNC_TOKEN を使う"
  else
    note "token: 手元の gh 認証を使う(PROJECT_SYNC_TOKEN 未設定)"
  fi
  resolve_project
  note "project id: $PROJECT_ID / title: $(jq -r '.title // "?"' <<<"$PROJECT_FIELDS")"
  note "Status フィールド: $(jq -r '.name' <<<"$STATUS_FIELD_JSON")"
  for k in todo inProgress inReview "done"; do # done はクォート必須(予約語と読まれる)
    opt="$(option_id "$STATUS_FIELD_JSON" "$(status_candidates "$k")")"
    if [ -n "$opt" ]; then
      note "  $k → $(jq -r --arg id "$opt" '.options[] | select(.id == $id) | .name' <<<"$STATUS_FIELD_JSON")"
    else
      warn "  $k → 対応する列が無い(候補: $(status_candidates "$k"))"
    fi
  done
  if [ -n "$PRIORITY_FIELD_JSON" ]; then
    note "Priority フィールド: $(jq -r '.name' <<<"$PRIORITY_FIELD_JSON")"
    for k in $(priority_keys); do
      opt="$(option_id "$PRIORITY_FIELD_JSON" "$(priority_candidates "$k")")"
      if [ -n "$opt" ]; then
        note "  $k → $(jq -r --arg id "$opt" '.options[] | select(.id == $id) | .name' <<<"$PRIORITY_FIELD_JSON")"
      else
        warn "  $k → 対応する選択肢が無い(候補: $(priority_candidates "$k"))"
      fi
    done
  else
    note "Priority フィールドは board に無い(優先度は反映しない)"
  fi
  note "ラベル: ticket=$TICKET_LABEL / in-progress=$INPROGRESS_LABEL"
}

case "$MODE" in
  sync-issue) sync_issue "$ARG_NUMBER" ;;
  sync-pr) sync_pr "$ARG_NUMBER" ;;
  backfill) backfill ;;
  check) check ;;
  *) die "不明なモード: $MODE" ;;
esac

exit 0
