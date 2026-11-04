---
description: テンプレートリポジトリの更新(共通ルール・コマンド・スキル・ハーネス)を差分だけ取り込み、PR を作成する
---

# テンプレート同期

テンプレート(`claude-codex-template`)側でルールやハーネスが更新されたとき、**前回同期以降の差分だけ**をこのプロジェクトに取り込むコマンドです。同期対象の単一ソースは `.claude/template-manifest.json`。

**機械的な取り込みは `.claude/scripts/sync-template.mjs` が行う。** このコマンド(Claude)が担うのは、スクリプトが判断できなかったもの —— **競合の解消**と **CHANGELOG の `[manual]` 項目の対応** —— と、検証・PR 作成だけ。ファイルを 1 つずつ手で上書き・統合しない。

**引数:** なし(`--dry-run` を渡した場合は結果の提示までで停止し、ファイルを変更しない)

月次の `template-update-check` ワークフローが同じスクリプトで同期 PR を自動作成する。**PR が既に立っているなら、まずそれをレビューしてマージすればよい**(このコマンドが要るのは、Issue で「競合あり」「ワークフローが変わる」と知らされたときや、急ぐとき)。

---

## 前提: 所有権モデル

| 区分 | スクリプトの扱い |
| --- | --- |
| `owned` | テンプレートが正。**上書き**。テンプレートで消えたファイルは、ローカルで手を入れていなければ消す(入れていれば残して報告) |
| `merge` | 双方が編集しうる。**前回同期した版(`syncedAt`)を共通の祖先にした 3-way マージ**。テキストは `git merge-file`(ignore 系は行の和集合)、JSON はキー単位の構造マージ(配列は集合として追加・削除を両方反映)。両側が同じ箇所を変えたときだけ競合 |
| `never` | プロジェクトが正。**触らない** |

パスが複数区分に該当する場合は **最も具体的な(長い)エントリが勝つ**。同じ長さなら owned > merge > never(例: `docs/` は never だが `docs/ui-design-request-template.md` は owned / `.claude/scripts/` は owned だが `.claude/scripts/lint-on-edit.sh` は merge)。**プロジェクトの manifest にだけある `never` のエントリは最優先**(テンプレートから更新されたくないファイルを、プロジェクトが個別に止めるための指定)。

技術スタックに合わせて `/kickoff` フェーズ1 が書き換えるファイル(`ci.yml` / `session-start.sh` / `lint-on-edit.sh` など)は、ディレクトリが owned でも **merge** に個別指定してある。

## フェーズ0: 前提確認

1. `.claude/template-manifest.json` が無ければ「このプロジェクトはテンプレート同期に未対応です」と伝えて終了する(README「同期未対応のプロジェクトを追いつかせる」を案内)。
2. `.claude/scripts/sync-template.mjs` が無ければ、旧版のプロジェクト。**スクリプトだけを先に取り込んでから**進める:
   ```bash
   git remote get-url template >/dev/null 2>&1 || git remote add template <templateRepo>
   git fetch --quiet template <templateBranch>
   git checkout template/<templateBranch> -- .claude/scripts/sync-template.mjs
   ```
3. `.claude/branch-policy.json` の `baseBranch` を把握する。保護ブランチ上にいる場合は、同期用ブランチ `chore/sync-template-$(date +%Y%m%d)` を切る(`allowedPrefixes` に `chore/` が無ければ `fix/` を使う)。
4. 作業ツリーがクリーンであることを確認する(スクリプトも検査して止まる)。

## フェーズ1: 試し実行(dry-run)

```bash
node .claude/scripts/sync-template.mjs --dry-run
node .claude/scripts/sync-template.mjs --check-drift
```

- 1 行目で、上書き・追加・削除・3-way マージ・競合の見込みと、CHANGELOG の `[manual]` 項目が出る
- 2 行目は、**owned なのにプロジェクトで書き換えてあるファイル**(次の同期で上書きされて失われる変更)を出す。該当があれば、上書きされる前にユーザーへ伝え、必要な内容を `CLAUDE.md` の「プロジェクト固有ルール」へ移すか、テンプレート側へフィードバックするか、manifest の `never` に足して同期から外すかを確認する
- 「テンプレートは最新です」なら終了する

ユーザーに結果を 1 画面で要約して承認を得る(`--dry-run` 指定時はここで停止)。**差分本文はこの時点で読まない。**

## フェーズ2: 適用

```bash
node .claude/scripts/sync-template.mjs --json > /tmp/sync-template.json
```

終了コード: `0` = 完了 / `2` = 完了したが競合あり / `1` = 実行できなかった(メッセージに従う)。

### 競合がある場合(終了コード 2)

`conflicts` に挙がったファイルだけを開いて解消する。

- **テキスト**: `<<<<<<< project` / `||||||| last-sync` / `>>>>>>> template` のマーカーが残っている。プロジェクト固有の設定(スタック・検証コマンド・独自の手順)を保ったまま、テンプレート側の意図を取り込む。判断に迷う箇所はユーザーに確認する
- **JSON**: マーカーは入らない(ローカルの値を残してある)。`detail` に挙がったキーについて、テンプレート側の値を取り込むべきかを判断し、必要なら Edit で直す
- 解消後、`grep -rn '^<<<<<<< project' <ファイル>` でマーカーの消し忘れが無いことを確認する

### `[manual]` 項目の対応

出力の `manual` に CHANGELOG の `[manual]` 行が並ぶ。**3-way マージで既に反映済みのものも多い**ので、1 件ずつ差分(`git diff`)と突き合わせ、未対応のものだけ対応する。1 コマンドで終わらないもの(ドキュメント更新など)は、その場でやるか残課題にするかをユーザーに確認する。

## フェーズ3: 検証と PR

1. `/check` を実行する(test-runner に委譲)。hooks / scripts / workflows が入れ替わっているため、**同期後の検証は必須**。
2. `.claude/hooks/` `.claude/scripts/` `.claude/settings.json` に変更があった場合、**反映には Claude Code の再起動が必要**である旨を伝える。
3. `/commit` でコミットし(`chore: テンプレートの更新を取り込む` 相当)、`gh pr create --base <baseBranch>` で PR を作成する。PR ボディに以下を含める:
   - 同期元 SHA(`from` → `to`)
   - 上書き・追加・削除・3-way マージしたファイル(出力 JSON から)
   - 競合をどう解消したか
   - `[manual]` 項目の対応状況(未対応があれば残課題として明記)
   - `--check-drift` で上書きされたローカル変更があれば、その扱い

## 完了条件

- `.claude/template-manifest.json` の `syncedAt` が新しい SHA に更新されている(スクリプトが更新する)
- 競合マーカーが残っていない
- `/check` が通っている
- `[manual]` 項目が対応済み、または PR ボディに残課題として明記されている
- 再起動が必要な変更があれば、その旨をユーザーに伝えている

## 注意

- **`never` のファイルは理由があっても触らない。** テンプレート側の CLAUDE.md にルールが増えていた場合、それは `.claude/rules/` に切り出されていないテンプレート側の設計ミスなので、**取り込まずにテンプレートへフィードバックする**
- **スクリプトの結果を手で上書きし直さない。** owned を Edit で戻すと次の同期でまた上書きされる。残したい変更は manifest の `never` に足して同期から外すか、テンプレートへフィードバックする
