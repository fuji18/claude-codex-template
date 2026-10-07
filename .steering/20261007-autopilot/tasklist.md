<!-- main-edit-ok --> (テンプレート自体の改修。新規パターンの 1 例目で判定ロジックと設計が不可分なため司令塔が参照実装を書く)
# タスクリスト: autopilot

- [x] `.claude/autopilot.json` を追加
- [x] `.claude/scripts/autopilot-next.sh` を実装(フィクスチャで action 5 種を確認)
- [x] `.claude/scripts/autopilot-loop.sh` を実装(`--dry-run` で確認)
- [x] `.claude/commands/fix-pr.md` を追加
- [x] `.claude/commands/autopilot.md` を追加
- [x] `.claude/commands/next-ticket.md` を WIP 判定・ブランチ切り直しに変更
- [x] `.claude/commands/status.md` の次の一手を更新
- [x] `branch-and-tickets.md` / `settings.json` / `template-manifest.json` を更新
- [x] README・CHANGELOG を更新
- [ ] 検収(code-reviewer + test-runner)
