# 検証結果: D2.5(`.git/config` 実行ベクタ検査)Issue #58

すべてこのリポジトリのワーキングツリーで実測。各シナリオは「設定 → 検査 → 復元」を同一コマンド行で実施し、
検証後に `.git/config` へキーが残っていないことを確認済み。

## §4-0 事前確認

```
bash -n .claude/scripts/check-guard-integrity.sh          # exit=0
git config --local --list | grep -cE '...'                # 0
```

## §4-1 誤爆しないこと(受け入れ条件2)

```
bash .claude/scripts/check-guard-integrity.sh degraded; echo "exit=$?"
```

結果: 出力なし、`exit=0`。D2.5 由来の行は 0 行(誤爆なし)。

## §4-2 各キーの検出結果

| # | KEY | VALUE | 結果 |
| --- | --- | --- | --- |
| C1 | `core.fsmonitor` | `echo pwned` | 検出(受け入れ条件1)。出力: `.git/config(local)に core.fsmonitor=echo pwned が設定されている(git status 等のたびに実行される)。` |
| C2 | `core.sshCommand` | `ssh -o ProxyCommand=curl evil` | 検出。キーは `core.sshcommand`(git の正規化どおり小文字)として出力 |
| C3 | `core.pager` | `sh -c "echo pwned"` | 検出 |
| C4 | `credential.helper` | `!echo pwned` | 検出 |
| C5 | `credential.https://example.com.helper` | `!echo pwned` | 検出(URL 付きサブセクション形も一致) |
| C6 | `filter.evil.clean` | `sh -c "echo pwned"` | 検出 |
| C7 | `filter.evil.smudge` | `sh -c "echo pwned"` | 検出 |
| C8 | `include.path` | `/tmp/evil.cfg` | 検出 |
| C9 | `alias.evil` | `!echo pwned` | 検出(`git <alias> 実行時に shell が走る`) |
| C10 | `alias.harmless` | `status --short` | **検出しない**。`grep -F 'alias.harmless'` は exit=1(何も返らない)。判断4のとおり `!` 無しエイリアスは対象外 |
| C11 | `url.https://evil.example.com/.insteadOf` | `https://github.com/` | 検出。キーは `url.https://evil.example.com/.insteadof`(サブセクション部は保持、キー名部のみ小文字化)として出力 |
| C12 | `url.https://evil.example.com/.pushInsteadOf` | `https://github.com/` | 検出(同上) |
| C13 | `core.editor` | `sh -c "echo pwned"` | 検出 |
| C14 | `sequence.editor` | `sh -c "echo pwned"` | 検出 |
| C15 | `core.gitProxy` | `sh -c "echo pwned"` | 検出(キーは `core.gitproxy`) |
| C16 | `diff.evil.command` | `sh -c "echo pwned"` | 検出 |
| C17 | `merge.evil.driver` | `sh -c "echo pwned"` | 検出 |
| C18 | `includeIf.gitdir:/workspaces/.path` | `/tmp/evil.cfg` | 検出。**司令塔が実測**(1 巡目では `includeif.*.path` の `gitdir:` サブセクション形が未実測だった)。検出を確認し、検証後に残留 0 件も確認済み |

補足(判断4 の実測記録): `git config --local alias.status '!echo HIJACKED'` を仕込んでローカルで `git status` を実行したところ、
本来の `git status` の動作となり、shell 経由の乗っ取りは発生しなかった(git は組み込みサブコマンドを上書きするエイリアスを無視する)。
これにより「`!` 形式のエイリアスだけを対象にする」という判断4の妥当性を確認した。

## §4-3 値の切り詰めと多行値

```
git config --local core.pager "$(printf 'AAAA%.0s' {1..200})"; bash .claude/scripts/check-guard-integrity.sh degraded | grep -F 'core.pager'
```

結果: 出力は 1 行に収まり、120 文字の `A` の後に `…` で切り詰められていることを確認(`AAAA...A…`)。

## §4-4 後始末

```
git config --local --list | grep -cE '^(core\.(fsmonitor|sshcommand|pager)|credential\.|filter\.|include\.|includeif\.|alias\.)'   # → 0
git status --short   # .git/config はワークツリー外のため差分に現れず、意図しない変更なし
```

結果: 検証用キーは 1 つも残っていない。`git status --short` にも `.git/config` 由来の差分は出ない(想定どおり)。

## §4-4 再実行(2 巡目・C11〜C18 追加後)

```
git config --local --list | grep -cE '^(core\.(fsmonitor|sshcommand|pager|editor|gitproxy)|sequence\.editor|credential\.|url\.|filter\.|diff\.|merge\.|include\.|includeif\.|alias\.)'   # → 0
git config --local --list | grep -E '^(url\.|diff\.|merge\.)'   # → 該当なし(空セクション残留なし)
git status --short
```

結果: 追加した危険キーの残留は 0 件。`url.*` / `diff.*` / `merge.*` の空セクション残留も無し(`--unset-all` 後の `--remove-section` が効いている)。`git status --short` に現れるのはこのチケットの実装差分(`.claude/` / `docs/` の変更ファイルと `.steering/` の新規ディレクトリ)のみで、`.git/config` 由来の意図しない差分は無い。

**注記(環境依存)**: 判断2 の根拠(`--global` / `--system` に `credential.helper` の `!` 形式が既定で置かれている)は、このテンプレートリポジトリの devcontainer 1 インスタンスでの実測値。配布先の devcontainer 構成では成立しないことがあるため、`--local` 限定という設計判断を見直す場合はその環境で再実測すること。
