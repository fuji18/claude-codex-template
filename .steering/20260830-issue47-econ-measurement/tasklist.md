# タスクリスト: econ モードの効果測定(Issue #47)

対応する設計: `design.md`(§4 に各ファイルの変更内容が確定済み。設計判断は不要)

- [x] `docs/template-dev/econ-measurement.md` を新規作成する(design.md §4-1 の構成・見出しに従い、§1〜§3 の内容を本文にする)
- [x] `docs/template-dev/README.md` の表に `econ-measurement.md` の行を足す(design.md §4-2。`cost-model.md` の行の直後)
- [x] `.claude/rules/mode/econ.md` の「司令塔の作法」に作法5 を **1 行**足す(design.md §4-3。他の行は変更しない)
- [x] `.harness/decisions.jsonl` の `mode-b-weekly-budget-baseline-followup` の行を design.md §4-4 の 1 行に置換する(`date` / `issue` は変更しない)
- [x] `docs/template-dev/CHANGELOG.md` の既存 `## 2026-08-30` 見出しの直下に design.md §4-5 のブロックを挿入する(日付見出しは新設しない)
- [x] 検証: `decisions.jsonl` の全行が `jq -e .` を通ること / `econ.md` の追加行数が 1 であること(design.md §6)

## 司令塔が実装後に行う(このリストの対象外)

- `.harness/decisions.jsonl` へ `"issue": 47` の行を追記する(`delegation-policy.md`: 書くのは PR を出す前)
- コミット・PR 作成

## 振り返り(申し送り)

### 検収で入った変更(レビュー 1 巡 / Major 2・Minor 2、すべて採用)

- **[Major] normal 層のサンプルが構造的に溜まらない** — `usage.mode` で econ / normal を層別する設計なのに、リマインドを `mode/econ.md` にしか置いていなかった。`.claude/rules/mode/` に normal 用の注入ファイルは存在しないため、normal 側の記録トリガがどこにも無く、比較が永久に「サンプル不足」で止まる。**対処**: `.claude/rules/lead/delegation-policy.md`「実測の記録」の既存 1 行に `/usage` の週枠使用率を足した(行数は増えない・モードによらず司令塔セッションに注入される)。normal 用のルールファイル新設は、normal が既定モードでほぼ全セッションに載るため採らなかった
- **[Major] CHANGELOG の `[auto]` 区分が実態と食い違う** — `.harness/` と `docs/` は `template-manifest.json` の `never` で `/sync-template` が触らない。上書き対象外のファイルへの変更を `[auto]`(取り込む側の作業ゼロ)と書くと「何もしなくても反映される」と誤読される。**対処**: `decisions.jsonl` の項目を `[manual]` に変え「次に書くときから `usage` を足す」を明記、`econ-measurement.md` の項目には同期対象外である旨を追記した
- **[Minor]** `"issue":47` の行を PR 前に追記(司令塔の担当として実施済み)
- **[Minor]** `measured_at` にタイムゾーンを必須化(`week_resets_at` との突き合わせで解釈がぶれるため)
- 司令塔が自分で見つけた粗 3 件も同時に修正: `要求2` の宙に浮いた参照 / 中央値の参照先が `§5` → `§4-6` / 「過去 22 行」の固定値が陳腐化する

### 次に持ち越すこと

- **Issue #47 の受け入れ条件のうち「次に econ モードでチケットを消化したとき、記録が漏れないことを 1 件で確認する」は未消化**(Issue 本文どおりクローズ条件には含めない)。次回の econ 運用時に確認する
- **この PR 自身の `usage.weekly_pct` は `null`。** `/usage` は人間しか読めず本セッションでは未取得。normal 層の 1 件目として値を残したい場合は、当該行に後から追記する
- **閾値(`delegation-policy.md`)は動かしていない。** 各モード 3 件揃うまで動かさないのが今回確定した条件
