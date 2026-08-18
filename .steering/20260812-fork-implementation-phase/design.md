# 設計: 実装フェーズの fork 委譲と rules の役割分割

## 全体構成

```
司令塔(Opus・メインセッション)
├── 読み込む: CLAUDE.md + .claude/rules/*.md + [SessionStart hook 注入] .claude/rules/lead/*.md
├── 担当: チケット選定 / steering 計画 / 判断 / 検収 / commit / PR
└── implement-ticket スキルを呼ぶ
      ↓ context: fork（会話履歴は引き継がれない）
    implementer(Sonnet・サブエージェント)
    ├── 読み込む: CLAUDE.md + .claude/rules/*.md のみ（lead/ は載らない）
    ├── 担当: design.md / tasklist.md に従った実装のみ
    └── 停止条件に当たったら即座に報告して終了
```

## 1. rules の役割分割

| 配置 | 読まれる範囲 | 載せ方 |
| --- | --- | --- |
| `.claude/rules/*.md` | 司令塔 + **全サブエージェント** | CLAUDE.md が `@` インポート |
| `.claude/rules/lead/*.md` | **司令塔のみ** | SessionStart hook が stdout に出して注入 |

`.claude/rules/` に残すのは `spec-driven.md`(実装前の確認 / スコープガード / 完了報告と回復 / ステアリング)のみ。それ以外は `lead/` に移す。判断の根拠(実測値・単価の説明)は `docs/template-dev/cost-model.md` に退避し、rules には `when X, do Y` だけを残す。

## 2. implementer エージェント

`.claude/agents/implementer.md`(`model: sonnet`、tools は Read / Edit / Write / Bash / Grep / Glob)。

**停止条件**(いずれかに当たったら実装を止めて報告し、自力で解決しない):

- `design.md` に書かれていない設計判断が必要になった
- 同じエラーの修正に 2 回連続で失敗した
- `design.md` / `tasklist.md` が存在しない

`Agent` ツールを持たないため、`/check`(test-runner への委譲)は使えない。品質チェックは npm スクリプトを直接実行する。この読み替えをエージェントのプロンプトに明記する(CLAUDE.md 経由で読む共通ルールと矛盾するため)。

返却は固定フォーマット(判定 / 変更ファイル / 残タスク / 品質チェック / 詳細)で 20 行以内。司令塔のコンテキストに永続的に残るため。

## 3. implement-ticket スキル

`.claude/skills/implement-ticket/SKILL.md`:

```yaml
context: fork
agent: implementer
model: sonnet
background: false
```

`background: false` は必須(背景実行ではツールセットが狭まり、編集が `/rewind` の対象外になる)。引数でステアリングディレクトリを受け取り、省略時は最新の `.steering/*/` を自動検出する。

## 4. 逸脱の強制ブロック

`.claude/scripts/check-implementation-phase.sh`(PreToolUse / matcher `Edit|Write`)。

以下の**すべて**を満たすときだけ `exit 2` でブロックする:

1. 入力 JSON に `agent_id` が無い(= メインスレッドからの編集)
2. `.steering/*/` に `design.md` があり、`tasklist.md` に未完了タスク(`- [ ]`)が残っている
3. 編集対象が `.steering/` / `docs/` / `.claude/` / `.github/` の外(= 実装コード)

これにより「fork が判断待ちで戻ってきたので司令塔が design.md を直す」は通り、「司令塔が自分で実装を始める」だけが止まる。検収フェーズ(tasklist が全て `[x]`)では発火しないため、code-reviewer の指摘対応は司令塔が直接行える。

脱出弁: `tasklist.md` に `<!-- main-edit-ok -->` を書くと解除される。

## 5. コマンドの書き換え

`/next-ticket` / `/add-feature` / `/fix-issue` の実装ステップを、`Skill('implement-ticket')` の呼び出しに置き換える。呼び出し前に作業ツリーがクリーンであることを確認する(fork の編集は `/rewind` で戻せない可能性があるため、git を退避手段として確保する)。

戻り値による分岐:

- `完了` → 検収(code-reviewer + test-runner)へ進む
- `判断待ち` → 司令塔が判断し **design.md に追記**してから再度呼ぶ
- `失敗` → 司令塔が原因を分析する(設計起因なら design.md を修正、根本原因不明なら `/model fable` を提案)

## 6. 権限方針

方針 A(`allowed-tools` のみ、`settings.json` は広げない)を採る。実装に要る npm / npx / git status・diff は既に `settings.json` の allow に入っているため、追加の恒久的な権限拡大は行わない。スキル側にも同じ範囲を `allowed-tools` として書き、設定が乖離しても自己完結するようにする。

## 影響ファイル

- 新規: `.claude/rules/lead/planning.md` / `.claude/agents/implementer.md` / `.claude/skills/implement-ticket/SKILL.md` / `.claude/scripts/check-implementation-phase.sh` / `docs/template-dev/cost-model.md`
- 移動: `.claude/rules/{model-strategy,context-management,review-policy,branch-and-tickets}.md` → `lead/`
- 更新: `.claude/rules/spec-driven.md` / `.claude/hooks/session-start.sh` / `.claude/settings.json` / `.claude/commands/{next-ticket,add-feature,fix-issue}.md` / `CLAUDE.md` / `README.md` / `docs/template-dev/CHANGELOG.md`
- `.claude/template-manifest.json` は `.claude/rules/` をディレクトリ単位で `owned` にしているため変更不要
