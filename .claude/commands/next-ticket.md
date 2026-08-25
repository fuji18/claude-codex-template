---
description: GitHub Issues のチケットから次に着手すべきものを選定し、ラベルでステータス管理しながらadd-featureフローで実装する
---

# 次のチケットに着手

GitHub Issues のチケット(`ticket` ラベル付き Issue)を消化するための日常コマンドです。ステータスはラベル(`in-progress`)と open/closed で管理し、チケットファイルの編集・コミットは発生しません。

**引数:** なし(任意で Issue 番号を指定してよい。例: `/next-ticket 12`)

---

## 手順

### ステップ1: チケットの選定

1. チケット Issue の一覧と状態を取得する。**`body` は取得しない**（最大100件分の受け入れ条件・技術メモが丸ごとコンテキストに載り、選定に不要なぶんが以降のターンで再送され続けるため）:
   ```bash
   gh issue list --label ticket --state open --json number,title,labels --limit 100
   ```
   依存関係(`depends: #N`)の判定に必要な行だけを、本文とは別に抜き出す:
   ```bash
   gh issue list --label ticket --state open --json number,body --limit 100 \
     --jq '.[] | "\(.number): \([.body | scan("depends:\\s*#\\d+")] | join(", "))"' | grep -v ': $'
   ```
2. **`in-progress` の Issue が既にある場合**は、新しいチケットに着手せず次の分岐に従う:
   - その Issue に対応するオープン PR がある(`gh pr list` で確認)→ マージ待ち。PR の確認・マージを提案して終了する
   - オープン PR がない → 作業が中断している。対応する `.steering/` を提示して `/resume-work` を案内して終了する
3. 引数で Issue 番号が指定されていればそれを選ぶ。指定がなければ以下の条件で選定する:
   - `in-progress` ラベルが付いていないこと
   - ボディの `depends: #N` で参照される Issue がすべて closed であること
   - 優先度ラベルが最も高いこと(P0 > P1 > P2。同順位ならフェーズ順・番号順)
4. 選定した Issue に **`delegate:codex` ラベルが付いているか**を確認する(ステップ1-1 で取得済みの `labels` を見る。追加の API 呼び出しは不要)。**ラベルの有無は選定順序に影響しない** — 変わるのはステップ3 の実装フェーズの流し方だけ。
5. 選定結果(Issue 番号・タイトル・理由・`delegate:codex` の有無)を 1〜2 行でユーザーに提示してから着手する。

### ステップ2: ステータス更新(着手)

```bash
gh issue edit [番号] --add-label in-progress
```

### ステップ3: 実装

**着手する Issue のボディだけ**をここで取得する(`gh issue view [番号] --json body --jq .body`)。そのボディ(スコープ・受け入れ条件・技術メモ)を要求として、`/add-feature` と同じフロー(ブランチ作成 → steering 計画 → **implement-ticket への委譲** → 並列検証(code-reviewer + test-runner) → 振り返り → コミット・PR)を実行する。

**フェーズごとの担当が分かれている点に注意する**(詳細は `/add-feature` ステップ5):

| フェーズ | 担当 |
| --- | --- |
| Issue 選定・ブランチ作成・steering 計画(requirements / design / tasklist) | 司令塔(Opus) |
| **実装(tasklist の消化)** | **委託(既定 = `delegate-codex.sh impl` / フォールバック = `Skill('implement-ticket')` の Sonnet fork)** |
| 検収の判断・振り返り・コミット・PR | 司令塔(Opus) |

**`delegate:codex` ラベルによる実装フェーズの流し方**(判定基準の全文は `.claude/rules/lead/delegation-policy.md`):

| 状態 | 流し方 |
| --- | --- |
| **ラベルあり** | `design.md` を書き切ったら、**tasklist を分割せず 1 回の `delegate-codex.sh impl` で全体を委託する**(バッチに割らない)。検収は PR 単位で 1 回 |
| ラベルなし | 機械的な項目が 3 つ以上連続する部分を 3 項目前後のバッチで委託し、**各バッチの検収を通してから**次を委託する。機械的な項目が 2 つ以下なら Codex に渡さず `Skill('implement-ticket')` に渡す |

- **計画中(steering)に委託の前提が崩れたらラベルを外す**: 委託禁止領域(`CLAUDE.md`「プロジェクト固有ルール」)に触れる / 新規依存の追加が要る / `design.md` に書き切れない設計判断が残る、のいずれかに当たったら `gh issue edit [番号] --remove-label delegate:codex` を実行し、理由を 1 行でユーザーに伝えてから通常経路に落とす
- **`exit 3`(Codex 利用不可)ではラベルを外さない。** 環境の欠落でありチケットの属性ではないため、Sonnet fork にフォールバックするだけでよい
- ラベルが付いていないチケットを委託候補だと判断した場合は、`gh issue edit [番号] --add-label delegate:codex` を実行してから流す(判断の記録が Issue に残る)

- **司令塔は実装コードを書かない。** モデルの手動切替も不要。分岐は `/add-feature` ステップ5 の**手順ごと**に従う(終了コード表だけでなく、**`exit 3` を一度受けたらそのセッションでは `delegate-codex.sh` を呼び直さない**という恒久フォールバックの手順も含む)
- **`design.md` は、実装者が設計判断を一切せずに実装できる粒度まで書き切る。** fork は会話履歴も Issue 本文も持たず `design.md` / `tasklist.md` だけを読むため、ここの不足がそのまま往復コストになる
- `.steering/` のディレクトリ名は `[YYYYMMDD]-issue[番号]-[短い名前]` とする
- PR ボディに **`Closes #[番号]`** を必ず含める(マージ時に Issue が自動クローズされる)
- Issue に書かれていない機能(P1/P2 の前倒し等)を実装しない

### ステップ4: 作業記録の残置

PR 作成まで完了したら、Issue にコメントで記録を残す(ステータス編集は不要。クローズは PR マージが自動で行う):

```bash
gh issue comment [番号] --body "実装完了。PR: [PR URL] / steering: .steering/[ディレクトリ名]"
```

### ステップ5: 報告

- 完了したチケットと PR URL を報告する
- 残りチケット数と、次に着手可能なチケットを 1 行で提示する
- 次のチケットに移る前の `/clear` を推奨する(コンテキストの持ち越しは不要。CLAUDE.md のコンテキスト管理ルール)
- 全チケットがクローズ済みの場合は、`/sync-docs` の実行と P1 チケットの検討(`/setup-tickets`)を提案する
