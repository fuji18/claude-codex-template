# タスクリスト: レビュー方針を review-policy.md に一本化

Issue: #85 / design: `design.md`

## 実装

- [x] 1. `.claude/rules/lead/delegation-policy.md` 粒度表の「重要変更のレビュー」行の 4 列目をポインタに置換(design §1)
- [x] 2. `.claude/rules/lead/delegation-policy.md` の `### 重要変更のレビューは ...` 節を丸ごと削除(design §2)
- [x] 3. 削除後の空行が 1 つだけであること、`### 損益分岐` が直後に来ることを目視確認(design §2)
- [x] 4. `.claude/rules/lead/review-policy.md` の 32 行目に単一ソースの目印を追記(design §3)。33〜35 行目は無改変

## 計測と記録

- [x] 5. `wc -c .claude/rules/lead/*.md` と合計を実測(design §4)。**推定値を使わない**
- [x] 6. `docs/template-dev/CHANGELOG.md` の `## 2026-09-06` 直下に `[auto]` 項目を追記し、実測値を埋める(design §5)

## 検証

- [x] 7. `grep -rn "片方だけ直さないこと" .claude/rules/` が 0 件
- [x] 8. `grep -n "重要変更のレビューは" .claude/rules/lead/delegation-policy.md` が 0 件
- [x] 9. `grep -rln "ユーザー起動 + 課金" .claude/rules/` が `review-policy.md` の 1 件だけ
- [x] 10. `grep -n "(下記)" .claude/rules/lead/delegation-policy.md` が当該行を返さない
- [x] 11. `bash .claude/scripts/check-forbidden-paths-doc.sh` が成功
- [x] 12. `npm run lint && npm run format:check` が成功

## 振り返り(司令塔)

- 検収: `code-reviewer` 1 巡 Critical0/Major0/Minor0、`test-runner` 5 項目全パス。1 巡目で受理
- 実測: `lead/*.md` 28,854 B → 27,823 B(−1,031 B / 3.6%)、`delegation-policy.md` 10,874 B → 9,736 B
- 手順 4(他の重複の走査)は「見つからなかった」ことを `requirements.md` の表に記録して完了とした
- `.harness/decisions.jsonl` に 1 行追記済み(#85)
