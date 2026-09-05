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
文言側を調整した)。

**訂正(T17)**: 上記直後に「委託禁止領域の実体・挙動は変えていない」と記載したが、
これは不正確だった。マーカー内のバックティック抽出は「コメントでない行から `h` を
source しているか」のような散文中の引用も無検証で拾うため、`settings.local.json`
(単体語)や `.husky/_/` がこの時点で `PROJECT_FORBIDDEN_PATHS` の生の抽出結果に
実際に混入していた(V1b 追加前は気づけなかった)。実害が無かったのは
`.husky/_/` が `.husky/` の部分集合であることと、裸の `settings.local.json` が
`[ -e ]` の実在検査で無視されることに支えられていたためで、**偶然機能していた**に近い。
T13 でマーカー内の表記規約(禁止領域そのものだけをバックティックで囲む)を明文化し、
該当箇所を地の文に修正して抽出結果を意図した集合に一致させた(T16 の V1b で確認)。

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

## 検収の指摘反映(code-reviewer 1 巡目: T13〜T18)

### T13: AGENTS.md §4 マーカー内の意図しないバックティック断片を除去

- 150 行目の `` `settings.local.json` ``(単体語)を地の文の `settings.local.json` に変更。
- 153 行目の 2 箇所の `` `.husky/_/` `` を地の文の `.husky/_/` に変更し、行末に
  「この節のバックティックは禁止領域そのもののパスにだけ使い、説明のための例示は
  地の文で書きます」という表記規約の 1 文を追記した。
- 行頭の項目名 `` `.claude/settings.local.json` `` / `` `.husky/` `` は変更していない。

### T14: `WRAPPER_RE` の行末インラインコメント許容

`WRAPPER_RE` を `'^[^#]*(source|\.)[[:space:]]+[^#]*/h"?[[:space:]]*(#.*)?$'` に変更
(`(#.*)?` を追加。行末アンカー `$` は維持)。あわせて、アンカーを外さない理由
(検査 4 の INVOKE_RE との違い)をコメントに追記した。

```
$ cp .husky/_/pre-commit /tmp/_pc.bak2
$ printf '#!/usr/bin/env sh\n. "$(dirname "$0")/h" # husky dispatcher\n' > .husky/_/pre-commit
$ bash .claude/scripts/check-guard-integrity.sh; echo "exit=$?"
exit=0
$ cp /tmp/_pc.bak2 .husky/_/pre-commit && rm /tmp/_pc.bak2
$ bash .claude/scripts/check-guard-integrity.sh; echo "exit=$?"
exit=0
```

→ **PASS**。行末にインラインコメントが付いたラッパは偽陽性を出さなくなった。
無効化されたラッパ(exit 0 の 2 行)を検出する挙動(V3 と同じ)は変わらず維持されている
(下記 T18 再実行で確認)。

### T15: CHANGELOG.md の追記漏れ注意を追記

`docs/template-dev/CHANGELOG.md` の 2026-09-05 エントリの「取り込む側の作業」に、
`.claude/settings.local.json` 行の追記漏れに注意する 1 文を追加した。

### T16: V1 の穴を塞ぐ完全一致検証(V1b)

```
$ bash .claude/scripts/delegate-codex.sh --print-forbidden | LC_ALL=C sort -u | diff - /tmp/expected-forbidden.txt && echo "V1b PASS"
V1b PASS
```

→ **PASS**。期待した 17 エントリとの完全一致を確認し、T13 で除去した意図しない断片
(単体語 `settings.local.json` / `.husky/_/`)が抽出結果に残っていないことを確認した。

### T17: V1 の記述訂正

V1 セクションに **訂正(T17)** の段落を追記し、「委託禁止領域の実体・挙動は変えていない」
という当初の記述を訂正した(詳細は当該段落を参照。要点: マーカー内の生の抽出結果は
実際に変化しており、T13 の修正はその変化を意図した集合に一致させるものだった)。

### T18: 再検証(V3 再実行 + 静的検査)

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

V3(無音化検出 → 復元)を pre-commit / prepare-commit-msg の両方で再実行:

```
$ bash .claude/scripts/check-guard-integrity.sh; echo "baseline exit=$?"
baseline exit=0
$ printf '#!/usr/bin/env sh\nexit 0\n' > .husky/_/pre-commit
$ bash .claude/scripts/check-guard-integrity.sh; echo "exit=$?"
(指摘 1 行) exit=1
$ cp /tmp/_pc.bak .husky/_/pre-commit && rm /tmp/_pc.bak
$ bash .claude/scripts/check-guard-integrity.sh; echo "exit=$?"
exit=0
$ printf '#!/usr/bin/env sh\nexit 0\n' > .husky/_/prepare-commit-msg
$ bash .claude/scripts/check-guard-integrity.sh; echo "exit=$?"
(指摘 1 行) exit=1
$ cp /tmp/_pcm.bak .husky/_/prepare-commit-msg && rm /tmp/_pcm.bak
$ bash .claude/scripts/check-guard-integrity.sh; echo "exit=$?"
exit=0
```

`git status --porcelain --ignored=matching -- .husky/_` で `.husky/_` 配下が
すべて `!!`(gitignore 済み・追跡外)のままであることを確認し、復元漏れが無いことを確認した。

→ **PASS**(全項目)。T13〜T18 の変更後も検査 5 の検出・復元後の無音化がいずれも
design の期待どおりに機能している。

## 補足: 検証中に混入した無関係な差分

検証コマンド(`npx prettier` 等の npm 実行)の副作用で `package-lock.json` から
`libc` フィールドが 30 行削除される差分が発生した。本チケットのスコープ外のため
`git checkout -- package-lock.json` で元に戻した(コミット対象に含めていない)。
