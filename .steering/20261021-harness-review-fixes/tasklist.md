# タスクリスト

<!-- main-edit-ok -->

- [x] `lead/*.md` と `mode/*.md` に path-scoped の frontmatter を付ける
- [x] SessionStart hook: 司令塔専用ルールを Read 指示に置き換え、mode の frontmatter を取り除いて注入する
- [x] SessionStart hook: リモートセッションのブランチを自動で切り替える
- [x] `branch-and-tickets.md` の運用記述を更新する
- [x] `check-push-policy.sh` と `.husky/pre-push` を追加する
- [x] `check-branch-policy.sh` で `git push --no-verify` を止める
- [x] `template-manifest.json`・説明文(CLAUDE.md / README / spec-driven / context-management / cost-model)・CHANGELOG を更新する
- [x] 動作確認(hook の出力・pre-push の判定・CI と同じ検査)

## 申し送り

- frontmatter `paths` で自動ロードが止まることは、**次の新規セッションでしか確かめられない**(このセッションのコンテキストは開始時に組み立て済み)。次のセッションの冒頭で、`lead/` と `mode/` の本文がプロジェクトの指示に載っていないことを確認する
- ディレクトリの移動(`.claude/rules/` の外へ出す)は、自動モードの判定で `.claude/` 配下のシェル操作が止められたため見送った。frontmatter が効かない場合はこの案に戻る
- 動作確認の記録: hook の出力 14.8KB → 2.9KB。pre-push の判定 8 ケース・`--no-verify` 4 ケースが期待どおり。CI 相当の検査(実行ビット・構文・guard-integrity・forbidden-paths drift・format・lint・typecheck・test・secretlint)は全て通過
