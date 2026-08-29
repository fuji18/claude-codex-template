# 検証結果: CHANGELOG 検査のトリガに `.github/workflows/` を追加する(Issue #41)

design.md §5 の 7 ケースを、記載の順に実行した結果。`S=.claude/scripts/check-record-hygiene.sh` で統一。

| # | 入力 | 期待 | 実測 | 一致 |
| --- | --- | --- | --- | --- |
| V0 | `bash -n "$S"` | 構文 OK / rc=0 | rc=0 | 一致 |
| V1 | `CHANGED_FILES='.github/workflows/ci.yml' PR_LABELS='' TICKET_ISSUES=''` | ERROR 1 件(検出パスに `.github/workflows/ci.yml`)/ rc=1 | ERROR 1 件(`.github/workflows/ci.yml` を検出)/ rc=1 | 一致 |
| V2 | V1 + `PR_LABELS='no-changelog'` | NOTICE 1 件 / rc=0 | NOTICE 1 件(`no-changelog` によりスキップ)/ rc=0 | 一致 |
| V3 | `CHANGED_FILES=$'.github/workflows/ci.yml\ndocs/template-dev/CHANGELOG.md'` | 出力なし / rc=0 | 出力なし / rc=0 | 一致 |
| V4 | `CHANGED_FILES='.github/ISSUE_TEMPLATE/bug.md'` | 出力なし / rc=0(`.github/` 全体では鳴らない) | 出力なし / rc=0 | 一致 |
| V5 | `CHANGED_FILES='.claude/scripts/foo.sh'` | ERROR 1 件 / rc=1(既存トリガの回帰確認) | ERROR 1 件 / rc=1 | 一致 |
| V6 | `CHANGED_FILES='README.md'` | 出力なし / rc=0(非トリガの回帰確認) | 出力なし / rc=0 | 一致 |

全 7 ケースが期待どおり。ズレなし。

## §6 品質チェック(実測)

| コマンド | 結果 |
| --- | --- |
| `bash -n .claude/scripts/check-record-hygiene.sh` | rc=0 |
| `npx eslint .` | rc=0 |
| `npx tsc --noEmit` | rc=0 |
| `npm test`(vitest) | rc=0(1 テスト) |
| フォーマット | rc=0 |

検収の `test-runner`(フルスイート 1 回)と `code-reviewer` の再実行でも同結果。

## 実 PR 確認の扱い(司令塔判断 / 2026-08-29)

受け入れ条件の「実 PR で確認」は、**本 PR では原理的に判別できない**。

- 本 PR は `.claude/scripts/` を変更するため、`.github/workflows/` をトリガに足さなくても検査1 は鳴る
- 検出パス(`triggered`)は `CHANGED_FILES` の**先頭一致で確定して break** する。GitHub API のファイル一覧は概ね辞書順で、`.claude/…` は `.github/…` より前に来るため、ワークフローを同時に変更しても annotation には `.claude/…` が出る
- 逆に「ワークフローだけを変更する PR」を本ブランチ以外から立てると、CI がチェックアウトするマージ参照のスクリプトは **main 側の旧配列**になり、後の挙動を確かめられない

したがって**マージ後に確認する**。手順: `main` から `.github/workflows/ci.yml` にコメント 1 行だけを足した **draft PR** を立て、`record-hygiene` が赤く落ちること(annotation に `.github/workflows/ci.yml` が出ること)を確認してから close する。draft にするのは `claude-code-review.yml` が `draft == false` のときだけ走るためで、Claude の枠を消費させない。

CI 側の配管(`set +e` の扱い・annotation / Job Summary の出力)は #37 の実 PR(run 33125304790 以降)で実測済みで、本チケットでは `record-hygiene.yml` を変更していない。今回新規なのは配列の内容だけで、それは V1〜V6 で CI と同一のスクリプトに対して実測している。
