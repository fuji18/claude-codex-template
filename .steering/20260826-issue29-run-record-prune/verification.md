# 検証記録: Issue #29 run record のローテーション(prune)

検証はすべて scratchpad に作った使い捨て git リポジトリ(`.../scratchpad/prune-test`)で実施した。実リポジトリの `.harness/codex-runs/` は一切触っていない。

## 1. 構文チェック

- `bash -n .claude/scripts/codex-run.sh` → OK
- `bash -n .claude/scripts/delegate-codex.sh` → OK

## 2. `prune --dry-run --keep 0`(削除されないこと)

fixture 4 件(§6 の表どおり: 000001=completed/true, 000002=completed/false, 000003=running/pid生存, 000004=completed/true)で実行。

- 出力: `000004` `000001` を削除候補、`000003` は「実行中」、`000002` は「未検収」として残す表示
- 実行前後で `.json` の件数は 4 のまま変化なし(`before=4 after=4`)

## 3. `prune --keep 0`(実削除)

同じ fixture で実行 → `削除: 2 件`。削除対象(000001, 000004)は `.json` / `.log` / `.last.txt` の 3 点セットすべてが消え、孤立ファイルは残らないことを `ls` で確認。

## 4. 未検収(accepted=false)の扱い

- 既定(`--include-unaccepted` 無し)では常に残る(上記 2・3 で確認済み)
- `--include-unaccepted --keep 0` を付けると削除候補/削除対象になることを確認(`削除候補: 20260101-000002-1 (... accepted=false)` → 実行後 `削除: 1 件`)

## 5. 実行中(status=running かつ pid 生存)

`--include-unaccepted --keep 0` を付けても常に残ることを確認(pid をテスト実行シェル自身の `$$` にして `kill -0` を通した状態で検証)。

## 6. 削除後の他コマンドの正常終了

削除後に以下がいずれもエラーなく完了:

- `list`(未検収なしのメッセージ、または残存 record の一覧)
- `list --all`
- `pending`
- `show <残った id>`

## 7. オプションのエラーハンドリング

- `prune --keep abc` → `codex-run: --keep には 0 以上の整数を指定してください: abc` / exit 1
- `prune --bogus` → 不明なオプションのメッセージ + usage 出力 / exit 2

## 8. jq 無し経路(sed 経路)

`jq` を含まない最小 PATH(`bash / sh / git / find / sort / head / cat / rm / mkdir / printf / kill / sed / cp / mv / wc / tr / date / grep / xargs / env` のみをシンボリックリンク)で `prune --dry-run --keep 0` と `prune --keep 0` を再実行。jq ありのときと同じ判定(000001 削除・000002 未検収で残す・000003 実行中で残す)になることを確認。

## 9. `bash -n` delegate-codex.sh

再掲(1 節参照)。§4 の警告ブロック・§4.2 のコメント差し替え後も構文エラーなし。

## 10. 実リポジトリの汚染確認

検証後 `rm -rf` で scratchpad の使い捨てリポジトリを削除。実リポジトリの `git status --short` は本タスクで変更した 3 ファイル(`codex-run.sh` / `delegate-codex.sh` / `codex-delegation-plan.md`)と新規 `.steering/20260826-issue29-run-record-prune/` のみで、`.harness/codex-runs/` に汚染は無い。

## 11. 検収指摘の反映(design §7)

### 11.1 採用: 非数値 pid のガード(Minor 1)

`cmd_prune()` の `status=running` 判定ブロックを design §7.1 のとおり差し替えた(`_pid` を数字以外なら空文字に正規化し、`_pid` が空 or `kill -0` 成立なら「実行中かもしれない」側に倒して残す)。

再検証:

- `bash -n .claude/scripts/codex-run.sh` → OK
- scratchpad に fixture `20260101-000005-1`(status=running, pid=nonnumeric-abc, accepted=true)を追加し、`prune --include-unaccepted --keep 0` を実行 → `残す: 20260101-000005-1 (実行中(pid=不明))` として保護され、削除対象に入らないことを確認。既存の pid 生存ケース(000003)・pid 数値だが死んでいるケースの挙動には変化なし。

### 11.2 不採用(記録のみ)

- **Minor 2(`rec_field` の sed 経路が 1 行 1 キー形式に依存)**: `write_record` 以外が record を書かない前提は既存 5 サブコマンド(`list` / `list --all` / `pending` / `show` / `set-status`)と共通で、今回の `prune` が新たに持ち込んだ依存ではない。かつ形式が食い違って値が読めなかった場合は `_accepted != "true"` 側に転び「未検収として保護」される(安全側に倒れる)。design どおり不採用とし、対応は行わない
- **Minor 3(`find | wc -l` が pipefail で非ゼロを拾いうる)**: 該当箇所は `delegate-codex.sh` の警告ブロックで `REC_COUNT="$(find ... | wc -l | tr -d ' ')"` という**代入の右辺**であり、スクリプトは `-e` を使っていないため `pipefail` で非ゼロが返っても代入文自体は失敗として扱われず後続処理が続く。この終了ステータスを分岐で見ている箇所も無いため実害は無い。design どおり不採用とし、対応は行わない
