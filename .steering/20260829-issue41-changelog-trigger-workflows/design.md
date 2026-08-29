# 設計: CHANGELOG 検査のトリガに `.github/workflows/` を追加する(Issue #41)

<!-- status: ready -->

実装者は設計判断をしない。以下の §1〜§5 をそのまま適用する。

## 前提(読む必要のあるファイル)

- `.claude/scripts/check-record-hygiene.sh`(§1 の対象。判定の実体)
- `.claude/rules/lead/delegation-policy.md`(§2 の対象。50〜55 行目の表)
- `docs/template-dev/CHANGELOG.md`(§3・§4 の対象)
- `.claude/template-manifest.json`(読むだけ。`owned` に `.github/workflows/` の 5 本が載っていることの確認)

`.github/workflows/record-hygiene.yml` は**変更しない**。CI 側の配管(`set +e` を含む)は #37 で実 PR 実測済み。

## §1 `.claude/scripts/check-record-hygiene.sh`

31〜33 行目(コメント 2 行 + 配列 1 行)を、以下のブロックで**丸ごと置き換える**。

```bash
# CHANGELOG の追記を要求する変更対象。末尾が / のものはディレクトリ配下すべてを指す。
#
# ここは .claude/template-manifest.json の owned / merge に載っている「面」と対応させる。
# 基準は「/sync-template で取り込む側が [manual] 項目に気づけなければ困るか」であって、
# ディレクトリの見た目ではない。.github/ 全体ではなく .github/workflows/ に絞るのは、
# manifest に載っているのがワークフロー 5 本だけだからで、ISSUE_TEMPLATE 等は対象外。
#
# manifest から動的に生成はしない。manifest の構造変更に検査が引きずられる方が高くつく。
# owned / merge に新しい面を足すときは、この配列も同時に直す(2 箇所の手作業で足りる)。
CHANGELOG_TRIGGERS=(".claude/" ".husky/" ".codex/" ".github/workflows/" "AGENTS.md")
```

- 配列の**要素の順序**: ディレクトリ(末尾 `/`)を先に並べ、単体ファイル `AGENTS.md` を末尾に置く。
  照合ロジックは順序に依存しないが、`delegation-policy.md` / `CHANGELOG.md` の列挙とこの順序を揃える。
- 照合ロジック(63〜71 行目の `case`)は**変更しない**。末尾 `/` 付きのプレフィックス一致で、
  `.github/workflows/ci.yml` は `.github/workflows/` に前方一致して鳴る。
  `.github/ISSUE_TEMPLATE/bug.md` は前方一致しないので鳴らない。

## §2 `.claude/rules/lead/delegation-policy.md`

52 行目(表の CHANGELOG 行)の「落ちる条件」列を書き換える。

置換前:
```
| `docs/template-dev/CHANGELOG.md` | `.claude/` / `.husky/` / `.codex/` / `AGENTS.md` を変更した PR で CHANGELOG が未更新 | `no-changelog` |
```
置換後:
```
| `docs/template-dev/CHANGELOG.md` | `.claude/` / `.husky/` / `.codex/` / `.github/workflows/` / `AGENTS.md` を変更した PR で CHANGELOG が未更新 | `no-changelog` |
```

他の行・他の節は触らない。

## §3 `docs/template-dev/CHANGELOG.md`「記法」節

13 行目の運用ルール 1 行のトリガ列挙を実態に合わせる。

置換前(行頭の `- ` 以降):
```
**`.claude/` / `.husky/` / `.codex/` / `AGENTS.md` を変更する PR は、このファイルの更新も必須。**
```
置換後:
```
**`.claude/` / `.husky/` / `.codex/` / `.github/workflows/` / `AGENTS.md` を変更する PR は、このファイルの更新も必須。**
```

行の残り(CI が機械検査する旨と `no-changelog` の案内)は**そのまま残す**。

**29 行目(`## 2026-08-27` 節の中の検査1 の説明)は書き換えない。** あれは #37 時点の事実を記録した過去エントリで、
遡って書き換えると「いつ変わったか」が消える。

## §4 `docs/template-dev/CHANGELOG.md` への追記

既に `## 2026-08-29` の見出しがある(#40 の分)。**新しい日付見出しを作らず、この節の末尾**
(`- **[auto]** ハーネス改修を Codex に委託していたプロジェクトでは…` の行の直後、`## 2026-08-27` の直前)に
空行を 1 つ挟んで以下を追記する。

```markdown
**CHANGELOG 検査のトリガに `.github/workflows/` を追加した(Issue #41)。** `/sync-template` の同期対象(`owned`)にワークフロー 5 本が載っているのに、検査のトリガは 4 項目のままでした。**ワークフローだけを変更した PR は CHANGELOG 未更新でも緑**で、#37 が塞いだはずの穴が同期対象の一部で残っていました。

- **[auto]** **`check-record-hygiene.sh` の `CHANGELOG_TRIGGERS` に `.github/workflows/` を追加した**(#41)。今後は `.github/workflows/` 配下だけを変更した PR も CHANGELOG の追記が必要になります(不要な変更ならラベル `no-changelog` で外せます)。`.github/` 全体ではなく `workflows/` に絞っており、`.github/ISSUE_TEMPLATE/` 等は対象外です。あわせて、**manifest の `owned` / `merge` に面を足すときはこの配列も同時に直す**という運用をスクリプト側のコメントに明記しました(manifest からの動的生成はしません)
```

日付見出しを遡って追記しないルールに抵触しない(今日の見出しがすでに最上位にある)。

## §5 検証(手元で機械的に再現する)

`S=.claude/scripts/check-record-hygiene.sh` として、以下 7 ケースを**この順に**実行し、
出力と `rc` を `verification.md` に表で記録する。`TICKET_ISSUES=''` を必ず付ける(検査2 を鳴らさないため)。

| # | 入力 | 期待 |
| --- | --- | --- |
| V0 | `bash -n "$S"` | 構文 OK / rc=0 |
| V1 | `CHANGED_FILES='.github/workflows/ci.yml' PR_LABELS='' TICKET_ISSUES=''` | ERROR 1 件(検出パスに `.github/workflows/ci.yml`)/ rc=1 |
| V2 | V1 + `PR_LABELS='no-changelog'` | NOTICE 1 件 / rc=0 |
| V3 | `CHANGED_FILES=$'.github/workflows/ci.yml\ndocs/template-dev/CHANGELOG.md'` | 出力なし / rc=0 |
| V4 | `CHANGED_FILES='.github/ISSUE_TEMPLATE/bug.md'` | 出力なし / rc=0(`.github/` 全体では鳴らない) |
| V5 | `CHANGED_FILES='.claude/scripts/foo.sh'` | ERROR 1 件 / rc=1(既存トリガの回帰確認) |
| V6 | `CHANGED_FILES='README.md'` | 出力なし / rc=0(非トリガの回帰確認) |

実行例:
```bash
S=.claude/scripts/check-record-hygiene.sh
CHANGED_FILES='.github/workflows/ci.yml' PR_LABELS='' TICKET_ISSUES='' bash "$S"; echo "rc=$?"
```

**実 PR での確認について**: 受け入れ条件の「実 PR で確認」は、本 PR 自体では判別できない
(本 PR は `.claude/scripts/` を変更するので、`.github/workflows/` を足さなくても検査1 は鳴る)。
この扱いは司令塔が PR 作成時に判断する。**実装者は §5 の手元検証まででよい。**

## §6 品質チェック

- `bash -n .claude/scripts/check-record-hygiene.sh`
- `npx eslint .` / `npx tsc --noEmit`(変更が `.sh` / `.md` のみのため影響は無いはずだが、通す)

## 完了時に報告すること

- §1〜§4 の適用結果(差分の要点)
- §5 の 7 ケースの実測結果(期待と一致したか。ズレたケースがあれば止めて報告する)
