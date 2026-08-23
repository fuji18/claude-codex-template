# タスクリスト: 段階4 — モード B(節約)

対象 Issue: #6 / 設計: `design.md`(このディレクトリ)

**1 タスク完了ごとに `- [x]` へ更新すること。** まとめ更新は禁止(途中停止時に引き継げなくなる)。

## 実装

- [x] T1. `.claude/scripts/harness-mode.sh` を design §1 の全文どおり新規作成する
- [x] T2. `chmod +x .claude/scripts/harness-mode.sh` を実行する(**`git update-index` は実行しない** — sandbox では `.git` が読み取り専用。index への反映は L4 で司令塔が行う。design §1 の但し書き)
- [x] T3. `.claude/scripts/delegate-codex.sh` のモード読み取り 5 行を design §2 のブロックに差し替える
- [x] T4. `.claude/scripts/codex-run.sh` の `usage()` に `pending` の説明行を足す(design §3.2)
- [x] T5. `.claude/scripts/codex-run.sh` に `cmd_pending()` を追加する(design §3.3)
- [x] T6. `.claude/scripts/codex-run.sh` のサブコマンド分岐に `pending` を足す(design §3.4)
- [x] T7. `.claude/rules/mode/econ.md` を design §4.2 の全文どおり新規作成する
- [x] T8. `.claude/rules/mode/degraded.md` を design §4.3 の全文どおり新規作成する
- [x] T9. `.claude/hooks/session-start.sh` にモード注入ブロックを追加する(design §5.2)
- [x] T10. `.claude/hooks/session-start.sh` に未検収取得ブロックを追加する(design §5.3)
- [x] T11. 現在地ブロック内に `CODEX_PENDING` の差し込みを 1 行入れる(design §5.4)
- [x] T12. 現在地ブロックの `fi` を `else` 付きに変え、startup でも未検収を出す(design §5.5)
- [x] T13. `.claude/commands/add-feature.md` のステップ6 に econ スキップの注記を足す(design §6.1)
- [x] T14. `.claude/commands/add-feature.md` のステップ8 に `--draft` 分岐を足す(design §6.1)
- [x] T15. `.claude/commands/fix-issue.md` の PR 作成手順に `--draft` 分岐を足す(design §6.2)

## ドキュメント

- [x] T16. `README.md` のディレクトリ構造(`mode` 行 / `rules/` 配下)を更新する(design §7.1)
- [x] T17. `docs/template-dev/codex-delegation-plan.md` §11 の段階4 行を完了表記にする(design §7.2-1)
- [x] T18. 同 §11 に段階4 の完了記録を追加する(design §7.2-2。draft PR の実機結果は placeholder)
- [x] T19. 同 §3.4 に「実装は `codex-run.sh pending` に集約した」注記を足す(design §7.2-3)
- [x] T19b. 同 §9(リスクと注意点)に「`.git` は sandbox で読み取り専用 = index 操作は委託不可」を追加する(design §7.2-4)
- [x] T20. `.harness/decisions.jsonl` に design §7.3 の 1 行を追記する(既存行は消さない)

## 検証(design §8)

- [x] T21. V1〜V4(`harness-mode.sh` の読み取り順序と不正値)を実行し結果を記録する
- [x] T22. V5〜V6(モード注入の出る/出ない)を実行し結果を記録する
- [x] T23. V7〜V11(`pending` の各表示分岐)を実行し結果を記録する (V7 は既存の未検収 record 2 件を表示。V8〜V11 の分岐は検証用 record で確認)
- [x] T24. V12〜V13(hook からの注入位置。startup / clear の両方)を実行し結果を記録する
- [x] T25. V14(jq 不在時のフォールバック一致)を実行する。環境が作れなければ「実施不可」と理由を書く
- [x] T26. V15〜V16(`bash -n` と git index の実行権限)を実行する (V15 pass。V16 は untracked のため司令塔 L4 で 100755 を反映・確認)
- [x] T27. 検証用 record と `.harness/mode` を削除して後始末する(design §8 の「後始末(必須)」)
- [x] T28. 変更したファイルに対して lint / フォーマットを回す(**変更したファイルのみ**。全体フォーマットは回さない)

## 司令塔が担当(実装者は行わない)

- [x] L1. draft PR を作り、`ci.yml` が走り `claude-code-review.yml` が走らないことを Actions で確認する(PR #11: CI=success / Claude Code Review=skipped)
- [x] L2. L1 の結果を `docs/template-dev/codex-delegation-plan.md` §11 に記入した
- [ ] L3. 週枠の実効寿命の測定ベースライン(`/usage` の実数)を振り返りフェーズで記録する
- [x] L4. コミット時に `git update-index --chmod=+x` を実行し index が `100755` であることを確認した

## 申し送り

実装完了日: 2026-08-23

### 計画と実績の差分

- **1 回目の委託が `exit 2` で停止した(設計起因)。** design.md が T2 に `git update-index --chmod=+x` を含めていたが、Codex の `workspace-write` sandbox では **`.git` が読み取り専用**で必ず失敗する。design を修正し(index 反映は司令塔の L4 へ)再委託して完走。**`.git` を書き換えるタスクは委託対象外**という一般則を `codex-delegation-plan.md` §9 に記録した
- **2 回目の委託は全タスクを完遂したが、委託スクリプト自身が死んだ。** Codex が T3 で `delegate-codex.sh` を編集した結果、**実行中の親 bash が逐次読み込みのオフセットを崩して構文エラーで落ちた**。成果物は無傷だが run record が `running` のまま孤児化し、`set-status` で手当てが要った。§9 に未対処のリスクとして記録済み(回避策の候補も併記)
- 検収の往復は **1 回**(Critical 0 / Major 1 / Minor 4)。Major は「`summary` に改行が入ると `pending` の出力構造が壊れる」もので、`delegate-codex.sh` が成果実在確認の警告を改行込みで追記する実在の経路だった

### 学んだこと

- **委託先の環境制約を design.md に書き切れていないと、実装ではなく環境で止まる。** 段階3 は「Codex が何をするか」は詳細に決めていたが「Codex が**できないこと**」(`.git` 書き込み・ネットワーク)を実装者向けに明記していなかった。design §9「やらないこと」に環境制約を書く欄を常設するのが再発防止になる
- **ハーネス自身を委託対象にすると、委託経路が自分の足を撃つ。** テンプレート開発では常態なので、`delegate-codex.sh` の自己編集耐性は段階6 までに対処すべき

### 次回への改善提案

- `delegate-codex.sh` の自己編集耐性(本体を関数で包む / 一時コピーを `exec`)を段階6 までに入れる
- `code-reviewer` の Minor 指摘のうち未対処のもの:
  - `date -u -d` は GNU date 専用(非 GNU 環境では「7 日以上前」判定が静かに無効化される)。コメントで明示するに留めた
  - `session-start.sh` が `harness-mode.sh` を 2 回起動している(stderr 捕捉のため。設計どおり・実害なし)
  - `summary` は Codex の自由記述がサニタイズなしで次セッションに注入される(段階3 の設計の帰結。本チケット固有の新規リスクではない)
