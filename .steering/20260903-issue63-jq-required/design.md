# 設計: 委託経路で jq を必須化し、sed フォールバック経路を削除する(#63)

<!-- status: ready -->

## 0. 全体像

**「jq が無い」を分岐で吸収するのをやめ、入口で終端させる。** 分岐で吸収すると、失敗が
「エラー」ではなく「空文字列」として現れ、フェイルクローズと宣言した検査が静かに素通しする
(#29 の Critical がまさにこれ)。

境界は **層** で引く。同じ `lib-record.sh` を読んでいても、**止めてよい層**と**止めてはいけない層**が
混在しているので、呼び出し元ごとに判定する。

| 層 | 呼び出し元 | jq が無いときの挙動 | 理由 |
| --- | --- | --- | --- |
| **止める(フェイルクローズ)** | `delegate-codex.sh` の委託モード(`explore` / `review` / `impl`) | **`exit 3`**(Codex 利用不可) | 委託が止まっても Sonnet fork に落ちるだけ(`model-strategy.md`)。通したコスト(枠の消費・機密の送信・再入防止の空振り)の方が大きい |
| **止める(フェイルクローズ)** | `codex-run.sh` の `accept` / `set-status` / `prune` / `list` | **`exit 2`** | 検収状態を書き換える層(`accept` / `set-status`)と、record を**削除**する層(`prune`)。`list` は人間が検収判断に使う一覧で、空欄が並ぶより止めた方がよい |
| **止めない(フェイルオープン)** | `codex-run.sh pending`(SessionStart 注入) | **何も出さず `exit 0`** | ここを `exit` にするとセッションが開けなくなる。注入が減るだけに倒す |
| **止めない(jq を要求しない)** | `delegate-codex.sh --print-forbidden` | 従来どおり一覧を出して `exit 0` | jq を 1 行も使わない read-only 経路。`check-guard-integrity.sh degraded` がここから禁止領域を受け取る(#42)。jq を要求すると、jq 不在環境で**縮退モードの差分検査まで一緒に落ちる** |
| **止めない(jq を要求しない)** | `codex-run.sh show` | 従来どおり `cat` して `exit 0` | `rec_field` を使わない純粋な `cat`。record が壊れているときの調査手段なので、依存を足さない |
| **変更しない** | `session-start.sh` のブランチポリシー読み出し / `check-protected-branch.sh` / `check-implementation-phase.sh` / `check-guard-integrity.sh` | 現状維持 | スコープ外(フェイルオープンが意図的な層、または本件と無関係) |

## 1. 判断1: `rec_field` は自己強制できない ⇒ 強制は入口に置く

`rec_field` は **すべて `_x="$(rec_field ...)"` の形(コマンド置換)で呼ばれている。**
コマンド置換の中の `exit` は**サブシェルしか殺さない**ため、`rec_field` 自身が
`exit` しても呼び出し元は空文字列を受け取って先へ進む — 潰したいフェイルオープンと
同じ形になる。

したがって:

- **強制は呼び出し元(スクリプトの入口)で行う**。共有関数 `require_jq` を `lib-record.sh` に置き、
  各スクリプトが自分の終了コードを渡して呼ぶ
- `rec_field` 側は**二次層**として、jq が無ければ **stderr に 1 行出して `return 1`** する
  (黙って空を返さない)。これは保険であって強制ではない

## 2. `.claude/scripts/lib-record.sh` の変更

### 2-1. `require_jq` を追加する(`rec_field` の直前に置く)

```bash
# ---------- jq 必須の宣言(#63) ----------
#
# run record の読み書きは jq に一本化した。**sed フォールバックは持たない。**
# 過去に sed 経路が 2 回バグを出しており(#29 の Critical: 末尾カンマを飲み込んで
# 再入防止が静かにフェイルオープン / write_field の独自 JSON 検査)、
# 「jq が無い環境でも動く」利得より「検査が空振りしても失敗として現れない」損失が
# 大きいと判断した(#63)。devcontainer / CI は jq を保証している。
#
# **呼び出し元は 2 種類ある。層を取り違えないこと(#63 design §0):**
#   - 止める層 = 委託経路(delegate-codex.sh の委託モード / codex-run.sh の書き込み系)
#     … この関数を入口で呼び、jq が無ければ止める
#   - 止めない層 = SessionStart 注入(codex-run.sh pending)
#     … この関数は呼ばず、自前で `command -v jq` を見て黙って抜ける
#
# $1=呼び出し元の表示名(メッセージの接頭辞) $2=jq 不在時の終了コード
require_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  echo "${1:-lib-record}: jq が見つかりません。run record を安全に読み書きできないため中止します(jq を入れてください)。" >&2
  exit "${2:-2}"
}
```

### 2-2. `rec_field` の sed 分岐を削除する

`rec_field` の**直前のコメント**は、sed フォールバックの癖(末尾カンマ)を説明する
段落がまるごと不要になる。次の内容に置き換える:

```bash
# $1=json ファイル $2=キー名。無い/null は空文字列を返す。
#
# **jq 必須。** 呼び出し元は入口で require_jq を通していること(止めない層は
# 自前で jq の有無を見てから呼ぶこと)。ここでの検査は二次層でしかない —
# rec_field はコマンド置換で呼ばれるので、この中の exit はサブシェルしか
# 殺せず、呼び出し元を止められない(#63 design §1)。
rec_field() {
  local _out=""
  if ! command -v jq >/dev/null 2>&1; then
    echo "lib-record: jq が見つかりません(rec_field は jq 必須。呼び出し元が require_jq を通していません)" >&2
    return 1
  fi
  # `// empty` は使わない。jq の // は false も falsy として捨てるため、
  # "accepted": false が「キーが無い」と区別できなくなる。
  # null のときだけ空を返す形にする。
  _out="$(jq -r --arg k "$2" '.[$k] | if . == null then empty else . end' "$1" 2>/dev/null)"
  [ "$_out" = "null" ] && _out=""
  printf '%s' "$_out"
}
```

**注意:** 既存コメントの「sed 経路は run record が『1 行 1 キー』であることに依存する」
「sed フォールバックの既知の癖(検収で実測)…」の 2 段落は**削除する**(経路ごと消えるため)。
ファイル冒頭の「source 専用 / 命名規約 / 委託禁止領域 / 実行中の書き換えハザード」の
コメント群は**そのまま残す**(#45 / #15 の設計根拠であり本件と無関係)。

## 3. `.claude/scripts/delegate-codex.sh` の変更

### 3-1. 入口検査0-2(jq)を追加する

**置き場所は `--print-forbidden` の早期 exit ブロックの直後、`# ---------- 入口検査1: 機密ファイル ----------` の直前。**

**入口検査0(`find grep sed head tail tr sort uniq`)の配列に jq を足してはいけない。**
入口検査0 は `--print-forbidden` より前にあり、そこに足すと jq 不在環境で
`--print-forbidden` が `exit 3` になる。`check-guard-integrity.sh degraded` は
この出力から禁止領域を受け取っているため(#42)、**モード C の差分検査が
「禁止領域を返さない」に落ちる** — jq 不在という無関係な理由で縮退モードの
検知層を 1 枚失う。

追加する内容:

```bash
# ---------- 入口検査0-2: jq(委託モードのみ) ----------
#
# run record の読み書きは jq に一本化してある(#63 / lib-record.sh)。
# sed フォールバックを持たないので、jq が無い状態で先へ進むと入口検査5-5
# (impl の再入防止)が空文字列を受けて静かに素通しする。**ここで止める。**
#
# exit 3(Codex 利用不可)を返すのは、これが環境の欠落であってタスクの失敗では
# ないため。司令塔は恒久フォールバック(Sonnet fork)へ落ちる。
#
# **--print-forbidden より後に置くこと。** あちらは jq を 1 行も使わず、
# check-guard-integrity.sh degraded が禁止領域の単一ソースとして読む read-only
# 経路なので、jq 不在で巻き添えにしてはならない(#42 / #63 design §3-1)。
require_jq "delegate-codex" "$EX_UNAVAIL"
```

### 3-2. `json_str` の `command -v jq` 分岐を外す

jq は 3-1 で保証済み。ただし**空出力時のフォールバックは残す** — これは
「jq が無い」ための経路ではなく、「jq が**エラーを返した**」ための保険
(サマリーは 2000 バイトで切るため末尾がマルチバイト文字の途中になりうる)。
現行の `if command -v jq ...; then ... fi` を外し、コメントを次の趣旨に直す:

```bash
json_str() {
  # jq に任せる(入口検査0-2 で存在は保証済み)。ただし空を返させないこと —
  # record は状態の正なので、ここが空文字列を返すと `"summary": ,` のような
  # 壊れた JSON になり、「委託を挟んで /clear できる」という前提ごと崩れる。
  # 下のフォールバックは **jq 不在用ではなく jq がエラーを返したとき用**
  # (サマリーは 2000 バイトで切るため、末尾がマルチバイト文字の途中に
  #  なりうる。jq がそれを拒む場合に落ちる先)。
  local _out=""
  _out="$(printf '%s' "${1:-}" | jq -Rs . 2>/dev/null)"
  if [ -n "$_out" ]; then
    printf '%s' "$_out"
    return
  fi
  printf '"%s"' "$(printf '%s' "${1:-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\t' '  ')"
}
```

### 3-3. `lifecycle_snapshot` の `command -v jq` 分岐を外す

同じ理由。`|| git hash-object` は **jq が失敗したとき**のフォールバックとして残す。
コメント末尾の「jq を必須化しないのは入口検査0 の必須コマンド一覧に無いため
(必須化は Issue #63 の担当)」は**事実が変わるので必ず書き換える**:

```bash
# ライフサイクル節だけを抜き出して比べる(prepare は scripts の中のキーなので
# scripts を見れば覆う)。jq は入口検査0-2 で保証済み(#63)。jq が失敗した場合だけ
# ファイル全体のハッシュに落ちる(依存追加でも鳴るが、警告しか出さない層なので
# 過検出側に倒す)。
#
# 空振り条件: package.json が無いプロジェクトでは常に空文字列になり、前後が一致して
# 何も出ない(Node 以外のスタックでは正しい挙動)。
lifecycle_snapshot() {
  [ -f package.json ] || return 0
  jq -S '{scripts: .scripts, "lint-staged": ."lint-staged"}' package.json 2>/dev/null ||
    git hash-object -- package.json 2>/dev/null || true
}
```

### 3-4. 変更しないもの

- 自己コピー exec のブロック(`lib-record.sh` の同梱を含む)。**同梱するファイル構成は変わらない**
- `LIB_RECORD` の解決順・フェイルクローズ
- 入口検査0 の必須コマンド配列(`find grep sed head tail tr sort uniq`)。`sed` は
  `json_str` のフォールバックと他の整形で使い続けるので**外さない**

## 4. `.claude/scripts/codex-run.sh` の変更

### 4-1. ヘッダーの終了コード表に 1 行足す

```
#   0 成功
#   1 対象が無い・値が不正
#   2 使い方の誤り / jq 不在(pending を除く。#63)
```

あわせてヘッダーのどこか(終了コード表の下)に層の宣言を置く:

```
# jq の扱い(#63): record の読み書きは jq 必須で sed フォールバックを持たない。
#   - accept / set-status / prune / list … jq が無ければ exit 2 で止める(止める層)
#   - pending                            … jq が無ければ何も出さず exit 0(SessionStart
#                                          注入。ここを止めるとセッションが開けない)
#   - show                               … cat のみ。jq を要求しない
```

### 4-2. `write_field` から sed 経路と独自 JSON 検査を削除する

**第 4 引数(末尾カンマ)は sed 経路専用だったので、シグネチャごと落とす。**

```bash
# $1=file $2=key $3=raw-json-value
#
# **jq 必須**(呼び出し元が require_jq を通していること)。sed で書き換える経路は
# 削除した(#63)。壊れ方を後追いで検出するための独自検査(先頭 { / 末尾 } /
# キーの実在)も、jq -e . が本物のパーサで見るので不要になった。
write_field() {
  local _file="$1" _key="$2" _val="$3"
  local _tmp="$_file.tmp.$$"
  local _bak="$_file.bak"

  jq --argjson v "$_val" --arg k "$_key" '.[$k] = $v' "$_file" >"$_tmp" 2>/dev/null || {
    rm -f "$_tmp"
    return 1
  }

  cp "$_file" "$_bak"
  mv "$_tmp" "$_file"

  # 妥当性確認。壊れていればバックアップから戻す。
  if ! jq -e . "$_file" >/dev/null 2>&1; then
    mv "$_bak" "$_file"
    return 1
  fi
  rm -f "$_bak"
  return 0
}
```

### 4-3. `cmd_accept` の呼び出しを 3 引数に直す

現行:

```bash
  # accepted は write_record が書く JSON の最後のフィールド。
  # sed 経路は末尾カンマを常に付けるため、末尾フィールドではカンマ無しにする。
  if ! write_field "$_f" accepted true ""; then
```

に変える(コメントは sed 経路の説明なので削除する):

```bash
  if ! write_field "$_f" accepted true; then
```

`cmd_set_status` の `write_field "$_f" status "\"$_new\""` は**そのままでよい**
(もともと第 4 引数を渡していない)。

### 4-4. 各サブコマンドに層の判定を入れる

`cmd_*` 関数の**先頭**に置く(`find_record` の前でよい)。

- `cmd_list` 先頭:

  ```bash
  # 止める層(#63): 一覧は人間が検収判断に使う。jq が無いと全フィールドが
  # 空欄で並び、「未検収が無い」ように見える。空欄より止める方が安全。
  require_jq "codex-run" 2
  ```

- `cmd_accept` / `cmd_set_status` 先頭:

  ```bash
  # 止める層(#63): 検収状態を書き換える。
  require_jq "codex-run" 2
  ```

- `cmd_prune` 先頭(**引数パースより前**でよい):

  ```bash
  # 止める層(#63): record を削除する。status / accepted が読めないまま
  # 走らせると、未検収の record を「消してよい」と誤判定しうる。
  require_jq "codex-run" 2
  ```

- `cmd_pending` 先頭(**`[ -d "$RUN_DIR" ] || exit 0` と同じ扱い**):

  ```bash
  # **止めない層(#63)。** ここは SessionStart hook が呼ぶ注入口で、
  # exit 2 を返すとセッション開始そのものに影響する。jq が無ければ
  # 注入をスキップして黙って続行する(require_jq は呼ばない)。
  command -v jq >/dev/null 2>&1 || exit 0
  ```

- `cmd_show` には**何も入れない**。`cat` しかしておらず、record が壊れている
  ときの調査手段だから(4-1 のヘッダーにその旨を書く)。

## 5. 影響範囲の確認(層の取り違えが唯一の危険)

`lib-record.sh` を source するのは **`delegate-codex.sh` と `codex-run.sh` の 2 本だけ**
(実測: `grep -rl "lib-record.sh" --include="*.sh"`)。`session-start.sh` は
`lib-record.sh` を source せず、`codex-run.sh pending` を**サブプロセスとして**呼ぶだけ
(`bash .claude/scripts/codex-run.sh pending 2>/dev/null || true`)。したがって
pending が `exit 0` で黙って抜ければ、SessionStart は従来どおり続行する。

`untrusted_sanitize` / `untrusted_oneline` / `untrusted_block`(#61)は jq を使わない。
**変更しない。**

## 6. 検証(受け入れ条件の実測手順)

### 6-1. jq を PATH から外した環境の作り方

`jq` は `/usr/bin/jq`。ディレクトリごと外すと他のコマンドまで消えるので、
**jq 以外の実行ファイルへの symlink を張った PATH** を作る:

```bash
NOJQ=/tmp/claude-1000/nojq-bin
rm -rf "$NOJQ"; mkdir -p "$NOJQ"
IFS=: read -ra _dirs <<<"$PATH"
for d in "${_dirs[@]}"; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    b="${f##*/}"
    [ -x "$f" ] && [ ! -d "$f" ] && [ "$b" != "jq" ] && [ ! -e "$NOJQ/$b" ] && ln -s "$f" "$NOJQ/$b"
  done
done
PATH="$NOJQ" command -v jq   # 何も出ないこと(rc=1)
```

### 6-2. 実測項目

| # | コマンド | 期待 |
| --- | --- | --- |
| V1 | `PATH="$NOJQ" bash .claude/scripts/delegate-codex.sh impl .steering/20260903-issue63-jq-required; echo $?` | **3**。メッセージは `delegate-codex: jq が見つかりません…`(入口検査4 の codex CLI 不在ではないこと) |
| V2 | `PATH="$NOJQ" bash .claude/scripts/delegate-codex.sh --print-forbidden \| wc -l; echo rc=$?` | **jq あり実行時と同じ行数 / rc=0**(現時点 32 行 = `FORBIDDEN_PATHS` + `AGENTS.md` §4 のプロジェクト固有パス。数値は増減しうるので、jq 有無で**一致すること**を見る) |
| V3 | `PATH="$NOJQ" bash .claude/scripts/codex-run.sh pending; echo $?` | **出力なし / 0** |
| V4 | `PATH="$NOJQ" bash .claude/hooks/session-start.sh </dev/null; echo $?` | **0**(注入本文が出て、Codex 委託の節だけが消える) |
| V5 | `PATH="$NOJQ" bash .claude/scripts/codex-run.sh list; echo $?` | **2** + jq のメッセージ |
| V6 | `PATH="$NOJQ" bash .claude/scripts/codex-run.sh accept <既存 id>; echo $?` | **2**。**record が書き換わっていないこと**(`git status` / `jq .accepted` で確認) |
| V7 | `bash .claude/scripts/codex-run.sh pending`(jq あり) | 従来どおり未検収一覧が出る |
| V8 | `bash .claude/scripts/codex-run.sh list --all \| head` | 全フィールドが埋まっている |
| V9 | 使い捨て record を作って `codex-run.sh accept <id>` → `set-status <id> failed` → `jq . <file>` | rc=0 / `accepted: true` / `status: "failed"` / **JSON として妥当**。`.bak` `.tmp.*` が残っていないこと |
| V10 | `CODEX_DELEGATE_NO_SELF_COPY=1 bash .claude/scripts/delegate-codex.sh --print-forbidden \| wc -l` | **V2 と同じ行数**(自己コピー無効経路でも共有ファイルが解決される) |
| V11 | 自己コピー経路の同梱: `bash .claude/scripts/delegate-codex.sh --print-forbidden >/dev/null; echo $?` | **0**(警告 `lib-record.sh の一時コピーを使えていません` が出ないこと) |
| V12 | `bash -n` を 3 本(`lib-record.sh` / `delegate-codex.sh` / `codex-run.sh`)+ `shellcheck` | エラーなし |

**V9 の使い捨て record** は既存を壊さないよう新規に作る:

```bash
ID="99999999-000000-$$"
printf '{\n  "id": "%s",\n  "mode": "impl",\n  "status": "running",\n  "pid": 999999,\n  "accepted": false\n}\n' "$ID" > .harness/codex-runs/$ID.json
# 検証後: rm -f .harness/codex-runs/$ID.json
```

`pid: 999999` は非数値ではないが生存しない値。`kill -0` が失敗して
`running(プロセス不在)` 側に落ちるため、`prune` の「実行中は残す」判定も同時に見られる。
**検証が終わったら必ず消す**(未検収 record が残ると SessionStart に出続ける)。

### 6-3. `/check`

`bash .claude/scripts/check-guard-integrity.sh`(引数なし)も 1 回通し、
ガードレール健全性が変わっていないことを見る。

## 7. CHANGELOG(`docs/template-dev/CHANGELOG.md`)

`## 2026-09-03` の見出し**配下の先頭**に追記する(日付見出しが既にあるので**新しい見出しを作らない**)。
区分は **`[manual]`**(jq を入れていない環境では委託が止まるため、取り込む側に作業が要る)。

```markdown
- **[manual]** **委託経路(`delegate-codex.sh` の委託モード / `codex-run.sh` の書き込み系)を `jq` 必須にし、`rec_field` / `write_field` の sed フォールバック経路を削除しました(Issue #63)。** sed 経路は「末尾カンマを飲み込んで再入防止が静かにフェイルオープン」する Critical(#29)と、壊れた JSON を検知するための独自検査を生んでおり、**失敗がエラーではなく空文字列として現れる**のが本質的な問題でした。jq が無い場合、`delegate-codex.sh` は **`exit 3`**(Codex 利用不可 = Sonnet fork へ恒久フォールバック)で止まります。**SessionStart 注入(`codex-run.sh pending`)だけはフェイルオープンのまま**で、jq が無ければ注入をスキップして黙って続行します(ここを止めるとセッションが開けません)。**取り込む側の作業**: 委託を使う環境に `jq` が入っているか確認してください(devcontainer / CI には既に入っています)。入っていない場合、委託は `exit 3` で止まり Sonnet fork に落ちます
```

## 8. やらないこと(スコープ外の再掲)

- `check-protected-branch.sh` / `check-implementation-phase.sh` / `check-guard-integrity.sh` /
  `session-start.sh` 自身の jq 使用箇所は**触らない**
- `codex-delegation-plan.md` の過去の検証記録(§の実測表・事故の記録)は**history なので書き換えない**
- run record のフォーマット変更・`prune` の判定規則の変更はしない
