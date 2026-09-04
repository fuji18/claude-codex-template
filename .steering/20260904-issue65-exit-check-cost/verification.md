# 検証記録: 出口検査の固定費を下げる(Issue #65)

検証ドライバ(`$SCRATCH/snap.sh`、design.md §3-1 のとおり)をスクラッチパッドに作成し、
`old.sh`(実装前の HEAD = `git show HEAD:.claude/scripts/delegate-codex.sh`)と
新版(`.claude/scripts/delegate-codex.sh`)を突き合わせた。ドライバ自体はコミットしない。

## ケース A: 実リポジトリの禁止領域そのまま(受け入れ条件 1)

```bash
bash "$SCRATCH/snap.sh" "$SCRATCH/old.sh"                 > "$SCRATCH/a-old.txt" 2>"$SCRATCH/a-old.err"
bash "$SCRATCH/snap.sh" .claude/scripts/delegate-codex.sh > "$SCRATCH/a-new.txt" 2>"$SCRATCH/a-new.err"
diff "$SCRATCH/a-old.txt" "$SCRATCH/a-new.txt" && echo "A: 一致"
```

結果:

- stderr(旧/新とも): 空
- `diff`: 差分なし → `A: 一致`
- 行数: 旧 164 行 / 新 164 行(一致)

## ケース B: 不在パス・ディレクトリ・空ファイル混在(受け入れ条件 2)

フィクスチャ(`$FIX`)を作成:

```bash
FIX="$SCRATCH/fix"
rm -rf "$FIX" && mkdir -p "$FIX/sub" "$FIX/dir_as_file"
printf 'alpha\n' > "$FIX/a.txt"
: > "$FIX/empty.txt"
printf 'one\n'  > "$FIX/sub/1.txt"
printf 'two\n'  > "$FIX/sub/2.txt"
export TEST_FORBIDDEN="'$FIX/a.txt' '$FIX/empty.txt' '$FIX/sub/' '$FIX/dir_as_file' '$FIX/missing.txt'"

bash "$SCRATCH/snap.sh" "$SCRATCH/old.sh"                 > "$SCRATCH/b-old.txt" 2>"$SCRATCH/b-old.err"
bash "$SCRATCH/snap.sh" .claude/scripts/delegate-codex.sh > "$SCRATCH/b-new.txt" 2>"$SCRATCH/b-new.err"
diff "$SCRATCH/b-old.txt" "$SCRATCH/b-new.txt" && echo "B: 一致"
```

結果:

- stderr(旧/新とも): 空
- `diff`: 差分なし → `B: 一致`
- 出力内容(新版。`$FIX` はスクラッチパッド配下の絶対パス):

  ```
  4a58007052a65fbc2fc3f910f2855f45a4058e74 $FIX/a.txt
  UNREADABLE $FIX/dir_as_file
  e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 $FIX/empty.txt
  5626abf0f72e58d7a153368ba57db4c673c0e171 $FIX/sub/1.txt
  f719efd430d52bcfc8566a43b2eb655688d38871 $FIX/sub/2.txt
  ```

- `UNREADABLE $FIX/dir_as_file` が 1 行あること: 確認済み
- `missing.txt` の行が無いこと: 確認済み(5 行のみ、`missing.txt` への言及なし)
- `dir_as_file` の存在により `git hash-object --stdin-paths` が全ファイル分を返せず、
  出力行数(4)と入力行数(5)が不一致になるため、バッチ経路からフォールバック
  (1 ファイルずつ)へ落ちる。落ちた上で旧版と出力が完全一致することを確認した。

## ケース C: 改ざん検出(受け入れ条件 3)

### C-1: フォールバック経路(`dir_as_file` を含む混在フィクスチャのまま)

```bash
bash "$SCRATCH/snap.sh" .claude/scripts/delegate-codex.sh > "$SCRATCH/c-before.txt"
printf 'x' >> "$FIX/sub/1.txt"
bash "$SCRATCH/snap.sh" .claude/scripts/delegate-codex.sh > "$SCRATCH/c-after.txt"
diff "$SCRATCH/c-before.txt" "$SCRATCH/c-after.txt"
cat "$SCRATCH/c-before.txt" "$SCRATCH/c-after.txt" | sort | uniq -u
```

結果(`diff`):

```
4c4
< 5626abf0f72e58d7a153368ba57db4c673c0e171 $FIX/sub/1.txt
---
> 3cb87fc91fbd8402b0c4f398e3f0ff170481c2c0 $FIX/sub/1.txt
```

`sort | uniq -u`(出口検査本体と同じ突き合わせ)でも `sub/1.txt` の 2 行(前後のハッシュ)
だけが残り、他ファイルの行は現れなかった。**`sub/1.txt` の行だけが差分**という期待どおり。

### C-2: バッチ経路そのものの改ざん検出

`dir_as_file` を削除し、全ファイルが読める構成(= `--stdin-paths` が完走してバッチ結果を
採用する構成)にしてから同じ手順を回した:

```bash
rmdir "$FIX/dir_as_file"
export TEST_FORBIDDEN="'$FIX/a.txt' '$FIX/empty.txt' '$FIX/sub/'"

bash "$SCRATCH/snap.sh" .claude/scripts/delegate-codex.sh > "$SCRATCH/c2-before.txt"
printf 'y' >> "$FIX/sub/2.txt"
bash "$SCRATCH/snap.sh" .claude/scripts/delegate-codex.sh > "$SCRATCH/c2-after.txt"
diff "$SCRATCH/c2-before.txt" "$SCRATCH/c2-after.txt"
cat "$SCRATCH/c2-before.txt" "$SCRATCH/c2-after.txt" | sort | uniq -u
wc -l "$SCRATCH/c2-before.txt"
```

結果(`diff`):

```
4c4
< f719efd430d52bcfc8566a43b2eb655688d38871 $FIX/sub/2.txt
---
> cc08769ce0fce4e036c9cd1bb7d1b50ba2a1c111 $FIX/sub/2.txt
```

`sort | uniq -u` でも `sub/2.txt` の 2 行だけが残った。入力ファイル数と一致する 4 行が
出力されており(`wc -l` = 4)、入力行数と出力行数が一致 → バッチ経路(`--stdin-paths`)が
採用されたことを確認した上での改ざん検出。**フォールバックとバッチの両方で検出できることを
確認済み。**

## ケース D: `--print-forbidden` の短絡(受け入れ条件 4・5)

出力の同一性:

```bash
bash "$SCRATCH/old.sh" --print-forbidden               > "$SCRATCH/d-old.txt" 2>/dev/null
bash .claude/scripts/delegate-codex.sh --print-forbidden > "$SCRATCH/d-new.txt" 2>/dev/null
diff "$SCRATCH/d-old.txt" "$SCRATCH/d-new.txt" && echo "D: 一致"
```

結果: `diff` 差分なし → `D: 一致`。行数: 旧 32 行 / 新 32 行(一致)。

短絡していることの観測(`mktemp -d` を失敗させる):

```bash
TMPDIR=/nonexistent-dir bash "$SCRATCH/old.sh" --print-forbidden 2>&1 >/dev/null | head -2
TMPDIR=/nonexistent-dir bash .claude/scripts/delegate-codex.sh --print-forbidden 2>&1 >/dev/null | head -2
```

結果:

- 旧版: `delegate-codex: 警告 — 自身の一時コピーを作れませんでした。委託中にこのスクリプトが書き換わると異常終了します。`
- 新版: 出力なし(空)→ 短絡していることを確認

波及がないこと(`--print-forbidden` 以外は従来どおり自己コピーを試みる):

```bash
TMPDIR=/nonexistent-dir bash .claude/scripts/delegate-codex.sh explore "dummy" 2>&1 >/dev/null | head -2
```

結果(新版 explore モード):

```
delegate-codex: 警告 — 自身の一時コピーを作れませんでした。委託中にこのスクリプトが書き換わると異常終了します。
delegate-codex: ワークツリーに機密の可能性があるファイルがあります。
```

→ 短絡は `--print-forbidden` のみで、他モードは従来どおり警告することを確認した。

consumer からの疎通:

```bash
bash .claude/scripts/check-guard-integrity.sh degraded
echo "exit=$?"
```

結果: `exit=0`、標準出力・標準エラーとも空(警告 0 件)。
`$DELEGATE --print-forbidden が委託禁止領域を返さない` という警告文字列の出現件数を
`grep -c` で確認したところ 0 件だった。**期待どおり出ないことを確認した。**

## まとめ

ケース A〜D すべてで期待どおりの結果を得た。バッチ化(`git hash-object --stdin-paths`)は
正常系で旧版と完全に同一の出力を返し、`--stdin-paths` が完走できない構成(ディレクトリを
指したパスなど)では自動的に 1 ファイルずつのフォールバックへ落ちて、判定内容(改ざん検出・
`UNREADABLE` の扱い)は変わらないことを確認した。`--print-forbidden` の自己コピー短絡は
出力を変えず、他モードへの波及もない。
