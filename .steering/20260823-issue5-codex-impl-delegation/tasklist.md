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

**実装完了日**: 2026-08-23

### 計画と実績の差分

- `design.md` は設計判断を尽くしたが、**シェルの実装細部までは指定しきれなかった**。fork は往復 0 回で完了した一方、検収で Critical 1 件・Major 4 件が出た。粒度不足ではなく、bash の落とし穴(正規表現の greedy マッチ・`jq` の falsy 判定)は設計文書では捕まえられない層だという整理をした
- `.claude/template-manifest.json` への `codex-run.sh` 個別登録は **design.md の指示自体が誤り**だった。`.claude/scripts/` がディレクトリエントリとして既に `owned` を覆っており、重複でしかない。検収で指摘され削除した
- 検収で提案された `core.hooksPath = ".husky"` の等値比較は**このリポジトリでは誤り**(husky v9 が設定するのは `.husky/_`)。採用せず、「非空 + 指すディレクトリが実在」に置き換えた

### 学んだこと

- **`jq` の `//` 演算子は `false` を falsy として捨てる。** `.accepted // empty` は `"accepted": false` を「キーが無い」と同じ扱いにするため、jq 経路と sed 経路で結果が食い違う。段階4 の SessionStart 注入がこの関数を再利用するので、そこに持ち越さずに潰した
- **「フェイルクローズと宣言した層が静かにフェイルオープンする」事故が段階2 に続いて再発した。** 今回は `rec_field` の sed フォールバックが `pid` の末尾カンマを飲み込み、`kill -0 "82711,"` が常に失敗して再入防止が素通りしていた。検査を書いたら「この検査が空振りする条件」を列挙する、という段階2 の教訓は**列挙しただけでは足りず、その条件を実際に再現するテストまで要る**。design.md の V15(jq 不在時の検証)は `accept` / `set-status` しか対象にしておらず、`accepted` が JSON の最後のフィールドでカンマが付かないためこの経路を通らなかった
- 実機の Codex は初回の impl 委託で **tasklist を逐次更新し、exit 0 で完走した**。生ログ 66,347 B に対し司令塔へ返ったのは約 60 B。`codexSessionId`(`thread_id`)は実機で取得できた — §13 #6 で「取れない」と確定していたのは `resets_at` の方

### 次回への改善提案

- **jq 不在経路のテストは「クォートされていない値」「JSON の途中のフィールド」を必ず含める。** 末尾フィールドだけを見るテストは今回のバグを通す
- 段階4 で SessionStart 注入を作るとき、表示ロジックを `codex-run.sh list` に寄せる(判定規則を 2 箇所に分けない)
- **未対応で残した検収指摘**(意図的):
  - 再入防止の TOCTOU(ロックファイルを使わない check-then-act)。司令塔が逐次に呼ぶ運用では競合窓が実質存在せず、ロックを入れると stale lock という別の詰まり方を作る方が高くつく
  - `write_field` の sed 経路は括弧の対応までは検証しない(空・先頭/末尾・対象キーの残存のみ)。jq 無しで JSON を厳密に検証する手段が無いため
