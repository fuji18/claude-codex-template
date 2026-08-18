<!-- テンプレート所有ファイル: /sync-template で上書きされます。プロジェクト固有のルールは CLAUDE.md の「プロジェクト固有ルール」節に書いてください。 -->
<!-- 司令塔専用: SessionStart hook がメインセッションにのみ注入します。サブエージェントには読み込まれません。 -->

## レビューの使い分け(トークン最適化済み)

- **機械的な品質ゲート**: CI(`ci.yml`)が **PR(全ベース)と main / develop への push** で lint・型チェック・フォーマット・テストを実行する(シークレット不要)。**作業ブランチへの push だけでは走らない**(PR を開いた後は synchronize で走る)。**CI は Claude の枠を一切消費しない**ので、機械的検証はできるだけ CI に寄せる
- **品質チェックの三層の役割分担**(同じ内容を繰り返し回さないための切り分け):

  | 層 | 範囲 | 担当 |
  | --- | --- | --- |
  | 実装直後の自己修復 | **変更したファイル**の lint・型・関連テスト | `implement-ticket` の fork(Sonnet) |
  | 検収 | フルスイート 1 回 | `test-runner`(Haiku)= `/check` |
  | 最終ゲート | フルスイート + secretlint + Harness integrity | CI |

  `/check` を「実装中に即時フィードバックが要る局面」以外で繰り返し回さない
- **実装中(主レビュー)**: `code-reviewer` subagent(read-only、Sonnet)を起動する。docs/ とのスペック整合もここで確認する
- **PR 時(最終ゲート、自動は 1 回だけ)**: GitHub Actions は **main 向け PR のオープン時と ready_for_review 時のみ**走る。develop 等の統合ブランチ向け PR では走らない(意図的なコスト削減。feature コードの主レビューは実装中の code-reviewer が担う)。push ごとの再レビューも走らない。再レビューが必要なときは PR 上で `@claude` にメンションする
  - テンプレート既定(GitHub Flow / `baseBranch: main`)では、すべての作業 PR がこの 1 回のレビュー対象になる。`develop` 統合ブランチを採るプロジェクトに切り替えた場合は「main 向け PR = リリース単位」となり、feature の主レビューは実装中の code-reviewer だけになる点に注意する(ベースの逸脱自体は CI の `branch-policy` ジョブが検出する)
- **Agent Teams 並行レビュー / `/code-review ultra`**: **200 行以上 かつ 重要変更(認証・決済・データ移行・アーキテクチャ変更)** のときのみ提案する。通常の大きめ差分には使わない
- **UI/画面のレビュー**: `docs/ui-design-guidelines.md`(スタック非依存の UI 基準)を参照し、§6 のチェックリストを `code-reviewer` または Design プラグイン(`/design:critique`)で当てる。**Design プラグインは画面作成があるプロジェクトのときだけ `/kickoff` フェーズ1.5 で導入を判断する**(画面が無いプロジェクトには入れない)
