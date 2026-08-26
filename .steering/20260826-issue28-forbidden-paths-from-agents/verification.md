# 検証記録: Issue #28 出口検査に AGENTS.md のプロジェクト固有パスを含める

実施日: 2026-08-26 / 実施者: implement-ticket (fork)

## 1. `bash -n .claude/scripts/delegate-codex.sh`

```
$ bash -n .claude/scripts/delegate-codex.sh
(出力なし) → 構文エラーなし
```

## 2. スタブスクリプト(design.md §5-0 と同一)

`PATH` の先頭にスタブ `codex` を置き、実 Codex を呼ばずに `delegate-codex.sh impl` を通した。
内容は design.md §5-0 のまま(`FAKE_CODEX_CMD` 対応版)。

## 3. 前置き

- テスト用ステアリング `.steering/zz-issue28-fixture/`(`design.md` に `<!-- status: ready -->`、
  `tasklist.md` に `- [ ] dummy` 1 行)を作成
- `AGENTS.md` / `CLAUDE.md` は `cp` でバックアップし、各シナリオ後 `cp` で復元した
  (`git checkout -- ` は使わない。未コミットの本作業の変更ごと消えるため)
- ワークツリーに元から `.claude/settings.local.json` があり、入口検査1(機密ファイル検査)に
  毎回ひっかかるため、全シナリオで `CODEX_DELEGATE_ACK_SECRETS=1` を付けて実行した
  (本チケットの変更とは無関係の既存ファイル)
- `.husky/pre-commit` / `.claude/codex-denylist.txt` はスタブが改ざんした後、
  `git checkout -- <path>` で復元(こちらは未コミット変更が乗っていない追跡ファイルなので安全)

## 4. シナリオ結果

| # | 前提 | 走らせ方 | 結果 |
| --- | --- | --- | --- |
| 1 | マーカー内に `docs/dummy-project-secret.md` を追記し、そのファイルを作成 | `FAKE_CODEX_TOUCH=docs/dummy-project-secret.md` | `status=failed` / `exit=2`。違反一覧に `docs/dummy-project-secret.md`(id=20260826-044728-94185) |
| 2 | マーカー行を両方削除(中身も削除) | `FAKE_CODEX_TOUCH=.husky/pre-commit` | `status=failed` / `exit=2`(汎用項目が従来どおり働く。id=20260826-044830-95451) |
| 3 | マーカー行は残し中身だけ全削除 | `FAKE_CODEX_TOUCH=.claude/codex-denylist.txt` | `status=failed` / `exit=2`(汎用項目の保護が消えない。id=20260826-044859-96421) |
| 4 | マーカー内に `これは説明用の語`(実在しない)を追記 | `FAKE_CODEX_TOUCH` なし / `FAKE_CODEX_WORK` のみ | `status=completed` / `exit=0`(誤検出なし。id=20260826-044921-97285) |
| 5 | マーカー内に `docs/dummy-late.md` を委託中に追記させる | `FAKE_CODEX_CMD` でマーカー内に 1 行追記 + `docs/dummy-late.md` を作成 | `status=failed` / `exit=2`。違反一覧は **`AGENTS.md` のみ**(`docs/dummy-late.md` は含まれない = 開始時点のリストで検査された証拠。id=20260826-045003-98381) |
| 6 | マーカーの終了側だけ削除 | `FAKE_CODEX_WORK` のみ | 警告「マーカーが片方しかありません」が出て `status=completed` / `exit=0`(過剰阻止しない。id=20260826-045030-99346) |

すべて design.md §5-2 の期待どおり。design.md と実機挙動の相違はなし。

### シナリオ 1 の run record 抜粋

```json
{
  "status": "failed",
  "summary": "⚠️ 委託禁止領域が変更されました(出口検査): docs/dummy-project-secret.md\n\n完了: tasklist 1/1 / 変更 1 ファイル / lint・型・関連テスト pass",
  "error": "委託禁止領域が変更されました: docs/dummy-project-secret.md"
}
```

### シナリオ 5 の run record 抜粋(開始時点のリストで検査されたことの裏取り)

```json
{
  "status": "failed",
  "summary": "⚠️ 委託禁止領域が変更されました(出口検査): AGENTS.md\n\n完了: tasklist 1/1 / 変更 1 ファイル / lint・型・関連テスト pass",
  "error": "委託禁止領域が変更されました: AGENTS.md"
}
```

`AGENTS.md` 自体は汎用項目としてもとから検査対象なので、内容が変われば単独でも `failed` になる。
`docs/dummy-late.md` が違反一覧に現れないのは、`PROJECT_FORBIDDEN_PATHS` が委託開始時点(まだ
`docs/dummy-late.md` の行が無い状態)で抽出され、以後書き換わらないため(design.md §0.2 の意図どおり)。

### シナリオ 6 の警告文言

```
delegate-codex: 警告 — AGENTS.md の <!-- kickoff:delegation-forbidden-paths --> マーカーが片方しかありません。プロジェクト固有パスの抽出をスキップします(汎用項目の検査は従来どおり働きます)。
```

## 5. 後片付け

- `AGENTS.md` は各シナリオ後に `cp` でバックアップから復元し、最終状態が本チケットの意図した差分
  (task 6 の 1 文差し替えのみ)と一致することを `diff` で確認済み
- `docs/dummy-project-secret.md` / `docs/dummy-late.md` は削除済み
- `.husky/pre-commit` / `.claude/codex-denylist.txt` は `git checkout --` で復元済み
- テスト用の run record(id 末尾: 94185, 95451, 96421, 97285, 98381, 99346)の
  `.json` / `.log` / `.last.txt` はすべて削除済み(`.gitignore` 済みのため元々コミット対象外)
- `.steering/zz-issue28-fixture/` は削除済み

最終確認(`git status --short`):

```
 M .claude/commands/kickoff.md
 M .claude/scripts/delegate-codex.sh
 M AGENTS.md
 M CLAUDE.md
?? .steering/20260826-issue28-forbidden-paths-from-agents/
```

意図した 4 ファイルの変更と、本チケットのステアリングディレクトリ以外に差分は無い。

## 6. 品質チェック

```
$ npx --no-install prettier --check AGENTS.md CLAUDE.md .claude/commands/kickoff.md \
    .steering/20260826-issue28-forbidden-paths-from-agents/verification.md
Checking formatting...
All matched files use Prettier code style!
```

`delegate-codex.sh` はシェルスクリプトのため ESLint / Prettier の対象外(拡張子不一致で
スキップされる)。shellcheck は未インストールのため実行できず、構文チェックは §1 の
`bash -n` で代替(design.md §6 の完了条件のとおり)。

## 7. 再現手順(標準形)

各シナリオは、スタブを置いたディレクトリを `PATH` の先頭に載せて次の形で実行した。
`CODEX_DELEGATE_ACK_SECRETS=1` は §3 のとおり、本チケットと無関係な
`.claude/settings.local.json` が入口検査1 に毎回引っかかるため全シナリオで付与している。

```bash
STUB=/tmp/issue28-stub          # §2 のスタブを codex という名前で置いたディレクトリ
FIXTURE=.steering/zz-issue28-fixture

PATH="$STUB:$PATH" \
  CODEX_DELEGATE_ACK_SECRETS=1 \
  FAKE_CODEX_TOUCH=<シナリオごとの改ざん対象> \
  FAKE_CODEX_CMD=<シナリオ5 のみ> \
  FAKE_CODEX_WORK="$FIXTURE/scratchN.txt" \
  .claude/scripts/delegate-codex.sh impl "$FIXTURE"
echo "exit=$?"
```

シナリオごとに変わるのは `FAKE_CODEX_TOUCH` / `FAKE_CODEX_CMD` / `scratchN.txt` の番号と、
事前に `AGENTS.md` へ加える前提(§4 の「前提」列)だけ。判定は `exit` と
`.harness/codex-runs/[id].json` の `status` / `error`、および標準エラーの `該当:` 以下を見る。

## 8. 検収での判断(司令塔)

`code-reviewer` の指摘 4 件(いずれも minor)への判断:

- **実在しないパスを無音で無視する件(警告を出してはどうか)→ 不採用。** マーカー内には
  説明のためにバックティックで囲んだ語(`<!-- verify-probe: ... -->`)が**意図的に**含まれる
  ため、「実在しなかった件数」の警告は毎回必ず出る。常時出る警告は読まれなくなり、本当に
  typo で保護が抜けたときの検知性はむしろ下がる。design.md §0.4 の判断を維持する
- 実行コマンドの逐語が無い → §7 を追記
- `forbidden_files()` のコメントの因果が不正確 → 修正済み
- 変則的なグロブ表記が無音で無視される → コメントに明記済み
