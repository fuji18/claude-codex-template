# 設計書: 段階2 — 最小ハーネス(読み取り委託)

<!-- status: ready -->

正: `docs/template-dev/codex-delegation-plan.md` §3 / §7 / §8.2。ここには**実装に落ちる形の決定だけ**を書く。

## アーキテクチャ概要

```
司令塔(Claude Opus)
  │
  │  .claude/scripts/delegate-codex.sh <mode> <target>
  ▼
┌─────────────────────────────────────────────┐
│ 入口検査(委託前に止める層)                │
│  1. 機密ファイルの検出        → exit 2      │
│  2. AGENTS.md の存在          → exit 3      │
│  3. 検証プローブの導通        → exit 3      │
│  4. codex CLI 不在 / 未認証   → exit 3      │
└─────────────────────────────────────────────┘
  │  run record: status=running
  ▼
codex exec --sandbox read-only --json -o <last>
  │
  ▼
┌─────────────────────────────────────────────┐
│ 出口判定(JSONL イベントを見る)            │
│  rate/usage limit 識別子 → exit 4           │
│  auth 系識別子           → exit 3           │
│  それ以外の非ゼロ        → exit 2           │
│  ゼロ                    → exit 0           │
└─────────────────────────────────────────────┘
  │  run record: status=completed|failed|rate-limited
  ▼
標準出力にサマリーのみ / 生ログは .harness/codex-runs/[id].log
```

## 決定事項

### D1. sandbox は設定ファイルではなく CLI フラグで渡す

**根拠**: Codex の設定解決順は「CLI フラグ・`-c` > project config(`.codex/config.toml`)> profile > user config > system > 既定」であり、さらに**project を untrusted にすると `.codex/` レイヤが丸ごと読まれない**。つまり `.codex/config.toml` に `sandbox_mode` を書いても、それが効いている保証が無い。

- `delegate-codex.sh` は `--sandbox read-only` を**必ずフラグで**渡す
- `.codex/config.toml` は「人間が `codex` を直接叩くとき(モード C)の既定」に位置づけを下げる。**防衛線として当てにしない**
- 計画文書 §9 の「`.codex/config.toml` が唯一の防衛線」は誤りなので、今回あわせて訂正する

### D2. exit 4 は JSONL のエラー識別子で判定する。ただし**当てる範囲**を絞る

`codex exec --json` は改行区切りの JSON イベントを吐く。上限系は `rate_limit_reached` / `usage_limit_reached` / `credits_depleted`(および `workspace_owner_*` / `workspace_member_*` の変種)という**識別子**で流れる。文言そのものより変化しにくいので、これを一次判定にする。

```
一次: rate_limit_reached|usage_limit_reached|credits_depleted
二次: rate limit|usage limit|quota|429       ← 一次が改名されたときの保険
```

**二次を残す理由**: 一次の識別子が改名されると、上限を「タスク起因の失敗(exit 2)」として誤分類し、司令塔が原因分析に入って**さらに枠を溶かす**。

#### D2-1. 当初の設計は誤りだった(レビュー指摘 P0。修正済み)

当初は上のパターンを**ログ全体に、終了コードと無関係に**当てていた。これは壊れている。

**`--json` のログは Codex が読んだファイルの引用を含む。** したがってレビュー対象のファイルに "quota" や "rate limit" と書かれているだけで上限と誤判定する。**このスクリプト自身とハーネスの計画文書がまさにそれに当たり、自分をレビュー対象にすると成功した委託が exit 4 に化けた**(レビュアーが実測で再現)。

判定の範囲を 3 段階に分ける:

| 状況 | 上限・認証の判定 |
| --- | --- |
| `codex exec` が **exit 0** | **一切しない**。完走してサマリーが出ている以上、上限では終わっていない |
| exit 非ゼロ・**一次識別子** | ログ全体に当てる(識別子は具体的なので引用による誤爆が起きにくい) |
| exit 非ゼロ・**二次の文言** | 末尾 20 行のうち **`error` / `fail` を含む行だけ**に当てる |

**末尾に絞るだけでは足りない点が要点。** 失敗した委託の末尾にも Codex が読んだファイルの引用は来る(検証で確認)。エラーらしい行に限定して初めて誤爆が止まる。

**「誤検知より見逃しの方が高くつく」という当初の判断は、見逃しが静かに起きることを前提にしていた。** exit 0 のときサマリーは標準出力に出て司令塔の目に入るので、その前提が成り立たない。非対称の向きは状況によって変わる。

### D3. 認証欠落は exit 3(恒久)、上限は exit 4(一時)

判定順は **上限 → 認証 → その他**。認証パターン(`401` / `unauthorized`)は上限応答にも混ざりうるため、上限を先に見る。

事前検査には `codex login status` を使う(**ログイン済みなら exit 0** を返す、と公式が自動化向けに明記している)。事前に落とせば枠を一切消費しない。

### D4. 検証コマンドの導通確認は AGENTS.md の機械可読マーカーで行う

`delegate-codex.sh` は `.claude/scripts/` = **テンプレート所有**で全プロジェクトに配られるため、`node_modules` を決め打ちで見てはいけない(§3.2)。そこで**検査の機構はスクリプト、検査の中身は AGENTS.md** に分ける。

AGENTS.md に 1 行だけ機械可読マーカーを置く:

```markdown
<!-- verify-probe: npx --no-install eslint --version -->
```

- スクリプトは最初の 1 件を取り出し、`bash -c` で実行して**終了コードだけ**見る
- 失敗 = 依存が入っていない → **委託せず exit 3**(ネットワーク無効の sandbox では Codex が何も完遂できず、枠だけ溶ける)
- **マーカーが無い場合は警告して続行**(フェイルオープン)。AGENTS.md は `merge` 区分でプロジェクトが書き換えるため、マーカー未反映のプロジェクトを止めない
- **AGENTS.md 自体が無い場合は exit 3**(規約の写像が存在しない状態で委託しない)。マーカー欠落との強さの差は意図的

### D5. 機密チェックは env 変数で承認する(対話しない)

§13 #7 の検証で **Codex にパス単位の読み取り除外は存在しない**ことが確定した。sandbox は書き込みの制限であって、読み取りは止まらない。したがって「ワークツリーに `.env` があれば委託先へ送られうる」は緩和不能で、**入口で人間に確認させるのが唯一の層**。

- 検出対象: `.env` / `.env.*` / `*.pem` / `id_rsa*` / `credentials*`(深さ 3 まで。`node_modules` / `.git` / `.harness` は除外)
- **`*.example` / `*.sample` / `*.template` は除外**(`.env.example` は正常な配布物。毎回警告が出ると警告そのものが無視されるようになる)
- 検出したら一覧を stderr に出し、**`CODEX_DELEGATE_ACK_SECRETS=1` が無ければ exit 2**
- 対話プロンプトにしない理由: このスクリプトは司令塔から非対話で呼ばれる。`read` で止めると**ハングする**

### D6. `--background` と `impl` / `fix-ci` は明示的に拒否する

段階2 の範囲外。黙って無視すると「指定したのに効いていない」に気づけないので、**exit 2 + 「段階3 で実装します」**と返す。

### D7. run record は jq が無くても書く

run record は §3.2 で「**これが状態の正**」と定義されており、書けないと委託を挟んだ `/clear` が成立しない。jq があれば `jq -Rs .` でエスケープし、無ければ bash の `sed` 版にフォールバックする。

段階2 では `steering` は常に `null`(`explore` / `review` は steering を取らない)。**再入判定(同じ steering の二重起動防止)も段階3 で入れる** — 段階2 には鍵になる識別子が無い。

### D8. モードの読み取り順は §3.2 に従って固定する

`CODEX_HARNESS_MODE`(プロンプト経由の上書き)> `.harness/mode` > `normal`。

段階2 では読み取ってプロンプトに載せるだけで、モードによる分岐は持たない(コミットしないので分岐する対象が無い)。**それでも今から入れる**のは、AGENTS.md 側の起動時手順(§7.1)と対になる経路を最初から揃えておくため。

### D9. サマリーは `--output-last-message` で受ける

`codex exec -o <path>` は**アシスタントの最終メッセージだけ**をファイルに書く。「標準出力にはサマリーのみ」(§3.2)はこの仕組みにそのまま乗る。生の JSONL は `.log` に落とし、司令塔には渡さない。

標準出力は 2,000 バイトで打ち切る(司令塔のコンテキストを守る上限)。

## コンポーネント設計

### 1. `.claude/scripts/delegate-codex.sh`(新規)

> **以下は計画時点の初稿です。実体は `.claude/scripts/delegate-codex.sh` を見てください。**
> 実装・検証・レビューを経て次の差分があります(いずれも下の「実装からの逸脱」とレビュー対応に記録済み):
> 入口検査0(依存コマンドの存在確認)の追加 / 出口判定の範囲限定(D2-1)/ `json_str` の空返し防止 / 余剰オプション処理の書き換え。

```bash
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
#   0 完了                          → 検収へ
#   1 判断待ち                      → design.md に追記して再委託
#   2 失敗(タスク起因・使い方の誤り)→ 原因分析
#   3 Codex 利用不可(CLI 不在・未認証・依存未インストール)→ 恒久フォールバック(Sonnet fork)
#   4 Codex 側のレート上限          → 一時フォールバック(待つ or Sonnet fork)
#   5 計画が未完成(段階3 の impl でのみ使う)
#
# 3 と 4 を混ぜないこと。前者は環境の欠落(恒久)、後者は枠切れ(一時)で回復手段が違う。
#
# 出力はサマリーのみ。生ログは .harness/codex-runs/[id].log に落とす。
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

MODE="${1:-}"; [ $# -ge 1 ] && shift
TARGET="${1:-}"; [ $# -ge 1 ] && shift

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

for arg in "$@"; do
  case "$arg" in
    --background)
      echo "delegate-codex: --background は段階3(impl)で実装します" >&2
      ;;
    *)
      echo "delegate-codex: 未知のオプション: $arg" >&2
      ;;
  esac
  exit "$EX_FAIL"
done

# ---------- 入口検査1: 機密ファイル ----------
#
# Codex の sandbox は「書き込み」の制限であり、読み取りの deny-list は存在しない
# (段階2 で公式ドキュメントを確認済み)。.gitignore されていてもディスク上に
# あれば読めるため、委託は機密を OpenAI 側へ送りうる。入口の人間確認が唯一の層。

SENSITIVE="$(
  find . -maxdepth 3 \
    \( -name node_modules -o -name .git -o -name .harness \) -prune -o \
    \( -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name 'id_rsa*' -o -name 'credentials*' \) \
    -type f -print 2>/dev/null |
    grep -Ev '\.(example|sample|template)$' |
    head -20
)"

if [ -n "$SENSITIVE" ]; then
  cat >&2 <<'MSG'
delegate-codex: ワークツリーに機密の可能性があるファイルがあります。

Codex の sandbox には読み取りの除外機能が無いため、これらは委託先へ送られうる。
内容を確認し、問題なければ承認して再実行してください:

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

Codex は CLAUDE.md も hooks も permissions も読みません。AGENTS.md が規約の
唯一の写像なので、これが無い状態では委託しません。
MSG
  exit "$EX_UNAVAIL"
fi

# 検査の機構はスクリプト、検査の中身は AGENTS.md 側に置く。
# delegate-codex.sh はテンプレート所有で全プロジェクトに配られるため、
# node_modules のようなスタック固有のものを決め打ちで見てはいけない。
PROBE="$(sed -n 's/^[[:space:]]*<!--[[:space:]]*verify-probe:[[:space:]]*\(.*\)[[:space:]]*-->[[:space:]]*$/\1/p' "$AGENTS" | head -1)"

if [ -z "$PROBE" ]; then
  echo "delegate-codex: 警告 — AGENTS.md に <!-- verify-probe: ... --> がありません。依存の導通確認をスキップします。" >&2
elif ! bash -c "$PROBE" >/dev/null 2>&1; then
  cat >&2 <<MSG
delegate-codex: 検証プローブが失敗しました: $PROBE

依存が未インストールの可能性があります。Codex の sandbox はネットワーク無効の
ため、この状態で委託すると何も完遂できないまま枠だけを消費します。
先に依存をインストールしてから再実行してください。
MSG
  exit "$EX_UNAVAIL"
fi

# ---------- 入口検査4: Codex CLI ----------

if ! command -v codex >/dev/null 2>&1; then
  cat >&2 <<'MSG'
delegate-codex: codex コマンドが見つかりません(Codex 利用不可)。

司令塔は恒久フォールバック(Sonnet fork)に切り替えてください。
導入する場合は docs/template-dev/codex-delegation-plan.md §11 の段階0 を参照。
MSG
  exit "$EX_UNAVAIL"
fi

if ! codex login status >/dev/null 2>&1; then
  cat >&2 <<'MSG'
delegate-codex: Codex が未認証です(Codex 利用不可)。

  codex login

を実行してから再委託してください。司令塔は当面 Sonnet fork にフォールバック。
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

RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR=".harness/codex-runs"
mkdir -p "$RUN_DIR" || exit "$EX_FAIL"
LOG="$RUN_DIR/$RUN_ID.log"
REC="$RUN_DIR/$RUN_ID.json"
LAST="$RUN_DIR/$RUN_ID.last.txt"
BRANCH="$(git branch --show-current 2>/dev/null || true)"

json_str() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "${1:-}" | jq -Rs .
  else
    printf '"%s"' "$(printf '%s' "${1:-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\t' '  ')"
  fi
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

RATE_RE='rate_limit_reached|usage_limit_reached|credits_depleted|rate limit|usage limit|quota|429'
AUTH_RE='unauthorized|not logged in|invalid_api_key|authentication_error|401'

ERR3="$(grep -Eiv '^\s*$' "$LOG" 2>/dev/null | tail -3 | tr '\n' ' ')"
SUMMARY=""
[ -f "$LAST" ] && SUMMARY="$(head -c 2000 "$LAST")"

if grep -Eqi "$RATE_RE" "$LOG" 2>/dev/null; then
  RESET_AT="$(grep -Eo '"reset[_a-zA-Z]*"[[:space:]]*:[[:space:]]*"[^"]*"' "$LOG" 2>/dev/null | head -1 | sed 's/.*: *"\(.*\)"/\1/')"
  write_record "rate-limited" "" "$ERR3" "$RESET_AT"
  emit "rate-limited" "$EX_RATELIMIT"
  echo "Codex 側のレート上限です。待つか Sonnet fork にフォールバックしてください。" >&2
  [ -n "$RESET_AT" ] && echo "reset: $RESET_AT" >&2
  exit "$EX_RATELIMIT"
fi

if [ "$CODEX_EXIT" -ne 0 ] && grep -Eqi "$AUTH_RE" "$LOG" 2>/dev/null; then
  write_record "failed" "" "$ERR3" ""
  emit "unavailable" "$EX_UNAVAIL"
  echo "Codex の認証に失敗しました(codex login)。恒久フォールバックへ。" >&2
  exit "$EX_UNAVAIL"
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
```

**実行権限**: `chmod +x` を付ける(CI の `harness-integrity` が `.claude/scripts/*.sh` の実行権限を検査する)。

### 2. `AGENTS.md`(新規 / マニフェスト `merge`)

Codex 側への**規約の唯一の写像**。§7.1 の指示どおり、含めるもの/含めないものを厳密に分ける。

**構成**(見出しのみ。本文は実装時に §7.1 の表をそのまま落とす):

1. このファイルの位置づけ(正は `docs/development-guidelines.md`。ここはその派生)
2. **起動時の手順**(モード判定 → ブランチ確認 → hooksPath 確認 → 検証プローブ)
3. 検証コマンド(`<!-- verify-probe: ... -->` マーカーを含む)
4. モード別の禁止事項(§7.1 の表)
5. スコープガード
6. コミットメッセージ規約(`Codex-authored: true` トレーラー)
7. `.steering/` の扱い

**テンプレート既定の検証コマンド**(Node.js / TypeScript):

| 用途 | コマンド |
| --- | --- |
| lint | `npm run lint` |
| 型チェック | `npm run typecheck` |
| テスト | `npm test` |
| フォーマット | `npm run format:check` |
| **導通プローブ** | `npx --no-install eslint --version` |

プローブに `--no-install` を付けるのが要点。**ネットワーク無効の sandbox では取得を試みた時点で失敗する**ため、「入っているかどうか」だけを見る形にする。

**モード C の開始条件 3 点**(§2.3)と、**起動時に `.harness/mode` を読む手順**(§2.2)は段階2 時点で書き切る。段階5 で書き足す形にすると、段階2〜4 の間だけ「モードを読まない AGENTS.md」が配られることになるため。

### 3. `.codex/config.toml`(新規 / マニフェスト `merge`)

```toml
# Codex CLI のプロジェクト設定。
#
# 位置づけ(重要): このファイルは防衛線ではない。
#   - CLI フラグと -c が project config に優先する
#   - プロジェクトを untrusted にすると .codex/ レイヤは丸ごと読まれない
# したがって delegate-codex.sh は sandbox を必ず --sandbox フラグで明示的に渡す。
# ここに書くのは「人間が codex を直接叩くとき(モード C)の既定」。

# 書き込みはワークツリー内に限る。
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
# ネットワーク無効が既定。帰結として、新規依存の追加を伴うタスクは委託対象外。
# 必要な依存は委託前に人間 / 司令塔がインストールしておく。
network_access = false

# model / model_reasoning_effort は既定のまま。変更する場合はここで上書きする。
# model = "..."
# model_reasoning_effort = "..."
```

### 4. `.claude/template-manifest.json`(改訂)

| パス | 追加先 | 理由 |
| --- | --- | --- |
| `AGENTS.md` | `merge` | 雛形はテンプレート、検証コマンドはスタック依存 |
| `.codex/config.toml` | `merge` | sandbox 既定はテンプレート方針、model はプロジェクト裁量 |
| `.codex/prompts/` | `owned` | ワークフローの写像(段階5 で中身を入れる) |
| `.harness/` | `never` | ハーネスのローカル状態 |

### 5. `.gitignore`(改訂)

`.harness/` を丸ごと無視してはいけない(`.harness/decisions.jsonl` は永続ログ)。追加は 2 行だけ:

```gitignore
# Codex 併用ハーネスのローカル状態(.harness/decisions.jsonl は追跡する)
.harness/mode
.harness/codex-runs/
```

### 6. `.prettierignore`(改訂)

Prettier は `.gitignore` を参照しないため、gitignore 済みでも `npm run format:check` が run record の JSON を検査対象にして**ローカルだけが落ちる**。あわせて `AGENTS.md` も除外する(`CLAUDE.md` と同じ扱い。表の整形差分がノイズになる)。

```
.harness/
AGENTS.md
```

### 7. `/sync-docs` への追加(§7.1)

検査対象に「**CLAUDE.md ↔ AGENTS.md の乖離**」を 1 項目追加する。検証コマンドや規約を変えたら両方を更新する必要があるため。

### 8. ドキュメント反映

| ファイル | 内容 |
| --- | --- |
| `docs/template-dev/codex-delegation-plan.md` | §11 の段階2 を完了に / §13 の検証結果を反映 / §9 の「config.toml が唯一の防衛線」を訂正 / §3.2 に exit 4 の判定方法(JSONL 識別子)を反映 |
| `docs/template-dev/CHANGELOG.md` | 段階2 の追加分。`AGENTS.md` と `.codex/config.toml` は `merge` 区分であることを明記 |
| `docs/template-dev/codex-harness.html` | 段階の進捗(1/6 → 2/6)と、判明した仕様の反映 |
| `README.md` | ディレクトリ構造に `AGENTS.md` / `.codex/` / `.harness/` を追記 |

## エラーハンドリング方針

| 状況 | 挙動 | 根拠 |
| --- | --- | --- |
| git リポジトリ外 | exit 2 | 委託の前提が無い |
| 機密ファイル検出 + 未承認 | exit 2 | 人間の判断が要る。フェイルクローズ |
| AGENTS.md 不在 | exit 3 | 規約の写像が無い = 環境の欠落 |
| verify-probe マーカー不在 | 警告して続行 | `merge` 区分のファイル。未反映のプロジェクトを止めない |
| verify-probe 失敗 | exit 3 | 依存未インストール。枠を溶かす前に止める |
| codex 不在 / 未認証 | exit 3 | 恒久フォールバック |
| 上限検出 | exit 4 | 一時フォールバック |
| その他の失敗 | exit 2 | 原因分析へ |

**フェイルオープンにしない**のがこのスクリプトの方針(保護ブランチ検査とは逆)。理由: 保護ブランチ検査は「止めるとコミットが不能になる」ためフェイルオープンだが、委託は**止めても作業が継続できる**(Sonnet fork がある)。止めた場合のコストが小さく、通した場合のコスト(枠の消費・機密の送信)が大きいので、非対称は逆向き。

## 検証マトリクス

Codex CLI が無い環境で確認できるものと、できないものを分ける。

### 今回確認できるもの

| # | ケース | 期待 |
| --- | --- | --- |
| V1 | 引数なし | usage + exit 2 |
| V2 | 未知の mode | usage + exit 2 |
| V3 | `impl` / `fix-ci` | 「段階3 で実装」+ exit 2 |
| V4 | `--background` 付き | 「段階3 で実装」+ exit 2 |
| V5 | target 空 | exit 2 |
| V6 | 機密ファイルあり・未承認 | 一覧 + exit 2 |
| V7 | 機密ファイルあり・`ACK=1` | 検査を通過して次へ進む |
| V8 | `.env.example` のみ | 警告を出さない |
| V9 | AGENTS.md 不在 | exit 3 |
| V10 | verify-probe マーカー不在 | 警告 + 続行 |
| V11 | verify-probe 失敗 | exit 3 |
| V12 | codex 不在(**現環境がそのまま該当**) | exit 3 |
| V13 | git リポジトリ外 | exit 2 |
| V14 | `bash -n` | 構文エラーなし |

### スタブで確認するもの

`codex` という名前のスタブスクリプトを PATH の先頭に置き、`login status` に 0 を返させたうえで `exec` の出力を差し替える。

| # | スタブの出力 | 期待 |
| --- | --- | --- |
| V15 | `{"type":"error","code":"rate_limit_reached"}` + 非ゼロ | exit 4 / record が `rate-limited` |
| V16 | 上記に `"resets_at":"..."` を含む | `resetAt` が record に入る |
| V17 | `401 unauthorized` + 非ゼロ | exit 3 |
| V18 | 正常終了 + last-message ファイル | exit 0 / record が `completed` / サマリーが標準出力に出る |
| V19 | 非ゼロだが上限でも認証でもない | exit 2 / record が `failed` |
| V20 | jq を PATH から外して V18 | record が壊れない JSON になる |

### 今回確認できないもの(段階3 へ持ち越し)

- Codex が実際に指示どおりのサマリーを返すか(委託の**品質**)
- devcontainer で Codex CLI が動くか(§13 #5)
- `resetAt` が実際に取得できるか(§13 #6)

## 実装の順序

1. `AGENTS.md`(`delegate-codex.sh` が参照するため先に作る)
2. `.codex/config.toml`
3. `.claude/scripts/delegate-codex.sh` + `chmod +x`
4. 検証(V1〜V14)
5. スタブ検証(V15〜V20)
6. マニフェスト / `.gitignore` / `.prettierignore` / `/sync-docs`
7. ドキュメント反映
8. 品質チェック
