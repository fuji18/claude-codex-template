# 要求定義: レート上限の構造化識別子マッチを行単位に限定する(Issue #62)

## 背景

`delegate-codex.sh` の失敗時(`CODEX_EXIT != 0`)分岐で、レート上限の一次判定に使う
`RATE_ID_RE`(`rate_limit_reached|usage_limit_reached|credits_depleted`)が
**ログ全文**に当てられている(`:1394`)。

`$LOG` は `codex exec --json` の全イベント(+ `2>&1` で codex 自身の stderr)で、
**委託先が読んだファイルの引用を含む**。このリポジトリ自体が `delegate-codex.sh` 本体・
`docs/template-dev/codex-delegation-plan.md`・`.steering/20260820-codex-minimal-harness/*`
にこれらの識別子を含むため、**それらを読んだ委託がタスク起因で失敗すると `exit 4`
(レート上限 = 待て)に誤分類され**、本来通るべき `exit 2` の原因分析・回復手順に入れない。

成功時(`exit 0`)に判定しない修正は既に入っている。**失敗時の同型が残っている。**

## 要求

| ID | 要求 |
| --- | --- |
| R1 | 構造化識別子(`RATE_ID_RE`)のマッチ範囲を、**ログ全文ではなく「レート上限を運びうるイベント行」に限定する** |
| R2 | 限定の根拠は**推測ではなく実測した実イベント形式**に置く(codex-cli v0.149.0) |
| R3 | 本物のレート上限イベント行では従来どおり `exit 4` / `status=rate-limited` になる |
| R4 | 識別子を含むファイルを読んだだけの失敗委託は `exit 2` / `status=failed` になる |
| R5 | 誤判定しても run record の生エラー(`ERR3`)で人間が判定できる設計を維持する(この検査は分岐の補助であり唯一の根拠ではない) |

## スコープ外

- 自然言語のレート上限文言判定(`RATE_TEXT_RE`)の変更 — 既に `ERR_ONLY`(末尾 20 行のうち error/fail 行)に限定済みで、本チケットは構造化識別子側だけを扱う
- `AUTH_RE` の適用範囲 — 既に `ERR_ONLY` 限定
- `RESET_AT` の抽出範囲 — 上限判定が成立した後にしか読まれない付随情報で、判定の分岐には影響しない
- `exit 4` の意味づけ・待機ロジックの変更

## 受け入れ条件

- [ ] `rate_limit_reached` を本文に含むファイルを読んだだけで失敗した委託が `exit 2`(実測)
- [ ] 本物のレート上限イベント行では `exit 4`(サンプル行を流して実測)
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み
