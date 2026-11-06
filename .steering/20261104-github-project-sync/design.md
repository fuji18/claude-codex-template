# design: GitHub Projects を開発サイクルのダッシュボードにする

<!-- status: ready -->

## 全体像

```
Issue / PR のイベント
  → .github/workflows/project-sync.yml(未設定なら skip)
    → bash .claude/scripts/project-sync.sh sync-issue N
      ├ REST: Issue(state / labels)+ open PR 一覧(Closes #N の照合)
      │    → Status を決める(イベント種別は見ない = 冪等)
      └ GraphQL: Project / フィールド解決 → item 追加 → Status / Priority 設定
```

**判定の正はラベルと PR のまま。** `autopilot-next.sh` は一切変更しない
(Project を判定に入れると REST 限定の前提が壊れる。requirements 参照)。

## 1. 設定(2 系統)

| 置き場 | 持つもの | 理由 |
| --- | --- | --- |
| リポジトリの variable / secret | `PROJECT_URL`(variable)/ `PROJECT_SYNC_TOKEN`(secret) | board の場所と権限。リポジトリごとに違い、git に入れられない |
| `.claude/project-sync.json` | ラベル名・Status / Priority のフィールド名とオプション名の候補 | ボードの命名はプロジェクトごとに違う(日本語ボードもある) |

`PROJECT_URL` は `https://github.com/users/<login>/projects/<n>` または
`https://github.com/orgs/<org>/projects/<n>`。**URL から owner 種別を判定する**
(`users/` → `user(login:)` / `orgs/` → `organization(login:)`)。GraphQL のルートが
違うので、推測ではなく URL の形で分岐する。

`GITHUB_TOKEN` は使えない —— GitHub の docs に
「`GITHUB_TOKEN` is scoped to the repository level and cannot access projects」と明記されている。
classic PAT(`project` + `repo` scope)か GitHub App の installation token が要る。

### `.claude/project-sync.json`

```json
{
  "ticketLabel": "ticket",
  "inProgressLabel": "in-progress",
  "statusField": ["Status", "ステータス"],
  "status": {
    "todo":       ["Todo", "To do", "未着手"],
    "inProgress": ["In Progress", "In progress", "進行中"],
    "inReview":   ["In Review", "In review", "レビュー中"],
    "done":       ["Done", "完了"]
  },
  "priorityField": ["Priority", "優先度"],
  "priority": { "P0": ["P0", "High"], "P1": ["P1", "Medium"], "P2": ["P2", "Low"] }
}
```

- 名前の照合は**候補リストの順で先頭一致を採り、大小文字と前後空白を無視する**
- **オプションが見つからなければその 1 項目だけ飛ばして警告**(`In Review` 列が無いボードでも
  Todo / In Progress / Done は動く)。`Status` フィールド自体が無いときは失敗として扱う
  (ボードの指定を間違えている)
- Priority フィールドが無いのは正常(警告も出さない。優先度列を作らない運用があるため)

## 2. Status の決め方(冪等)

**イベント種別ではなく Issue の現在の状態から毎回決め直す。** 取りこぼしや
イベントの順序入れ替わりで板がずれないようにするため。

| 条件(上から最初に当たったもの) | Status |
| --- | --- |
| Issue が closed | `done` |
| `Closes #N` で紐づく **open PR** がある(fork の PR は除く) | `inReview` |
| `in-progress` ラベルがある | `inProgress` |
| それ以外 | `todo` |

- **draft PR も `inReview`** に入れる。econ(モード B)は draft で積む運用なので、
  draft を `inProgress` に残すと板が実装中と区別できなくなる
- `Closes #N` の照合は **`autopilot-next.sh` と同じ正規表現**を使う:
  `\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\s+#(\d+)`(`gi`)。
  同じ概念に 2 つの実装を持たせない
- **`done` になるのは Issue が closed になったときだけ。** GitHub の `Closes #N` は
  **既定ブランチへのマージでしか Issue を自動クローズしない**ため、`baseBranch` を `develop` に
  している構成では feature → develop のマージ時点で `done` にならず `inProgress` に戻る
  (`in-progress` ラベルが残っている限り)。`done` はリリース PR が `main` に入った時点で付く。
  テンプレート既定(GitHub Flow / `baseBranch: main`)では起きない
- **fork の PR は紐づけない。** `head.repo.full_name != base.repo.full_name` で落とす
  (`autopilot-next.sh` の untrustedPrs と同じ境界。本文に `Closes #N` と書くだけで
  外部の人が板を動かせてはならない)

### 対象の入口は `ticket` ラベル

`ticket` ラベルが無い Issue は Project に触らない。**ラベル付与自体が信頼の境界になる**
—— 書き込み権限が無いと Issue 作成時にラベルを付けられないため、外部からの Issue が
勝手に板に載ることはない。

## 3. スクリプト: `.claude/scripts/project-sync.sh`

ロジックは**ワークフローの YAML に埋めずスクリプトに置く**(shellcheck の対象になり、
フィクスチャで検証でき、人間が手元から `backfill` を回せる)。

```
bash .claude/scripts/project-sync.sh sync-issue N    # Issue 1 件を同期
bash .claude/scripts/project-sync.sh sync-pr N       # PR の Closes #N を辿って各 Issue を同期
bash .claude/scripts/project-sync.sh backfill        # ticket ラベルの open Issue 全件(初回投入)
bash .claude/scripts/project-sync.sh --check         # 設定・権限・名前の照合結果を出す(書き込まない)
bash .claude/scripts/project-sync.sh --resolve-status --issue F --prs F   # フィクスチャで Status 決定だけを出す
```

終了コード: **0 = 成功または未設定でスキップ / 2 = 設定・取得・更新の失敗**
(`autopilot-board.sh` と同じ方針)。

### GraphQL(docs で確認済みの形)

1. **Project とフィールドの解決**(1 クエリ)

   ```graphql
   query($login: String!, $number: Int!) {
     user(login: $login) {            # orgs/ のときは organization(login: $login)
       projectV2(number: $number) {
         id
         fields(first: 50) {
           nodes {
             ... on ProjectV2SingleSelectField { id name options { id name } }
           }
         }
       }
     }
   }
   ```

2. **item の追加**(既にあれば既存の item ID が返る = 冪等)

   ```graphql
   mutation($project: ID!, $content: ID!) {
     addProjectV2ItemById(input: { projectId: $project, contentId: $content }) { item { id } }
   }
   ```

3. **Status / Priority の設定**(追加と同じ呼び出しにはできない)

   ```graphql
   mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
     updateProjectV2ItemFieldValue(
       input: { projectId: $project, itemId: $item, fieldId: $field,
                value: { singleSelectOptionId: $option } }
     ) { projectV2Item { id } }
   }
   ```

Issue の node ID は REST の `node_id` から取る(GraphQL の引き直しをしない)。

### 実装の順序(1 回の sync-issue)

1. 設定を読む。`PROJECT_URL` か `PROJECT_SYNC_TOKEN` が空なら**何もせず exit 0**
2. REST で Issue を取る(`state` / `labels` / `node_id`)。`ticket` ラベルが無ければ exit 0
3. closed でなければ REST で open PR 一覧を取り、fork を除いて `Closes #N` を照合する
4. Status を決める(上の表)
5. GraphQL でプロジェクトとフィールドを解決する(1 回の実行では**キャッシュして使い回す**。
   `backfill` で Issue ごとに引き直さない)
6. item を追加し、Status を設定する。優先度ラベルがあり Priority フィールドが
   解決できていれば Priority も設定する

## 4. ワークフロー: `.github/workflows/project-sync.yml`

```yaml
on:
  issues:
    types: [opened, reopened, closed, labeled, unlabeled]
  pull_request:
    types: [opened, reopened, closed, ready_for_review, converted_to_draft]
```

- **`pull_request_target` は使わない。** fork の PR は対象外なので secret を要らず、
  `pull_request` で足りる(fork からは secret が渡らないので自然に skip される)
- fork からの PR では `PROJECT_SYNC_TOKEN` が空になる → 上の「未設定ならスキップ」で落ちる。
  それでもスクリプト側で head リポジトリを見る(二重の境界)
- `permissions: { contents: read, issues: read, pull-requests: read }`
  (Project への書き込みは PAT が担うので `GITHUB_TOKEN` の権限は読み取りだけ)
- `concurrency` は**ジョブを潰さず直列化する**: `group: project-sync-${{ github.event.issue.number || github.event.pull_request.number }}` / `cancel-in-progress: false`
  —— 同じ Issue への連続イベントで**古いほうを捨てると最終状態が落ちる**(`claude-code-review.yml` の
  `cancel-in-progress: true` と判断が逆になるのは、あちらが「最新の差分だけ見ればよい」のに対し、
  こちらは「全イベントを順に反映したい」ため)
- 未設定時は `::notice` を出して skip(`::warning` にしない。テンプレートから作った直後の
  リポジトリで毎イベント警告が出るのは鳴りっぱなし)。設定済みで失敗したときは `::error` + 失敗

## 5. manifest の区分

| ファイル | 区分 | 理由 |
| --- | --- | --- |
| `.github/workflows/project-sync.yml` | `owned` | 他の Claude 系ワークフローと同じ。テンプレートが配る |
| `.claude/scripts/project-sync.sh` | (`.claude/scripts/` で既に `owned`) | 追加不要 |
| `.claude/project-sync.json` | `merge` | ボードの命名はプロジェクト固有。`autopilot.json` と同じ扱い |

## 6. 検証

- `--resolve-status` + フィクスチャで Status 決定の 4 分岐と fork 除外を確認する
  (GitHub に触らない)
- `--check` を手元で実行し、設定不備 / 権限不足 / 名前の不一致がそれぞれ読めるメッセージで
  出ることを確認する
- `bash .claude/scripts/check-shell.sh` / `check-manifest-coverage.sh` を通す
- **実際のボードでの動作確認は人間の担当**(PAT の発行と Project の作成が要る)。
  CHANGELOG の `[manual]` にその手順を書く
