---
description: 永続ドキュメントをもとに実装を段階的なチケットに分割し GitHub Issues に登録する(/setup-project 後に実行)
---

# 実装チケットの作成(GitHub Issues)

`/setup-project` で作成した永続ドキュメント(`docs/`)を読み込み、**段階的に実装できるチケット単位**へ分割して **GitHub Issues** に登録するコマンドです。各チケットはそのまま `/next-ticket` で実装に着手できる粒度で作成します。

チケットを git の外(Issues)に置くことで、ステータス更新のためのコミットが不要になり、複数ブランチ・エージェントの並行作業でも競合しません。PR の `Closes #N` でマージ時に自動クローズされます。

**引数:** なし（任意でスコープやエピック名を渡してよい。例: `/setup-tickets 認証まわり`）

---

## 前提

- `/setup-project` 済みで `docs/` に永続ドキュメント（PRD・機能設計など）があること。無い場合はユーザーに `/setup-project` の先行実行を促す。
- `gh auth status` が認証済みであること。未認証・オフラインの場合はその旨を伝えて中断する。
- ハブ&スポーク構成のプロジェクトでは、**`/setup-spoke-standards` を先に済ませておく**こと。`docs/playbook/spoke-development-standards.md` が無い状態でスポーク実装をチケット化しようとしている場合は、先行実行を促す(MUST 項目がチケットの受け入れ条件になるため)。

## 手順

### ステップ0: ドキュメントの読み込み

次を読み、実装対象の全体像と制約を把握する。

1. `docs/product-requirements.md`（何を作るか・ユーザーストーリー・受け入れ条件・成功指標）
2. `docs/functional-design.md`（機能の振る舞い）
3. `docs/architecture.md`（技術構成・非機能要件）
4. `docs/repository-structure.md`（配置）
5. `docs/development-guidelines.md`（実装規約）/ `docs/glossary.md`（用語）
6. 既存実装があれば該当ディレクトリも確認する（広範囲の探索は Explore subagent に委譲）。

### ステップ1: 分割方針の決定

ドキュメントの機能・ユーザーストーリーを、**段階的に実装・検証できる単位**へ分解する。

- **粒度**: 1チケット = おおよそ 1 PR / 半日〜数日。大きすぎるものは分割し、小さすぎるものは束ねる。
- **縦切り優先**: 「画面だけ」「DBだけ」ではなく、ユーザー価値が確認できる薄い縦串を基本にする。
- **依存と順序**: チケット間の依存関係を洗い出し、実装順序（フェーズ）を決める。基盤・共通部分を先に。
- **MVP を明確化**: 最初のフェーズで動くものになるよう、必須チケット(P0)と後回し可能なチケット(P1/P2)を区別する。**Issue として登録するのは P0 のみ**（スコープガード）。P1/P2 は一覧に backlog として示すに留める。
- 各チケットに **受け入れ条件（完了条件）** を必ず付ける。
- **テンプレートのプレースホルダの回収**: `src/index.ts` / `src/index.test.ts` がテンプレートのプレースホルダ（`greet()`）のまま残っている場合、**最初の実装チケットの受け入れ条件に「プレースホルダの削除」を必ず含める**（口頭の申し送りだけでは残り続けるため）。

### ステップ2: チケット計画の提示と承認

全チケットの一覧表を提示する。

| # | タイトル | 概要 | フェーズ | 依存 | 優先度 |
|---|---|---|---|---|---|
| 1 | ... | ... | 1 | - | P0 |

**この一覧をユーザーに提示し、粒度・順序・抜け漏れを確認して承認を得てから次へ進む**（ドキュメント作成の基本ルールに従う）。

### ステップ3: ラベルの準備と Issue の発行

承認後、以下を実行する。

1. **ラベルを作成する**（既存なら skip。`gh label create` は既存時に失敗するが無視してよい）:
   ```bash
   gh label create ticket --color 0E8A16 --description "実装チケット" 2>/dev/null || true
   gh label create P0 --color B60205 --description "必須(MVP)" 2>/dev/null || true
   gh label create P1 --color D93F0B --description "P0後に検討" 2>/dev/null || true
   gh label create P2 --color FBCA04 --description "後回し可" 2>/dev/null || true
   gh label create in-progress --color 1D76DB --description "着手中" 2>/dev/null || true
   ```

2. **依存の少ない順(フェーズ順)に Issue を発行する**（先に発行した Issue の番号を後続の depends 行で参照できるようにするため）:
   ```bash
   gh issue create \
     --title "[チケット] <タイトル>" \
     --label ticket --label P0 \
     --body "## 背景・目的
   <なぜこのチケットが必要か。対応するユーザーストーリー/要求>

   ## メタ
   - フェーズ: 1
   - depends: #<依存するIssue番号>（なければ「なし」）
   - 根拠: docs/functional-design.md「◯◯機能」節 のように**節レベルで具体的に**書く(実装時に該当節だけ読めば済むようにするため)

   ## スコープ（やること）
   - <この PR で実装する範囲>

   ## スコープ外（やらないこと）
   - <混同しやすいが今回はやらない範囲>

   ## 受け入れ条件
   - [ ] <満たすべき完了条件1>
   - [ ] <満たすべき完了条件2>

   ## 技術メモ・参照
   - <関連する設計判断、参照する docs/ の該当節、注意点>"
   ```

### ステップ4: 完了報告

```
実装チケットの作成が完了しました。

✅ GitHub Issues に N 件のチケットを発行（ラベル: ticket / P0）
✅ backlog（P1/P2）: M 件（Issue 未発行。着手時に /setup-tickets で発行）

実装は /next-ticket で着手してください（依存・フェーズ順に自動選定されます）。
進捗は Issue のラベル（in-progress）と open/closed で管理され、
PR マージ時に Closes #N で自動クローズされます。
```

## 完了条件

- 承認済みの P0 チケットがすべて GitHub Issues に発行されている（`ticket` + 優先度ラベル付き）。
- 各 Issue に受け入れ条件・フェーズ・depends があり、`/next-ticket` で着手できる粒度になっている。
- P1/P2 は backlog 一覧としてユーザーに提示されている（Issue 未発行）。
