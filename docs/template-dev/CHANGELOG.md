# テンプレート CHANGELOG

テンプレート利用側(このテンプレートから作ったプロジェクト)が **`/sync-template` で更新を取り込むとき** に読む変更履歴です。テンプレート自身の開発メモではなく、**「取り込む側が何をすればよいか」** だけを書きます。

## 記法

- 新しいものを**上**に置く。見出しは `## YYYY-MM-DD` の日付単位
- 各項目の先頭に区分を付ける:
  - **`[auto]`** — `/sync-template` の上書きだけで完結する。取り込む側の作業はゼロ
  - **`[manual]`** — 取り込む側に作業が必要。**何をすればよいかを 1 行で書く**(これが無い `[manual]` は書いた意味がない)
- 破壊的変更(既存の運用が壊れる)は `[manual]` にし、行頭に **⚠️** を付ける
- `/sync-template` は `syncedAt` のコミット日以降の日付見出しだけを読む。**日付を遡って過去の見出しに追記しない**(取り込む側が見落とす)

---

## 2026-08-12 (2)

fork 委譲構成の点検で見つかった欠陥の修正。**同日の初回同期分(下の「2026-08-12」)を取り込む場合は、こちらもまとめて取り込むこと**(単体では実装フェーズが動かない欠陥を含む)。

- **[auto]** ⚠️ `implement-ticket` スキルの `allowed-tools` を削除。Bash の限定パターンだけを列挙しており Read / Edit / Write が含まれていなかったため、fork 先の実装エージェントが編集できず全チケットが失敗しうる状態だった。権限の担保は `settings.json` の `permissions.allow` と `implementer` の `tools:` に一本化する
- **[auto]** 最新ステアリングディレクトリの判定を `.claude/scripts/latest-steering.sh` に集約。従来の `ls -1d .steering/*/ | sort -r | head -1` は**ディレクトリ名全体**の降順のため、同日に複数の作業があると機能名の文字順で決まり、hook・fork・SessionStart が別々のディレクトリを指すことがあった。新規則は「日付プレフィックス降順 → 同日は mtime 降順」
- **[manual]** テンプレート由来の `.steering/*/` をプロジェクト側に残さないこと。これらの `tasklist.md` には実装フェーズのブロックを解除する `<!-- main-edit-ok -->` が入っており、残ったまま「最新」と判定されると**強制委譲が効かない状態で開発が始まる**。**取り込む側の作業**: `ls -1d .steering/*/` を確認し、テンプレート開発の作業記録(`*-fork-implementation-phase` / `*-rule-defect-fixes`)が残っていたら削除する(`/kickoff` フェーズ5 に手順を追加済み)
- **[auto]** PreToolUse hook の誤爆を修正。`check-branch-policy.sh` / `block-dangerous-cmds.sh` の検出をコマンド位置(行頭・`;`・`&&`・`||`・パイプの直後)に限定した。従来は `grep "gh pr create" docs/` のように**引用符の中に文字列が現れただけ**の調査コマンドがブロックされていた。あわせて破壊的 SQL の検査を DB クライアント経由の実行に限定し、`git push -f origin main`(フラグが第一引数に来る形)の取りこぼしを修正
- **[auto]** `/fix-issue` の検証ステップに `code-reviewer` を追加(従来は `/check` のみでレビューが走らず、`develop` 運用では PR 時の自動レビューも走らないためレビューゼロで PR に到達しうる経路だった)。コミットも `Skill('commit')` に統一
- **[manual]** `.claude/settings.json` の `permissions.allow` に `Bash(git fetch:*)` / `Bash(git merge:*)` / `Bash(gh pr create:*)` を追加。**取り込む側の作業**: `merge` 対象のため、自分の allow 配列に同じ 3 つを追記する(無いと `/add-feature` の「無停止」フローが毎回 permission prompt で止まる)
- **[auto]** 品質チェックの三層の役割分担を明記(fork = 変更ファイルの自己修復 / `test-runner` = フルスイート 1 回 / CI = 最終ゲート)。CI のトリガー範囲の記述も実態(PR は全ベース、push は main・develop のみ)に修正

## 2026-08-12

- **[manual]** ⚠️ 実装フェーズを `implement-ticket` スキル(`context: fork` / `model: sonnet`)への委譲に変更。司令塔はモデルを切り替えず、実装は Sonnet の subagent が行う。**取り込む側の作業**: `/next-ticket` / `/add-feature` / `/fix-issue` をカスタマイズしている場合、実装ステップを `Skill('implement-ticket')` の呼び出しに置き換える(戻り値 `完了` / `判断待ち` / `失敗` で分岐)。手動の `/model sonnet` 運用をドキュメント化している箇所があれば削除する
- **[manual]** ⚠️ `.claude/rules/` を 2 層に分割。全エージェント共通は `.claude/rules/*.md`(CLAUDE.md が `@` インポート)、司令塔専用は `.claude/rules/lead/*.md`(SessionStart hook が注入)。**取り込む側の作業**: `CLAUDE.md` の `@.claude/rules/...` 行を `@.claude/rules/spec-driven.md` の 1 行だけに減らす(残り 4 本は `lead/` へ移動済みで、hook が注入するため `@` インポートは不要)。カスタム subagent を追加している場合、モデル切替や `/check` 委譲の指示が効かなくなる点に注意する
- **[manual]** PreToolUse hook `check-implementation-phase.sh` を追加(実装フェーズ中のメインセッションからの実装コード編集をブロック)。**取り込む側の作業**: `.claude/settings.json` の `hooks.PreToolUse` に `matcher: "Edit|Write"` のエントリを追加する。テンプレート自体の改修など司令塔が実装すべき作業では、`tasklist.md` に `<!-- main-edit-ok -->` を書いて解除する
- **[auto]** `.claude/agents/implementer.md` / `.claude/skills/implement-ticket/SKILL.md` を新設
- **[auto]** `docs/template-dev/cost-model.md` を新設。ルールファイルは subagent 起動のたびに全量ロードされるため、判断の根拠(実測値・単価)はルールから分離してここに置く

## 2026-08-11

- **[manual]** ⚠️ CLAUDE.md の共通ルールを `.claude/rules/*.md`(モデル運用方針 / スペック駆動 / ブランチ・チケット / コンテキスト管理 / レビュー使い分け)に分割し、CLAUDE.md からの `@` インポートに変更。**取り込む側の作業**: CLAUDE.md の該当節を削除し、代わりに 5 つの `@.claude/rules/...` 行を追記する。プロジェクト固有の追記(MCP の使いどころ・スポーク構成ルールへの参照・ハーネス節)は CLAUDE.md に新設した「プロジェクト固有ルール」節へ移す
- **[manual]** テンプレート追従の仕組みを追加(`.claude/template-manifest.json` / `/sync-template` / 月次 `template-update-check` ワークフロー)。**取り込む側の作業**: マニフェストの `syncedAt` に、いまテンプレートから取り込んだ commit SHA を記入する(以降は `/sync-template` が自動更新する)
- **[auto]** `docs/template-dev/CHANGELOG.md` を新設(このファイル)。`/sync-template` がリモートから直接読むため、`docs/template-dev/` を削除済みのプロジェクトでも動作する
