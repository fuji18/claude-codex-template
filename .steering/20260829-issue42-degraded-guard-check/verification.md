# 実測: モード C 復帰時のガードレール健全性検査(Issue #42)

design.md §6 の 5 シナリオ + 3 確認を実行した記録。使い捨てリポジトリで実行し、
本リポジトリは汚していない。

## 実装上の変更点(design.md からの差異)

D2(`.git/hooks/` に直書きされたフックが無いか)で、design.md が指定した
`git rev-parse --git-path hooks` をそのまま使うと、**core.hooksPath が
`.husky/_` を指す健全な状態でも false positive になる**ことが実測で判明した。
`--git-path hooks` は `core.hooksPath` を尊重してその値をそのまま返す仕様のため
(`.husky/_` を指している場合はそのパスが返る)、`.husky/_` 配下の正規フックを
「`.git/hooks/` に直書きされたフック」と誤検知してしまい、design.md §6 シナリオ1
(「何も壊れていない状態で degraded → 出力なし / exit 0」)を満たせなかった。

物理的な `.git/hooks/` を常に見るため、`git rev-parse --git-dir` から手で
`/hooks` を組み立てる形に変更した(`check-guard-integrity.sh` 内のコメントに
理由を明記済み)。意図(`.git/hooks/` への直書きを検出する)は design.md の
説明文と変わらない。

## 使い捨てリポジトリでのシナリオ 1〜5

セットアップ:

```bash
WORK="$(mktemp -d)"
git -C "$WORK" init -q
cp -r .claude .husky .codex AGENTS.md package.json "$WORK"/
cd "$WORK"
git config user.email test@example.com
git config user.name test
git add -A && git commit -q -m "chore: baseline"
git config core.hooksPath .husky/_
```

### シナリオ1: 何も壊れていない状態

```
$ bash .claude/scripts/check-guard-integrity.sh degraded
(出力なし)
$ echo $?
0
```

期待どおり(出力なし / exit 0)。

### シナリオ2: `core.hooksPath` を `.git/hooks` に書き換え

```
$ git config core.hooksPath .git/hooks
$ bash .claude/scripts/check-guard-integrity.sh degraded
core.hooksPath が .husky 配下以外(.git/hooks)を指している。ベンダー非依存の git hook 層が迂回されている
$ echo $?
1
```

期待どおり。以降 `git config core.hooksPath .husky/_` で復元して次のシナリオへ。

### シナリオ3: `.git/hooks/pre-commit` を実行可能で直書き

まず sample のみの状態(何もしていない状態)で確認:

```
$ bash .claude/scripts/check-guard-integrity.sh degraded
(出力なし)
$ echo $?
0
```

`.git/hooks/pre-commit.sample` のままでは鳴らないことを確認済み。次に実行可能な
`pre-commit` を直書き:

```
$ printf '#!/bin/bash\necho hi\n' > .git/hooks/pre-commit
$ chmod +x .git/hooks/pre-commit
$ bash .claude/scripts/check-guard-integrity.sh degraded
.git/hooks/pre-commit が直書きされている(git 同梱の *.sample 以外の実行可能フック)。core.hooksPath を戻すだけで .husky/ を迂回できる状態
$ echo $?
1
$ rm -f .git/hooks/pre-commit
```

期待どおり。

### シナリオ4: `AGENTS.md` を変更した `Codex-authored: true` コミット

npm 依存が未インストールのため `.husky/_/pre-commit` の `npx lint-staged` が
失敗し通常の `git commit` は通らなかった(このリポジトリの構成では想定内。
D3 のテスト目的でコミット自体を成立させるため `--no-verify` を使用):

```
$ echo "test change" >> AGENTS.md
$ git add AGENTS.md
$ git commit -q --no-verify -m "feat: test change to AGENTS.md

Codex-authored: true"
$ bash .claude/scripts/check-guard-integrity.sh degraded
縮退中のコミット cfe9867 が委託禁止領域 AGENTS.md を変更している。マージ前に内容を確認すること(delegate-codex.sh の出口検査が掛かっていない経路)
$ echo $?
1
```

期待どおり。その後 `git reset --hard HEAD~1` で戻してシナリオ5へ。

### シナリオ5: 禁止領域外(`README.md`)だけの `Codex-authored` コミット

```
$ echo "test" > README.md
$ git add README.md
$ git commit -q --no-verify -m "docs: add README

Codex-authored: true"
$ bash .claude/scripts/check-guard-integrity.sh degraded
(出力なし)
$ echo $?
0
```

期待どおり(出力なし / exit 0)。

## 本リポジトリでの 3 確認

```
$ bash .claude/scripts/check-guard-integrity.sh
(出力なし)
$ echo $?
0

$ bash .claude/scripts/delegate-codex.sh --print-forbidden | wc -l
22
$ bash .claude/scripts/delegate-codex.sh --print-forbidden >/dev/null
$ echo $?
0

$ bash .claude/scripts/check-guard-integrity.sh bogus
使い方: check-guard-integrity.sh [degraded]
$ echo $?
2
```

- 引数なしの既存呼び出しは従来どおり無出力 / exit 0(この改修による退行なし)
- `--print-forbidden` は codex CLI 不在でも exit 0 で返り、汎用項目 10 行 +
  プロジェクト固有パス(本リポジトリの `AGENTS.md` §4 抽出分)を含め 22 行を出力
- 未知サブコマンドは使い方を stderr に出して exit 2
