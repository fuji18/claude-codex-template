# タスクリスト: Claude レビューの skip を可視化する(Issue #12)

## 実装

- [x] T1. `.github/workflows/claude-code-review.yml` に `Notify review skipped` ステップを追加する(design.md 変更 1)
- [x] T2. `.github/workflows/claude.yml` に `Notify mention skipped` ステップを追加する(design.md 変更 2)
- [x] T3. `README.md` Step 0 の項番 2 にサブ項目を 1 行追加する(design.md 変更 3)
- [x] T4. `docs/template-dev/codex-delegation-plan.md` §2.6 に可視化の追記をする(design.md 変更 4)

## 検証(実装者)

- [x] V1. 両 YAML が YAML として妥当であることを確認する
- [x] V2. `npm run format` を実行し、`npm run format:check` が通ることを確認する
- [x] V3. `git diff` で既存ステップ・既存ガードに変更が入っていないことを確認する

## 検証(司令塔・PR 作成後)

- [x] V4. 実機で run の annotation・Summary・ジョブ結論(`success`)の 3 点を確認した(PR #13 / run 32725845245)
  - `Run Claude Code Review` = `skipped`(ガードは無変更のまま効いている)
  - `Notify review skipped` = `success`
  - annotation = `[warning] Claude レビュー未実行`(メッセージも期待どおり。全角文字・`::` の混入で壊れていない)
  - **ジョブ結論 = `success`**(赤くなっていない)
  - Summary の本文は GitHub の API が公開していないため run ページでの目視が要る。
    ステップが `success` で終わっており、同じスクリプトのローカル実行で 310 バイトの
    期待どおりの内容が書き出されることは確認済み

## 申し送り

実装完了日: 2026-08-24

### 計画と実績の差分

- **委託は 1 回で完走(`exit 0` / 変更 5 ファイル / tasklist 7/8)。** 往復ゼロ。
  段階4 の申し送り「委託先の環境制約を design.md に書き切る」を受けて、
  今回は `.git` を触るタスクもネットワークを要するタスクも計画に含めなかったことが効いた
- **委託の入口で `exit 2`(機密ファイル検出)を 1 回踏んだ。** 該当は `.claude/settings.local.json`。
  中身は permission allowlist と `enabledMcpjsonServers` のみで機密ではなかったため、
  内容を確認のうえ `CODEX_DELEGATE_ACK_SECRETS=1` で承認して再実行した。
  **このファイルは gitignore 済みだが常時ワークツリーに存在する**ため、
  委託のたびに同じ承認を求められる。段階6 で「確認済みパスの許可リスト」を検討する価値がある
- 検収は **往復 0 回**(Critical 0 / Major 0 / Minor 0)。test-runner も全項目 pass・自動修正なし

### 検証で工夫した点

- **YAML のリテラルブロックから `run:` の本文を抜き出し、`GITHUB_STEP_SUMMARY` を一時ファイルに
  差し替えてローカルの bash で実行した。** この変更の唯一の技術的リスクは
  「YAML のインデント除去後にヒアドキュメントの終端 `EOF` が列 0 になるか」であり、
  静的な目視や YAML パースでは検証できない。実際に走らせて exit 0 と出力内容を確認したことで、
  実機(GitHub Actions)での確認前にリスクをほぼ潰せた
- 受け入れ条件の「ジョブが赤くならない」も、ステップが非ゼロ終了しないことをこの実行で確認済み

### 残課題

- **V4(実機確認)は PR 作成後に司令塔が行う。** この PR を**非 draft**で開くと
  `claude-code-review.yml` が起動し、シークレット未登録のため今回追加した通知ステップが走る
  = **この PR 自体が実機確認の機会**になる(Issue #12 の受け入れ条件どおり)
- **可視化は入ったが、シークレットは依然未登録。** 「出口の無いキュー」問題の根治は
  人間が `CLAUDE_CODE_OAUTH_TOKEN` を Actions シークレットに登録すること。
  本チケットのスコープ外(誤読を run 上で否定できるようにしただけ)

### 次回への改善提案

- `delegate-codex.sh` の機密検出に「確認済みパスの許可リスト」を入れる(段階6 / Issue #8)
- 段階4 の申し送りに挙がった `delegate-codex.sh` の自己編集耐性は**今回も未対処**。
  今回はハーネス本体を編集しなかったため踏まなかっただけで、リスクは残っている
