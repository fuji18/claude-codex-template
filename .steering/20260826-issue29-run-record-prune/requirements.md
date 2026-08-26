# 要件: Issue #29 run record のローテーションを整備する

## 背景

`.harness/codex-runs/` には委託 1 本につき 3 ファイル(`<id>.json` / `<id>.log` / `<id>.last.txt`)が積まれるが、削除する機構が無い。#20 でこのディレクトリを出口検査の対象に加えたため、`forbidden_snapshot()` が配下の全ファイルを前後 2 回ハッシュする。run 数に比例して委託ごとのコストが増える。

## スコープ

1. `codex-run.sh` に `prune` サブコマンドを追加する(`--dry-run` / `--keep N` / `--include-unaccepted`)
2. 未検収(`accepted != true`)・実行中(`status=running` かつ pid 生存)・直近 N 本を既定で残す
3. 削除は `<id>.json` / `<id>.log` / `<id>.last.txt` の 3 点セット単位
4. `delegate-codex.sh` の起動時に件数が閾値を超えていたら **警告だけ**出す(自動削除しない)
5. `docs/template-dev/codex-delegation-plan.md` に運用を追記し、`forbidden_snapshot()` の「空振り条件」コメントを更新する

## スコープ外

- `forbidden_snapshot()` 側の絞り込み(#20 の設計判断を覆すため)
- `.harness/decisions.jsonl` の圧縮・削除(追記のみの永続ログ)
- 自動削除・cron 等の定期実行

## 受け入れ条件(Issue #29 より)

- [ ] `codex-run.sh prune --dry-run` が削除候補を一覧表示し、実際には何も消さない
- [ ] `codex-run.sh prune` が 3 点セット単位で削除する(片方だけ残らない)
- [ ] `accepted: false` の record が既定で残る
- [ ] `status=running` かつプロセス生存中の record が残る
- [ ] 削除後も `codex-run.sh list` / `pending` / `show` が正常に動く
- [ ] 運用が `docs/template-dev/codex-delegation-plan.md` に記載されている
