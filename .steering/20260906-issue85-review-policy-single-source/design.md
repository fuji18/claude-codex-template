# 設計: レビュー方針を review-policy.md に一本化する

<!-- status: ready -->

## 0. 前提(実装者はここだけ読めば判断不要)

- 変更対象は **3 ファイルのみ**: `.claude/rules/lead/delegation-policy.md` /
  `.claude/rules/lead/review-policy.md` / `docs/template-dev/CHANGELOG.md`
- **`review-policy.md` の既存本文に不足は無い。** 司令塔が両者を突き合わせた結果、
  `review-policy.md:32-35` は `delegation-policy.md:52-59` の**上位集合**である
  (`review-policy.md` だけが「Agent Teams 並行レビュー」と「通常の大きめ差分にはどちらも使わない」を持つ)。
  したがって **`delegation-policy.md` 側から `review-policy.md` へ移す本文は無い。削除だけでよい。**
- 着手前の実測値(`wc -c`):

  | ファイル | 変更前 |
  | --- | --- |
  | `.claude/rules/lead/delegation-policy.md` | 10,874 B |
  | `.claude/rules/lead/review-policy.md` | 4,918 B |
  | `lead/*.md` 合計(6 ファイル) | 28,854 B |

## 1. 変更 E1: `delegation-policy.md` の粒度表の該当行をポインタにする

対象は 8 行目から始まる粒度表の中の「重要変更のレビュー」行(現在 13 行目)。
**4 列目(判定基準)だけを置き換える。** 1〜3 列目は変更しない。

置換前(行全体):

```
| **重要変更のレビュー** | `delegate-codex.sh review` | 200 行以上かつ認証・決済・データ移行・アーキテクチャ変更 | **この条件の既定はこちら。**`/code-review ultra` は昇格先で、併用しない(下記) |
```

置換後(行全体):

```
| **重要変更のレビュー** | `delegate-codex.sh review` | 200 行以上かつ認証・決済・データ移行・アーキテクチャ変更 | **判断の実体は `review-policy.md`「200 行以上 かつ 重要変更」の項。** ここでは粒度だけを示す |
```

**「(下記)」を消すことが必須**(E2 で参照先の節が消えるため、残すと宙に浮いた参照になる)。

## 2. 変更 E2: `delegation-policy.md` の解説節と「片方だけ直さないこと」を削除する

現在 52〜59 行目の節を、**前後の空行を 1 つだけ残す形で丸ごと削除する。**

削除する範囲は、次の見出し行から:

```
### 重要変更のレビューは `delegate-codex.sh review` が既定(`/code-review ultra` は昇格先)
```

次の見出し行の**直前**まで:

```
### 損益分岐(粒度を満たしていても常に得ではない)
```

削除後は、`### 委託禁止領域(パス一覧)` 節の末尾段落(`**機密の送信禁止...振り分け判断。**`)の直後に
**空行 1 つを挟んで** `### 損益分岐(粒度を満たしていても常に得ではない)` が来る形になる。
空行が 2 連続したり 0 になったりしないこと。

**この節の中にある「同じ結論を `.claude/rules/lead/review-policy.md` にも書いてある。**片方だけ直さないこと。**」
も同時に消える**(受け入れ条件 3)。`review-policy.md` 側には同種の注記は元から無いので、
そちらでの削除作業は発生しない。

## 3. 変更 E3: `review-policy.md` を単一ソースとして明示する

**本文の判断は 1 文字も変えない。** 32 行目の末尾に、単一ソースであることの目印だけを足す。

置換前(32 行目の全体):

```
- **200 行以上 かつ 重要変更(認証・決済・データ移行・アーキテクチャ変更)のレビュー**: **既定は `delegate-codex.sh review`**。`/code-review ultra` と Agent Teams 並行レビューは**昇格先**であって、既定と併用しない(同じ発動条件に 2 つの手段を割り当てると両方回す運用崩れになる。#60 / C4)
```

置換後(32 行目の全体):

```
- **200 行以上 かつ 重要変更(認証・決済・データ移行・アーキテクチャ変更)のレビュー**(**この判断の単一ソース**。`delegation-policy.md` の粒度表からは 1 行で参照される): **既定は `delegate-codex.sh review`**。`/code-review ultra` と Agent Teams 並行レビューは**昇格先**であって、既定と併用しない(同じ発動条件に 2 つの手段を割り当てると両方回す運用崩れになる。#60 / C4)
```

33〜35 行目(理由・提案する 2 条件・「通常の大きめ差分にはどちらも使わない」)は**無改変**。

### なぜ「片方だけ直さないこと」ではなく「単一ソース」と書くのか

前者は**双方向の同期義務**(=乖離が起きうる前提)を宣言している。後者は**方向のある参照**で、
`delegation-policy.md` を直しても判断は変わらない、と読める。今回の目的はこの向きを付けること。

## 4. 変更 E4: 削減幅の計測

E1〜E3 を適用した**後**に、次を実行して実測値を得る:

```bash
wc -c .claude/rules/lead/*.md
cat .claude/rules/lead/*.md | wc -c
```

得た値を E5 の CHANGELOG 本文に埋める。**推定値を書かない。**
`delegation-policy.md` 単体の変更前後と、`lead/*.md` 合計の変更前後(変更前は §0 の表の値)を記録する。

## 5. 変更 E5: `docs/template-dev/CHANGELOG.md` への追記

`## 2026-09-06` 見出しの**直下**(既存の D0 の項目より上)に、区分 `[auto]` で追記する。
新しい日付見出しは作らない(同日に #82〜#84 の項目が既にあるため)。

文面(`X` / `Y` / `Z` / `W` は §4 の実測値に置き換える):

```
- **[auto]** 「200 行以上 かつ 重要変更のレビュー」の判断を
  `.claude/rules/lead/review-policy.md` の 1 箇所に一本化しました。
  `delegation-policy.md` は粒度表の 1 行ポインタだけになり、同じ結論を複製していた解説節と
  「片方だけ直さないこと」の注記を削除しています。**司令塔の結論は変わりません**
  (既定 = `delegate-codex.sh review` / 昇格先 = `/code-review ultra` / 併用しない)。
  SessionStart hook が毎回注入する `lead/*.md` は Z B → W B(delegation-policy.md 単体で
  X B → Y B)になりました(Issue #85)。
```

行の折り返しは既存項目に合わせる(1 行あたり全角 40〜45 文字程度)。

## 6. やらないこと(明示)

- `review-policy.md:32-35` の**判断内容の変更**。文言の言い換えもしない(受け入れ条件 5)
- `delegation-policy.md` の他の節(粒度表の他の行 / 委託禁止領域 / 損益分岐 / バッチ運用 /
  ラベルの付け外し / 実測の記録)への変更
- `lead/` 配下の他の 4 ファイルへの変更。**司令塔が横断走査済みで、追加の重複は無い**
  (根拠は `requirements.md` の「司令塔による事前調査」表)
- `<!-- forbidden-paths -->` マーカーとその中身への変更。CI の `harness-integrity` ジョブが
  `delegate-codex.sh --print-forbidden generic` と完全一致で照合しているため、
  **1 文字でも触れると CI が落ちる**
- `README.md` / `CLAUDE.md` / `.claude/commands/*.md` の更新。
  司令塔が全リポジトリを grep した結果、削除する節を名指しで参照している箇所は
  `delegation-policy.md:59` の当該注記だけだった(`.steering/` の過去ログを除く)

## 7. 検証

```bash
# 1) 削除した節が消えているか / 注記が両ファイルから消えているか
grep -rn "片方だけ直さないこと" .claude/rules/    # 0 件であること
grep -n "重要変更のレビューは" .claude/rules/lead/delegation-policy.md  # 0 件であること

# 2) 判断の実体が review-policy.md にだけ残っているか
grep -rln "ユーザー起動 + 課金" .claude/rules/   # review-policy.md の 1 件だけであること

# 3) 宙に浮いた参照が無いか
grep -n "(下記)" .claude/rules/lead/delegation-policy.md   # 当該行に無いこと

# 4) 禁止領域テーブルの整合(CI と同じ検査)
bash .claude/scripts/check-forbidden-paths-doc.sh

# 5) 通常の品質チェック
npm run lint && npm run format:check
```

**検証 4 が落ちたら E2 の削除範囲が広すぎる。** マーカー内を戻すこと。
