# 設計: 出口検査の固定費を下げる(Issue #65)

<!-- status: ready -->

対象ファイルは `.claude/scripts/delegate-codex.sh` の 1 本だけ。
以下に置換内容をそのまま書く。**設計判断は残していない。**

---

## 1. `forbidden_snapshot()` のバッチ化

### 現状(置換対象)

`forbidden_snapshot()` の関数本体。`forbidden_files | sort -u` の各行に対して
`git hash-object -- "$_f"` をプロセス起動し、失敗したら `UNREADABLE` を置く。

現行が持っている性質(**壊してはいけない**):

- 出力は `<hash> <path>` を `LC_ALL=C sort -u` 順に 1 行 1 ファイル
- 個々のファイルのハッシュ計算失敗は**握りつぶして `UNREADABLE`** にする。
  前後どちらの時点でも同じように失敗すれば差分ゼロになるのが意図(`:1090` のコメント)
- ディレクトリを値に持つパス(末尾 `/` を書き忘れた指定など)は `[ -e ]` を通り、
  `git hash-object` が失敗して `UNREADABLE` になる

### 置換後(この内容にする)

```bash
forbidden_snapshot() {
  local _f _h _i _batch_ok
  local -a _files=() _hashes=()

  # sort -u なのは重複を畳むため(汎用項目とマーカー内の項目は重なる。ディレクトリ指定と
  # その配下ファイルの二重指定も起こりうる)。重複行が残ると、出口検査の違反抽出
  # (sort | uniq -u)が「2 回現れる行」として違反パスを取りこぼす。
  while IFS= read -r _f; do
    _files+=("$_f")
  done < <(forbidden_files | LC_ALL=C sort -u)
  [ "${#_files[@]}" -gt 0 ] || return 0

  # バッチ化(#65): git hash-object --stdin-paths なら全ファイルを 1 プロセスで畳める。
  # 委託の前後 2 回走り、.harness/codex-runs/ の件数に線形だったプロセス起動が消える。
  #
  # **フォールバックを必ず残す。** --stdin-paths は 1 ファイルでも失敗すると
  # そこで die して残りを処理しない = 現行の「1 ファイルずつ握りつぶして UNREADABLE」
  # と挙動が変わる。挙動が変わると「改ざんが差分ゼロで通る」側に倒れうるので、
  # **出力行数が入力行数と一致したときだけバッチ結果を採用**し、それ以外は
  # 従来どおり 1 ファイルずつ回す。速い経路は最適化、正しさは従来経路が持つ。
  #
  # 先頭が " のパスをバッチに乗せないのは、git hash-object --stdin-paths が
  # `"` で始まる行を C クォート文字列として unquote するため(別のパスをハッシュしうる)。
  # 該当があればバッチ自体を諦めて 1 ファイルずつに落とす。
  _batch_ok=1
  for _f in "${_files[@]}"; do
    case "$_f" in '"'*) _batch_ok=0; break ;; esac
  done

  if [ "$_batch_ok" = 1 ]; then
    while IFS= read -r _h; do
      _hashes+=("$_h")
    done < <(printf '%s\n' "${_files[@]}" | git hash-object --stdin-paths 2>/dev/null)
    if [ "${#_hashes[@]}" -eq "${#_files[@]}" ]; then
      for _i in "${!_files[@]}"; do
        printf '%s %s\n' "${_hashes[$_i]}" "${_files[$_i]}"
      done
      return 0
    fi
  fi

  # フォールバック: 1 ファイルずつ。失敗は握りつぶして UNREADABLE(前後で同じ扱いになる)。
  for _f in "${_files[@]}"; do
    _h="$(git hash-object -- "$_f" 2>/dev/null)"
    printf '%s %s\n' "${_h:-UNREADABLE}" "$_f"
  done
}
```

### 制約

- **関数本体の中に、行頭カラム 0 の `}` を書かないこと。** 検証ドライバが
  `sed -n '/^forbidden_snapshot() {/,/^}/p'` で本体を抜き出す
- `paste` / `awk` / `wc` を使わない(入口検査0 の保証対象外。requirements 非機能)
- 関数の直前にあるコメントブロック(ハッシュ方式を選んだ理由と空振り条件)は**残す**。
  そのうち「`.harness/codex-runs/` が溜まるほど前後 2 回のハッシュ計算コストが線形に増える」
  の項だけは実態と合わなくなるので、次の内容に差し替える:

  ```
  #   - .harness/codex-runs/ が溜まるほど対象ファイル数は増えるが、ハッシュ計算は
  #     git hash-object --stdin-paths の 1 プロセスに畳んである(#65)。元を断つ側
  #     (手動の `codex-run.sh prune`)は従来どおり。自動削除はしない(Issue #29 / §12.8)
  ```

---

## 2. `--print-forbidden` の自己コピー短絡

### 現状(置換対象)

冒頭「自己編集ハザード対策」ブロックの分岐:

```bash
if [ "${CODEX_DELEGATE_NO_SELF_COPY:-}" = "1" ]; then
```

### 置換後(この 1 行の前に分岐を 1 つ足す)

```bash
if [ "${1:-}" = "--print-forbidden" ]; then
  # 短絡(#65): --print-forbidden は配列を出力して exit 0 するだけの read-only 経路で、
  # codex exec を起動しない = 実行中に自身が書き換わる窓が無い。自己コピー + mktemp -d の
  # 固定費を掛ける理由がないので飛ばす。CODEX_DELEGATE_NO_SELF_COPY の警告より前に
  # 置いているのは、ここが「他スクリプトが読む一覧出力口」であり、無関係な警告で
  # stderr を汚さないため(保護を切っているわけではないので、記録すべき事実も無い)。
  # **短絡するのはコピーだけ。** 以降の引数検査・配列定義・抽出は共通経路をそのまま通る。
  :
elif [ "${CODEX_DELEGATE_NO_SELF_COPY:-}" = "1" ]; then
```

以降(`elif [ -z "${CODEX_DELEGATE_SELF_COPY:-}" ]; then` 以下)は**一切変更しない**。

### 波及がないことの根拠(実装時に確認する)

- `SELF_COPY_DIR` は `CODEX_DELEGATE_SELF_COPY` が空なので設定されず、EXIT トラップも張られない。
  `--print-forbidden` は `exit 0` で終わるだけなので後始末は不要
- `lib-record.sh` の解決は `$ROOT/.claude/scripts/lib-record.sh` に落ちる。
  「一時コピーを使えていません」警告は `[ -n "${SELF_COPY_DIR:-}" ]` で守られているので出ない
- `require_jq` は `--print-forbidden` の後段にあるため到達しない(#63 の設計どおり)

### ヘルプの追記

`usage()` の環境変数節は変更しない。`--print-forbidden` の説明行に手を入れる必要も無い。

---

## 3. 検証(実測)

使い捨てのドライバをスクラッチパッドに置いて回し、**結果を
`.steering/20260904-issue65-exit-check-cost/verification.md` に記録する**
(ドライバ自体はコミットしない。このリポジトリにシェル用テストスイートは無く、
1 チケットのために新設するのはスコープ外)。

### 3-1. ドライバ

`$SCRATCH/snap.sh`(`$SCRATCH` は任意の作業ディレクトリ):

```bash
#!/bin/bash
# 使い方: bash snap.sh <delegate-codex.sh のパス>
# 環境変数 TEST_FORBIDDEN があれば FORBIDDEN_PATHS をそれで置き換える(空白区切りの配列リテラル)
set -uo pipefail
SRC="$1"
DEFS="$(mktemp)"
{
  sed -n '/^FORBIDDEN_PATHS=(/,/^)/p' "$SRC"
  sed -n '/^forbidden_files() {/,/^}/p' "$SRC"
  sed -n '/^forbidden_snapshot() {/,/^}/p' "$SRC"
} > "$DEFS"
. "$DEFS"
rm -f "$DEFS"
PROJECT_FORBIDDEN_PATHS=()
REC="__none_rec__"; LOG="__none_log__"; LAST="__none_last__"
[ -n "${TEST_FORBIDDEN:-}" ] && eval "FORBIDDEN_PATHS=($TEST_FORBIDDEN)"
forbidden_snapshot
```

旧版は `git show HEAD:.claude/scripts/delegate-codex.sh > $SCRATCH/old.sh` で取る
(実装コミットより前の HEAD であること)。

### 3-2. ケース A: 実リポジトリの禁止領域そのまま(受け入れ条件 1)

リポジトリルートで:

```bash
bash "$SCRATCH/snap.sh" "$SCRATCH/old.sh"                      > "$SCRATCH/a-old.txt"
bash "$SCRATCH/snap.sh" .claude/scripts/delegate-codex.sh      > "$SCRATCH/a-new.txt"
diff "$SCRATCH/a-old.txt" "$SCRATCH/a-new.txt" && echo "A: 一致"
```

**期待: 差分なし。** 行数(= 対象ファイル数)も記録する。

### 3-3. ケース B: 不在パス・ディレクトリ・空ファイル混在(受け入れ条件 2)

フィクスチャを作る:

```bash
FIX="$SCRATCH/fix"
rm -rf "$FIX" && mkdir -p "$FIX/sub" "$FIX/dir_as_file"
printf 'alpha\n' > "$FIX/a.txt"
: > "$FIX/empty.txt"
printf 'one\n'  > "$FIX/sub/1.txt"
printf 'two\n'  > "$FIX/sub/2.txt"
export TEST_FORBIDDEN="'$FIX/a.txt' '$FIX/empty.txt' '$FIX/sub/' '$FIX/dir_as_file' '$FIX/missing.txt'"
```

- `dir_as_file` は末尾 `/` なしのディレクトリ → `[ -e ]` を通り `git hash-object` が失敗 →
  **`UNREADABLE` になり、バッチ経路がフォールバックに落ちることの確認も兼ねる**
- `missing.txt` は不在 → `forbidden_files` の実在検査で落ちて列挙されない

```bash
bash "$SCRATCH/snap.sh" "$SCRATCH/old.sh"                 > "$SCRATCH/b-old.txt"
bash "$SCRATCH/snap.sh" .claude/scripts/delegate-codex.sh > "$SCRATCH/b-new.txt"
diff "$SCRATCH/b-old.txt" "$SCRATCH/b-new.txt" && echo "B: 一致"
```

**期待: 差分なし。** 出力に `UNREADABLE $FIX/dir_as_file` が 1 行あること、
`missing.txt` の行が無いことを目視で確認して記録する。

### 3-4. ケース C: 改ざん検出(受け入れ条件 3)

ケース B の `TEST_FORBIDDEN` のまま:

```bash
bash "$SCRATCH/snap.sh" .claude/scripts/delegate-codex.sh > "$SCRATCH/c-before.txt"
printf 'x' >> "$FIX/sub/1.txt"
bash "$SCRATCH/snap.sh" .claude/scripts/delegate-codex.sh > "$SCRATCH/c-after.txt"
diff "$SCRATCH/c-before.txt" "$SCRATCH/c-after.txt"
```

**期待: `sub/1.txt` の行だけが差分として出る**(他の行は不変)。
出口検査本体と同じ突き合わせ(`sort | uniq -u`)でも 1 パスだけが残ることを確認する。

なお、バッチ経路そのものの改ざん検出も確認する。`dir_as_file` を消して
全ファイルが読める構成(= `--stdin-paths` が完走する構成)にしてから同じ手順を回し、
差分が出ることを見る。**フォールバックとバッチの両方で検出できていること**が要件。

### 3-5. ケース D: `--print-forbidden` の短絡(受け入れ条件 4・5)

出力の同一性:

```bash
bash "$SCRATCH/old.sh" --print-forbidden               > "$SCRATCH/d-old.txt" 2>/dev/null
bash .claude/scripts/delegate-codex.sh --print-forbidden > "$SCRATCH/d-new.txt" 2>/dev/null
diff "$SCRATCH/d-old.txt" "$SCRATCH/d-new.txt" && echo "D: 一致"
```

短絡していることの観測(`mktemp -d` を失敗させて分岐を可視化する):

```bash
# 旧版: 自己コピーに失敗して警告が出る
TMPDIR=/nonexistent-dir bash "$SCRATCH/old.sh" --print-forbidden 2>&1 >/dev/null | head -2
# 新版: 短絡するので警告が出ない(出力は空)
TMPDIR=/nonexistent-dir bash .claude/scripts/delegate-codex.sh --print-forbidden 2>&1 >/dev/null | head -2
```

波及がないこと(`--print-forbidden` 以外は従来どおり自己コピーを試みる):

```bash
# 新版でも explore は自己コピー失敗の警告を出す(短絡していない証拠)
TMPDIR=/nonexistent-dir bash .claude/scripts/delegate-codex.sh explore "dummy" 2>&1 >/dev/null | head -2
```

consumer からの疎通:

```bash
bash .claude/scripts/check-guard-integrity.sh degraded; echo "exit=$?"
```

**期待: `$DELEGATE --print-forbidden が委託禁止領域を返さない` が出ないこと。**

### 3-6. `verification.md` に書くこと

ケース A〜D それぞれについて、**実行したコマンドと実際の出力(diff の結果・行数・
警告の有無・exit code)**を貼る。「一致した」だけの記述にしない。

---

## 4. CHANGELOG

`docs/template-dev/CHANGELOG.md` の先頭に `## 2026-09-04` の見出しを作り(既存の
`## 2026-09-03` の**上**)、次の 1 項目を置く。区分は **`[auto]`**(取り込む側の作業ゼロ)。

- **[auto]** 委託の出口検査の固定費を下げました(Issue #65)。禁止領域のスナップショットを
  `git hash-object --stdin-paths` の 1 プロセスに畳み(従来はファイルごとにプロセス起動。
  `.harness/codex-runs/` の件数に線形)、`--print-forbidden`(`check-guard-integrity.sh degraded`
  が読む read-only の一覧出力)は自己コピー + `mktemp -d` を短絡するようにしました。
  **判定内容は変わりません** — バッチが 1 ファイルでも失敗した場合は従来どおり
  1 ファイルずつ計算する経路に落ちるため、不在ファイルや読めないファイルの扱い
  (`UNREADABLE` として前後同じ扱いに倒す)は同一です

見出しの日付は `## 2026-09-04`。過去の見出しには追記しない。

---

## 5. やらないこと(明示)

- `delegate-codex.sh` の分割
- 検証ドライバのコミット、テストスイートの新設
- `forbidden_files()` の変更(列挙ロジックは触らない)
- prune 閾値・`.harness/codex-runs/` の運用変更
