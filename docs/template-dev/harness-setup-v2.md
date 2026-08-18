# ハーネスエンジニアリング基盤 — 設計判断の記録(v2 統合版)

> **正式版**: `.claude/skills/harness-setup/SKILL.md` としてインストール済み。`/harness-setup` で起動する。
> このファイルは壁打ちの成果物として、v1(`harness-setup-v1-draft.txt`)からの設計判断だけを記録する。

## 採用した設計判断

### 1. モデル戦略: 司令塔 = Opus / 委譲 = Sonnet

Fable 5 はトークン消費が大きい($10/$50 per MTok。Opus 4.8 の 2 倍、Sonnet 5 の 3 倍超)ため:

- **司令塔(メインセッション)**: Opus 4.8。`.claude/settings.json` の `"model": "opus"` で固定
- **委譲作業**: Sonnet。全 worker subagent(code-reviewer / doc-reviewer / implementation-validator 等)の frontmatter を `model: sonnet` に。Agent Teams の teammates も Sonnet 指定
- **Fable 5**: 最難関の設計・調査時のみ `/model fable` で一時切替

### 2. 既存スペック駆動体系との統合(重複機構の廃止)

| v1 の機構 | 統合先 |
|---|---|
| planner subagent / product_spec / feature_list.json | `/setup-project` + `/setup-tickets` + steering スキル モード1 |
| progress.md + UserPromptSubmit 強制注入 | `.steering/*/tasklist.md` + `/resume-work` + auto-memory |
| changelog.md / 振り返り | steering スキル モード3 |
| snapshots/(バックアップ) | 組み込み checkpointing + `/rewind` |
| pr-prep skill | `/check` + `/commit` + `/fix-issue` + `/code-review ultra` |
| CLAUDE.md 新規生成 | 既存 CLAUDE.md への「ハーネス」節追記 |

`.harness/` に残すのは既存体系に相当機能がないものだけ: `decisions.jsonl`(横断的判断ログ)/ `state.json` / `team_runbook.md`。

### 3. 最新化(2026-07 時点で公式情報を検証済み)

- 対象モデル: Opus 4.7 → **Claude 5 世代(Fable 5 / Opus 4.8)**。「過剰に規範的なプロンプトは品質を下げる」「委譲は抑制ではなく活用」「effort は high 開始で sweep」が公式ガイダンス
- Agent Teams(v2.1.178+): `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` は引き続き必要。**クリーンアップは自動化**され「Clean up the team」指示は不要に。表示モードのデフォルトは `in-process`。subagent 定義の `skills`/`mcpServers` frontmatter は teammate に非適用
- `/ultrareview` → `/code-review ultra`(deprecated エイリアス)
- 危険コマンドは `permissions.deny` を第一防衛線に(hook スクリプトはパターン検査専用に縮小)
- lint/typecheck hook は `async: true` + `|| true`(同期実行による編集ブロックを回避)
- code-reviewer には coverage-first の報告方針(Claude 5 世代は重大度フィルタ指示に忠実すぎて recall が下がるため)

## 導入済みの実体(このテンプレート)

- `.claude/skills/harness-setup/SKILL.md` — ハーネス層を対話的に追加するスキル
- `.claude/agents/code-reviewer.md` — sonnet worker(既存 doc-reviewer / implementation-validator も sonnet)
- `.claude/settings.json` — `"model": "opus"`(司令塔固定)
- `CLAUDE.md` — 「モデル運用方針」節

hooks / permissions.deny / Agent Teams 有効化 / `.harness/` の生成は、プロジェクトの検証コマンドが確定してから `/harness-setup` の対話で行う。
