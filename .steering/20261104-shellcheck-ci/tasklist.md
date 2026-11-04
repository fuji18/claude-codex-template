# tasklist: shellcheck を CI の機械的ゲートに加える

<!-- main-edit-ok -->
<!-- `.github/workflows/` `.claude/scripts/` `.claude/hooks/` `.husky/` はいずれも委託禁止領域。
     司令塔が直接書く。 -->

## 準備

- [x] shellcheck を入手してベースラインを測る(手元の devcontainer イメージに 0.9.0 を入れて固める)
- [x] 深刻度の線を決める(`--severity=warning`。note 20 件は意図した書き方・誤検知寄り)

## 実装

- [x] `ci.yml` の `harness-integrity` 末尾に ShellCheck ステップを足す(`-x -P SCRIPTDIR --severity=warning`)
- [x] ツールが無いとき・対象が空のときは `exit 1`(黙って通さない)
- [x] SC2164 ×8 を直す(hook は `|| exit 0`、ルート移動は `|| true`、テストは `|| exit 1`)
- [x] SC2034 ×1 を直す(`autopilot-preflight.sh` の未使用 `OPEN` を削除)
- [x] SC2148 ×2 を直す(`.husky/*` の先頭に `# shellcheck shell=sh`)

## 文書

- [x] `docs/template-dev/CHANGELOG.md` に `## 2026-11-04` を起こして `[manual]` で 1 項目

## 検証

- [x] `ci.yml` と同じコマンドで `exit 0`(追跡下 30 ファイル / 11 件 → 0 件)
- [x] `bash -n`(`.claude/scripts/*.sh` / `.claude/hooks/*.sh` / `.husky/*`)
- [x] `check-guard-integrity.sh` / `check-forbidden-paths-doc.sh` / `check-manifest-coverage.sh`(全て exit 0)
- [x] `test-sync-template.sh` / `test-route.sh`(all checks passed)
- [x] `harness-mode.sh`(`normal` / exit 0)・SessionStart hook(exit 0 / 394 行を注入)
- [x] `20261103-trusted-bots-union` の検証スイート 16 件(全て合格のまま)
- [x] `prettier --check`(`ci.yml` / `.claude/scripts/` / `.claude/hooks/` / `.husky/`)
- [x] git の記録モードが変わっていないこと(`git diff --summary` が空)

## 仕上げ

- [x] コミットして PR #113 を更新する(マージはしない)

## 申し送り

- **ローカルには shellcheck が無いまま。** ゲートは CI だけにある。手元で先に見たいなら
  devcontainer に入れる(`.devcontainer/post_create.sh` か Dockerfile)のが素直だが、
  **devcontainer の変更は隔離の境界に触る**ので別途判断が必要
- `.husky/*` の directive は `# shellcheck shell=sh  # husky は…` の形で、同じ行に説明を付けている。
  shellcheck 0.9.0 はこれを受け付ける(SC2148 が消えることで確認済み)
- **下流プロジェクトは自分のシェルスクリプトの指摘を潰す必要がある**(`[manual]`)。
  シェルを使わない構成ではステップごと落として構わない
