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
- [x] 検収(code-reviewer + test-runner)
  - test-runner: lint / typecheck / test / format / secretlint / guard-integrity / forbidden-paths-doc すべてパス
  - code-reviewer: Critical 0 / Major 7 / Minor 9。Major は全件修正(変更要求は現在の head に対するものだけ数える /
    `depends:` 行の複数番号 / `Closes` の単語境界 / クラウドの再予約上限と子セッション ID の Issue コメント /
    ループの数値検証 / `issue[N]-` の区切り照合 / 別セッションの stalled を奪わない)。Minor は 9(取得失敗の表示)・
    10(cancelled を外す)・11(判定 1 回)・12(設計書の整合)・13(maxInFlight 0 を拒否)・14(develop の注記)・
    15(信頼できるレビュアーのみ)を修正、8(package-lock.json)は差分から除外

## 申し送り

- 16(`harness-mode.sh` 不在時に normal へ倒れる)は据え置き。同スクリプトは常に exit 0 で有効値を返し、不在は SessionStart / CI の harness-integrity が先に検出する
- クラウド経路(子セッション起動・send_message・send_later)は手順書のみで、実地の通し運転は未実施。初回は `/autopilot` を見守りながら回すこと
- コメントだけのレビュー指摘は判定スクリプトでは検出しない(クラウドは PR イベント、ローカルは Request changes / `@claude`)
