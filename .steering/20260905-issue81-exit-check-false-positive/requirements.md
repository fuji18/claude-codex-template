# 要求: 出口検査の誤爆を止める(explore / review の並行が impl を failed にする)

- Issue: #81(P1 / `delegate:codex` なし = `.claude/scripts/` は委託禁止領域)
- 根拠: Codex 併用ハーネス実装レビュー(2026-09-04)B1 / C3、対応順序 2

## 解く問題

### B1: read-only の並行委託が impl の出口検査を誤爆させる

1. `.harness/codex-runs/` が `FORBIDDEN_PATHS` に含まれる(委託先が自分の結果を `accepted` に書き換えるのを防ぐため。妥当)
2. `forbidden_files()` は `find .harness/codex-runs -type f` で**全 run record を列挙**し、除外するのは今回の委託自身の 3 ファイル(`$REC` / `$LOG` / `$LAST`)だけ
3. `delegation-policy.md` は「read-only の explore / review はこの検査(5-5)を通らず並行できる」と明記しており、**これは意図された運用**
4. impl の実行中に explore / review を 1 本起動すると、そちらが新しい `.json` / `.log` / `.last.txt` を作り、`.log` は実行中ずっと成長する
5. impl の `FORBIDDEN_AFTER` が `FORBIDDEN_BEFORE` と一致しなくなり、**正常に完了していても** `status=failed` / `exit 2` で「委託禁止領域が変更されました」というセキュリティ違反の見た目で返る

同じことは impl 実行中に人間が `codex-run.sh accept <id>` / `set-status` / `prune` を叩いた場合にも起きる。

**実害は失われた作業と枠だけではない。** この層は「鳴ったら本物」であることに価値がある。運用上ありうる操作で偽陽性が出ると、次に本物が鳴ったときに無視される。

### C3: 走査対象が単調増加する(同じ場所の副次的な問題)

`.harness/codex-runs/` は 1 委託につき 3 ファイル増え、自動削除しない設計(#29 / §12.8)。出口検査は impl 1 回につきこのディレクトリ全体を 2 回ハッシュする。#65 でプロセス起動は定数化されたが、**I/O とハッシュ計算はファイル数に比例**する(`.log` は数百 KB になりうる)。B1 の修正で同時に縮む。

## 受け入れ条件(Issue 転記)

- [ ] impl 委託の実行中に explore を 1 本起動しても、impl が `completed` / `exit 0` で終わる(再現テストで確認する)
- [ ] impl 委託の実行中に `codex-run.sh accept <別 id>` を叩いても、impl が `completed` で終わる
- [ ] 委託先が既存 record の `accepted` を `true` に書き換えた場合は、**引き続き** `failed` / `exit 2` になる(守りたい性質が消えていないこと)
- [ ] `delegation-policy.md` の並行数の記述が修正後の挙動と一致している
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み

## スコープ外

- explore / review も 1 本に制限すること(read-only の並行は意図された運用)
- run record の自動削除(#29 / §12.8 の判断を覆さない)
- `.harness/codex-runs/` を `FORBIDDEN_PATHS` から外すこと(委託先による書き換え禁止は残す)
