<!-- テンプレート所有ファイル: /sync-template で上書きされます。プロジェクト固有のルールは CLAUDE.md の「プロジェクト固有ルール」節に書いてください。 -->
<!-- 司令塔専用: SessionStart hook がメインセッションにのみ注入します。サブエージェントには読み込まれません。 -->

## ブランチ戦略とチケット運用

### ブランチ戦略(単一ソース = `.claude/branch-policy.json`)

ブランチ戦略の判断は**推測せず、必ず `.claude/branch-policy.json` を読む**(`baseBranch` / `protectedBranches` / `allowedPrefixes`)。人間向けの説明は `docs/development-guidelines.md` に置くが、hook・CI・スラッシュコマンドが参照する値はポリシーファイルが正。

- **アプリ/web のリモートセッションは `claude/*` ブランチが先に作られた状態で始まる**。これは `feature/*` と同格の正規ブランチとして扱い、**リネームしない**(セッションとブランチの紐付けが壊れる)。新しいブランチも切らずそのまま作業する
- リモートセッションはプラットフォーム既定ブランチ(通常 `main`)起点で作られるため、`baseBranch` が `develop` のプロジェクトでは**乖離が起きる**。PR 作成前に `git merge origin/[baseBranch]` で追従し、`gh pr create --base [baseBranch]` を必ず明示する
- 保護ブランチ上での作業は禁止。層は **強制 3 層 + 情報提供 1 層**で、役割を混ぜないこと(強制 3 層の保護ブランチ判定は `.claude/scripts/check-protected-branch.sh` に一本化してあり、経路によらず同じ結果になる):
  - **情報提供(阻止しない)**: SessionStart hook が現在のブランチとポリシー上のベースを注入する
  - **強制1**: PreToolUse hook(直接コミットと `gh pr create --base` の誤りをブロック。**Claude 経由のみ**)
  - **強制2**: `.husky/pre-commit`(`git commit` / `--amend`)
  - **強制3**: `.husky/prepare-commit-msg`(`git revert` / `git cherry-pick`)。**2・3 はベンダー非依存**なので Codex・手動 git・他ツールにも効く
  - **最終検証(別軸)**: CI の `branch-policy` ジョブはクライアント非依存だが、見るのは **PR の base とブランチ名だけ**で、直接コミットされたかは見ない
  - git hook 層は 2 ファイル構成: `pre-commit` が `git commit` / `--amend` を、`prepare-commit-msg` が **`git revert` / `git cherry-pick`** を止める。後者は `pre-commit` が発火しないため別フックが要る。`git merge` / `git pull` の取り込みだけを通す(取り込みは違反ではない)。通す判定には第 2 引数ではなく **`.git/MERGE_HEAD` の有無**を使う — `git revert -e` / `git cherry-pick -e` も第 2 引数に `merge` を渡してくるため、引数だけで素通しにすると保護ブランチ上ですり抜ける(実測)。なおコンフリクトしたマージを `git commit` で確定する経路は `pre-commit` が発火するためブロックされる(保護ブランチ上でそこまで進むこと自体が想定外)
  - **`prepare-commit-msg` は `--no-verify` で迂回できない**(git の `--no-verify` は `pre-commit` と `commit-msg` しか無効化しない)。ローカルで唯一 `--no-verify` に耐える層

### チケット運用(GitHub Issues)

チケットは GitHub Issues(`ticket` + 優先度ラベル)で管理する(`/setup-tickets` が発行)。着手時に `in-progress` ラベルを付け、PR ボディの `Closes #N` でマージ時に自動クローズさせる。PR 作成後は Issue にコメントで `.steering/` ディレクトリ名とPR URLを記録する(`/next-ticket` が担当)。チケットファイルのステータス編集・コミットは行わない。

**`gh` CLI が使えない環境(Claude Code on the web のリモート実行等)では、コマンド・スキル内の `gh` 操作を同等の GitHub MCP ツール(`mcp__github__*`)で代替する。**
