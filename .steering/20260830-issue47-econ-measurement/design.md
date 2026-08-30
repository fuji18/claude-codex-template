# 設計: econ モードの効果測定(Issue #47)

<!-- status: ready -->

実装者は設計判断をしない。本ファイルに書かれた内容を、指定のファイルに指定の形で反映するだけでよい。

## 1. 測定設計の中核となる 3 つの判断

### 判断1: 記録は「1 チケット 1 点」にする(開始値と終了値の 2 点を取らない)

週枠の使用率は**週次リセットまで単調増加する累積量**である。したがって 1 チケットにつき 1 点だけ記録すれば、**同じ週の隣接エントリの差**で「そのチケットが週枠を何 pp 消費したか」が事後に計算できる。

2 点(着手時 / 完了時)を取る案を採らない理由は 2 つ:

- econ モードは司令塔セッションが分割される設計(`econ.md` の作法1・作法4)。着手時のセッションと PR を出すセッションが別なので、2 点記録は「セッションをまたいで開始値を持ち越す」運用になり、最も落ちやすい
- 記録タイミングを増やすと `econ.md` の注入文が 1 行で収まらない(要求2 に反する)

**1 点記録の代償**: そのチケットの区間に混ざったチケット外の作業(相談・調査)が差分に混入する。これは受容し、集計では**平均ではなく中央値**を使う(判断3)。

### 判断2: 記録タイミングは既存の `decisions.jsonl` 書き込みに相乗りする

新しいタイミングを作らない。`delegation-policy.md` が定める「**書くのは PR を出す前**(検収が終わり、往復回数と指摘数が確定した時点)」と同じ瞬間に `usage` を載せる。

`/usage` は人間しか読めないため、司令塔は**その場でユーザーに 1 行で尋ねる**。答えが得られない場合は `weekly_pct` を `null` にして**そのまま進む**(PR を止めない)。測定は運用の従属物であって、測定のために運用を止めない。

### 判断3: サンプルが各モード 3 件揃うまで結論を出さない

1〜2 件の差で `delegation-policy.md` の閾値を動かさない。#8 の followup が失敗した理由の一つが「econ 運用の縦断サンプルが 1 チケット分しかない」ことだった。同じ失敗を繰り返さないよう、下限をデータ側の定義として書き残す。

## 2. `usage` オブジェクトの仕様

`.harness/decisions.jsonl` の既存の 1 チケット 1 行に、**任意フィールド `usage` を 1 つ足す**。既存キーは変更しない。行の JSON 構造は既存エントリ(`measure` オブジェクトを持つ #6 / #8 の行が先例)と同型で、CI 検査2 が見る `"issue": N` にも影響しない。

| キー | 型 | 内容 |
| --- | --- | --- |
| `mode` | string | 記録時点の `.harness/mode` の値。ファイルが無ければ `"normal"` |
| `weekly_pct` | number \| null | `/usage` が表示する**週枠の使用率**(整数 %)。得られなければ `null` |
| `week_resets_at` | string \| null | `/usage` が表示する週枠のリセット日時。表示のまま文字列で入れる |
| `measured_at` | string | 記録した日時(`YYYY-MM-DDTHH:MM`) |
| `raw` | string \| null | 上の 3 つに落とし込めなかったときの `/usage` 表示の写し。表示仕様が変わっても生データを失わないための逃げ場 |

`weekly_pct` が `null` の行は集計から除外される。**`usage` 自体が無い行があってよい**(過去 22 行はすべてそう)。

## 3. 事後の集計手順(このとおりに計算する)

1. `usage.weekly_pct` が非 null の行を `usage.measured_at` の昇順に並べる
2. 直前の行と `usage.week_resets_at` が**一致する場合のみ**差を取る。その差をその行のチケットの消費 pp とする
3. `week_resets_at` が変わった行(週境界)は差を取らずスキップする(週の最初の行はその週のベースライン)
4. `usage.mode` で層別する(`econ` vs `normal`)
5. **交絡は既存フィールドで統制する**: `delegated_to_codex` / `implementer` / `tasks`。**同じ委託経路のチケット同士だけを比べる**(Codex 委託した econ チケットと fork 実装した normal チケットを直接比べない)
6. 各層 3 件以上揃ってから、**中央値**で比較する。3 件未満なら「サンプル不足」とだけ記録し、閾値は動かさない

## 4. 変更するファイル(4 ファイル + 新規 1)

### 4-1. 新規: `docs/template-dev/econ-measurement.md`

上記 §1〜§3 の内容を文書化する。以下の構成・見出しで書く(本文は §1〜§3 の記述をそのまま使ってよい):

```
# econ モードの効果測定: 何を・いつ・どう記録するか

（導入 2〜3 行: 何が欠けていたか。delegation-policy.md の閾値宣言と
  mode-b-weekly-budget-baseline-followup の "未実施" の乖離）

## 1. 測る対象と主指標
  - 対象: モード B(econ)が週枠の実効寿命を延ばすか
  - 主指標: 週枠消費率 pp / チケット 1 枚

## 2. 記録の仕方(1 チケット 1 点)
  - §1 判断1 の内容(単調増加する累積量なので隣接差分で足りる / 2 点記録を採らない理由 2 つ / 混入の代償)

## 3. 記録するタイミングと値
  - §1 判断2 の内容 + §2 の表をそのまま載せる

## 4. 集計手順
  - §3 の 1〜6 をそのまま載せる

## 5. 結論を出す条件
  - §1 判断3 の内容(各モード 3 件未満で閾値を動かさない)

## 6. やらないことと、その理由
  - 自動化しない: /usage は機械取得できず、無理に自動化するとコストが測定対象を歪める
  - CI の必須項目にしない: /usage を読めない経路(サブエージェント・リモート実行)で全 PR が落ちる。
    担保は econ.md の 1 行リマインドだけに留める
  - 測定のためにモードを切り替えない: モード切替の宣言は人間の担当
```

末尾に参照を 1 行置く: 「関連: `.claude/rules/mode/econ.md`(リマインド) / `.claude/rules/lead/delegation-policy.md`(この測定が動かす閾値) / `docs/template-dev/cost-model.md`(既に取れている実測値)」

### 4-2. `docs/template-dev/README.md` の表に 1 行足す

`cost-model.md` の行の**直後**に挿入する:

```
| `econ-measurement.md` | **モード B(econ)の効果測定の設計**(何を・いつ・どう記録し、どの条件で結論を出すか)。記録の実体は `.harness/decisions.jsonl` の `usage` フィールド |
```

### 4-3. `.claude/rules/mode/econ.md` に 1 行足す

「### 司令塔の作法」の番号付きリスト(現在 1〜4)の **4 の直後に 5 として**、次の 1 行を追加する。**1 行を超えないこと**(econ モードの全セッションに注入される):

```
5. **`decisions.jsonl` を書く前に `/usage` の週枠使用率をユーザーに 1 行で尋ね、`usage` に載せる**(答えが無ければ `null` のまま進む。設計: `docs/template-dev/econ-measurement.md`)
```

他の行は変更しない。

### 4-4. `.harness/decisions.jsonl` の followup エントリを更新する

対象は `"topic":"mode-b-weekly-budget-baseline-followup"` の行(現在 5 行目)。**`date` と `issue` は変更しない**(#8 の時系列上の記録であるため)。`measure` を差し替え、`updated` / `updated_by_issue` / `design` を足し、`note` を書き換える。置換後の 1 行は次のとおり(改行を入れず 1 行で書く):

```json
{"date":"2026-08-24","topic":"mode-b-weekly-budget-baseline-followup","issue":8,"updated":"2026-08-30","updated_by_issue":47,"design":"docs/template-dev/econ-measurement.md","measure":{"metric":"週枠消費率 pp / チケット 1 枚(同じ週の隣接エントリの usage.weekly_pct の差)","source":"/usage の週枠使用率。人間しか読めないため、司令塔が decisions.jsonl を書く前にユーザーへ 1 行で尋ねて usage オブジェクトに載せる","granularity":"1 チケット 1 点(着手時と完了時の 2 点は取らない)","stratify_by":"usage.mode(econ / normal)。交絡は delegated_to_codex / implementer / tasks で統制し、同じ委託経路同士だけを比べる","min_samples":"各モード 3 件。それ未満では delegation-policy.md の閾値を動かさない","statistic":"中央値(チケット外の作業が差分に混入するため平均を使わない)","status":"設計確定・記録開始待ち"},"note":"#47 で測定設計を確定した。旧 status は「未実施」で、理由は (1) /usage は人間しか読めない (2) econ 運用の縦断サンプルが 1 チケット分しかない、の 2 点だった。(1) は「司令塔が PR 前にユーザーへ 1 行で尋ね、答えが無ければ null で進む」と決めて経路を作り、(2) は「1 チケット 1 点だけ記録して隣接差分で per-ticket コストを出す」に変えて、着手時の値を持ち越す必要をなくした(econ モードは司令塔セッションが分割される設計なので、2 点記録は最も落ちやすい)。記録漏れの担保は .claude/rules/mode/econ.md の作法5(1 行)だけに留め、CI 検査には足さない — usage を必須にすると /usage を読めない経路で全 PR が落ちる。ベースラインの定義(mode-b-weekly-budget-baseline)はそのまま有効。"}
```

### 4-5. `docs/template-dev/CHANGELOG.md` に追記する

既存の `## 2026-08-30` 見出しの**直下**(見出しと最初の項目の間)に挿入する。日付見出しは新設しない:

```
**econ モードの効果測定の設計を確定し、記録漏れを防ぐ 1 行を注入文に入れた(Issue #47)。** `delegation-policy.md` は委託粒度の閾値を「実測で上下させる」と宣言していますが、モード B の週枠寿命の比較は `decisions.jsonl` に「未実施」と記録されたままでした。宣言だけがあって実測が回らない状態は、#37 が機械化で塞いだ「散文の運用ルールは守られない」と同じ構造です。

- **[auto]** `docs/template-dev/econ-measurement.md` を新規追加(何を・いつ・どう記録し、どの条件で結論を出すか)。記録は **1 チケット 1 点**で、週枠使用率は週次リセットまで単調増加するため、同じ週の隣接エントリの差で per-ticket の消費が出ます。着手時の値を持ち越す必要がないので、セッションが分割される econ モードでも落ちません
- **[auto]** `.harness/decisions.jsonl` に任意フィールド `usage`(`mode` / `weekly_pct` / `week_resets_at` / `measured_at` / `raw`)を足せるようにした。**既存キーは変更していない**ため、CI(`check-record-hygiene.sh` 検査2)が見る `"issue": N` の前提は変わりません。`usage` が無い行があってよく、**CI の必須項目にはしません**(`/usage` を読めない経路で全 PR が落ちるため)
- **[manual]** **`.claude/rules/mode/econ.md` の「司令塔の作法」に作法5 を 1 行足した。** econ モードのセッションで `decisions.jsonl` を書く前に、`/usage` の週枠使用率をユーザーへ 1 行で尋ねて記録します(答えが無ければ `null` のまま進み、PR は止めません)。**取り込む側の作業**: econ モードを使っているプロジェクトでは、次回の econ 運用時にこの記録が 1 件残ることを確認する
```

## 5. やらないこと(実装者が足さないこと)

- `usage` を必須にする CI 検査の追加
- `/usage` を機械的に取得する hook・スクリプト
- `delegation-policy.md` の閾値の変更
- `decisions.jsonl` の既存 22 行への `usage` の遡及追記(取得不能な値を捏造することになる)
- `.harness/mode` の書き換え

## 6. 検証

- `.harness/decisions.jsonl` の全行が JSON として妥当であること:
  `while read -r l; do [ -z "$l" ] && continue; printf '%s' "$l" | jq -e . >/dev/null || echo "NG: $l"; done < .harness/decisions.jsonl`
- `.claude/rules/mode/econ.md` の追加が 1 行であること: `git diff --numstat .claude/rules/mode/econ.md` の追加行数が 1
- `bash .claude/scripts/check-record-hygiene.sh` 相当が通ること(CI で確認する。手元では環境変数が要るため必須にしない)

**実装フェーズではコミットしない。** 検証はワーキングツリーの状態に対して行う。
