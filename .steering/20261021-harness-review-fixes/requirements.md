# 要求: ハーネスレビュー指摘の修正(2026-10-21)

<!-- main-edit-ok -->

## 背景

効率・利便性・セキュリティの観点でハーネスをレビューし、次の 3 点を直すことになった(ユーザー承認済み)。

1. **司令塔専用ルールが全サブエージェントに読み込まれている。** Claude Code は `.claude/rules/` 配下の `.md` をサブディレクトリまで自動ロードするため、`lead/` と `mode/` が SessionStart hook の注入とは無関係に全エージェントへ載る。`mode/econ.md` と `mode/degraded.md` が同時に「現在のハーネスモード」を名乗り、normal モードでも矛盾した指示になっている。さらに hook の出力(14.8KB)が上限を超え、先頭 2KB のプレビューに切り詰められている
2. **リモートセッションのブランチ名がポリシー外になる。** プラットフォームが `ccr-…` のような名前でブランチを作るため、CI の branch-policy で必ず落ちる。ポリシーに `ccr` を足すのではなく、**セッション開始時にポリシー準拠のブランチへ自動で切り替える**(ユーザー指定)
3. **保護ブランチへの push がローカルのどの層でも止まらない。** `git push origin HEAD:main` が Claude・Codex・autopilot のいずれの経路でも素通りする

## 受け入れ条件

- `lead/*.md` と `mode/*.md` は、そのファイル自体を扱うとき以外は自動ロードされない
- SessionStart hook は司令塔専用ルールの本文を貼らず、Read すべきパスを指示する(出力が上限内に収まる)
- リモートセッションの startup で、ブランチ名が `allowedPrefixes` に一致しなければ `remoteSessionPrefix` を付けたブランチへ切り替わる
- `.husky/pre-push` が、保護ブランチへの push とポリシー外のブランチ名への push を止める(削除は保護ブランチ以外なら通す)
- PreToolUse hook が `git push --no-verify` を止める(pre-push を迂回できる唯一の経路)
