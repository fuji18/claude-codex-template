# プロジェクトメモリ

> このファイルは**プロジェクト所有**です。自由に書き換えてください。
> 以下でインポートしている `.claude/rules/*.md` は**テンプレート所有**で、`/sync-template` 実行時に上書きされます。**編集しても同期で失われます。**上書きしたい場合はこのファイルの「プロジェクト固有ルール」節に例外を書いてください(後勝ち)。

## 共通ルール(テンプレート同期対象)

@.claude/rules/spec-driven.md

上記は**メインセッションと全サブエージェントに読み込まれる**共通ルール。司令塔だけが使うルール(モデル運用・コンテキスト管理・レビューの使い分け・ブランチ/チケット運用・計画フェーズ)は `.claude/rules/lead/*.md` にあり、**SessionStart hook がメインセッションにのみ注入する**(サブエージェントに載せると spawn のたびに課金されるため。根拠は `docs/template-dev/cost-model.md`)。

## 技術スタック

- 開発環境: devcontainer
- Node.js v24(devcontainer / CI / `engines` で固定)
- TypeScript 6.x
- パッケージマネージャー: npm

※ テンプレート既定値。プロジェクト開始時(`/kickoff`)にアイデアの技術選定と突き合わせ、実態に更新する。

## プロジェクト固有ルール

<!-- ここはプロジェクト所有。テンプレート同期で消えません。
     追記先の例: MCP の使いどころ(/kickoff フェーズ1.5)、スポーク構成ルールへの参照(/setup-spoke-standards)、
     ハーネス層の検証コマンド(/harness-setup)、共通ルールの上書き・例外。 -->

### Codex への委託禁止領域(パス)

以下は Codex に委託しない(司令塔または `implement-ticket` の fork が直接書く)。振り分けの判断基準は `.claude/rules/lead/delegation-policy.md`。

- `.claude/scripts/` — 委託の唯一の入口(`delegate-codex.sh`)、保護ブランチ判定、CI が `bash` で呼ぶ判定の実体(`check-record-hygiene.sh` / `check-guard-integrity.sh`)、検収状態を書き換える `codex-run.sh` がすべてここにある。`.github/workflows/` を守っても、そのワークフローが実行する実体が書き換え可能なら防御は成立しない。個別列挙はスクリプトが増えるたびに漏れるのでディレクトリ単位で禁止する(実行中プロセスの保護は #15 の自己コピー exec で別途実装済み。`docs/template-dev/codex-delegation-plan.md` §9)
- `.claude/hooks/` / `.claude/settings.json` — PreToolUse hook の定義そのものと、司令塔コンテキストへの注入元(プロンプトインジェクションの経路になり得る)
- `.husky/pre-commit` / `.husky/prepare-commit-msg` — ベンダー中立ガードレールの本体
- `.claude/codex-denylist.txt` — 委託先が自分の送信禁止リストを編集できてはならない
- `AGENTS.md` — 委託先の憲法。入口検査3 の `<!-- verify-probe: ... -->` は次回委託時にホスト上の `bash -c` へそのまま渡されるため、書き換えを許すとサンドボックス外でのコマンド実行経路になる
- `.github/workflows/` — 非 fork PR で `CLAUDE_CODE_OAUTH_TOKEN` にアクセスできるワークフロー定義そのもの
- `.harness/mode` / `.harness/codex-runs/` — ハーネスモードと run record。委託先が自分の結果を `accepted` に書き換えたりモードを詐称したりできてはならない

`.claude/` 配下でも `skills/` / `commands/` / `agents/` / `rules/` / `docs/` は禁止領域に含めない。対象は**実行される実体**(scripts / hooks / settings.json)に限る。

**機密の送信禁止(`.claude/codex-denylist.txt`)とは別の層。** denylist は該当ファイルが存在するだけで委託を止めるフェイルクローズ検査、こちらは司令塔が「どのチケットを渡すか」を決める振り分け判断。

**単一ソースは 2 系統に分かれる。** 上に挙げた**汎用項目**は `delegate-codex.sh` の `FORBIDDEN_PATHS` 配列が正。`/kickoff` フェーズ4 が書く**プロジェクト固有パス**(認証・決済・データ移行などの実パス)は `AGENTS.md` §4 の `<!-- kickoff:delegation-forbidden-paths -->` マーカー内が正で、出口検査が委託の開始時に抽出して配列とマージする。impl 委託の実行後に前後の内容ハッシュを突き合わせ、差分があれば `status=failed` / `exit 2` で止める。ここの記述はその説明であり、汎用項目を変えるときはスクリプト側の配列と `AGENTS.md` §4 を同時に直す。

## ディレクトリ構造(要点)

- `docs/ideas/`: 下書き・アイデア(自由形式。`/setup-project` が自動で読み込む)。プロジェクト開始の起点は `initial-requirements.md`
- `docs/template-dev/`: テンプレート自体の開発記録と記入例(`*.example.md` 含め読み込み対象外。プロダクト開発開始後は削除可)
- `docs/`: 正式版の永続ドキュメント6つ(PRD / 機能設計 / 技術仕様 / リポジトリ構造 / 開発ガイドライン / 用語集)。基本設計を記述し頻繁には更新しない「北極星」
  - `docs/ui-design-guidelines.md`: 上記6つとは別枠のテンプレート同梱・横断ガイド(スタック非依存の UI 品質基準)。画面/UI を作る場合に参照し、§7「実装への翻訳」表は `/kickoff` フェーズ1.5 でスタックに合わせて記入する
  - `docs/ui-design-request-template.md`: AI に画面デザインを依頼するプロンプト雛形(ガイドライン §11 の単体版・記入例つき)
- 実装チケット: GitHub Issues で管理(`/setup-tickets` が発行。リポジトリ内にチケットファイルは置かない)
- `.claude/rules/`: テンプレート所有の共通ルール(全エージェント共通。上記でインポート)。`/sync-template` の同期対象
  - `.claude/rules/lead/`: 司令塔専用ルール(SessionStart hook が注入。サブエージェントには載らない)
- `.claude/docs/`: プロジェクト開始後も参照が続く判断ガイド(MCP 導入の判断 / serena 再導入の目安と手順)。`docs/template-dev/` と違い削除しない
- `.steering/`: 作業単位の計画とタスクリスト。作業ごとに新規作成し、**履歴としてコミットして保持する**

詳細は `README.md` を参照。

## 開発プロセス

### 初回セットアップ

詳細な手順書は `README.md` を参照。

1. このテンプレートを使用(devcontainerで開く)
2. アイデアを `docs/ideas/initial-requirements.md` に書く
3. `/kickoff` を実行(スタック整合 → /setup-project → /setup-tickets → /harness-setup → README書き換えまで一気通貫)
   - ハブ&スポーク構成の場合は `/setup-spoke-standards` も実行する(**ハブ側リポジトリで、`/setup-tickets` より前に実行**。スポーク側リポジトリでは実行せず、生成された `docs/playbook/spoke-development-standards.md` を読んで従う)
4. `/next-ticket` でチケットを消化(または `/add-feature [機能]`)

### 日常的な使い方

基本は普通に会話で依頼する(ドキュメント編集・調査・相談など)。定型フローのみスラッシュコマンドを使う(各コマンドの説明はコマンド一覧に注入済み。早見表は `README.md` の「コマンド早見表」を参照)。

**ポイント**: スペック駆動開発の詳細を意識する必要はありません。Claude Codeが適切なスキルを判断してロードします。

### テンプレート更新の取り込み

テンプレート(`claude-code-template`)側で共通ルール・コマンド・スキル・ハーネスが更新されたら、**`/sync-template`** で差分を取り込む。同期対象・除外は `.claude/template-manifest.json` が単一ソース。

- 月次の `template-update-check` ワークフロー(毎月1日)が、テンプレートに未取り込みの更新があれば Issue を立てる
- `[manual]` 印の変更はプロジェクト側の対応が要るため、`/sync-template` の提示に従って個別に判断する
