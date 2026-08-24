# タスクリスト: 段階6 — チケット統合(Issue #8)

> **設計は `design.md` に書き切ってある。** 各タスクは対応する節の内容を**そのまま**反映するだけで、設計判断は不要。
> 判断が必要になったら停止して報告すること(`.claude/scripts/` と `.harness/` は 1 行も変更しない)。
> **1 タスク完了ごとに `- [x]` へ更新する**(まとめ更新は禁止)。

- [ ] 1. `.claude/rules/lead/delegation-policy.md` を新規作成する(design.md §2 の内容をそのまま)
- [ ] 2. `.claude/commands/setup-tickets.md` を更新する(design.md §3 の 3-1〜3-6 の 6 か所)
- [ ] 3. `.claude/commands/next-ticket.md` を更新する(design.md §4 の 4-1・4-2 の 2 か所)
- [ ] 4. `.claude/commands/kickoff.md` を更新する(design.md §5 の 5-1〜5-3 の 3 か所)
- [ ] 5. `AGENTS.md` の §4 に「委託禁止領域(パス)」節を挿入する(design.md §6)
- [ ] 6. `CLAUDE.md` の「プロジェクト固有ルール」節を差し替える(design.md §7)
- [ ] 7. `README.md` を更新する(design.md §8 の 8-1〜8-3 の 3 か所)
- [ ] 8. `docs/template-dev/codex-delegation-plan.md` に申し送りの消し込みと注記を入れる(design.md §9 の 9-1〜9-5 の 5 か所)
- [ ] 9. `npx --no-install prettier --write` で変更した Markdown を整形し、`npm run lint` が通ることを確認する

## 申し送り

(実装後に司令塔が記入する)
