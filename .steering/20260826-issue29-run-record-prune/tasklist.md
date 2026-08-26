# タスクリスト: Issue #29 run record のローテーション(prune)

## 実装

- [x] `codex-run.sh` のヘッダ・`usage()` に `prune` を追記する(design §1)
- [x] `codex-run.sh` に `cmd_prune()` を挿入する(design §2)
- [x] `codex-run.sh` の dispatch に `prune)` を足す(design §3)
- [x] `delegate-codex.sh` に run record 件数の警告ブロックを挿入する(design §4.1)
- [x] `delegate-codex.sh` の `forbidden_snapshot()` 空振り条件コメントを差し替える(design §4.2)
- [x] `codex-delegation-plan.md` に §12.8 を新設する(design §5)

## 検証

- [x] `bash -n` が両スクリプトで通る(design §6-1 / §6-9)
- [x] scratchpad の使い捨てリポジトリで fixture を作り、§6 の確認項目 2〜7 を通す
- [x] jq 無し経路(sed 経路)でも同じ判定になることを確認する(§6-8)
- [x] 実リポジトリの `.harness/codex-runs/` と `git status` が汚れていないことを確認する(§6-10)
- [x] `verification.md` に結果を書く
- [x] `/check`(lint / 型 / format / test)を通す(変更対象は shell/md のみ。JS/TS 影響なしを確認のうえ `prettier --check` で md の整形のみ実施)

## 検収指摘の反映(code-reviewer Minor 3 / 採用 1)

- [x] `cmd_prune()` の pid 判定に非数値ガードを足す(design §7)
- [x] Minor 2 / Minor 3 の不採用判断を `verification.md` に記録する(design §7)
- [x] `bash -n` と該当ケースの再検証、`/check` を通す
