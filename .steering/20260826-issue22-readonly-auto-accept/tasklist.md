# タスクリスト: explore / review の run record を auto-accept する(Issue #22)

design.md の節番号に対応。上から順に実施する。

- [x] 1. `write_record` に第 5 引数 `accepted` を足す(design.md §1)
  - [x] コメント行に `$5=accepted(true/false。既定 false)` を追記
  - [x] 関数先頭に `local _accepted` + `case "${5:-false}"` の正規化を追加
  - [x] ヒアドキュメントの `"accepted": false` を `"accepted": $_accepted` に変更(位置・カンマ無しは現状維持)
- [x] 2. `completed` の呼び出しをモードで出し分ける(design.md §2)
  - [x] `ACCEPT_ON_COMPLETE` を `impl` の否定で決める分岐を追加(理由コメント込み)
  - [x] `write_record "completed" "$SUMMARY" "" "" "$ACCEPT_ON_COMPLETE"` に変更
- [x] 3. 他 8 箇所の `write_record` 呼び出しを変更していないことを確認する(design.md §3)
- [x] 4. 検証を実行し `.steering/20260826-issue22-readonly-auto-accept/verification.md` に記録する(design.md §4)
  - [x] `bash -n` の構文チェック
  - [x] スタブ Codex でシナリオ 1〜4
  - [x] record の JSON 妥当性と `accepted` が最終フィールドであることの確認
  - [x] 検証で作った record の後片付け
- [x] 5. `docs/template-dev/codex-delegation-plan.md` に 1 文追記する(design.md §5)
- [x] 6. 品質チェック(`npm run lint` / `npm run typecheck` / `npm run format:check`)を通す

## 振り返り(モード3)

- 往復 0 回で完走。`design.md` に変更行・コメント文言・検証手順まで書き切ったため、実装者側の設計判断はゼロだった
- 検収は Critical 0 / Major 0 / Minor 2。Minor 1(design.md の呼び出し箇所数の内訳)は**レビュー側の数え違い**で、実測は合計 9 箇所・`failed` 4 箇所。design.md の内訳(`failed` 5)の方が誤っていたため、そちらを訂正した
- 実装者が `verification.md` で報告した相違点(`CODEX_DELEGATE_ACK_SECRETS=1` が必要だった)は既存の入口検査の挙動であり、今回の変更とは無関係。ただし**スタブ検証の手順として恒常的に必要**なので、次に同種の検証を設計するときは design.md の検証手順に最初から含める
- 申し送り: 本チケットは「発生源を止める」だけ。既に溜まっている未検収の explore / review レコードは残るため、必要なら `codex-run.sh accept` で個別に片付ける(自動削除・件数上限は Issue #29 の範囲)
