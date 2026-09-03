# 設計: レート上限の構造化識別子マッチを行単位に限定する(Issue #62)

<!-- status: ready -->

## 1. 実測した事実(この設計の根拠)

### 1.1 `$LOG` の中身

`delegate-codex.sh` の `codex exec --json ... >"$LOG" 2>&1` により、`$LOG` には
**改行区切りの JSON イベント(stdout)** と **codex 自身の tracing 行(stderr)** が混ざる。
既存 run record(`.harness/codex-runs/*.log`)で確認した実形式:

```
Reading additional input from stdin...
{"type":"thread.started","thread_id":"01a0..."}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"..."}}
{"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"/bin/bash -lc \"sed -n '1,260p' AGENTS.md ...\"","aggregated_output":"","exit_code":null,"status":"in_progress"}}
```

**委託先が読んだファイルの内容は `item.*` イベントの中に JSON 文字列として入る。**
改行は `\n` に、引用符は `\"` にエスケープされるので、**引用されたファイル内容が
独立した行の先頭に来ることはない。** これが今回の限定が成立する根拠。

### 1.2 エラー系イベントの実形式(codex-cli v0.149.0 で実測)

未認証の `HOME` で `codex exec --json` を流し、失敗時に出るイベントを採取した
(2026-09-03 実測。ネットワークは有効、認証だけを落とした):

```
{"type":"error","message":"unexpected status 401 Unauthorized: Missing bearer or basic authentication in header, url: https://api.openai.com/v1/responses, cf-ray: ..., request id: ..."}
{"type":"item.completed","item":{"id":"item_0","type":"error","message":"Falling back from WebSockets to HTTPS transport. ..."}}
{"type":"turn.failed","error":{"message":"unexpected status 401 Unauthorized: ..."}}
```

バイナリ内のイベントタグ表(`ThreadEvent`)も同じ構成:
`thread.started` / `turn.started` / `turn.completed` / `turn.failed` /
`item.started` / `item.updated` / `item.completed`、これに `{"type":"error"}` が加わる。

**結論**: レート上限の構造化識別子は `{"type":"error",...}` と
`{"type":"turn.failed",...}` の 2 種類のトップレベル行で運ばれる。
この 2 種類は**ファイル引用を運ばない**(payload はエラーメッセージのみ)。
一方 `item.*` は `aggregated_output` / `text` でファイル内容を運ぶ。

## 2. 方針

**許可リスト方式**で「トップレベルのエラーイベント行」だけに `RATE_ID_RE` を当てる。

- 除外側(`item.*` を弾く)= 拒否リストにしない。codex が新しい内容運搬イベントを
  足したときに旧バグへ戻るため
- 許可リストの失敗方向は**見逃し**(`exit 4` にならず `exit 2` になる)= 安全側。
  run record に生エラー(`ERR3`)が残るので人間が判定できる(R5)。
  かつ `RATE_TEXT_RE`(`ERR_ONLY` 限定)が第 2 の網として残る
- 誤検知方向(`exit 2` であるべきものが `exit 4` になる)は**塞ぐ**。これが本チケットの目的

行頭アンカー(`^{"type":"..."`)を使えるのは §1.1 のエスケープ規則による。
引用されたファイル内容の中では `{\"type\":\"error\"` の形になり、かつ行頭に来ない。

## 3. 変更内容(これがすべて。他のファイルは触らない)

### 3.1 `.claude/scripts/delegate-codex.sh` — 定数の追加

`RATE_ID_RE='rate_limit_reached|usage_limit_reached|credits_depleted'`(現行 `:1302`)の
**直後**に、次の 1 行と直前コメントを追加する:

```sh
RATE_ID_RE='rate_limit_reached|usage_limit_reached|credits_depleted'
# 構造化識別子を当てる範囲。トップレベルのエラーイベント行だけに限定する。
# codex exec --json のイベントのうち、ファイル引用(aggregated_output / text)を
# 運ぶのは item.* だけで、error / turn.failed はエラーメッセージしか運ばない
# (v0.149.0 実測。design.md §1.2)。引用されたファイル内容は JSON 文字列の中で
# \" にエスケープされ行頭にも来ないため、行頭アンカーで確実に外れる。
# 外した側の失敗方向は「見逃し = exit 2」で安全側。生エラーは run record に残る。
RATE_EVENT_RE='^\{"type":"(error|turn\.failed)"'
RATE_TEXT_RE='rate limit|usage limit|quota|429'
```

**`RATE_ID_RE` / `RATE_TEXT_RE` / `AUTH_RE` の中身は変更しない。**

### 3.2 `.claude/scripts/delegate-codex.sh` — 適用箇所の書き換え

現行(`:1405-1406`):

```sh
  if grep -Eqi "$RATE_ID_RE" "$LOG" 2>/dev/null ||
    printf '%s' "$ERR_ONLY" | grep -Eqi "$RATE_TEXT_RE"; then
```

変更後(**1 回の `grep` で完結させる。パイプにしない**):

```sh
  if grep -Eqi "$RATE_EVENT_RE.*($RATE_ID_RE)" "$LOG" 2>/dev/null ||
    printf '%s' "$ERR_ONLY" | grep -Eqi "$RATE_TEXT_RE"; then
```

注意点(そのまま守ること):

- **2 段の `grep` をパイプでつながない。** このスクリプトは `:35` で `set -uo pipefail` を
  有効にしており、`grep -E ... "$LOG" | grep -Eqi ...` にすると **`grep -q` が最初の
  ヒットで即終了 → 上流の `grep` が SIGPIPE で 141 → `pipefail` によりパイプ全体が 141
  = 偽**になる。実測では 277KB(実ログとほぼ同サイズ)のログで 10 回中 10 回とも
  この経路に落ち、**本物のレート上限を取り逃がした**(2026-09-03 実測)。
  ログが小さいとき(数行のスタブ)だけ通るため、検証で見落としやすい
- 同じ理由で `RATE_EVENT_LINES="$(grep ...)"` に一旦受けて
  `printf '%s' "$RATE_EVENT_LINES" | grep -Eqi ...` とするのも避ける。
  行数が多いと `printf` 側が同じ SIGPIPE 経路に落ちる
  (既存の `ERR_ONLY` がこの形なのは**高々 20 行**で必ずパイプバッファに収まるため)
- 合成した正規表現は `-Eqi`(大小無視)のまま使う。行頭アンカーがあるので、
  引用されたファイル内容がこの条件に乗ることはなく、大小無視でも限定は緩まない
- `.*` を挟んでも `grep` は行単位なので、**別々の行**のタグと識別子が
  組み合わさって成立することはない
- **スクリプト冒頭の `set` 行は変更しない**

### 3.3 ログ範囲コメントの更新

`:1283` から始まる「── 何を、どの範囲で見るか(重要)──」ブロックの中の

```
#   - 失敗(exit 非ゼロ)したときだけ判定する。構造化識別子はログ全体に
#     当ててよいが、緩い文言パターンは末尾 20 行のうち "error" / "fail"
#     を含む行だけに当てる。末尾に絞るだけでは足りない — 失敗した委託の
#     末尾にも、Codex が読んだファイルの引用は来る。
```

を、次に差し替える(「構造化識別子はログ全体に当ててよい」が誤りだったため):

```
#   - 失敗(exit 非ゼロ)したときだけ判定する。ただし構造化識別子も
#     ログ全体には当てない — 委託先が読んだファイルの引用がイベントの中に
#     入るため、このリポジトリ自身(識別子を本文に含む)を読んだ委託が
#     タスク起因で失敗すると exit 4 に化ける(#62)。トップレベルの
#     エラーイベント行(error / turn.failed)だけに当てる。
#     緩い文言パターンはさらに狭く、末尾 20 行のうち "error" / "fail"
#     を含む行だけに当てる。末尾に絞るだけでは足りない — 失敗した委託の
#     末尾にも、Codex が読んだファイルの引用は来る。
```

### 3.4 `docs/template-dev/CHANGELOG.md`

既存の `## 2026-09-03` 見出し(ファイル先頭側)の**項目リストの末尾**に 1 行足す。
**新しい日付見出しは作らない**(同じ日付の見出しが既にある)。

```markdown
- **[auto]** 失敗した委託のレート上限判定で、構造化識別子(`rate_limit_reached` 等)を**トップレベルのエラーイベント行(`{"type":"error"}` / `{"type":"turn.failed"}`)だけ**に当てるようにしました(Issue #62)。従来はログ全文に当てていたため、**これらの識別子を本文に含むファイル(`delegate-codex.sh` 自身や計画書)を読んだ委託がタスク起因で失敗すると `exit 4`(レート上限 = 待て)に誤分類され**、`exit 2` の原因分析に入れませんでした。取りこぼした場合は `exit 2` + run record の生エラーに落ちる安全側の失敗になります
```

## 4. 検証(実測。すべて `codex` スタブで行う)

`codex` 実バイナリを呼ばずに、`PATH` の先頭に置いたスタブで `$LOG` の内容と
終了コードを作る。既存の V9 / V15(`.steering/20260823-issue5-codex-impl-delegation/design.md`)と
同じ手法。

作業用ディレクトリは `/tmp/claude-1000/.../scratchpad`(このセッションのスクラッチパッド)を使い、
**リポジトリ内に検証用ファイルを残さない。**

### 手順(共通)

1. スタブ `stub/codex` を作る。**入口検査4 が `codex login status` を先に呼ぶので、
   スタブは 2 つのサブコマンドを扱う必要がある**:
   - `login status` → 何も出さず `exit 0`
   - `exec ...` → 引数から `--output-last-message` の値を拾って空ファイルを作り、
     検証ケースの行を stdout に出して `exit 1`

   雛形(検証ケースの行は環境変数 `STUB_LOG` にファイルパスで渡す):

   ```sh
   #!/usr/bin/env bash
   if [ "$1" = "login" ]; then exit 0; fi
   last=""
   while [ $# -gt 0 ]; do
     [ "$1" = "--output-last-message" ] && last="$2"
     shift
   done
   [ -n "$last" ] && : >"$last"
   cat "$STUB_LOG"
   exit 1
   ```

   `env -i` で呼ばれるため **`STUB_LOG` は素通しされない**。スタブ内で参照できるよう、
   雛形の `cat "$STUB_LOG"` は**検証ケースごとにログ本文を直接埋め込む形に書き換える**
   (ケースごとにスタブを作り直すのが確実)
2. `PATH="$PWD/stub:$PATH"` で `delegate-codex.sh` を呼ぶ。**引数は `explore` モード**を使う
   (read-only なので作業ツリーを変更しない。impl の入口検査を通さずに出口判定へ到達できる)
3. `$?` と `.harness/codex-runs/*.json` の `status` を確認する

### V1(誤検知が消えること / R4)

スタブが出す行 — 「ファイルを読んだだけ」を再現する `item.completed` 行:

```
{"type":"thread.started","thread_id":"t"}
{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/bash -lc \"sed -n '1,20p' .claude/scripts/delegate-codex.sh\"","aggregated_output":"RATE_ID_RE='rate_limit_reached|usage_limit_reached|credits_depleted'\n","exit_code":0,"status":"completed"}}
{"type":"turn.failed","error":{"message":"tool call failed: command exited with 1"}}
```

期待: **`exit 2`** / record の `status` が `failed`。
(変更前の実装ではここが `exit 4` / `rate-limited` になる — 修正前後で両方流して差を確認する)

### V2(本物は従来どおり通ること / R3)

```
{"type":"thread.started","thread_id":"t"}
{"type":"error","message":"stream error: rate_limit_reached"}
{"type":"turn.failed","error":{"message":"rate_limit_reached: please try again later"}}
```

期待: **`exit 4`** / record の `status` が `rate-limited`。

### V3(文言パターンの網が残ること)

```
{"type":"thread.started","thread_id":"t"}
{"type":"error","message":"request failed with status 429"}
{"type":"turn.failed","error":{"message":"error: too many requests (429)"}}
```

期待: **`exit 4`**(`RATE_TEXT_RE` の `429` が `ERR_ONLY` にヒットする)。
これは今回の変更で壊れていないことの確認。

### V4(既存の回帰確認)

`bash -n .claude/scripts/delegate-codex.sh` が通ること。

### V5(大きいログでも本物が通ること / R3・SIGPIPE 回帰)

**V2 と同じ内容を大きいログで流す。** 3 行のスタブログでは §3.2 の SIGPIPE 経路が
発生せず、欠陥を見逃す。スタブが出す内容:

1. 1 行目に本物のレート上限イベント
   `{"type":"error","message":"stream error: rate_limit_reached"}`
2. 続けて `{"type":"error","message":"pad <n> aaaa…"}` を **2000 行以上**(合計 250KB 以上)
3. 最後に `{"type":"turn.failed","error":{"message":"rate_limit_reached"}}`

期待: **`exit 4`** / record の `status` が `rate-limited`。
**`exit 2` になったら §3.2 の注意点(パイプにしない)に違反している。**

### 後片付け

検証で増えた `.harness/codex-runs/*` は**コミットしない**。`git status` で確認し、
生成物が残っていれば削除する(`.gitignore` 対象なら何もしなくてよい。まず `git status` を見る)。

## 5. やらないこと

- `RESET_AT` の抽出範囲の変更(要求のスコープ外。上限判定が成立した後にしか読まれない)
- `RATE_TEXT_RE` / `AUTH_RE` の内容・適用範囲の変更
- 新しいテストフレームワークの導入(このリポジトリにシェルのテストスイートは無い)

## 6. 検収指摘の判断(2026-09-03 / code-reviewer 1 巡目)

0 critical / 1 major / 2 minor。判断は次のとおり。

### Major: `item.completed` にネストされた `type:"error"` が許可リストから漏れる

**ロジックは変えない。理由をコメントで残す(T11)。**

- 判定に入るのは `CODEX_EXIT != 0` のときだけ = **ターンが失敗している**。
  §1.2 の実測では、致命的な理由は必ずトップレベルの `turn.failed` に載って出た
  (item にネストされた `type:"error"` は "Falling back from WebSockets…" という
  **非致命の通知**だった)。したがって許可リストの `turn.failed` が終端理由を捕まえる
- レビューの代替案「`RATE_TEXT_RE` にアンダースコア表記を足す」は**採らない**。
  `RATE_TEXT_RE` は `ERR_ONLY`(末尾 20 行のうち error/fail 行)に当たり、そこには
  **ファイル引用が来る**(既存コメントに実測として明記済み)。識別子を足すと
  #62 と同じ誤検知を、窓を狭めただけの形で作り直すことになる
- 許可リストに `item.completed` の error 形状を足す案は、`item.completed` が
  `command_execution` の `aggregated_output`(= ファイル引用)も運ぶため、
  キー並び順に依存した脆い正規表現になる。**倒れる先が安全側**(見逃し = `exit 2` +
  run record の生エラー)である以上、脆い正規表現を足す方が損

### Minor: design.md の行番号ずれ

修正した(`:1302` → `:1306` / `:1394-1395` → `:1405-1406`)。

### Minor: `workspace_owner_*` / `workspace_member_*` の変種が `RATE_ID_RE` に無い

**誤指摘。対応不要。** `RATE_ID_RE` はアンカーなしの部分一致なので、
`workspace_owner_credits_depleted` は `credits_depleted` に、
`workspace_member_usage_limit_reached` は `usage_limit_reached` に既に一致する。
codex-cli v0.149.0 のバイナリ内実文字列で確認済み。
