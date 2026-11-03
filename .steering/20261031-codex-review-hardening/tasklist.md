# タスクリスト

- [x] `delegate-codex.sh` review: 入口検査6・プロンプト・出力検証・サマリー上限・read-only 裏取り
- [x] `AGENTS.md` §1 注記と §8 Review guidelines
- [x] `review-policy.md` / `delegation-policy.md` / `add-feature.md` / `settings.json` / preflight の allow
- [x] `autopilot-next.sh`: fork PR・信頼するレビュアー
- [x] `autopilot-loop.sh`: クラウド拒否・判定の再試行・permission_denials
- [x] `fix-pr.md` / `next-ticket.md` / `econ.md` / `autopilot.md` / `autopilot.json` / 手順書
- [x] `.codex/hooks.json` / `template-manifest.json`
- [x] README・codex-delegation-plan.md の表・CHANGELOG
- [x] 検証(スタブ codex での review / explore / impl の通し・フィクスチャでの判定・スタブ claude でのループ・bash -n・shellcheck)

## 申し送り

- 実機の Codex での review は未実施。初回は小さな未コミット差分で `delegate-codex.sh review origin/main` を回し、`findings:` 行が出ることを確認する
- `claude -p --output-format json` の `permission_denials` フィールドは実機で未確認(無ければ一覧が空になるだけで、ループの動作は変わらない)
- `.codex/hooks.json` の新しい形は Linux / devcontainer の bash 前提。Windows ネイティブの Codex から hook を使う場合は別途確認する
- GitHub の Codex ボットのログイン名(例: `chatgpt-codex-connector[bot]`)は導入時に実際のレビューで確かめて `trustedReviewBots` に入れる
