---
description: テンプレートリポジトリの更新(共通ルール・コマンド・スキル・ハーネス)を差分だけ取り込み、PR を作成する
---

# テンプレート同期

テンプレート(`claude-code-template`)側でルールやハーネスが更新されたとき、**前回同期以降の差分だけ**をこのプロジェクトに取り込むコマンドです。同期対象の単一ソースは `.claude/template-manifest.json`。

**引数:** なし(`--dry-run` を渡した場合は差分の提示までで停止し、ファイルを変更しない)

---

## 前提: 所有権モデル

| 区分 | 扱い |
| --- | --- |
| `owned` | テンプレートが正。**無条件に上書き**(テンプレート側で削除されていればローカルも削除) |
| `merge` | 双方が編集しうる。**差分を提示し、プロジェクト側の追記を保ったまま手で統合** |
| `never` | プロジェクトが正。**絶対に触らない** |

パスが複数区分に該当する場合は **owned > merge > never** の順で上位が勝つ(例: `docs/` は never だが `docs/ui-design-request-template.md` は owned)。

## フェーズ0: 前提確認

1. `.claude/template-manifest.json` を読む。存在しなければ「このプロジェクトはテンプレート同期に未対応です」と伝え、`owned`/`merge`/`never` の初期値をユーザーと決めてマニフェストを作成することを提案して終了する。
2. `git remote get-url origin` が `templateRepo` と同一なら、**ここはテンプレート本体**。同期する対象がないので「テンプレート本体では実行しません」と伝えて終了する。
3. 作業ツリーがクリーンであることを確認する。未コミット変更があれば、コミットまたは stash を促して終了する(上書きが走るため)。
4. `.claude/branch-policy.json` を読み、`baseBranch` と保護ブランチを把握する。保護ブランチ上にいる場合は同期用ブランチを切ってから進める。

## フェーズ1: テンプレートの取得

```bash
git remote get-url template >/dev/null 2>&1 || git remote add template <templateRepo>
git fetch template <templateBranch> --quiet
git rev-parse template/<templateBranch>   # = 今回の同期先 SHA
```

- `--quiet` を付け、fetch のログを司令塔に流さない。
- リモート追加を含むため、失敗した場合はネットワーク/権限の問題としてユーザーに報告して終了する。

## フェーズ2: 差分の抽出

**`syncedAt` がある場合(通常):**

```bash
git diff --name-status <syncedAt>..template/<templateBranch> -- <owned と merge のパス>
```

**`syncedAt` が `null` の場合(初回):** 履歴が繋がっていないため差分の起点がない。`git diff --name-status HEAD template/<templateBranch> -- <owned と merge のパス>` で現状比較を行い、「初回同期のため差分が大きくなる」旨を伝える。

抽出結果を次の 3 つに仕分けて、**ファイル一覧とステータス(A/M/D/R)だけ**を提示する。**この時点で差分本文は読まない**(コンテキストが膨らむ。中身が必要なのは merge 対象と、ユーザーが説明を求めたファイルだけ)。

- **owned・変更あり** → 自動上書きの対象
- **owned・テンプレート側で削除** → ローカルも削除する対象(プロジェクト側で使い続けている可能性があるため、削除は個別に確認する)
- **merge** → 手動統合の対象

差分が 0 件なら「テンプレートは最新です」と伝えて終了する(`syncedAt` だけ更新する)。

## フェーズ3: 変更内容の要約(CHANGELOG)

テンプレート側の CHANGELOG をリモートから直接読む(ローカルに `docs/template-dev/` が残っていなくてよい):

```bash
git show template/<templateBranch>:docs/template-dev/CHANGELOG.md
```

`syncedAt` 以降のエントリだけを対象に、ユーザーへ提示する:

- **`[auto]`**: 上書きだけで完結する変更。まとめて 1 行で要約してよい
- **`[manual]`**: プロジェクト側の対応が要る変更(検証コマンドの置換、ドキュメントへの追記、設定の再確認など)。**1 件ずつ、必要な対応とあわせて提示する**

CHANGELOG が無い/読めない場合はスキップし、ファイル一覧だけで判断する旨を伝える。

## フェーズ4: 適用

ユーザーの承認を得てから実行する(`--dry-run` の場合はここで停止)。

1. 同期用ブランチを切る: `git switch -c chore/sync-template-$(date +%Y%m%d)`(`branch-policy.json` の `allowedPrefixes` に適合させる。適合するプレフィックスが無ければユーザーに確認する)
2. **owned の上書き**: `git checkout template/<templateBranch> -- <path>` をパス単位で実行する
3. **owned の削除**: テンプレート側で削除されたファイルは、1 件ずつ確認してから `git rm` する
4. **merge の統合**: ファイルごとに `git diff <syncedAt>..template/<templateBranch> -- <path>` で差分本文を読み、**プロジェクト固有の設定を保ったまま**テンプレート側の変更点だけを Edit で反映する。特に注意する箇所:
   - `.claude/settings.json`: permissions の allowlist はプロジェクト固有の追加を消さない
   - `.claude/branch-policy.json`: `baseBranch` はプロジェクトの選択を維持する
   - `.github/dependabot.yml`: `/kickoff` フェーズ4 でプロダクト向け(monthly)に再チューニング済みなら、その設定を維持する
   - `.husky/pre-commit` / `.secretlintrc.json`: 異スタックに置換済みなら、テンプレートの npm 前提をそのまま戻さない
5. **`[manual]` 項目の反映**: フェーズ3 で挙がった対応を実施する。1 コマンドで終わらないもの(ドキュメント更新など)は、その場でやるか残課題にするかをユーザーに確認する
6. **マニフェストの更新**: `syncedAt` をフェーズ1 で取得した SHA に、`syncedDate` を今日の日付(YYYY-MM-DD)に更新する

## フェーズ5: 検証と PR

1. `/check` を実行する(test-runner に委譲)。hooks / scripts / workflows が入れ替わっているため、**同期後の検証は必須**。
2. hook スクリプトを取り込んだ場合は実行権限を確認する: `chmod +x .claude/hooks/*.sh .claude/scripts/*.sh`
3. `.claude/hooks/` `.claude/scripts/` `.claude/settings.json` に変更があった場合、**反映には Claude Code の再起動が必要**である旨を伝える。
4. `/commit` でコミットし(`chore: テンプレートの更新を取り込む` 相当)、`gh pr create --base <baseBranch>` で PR を作成する。PR ボディに以下を含める:
   - 同期元 SHA(`<syncedAt>` → 新 SHA)
   - `[manual]` 項目の対応状況(未対応があれば残課題として明記)
   - 上書きしたファイル数 / 手動統合したファイル

## 完了条件

- `.claude/template-manifest.json` の `syncedAt` が新しい SHA に更新されている
- `/check` が通っている
- `[manual]` 項目が対応済み、または PR ボディに残課題として明記されている
- 再起動が必要な変更があれば、その旨をユーザーに伝えている

## 注意

- **`never` のファイルは理由があっても触らない。** テンプレート側の CLAUDE.md / README / docs はプロジェクトが書き換え済みで、上書きするとプロダクトの情報が失われる。テンプレート側の CLAUDE.md にルールが増えていた場合、それは `.claude/rules/` に切り出されていないテンプレート側の設計ミスなので、**取り込まずにテンプレートへフィードバックする**
- **差分本文を全部読まない。** owned は中身を確認せず上書きするのが原則。読むのは merge 対象と、ユーザーが説明を求めたファイルだけ
