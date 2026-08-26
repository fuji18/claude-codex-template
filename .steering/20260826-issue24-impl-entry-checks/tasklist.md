# タスクリスト: Issue #24 impl 入口検査の穴を塞ぐ

## 実装

- [x] `delegate-codex.sh` 5-1 に `.steering/` prefix 検査(`case` ブロック)を挿入する(design §1.2)
- [x] `delegate-codex.sh` 5-5 のブロックを mode=impl 判定へ差し替える(design §2.2)
- [x] `RUN_ID` 直前のコメントを差し替える(design §2.3)
- [x] `.claude/rules/lead/delegation-policy.md` の「並行数は 1 本まで」行を差し替える(design §3.1)
- [x] `docs/template-dev/codex-delegation-plan.md` §12 の入口検査表 5-1 行と 5-5 段落を直す(design §3.2)

## 検証

- [x] `bash -n .claude/scripts/delegate-codex.sh` が通る(design §4.1)
- [x] 5-1 の 7 ケースが期待どおり(design §4.2)
- [x] 5-5 の 4 ケースが期待どおり(jq 経路 / sed 経路の両方)(design §4.3)
- [x] スタブ record を `.harness/codex-runs/` から削除し、`git status` が汚れていないことを確認する
- [x] `verification.md` に結果を書く
- [x] `/check`(typecheck / format / lint / test)を通す(design §4.4)

## 検収指摘の反映(code-reviewer Major 1 / Minor 3)

- [x] `codex-delegation-plan.md` §3.2 の「再入可能にする」原則行を mode=impl 判定へ更新する(Major)
- [x] 5-5 のコメントに pid 再利用による誤検知の条件を明記する(Minor)
- [x] `.steering/*/` のネスト許容は仕様のままとし、判断を `verification.md` に記録する(Minor)
- [x] `verification.md` の宙に浮いた参照を直し、検収指摘の対応表を追記する
- [x] `/check` を通す
