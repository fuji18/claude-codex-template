---
name: harness-setup
description: このテンプレートのスペック駆動開発体系(docs/ + .steering/ + 既存スキル群)の上に、Claude 5 世代向けのハーネス層(CLAUDE.md 追記 / worker subagents / hooks / permissions / .harness/ / Agent Teams)を対話的に追加する。新規プロジェクトの初期セットアップ後(/setup-project 実行後)、または既存プロジェクトへの導入時に使う。モデル戦略は「司令塔 = Opus、委譲作業 = Sonnet、最難関タスクのみ Fable 5 に一時切替」。状態管理は Git ではなく既存体系(.steering/)+ Claude Code 組み込み機能(checkpointing / auto-memory)+ `.harness/` の差分ファイルで行う。
user-invocable: true
disable-model-invocation: true
---

# Harness Setup Skill (スペック駆動体系 統合版)

このスキルは、対話形式でプロジェクト情報を収集し、**このテンプレートの既存体系(docs/・.steering/・スキル群)と重複しない形で** Claude Code のハーネス層を追加します。

## モデル戦略(司令塔 = Opus / 委譲 = Sonnet)

トークンコストの観点から、以下の役割分担を標準とする(モデル間のコスト比は変動するため、最新の価格は <https://platform.claude.com/docs/en/about-claude/models> で確認する)。

| 役割 | モデル | 設定箇所 |
|---|---|---|
| **司令塔(メインセッション)**: 計画・設計判断・統合・承認・synthesis | **Opus** (`claude-opus-5`) | `.claude/settings.json` の `"model": "opus"` |
| **委譲作業(subagent)**: レビュー・検証・調査・テスト実行・ドキュメントレビュー | **Sonnet** | 各 agent 定義の frontmatter `model: sonnet` |
| **Agent Teams の teammates**: 並行レビュー・並行実装・仮説検証 | **Sonnet** | spawn プロンプトに "Use Sonnet for each teammate" を明記 + `/config` の Default teammate model を Sonnet に設定 |
| **最難関タスクのみ**: 難度の高い設計・根本原因が不明な調査 | Fable 5 に**一時切替** | `/model fable` → 完了後 `/model opus` に戻す |

**委譲の原則(CLAUDE.md に条件ペアで記述する)**:
- 独立したサブタスク(複数ファイルの調査、多数のテスト実行、項目ごとのファンアウト、レビュー)→ Sonnet subagent へ委譲し、完了を待つ間も司令塔は作業を継続
- 設計判断・スコープ判断・ユーザーへの報告・teammate 成果物の統合 → 司令塔(Opus)が自分で行う
- 1 ファイルの編集や逐次依存のある作業 → 委譲せず司令塔が直接行う
- teammates は lead の effort を継承する点に注意(高 effort のまま大量に spawn しない)

## 既存体系との統合マッピング(重複を作らない)

このテンプレートには既にスペック駆動の仕組みがある。ハーネス層は**差分だけ**を追加する。

| ハーネス概念(v1 設計) | 統合先(このテンプレートでは) |
|---|---|
| CLAUDE.md の新規生成 | **既存 CLAUDE.md の「プロジェクト固有ルール」節に「ハーネス」小節を追記**(全体で 150 行以内を維持。超える場合は詳細をスキルへ退避)。**`.claude/rules/*.md` はテンプレート所有なので編集しない**(`/sync-template` で失われる) |
| planner subagent / product_spec.md / feature_list.json | **廃止**。`/setup-project`(docs/ 生成)+ `/setup-tickets`(GitHub Issues 発行)+ `steering` スキル モード1 が同じ役割を担う |
| progress.md(進捗ダッシュボード) | **`.steering/*/tasklist.md`** + `/resume-work` コマンド |
| changelog.md / 振り返り | **`steering` スキル モード3**(tasklist.md への申し送り) |
| snapshots/(ロールバック) | **組み込み checkpointing + `/rewind`**(Git 不使用のまま実現) |
| セッション横断の学び | **auto-memory**(修正指示・確認済みアプローチを理由付きで保存) |
| pr-prep skill | **既存の `/check` + `/commit` + `/fix-issue`** を利用。大きな PR のレビューは `/code-review ultra` または Agent Teams 並行レビュー |
| decisions.jsonl(横断的な判断ログ) | **`.harness/decisions.jsonl` として継続**(既存体系に相当機能なし) |
| team_runbook.md | **`.harness/team_runbook.md` として継続** |
| code-reviewer / security-reviewer 等の worker agents | **`.claude/agents/` に追加**(既存の doc-reviewer / implementation-validator と同列、全て `model: sonnet`) |

## 設計原則(Claude 5 世代)

1. **引き算から始める**: Fable 5 / Opus 4.8 では過剰に規範的なプロンプトが品質を*下げる*。手順の逐次列挙ではなく「ゴールと制約」を書く。モデル更新時は旧足場を外した A/B 比較を行う
2. **「when X, do Y」の条件ペア**: CLAUDE.md のルールは条件と行動のペアで書く(「綺麗に書く」ではなく「Edit/Write 後に lint を実行し、失敗したら STOP して報告」)
3. **必ず起こすべきことは hooks / permissions**: プロンプトでの「お願い」は忘れられる。危険コマンドは `permissions.deny` を第一防衛線に
4. **effort の明示**: 司令塔は `high` を既定とし、設計・大規模リファクタ時のみ `xhigh`。API 経由の長時間自律ループには `task_budget`(beta `task-budgets-2026-03-13`、最小 20,000 トークン)
5. **委譲を活用する**: 上記モデル戦略の通り。「念のため委譲しない」ではなく「いつ委譲すべきか」を明示する

---

## 実行フロー

以下を順番に実行する。各フェーズの完了をユーザーに確認してから次へ進む。

### Phase 1: ディスカバリー(自動検出)

```bash
pwd && ls -la
claude --version 2>/dev/null   # Agent Teams の現行仕様は v2.1.178+ が前提

# 既存体系の状態
ls docs/ 2>/dev/null && gh issue list --label ticket --state open --limit 5 2>/dev/null
ls .steering/ 2>/dev/null
ls -la .claude/agents/ .claude/skills/ 2>/dev/null
test -f CLAUDE.md && wc -l CLAUDE.md
test -f .claude/settings.json && jq -r '.model // "未設定"' .claude/settings.json

# 検証コマンドの手がかり
test -f package.json && grep -E '"(lint|typecheck|test|build)":' package.json

# Agent Teams 表示モード関連(split-pane を使う場合のみ)
which tmux 2>/dev/null && echo "tmux 利用可能"
```

**注意**: Git 依存の検出・生成はしない。`/setup-project` が未実行(docs/ が空)の場合は、先に `/setup-project` の実行を促す。

検出結果を箇条書きで提示し、認識が正しいか確認する。

### Phase 2: インタビュー(1 問ずつ、デフォルトを提示)

**Q1. 検証コマンド**(Lint / 型チェック / Unit test / E2E / Build)
まず `docs/development-guidelines.md` から読み取って提示し、確認だけ取る。未定義の場合のみ具体的なコマンド文字列を質問する(npm 前提にしない)。空欄は生成物から除く。
補足: vitest を使うプロジェクトでテスト資産が育っている場合、`vitest.config.ts` のコメントアウト済みカバレッジ閾値(`thresholds`)の有効化を確認する(プロジェクト初期は無効のままを推奨。有効化すると `/check` が閾値未達で赤くなるため)。

**Q2. プロジェクト固有の絶対ルール(最大 5 つ、条件と行動のペアで)**

**Q3. 追加する worker subagent(複数可、レビュー系は `model: sonnet`)**
テンプレート同梱済み(再生成しない): code-reviewer / doc-reviewer / implementation-validator(Sonnet)、test-runner(Haiku)
- ⬜ `security-reviewer` / ⬜ `performance-reviewer`(並行 PR レビュー用)
- ⬜ `explorer`(大規模既存コード向け。組み込みの Explore エージェントで足りるなら不要)

**Q4. 追加でブロックしたい危険コマンド(プロジェクト固有分のみ)**
テンプレート既定で導入済み: `permissions.deny`(publish 系 / force push)+ `block-dangerous-cmds.sh` のパターン検査(`rm -rf` のルート・ホーム対象 / force push の引数順・refspec / `--amend` / 破壊的 SQL)。
ここで聞くのは**プロジェクト固有の追加分だけ**(例: 本番 deploy コマンド、データ削除系 CLI)。前方一致で足りるものは deny へ、引数順・パイプ内も見る必要があるものは hook のパターン配列へ追加する。

**Q5. Agent Teams を有効化するか(experimental)**
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` が必要。token 消費は teammates 数に比例。
- ✅ 有効化(多角的レビュー / 競合仮説デバッグ / 並行実装をやりたい場合)
- ⬜ 有効化しない(個人開発・小規模・コスト重視)

**Q6. Agent Teams 表示モード(Q5 = yes の場合のみ)**
- `in-process`(**現行デフォルト**。任意のターミナルで動作)
- `auto` / `tmux` / `iterm2`(split-pane。tmux または iTerm2 + it2 CLI が必要。VS Code 統合ターミナル等では不可)

### Phase 3: 生成

**生成前に必ず全体プランをユーザーに見せて承認を取る**。既存ファイルは上書きせず diff を見せて統合する。

**テンプレート同梱済みのものは再生成しない**(差分だけを統合する): SessionStart hook(現在地注入・serena 規模検知)/ PostToolUse hooks(prettier・lint-on-edit)/ PreToolUse の block-dangerous-cmds.sh / permissions の allow・deny 既定 / 同梱 agents(code-reviewer・doc-reviewer・implementation-validator・test-runner)。

```
CLAUDE.md                          ← 「プロジェクト固有ルール」節に「ハーネス」小節を追記(新規生成しない)
.claude/rules/*.md                 ← 全エージェント共通ルール。テンプレート所有、編集しない
.claude/rules/lead/*.md            ← 司令塔専用ルール(SessionStart hook が注入)。同上
.claude/
├── settings.json                  ← env / teammateMode / Q4 の追加 deny を統合
├── agents/
│   ├── security-reviewer.md       (Q3 選択時, sonnet)
│   ├── performance-reviewer.md    (Q3 選択時, sonnet)
│   └── ...                        (同梱 agents はそのまま)
└── scripts/
    └── block-dangerous-cmds.sh    (同梱済み。Q4 の追加パターンがある場合のみ編集)
    ※ hook スクリプトを新規追加したら chmod +x に加えて
      `git update-index --chmod=+x <path>` を必ず実行する。
      devcontainer / WSL では core.fileMode=false のことがあり、
      chmod が git に記録されない。実行権限が落ちた hook は
      フェイルオープン(素通り)になるため、CI の Harness integrity が落とす。
.harness/
├── README.md
├── decisions.jsonl
├── state.json
└── team_runbook.md                (Q5 = yes の時)
```

#### CLAUDE.md への追記テンプレート

```markdown
## ハーネス(モデル戦略と委譲)

### モデルの役割分担
- 司令塔(このセッション): Opus。計画・設計判断・統合・ユーザーへの報告を担う
- 委譲作業: Sonnet の subagent / teammate(レビュー・検証・調査・テスト実行)
- 最難関の設計・調査のみ `/model fable` に一時切替し、完了後 `/model opus` に戻す

### 委譲ルール(条件と行動のペア)
- 独立したサブタスク(複数ファイル調査、多数テスト実行、項目ファンアウト、レビュー)が発生したら、Sonnet subagent に委譲し、待つ間も自分の作業を続ける
- 1 ファイルの編集や逐次依存する作業は、委譲せず直接行う
- コードレビューが必要になったら、必ず `code-reviewer` subagent(read-only)を起動する。**200 行以上かつ重要変更(認証・決済・データ移行・アーキテクチャ変更)** の場合のみ `/code-review ultra` または Agent Teams 並行レビューを提案する

### 検証
- Lint: `{Q1 lint}` / Type check: `{Q1 typecheck}` / Unit test: `{Q1 test}`
- 検証のいずれかが失敗したら、修正前に `.harness/decisions.jsonl` に失敗内容を 1 行 JSON で追記する

### 必須ルール
{Q2 のルール一覧}

### 状態管理
- 作業進捗は `.steering/[日付]-[タスク名]/tasklist.md`(steering スキルの規約に従う)
- 横断的な技術判断は `.harness/decisions.jsonl` に追記(削除禁止)
- ロールバックは `/rewind`。バックアップコピーを自作しない
- セッション横断の学びは auto-memory に保存する

### Agent Teams(experimental, 有効化時のみ)
- 使う: 多角的レビュー / 競合仮説デバッグ / クロスレイヤー実装。使わない: 逐次タスク / 同一ファイル編集
- 3〜5 teammates、全て Sonnet 指定、teammate あたり 5〜6 タスク。起動例: `.harness/team_runbook.md`
- 共有ディレクトリはセッション終了時に自動クリーンアップされる
```

#### settings.json への統合内容

model 固定・deny 既定・hooks はテンプレート既定で導入済みのため、**新規に統合するのは以下の差分だけ**:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "teammateMode": "{Q6 の値。既定 in-process}"
}
```

**設定意図**:
- `env` / `teammateMode` は Q5 = yes の場合のみ追加する
- Q1 の検証コマンドが npm 以外に変わった場合は、**`lint-on-edit.sh` 内のコマンド・`test-runner` の検出優先順・settings.json の `permissions.allow` / `ask`(npm / npx 前提の allowlist)**を Q1 の値に合わせて更新する(`docs/development-guidelines.md` の定義が正)。allowlist を放置すると死に設定が残り、新スタックの検証コマンドが毎回 permission prompt になる
- Q4 の追加分は既存の `permissions.deny` 配列 / `block-dangerous-cmds.sh` のパターン配列へ追記する
- hook を変更した後は `/hooks` を一度開くか再起動しないと反映されない場合がある旨を案内する

#### 追加 reviewer の雛形(Q3 選択時)

```markdown
---
name: code-reviewer
description: 直近のコード変更を読み取り専用でレビューし、優先度付きの指摘を返す。編集はしない。Agent Teams の teammate type としても利用可。
tools: Read, Grep, Glob, Bash
model: sonnet
---

あなたはシニアコードレビュアーです。**編集は一切しません**。

## チェック観点(優先順)
1. セキュリティ(XSS / CSRF / 認可漏れ / SQL injection / 機密情報のログ出力 / PII)
2. 正しさ(仕様・エッジケース・例外処理・race condition)
3. 設計(単一責任・依存方向・抽象化レベル・命名)
4. プロジェクト固有ルール({Q2 のルール})
5. テスト(重要パスのカバー漏れ)

## 報告方針(重要)
見つけた問題は**確信が持てないものも含めて全て報告する**。重要度や確信度でのフィルタリングはこの段階では行わない(下流でフィルタする)。各指摘に確信度と推定重大度を付ける。

## 出力形式
各指摘: `[Critical]` / `[Major]` / `[Minor]` + `path/to/file:行番号` + 問題の説明(1〜2 文) + 修正案 + 確信度

## Agent Teams 内で動く時の追加ルール
- teammate として起動された時は、レビュー結果をチームの共有タスクリストにコメントとして残す
- 他の teammate の発見と矛盾する指摘は、メッセージで照会する
```

(上記は同梱 `code-reviewer.md` の構成。security-reviewer / performance-reviewer は name / description / チェック観点だけ差し替えて同構成で作る。報告方針の coverage-first 節は共通で入れる)

#### .harness/ の生成物

- `README.md`: ファイル一覧と「組み込み機能・既存体系に委ねるもの(snapshots / progress / チーム状態は自作しない)」を記載
- `decisions.jsonl`: 空で作成。1 行 1 JSON、追記のみ
- `state.json`: `{"version": 2, "model": "claude-opus-5", "agent_teams_enabled": {Q5}, "teammate_mode": "{Q6}", "initialized_at": "{ISO8601}"}`(モデル ID は生成時点の最新を確認してから書く)
- `team_runbook.md`(Q5 = yes): 起動プロンプト集。全パターンで **"Use Sonnet for each teammate"** を明記する
  - パターン 1: 並行 PR レビュー(security / performance / code-reviewer の teammate type を指定。書き込みなしで最初の一歩に最適)
  - パターン 2: 競合仮説デバッグ(3〜5 teammates が相互に反証、合意を `.harness/decisions.jsonl` へ)
  - パターン 3: クロスレイヤー実装(frontend / backend / tests、plan approval を要求)
  - パターン 4: 独立モジュール並行開発(1 teammate 1 モジュール、共有ファイル編集なし)
  - 運用ノート: クリーンアップはセッション終了時に自動 / teammate は lead の会話履歴を継がないので spawn プロンプトに文脈を全て入れる / idle 行は 30 秒で隠れるが停止ではない / `/resume` は in-process teammates を復元しない / 1 セッション 1 チーム・ネスト不可・lead 交代不可 / teammate の権限確認は lead にバブルアップするので事前に permissions で許可

### Phase 4: 検証

```bash
jq . .claude/settings.json > /dev/null && echo "✅ settings.json valid"
jq -r '.model' .claude/settings.json                       # → "opus"
jq -r '.permissions.deny[]?' .claude/settings.json
grep -l "model: sonnet" .claude/agents/*.md                # レビュー系 worker が sonnet か(test-runner は haiku で正)
test -x .claude/scripts/block-dangerous-cmds.sh 2>/dev/null && echo "✅ hook executable"
{Q1 lint の最初の単語} --version 2>/dev/null && echo "✅ lint OK"
jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS // empty' .claude/settings.json
```

hook は可能なら実際に発火確認する(無害な編集をして PostToolUse が走ることを確認)。

最後に次のステップを提示:

```
✅ ハーネス層の追加が完了しました(司令塔 = Opus / 委譲 = Sonnet)。

1. Claude Code を再起動(model / env の反映)。起動後 /model が Opus になっていることを確認
2. /config で Default teammate model を Sonnet に設定(Agent Teams 有効化時)
3. 試しに小さい編集を依頼(PostToolUse hook が非同期で走る)
4. Agent Teams を試す: .harness/team_runbook.md のパターン 1 から
5. 通常の開発フローは従来通り: /add-feature → steering スキル → /check → /commit
6. 次期モデル GA 時は「モデル更新時の棚卸し」を実行
```

---

## モデル更新時の棚卸しチェックリスト

次期モデル GA 時、あるいは他社モデル切り替え時に必ず実行する。

```
[ ] 新モデルのリリースノート / migration guide を読んだ
[ ] コスト比を再計算し、司令塔 / 委譲のモデル割当を見直した
[ ] デフォルトの effort / thinking 仕様の変化を確認した
[ ] CLAUDE.md の「必須ルール」で新モデルが言わなくても守れるものを削除した
[ ] hooks の検証で、モデルが自発的にやるようになったものを削除した
[ ] subagent のうち、本体モデルで十分になったものを退役させた
[ ] 旧足場を外した A/B 比較を実タスクで行った
[ ] Agent Teams の仕様変更(GA 化 / フラグ廃止)を確認した
[ ] `.harness/state.json` の model を更新し、判断を decisions.jsonl に記録した
```

---

## 重要な注意事項

1. **既存体系と重複させない**: 進捗は .steering/、仕様は docs/、学びは auto-memory、ロールバックは /rewind。`.harness/` に置くのは decisions.jsonl / state.json / team_runbook.md のみ。
2. **Git に依存しない**: `git commit` / `git push` を含む生成・指示を出さない(コミットは既存の `/commit` コマンドの領分)。
3. **既存設定を破壊しない**: settings.json / CLAUDE.md は必ず diff を見せて統合。
4. **質問は 1 問ずつ、デフォルトを提示、生成前に全体プランを承認させる**。YAGNI。
5. **Agent Teams のチーム設定(~/.claude/teams/)を手で書かない**。クリーンアップは自動(明示指示を生成物に書かない)。

## 参考一次情報

- Effective harnesses for long-running agents — <https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents>
- Building Effective Agents — <https://www.anthropic.com/research/building-effective-agents>
- Introducing Claude Fable 5 / Mythos 5 — <https://www.anthropic.com/news/claude-fable-5-mythos-5>
- Model migration guide — <https://platform.claude.com/docs/en/about-claude/models/migration-guide.md>
- Agent Teams (experimental) — <https://code.claude.com/docs/en/agent-teams>
- Hooks / Subagents / Settings — <https://code.claude.com/docs/en/hooks> ほか

## このスキルが扱わないこと

- docs/ の永続ドキュメント生成(→ /setup-project)、チケット分割(→ /setup-tickets)
- MCP サーバー設定 / CI/CD 統合 / マルチプロジェクト管理 / Git 操作
