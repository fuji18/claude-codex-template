# 検証記録: #80

design.md §5 の V1〜V5 の実行結果をここに記録する(コマンドと実際の出力)。

## V1: 配列と出力

```
$ bash .claude/scripts/delegate-codex.sh --print-forbidden | grep -E '^(\.husky/|\.claude/settings\.local\.json)$'
.claude/settings.local.json
.husky/
.claude/settings.local.json
.husky/
```

(汎用項目 `FORBIDDEN_PATHS` とAGENTS.md §4 マーカーからの `PROJECT_FORBIDDEN_PATHS` の両方に
1 回ずつ現れるため 2 回ずつ出力される。設計は重複除去を要求していないので想定どおり)

```
$ bash .claude/scripts/delegate-codex.sh --print-forbidden | grep -E '^\.husky/(pre-commit|prepare-commit-msg)$'
(no output)
exit=1
```

→ **PASS**。旧記法 `.husky/pre-commit` / `.husky/prepare-commit-msg` は配列からも
AGENTS.md 由来の抽出からも消えている。

**実装時の追加修正**: 最初、AGENTS.md §2-3(b) の説明文中で `.husky/pre-commit` を
バッククォートで具体的に例示していたため、マーカー内バックティック抽出の対象になり
`.husky/pre-commit` が `PROJECT_FORBIDDEN_PATHS` に復活してこの検査に失敗した。
説明文の意味を変えずに「配下のフック」という表現に変更し、リテラルな
`.husky/pre-commit` のバックティック引用を避けることで解消した(design 自身の
V1 の受け入れ条件と、design 2-3(b) の例示的な文言が両立しない状態だったため、
文言側を調整した。委託禁止領域の実体・挙動は変えていない)。

## V2: ラッパが列挙対象に入ったか

```
$ find .husky -type f -print | grep -E '_/(pre-commit|prepare-commit-msg|h)$'
.husky/_/prepare-commit-msg
.husky/_/pre-commit
.husky/_/h
```

→ **PASS**(3 行)。

## V3: `check-guard-integrity.sh` が無音化を検出するか

`pre-commit` を `exit 0` の 2 行に置き換えた場合:

```
$ printf '#!/usr/bin/env sh\nexit 0\n' > .husky/_/pre-commit
$ bash .claude/scripts/check-guard-integrity.sh; echo "exit=$?"
.husky/_/pre-commit が husky のディスパッチャ(h)を source していない。.husky/pre-commit
が呼ばれないまま保護ブランチ上の git commit / git commit --amend が通る
(.husky/_ は git 追跡外なので git diff にも出ない)
exit=1
```

復元後:

```
$ cp /tmp/_pc.bak .husky/_/pre-commit
$ bash .claude/scripts/check-guard-integrity.sh; echo "exit=$?"
(no output)
exit=0
```

`prepare-commit-msg` でも同様に実施し、同じ結果(検出時 exit=1・復元後 exit=0)を確認した。
→ **PASS**。最終的に `npx husky` で両ファイルを正規状態に復元し、
`check-guard-integrity.sh` の無出力・exit=0 を確認済み。

## V4: 静的検査と既存 CI 相当

```
$ bash -n .claude/scripts/delegate-codex.sh
delegate-codex.sh OK
$ bash -n .claude/scripts/check-guard-integrity.sh
check-guard-integrity.sh OK
$ bash .claude/scripts/check-forbidden-paths-doc.sh; echo "exit=$?"
exit=0
$ npx prettier --check CLAUDE.md AGENTS.md docs/template-dev/CHANGELOG.md
All matched files use Prettier code style!
```

→ **PASS**(全項目)。

## V5: 出口検査の再現テスト

この環境に `codex` CLI が無いため(`which codex` → exit 1)、design 記載のスタブで代替した。

**設計の例示スタブそのままでは到達できなかった。** `delegate-codex.sh` は入口検査で
`codex login status` を実行しており(委託の実行本体である `codex exec` より前)、
design のスタブは引数を見ずに毎回 `.husky/_/pre-commit` を書き換える実装だったため、
`login status` 呼び出しの時点で禁止領域が改ざんされ、その後に取得される
`FORBIDDEN_BEFORE` スナップショットが「すでに改ざん済みの内容」を基準にしてしまい、
本来検出したかった `codex exec` 由来の改ざんと差分が出ず、出口検査ではなく
「exit 0 だが成果物が確認できない」(tree_snapshot 不変)の失敗経路に流れた
(exit=2 は同じだが理由が異なる。デバッグは `CODEX_DELEGATE_NO_SELF_COPY=1` で
自己コピーを無効化し `bash -x` のトレースで `FORBIDDEN_BEFORE` / `FORBIDDEN_AFTER` の
実際のハッシュ値を比較して特定した)。

スタブを「`$1` が `exec` のときだけ副作用を起こし、`login` のときは何もせず exit 0」に
修正して再実行したところ、design の期待どおりの結果を得た:

```
$ CODEX_DELEGATE_NO_SELF_COPY=1 PATH="$STUB:$PATH" bash .claude/scripts/delegate-codex.sh impl \
    .steering/20260905-issue80-gitignored-host-exec-paths
...
⚠️ 委託禁止領域が変更されました(出口検査): .husky/_/pre-commit
delegate-codex: 委託禁止領域のファイルが変更されました(出口検査)。
...
RESULT_EXIT=2
```

`.claude/settings.local.json` 側も同じ改修済みスタブ(`printf '{}' > .claude/settings.local.json`)
で再現し、同様に `⚠️ 委託禁止領域が変更されました(出口検査): .claude/settings.local.json` と
`RESULT_EXIT=2` を確認した。検証後、`.husky/_/pre-commit` は `npx husky` で正規状態に復元し
(`check-guard-integrity.sh` の無出力・exit=0 で確認済み)、`.claude/settings.local.json` は
削除した。

→ **PASS**(スタブを引数分岐に修正のうえ再現。design が新設した検査 5・および
`.claude/settings.local.json` の禁止領域化の両方が、出口検査で `exit=2` として
機能することを確認)。この修正は検証用スタブ(自作の再現スクリプト)の作り直しであり、
`delegate-codex.sh` 本体・`check-guard-integrity.sh` 本体には一切手を入れていない。

## 補足: 検証中に混入した無関係な差分

検証コマンド(`npx prettier` 等の npm 実行)の副作用で `package-lock.json` から
`libc` フィールドが 30 行削除される差分が発生した。本チケットのスコープ外のため
`git checkout -- package-lock.json` で元に戻した(コミット対象に含めていない)。
