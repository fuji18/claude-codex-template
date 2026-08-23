# タスクリスト: 段階4 — モード B(節約)

対象 Issue: #6 / 設計: `design.md`(このディレクトリ)

**1 タスク完了ごとに `- [x]` へ更新すること。** まとめ更新は禁止(途中停止時に引き継げなくなる)。

## 実装

- [ ] T1. `.claude/scripts/harness-mode.sh` を design §1 の全文どおり新規作成する
- [ ] T2. `chmod +x` と `git update-index --chmod=+x .claude/scripts/harness-mode.sh` を実行する(design §1)
- [ ] T3. `.claude/scripts/delegate-codex.sh` のモード読み取り 5 行を design §2 のブロックに差し替える
- [ ] T4. `.claude/scripts/codex-run.sh` の `usage()` に `pending` の説明行を足す(design §3.2)
- [ ] T5. `.claude/scripts/codex-run.sh` に `cmd_pending()` を追加する(design §3.3)
- [ ] T6. `.claude/scripts/codex-run.sh` のサブコマンド分岐に `pending` を足す(design §3.4)
- [ ] T7. `.claude/rules/mode/econ.md` を design §4.2 の全文どおり新規作成する
- [ ] T8. `.claude/rules/mode/degraded.md` を design §4.3 の全文どおり新規作成する
- [ ] T9. `.claude/hooks/session-start.sh` にモード注入ブロックを追加する(design §5.2)
- [ ] T10. `.claude/hooks/session-start.sh` に未検収取得ブロックを追加する(design §5.3)
- [ ] T11. 現在地ブロック内に `CODEX_PENDING` の差し込みを 1 行入れる(design §5.4)
- [ ] T12. 現在地ブロックの `fi` を `else` 付きに変え、startup でも未検収を出す(design §5.5)
- [ ] T13. `.claude/commands/add-feature.md` のステップ6 に econ スキップの注記を足す(design §6.1)
- [ ] T14. `.claude/commands/add-feature.md` のステップ8 に `--draft` 分岐を足す(design §6.1)
- [ ] T15. `.claude/commands/fix-issue.md` の PR 作成手順に `--draft` 分岐を足す(design §6.2)

## ドキュメント

- [ ] T16. `README.md` のディレクトリ構造(`mode` 行 / `rules/` 配下)を更新する(design §7.1)
- [ ] T17. `docs/template-dev/codex-delegation-plan.md` §11 の段階4 行を完了表記にする(design §7.2-1)
- [ ] T18. 同 §11 に段階4 の完了記録を追加する(design §7.2-2。draft PR の実機結果は placeholder)
- [ ] T19. 同 §3.4 に「実装は `codex-run.sh pending` に集約した」注記を足す(design §7.2-3)
- [ ] T20. `.harness/decisions.jsonl` に design §7.3 の 1 行を追記する(既存行は消さない)

## 検証(design §8)

- [ ] T21. V1〜V4(`harness-mode.sh` の読み取り順序と不正値)を実行し結果を記録する
- [ ] T22. V5〜V6(モード注入の出る/出ない)を実行し結果を記録する
- [ ] T23. V7〜V11(`pending` の各表示分岐)を実行し結果を記録する
- [ ] T24. V12〜V13(hook からの注入位置。startup / clear の両方)を実行し結果を記録する
- [ ] T25. V14(jq 不在時のフォールバック一致)を実行する。環境が作れなければ「実施不可」と理由を書く
- [ ] T26. V15〜V16(`bash -n` と git index の実行権限)を実行する
- [ ] T27. 検証用 record と `.harness/mode` を削除して後始末する(design §8 の「後始末(必須)」)
- [ ] T28. 変更したファイルに対して lint / フォーマットを回す(**変更したファイルのみ**。全体フォーマットは回さない)

## 司令塔が担当(実装者は行わない)

- [ ] L1. draft PR を作り、`ci.yml` が走り `claude-code-review.yml` が走らないことを Actions で確認する
- [ ] L2. L1 の結果を `docs/template-dev/codex-delegation-plan.md` §11 の placeholder に記入する
- [ ] L3. 週枠の実効寿命の測定ベースライン(`/usage` の実数)を振り返りフェーズで記録する

## 申し送り

(実装完了後に記載する)
