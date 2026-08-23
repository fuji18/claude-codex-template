# タスクリスト: 段階3 — 実装委託と終了コード契約

対象 Issue: #5 / 設計: `design.md`(このディレクトリ)

**全タスクを `[x]` にするまで作業を継続すること。** 技術的理由で不要になった場合のみ
`- [x] ~~タスク名~~ (理由: ...)` の形で残す。理由なくスキップしない。

## 1. delegate-codex.sh の改修(design.md §1)

- [x] 1-1. 終了コード定数 `EX_BLOCKED=1` / `EX_NOTREADY=5` を追加し、ヘッダーコメントの終了コード表から「段階3 で」の但し書きを外す(§1.1 / §1.8-c)
- [x] 1-2. 引数処理を更新する: `impl` を許可、`fix-ci` のメッセージを「未実装」に、`--background` のメッセージを「段階4」に、`usage()` に impl の行を追加(§1.2)
- [x] 1-3. `rec_field()` を `json_str` 群の近くに追加する(§1.4)
- [x] 1-4. `RUN_DIR` の代入を入口検査5 より前に移動する(`mkdir -p` は現状位置のまま)(§1.3)
- [x] 1-5. 入口検査5(impl 専用)を入口検査4 の直後に追加する: 5-1 target 検査 / 5-2 完成マーカー(exit 5) / 5-3 hooksPath(exit 3) / 5-4 保護ブランチ(exit 2) / 5-5 再入防止(§1.3)
- [x] 1-6. `write_record` を差し替える(`steering` / `codexSessionId` / `startedAt` / `endedAt` の追加、`pid` と `accepted` の維持)。`STARTED_AT` / `ENDED_AT` / `CODEX_SESSION_ID` を初期化する(§1.4)
- [x] 1-7. `tree_snapshot()` / `count_done()` と事前スナップショット(`TREE_BEFORE` / `HEAD_BEFORE` / `DONE_BEFORE`)を追加する(§1.5)
- [x] 1-8. `PREAMBLE` を impl / 読み取りで分け、`case "$MODE"` に impl のプロンプトを追加する(§1.6)
- [x] 1-9. `SANDBOX` 変数を導入し `codex exec` の `--sandbox` を切り替える(§1.7)
- [x] 1-10. `codex exec` 直後に `CODEX_SESSION_ID` と `ENDED_AT` を設定する(§1.8-a)
- [x] 1-11. impl の出口判定(判定行の抽出 → 判断待ち/失敗の分岐 → 成果実在確認 → 逐次更新なしの警告)を追加する。**順序を守ること**(§1.8-b)

## 2. codex-run.sh の新規作成(design.md §2)

- [x] 2-1. `.claude/scripts/codex-run.sh` を作成する(ヘッダーコメント・`cd` toplevel・`rec_field` のコピー)
- [x] 2-2. `list` / `show` を実装する(未検収の抽出、プロセス不在の表示、別ブランチの注記)
- [x] 2-3. `write_field()`(jq / sed の 2 経路 + 末尾カンマの引数 + バックアップと妥当性確認)を実装する
- [x] 2-4. `accept` / `set-status`(語彙の限定)を実装する
- [x] 2-5. `chmod +x` と `git update-index --chmod=+x` を実行する

## 3. コマンド 3 本の改訂(design.md §3)

- [x] 3-1. `/add-feature` ステップ5 を差し替える(終了コード表・fork フォールバック表・中断時の手順・禁止行為)
- [x] 3-2. `/add-feature` ステップ6 に `codex-run.sh accept` の項目を追加する
- [x] 3-3. `/next-ticket` の担当表と箇条書きを更新する
- [x] 3-4. `/fix-issue` ステップ4 を委託経路に更新し、重複を add-feature への参照に寄せる

## 4. マニフェストとドキュメント(design.md §4)

- [x] 4-1. `.claude/template-manifest.json` に `codex-run.sh` を登録する
- [x] 4-2. `README.md` の `scripts/` 説明に 1 行追記する
- [x] 4-3. `codex-delegation-plan.md` の §11 段階表・箇条書き・§3.2 の callout を更新する
- [x] 4-4. `codex-harness.html` の「impl は未実装」系の記述を実態に合わせる(3 箇所)

## 5. 検証(design.md §5)

- [x] 5-1. スクラッチパッドに `codex` スタブと検証スクリプトを用意する
- [x] 5-2. V1〜V12(delegate-codex.sh)を実行し、結果表を作る
- [x] 5-3. V13〜V15(codex-run.sh / jq 不在)を実行する
- [x] 5-4. `explore` / `review` の非回帰を確認する
- [x] 5-5. `V12` で変更した `core.hooksPath` を復元したことを確認する
- [x] 5-6. 変更したファイルを対象に lint・フォーマット・型チェックを回す(shell はフォーマット対象外。Markdown / JSON は prettier の対象)

## 申し送り事項

(実装完了後、振り返りモードで記載する)
