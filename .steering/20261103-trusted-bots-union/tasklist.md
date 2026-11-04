# tasklist: 信頼するボットを 2 キーの和集合で解決する

<!-- main-edit-ok -->
<!-- `.claude/scripts/` は委託禁止領域(CLAUDE.md「Codex への委託禁止領域」)。
     テンプレート自体の改修なので司令塔が直接書く。 -->

## 実装

- [x] `.claude/scripts/pr-feedback.sh` の `BOTS` を 2 キーの和集合にする(`unique`)。`.user.type == "Bot"` の確認は残す
- [x] `.claude/scripts/autopilot-next.sh` の `TRUSTED_BOTS` を同じ和集合にし、`trustedBots` にも同じ型検査(文字列の配列でなければ die)を入れる
- [x] 既定値の扱いを両スクリプトで揃える(キーが無いときは `["claude[bot]","github-actions[bot]"]`)

## 文書

- [x] `.claude/autopilot.json` の `$comment`(既定値は変えない)
- [x] `.claude/commands/autopilot.md` の設定表
- [x] `.claude/docs/autopilot-guide.html` の設定表(`trustedBots` の行を足す)と FAQ
- [x] `.claude/commands/fix-pr.md` のステップ1-5 / 2-3
- [x] `.claude/rules/lead/review-policy.md` の「GitHub 上の Codex レビュー」の項
- [x] `docs/template-dev/CHANGELOG.md` の `## 2026-11-03` に `[auto]` で 1 項目

## 検証

- [x] `pr-feedback.sh`: `gh` スタブで 4 ケース(trustedReviewBots のみ / trustedBots のみ / どちらにも無し / `user.type: "User"`)
- [x] `autopilot-next.sh`: フィクスチャで 4 ケース(trustedBots / trustedReviewBots / どちらにも無し / 型不正で exit 2)
- [x] 修正前(`origin/main`)で不具合が再現することも同じ検証で確認した(両方向)
- [x] `bash -n`(`.claude/scripts/*.sh` 全量)
- [x] ~~`shellcheck -x`~~ (理由: ホストに shellcheck が無く、取得が sandbox に拒否された。手元の docker イメージ全てにも入っていない。CI にも shellcheck のジョブは無い。代わりに `bash -n` 全量 + 新規コードの目視で代替し、**人間に申し送る**)
- [x] `bash .claude/scripts/check-forbidden-paths-doc.sh`(exit 0)
- [x] `npx prettier --check .`(追跡ファイルは全て合格。未追跡の `.agents/` 39 ファイルだけが警告 —— 本作業の対象外)
- [x] `bash .claude/scripts/autopilot-preflight.sh` の設定検査が ✅ のまま
- [x] 追加で `check-manifest-coverage.sh` / `test-sync-template.sh` / `test-route.sh` / `tsc --noEmit` / `vitest run` / `eslint .` も通した

## 仕上げ

- [x] コミットして PR を作る(マージはしない)

## 申し送り

- **検証環境**: Windows ホストに `jq` が無いため、スクリプトの検証は手元にビルド済みの
  devcontainer イメージ(`jq 1.6` / `--network none`)の中で回した。テストは
  `gh` スタブ + `--issues/--prs/--details` フィクスチャで、リポジトリにはコミットしていない
- **`shellcheck -x` は未実行**。ホスト・docker イメージのどこにも無く、取得も拒否された。
  CI にも shellcheck のジョブは無いので、**入れるなら `ci.yml` にジョブを足すのが筋**(別チケット向き)
- **`.agents/`(未追跡)が `prettier --check .` を 39 ファイル分落としている**。git 追跡外なので CI は赤くならないが、
  手元で `npm run format:check` を回すと必ず失敗する。`.prettierignore` か `.gitignore` に入れるかは別途判断が要る
- **CHANGELOG は `## 2026-11-03` に追記した**(依頼どおり)。記法上は「日付を遡って追記しない」が原則だが、
  この項目は `[auto]`(取り込む側の作業ゼロ)なので、既に 11-03 分を同期した下流が見落としても害は無い
