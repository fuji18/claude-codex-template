<!-- テンプレート所有ファイル: /sync-template で上書きされます。プロジェクト固有のルールは CLAUDE.md の「プロジェクト固有ルール」節に書いてください。 -->
<!-- 司令塔専用: SessionStart hook がメインセッションにのみ注入します。サブエージェントには読み込まれません。 -->

## モデル運用方針(設計 = Opus / 実装 = Sonnet の fork / 委譲 = Sonnet・Haiku)

判断の根拠と実測値は `docs/template-dev/cost-model.md` にある(読み込み対象外)。ここには判断だけを書く。

- **司令塔(メインセッション)は Opus 固定**(`.claude/settings.json`)。計画・設計判断・統合・ユーザーへの報告を担う
- **実装フェーズは `implement-ticket` スキルに委譲する。** `context: fork` + `model: sonnet` で Sonnet のサブエージェントとして走るため、**司令塔はモデルを切り替えない**。実装ループのログは fork の中で完結し、司令塔にはサマリーだけが返る
  - `/next-ticket` / `/add-feature` / `/fix-issue` の実装ステップはすべてこの経路を通る
  - **司令塔が自分で実装コードを書き始めてはいけない。** PreToolUse hook(`check-implementation-phase.sh`)が Edit/Write をブロックする
- **委譲先の既定**: レビュー(`code-reviewer`)・スペック検証(`implementation-validator`)・ドキュメントレビュー(`doc-reviewer`)は Sonnet、品質チェック実行(`test-runner`)は Haiku、広範囲のコード探索は組み込みの Explore
- **subagent への受け渡しは参照で**: spawn プロンプトにファイル内容や Issue 本文を貼らず、パス・Issue 番号だけ渡して subagent 自身に読ませる。返しはサマリーのみを要求する
- **ログの長い作業は司令塔で直接実行しない**: lint・テスト実行は `/check`、docs/ と実装の突き合わせは `/sync-docs` を使い、司令塔にはサマリーだけを残す
- **Fable 5 は最難関タスクのみ**(難度の高い設計、根本原因不明の調査)。`/model fable` で一時切替し、完了後 `/model opus` に戻す
- Agent Teams を使う場合、teammates は Sonnet を指定する(spawn プロンプトに明記)
- ハーネス層の追加・更新は `/harness-setup` を使う

### fork の戻り値による分岐(when X, do Y)

| 戻り値 | 司令塔の動き |
| --- | --- |
| `完了` | 検収(`code-reviewer` + `test-runner`)へ進む |
| `判断待ち` | 判断を下し、**`design.md` に追記してから**再度 `implement-ticket` を呼ぶ(tasklist の途中から再開される) |
| `失敗` | 原因を分析する。設計起因なら `design.md` を修正、根本原因が不明なら `/model fable` への一時切替を検討する |

**1 チケットで往復が 2 回を超えたら `design.md` の粒度不足のサイン。** 計画フェーズで「Sonnet が設計判断なしで実装できる粒度」まで書き切れているか見直す。ここの詰めが甘いと往復のコストが委譲の利得を食い潰す。

### 参照実装は司令塔が書く

P0 の基盤や新しいパターンの 1 例目は品質のレバレッジが最大なので、`design.md` に実装内容を書き切る形で司令塔が主導する。2 例目以降の横展開が fork の主戦場。

### fork を使わない手動切替(フォールバック)

テンプレート自体の改修など、fork 経路を通らない作業で実装が長引く場合のみ使う。

1. `/clear` してから `/model sonnet`
2. 完了後、`/clear` してから `/model opus`

**切替の前に必ず `/clear` する。** プロンプトキャッシュはモデル単位で分かれるため、膨らんだ文脈を抱えたまま切り替えると全体がキャッシュミスとなり全額課金される。計画直後はコンテキストが最も膨らんでいるので、そのまま切り替えるのが最も高くつく。
