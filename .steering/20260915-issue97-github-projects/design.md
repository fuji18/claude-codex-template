# 設計: GitHub Projects による開発管理の導入

<!-- status: ready -->

## 0. 前提(実装者はここだけ読めば設計判断は不要)

**この設計で決めたこと(以降の節はすべてこの 6 行の具体化):**

1. **Issues が正、Projects は投影。** Status は Issue の事実から**一方向に導出**する。双方向同期はしない
2. **同期は 2 層。** 層1 = GitHub の組み込みワークフロー(人間が UI で有効化)、層2 = コマンド実行時の 1 件投影(ローカルの `gh`)。**Actions と Secret は初版では使わない**
3. **完了は Issue の close のみ。** PR 作成は `In review` 止まり
4. **判定の実体はスクリプト 1 本**(`.claude/scripts/projects-sync.sh`)。3 コマンドも既存コマンドもここを経由し、散文で `gh` 手順を二重に書かない
5. **未導入・`enabled:false`・`gh` 不在・認証不足は、すべて静かな no-op**(既存フローを止めない)。ただし `/github-projects-status` だけは「未確認」として明示する
6. **Codex は Projects を操作しない。** sandbox はネットワーク無効で、Issue 操作も既に禁止されている(`AGENTS.md` §3)

**確認済みの外部仕様(2026-09-15 / 公式ドキュメント):**

| 事実 | 出典 | 設計上の帰結 |
| --- | --- | --- |
| Actions の `GITHUB_TOKEN` は Projects にアクセスできない | Automating projects using Actions | Actions 経路は PAT / GitHub App Secret が必須 → 初版から外す |
| `gh project` の最小スコープは `project` | gh CLI マニュアル | 認証検査は `gh auth status` のスコープ行を見る |
| classic PAT は `project`(private repo なら `repo` も)が必要 | 同上 / add-to-project README | 人間作業の表に明記 |
| **fine-grained PAT には「ユーザー所有 Project」の権限が存在しない** | Permissions required for fine-grained PATs / community discussion | ユーザー所有 Project を使うなら classic PAT か OAuth ログインが必要。組織所有なら fine-grained の org `Projects: Read and write` で足りる |
| 既定で有効な組み込みワークフローは「closed → Done」「PR merged → Done」の 2 つ。Auto-add は既定 off | Built-in automations | Auto-add の有効化は人間の手作業として必須項目にする |
| 組み込みワークフローの設定は UI 手順のみが文書化されている(API 未文書) | 同上 | コマンドは有効化を**確認できない** → 常に「未確認(自己申告)」 |
| Projects v2 には REST(`/users/{u}/projectsV2`・`/orgs/{o}/projectsV2`、API version `2026-03-10`)と GraphQL の両方がある | REST API endpoints for Projects | 初版は `gh project`(内部は GraphQL)だけを使う。REST 直叩きはしない |

---

## 1. 正の所在(役割分担)

| 情報 | 正 | 他の場所での扱い |
| --- | --- | --- |
| チケットの内容・受け入れ条件・スコープ | **GitHub Issue の本文** | Project のカードは Issue を参照するだけ(下書きアイテムを作らない) |
| 優先度 | **Issue のラベル(`P0`/`P1`/`P2`)** | Project の Priority フィールドは初版では作らない |
| 依存関係 | **Issue 本文の `depends: #N`** | ボードには載せない |
| 着手中かどうか | **Issue の `in-progress` ラベル** | Status への導出元 |
| 完了 | **Issue の open/closed**(PR の `Closes #N` で閉じる) | Status `Done` への導出元 |
| 実装計画・設計・進捗 | **`.steering/[dir]/`**(`design.md` / `tasklist.md`) | Projects には持ち込まない。`/github-projects-next` は `design.md` の完成マーカーを**読むだけ** |
| 進行状態の**表示** | **Project の Status フィールド** | 上の事実から導出される派生値 |
| 委託先の判断 | **`delegate:codex` ラベル** | Projects には持ち込まない |

**競合回避の規則(これが双方向同期を避ける根拠):**

- Projects へ書かれる値は Status **1 フィールドだけ**。その値は §2 の導出関数の出力に等しい。
- **ボード上のドラッグは正ではない。** 人間がカードを動かしても Issue の事実は変わらないため、次の投影で元に戻る。状態を変えたいときはラベル・PR・Issue の close を動かす。この規則は `/enable-github-projects` の完了メッセージと `.claude/docs/github-projects-guide.md` に明記する。
- 逆向き(Projects → Issues)の書き込みは**どの経路でも行わない**。

---

## 2. Status モデルと遷移条件

Project の Status フィールドに、次の 5 状態を持たせる(名称は既存 Project に合わせて変えてよい。対応は config の `options` で吸収する)。

| キー(config 内の正) | 既定の表示名 | 導出条件 |
| --- | --- | --- |
| `backlog` | Backlog | open / `ticket` ラベルあり / `depends:` に未 closed の Issue が 1 件以上 |
| `ready` | Ready | open / `depends:` がすべて closed(または無し) / `in-progress` なし |
| `in_progress` | In progress | open / `in-progress` ラベルあり / 紐づくオープン PR **なし** |
| `in_review` | In review | open / `in-progress` ラベルあり / 紐づくオープン PR **あり** |
| `done` | Done | **closed** |

**導出関数(`projects-sync.sh` に 1 箇所だけ実装する。上から順に最初に一致したもの):**

```
expected_status(issue):
  1. issue.state == CLOSED                       -> done
  2. has_label(issue, "in-progress") && open_pr_closing(issue) -> in_review
  3. has_label(issue, "in-progress")             -> in_progress
  4. any_unclosed(depends_of(issue))             -> backlog
  5. otherwise                                   -> ready
```

- `open_pr_closing(issue)`: オープン PR の本文に `Closes #<番号>` を含むものがあるか。判定は次の 1 回の呼び出しで全件まとめて取る(PR ボディに `Closes #N` を書くことは既存規約で必須)。

  ```bash
  gh pr list --state open --json number,body --limit 100
  ```

- `depends_of(issue)`: Issue 本文の `depends:\s*#\d+`(`/next-ticket` ステップ1 と同じ抽出規則)。

**「PR 作成だけで完了扱いにしない」の担保:**

- 遷移 `in_review -> done` の唯一のトリガは **Issue が closed になること**。PR の作成・draft 解除・レビュー承認では Done にならない。
- Issue を閉じるのは PR のマージ時の `Closes #N` 自動クローズ(既存規約)。したがって **Done = マージ済み**が保たれる。
- 組み込みワークフロー「closed → Done」「PR merged → Done」は、この規則と同じ向きなので有効のままでよい(層1 と層2 の出力が一致する)。

---

## 3. 同期の 3 層(実行主体・起動イベント・認証・権限)

| 層 | 実行主体 | 起動イベント | 認証 | 必要権限 | 初版 |
| --- | --- | --- | --- | --- | --- |
| **層1: 組み込みワークフロー** | GitHub 本体 | Issue/PR の close・merge、Issue の作成/ラベル付与(Auto-add) | 不要(GitHub 内部) | Project の管理者が UI で有効化 | **採用(必須)** |
| **層2: コマンド実行時の 1 件投影** | Claude(ローカルの `gh`)または人間 | `/next-ticket` の着手時 / PR 作成時 / `/enable-github-projects` の初期投影 / `/github-projects-status` からの修復 | ローカルの `gh auth`(keyring) | `project` スコープ(classic PAT)または org `Projects: Read and write`(fine-grained) | **採用(必須)** |
| **層3: Actions による定期の全件同期** | GitHub Actions | `schedule` / `issues` / `pull_request` | Secret(PAT または GitHub App の秘密鍵) | 同上 + repo の `issues`/`pull-requests` 読み取り | **将来対応(初版では作らない)** |

**層3 を初版から外す理由(設計判断):**

- `GITHUB_TOKEN` では Projects を触れないため、層3 は**必ず Secret 登録を人間に要求する**。初版で Secret をゼロに保てば、「秘密情報を会話にも追跡ファイルにも書かない」という要件が**設計上の性質**になる(運用上の注意ではなくなる)。
- 層1 が既に「closed → Done」「merged → Done」「Auto-add」を無償で担うため、層3 が埋めるのは `in_progress` / `in_review` / `backlog` の差分だけ。これは層2 と `/github-projects-status` の drift 検出で足りる。
- テンプレートは全下流プロジェクトへ配布される。Secret 前提のワークフローを既定で配ると、**未設定の下流で毎回赤い CI が出る**。

**drift(ずれ)の扱い:** 層2 はイベント駆動なので、イベントを取りこぼすと実体とずれる(Codex 縮退モード中の作業、人間の手作業での close、ボードのドラッグ)。これを**検出専用**の `projects-sync.sh drift` と、**明示実行の一括修復** `projects-sync.sh reconcile` で回収する。定期実行はしない(人間か司令塔が `/github-projects-status` を叩いたときだけ動く)。

---

## 4. 設定ファイル

**パス: `.claude/projects-policy.json`(git 追跡対象)**

命名は既存の機械可読な単一ソース(`.claude/branch-policy.json`)に揃える。**このファイルが無い = Projects 連携は無効**(フェイルセーフ。テンプレートは実体を配布しない)。

```json
{
  "$comment": "GitHub Projects 連携の機械可読な単一ソース。秘密情報は入れない(トークンは gh の認証情報 / Actions Secret に置く)。/enable-github-projects が生成し、/github-projects-status と projects-sync.sh が読む。",
  "schemaVersion": 1,
  "enabled": false,
  "owner": "<owner ログイン名>",
  "ownerType": "user",
  "projectNumber": 0,
  "projectId": "PVT_xxx",
  "projectUrl": "https://github.com/users/<owner>/projects/<番号>",
  "statusField": {
    "id": "PVTSSF_xxx",
    "name": "Status",
    "options": {
      "backlog": "<option id>",
      "ready": "<option id>",
      "in_progress": "<option id>",
      "in_review": "<option id>",
      "done": "<option id>"
    }
  },
  "autoStart": false,
  "builtinWorkflows": {
    "autoAdd": { "declared": false, "declaredAt": null },
    "itemClosedDone": { "declared": false, "declaredAt": null },
    "prMergedDone": { "declared": false, "declaredAt": null }
  },
  "setupSteps": {
    "projectResolved": false,
    "linkedToRepo": false,
    "statusMapped": false,
    "initialItemsAdded": false,
    "verified": false
  }
}
```

**キーの意味と制約:**

- `enabled`: **最終検証(`setupSteps.verified`)が通ったときだけ `true` にする。** 途中失敗では `false` のまま残る(部分導入を「有効」と誤認しない)。
- `ownerType`: `user` | `org`。`gh api users/<owner> --jq .type` の結果(`User`/`Organization`)から決める。URL 形(`/users/` か `/orgs/`)と必要権限の分岐に使う。
- `projectId` / `statusField.id` / `options.*`: GraphQL node ID。**識別子であって資格情報ではない**(この値だけでは誰もアクセスできない)。したがって追跡してよい。
- `builtinWorkflows.*.declared`: **人間の自己申告**。API から読めないため、`/github-projects-status` は常に「未確認(自己申告: 日付)」と表示する。`declaredAt` は申告日(ISO 8601 の日付)。
- `autoStart`: 将来対応の予約キー。**初版では読むだけで、`true` でも挙動は変わらない**(`/github-projects-next` が「autoStart は未実装」と 1 行出す)。
- **禁止:** `token` / `pat` / `secret` / `privateKey` などのキーを追加しないこと。`.secretlintrc.json` による CI 検査に加え、`projects-sync.sh` は config 中にこれらのキー名を見つけたら **exit 2** で停止する(フェイルクローズ)。

**配布と分類(`.claude/template-manifest.json`):**

| パス | 分類 | 理由 |
| --- | --- | --- |
| `.claude/projects-policy.example.json` | `owned` | スキーマの単一ソース。テンプレートが配る |
| `.claude/projects-policy.json` | `never` | プロジェクト固有の実値。`/sync-template` が絶対に上書きしない |

`schemaVersion` が example 側より古い場合、`/github-projects-status` が「スキーマが古い(現行 N / 設定 M)。差分は `.claude/projects-policy.example.json` を参照」と 1 行出す(自動移行はしない)。

**委託禁止領域に追加するか(設計判断: 追加しない):** `.claude/projects-policy.json` は実行ベクタでも保護判定データでもなく、壊れても可視化が狂うだけで CI・ガードレール・保護ブランチ判定には影響しない。禁止領域を 1 項目増やすと `delegate-codex.sh` の `FORBIDDEN_PATHS` と `AGENTS.md` §4 と `delegation-policy.md` の 3 箇所を恒久的に同期し続ける義務が発生する(`check-forbidden-paths-doc.sh` の照合対象)。**費用が便益を上回るため追加しない。** 代わりに Codex 側の禁止は「Projects を操作しない」という §9 の行動規約で担保する。

---

## 5. `.claude/scripts/projects-sync.sh`(判定と同期の実体)

**置き場所の理由:** 同じ `gh project` 手順を 3 コマンド + `/next-ticket` + `/kickoff` の散文に書くと必ず乖離する。`check-protected-branch.sh`(保護ブランチ判定を 1 本に集約)と同じ方針で、**経路によらず同じ結果**になるようスクリプト 1 本に寄せる。`.claude/scripts/` は委託禁止領域なので、**このファイルは Claude Code 側が書く**(§15)。

**実行権限:** `chmod +x`(source 専用ではない)。呼び出しは常に `bash .claude/scripts/projects-sync.sh ...` の形で、実行権限が落ちてもフェイルオープンにならないようにする(`check-implementation-phase.sh` が `latest-steering.sh` を呼ぶのと同じ作法)。

### 5.1 サブコマンド

| 呼び出し | 動作 | 書き込み |
| --- | --- | --- |
| `status` | 設定・認証・Project 実在・フィールド対応・スキーマ版を診断し、`KEY=値` 形式の行を出す | なし |
| `expected <issue番号>` | その Issue の期待 Status キー(`backlog`/`ready`/`in_progress`/`in_review`/`done`)を 1 行で出す | なし |
| `drift` | open な `ticket` Issue 全件 + closed で Project に載っている分について、期待値と実値の差分を 1 行 1 件で出す | なし |
| `set <issue番号> [status-key]` | 1 件の Status を投影する。`status-key` 省略時は `expected` の結果を使う。Project にアイテムが無ければ追加してから設定する | あり(1 件) |
| `reconcile` | `drift` の全件に `set` を適用する。**明示実行のみ**(自動では呼ばない) | あり(複数) |
| `add <issue番号>` | Project にアイテムを追加する(既にあれば何もしない) | あり(1 件) |
| `--print-config` | config の**非秘密**キーを `KEY=値` で出す(診断用) | なし |

### 5.2 終了コード(呼び出し側の分岐はこれだけを見る)

| コード | 意味 | 呼び出し側の動き |
| --- | --- | --- |
| `0` | 成功(投影済み / 差分なし / 既に同値で no-op) | 続行 |
| `1` | drift あり(`drift` のみが返す) | `/github-projects-status` は件数と修復手順を出す。他の呼び出し元は続行 |
| `2` | 設定・認証・権限の異常(config 破損 / スコープ不足 / Project 不在 / Status 対応不整合 / 秘密キー混入) | **警告 1 行を出して続行。フローは止めない。** `/github-projects-status` は「未確認」と表示 |
| `3` | 未導入または `enabled:false` または `gh` 不在 | **何も出力せず静かに続行**(no-op) |
| `4` | 一時的失敗(API エラー・ネットワーク断・レート上限) | 警告 1 行を出して続行。自動リトライはしない |

**フェイルソフトである理由:** この層は可視化であってガードレールではない。保護ブランチ判定や denylist と違い、止めたときの損失(開発フローが進まない)が通したときの損失(ボードが古い)より大きい。`/github-projects-status` と `drift` が後追いで回収する。

### 5.3 出力の作法

- **1 行 1 事実、合計 20 行以内。** `gh` の生 JSON を司令塔へ返さない(`.claude/rules/lead/context-management.md`)。
- トークン値・`gh auth status` の生出力を**絶対に出さない**。スコープは「`project` スコープ: あり/なし/不明」に正規化して出す。
- `set` の出力例: `set: #42 in_progress -> in_review` / `set: #42 no-op (already in_review)`
- `drift` の出力例: `drift: #42 board=in_progress expected=in_review`

### 5.4 使用する `gh` サブコマンド(実装時の参照)

```bash
# 所有者種別
gh api users/<owner> --jq .type                  # User | Organization
# Project の作成 / 接続
gh project create --owner <owner> --title "<title>" --format json
gh project link <番号> --owner <owner> --repo <owner>/<repo>
gh project view <番号> --owner <owner> --format json
# フィールドと選択肢
gh project field-list <番号> --owner <owner> --format json
# アイテム
gh project item-add <番号> --owner <owner> --url <Issue URL> --format json
gh project item-list <番号> --owner <owner> --limit 200 --format json
gh project item-edit --id <item> --project-id <projectId> \
  --field-id <statusFieldId> --single-select-option-id <optionId>
# Issue / PR の事実
gh issue list --label ticket --state open --json number,body,labels,url --limit 100
gh pr list --state open --json number,body --limit 100
```

**実装時に 1 度だけ実機で確認する値(推定で書かない):** `gh project item-list --format json` が返すアイテムの Status 値のキー名と、`content` の形(`number` / `url` / `type`)。確認した実際のキー名をスクリプト内コメントに記録する(§14)。

---

## 6. 3 コマンドの仕様

すべて `.claude/commands/<名前>.md` として追加する(frontmatter は `description:` 1 行。既存コマンドと同形式)。

### 6.1 `/enable-github-projects`

**引数:** なし(任意で既存 Project の番号。例 `/enable-github-projects 7`)

| ステップ | 内容 | 人間の関与 |
| --- | --- | --- |
| 1. 前提確認 | `gh` の有無 / `gh auth status` / `project` スコープ / `gh repo view --json nameWithOwner,owner` / 既存 config の有無 | なし |
| 2. スコープ不足時の停止 | **書き込みを一切せず停止**し、§10 の該当行(トークン種別ごとの復旧手順)を提示 | 人間が CLI/ブラウザで対応 |
| 3. 再実行判定 | config があれば `projects-sync.sh status` を先に実行し、**差分のあるステップだけ**を実施 | なし |
| 4. 接続先の決定 | 「新規作成」か「既存に接続(番号を指定)」かを**質問して承認を取る**。所有者(user/org)とタイトルもここで確定 | **承認必須** |
| 5. Project の用意 | 新規: `gh project create` → `gh project link`。既存: `gh project view` で実在確認 → 未リンクなら `gh project link` | 書き込み前に承認 |
| 6. Status の対応付け | `gh project field-list` で Status の選択肢を読み、5 キーへの対応を提示。過不足があれば**人間に UI での整備を依頼**して停止するか、既存名への対応付けを承認で確定 | **承認必須**(名称が既定と違う場合) |
| 7. 既存 Issue の取り込み | open な `ticket` Issue を `item-add` → `set` で初期投影。件数を提示して承認を取る | **承認必須** |
| 8. 組み込みワークフロー | Auto-add / closed→Done / PR merged→Done の有効化手順(UI の場所)を提示し、**実施したかを質問**。回答を `builtinWorkflows.*.declared` に記録 | **人間が GitHub UI で実施** |
| 9. 確定 | `setupSteps.verified` を立て `enabled: true` にし、`/github-projects-status` を 1 回実行して結果を表示 | なし |

- **各ステップ完了時に `setupSteps` を書き込む。** 途中で失敗・中断しても、再実行は残りから再開する。
- **重複作成の回避:** 5 は config に `projectId` があればスキップ。7 の `item-add` は既存アイテムに対しては GitHub 側が既存項目を返す(重複しない)ため、無条件に呼んでよい。
- 出力は最後に「次の一手」1 行(`/github-projects-next` または `/next-ticket`)。

### 6.2 `/github-projects-status`

**引数:** なし。**読み取り専用。何も書き込まない。**

出力は次の固定表とし、各行の値は `ok` / `ng` / **`未確認`** の 3 値+短い説明。**確認できないものを `ok` と書かない。**

```
## GitHub Projects 連携の状態

| 項目 | 状態 | 備考 |
|---|---|---|
| 設定ファイル | ok / ng / 未確認 | .claude/projects-policy.json / schemaVersion N |
| 有効化 | ok / ng | enabled: true|false |
| gh CLI | ok / ng | 未インストールなら ng(連携は no-op) |
| 認証 | ok / ng / 未確認 | project スコープの有無(トークン値は表示しない) |
| Project の実在 | ok / ng / 未確認 | <owner>/<番号> |
| リポジトリ連携 | ok / ng / 未確認 | link 済みか |
| Status フィールド対応 | ok / ng | 5 キーすべてに option ID があるか |
| 同期差分 | ok / N 件 / 未確認 | drift の件数 |
| 組み込みワークフロー | **常に 未確認** | 自己申告: YYYY-MM-DD(API から確認できない) |
```

**復旧手順の提示規則(状態 → 提示するもの):**

| 状態 | 提示 |
| --- | --- |
| 設定ファイルなし | `/enable-github-projects` の実行 |
| `enabled: false` かつ `setupSteps` に未完あり | 「部分導入のまま。`/enable-github-projects` を再実行すると残りから再開する」 |
| `gh` 不在 | 「この環境では連携は no-op。`gh` のある環境で実行するか、GitHub MCP は Projects 非対応である旨」 |
| スコープ不足 | §10 のトークン種別ごとの手順(classic PAT / OAuth / fine-grained + org) |
| Project 不在(404) | 「Project が削除/移動された可能性。`enabled: false` にして `/enable-github-projects` で再接続」 |
| Status 対応不整合 | 「選択肢が変更された。`/enable-github-projects` の再実行で対応付けを取り直す」 |
| drift あり | 「`bash .claude/scripts/projects-sync.sh reconcile` で一括修復(書き込み)。件数と内訳は上記」 |
| 組み込みワークフロー未申告 | UI の有効化手順と、申告を更新するための `/enable-github-projects` 再実行 |

### 6.3 `/github-projects-next`

**引数:** なし。**読み取り専用。着手しない。**

**`/next-ticket` との責務分担(重複させない):**

| | `/github-projects-next` | `/next-ticket` |
| --- | --- | --- |
| 役割 | **候補の提示と根拠の説明**(最大 3 件) | **1 件の着手から PR 作成まで** |
| 書き込み | なし | ラベル・ブランチ・`.steering/`・PR |
| Projects 参照 | する(ボードの並び順を補助材料に使う) | しない(§7 の投影だけを行う) |
| 実行後 | 人間が `/next-ticket [番号]` を叩く | 実装フローへ入る |

**判定材料と優先順位(上が強い。ボード順は最弱の補助材料):**

1. `in-progress` の Issue が既にあるか → **あれば新規候補を出さない**(`/next-ticket` と同じ分岐: オープン PR があればマージ待ち、無ければ `/resume-work`)
2. `depends:` がすべて closed か(未解決は候補外)
3. 優先度ラベル(P0 > P1 > P2)
4. 対応する `.steering/` の `design.md` に `<!-- status: ready -->` があるか(あれば「即着手可」、`draft` なら「設計の書き切りが先」)
5. Project ボードの並び順(人間が手で並べ替えた意図の反映。**1〜4 と矛盾する場合は 1〜4 が勝つ**)

**出力形式:**

```
## 次の候補

| 順 | Issue | タイトル | 根拠 | 着手可否 |
|---|---|---|---|---|
| 1 | #42 | ... | P0 / depends 解決済 / ボード最上段 | 即着手可 |
| 2 | #45 | ... | P0 / design.md は draft | 設計を書き切ってから |

着手するには: /next-ticket 42
```

**候補提示から実装開始までの条件(すべて満たすまで実装に入らない):**

1. 人間が Issue 番号を選び、`/next-ticket [番号]` を明示的に実行した
2. 他に `in-progress` の Issue が無い(あるなら先にそれを終わらせる)
3. `depends:` がすべて closed
4. 司令塔が `design.md` を書き切り、完成マーカーが `<!-- status: ready -->` になっている(実装委託の入口検査)
5. `autoStart` が `true` でも**初版では自動着手しない**(未実装である旨を 1 行出す)

---

## 7. 既存コマンドへの差し込み

**原則:** 差し込みは**追記だけ**で、既存の手順・表・分岐は書き換えない。どの差し込みも「config が無ければ何もしない」で始まる。

### 7.1 `.claude/commands/next-ticket.md`

**ステップ2(`gh issue edit [番号] --add-label in-progress`)の直後**に次を追記する:

次の 3 要素を、この順で書く(**実際のファイルではコードブロックのフェンスを通常どおり書くこと**):

- 見出し無しの太字行 — `**Projects 連携(有効時のみ)**: ` に続けて「`.claude/projects-policy.json` があるときは、ラベル付与の直後に投影する。設定が無い・無効・`gh` が無い環境では静かに no-op になる(exit 3)。」
- bash のコードブロック 1 つ — 中身は `bash .claude/scripts/projects-sync.sh set [番号] in_progress` の 1 行だけ
- 補足 1 行 — 「exit 2 / 4(認証・API の問題)でも**着手は続行する**。警告 1 行を報告に含めるだけでよい。」

**ステップ4(Issue へのコメント)の直前**に次を追記する:

同じ形で 2 要素を書く:

- 太字行 — `**Projects 連携(有効時のみ)**: ` に続けて「PR を作成したら `In review` へ投影する。**ここで `Done` にはしない**(完了は PR マージによる Issue の close で、組み込みワークフローが Done にする)。」
- bash のコードブロック 1 つ — 中身は `bash .claude/scripts/projects-sync.sh set [番号] in_review` の 1 行だけ

### 7.2 `.claude/commands/kickoff.md`

**フェーズ3(チケット発行)とフェーズ4(ハーネス層)の間に、`## フェーズ3.5: GitHub Projects の導入(任意)` を新設する。**

挿入位置の理由: (a) 一括取り込みの対象になる Issue が出揃うのはフェーズ3 の直後、(b) 最初の `/next-ticket`(フェーズ6)より前に入れないと 1 枚目のチケットがボードに載らない、(c) 認証スコープの不足は人間の手作業を要するため、ハーネス設定より前に発覚させたい。

本文(要旨):

- ボードでの可視化を使うかをユーザーに確認する。使わないなら**何もせず次のフェーズへ**(既定は導入しない)。
- 使う場合は `/enable-github-projects` のフローを実行する。
- 認証スコープ・組織の承認が要る場合はフェーズ6 の「残課題」に再掲する(kickoff を止めない)。

`## 完了条件` に 1 行追加: 「Projects を導入した場合、`/github-projects-status` が `enabled: ok` を返し、組み込みワークフローの申告が記録されている」。

### 7.3 `.claude/commands/status.md`

ステップ1 の情報収集に 1 項目追加する:

```markdown
5. **Projects(導入済みのときのみ)**: `bash .claude/scripts/projects-sync.sh status` の要約 1 行。exit 3 なら行ごと省略する
```

ステップ2 の表に `| Projects | [drift N 件 / 同期済み / 未導入] |` の行を、**導入済みのときだけ**足す。

### 7.4 `.claude/commands/setup-tickets.md`

ステップ4 の完了報告に 1 行だけ追記する: 「Projects 連携が有効な場合、発行した Issue は Auto-add(有効時)で自動的にボードへ載る。載っていない場合は `/github-projects-status` で確認する」。**発行処理そのものは変更しない**(Auto-add は層1 の責務)。

---

## 8. エラー処理・部分失敗・再実行・停止

| 事象 | 検出 | 挙動 | 回復 |
| --- | --- | --- | --- |
| config が無い | `projects-sync.sh` の冒頭 | exit 3(無出力) | `/enable-github-projects` |
| `enabled: false` | config | exit 3(無出力) | `/enable-github-projects` の再実行で残りから再開 |
| `gh` が無い(web 等) | `command -v gh` | exit 3 | `gh` のある環境で実行。**GitHub MCP(`mcp__github__*`)には Projects v2 の操作系が無い**ため代替しない |
| `project` スコープ不足 | `gh auth status` のスコープ行 | exit 2 + 警告 1 行 | §10 の手順(トークン種別で分岐) |
| Project が削除/移動された | `gh project view` が 404 | exit 2 | `enabled: false` にして再接続 |
| Status の選択肢が UI で変更された | `field-list` と config の option ID 照合 | exit 2 | `/enable-github-projects` 再実行(ステップ6 のみ実施) |
| API/ネットワークの一時失敗 | `gh` の非 0 終了 | exit 4 + 警告 1 行。**リトライしない** | 次のコマンド実行時に投影されるか、`reconcile` で回収 |
| 投影の取りこぼし(縮退モード中など) | `drift` | 差分行を出す(自動修復しない) | `projects-sync.sh reconcile` の明示実行 |
| 一括取り込みの途中失敗 | `setupSteps.initialItemsAdded` が false のまま | `enabled` は `false` のまま | 再実行で未追加分だけを追加(既存は GitHub 側が重複させない) |
| ボードのドラッグによるずれ | `drift` | 差分行(board 値と expected 値の両方を表示) | `reconcile` で Issue 由来の値に戻す。ボード操作は正ではない |
| 連携を止めたい | — | `enabled` を `false` にすると**全経路が no-op**。Projects 上のデータは消さない | 再開は `/enable-github-projects` |
| 完全に撤去したい | — | config を削除 + Project を UI で close/delete(**コマンドは Project を消さない**) | — |

**再実行の安全性(冪等性)の担保:**

- `set` は現在値を読んでから書く(同値なら書かない)。
- `add` は既存アイテムに対しては GitHub 側が既存項目を返すため、二重登録が起きない。
- `create` 系(Project 作成)は `config.projectId` があるかぎり再実行されない。
- 途中経過は `setupSteps` にだけ持ち、**会話履歴に依存しない**(セッションが切れても再開できる)。

---

## 9. ハーネスモード(A/B/C)との整合

| モード | Projects の扱い | 根拠 |
| --- | --- | --- |
| **A(normal)** | 層1 + 層2 が通常どおり動く。`/next-ticket` の 2 箇所で投影 | 既定 |
| **B(econ)** | **投影は行う。** 1 件あたり数行の出力で枠をほぼ消費しないため、検収を飛ばす運用と矛盾しない。draft PR でも `in_review` にする(draft か否かで Status を分けない) | `.claude/rules/mode/econ.md` は Claude の**推論**枠の温存が目的で、`gh` 呼び出しはその対象ではない |
| **C(degraded)** | **同期は一切行われない。** Codex は sandbox(ネットワーク無効)で Issue も Projects も触らない。ボードは縮退中ずっと古いままになる | `AGENTS.md` §3「Issue 操作: しない」 |
| **C からの復帰時** | `.claude/rules/mode/degraded.md` の検収手順の**最後**(PR 作成の後)に `/github-projects-status` を実行し、drift を `reconcile` で回収する | 縮退中の取りこぼしを回収する唯一の経路 |

**Codex への追加の禁止事項(`AGENTS.md` §3 の表に 1 行追加):**

| 項目 | モード A・B | モード C |
| --- | --- | --- |
| **GitHub Projects の操作** | **しない** | **しない**(ネットワーク無効。Claude 復帰時にまとめて投影される) |

既存の「Issue 操作(ラベル・コメント)」行と同じ扱いにする。**委託禁止領域(§4 の列)には追加しない**(理由は §4 末尾)。

---

## 10. 人間の作業(自動 / 承認 / 手作業 / 組織要件)

| # | 処理 | 区分 | 実施者・場所 | 必要になる条件 | タイミング |
| --- | --- | --- | --- | --- | --- |
| 1 | `gh` の有無・認証・スコープの検査 | **コマンドが自動実行** | `/enable-github-projects` | 常に | 導入の最初 |
| 2 | Project の新規作成 / 既存接続の**選択** | **人間の選択・承認** | 会話 | 常に | ステップ4 |
| 3 | Project の作成・リポジトリへの link | **コマンドが自動実行**(承認後) | `gh project create` / `link` | 新規作成を選んだとき | ステップ5 |
| 4 | `project` スコープの付与 | **人間が CLI/ブラウザで手作業** | `gh auth refresh -s project`(**OAuth ログイン時のみ有効**)/ classic PAT の再発行 | スコープ不足のとき | ステップ2 で停止したら即時 |
| 5 | **fine-grained PAT を使っている場合のトークン差し替え** | **人間が手作業** | GitHub の設定画面 | **ユーザー所有 Project を使うとき**(fine-grained にはユーザー所有 Project の権限が存在しない) | 同上 |
| 6 | 組織所有 Project の権限付与(`Projects: Read and write`) | **組織・権限による追加対応** | 組織の PAT ポリシー / 管理者承認 | `ownerType: org` かつ組織が PAT 承認制のとき | 同上(承認待ちが発生しうる) |
| 7 | Status 選択肢の整備(Backlog/Ready/In progress/In review/Done) | **人間が GitHub UI で手作業** | Project の Settings → Status フィールド | 既定の 3 択(Todo/In Progress/Done)のままのとき | ステップ6。**対応付けだけで済ませることも可**(承認) |
| 8 | 5 キーへの対応付けの承認 | **人間の選択・承認** | 会話 | 選択肢名が既定と異なるとき | ステップ6 |
| 9 | 既存 Issue の一括取り込みの承認 | **人間の選択・承認** | 会話 | open な `ticket` Issue があるとき | ステップ7 |
| 10 | 組み込みワークフローの有効化(**Auto-add**) | **人間が GitHub UI で手作業** | Project → ⋯ → Workflows → Auto-add | 常に(既定 off) | ステップ8 |
| 11 | 組み込みワークフローの確認(closed→Done / PR merged→Done) | **人間が GitHub UI で確認** | 同上 | 既定 on だが**確認は必要**(API から読めない) | ステップ8 |
| 12 | 有効化したかの申告 | **人間の選択・承認** | 会話(config に日付だけ記録) | 常に | ステップ8 |
| 13 | Issue の着手・PR 作成時の Status 投影 | **コマンドが自動実行** | `/next-ticket` 内 | 連携が有効なとき | 日常運用 |
| 14 | close → Done の遷移 | **GitHub が自動実行**(層1) | 組み込みワークフロー | 10/11 が有効なとき | PR マージ時 |
| 15 | PR のレビュー・マージ | **人間が GitHub 画面で手作業** | PR 画面 | 常に(既存どおり) | 各チケットの最後 |
| 16 | drift の一括修復 | **人間の選択 → コマンドが実行** | `projects-sync.sh reconcile` | `/github-projects-status` が drift を報告したとき | 随時・縮退モード復帰時 |
| 17 | **Secret の登録(`PROJECTS_TOKEN` 等)** | **初版では不要** | — | **層3(Actions 同期)を将来導入するときだけ** | 将来 |
| 18 | **ワークフローの有効化(Actions)** | **初版では不要** | — | 同上 | 将来 |
| 19 | 自動着手の有効化 | **初版では不可**(設定キーのみ予約) | — | 将来の実装後に人間が明示的に `autoStart: true` | 将来 |

**秘密情報の扱い(設計上の担保):**

- 初版は **Secret を 1 つも要求しない**(層3 を外したことの直接の帰結)。
- 認証はローカルの `gh`(OS の資格情報ストア)にのみ存在する。**config・`.steering/`・コマンド出力・会話のいずれにもトークンを書かない。**
- `projects-sync.sh` は `gh auth status` の生出力を出さず、「`project` スコープ: あり/なし/不明」に正規化して出す(既存の `gh auth status` 出力にはトークンの先頭が含まれるため)。
- config に `token` / `pat` / `secret` / `privateKey` のキーがあれば **exit 2 で停止**(フェイルクローズ)。`.secretlintrc.json` による CI 検査はその後段。

---

## 11. 配置・配布・記録

| 対象 | 変更 | 担当 |
| --- | --- | --- |
| `.claude/commands/enable-github-projects.md` | 新規 | Codex |
| `.claude/commands/github-projects-status.md` | 新規 | Codex |
| `.claude/commands/github-projects-next.md` | 新規 | Codex |
| `.claude/commands/next-ticket.md` | §7.1 の追記 | Codex |
| `.claude/commands/kickoff.md` | §7.2 のフェーズ3.5 新設 | Codex |
| `.claude/commands/status.md` | §7.3 の追記 | Codex |
| `.claude/commands/setup-tickets.md` | §7.4 の 1 行追記 | Codex |
| `.claude/projects-policy.example.json` | 新規(§4 のスキーマ) | Codex |
| `.claude/docs/github-projects-guide.md` | 新規(運用ガイド。正の所在・ボード操作の位置づけ・人間作業の表) | Codex |
| **`.claude/scripts/projects-sync.sh`** | 新規 | **Claude Code(委託禁止領域)** |
| **`.claude/settings.json`** | `permissions.allow` に `Bash(gh project:*)` と `Bash(gh api users/:*)` を追加 | **Claude Code(委託禁止領域)** |
| **`.claude/template-manifest.json`** | `owned` に `.claude/projects-policy.example.json`、`never` に `.claude/projects-policy.json` を追加 | **Claude Code**(同期判定データのため) |
| **`.claude/rules/lead/branch-and-tickets.md`** | 「Projects を使う場合の正の所在」を**3 行以内**で追記 | **Claude Code(委託禁止領域)** |
| **`AGENTS.md`** | §3 の表に「GitHub Projects の操作: しない」行を追加 | **Claude Code(委託禁止領域)** |
| **`CLAUDE.md`** | ディレクトリ構造節に `.claude/projects-policy.json` の 1 行 | **Claude Code(委託禁止領域)** |
| `README.md` | コマンド早見表に 3 行 + スクリプト早見表に 1 行 | **Claude Code**(現在このブランチで未コミットの編集が進行中のため、競合回避) |
| `docs/template-dev/CHANGELOG.md` | 記録(`.claude/` 変更のため CI の `record-hygiene` が要求) | **Claude Code** |
| `.harness/decisions.jsonl` | PR 作成前に 1 行追記(委託先・往復・指摘数) | **Claude Code** |

**コンテキスト費用の注意:** `.claude/rules/` への追記は**全サブエージェントに毎ターン載る**(`context-management.md`)。Projects の詳細は `.claude/docs/github-projects-guide.md` に置き、`rules/lead/` には「正の所在」の 3 行だけを書く。

---

## 12. 検証方法と受け入れ条件

### 12.1 ネットワーク不要(Codex・CI でも回る)

| # | 手段 | 期待 |
| --- | --- | --- |
| V1 | `bash .claude/scripts/projects-sync.sh status`(config 無し) | 無出力・exit 3 |
| V2 | `enabled: false` の config を置いて同上 | 無出力・exit 3 |
| V3 | `token` キーを含む config を置いて同上 | exit 2・警告 1 行(値は出力しない) |
| V4 | `PATH` から `gh` を外して `set 1 in_progress` | 無出力・exit 3・**書き込みなし** |
| V5 | `grep -rn "gh project" .claude/commands/` | 3 コマンド + 差し込み先が**直接 `gh project` を呼んでいない**(すべて `projects-sync.sh` 経由)ことの確認 |
| V6 | `npm run lint && npm run format:check` | pass |
| V7 | `bash .claude/scripts/check-guard-integrity.sh` / `check-forbidden-paths-doc.sh` | 出力なし(禁止領域の記述に乖離がない) |
| V8 | `jq . .claude/projects-policy.example.json` | 妥当な JSON・`enabled: false`・秘密キーなし |
| V9 | `npx secretlint` 相当(CI の secretlint ジョブ) | 検出 0 |

### 12.2 実 GitHub が要る(人間の承認のうえで 1 回だけ実施)

| # | 手順 | 期待 |
| --- | --- | --- |
| V10 | 検証用 Project を作って `/enable-github-projects` を通す | config が生成され `enabled: true`、`setupSteps` が全 true |
| V11 | **同じコマンドをもう一度**実行 | Project もアイテムも増えない(差分のみ・重複なし) |
| V12 | テスト Issue に `in-progress` を付けて `set` | ボードが `In progress` |
| V13 | `Closes #N` 入りの PR を作って `set ... in_review` | ボードが `In review`、**`Done` にならない** |
| V14 | PR をマージ(Issue が close) | 層1 により `Done`。`drift` が 0 |
| V15 | ボード上でカードを手で `Todo` に戻す → `drift` | 差分 1 件を検出。`reconcile` で元に戻る |
| V16 | `gh auth` からスコープを外した状態で `/github-projects-status` | 認証行が `ng`、復旧手順が出る。**他の行を `ok` と断定しない** |

### 12.3 受け入れ条件(requirements.md のチェックリストに対応)

- V1・V2・V4 が通ること = 「未導入時に既存フローの挙動が変わらない」の機械的な担保
- V5 = 「散文で `gh` 手順を二重に書かない」の担保
- V13・V14 = 「PR 作成だけで完了扱いにしない」の担保
- V11 = 「再実行で重複しない」の担保
- V16 = 「確認できない状態を正常と断定しない」の担保

---

## 13. 初版スコープと将来対応

| 区分 | 内容 |
| --- | --- |
| **初版** | 3 コマンド / `projects-sync.sh` / config + example / 既存 4 コマンドへの差し込み / 運用ガイド / 層1・層2 の同期 / drift 検出と明示的な reconcile |
| **将来対応(Secret が要る)** | 層3 = Actions による定期同期(`schedule` + `issues`/`pull_request`)。PAT or GitHub App。導入時は §10 の #17/#18 が発生する |
| **将来対応(明示的な有効化が前提)** | `autoStart`: 候補提示から `/next-ticket` の自動起動。**初版は設定キーの予約のみ**で挙動を持たない |
| **将来対応(その他)** | Iteration/Estimate フィールド、ロードマップビュー、`updateProjectV2Field` による Status 選択肢の自動整備、複数リポジトリのハブ&スポーク横断ボード |
| **恒久的に対象外** | Codex からの Projects 参照・更新(sandbox はネットワーク無効)、Projects (classic) |

---

## 14. 実装前に実測で埋める値(設計判断ではない)

推定で書かないこと。**Claude Code 側が `gh` を実行して確定し、スクリプト内コメントに記録する。**

1. `gh project item-list --format json` が返すアイテムの **Status 値のキー名**(単一選択フィールドの平坦化規則)と `content` の形(`number`/`url`/`type`)
2. `gh project item-add --format json` の戻り値に含まれるアイテム ID のキー名
3. `gh project field-list --format json` の Status フィールドの `options[].id` / `.name` のキー名
4. `gh auth status` の出力からスコープを判定する行の形(**トークン値を含む行を出力しないこと**)
5. `gh project create --format json` の戻り値(`number` / `id` / `url`)

---

## 15. 委託の分割(なぜこの線で切るか)

| 区分 | 対象 | 理由 |
| --- | --- | --- |
| **Claude Code 側** | `.claude/scripts/projects-sync.sh` / `.claude/settings.json` / `.claude/rules/lead/` / `AGENTS.md` / `CLAUDE.md` / `.claude/template-manifest.json` / `README.md` / CHANGELOG / decisions.jsonl | 前 5 つは**委託禁止領域**(`AGENTS.md` §4)。加えてスクリプトは §14 の実測に**ネットワークが要る**が、Codex の sandbox はネットワーク無効で検証できない |
| **Codex 側** | `.claude/commands/` の新規 3 本と既存 4 本への追記 / `.claude/projects-policy.example.json` / `.claude/docs/github-projects-guide.md` | 禁止領域外の散文と JSON。仕様は §4・§6・§7 に**そのまま書き写せる粒度**で確定済み。ネットワーク不要 |

**順序の制約:** Codex に渡す前に `projects-sync.sh` の CLI(§5.1・§5.2)が**実在していること**。コマンドの散文は終了コードの分岐を書くため、契約が先に固まっていないと往復が発生する。

**`delegate:codex` ラベルは付けない。** このチケットは委託禁止領域の変更を含むため、Issue 単位の一括委託(1 Issue = 1 委託)の条件を満たさない(`.claude/rules/lead/delegation-policy.md`)。委託は「コマンド md のバッチ」1 回に限定する。
