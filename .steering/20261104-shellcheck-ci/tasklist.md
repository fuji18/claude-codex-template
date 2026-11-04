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

---

## 第2ラウンド: devcontainer にも入れ、判定を 1 箇所に寄せる

- [x] `.claude/scripts/check-shell.sh` を新規作成(対象の選定と引数を集約。`0/1/2` の終了コード契約・`--list`・`--help`)
- [x] git の index に実行ビットを立てる(`git update-index --chmod=+x`。CI の harness-integrity が検査する)
- [x] `ci.yml` のインライン実装をスクリプトの呼び出しに差し替える(非ゼロはすべて失敗)
- [x] `.devcontainer/post_create.sh` に `[2/5] Installing shellcheck...` を足す(`set -e` 下でも落ちないよう `if` の条件で受ける。ステップ番号を 4 → 5 に振り直す)
- [x] `test-runner.md` に検出項目を足す(`check-shell.sh` があるときだけ回す / `exit 2` はスキップ / 自動修正はしない)
- [x] `check.md` の description と README のコマンド早見表を「シェル検査」込みに直す
- [x] `docs/template-dev/CHANGELOG.md` の `## 2026-11-04` を最終形(3 点セット + 取り込む側の作業)に書き換える
- [x] `.claude/settings.json` の allow に `Bash(bash .claude/scripts/check-shell.sh:*)` を足す(**人間が手で追加**。auto モードの分類器が Claude の編集を自己改変として拒否したため。挿入位置・JSON の妥当性・重複なし・`autopilot-preflight.sh` の許可検査 ✅ を確認済み)

### 第2ラウンドの検証

- [x] `bash .claude/scripts/check-shell.sh` が追跡下 **31 ファイル**(新規スクリプト自身を含む)で `exit 0`
- [x] `--list` が 31 行(shellcheck が無くても動く)
- [x] shellcheck を退避した状態で `exit 2` と案内メッセージ
- [x] 対象 0 件(空の git リポジトリ)で `exit 2`
- [x] 不明な引数で `exit 2`
- [x] CI と同じ実行ビット / shebang / `bash -n` の検査(`lib-*.sh` は非実行 + shebang 無し、他は実行ビットあり)
- [x] `git ls-files -s` で `check-shell.sh` が `100755` になっていること
- [x] `bash -n .devcontainer/post_create.sh`
