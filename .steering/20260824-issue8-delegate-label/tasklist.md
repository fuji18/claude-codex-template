# タスクリスト: 段階6 — チケット統合(Issue #8)

> **設計は `design.md` に書き切ってある。** 各タスクは対応する節の内容を**そのまま**反映するだけで、設計判断は不要。
> 判断が必要になったら停止して報告すること(`.claude/scripts/` と `.harness/` は 1 行も変更しない)。
> **1 タスク完了ごとに `- [x]` へ更新する**(まとめ更新は禁止)。

- [x] 1. `.claude/rules/lead/delegation-policy.md` を新規作成する(design.md §2 の内容をそのまま)
- [x] 2. `.claude/commands/setup-tickets.md` を更新する(design.md §3 の 3-1〜3-6 の 6 か所)
- [x] 3. `.claude/commands/next-ticket.md` を更新する(design.md §4 の 4-1・4-2 の 2 か所)
- [x] 4. `.claude/commands/kickoff.md` を更新する(design.md §5 の 5-1〜5-3 の 3 か所)
- [x] 5. `AGENTS.md` の §4 に「委託禁止領域(パス)」節を挿入する(design.md §6)
- [x] 6. `CLAUDE.md` の「プロジェクト固有ルール」節を差し替える(design.md §7)
- [x] 7. `README.md` を更新する(design.md §8 の 8-1〜8-3 の 3 か所)
- [x] 8. `docs/template-dev/codex-delegation-plan.md` に申し送りの消し込みと注記を入れる(design.md §9 の 9-1〜9-5 の 5 か所)
- [x] 9. `npx --no-install prettier --write` で変更した Markdown を整形し、`npm run lint` が通ることを確認する

## 申し送り

- **チケット丸ごとの委託(`delegate:codex`)は成立した。** tasklist 9/9 を逐次更新して `exit 0`、所要 5 分 12 秒、差し戻し 0 回。生ログ 92,315 B に対し司令塔へ返ったサマリーは約 50 B。差分は `design.md` §2〜§9 の逐条と verbatim で一致した
- **検収の指摘 7 件(Critical 0 / Major 3 / Minor 4)は、すべて `design.md` 自身のスコープ漏れか、本チケット以前からあった文書間の不整合だった**(実装の誤りは 0 件)。委託の品質ではなく計画の網羅性が律速になる、というのが今回の学び
- **最も重要な指摘**: `AGENTS.md` の委託禁止領域マーカーを `/kickoff` が「差し替える」と書いていた点。マーカー内の汎用項目(`delegate-codex.sh` の自己編集ハザード・`.husky/`)はどのプロジェクトにも配布されるため、差し替えるとプロダクト側でガードレール保護が最初から欠落する。「汎用項目は残して**追記**する」に修正した
- 併せて司令塔が修正: README 冒頭サマリと「実装フェーズが…仕組み」節、`.claude/rules/lead/model-strategy.md`(いずれも実装フェーズ = Sonnet 固定のままで Codex 既定と矛盾していた)、`/kickoff` の 403 判定の表現、`/setup-tickets` の判定条件の補足、`/kickoff` フェーズ6 の 3 択結果の明記
- **残課題**: (1) 週枠の実効寿命の econ 比較(`/usage` は人間しか読めない。次の econ 運用時に記録)、(2) `delegate-codex.sh` の自己編集ハザードの実装(方針は決定済み。別 Issue に切り出す)
