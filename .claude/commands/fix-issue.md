---
description: GitHub Issueを読み込み、steeringフローで修正を実装してPRを作成する
---

# GitHub Issueの修正

指定されたGitHub Issueの内容を読み込み、ステアリングファイルで計画を立ててから修正を実装し、PRを作成するコマンドです。

**引数:** Issue番号（例: `/fix-issue 42`）

---

## 手順

### ステップ1: Issueの読み込み

1. Issue番号が指定されていない場合は、`gh issue list --state open` でオープンなIssue一覧を表示し、どれを対応するかユーザーに確認して終了する。
2. Issueの内容を取得する:
   ```bash
   gh issue view [Issue番号]
   ```
3. Issueから以下を把握する: 問題の内容、再現手順、期待される動作、関連ファイルのヒント。

### ステップ2: 原因調査

1. `CLAUDE.md` と関連する `docs/` の永続ドキュメントを読む。
2. GrepでIssueに関連するコードを検索し、原因箇所を特定する。
3. 原因が特定できない・Issueの内容が曖昧な場合は、調査結果と質問を `gh issue comment` で残すことを提案し、ユーザーの判断を仰ぐ。

### ステップ3: ブランチとステアリングファイルの作成

1. **`.claude/branch-policy.json` を読み**、`git branch --show-current` で現在地を確認する。
   - すでに `allowedPrefixes` に一致する作業ブランチ上にいる場合(アプリのリモートセッションが生成した `claude/*` を含む)は、**新しいブランチを作らずそのまま使う**。`claude/*` はリネームしない
   - 保護ブランチ上にいる場合のみ、ポリシーの `baseBranch` から切る:
     ```bash
     git fetch origin [baseBranch]
     git checkout -b fix/[YYYYMMDD]-issue-[Issue番号] origin/[baseBranch]
     ```
2. `.steering/[YYYYMMDD]-issue-[Issue番号]/` を作成し、`Skill('steering')` の**計画モード**で `requirements.md`・`design.md`・`tasklist.md` を生成する。
   - `requirements.md` にはIssueの内容とIssue番号を記載する
   - 軽微な修正（1〜2ファイル・数行程度）の場合、design.mdは簡潔でよい

### ステップ4: 実装(委託)

**司令塔は実装コードを書かない。** 委譲前に `git status` で作業ツリーがクリーンであることを確認したうえで、**既定は `bash .claude/scripts/delegate-codex.sh impl .steering/[dir]`**、`exit 3` なら `Skill('implement-ticket')`(`context: fork` / Sonnet)に切り替える。**分岐は `/add-feature` ステップ5 の手順ごとに従う**(3 コマンドで同一)。終了コード表だけでなく、**`exit 3` を一度受けたらそのセッションでは `delegate-codex.sh` を呼び直さない**という恒久フォールバックの手順も含む。

- `design.md` に「修正に対応するテストを追加または更新する(回帰防止)」を必ず含めてから委譲する

### ステップ5: 検証

1. 以下の 2 つのサブエージェントを**同一メッセージ内で並列起動**する(`/add-feature` ステップ6 と同じ検収。修正系だからといってレビューを省かない — `develop` 運用のプロジェクトでは PR 時の自動レビューが走らないため、ここが唯一の主レビューになる):
   - `code-reviewer`(Sonnet): prompt: "Issue #[番号] の修正差分をレビューしてください。対象ファイルは `[変更ファイルのパスリスト]` です。回帰防止のテストが修正内容を実際にカバーしているかを重点的に見て、確信が持てない指摘も含めて全て報告してください。"
   - `test-runner`(Haiku): 全品質チェック(lint・型チェック・テスト・フォーマット)の実行と機械的なエラーの自動修正を依頼する。
2. code-reviewer の `[Critical]` / `[Major]` の指摘は修正する。`[Minor]` は `tasklist.md` の申し送り事項に記録する。
3. 可能であれば、Issueに記載された再現手順で問題が解消したことを確認する。

### ステップ6: コミットとPR作成

1. `Skill('commit')` を実行して変更をコミットし(粒度と Conventional Commits はスキルが担う。件名に `(#[Issue番号])` を含める)、`git push` する。
2. PRを作成する（ベースブランチは **`.claude/branch-policy.json` の `baseBranch`** を使う。ポリシーファイルが無い場合のみデフォルトブランチ `main`。ボディは `.github/pull_request_template.md` の構成に従う）:
   ```bash
   gh pr create \
     --title "fix: [修正内容の要約]" \
     --base [ブランチ戦略に従ったベースブランチ] \
     --body "## 概要
   [修正内容と原因の説明。主な変更ファイル]

   ## 関連 Issue

   Closes #[Issue番号]

   ## ステアリング

   [.steering/ ディレクトリ名]

   ## 検証
   - [x] /check(lint・型チェック・テスト・フォーマット)がパス
   - [x] [Issueの再現手順で解消を確認した内容]

   🤖 Generated with [Claude Code](https://claude.com/claude-code)"
   ```
3. PRのURLをユーザーに報告する。
