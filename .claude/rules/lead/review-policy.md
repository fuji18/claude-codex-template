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
- **`/check` を回す前に `package.json` のライフサイクル系差分を目視する**(`scripts` / `lint-staged` / `prepare`)。`npm test` / `npm run lint` / `lint-staged` は**委託成果をホスト上・ネットワーク有効で実行する**経路で、sandbox はここを守らない(根拠: `docs/template-dev/codex-delegation-plan.md` §9)。委託を挟んだ差分では必ず見る:

  ```bash
  git diff -- package.json
  ```

  検収を飛ばすモードでも層が消えないよう、担保先をモードごとに決めてある:

  | モード | 担保 |
  | --- | --- |
  | A(通常) | 司令塔がこの目視を行う + `delegate-codex.sh` 出口検査の警告 |
  | B(節約) | **draft PR を作る前に人間が目視する**(`.claude/rules/mode/econ.md`) |
  | C(縮退) | `delegate-codex.sh` を通らないため出口検査が効かない。`check-guard-integrity.sh degraded` の D4 が報告する(`.claude/rules/mode/degraded.md`) |
- **実装中(主レビュー)**: `code-reviewer` subagent(read-only、Sonnet)を起動する。docs/ とのスペック整合もここで確認する
- **PR 時(最終ゲート、自動は 1 回だけ)**: GitHub Actions は **main 向け PR のオープン時と ready_for_review 時のみ**走る。develop 等の統合ブランチ向け PR では走らない(意図的なコスト削減。feature コードの主レビューは実装中の code-reviewer が担う)。push ごとの再レビューも走らない。再レビューが必要なときは PR 上で `@claude` にメンションする
  - テンプレート既定(GitHub Flow / `baseBranch: main`)では、すべての作業 PR がこの 1 回のレビュー対象になる。`develop` 統合ブランチを採るプロジェクトに切り替えた場合は「main 向け PR = リリース単位」となり、feature の主レビューは実装中の code-reviewer だけになる点に注意する(ベースの逸脱自体は CI の `branch-policy` ジョブが検出する)
- **200 行以上 かつ 重要変更(認証・決済・データ移行・アーキテクチャ変更)のレビュー**: **既定は `delegate-codex.sh review`**。`/code-review ultra` と Agent Teams 並行レビューは**昇格先**であって、既定と併用しない(同じ発動条件に 2 つの手段を割り当てると両方回す運用崩れになる。#60 / C4)
  - 理由は起動主体とコスト: `/code-review ultra` は**ユーザー起動 + 課金**で司令塔からは起動できず、温存したい Claude 枠を消費する。`delegate-codex.sh review` は read-only で司令塔が自分で起動でき、別ベンダーの第二意見にもなる
  - `/code-review ultra` を**ユーザーに提案する**のは次の 2 つだけ: (1) **その差分自体を Codex が書いた**(impl 委託の成果。同じベンダーの自己レビューは第二意見にならない)、(2) **Codex が使えない**(`exit 3` / レート上限)
  - 通常の大きめ差分にはどちらも使わない(主レビューは実装中の `code-reviewer`)
- **UI/画面のレビュー**: `docs/ui-design-guidelines.md`(スタック非依存の UI 基準)を参照し、§6 のチェックリストを `code-reviewer` または Design プラグイン(`/design:critique`)で当てる。**Design プラグインは画面作成があるプロジェクトのときだけ `/kickoff` フェーズ1.5 で導入を判断する**(画面が無いプロジェクトには入れない)
