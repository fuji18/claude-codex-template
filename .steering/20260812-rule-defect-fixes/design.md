# 設計: 実装ルールの欠陥修正とドキュメント整合

## 1. `implement-ticket` の allowed-tools(重大)

`allowed-tools` は Bash の限定パターンだけを列挙しており、Read / Edit / Write / Grep / Glob が無い。この宣言が fork 先に効く場合、implementer は編集できず全チケットが即失敗する。SKILL 本文が指示する `ls -1d .steering/*/` すら allowlist 外。

**対応**: `allowed-tools` 行を削除する。design(前作業)の方針 A どおり、権限の担保は `.claude/settings.json` の `permissions.allow` と `implementer` エージェントの `tools:` に一本化する。スキル側で二重に絞ると、片方の更新漏れがそのまま「実装できない」に直結する。

## 2. ステアリング最新判定の統一(重大)

現行 `ls -1d .steering/*/ | sort -r | head -1` は**ディレクトリ名全体**の降順のため、同日では機能名の文字順で決まる(`20260812-fork-...` が `20260812-add-...` に勝つ)。

**規則**: 日付プレフィックス(先頭 8 桁)の降順を第一キー、同日は mtime の降順を第二キーとする。

**実装**: `.claude/scripts/latest-steering.sh` を新設し、選定ロジックを 1 箇所にまとめる。

```bash
ls -1dt .steering/*/ |
  awk '{ d=$0; sub(/^\.steering\//,"",d); print substr(d,1,8) "\t" $0 }' |
  sort -k1,1r -s | cut -f2 | head -1
```

`ls -t` が mtime 降順を作り、`sort -s`(安定ソート)が同日内のその順序を保つ。クローン直後で mtime が揃っていても日付プレフィックスで決まるため決定的。

呼び出し側:

- `.claude/scripts/check-implementation-phase.sh` — 自前の `ls ... sort -r` を置換
- `.claude/hooks/session-start.sh` — 同上
- `.claude/skills/implement-ticket/SKILL.md` / `.claude/agents/implementer.md` — 散文中のコマンド例を新スクリプト呼び出しに差し替える

## 3. テンプレート同梱 steering の掃除(重大)

`.steering/20260812-fork-implementation-phase/tasklist.md` には `<!-- main-edit-ok -->` があり、これが「最新」と判定されている間は実装フェーズのブロックが無効になる。テンプレートから作った新規プロジェクトはこれを引き継ぐ。

**対応**(2 段構え):

1. `/kickoff` のフェーズ 5(README 書き換え)に、テンプレート由来の `.steering/*/` を削除する手順を追加する
2. `check-implementation-phase.sh` の脱出弁を**現行 HEAD にコミット済みの tasklist では無効化しない**……のは複雑すぎるため採らない。代わりに、脱出弁マーカーの直上コメント(既存)に加え、`/kickoff` の削除手順を単一の対策とする

## 4. hook の誤爆(重大)

`check-branch-policy.sh` の `gh pr create` 検出と `block-dangerous-cmds.sh` の各パターンが、**引用符の中の文字列**にも一致する(実証: `grep -E "...|pr create"` がブロックされた)。

**対応**: コマンド位置に限定する共通の接頭辞を付ける。

```
CMD_START='(^|[;&|(]|&&|\|\|)[[:space:]]*'
```

- `check-branch-policy.sh`: `git commit` / `gh pr create` の両検出に付与
- `block-dangerous-cmds.sh`: `rm -rf` / `git push` / `git commit --amend` / `publish` に付与
- SQL(`DROP TABLE` / `TRUNCATE TABLE`)は文字列としての出現が多いため、**DB クライアント経由の実行に限定**する。パターンを `(psql|mysql|sqlite3|mongosh|prisma|npx prisma)` から始まる行に付ける形へ変更する

いずれも「サンドボックスではなくベストエフォート」という既存の位置づけは変えない。

## 5. `/fix-issue` の検証ステップ(中)

現行は `/check` のみで `code-reviewer` が起動しない。`develop` 運用のプロジェクトでは PR レビューも走らないため、レビューゼロで PR に到達する経路になる。

**対応**: `/add-feature` ステップ 6 と同じく `code-reviewer` + `test-runner` の**並列起動**に置き換える。ステップ 6 のコミットも生 `git commit -m` をやめ `Skill('commit')` に統一する。

## 6. permissions の穴(中)

`git fetch` / `git merge` / `gh pr create` が `permissions.allow` に無く、`/add-feature` の「完全無停止」と矛盾する。

**対応**: `.claude/settings.json` の `allow` に `Bash(git fetch:*)` / `Bash(git merge:*)` / `Bash(gh pr create:*)` を追加する。`git merge` は破壊的操作ではなく、ブランチポリシー hook が base を検査するため追加してよい。

## 7. 品質チェックの多重実行(中)

fork 内 → 検収の test-runner → CI で 3 回走る。層を削るのではなく、**役割を分ける**:

- fork(`implement-ticket` 手順 3): 「変更したファイルを対象に lint・型チェックと**関連するテスト**を実行し、機械的なエラーを直す」= 自己修復
- 検収(`/add-feature` ステップ 6 の test-runner): フルスイート 1 回
- CI: 最終ゲート

`review-policy.md` の「二重に回すのは無駄」の記述に、この役割分担の 1 行を足して矛盾を解く。

## 8. ドキュメント整合(軽)

| ファイル | 修正 |
| --- | --- |
| `docs/template-dev/README.md` | 索引に `CHANGELOG.md` / `cost-model.md` / `dependabot-product.example.yml` を追加 |
| `.claude/skills/harness-setup/SKILL.md` | `claude-opus-4-8` → `claude-opus-5`(2 箇所) |
| `.claude/rules/lead/review-policy.md` | 「push / PR ごと」→ 実態(push は main/develop、PR は全て)に修正 |
| `CLAUDE.md` | ディレクトリ構造節に `.claude/docs/` を追加 |
| `README.md` | 「hook で強制される」→ Edit/Write に限る旨を明記。テンプレート由来 `.steering/` の掃除に言及 |
| `.steering/20260812-fork-implementation-phase/requirements.md` | 受け入れ条件のチェックを実態に更新(fork の実地検証だけ未達として残す) |
| `docs/template-dev/CHANGELOG.md` | 今回の変更を `[auto]` / `[manual]` 区分で追記 |

## 影響ファイル

- 新規: `.claude/scripts/latest-steering.sh`
- 更新: `.claude/scripts/{check-implementation-phase,check-branch-policy,block-dangerous-cmds}.sh` / `.claude/hooks/session-start.sh` / `.claude/skills/implement-ticket/SKILL.md` / `.claude/agents/implementer.md` / `.claude/commands/{fix-issue,kickoff}.md` / `.claude/settings.json` / `.claude/rules/lead/review-policy.md` / `.claude/skills/harness-setup/SKILL.md` / `CLAUDE.md` / `README.md` / `docs/template-dev/{README,CHANGELOG}.md` / 前作業の `requirements.md`
