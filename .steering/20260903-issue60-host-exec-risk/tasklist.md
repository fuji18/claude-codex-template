# タスクリスト: Issue #60 検収時のホスト実行

設計は `design.md` に書き切ってある。**節番号が対応する。**

## ドキュメント(明文化)

- [x] 1. `docs/template-dev/codex-delegation-plan.md` §9 に「検収時のホスト実行は塞げない(受容する判断)」を追記(design §1)
- [x] 2. `.claude/rules/lead/review-policy.md` の三層表の直後に「`/check` の前に `package.json` を目視」+ モード別担保表を追記(design §2-1)
- [x] 3. `.claude/rules/lead/review-policy.md` の `/code-review ultra` の項目を D-1 の結論に差し替え(design §2-2)
- [x] 4. `.claude/rules/lead/delegation-policy.md` の粒度表「重要変更のレビュー」行の判定基準セルを差し替え(design §3-1)
- [x] 5. `.claude/rules/lead/delegation-policy.md` に D-1 の結論の節を追記(design §3-2)
- [x] 6. `.claude/rules/mode/econ.md`(モード B)の司令塔の作法に項目を挿入し、以降の番号を繰り下げ(design §4)
- [x] 7. `.claude/rules/mode/degraded.md`(モード C)の手順 1 の説明文に D4 を追加(design §5-1)
- [x] 8. `.claude/rules/mode/degraded.md` の復帰検収に目視手順を挿入し、以降の番号を繰り下げ(design §5-2)
- [x] 9. `.claude/agents/code-reviewer.md` のチェック観点 1 にサブ項目を追加(design §6)

## 機械化(警告層)

- [x] 10. `.claude/scripts/delegate-codex.sh` に `lifecycle_snapshot()` を追加(design §7-1)
- [x] 11. `.claude/scripts/delegate-codex.sh` の事前スナップショットに `LIFECYCLE_BEFORE` を追加(design §7-2)
- [x] 12. `.claude/scripts/delegate-codex.sh` の出口検査に警告ブロックを追加(design §7-3)
- [x] 13. `.claude/scripts/check-guard-integrity.sh` に D4 を追加(design §8)

## 記録

- [x] 14. `docs/template-dev/CHANGELOG.md` に `## 2026-09-03` の節を追記(design §9)

## 検証

- [x] 15. design §10 の 1〜5 を実測し、`verification.md` に出力を貼る(推測で書かない)

## 検収 1 巡目の指摘対応(design §12)

- [x] 16. `docs/template-dev/codex-delegation-plan.md` §2.3 の「Claude 復帰時の手順」6 項目リストを、`degraded.md` を単一ソースとする文に置き換える(design §12 / Minor 1)
- [x] 17. `check-guard-integrity.sh` の D4 コメント末尾に、git log 重複が意図的である旨の 2 行を足す(design §12 / Minor 3)。**D3 は触らない**
- [x] 18. `docs/template-dev/CHANGELOG.md` の 2026-09-03 節に、§2.3 の単一ソース化を 1 項目追記する
- [x] 19. `verification.md` に 2 巡目の実測(`bash -n` / `check-guard-integrity.sh` 引数なし・degraded の再実行)を追記する
