# タスクリスト: 実装フェーズの fork 委譲と rules の役割分割

<!-- main-edit-ok -->
<!-- ↑ この作業はテンプレート自体の改修であり、司令塔が直接編集する。
     check-implementation-phase.sh のブロックを解除するマーカー。
     プロダクト開発のチケットでは付けないこと。 -->

## 1. rules の役割分割

- [x] `.claude/rules/lead/` を作成し、司令塔専用ルール 4 本を移動する
- [x] `.claude/rules/spec-driven.md` を全エージェント共有の実装ルールに絞る
- [x] `.claude/rules/lead/planning.md` を新設(計画・承認フローを spec-driven から移す)
- [x] `.claude/rules/lead/model-strategy.md` を fork 委譲前提に書き換え・圧縮する
- [x] `.claude/rules/lead/context-management.md` を圧縮する
- [x] `docs/template-dev/cost-model.md` に判断の根拠を退避する
- [x] `.claude/hooks/session-start.sh` で `lead/*.md` をメインセッションに注入する

## 2. 実装フェーズの fork 委譲

- [x] `.claude/agents/implementer.md` を作成する
- [x] `.claude/skills/implement-ticket/SKILL.md` を作成する
- [x] `.claude/scripts/check-implementation-phase.sh` を作成する
- [x] `.claude/settings.json` に PreToolUse(Edit|Write)を追加する

## 3. コマンドの書き換え

- [x] `/next-ticket` の実装ステップを fork 呼び出しに置き換える
- [x] `/add-feature` の実装ループを fork 呼び出しに置き換える
- [x] `/fix-issue` の実装ステップを fork 呼び出しに置き換える

## 4. 関連ドキュメントの整合

- [x] `CLAUDE.md` のインポート一覧・ディレクトリ構造を更新する
- [x] `README.md`(モデル運用方針・委譲フロー図・ディレクトリ構造・テンプレート更新節)を更新する
- [x] `docs/template-dev/CHANGELOG.md` に `[manual]` で記録する
- [x] `.claude/skills/harness-setup/SKILL.md` の rules 記述を更新する

## 5. 検証

- [x] hook スクリプトの構文チェックと実行権限
- [x] session-start.sh が lead ルールを注入することの確認
- [x] check-implementation-phase.sh の判定(ブロック/通過)の確認

## 申し送り

- `implement-ticket` の実効性(fork が実際に Sonnet で走り、停止条件が機能するか)は、次のプロダクト開発チケットで初めて実地検証される。最初の 1 チケットは fork の戻り値と往復回数を観察し、`design.md` の粒度が足りているかを確認すること
- `allowed-tools` がフォーク先サブエージェントの権限にも適用されるかはドキュメントに明記が無い。`settings.json` の allow が実質の担保になっているため、権限不足で止まった場合は止まったコマンドを記録してから追加を検討する(方針 A)
