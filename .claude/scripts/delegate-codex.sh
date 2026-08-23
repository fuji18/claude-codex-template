#!/bin/bash
# Codex への委託経路(唯一の入口)。
#
#   .claude/scripts/delegate-codex.sh <mode> <target>
#
# 段階2 で実装するのは読み取り専用の 2 モードだけ:
#   explore <調査指示 | ファイルパス>  … 広域コード探索。サマリーのみ返す
#   review  <base-ref>                … 敵対的レビュー。指摘リストを返す
# impl / fix-ci(workspace-write)と --background は段階3。
#
# 終了コード契約(司令塔はこの値だけを見て分岐する。推測しない):
#   0 完了                             → 検収へ
#   1 判断待ち                         → design.md に追記して再委託
#   2 失敗(タスク起因・使い方の誤り)  → 原因分析
#   3 Codex 利用不可(CLI 不在・未認証・依存未インストール)→ 恒久フォールバック
#   4 Codex 側のレート上限             → 一時フォールバック(待つ or Sonnet fork)
#   5 計画が未完成(段階3 の impl でのみ使う)
#
# 3 と 4 を混ぜないこと。前者は環境の欠落(恒久)、後者は枠切れ(一時)で
# 回復手段が違う。
#
# フェイルオープンにしない(保護ブランチ検査とは方針が逆)。
# 保護ブランチ検査は止めるとコミットが不能になるためフェイルオープンだが、
# 委託は止めても作業が継続できる(Sonnet fork がある)。止めたコストが小さく、
# 通したコスト(枠の消費・機密の送信)が大きいので、非対称が逆向きになる。
#
# 出力はサマリーのみ。生ログは .harness/codex-runs/[id].log に落とす。
#
# 参照: docs/template-dev/codex-delegation-plan.md §3
set -uo pipefail

EX_FAIL=2
EX_UNAVAIL=3
EX_RATELIMIT=4

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$ROOT" ]; then
  echo "delegate-codex: git リポジトリの外では実行できません" >&2
  exit "$EX_FAIL"
fi
cd "$ROOT" || exit "$EX_FAIL"

# ---------- 引数 ----------

MODE="${1:-}"
[ $# -ge 1 ] && shift
TARGET="${1:-}"
[ $# -ge 1 ] && shift

usage() {
  cat >&2 <<'USAGE'
使い方: .claude/scripts/delegate-codex.sh <mode> <target>

  explore <調査指示 | ファイルパス>   広域コード探索(read-only)
  review  <base-ref>                 敵対的レビュー(read-only)

環境変数:
  CODEX_HARNESS_MODE          ハーネスモードの上書き(既定は .harness/mode)
  CODEX_DELEGATE_ACK_SECRETS  機密ファイル検出時の承認(=1 で続行)
USAGE
}

case "$MODE" in
  explore | review) ;;
  impl | fix-ci)
    echo "delegate-codex: '$MODE' は段階3 で実装します(現在は explore / review のみ)" >&2
    exit "$EX_FAIL"
    ;;
  *)
    usage
    exit "$EX_FAIL"
    ;;
esac

if [ -z "$TARGET" ]; then
  echo "delegate-codex: target が空です" >&2
  usage
  exit "$EX_FAIL"
fi

# 余剰オプションは黙って無視しない。「指定したのに効いていない」に
# 気づけないのが一番まずい。
if [ $# -gt 0 ]; then
  case "$1" in
    --background)
      echo "delegate-codex: --background は段階3(impl)で実装します" >&2
      ;;
    *)
      echo "delegate-codex: 未知のオプション: $1" >&2
      ;;
  esac
  exit "$EX_FAIL"
fi

# ---------- 入口検査0: このスクリプトが依存する外部コマンド ----------
#
# find / grep が無いと下の機密チェックが「何も見つからなかった」と同じ形で
# 黙って通ってしまう。フェイルクローズと宣言した層が静かに素通しするのは、
# 層が無いことより悪い。ここで明示的に落とす。

for _cmd in find grep sed head tail tr; do
  if ! command -v "$_cmd" >/dev/null 2>&1; then
    echo "delegate-codex: '$_cmd' が見つかりません。入口検査が成立しないため委託しません。" >&2
    exit "$EX_UNAVAIL"
  fi
done

# ---------- 入口検査1: 機密ファイル ----------
#
# Codex の sandbox は「書き込み」の制限であり、読み取りの deny-list は
# 存在しない(§13 #7 で確定)。.gitignore されていてもディスク上にあれば
# 読めるため、委託は機密を委託先へ送りうる。入口の人間確認が唯一の層。
#
# 何を機密とみなすかはプロジェクト固有(§10.2)なので、パターンは
# .claude/codex-denylist.txt に外出しし、ここでは読むだけにする。

DENYLIST=".claude/codex-denylist.txt"

if [ ! -f "$DENYLIST" ]; then
  echo "delegate-codex: $DENYLIST がありません。機密チェックが成立しないため委託しません。" >&2
  exit "$EX_UNAVAIL"
fi

# find の式を denylist から組み立てる。
# / を含むパターンはパス一致、含まないパターンはファイル名一致。
FIND_EXPR=()
while IFS= read -r _line || [ -n "$_line" ]; do
  _line="${_line%%#*}"
  _line="$(printf '%s' "$_line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -z "$_line" ] && continue
  [ ${#FIND_EXPR[@]} -gt 0 ] && FIND_EXPR+=(-o)
  case "$_line" in
    */*) FIND_EXPR+=(-path "./$_line") ;;
    *) FIND_EXPR+=(-name "$_line") ;;
  esac
done <"$DENYLIST"

if [ ${#FIND_EXPR[@]} -eq 0 ]; then
  echo "delegate-codex: $DENYLIST に有効なパターンがありません。委託しません。" >&2
  exit "$EX_UNAVAIL"
fi

# -maxdepth は付けない。深い階層の .env を見逃すため。
# 代わりに node_modules / .git / .harness を prune して走査量を抑える。
SENSITIVE="$(
  find . \
    \( -name node_modules -o -name .git -o -name .harness \) -prune -o \
    \( "${FIND_EXPR[@]}" \) -type f -print 2>/dev/null |
    grep -Ev '\.(example|sample|template)$' |
    head -20
)"

if [ -n "$SENSITIVE" ]; then
  cat >&2 <<'MSG'
delegate-codex: ワークツリーに機密の可能性があるファイルがあります。

Codex の sandbox には読み取りの除外機能が無いため、これらは委託先へ
送られうる。内容を確認し、問題なければ承認して再実行してください:

  CODEX_DELEGATE_ACK_SECRETS=1 .claude/scripts/delegate-codex.sh ...

該当:
MSG
  echo "$SENSITIVE" | sed 's/^/  /' >&2
  if [ "${CODEX_DELEGATE_ACK_SECRETS:-}" != "1" ]; then
    exit "$EX_FAIL"
  fi
fi

# ---------- 入口検査2・3: AGENTS.md と依存の導通 ----------

AGENTS="AGENTS.md"
if [ ! -f "$AGENTS" ]; then
  cat >&2 <<'MSG'
delegate-codex: AGENTS.md がありません。

Codex は CLAUDE.md も hooks も permissions も読みません。AGENTS.md が
規約の唯一の写像なので、これが無い状態では委託しません。
MSG
  exit "$EX_UNAVAIL"
fi

# 検査の機構はこのスクリプト、検査の中身は AGENTS.md 側に置く。
# delegate-codex.sh はテンプレート所有で全プロジェクトに配られるため、
# node_modules のようなスタック固有のものを決め打ちで見てはいけない。
PROBE="$(sed -n 's/^[[:space:]]*<!--[[:space:]]*verify-probe:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*-->[[:space:]]*$/\1/p' "$AGENTS" | head -1)"

if [ -z "$PROBE" ]; then
  # AGENTS.md は merge 区分でプロジェクトが書き換える。マーカー未反映の
  # プロジェクトを止めないため、ここだけはフェイルオープン。
  echo "delegate-codex: 警告 — AGENTS.md に <!-- verify-probe: ... --> がありません。依存の導通確認をスキップします。" >&2
elif ! bash -c "$PROBE" >/dev/null 2>&1; then
  cat >&2 <<MSG
delegate-codex: 検証プローブが失敗しました: $PROBE

依存が未インストールの可能性があります。Codex の sandbox はネットワーク
無効のため、この状態で委託すると何も完遂できないまま枠だけを消費します。
先に依存をインストールしてから再実行してください。
MSG
  exit "$EX_UNAVAIL"
fi

# ---------- 入口検査4: Codex CLI ----------

if ! command -v codex >/dev/null 2>&1; then
  cat >&2 <<'MSG'
delegate-codex: codex コマンドが見つかりません(Codex 利用不可)。

司令塔は恒久フォールバック(Sonnet fork)に切り替えてください。
導入手順は docs/template-dev/codex-delegation-plan.md §11 の段階0。
MSG
  exit "$EX_UNAVAIL"
fi

# codex login status はログイン済みなら 0 を返す(公式が自動化向けに明記)。
# 事前に落とせば枠を一切消費しない。
if ! codex login status >/dev/null 2>&1; then
  cat >&2 <<'MSG'
delegate-codex: Codex が未認証です(Codex 利用不可)。

  codex login

を実行してから再委託してください。当面は Sonnet fork にフォールバック。
MSG
  exit "$EX_UNAVAIL"
fi

# ---------- ハーネスモード ----------
#
# 読む順序は固定する: プロンプト経由の上書き > .harness/mode > normal。
# AGENTS.md 側にも同じ順序を書いてある(モード C はこの経路を通らないため)。

HMODE="${CODEX_HARNESS_MODE:-}"
if [ -z "$HMODE" ] && [ -f .harness/mode ]; then
  HMODE="$(tr -d '[:space:]' <.harness/mode)"
fi
[ -n "$HMODE" ] || HMODE="normal"

# ---------- run record ----------
#
# §3.2: これが状態の正。会話に依存しないので、委託を挟んで /clear できる。

RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR=".harness/codex-runs"
mkdir -p "$RUN_DIR" || exit "$EX_FAIL"
LOG="$RUN_DIR/$RUN_ID.log"
REC="$RUN_DIR/$RUN_ID.json"
LAST="$RUN_DIR/$RUN_ID.last.txt"
BRANCH="$(git branch --show-current 2>/dev/null || true)"

json_str() {
  # jq が使えれば任せる。ただし空を返させないこと — record は状態の正なので、
  # ここが空文字列を返すと `"summary": ,` のような壊れた JSON になり、
  # 「委託を挟んで /clear できる」という前提ごと崩れる。
  # (サマリーは 2000 バイトで切るため、末尾がマルチバイト文字の途中に
  #  なりうる。jq がそれを拒む場合に備えて下のフォールバックへ落とす)
  local _out=""
  if command -v jq >/dev/null 2>&1; then
    _out="$(printf '%s' "${1:-}" | jq -Rs . 2>/dev/null)"
    if [ -n "$_out" ]; then
      printf '%s' "$_out"
      return
    fi
  fi
  printf '"%s"' "$(printf '%s' "${1:-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\t' '  ')"
}

json_or_null() {
  if [ -z "${1:-}" ]; then printf 'null'; else json_str "$1"; fi
}

# $1=status $2=summary $3=error $4=resetAt
write_record() {
  cat >"$REC" <<JSON
{
  "id": $(json_str "$RUN_ID"),
  "mode": $(json_str "$MODE"),
  "target": $(json_str "$TARGET"),
  "steering": null,
  "branch": $(json_str "$BRANCH"),
  "harnessMode": $(json_str "$HMODE"),
  "pid": $$,
  "status": $(json_str "$1"),
  "resetAt": $(json_or_null "${4:-}"),
  "summary": $(json_or_null "${2:-}"),
  "error": $(json_or_null "${3:-}"),
  "log": $(json_str "$LOG"),
  "accepted": false
}
JSON
}

# $1=status $2=exit-code
emit() {
  printf '[codex:%s] status=%s id=%s exit=%s\n' "$MODE" "$1" "$RUN_ID" "$2"
  printf 'log: %s\n' "$LOG"
}

# ---------- プロンプト構築(参照渡し。内容は貼らない) ----------

PREAMBLE="あなたは読み取り専用(--sandbox read-only)で起動されています。ファイルの変更・コミットは行わないでください。

まず $AGENTS を読み、そこに書かれた規約に従ってください。
現在のハーネスモード: $HMODE"

case "$MODE" in
  explore)
    if [ -f "$TARGET" ]; then
      TASK="次のファイルに書かれた調査指示に従ってください: $TARGET"
    else
      TASK="次の調査を行ってください: $TARGET"
    fi
    PROMPT="$PREAMBLE

$TASK

出力は次の形式の**サマリーのみ**にしてください(ファイル全文や長い引用を貼らない):
- 結論(3 行以内)
- 根拠(path:line の形式で最大 10 件)
- 残る不確実性(あれば 1 行)"
    ;;
  review)
    PROMPT="$PREAMBLE

git diff $TARGET...HEAD の差分を敵対的にレビューしてください。
差分もファイルも自分で読んでください(この指示には貼っていません)。

出力は次の形式の**指摘リストのみ**にしてください:
- [P0|P1|P2] path:line — 指摘の要旨(1 行)/ 失敗シナリオ(1 行)
指摘が無ければ「指摘なし」とだけ書いてください。"
    ;;
esac

# ---------- 実行 ----------
#
# sandbox は設定ファイルではなくフラグで渡す。CLI フラグは project config に
# 優先し、untrusted なプロジェクトでは .codex/ が丸ごと読まれないため、
# .codex/config.toml が効いている保証が無い(§7.2 / §9)。

write_record "running" "" "" ""

codex exec \
  --cd "$ROOT" \
  --sandbox read-only \
  --json \
  --color never \
  --output-last-message "$LAST" \
  "$PROMPT" >"$LOG" 2>&1
CODEX_EXIT=$?

# ---------- 出口判定 ----------
#
# 判定順は 上限 → 認証 → その他。認証パターン(401 等)は上限応答にも
# 混ざりうるため、上限を先に見る。
#
# ── 何を、どの範囲で見るか(重要)────────────────────────
#
# ログは --json の全イベント = Codex が読んだファイルの引用を含む。
# したがって「ログ全体を文言で検索する」と、レビュー対象のファイルに
# たまたま "quota" や "rate limit" と書かれているだけで上限と誤判定する。
# このスクリプト自身とハーネスの計画文書がまさにそれに当たり、
# 自分をレビュー対象にすると成功した委託が exit 4 に化けた(実測)。
#
# そこで範囲を 2 つに分ける:
#   - 成功(exit 0)したときは上限・認証の判定を一切しない。
#     完走してサマリーが出ている以上、上限では終わっていない。
#     仮に本文が上限に触れていても、そのサマリーは標準出力に出るので
#     人間・司令塔の目に入る = 見逃しても静かではない。
#   - 失敗(exit 非ゼロ)したときだけ判定する。構造化識別子はログ全体に
#     当ててよいが、緩い文言パターンは末尾 20 行のうち "error" / "fail"
#     を含む行だけに当てる。末尾に絞るだけでは足りない — 失敗した委託の
#     末尾にも、Codex が読んだファイルの引用は来る。
#
# 「誤検知より見逃しの方が高くつく」という当初の判断は、見逃しが静かに
# 起きることを前提にしていた。成功時はそうではないので前提が成り立たない。

RATE_ID_RE='rate_limit_reached|usage_limit_reached|credits_depleted'
RATE_TEXT_RE='rate limit|usage limit|quota|429'
AUTH_RE='unauthorized|not logged in|invalid_api_key|authentication_error|401'

ERR_TAIL="$(grep -Ev '^[[:space:]]*$' "$LOG" 2>/dev/null | tail -20)"
ERR3="$(printf '%s' "$ERR_TAIL" | tail -3 | tr '\n' ' ')"

# 緩い文言パターンは「エラーらしい行」だけに当てる。末尾 20 行に絞っても、
# Codex が読んだファイルの引用がそこに来ることはある(実測)。
ERR_ONLY="$(printf '%s' "$ERR_TAIL" | grep -Ei 'error|fail' || true)"
SUMMARY=""
[ -f "$LAST" ] && SUMMARY="$(head -c 2000 "$LAST")"

if [ "$CODEX_EXIT" -ne 0 ]; then
  if grep -Eqi "$RATE_ID_RE" "$LOG" 2>/dev/null ||
    printf '%s' "$ERR_ONLY" | grep -Eqi "$RATE_TEXT_RE"; then
    RESET_AT="$(grep -Eo '"reset[_a-zA-Z]*"[[:space:]]*:[[:space:]]*"[^"]*"' "$LOG" 2>/dev/null | head -1 | sed 's/.*: *"\(.*\)"/\1/')"
    write_record "rate-limited" "" "$ERR3" "$RESET_AT"
    emit "rate-limited" "$EX_RATELIMIT"
    echo "Codex 側のレート上限です。待つか Sonnet fork にフォールバックしてください。" >&2
    [ -n "$RESET_AT" ] && echo "reset: $RESET_AT" >&2
    exit "$EX_RATELIMIT"
  fi

  if printf '%s' "$ERR_ONLY" | grep -Eqi "$AUTH_RE"; then
    write_record "unavailable" "" "$ERR3" ""
    emit "unavailable" "$EX_UNAVAIL"
    echo "Codex の認証に失敗しました(codex login)。恒久フォールバックへ。" >&2
    exit "$EX_UNAVAIL"
  fi
fi

if [ "$CODEX_EXIT" -ne 0 ]; then
  write_record "failed" "$SUMMARY" "$ERR3" ""
  emit "failed" "$EX_FAIL"
  printf -- '--- error ---\n%s\n' "$ERR3" >&2
  exit "$EX_FAIL"
fi

write_record "completed" "$SUMMARY" "" ""
emit "completed" 0
printf -- '--- summary ---\n%s\n' "$SUMMARY"
exit 0
