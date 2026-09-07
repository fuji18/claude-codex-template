# 要求: 司令塔ルールの重複記述を解消する(レビュー方針を review-policy.md に一本化)

- Issue: #85(P2 / `ticket`)
- depends: #83(closed)
- `delegate:codex`: **付けない**(対象が `.claude/rules/` = 委託禁止領域)

## 背景

SessionStart hook が注入する `.claude/rules/lead/*.md` のうち、
`delegation-policy.md` と `review-policy.md` が
**「200 行以上かつ重要変更のレビューは `delegate-codex.sh review` が既定、`/code-review ultra` は昇格先」**
という同じ判断を**両方フルで**持っている。

`delegation-policy.md:59` にはこう書かれている:

> 同じ結論を `.claude/rules/lead/review-policy.md` にも書いてある。**片方だけ直さないこと。**

**この注記が必要になっている時点で、これは解決ではなく回避。**
#60(C4)で「同じ発動条件に 2 つの手段」という二択は解消したが、
そのとき**結論を 2 箇所に複製する形**で決着させたため、乖離のリスクが残った。

## 目的

判断の実体を `review-policy.md` に一本化し、`delegation-policy.md` からは 1 行のポインタにする。
**主目的はトークン削減ではなく乖離リスクの解消**(削減幅は約 1KB の見込み)。

既存の役割分担とも合致する:

| ファイル | 役割 |
| --- | --- |
| `delegation-policy.md` | **どの単位で**委託するか |
| `review-policy.md` | **どのレビュー手段を**使うか |

## 受け入れ条件(Issue より)

- [ ] 「200 行以上の重要変更のレビュー」の判断が `review-policy.md` の 1 箇所にだけ書かれている
- [ ] `delegation-policy.md` からは 1 行で参照できる
- [ ] 「片方だけ直さないこと」の注記が両ファイルから消えている
- [ ] `lead/*.md` の合計サイズの削減幅が計測され、`CHANGELOG.md` に記録されている
- [ ] 司令塔が「200 行以上の重要変更」に遭遇したときの結論が、整理の前後で変わっていない
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み

## スコープ外

- 司令塔ルールの**内容そのもの**の削減(判断が減ると司令塔の挙動が変わる)
- SessionStart hook の注入条件の変更
- `lead/` を `docs/template-dev/` へ移すこと
- `CLAUDE.md` の整理(#83 で完了済み)

## 司令塔による事前調査(手順 4「他に同種の重複が無いか」の結果)

`lead/*.md` 6 ファイルを横断して重複候補を洗った結果、
**判断の実体が 2 箇所にあるのは今回の 1 件だけ**で、他はすべて既にポインタ形になっていた。

| 候補 | 判定 |
| --- | --- |
| 委託先の既定(Codex → `exit 3` → Sonnet fork) | **重複なし。** 実体は `model-strategy.md:9`、`delegation-policy.md:6` は明示ポインタ |
| 参照実装は司令塔が書く | **重複なし。** 実体は `model-strategy.md:29-`、`delegation-policy.md:66` は明示ポインタ |
| 委託禁止領域のパス一覧 | **重複だが対処済み。** #83 で単一ソースを宣言 + CI `harness-integrity` が双方向照合 |
| `design.md` の粒度を書き切る | **重複ではない。** `planning.md:31` = ルール本体 / `model-strategy.md:27` = 往復 2 回超という診断閾値。別の内容 |
| `package.json` ライフサイクル目視 | **重複ではない。** `review-policy.md:16-28` が実体で、モード別の担保表は `mode/*.md` への索引 |
| `/clear` の扱い | **重複ではない。** `context-management.md` = コンテキスト量の運用 / `model-strategy.md:40` = モデル切替時のキャッシュ課金。別の理由 |

したがって追加の整理対象はなく、手順 4 は本チケットでは
**「走査した結果、他に無かった」ことの記録**として完了とする。
