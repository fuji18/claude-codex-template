#!/bin/bash
# Codex への委託経路(唯一の入口)。
#
#   .claude/scripts/delegate-codex.sh <mode> <target>
#
# 実装済みの 3 モード:
#   explore <調査指示 | ファイルパス>  … 広域コード探索。サマリーのみ返す(read-only)
#   review  <base-ref>                … 敵対的レビュー。指摘リストを返す(read-only)
#   impl    <.steering/[dir]>         … 実装フェーズの委託(workspace-write)
# fix-ci と --background は未実装(fix-ci は段階外、--background は段階4)。
#
# 終了コード契約(司令塔はこの値だけを見て分岐する。推測しない):
#   0 完了                             → 検収へ
#   1 判断待ち                         → design.md に追記して再委託
#   2 失敗(タスク起因・使い方の誤り)  → 原因分析
#   3 Codex 利用不可(CLI 不在・未認証・依存未インストール)→ 恒久フォールバック
#   4 Codex 側のレート上限             → 一時フォールバック(待つ or Sonnet fork)
#   5 計画が未完成(impl の design.md が draft のまま)
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
EX_BLOCKED=1    # 判断待ち
EX_NOTREADY=5   # design.md が ready でない

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
  impl <.steering/[dir]>             実装フェーズの委託(workspace-write)

環境変数:
  CODEX_HARNESS_MODE          ハーネスモードの上書き(既定は .harness/mode)
  CODEX_DELEGATE_ACK_SECRETS  機密ファイル検出時の承認(=1 で続行)
USAGE
}

case "$MODE" in
  explore | review | impl) ;;
  fix-ci)
    echo "delegate-codex: 'fix-ci' は本テンプレートでは未実装です" >&2
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
      echo "delegate-codex: --background は段階4で実装します(未検収委託が SessionStart に出るようになるまで非同期にしない)" >&2
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

# ---------- JSON / run record ヘルパー(入口検査5 より前に置く) ----------
#
# RUN_DIR は再入判定(5-5)が run record を読むために、この位置で確定させる。
# mkdir -p は従来どおり run record 節で行う(ここではまだ作らない)。

RUN_DIR=".harness/codex-runs"

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

# $1=json ファイル $2=キー名。無い/null は空文字列を返す。
# codex-run.sh にも同じ実装をコピーする(2 箇所・十数行のため共有ファイルは作らない)。
#
# sed フォールバックの既知の癖(検収で実測): クォートされていない値
# (pid / accepted など)では `[^"]*` が末尾のカンマまで飲み込む。
# "pid": 82711, → 82711, が返り、kill -0 "82711," が引数エラーで必ず失敗する。
# = 再入防止(5-5)が jq 不在環境で静かにフェイルオープンしていた。
# 捕獲後に末尾のカンマと空白を必ず剥がす。クォートされた値は `[^"]*` が
# 閉じ引用符で止まるためもともと影響を受けない。
rec_field() {
  local _out=""
  if command -v jq >/dev/null 2>&1; then
    # `// empty` は使わない。jq の // は false も falsy として捨てるため、
    # "accepted": false が「キーが無い」と区別できなくなり、sed 経路と
    # 結果が食い違う(実測)。null のときだけ空を返す形にする。
    _out="$(jq -r --arg k "$2" '.[$k] | if . == null then empty else . end' "$1" 2>/dev/null)"
  else
    _out="$(sed -n "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\},\{0,1\}[[:space:]]*$/\1/p" "$1" | head -1)"
    _out="${_out%"${_out##*[![:space:]]}"}"
    _out="${_out%,}"
    _out="${_out%"${_out##*[![:space:]]}"}"
  fi
  [ "$_out" = "null" ] && _out=""
  printf '%s' "$_out"
}

STEERING=""

# ---------- 入口検査5: impl 専用 ----------
#
# STEERING はグローバル変数として常に定義する(impl 以外では空文字列)。
# run record の steering フィールドがこれを使う。

if [ "$MODE" = "impl" ]; then
  # ---- 5-1: target がステアリングディレクトリであること ----
  STEERING="${TARGET#./}"
  STEERING="${STEERING%/}/"
  DESIGN="${STEERING}design.md"
  TASKLIST="${STEERING}tasklist.md"

  if [ ! -d "$STEERING" ] || [ ! -f "$DESIGN" ] || [ ! -f "$TASKLIST" ]; then
    echo "delegate-codex: impl の target は design.md と tasklist.md を持つステアリングディレクトリである必要があります: $STEERING" >&2
    exit "$EX_FAIL"
  fi

  # ---- 5-2: design.md の完成マーカー(§2.5)----
  # draft = 拒否(exit 5)/ ready = 通す / 印なし = 通す(マーカー導入以前のものを止めない)
  # 空振り条件: 印が無い design.md は書きかけでも通る。implement-ticket スキルと
  # AGENTS.md §4 が同じ規則なので、経路によらず結果が一致することを優先している。
  if grep -q '<!-- status: draft -->' "$DESIGN"; then
    cat >&2 <<MSG
delegate-codex: $DESIGN が <!-- status: draft --> です(計画が未完成)。

書きかけの設計で Codex の枠を溶かさないため委託しません。司令塔が design.md を
書き切り、印を <!-- status: ready --> に変えてから再委託してください。
MSG
    exit "$EX_NOTREADY"
  fi
  if ! grep -q '<!-- status: ready -->' "$DESIGN"; then
    echo "delegate-codex: 警告 — $DESIGN に完成マーカーがありません。検査対象外として通します。" >&2
  fi

  # ---- 5-3: git hook が有効か ----
  # .husky/ があるのに core.hooksPath が未設定 = husky が丸ごと無効。
  # 保護ブランチへのコミットを止めるベンダー非依存の層が存在しない状態で
  # workspace-write の委託をしない。
  # 空振り条件: .husky/ を持たないプロジェクト(Python/Go 等)ではこの検査は
  # 何も見ない。そこでは git hook 層そのものが存在しないので、判定できない。
  #
  # 「非空」だけでは足りない — 別ツールが core.hooksPath を実在しないパスに
  # 設定していると husky は無効なのにこの検査は素通りする。指すディレクトリの
  # 実在まで見る。値そのものを ".husky" と比較してはいけない: husky v9 が
  # 設定するのは ".husky/_" であり、決め打ちすると全委託が止まる(実測)。
  HOOKS_PATH="$(git config --get core.hooksPath 2>/dev/null || true)"
  if [ -d .husky ] && { [ -z "$HOOKS_PATH" ] || [ ! -d "$HOOKS_PATH" ]; }; then
    cat >&2 <<'MSG'
delegate-codex: git hook が無効です(core.hooksPath が未設定か実在しない / Codex 利用不可)。

husky が有効化されていないため、保護ブランチへのコミットを止めるベンダー非依存の
層が存在しません。sandbox はネットワーク無効なので Codex 自身では復旧できません。

  npm ci        (または npx husky)

を実行してから再委託してください。当面は Sonnet fork にフォールバック。
MSG
    exit "$EX_UNAVAIL"
  fi

  # ---- 5-4: 保護ブランチ上で実装委託しない ----
  # 判定の実体は共有スクリプトに委ねる(hook・CI と同じ結果になることが要件)。
  # 空振り条件: check-protected-branch.sh は jq / ポリシーファイルが無いとき
  # フェイルオープン(exit 0)する。そこでは保護ブランチでも通る。
  if [ -f .claude/scripts/check-protected-branch.sh ] &&
    ! bash .claude/scripts/check-protected-branch.sh 2>/dev/null; then
    echo "delegate-codex: 保護ブランチ上では実装を委託しません。作業ブランチを切ってください。" >&2
    exit "$EX_FAIL"
  fi

  # ---- 5-5: 再入防止(同じ steering への二重起動)----
  if [ -d "$RUN_DIR" ]; then
    for _f in "$RUN_DIR"/*.json; do
      [ -f "$_f" ] || continue
      [ "$(rec_field "$_f" steering)" = "$STEERING" ] || continue
      _st="$(rec_field "$_f" status)"
      [ "$_st" = "running" ] || continue
      _pid="$(rec_field "$_f" pid)"
      _rid="$(rec_field "$_f" id)"
      # pid は数字でなければ「取れなかった」として扱う。kill -0 に非数字を渡すと
      # 引数エラーで必ず失敗し、実行中の委託を「プロセス不在」と誤認して素通しする。
      # rec_field 側でも直したが、この層でも明示的に落とす(検査が空振りする条件を減らす)。
      case "$_pid" in
        '' | *[!0-9]*) _pid="" ;;
      esac
      if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
        echo "delegate-codex: 同じステアリングへの委託が実行中です(id=$_rid pid=$_pid)。二重起動しません。" >&2
        exit "$EX_FAIL"
      fi
      # プロセスが居ない running = 強制終了の疑い。止めはしないが必ず知らせる。
      echo "delegate-codex: 警告 — 過去の委託 $_rid が status=running のまま残っています(プロセス不在 = 強制終了の可能性)。" >&2
      echo "  回復手順は codex-delegation-plan.md §12.6。tasklist.md と git diff --stat を突き合わせてから続けてください。" >&2
    done
  fi
fi

# ---------- ハーネスモード ----------
#
# 読む順序は固定する: プロンプト経由の上書き > .harness/mode > normal。
# 判定の実体は harness-mode.sh に集約する(SessionStart hook と同じ結果になることが要件)。
# AGENTS.md 側にも同じ順序を書いてある(モード C はこの経路を通らないため)。
# スクリプトが消えていても委託自体は止めない(normal に倒す)。

HMODE=""
if [ -f .claude/scripts/harness-mode.sh ]; then
  HMODE="$(CODEX_HARNESS_MODE="${CODEX_HARNESS_MODE:-}" bash .claude/scripts/harness-mode.sh 2>/dev/null || true)"
fi
[ -n "$HMODE" ] || HMODE="normal"

# ---------- run record ----------
#
# §3.2: これが状態の正。会話に依存しないので、委託を挟んで /clear できる。

# pid を足すのは衝突回避。秒までしか持たない ID だと、別ステアリングへの
# 委託を同じ秒に始めたとき log と record が無条件に上書きされる。再入防止は
# 同一ステアリングしか見ないのでこの経路は塞げない。
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$RUN_DIR" || exit "$EX_FAIL"
LOG="$RUN_DIR/$RUN_ID.log"
REC="$RUN_DIR/$RUN_ID.json"
LAST="$RUN_DIR/$RUN_ID.last.txt"
BRANCH="$(git branch --show-current 2>/dev/null || true)"

STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ENDED_AT=""
CODEX_SESSION_ID=""

# $1=status $2=summary $3=error $4=resetAt
write_record() {
  cat >"$REC" <<JSON
{
  "id": $(json_str "$RUN_ID"),
  "mode": $(json_str "$MODE"),
  "target": $(json_str "$TARGET"),
  "steering": $(json_or_null "$STEERING"),
  "branch": $(json_str "$BRANCH"),
  "harnessMode": $(json_str "$HMODE"),
  "codexSessionId": $(json_or_null "$CODEX_SESSION_ID"),
  "pid": $$,
  "status": $(json_str "$1"),
  "startedAt": $(json_str "$STARTED_AT"),
  "endedAt": $(json_or_null "$ENDED_AT"),
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

if [ "$MODE" = "impl" ]; then
  PREAMBLE="あなたは実装フェーズ(--sandbox workspace-write)で起動されています。

まず $AGENTS を読み、そこに書かれた規約に従ってください。
現在のハーネスモード: $HMODE"
else
  PREAMBLE="あなたは読み取り専用(--sandbox read-only)で起動されています。ファイルの変更・コミットは行わないでください。

まず $AGENTS を読み、そこに書かれた規約に従ってください。
現在のハーネスモード: $HMODE"
fi

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
  impl)
    PROMPT="$PREAMBLE

対象のステアリングディレクトリ: $STEERING

${STEERING}design.md と ${STEERING}tasklist.md を読み、tasklist の未完了タスクを
先頭から 1 つずつ実装してください。内容はこの指示に貼っていません。自分で読んでください。

守ること:
- **1 タスク完了ごとに tasklist.md を - [x] へ更新する**(まとめ更新は禁止)。途中で
  停止しても別の実装者が続きから引き継げることが要件です
- design.md に書かれていない設計判断が必要になったら、推測せず停止して「判断待ち」で報告する
- 変更したファイルだけを対象に lint・型チェック・関連テストを回す(全体フォーマットは禁止)
- ネットワークは無効。新規依存の追加が必要になったら実装せず「判断待ち」で報告する
- コミットの可否は AGENTS.md のモード表に従う

**最後に、次のどれか 1 行を単独の行として出力してください。司令塔はこの行だけで分岐します:**
完了: tasklist N/M / 変更 K ファイル / lint・型・関連テスト pass
判断待ち: [何が決まっていないか] / [考えられる選択肢]
失敗: [何が起きたか] / [試したこと]"
    ;;
esac

# ---------- 実行 ----------
#
# sandbox は設定ファイルではなくフラグで渡す。CLI フラグは project config に
# 優先し、untrusted なプロジェクトでは .codex/ が丸ごと読まれないため、
# .codex/config.toml が効いている保証が無い(§7.2 / §9)。

SANDBOX="read-only"
[ "$MODE" = "impl" ] && SANDBOX="workspace-write"

# ---- 事前スナップショット(exit 0 の裏取りに使う。impl 以外では取らない) ----

tree_snapshot() { git status --porcelain 2>/dev/null | LC_ALL=C sort; }
count_done() {
  local _n
  _n="$(grep -cE '^[[:space:]]*- \[[xX]\]' "$TASKLIST" 2>/dev/null)"
  printf '%s' "${_n:-0}"
}

if [ "$MODE" = "impl" ]; then
  TREE_BEFORE="$(tree_snapshot)"
  HEAD_BEFORE="$(git rev-parse HEAD 2>/dev/null || echo none)"
  DONE_BEFORE="$(count_done)"
fi

write_record "running" "" "" ""

codex exec \
  --cd "$ROOT" \
  --sandbox "$SANDBOX" \
  --json \
  --color never \
  --output-last-message "$LAST" \
  "$PROMPT" >"$LOG" 2>&1
CODEX_EXIT=$?

CODEX_SESSION_ID="$(grep -Eo '"(thread_id|session_id|conversation_id)"[[:space:]]*:[[:space:]]*"[^"]+"' "$LOG" 2>/dev/null |
  head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
ENDED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

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

if [ "$MODE" = "impl" ]; then
  # 報告フォーマット(AGENTS.md §7)の判定行。複数あれば最後のものを採る。
  # 全角コロンと箇条書きの接頭辞も拾う。日本語で書かせている以上、Codex が
  # 「判断待ち:」を全角や「- 判断待ち:」で返すことは十分ありうる。ここで
  # 取りこぼすと、正しく停止した判断待ち(差分が無いのが正常)が下の
  # 成果実在確認に落ちて exit 2 に化ける。
  VERDICT="$(grep -hE '^[[:space:]]*([-*+][[:space:]]*)?(\*\*)?(完了|判断待ち|失敗)(\*\*)?[:：]' "$LAST" 2>/dev/null | tail -1)"

  case "$VERDICT" in
    *判断待ち*)
      write_record "blocked" "$SUMMARY" "" ""
      emit "blocked" "$EX_BLOCKED"
      printf -- '--- 判断待ち ---\n%s\n' "$SUMMARY"
      exit "$EX_BLOCKED"
      ;;
    *失敗*)
      write_record "failed" "$SUMMARY" "" ""
      emit "failed" "$EX_FAIL"
      printf -- '--- 失敗 ---\n%s\n' "$SUMMARY"
      exit "$EX_FAIL"
      ;;
  esac

  # ---- 成果の実在確認 ----
  # codex exec の exit 0 は「ターンが完了した」であってタスクの成否ではない
  # (段階0 の実測)。何も動いていない委託を検収に回さない。
  # 空振り条件: Codex が判定行を書かずに何かを 1 バイトでも変更した場合、
  # ここは通る。そのときの防衛線は司令塔の検収(code-reviewer + test-runner)。
  TREE_AFTER="$(tree_snapshot)"
  HEAD_AFTER="$(git rev-parse HEAD 2>/dev/null || echo none)"
  DONE_AFTER="$(count_done)"

  if [ "$TREE_AFTER" = "$TREE_BEFORE" ] &&
    [ "$HEAD_AFTER" = "$HEAD_BEFORE" ] &&
    [ "$DONE_AFTER" -le "$DONE_BEFORE" ]; then
    write_record "failed" "$SUMMARY" "exit 0 だが成果物が確認できない(作業ツリー・HEAD・tasklist のいずれも変化なし)" ""
    emit "failed" "$EX_FAIL"
    cat >&2 <<'MSG'
delegate-codex: Codex は正常終了しましたが、成果物が確認できません。
作業ツリー・HEAD・tasklist の進捗がいずれも変化していないため、失敗として扱います。
生ログで原因(sandbox の起動失敗など)を確認してください。
MSG
    exit "$EX_FAIL"
  fi

  if [ "$DONE_AFTER" -le "$DONE_BEFORE" ]; then
    SUMMARY="$SUMMARY

⚠️ tasklist.md の [x] が増えていません(変更はあります)。逐次更新がされていない
可能性があるため、進捗の判断は tasklist ではなく git diff --stat を根拠にしてください。"
  fi
fi

write_record "completed" "$SUMMARY" "" ""
emit "completed" 0
printf -- '--- summary ---\n%s\n' "$SUMMARY"
exit 0
