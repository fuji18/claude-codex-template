---
description: GitHub Issues のチケットから次に着手すべきものを選定し、ラベルでステータス管理しながらadd-featureフローで実装する
---

# 次のチケットに着手

GitHub Issues のチケット(`ticket` ラベル付き Issue)を消化するための日常コマンドです。ステータスはラベル(`in-progress`)と open/closed で管理し、チケットファイルの編集・コミットは発生しません。

**引数:** なし(任意で Issue 番号を指定してよい。例: `/next-ticket 12`)

---

## 手順

### ステップ1: チケットの選定

選定は**判定スクリプトに任せる**(`/autopilot` とローカルループも同じ判定を使う。散文の規則を経路ごとに持たない)。GitHub へは REST だけで触るので、GraphQL が使えないクラウドセッションでも動く:

```bash
bash .claude/scripts/autopilot-next.sh --summary   # 人間向け
bash .claude/scripts/autopilot-next.sh             # JSON(action / target / ready / attention / stalled / slots)
```

終了コード 2 は取得の失敗(gh 未認証等)。原因を報告して止まる。**Issue の `body` は取得しない**(選定に要る `depends:` と `Closes #N` はスクリプトが抜き出す)。

1. **引数で Issue 番号が指定された場合**:
   - その Issue が `stalled`(`in-progress` だが open PR が無い)に入っていて、**対応するブランチ(`git branch -a` で `issue[番号]-` を含むもの。`issue12` が `issue123` に当たらないよう区切りの `-` まで照合する)か `.steering/*-issue[番号]-*` がある** → 中断した作業の再開。そのブランチに移り、`.steering/` を `/resume-work` と同じ手順で再開する(ステップ3 の「ブランチの準備」は飛ばす)。どちらも無ければ `/autopilot` が着手直前に付けたラベルなので、新規着手として扱う
   - open PR がある → 着手済み。`/fix-pr [PR番号]` を案内して終了する
   - それ以外 → そのまま選ぶ(WIP 上限は見ない。指定した人・`/autopilot` が判断済み)
2. **指定が無い場合**は `action` で分岐する:

| action | 動き |
| --- | --- |
| `fix` | 進行中の PR に要対応(コンフリクト / CI 失敗 / 変更要求)がある。新規着手より先に `/fix-pr [target]` を案内して終了する(マージが早まると後続の依存も解ける) |
| `start` | `target` を選ぶ(依存が全部 closed・未着手・優先度 P0 > P1 > P2 → 番号順)。**他のチケットがレビュー待ちでも、空き枠(`slots`)があれば着手してよい** |
| `wait` | 空き枠が無い、または着手できるものが無い。オープン PR の確認・マージを提案して終了する。`stalled` があれば対応する `.steering/` を示して `/resume-work` を案内する |
| `blocked` | 依存が閉じず着手できない。`blocked` の一覧(`waitingOn`)を示して終了する |
| `done` | ステップ5 の「全チケットがクローズ済み」と同じ提案をして終了する |

   空き枠の上限は `.claude/autopilot.json` の `maxInFlight`(既定 2)。in-progress の open チケットと、チケットに紐づく open PR の和集合を数える。
3. 選定した Issue に **`delegate:codex` ラベルが付いているか**を確認する(`gh api repos/{owner}/{repo}/issues/[番号] --jq '[.labels[].name]'`)。**ラベルの有無は選定順序に影響しない** — 変わるのはステップ3 の実装フェーズの流し方だけ。
4. 選定結果(Issue 番号・タイトル・理由・`delegate:codex` の有無・レビュー待ちで並行している PR があればその番号)を 1〜2 行でユーザーに提示してから着手する。

### ステップ2: ステータス更新(着手)

```bash
gh issue edit [番号] --add-label in-progress
```

### ステップ3: 実装

**ブランチの準備(並行着手のための追加規則)**: 現在のブランチが**別チケットの open PR の head**(`autopilot-next.sh` の `prs[].head`)なら、そのブランチを使い回さない。`/add-feature` ステップ1.5 の (a) を適用せず、`git fetch origin [baseBranch] && git switch -c feature/[YYYYMMDD]-issue[番号]-[短い名前] origin/[baseBranch]` で base から切り直す(チケットのブランチを積み重ねると、前の PR の差分が次の PR に混ざる)。作業ツリーが汚れていれば先に止まって報告する。

**着手する Issue のボディだけ**をここで取得する(`gh issue view [番号] --json body --jq .body`。クラウドでは `mcp__github__issue_read`)。そのボディ(スコープ・受け入れ条件・技術メモ)を要求として、`/add-feature` と同じフロー(ブランチ作成 → steering 計画 → **implement-ticket への委譲** → 並列検証(code-reviewer + test-runner) → 振り返り → コミット・PR)を実行する。

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

- **計画中(steering)に委託の前提が崩れたらラベルを外す**: 委託禁止領域(`.claude/rules/lead/delegation-policy.md` の一覧 / 全量は `--print-forbidden`)に触れる / 新規依存の追加が要る / `design.md` に書き切れない設計判断が残る、のいずれかに当たったら `gh issue edit [番号] --remove-label delegate:codex` を実行し、理由を 1 行でユーザーに伝えてから通常経路に落とす
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
- 残りチケット数と、次に着手可能なチケットを 1 行で提示する(`autopilot-next.sh --summary`。レビュー待ちの間も空き枠があれば次に着手できる)
- 次のチケットに移る前の `/clear` を推奨する(コンテキストの持ち越しは不要。CLAUDE.md のコンテキスト管理ルール)。繰り返しを人手でやりたくない場合は `/autopilot` を案内する
- 全チケットがクローズ済みの場合は、`/sync-docs` の実行と P1 チケットの検討(`/setup-tickets`)を提案する
