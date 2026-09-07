# 設計: delegate-codex.sh を lib-*.sh に分割する

<!-- status: ready -->

Issue: #86 / requirements: `requirements.md`

**この作業はリファクタで、振る舞いを変えない。** 移動するコードは**コメントも含めて逐語で運ぶ**。
唯一の例外は「移動先を指すようになったポインタ的コメント」で、その差分は §6 に列挙してある。
それ以外の 1 文字の書き換えも行わないこと。

---

## §0 完成形(3 ファイル)

| ファイル | 中身 | フェイル方針 |
| --- | --- | --- |
| `.claude/scripts/delegate-codex.sh` | 入口検査の骨格・run record・プロンプト構築・実行・出口判定・出口検査 | 従来どおり |
| `.claude/scripts/lib-forbidden.sh`(新規) | `FORBIDDEN_PATHS` / `PROJECT_FORBIDDEN_PATHS` 抽出 / `forbidden_files()` / `forbidden_snapshot()` / `lifecycle_snapshot()` | **フェイルクローズ** |
| `.claude/scripts/lib-probe.sh`(新規) | `PROBE_ALLOWED_CMDS` / `PROBE_VERIFY_TOKENS` / `_probe_name_ok()` / `probe_format_reason()` / `PROBE_ENV` | **フェイルクローズ** |

`record_state_snapshot()` は **移さない**(禁止領域ではなく run record の検収状態を見る層で、責務が違う)。
`tree_snapshot()` / `count_done()` も移さない。

### フェイルクローズにした理由(Issue が「個別に判断して design.md に書く」と指定した箇所)

- **`lib-forbidden.sh`**: 無いまま進むと `FORBIDDEN_PATHS` が未定義になり、出口検査は列挙 0 件 =
  「差分ゼロ」= 正常終了として素通しする。`--print-forbidden` は空を返し、
  `check-guard-integrity.sh degraded` と `check-forbidden-paths-doc.sh` の照合まで同時に空振りする。
  **検査が消えたことが失敗として現れない**形なので止める(`lib-record.sh` と同じ判断)。
- **`lib-probe.sh`**: 無いまま進むと `probe_format_reason` が未定義のまま呼ばれ、その 127 が
  `elif ! _probe_reason="$(probe_format_reason "$PROBE")"` の「形式不適合」分岐に落ちる。
  委託は**誤った理由**(「許可形式に適合しない」)の警告を出して続行し、形式検査という層が
  消えたことは失敗として現れない。同じ形なので同じ判断にする。
- 2 ファイルともテンプレートが `delegate-codex.sh` と一緒に配布する。片方だけ欠けるのは
  壊れた導入であって、正当な設定ではない。

---

## §1 自己コピー exec のグロブ化

`delegate-codex.sh` の自己コピーブロック(`_self_dir=` の行)を置き換える。

**置換前**(逐語):

```bash
    # source する共有ファイル(lib-record.sh)も一緒に運ぶ。運ばないと、コピーを exec
    # しているのに実行中に読むファイルがリポジトリ側に残り、自己編集ハザード対策に
    # 穴が開く(委託先が実行中に書き換えられる)。
    # **ここはフェイルオープン**: 失敗しても委託は止めない。下の解決順が $ROOT へ
    # フォールバックし、警告を出す(design §1)。
    _self_dir="$(cd "$(dirname "$_self")" 2>/dev/null && pwd || true)"
    [ -n "$_self_dir" ] && cp "$_self_dir/lib-record.sh" "$_copy_dir/lib-record.sh" 2>/dev/null
```

**置換後**(逐語):

```bash
    # source する共有ファイル(lib-*.sh)も一緒に運ぶ。運ばないと、コピーを exec
    # しているのに実行中に読むファイルがリポジトリ側に残り、自己編集ハザード対策に
    # 穴が開く(委託先が実行中に書き換えられる)。
    # **ファイル名を列挙せずグロブで運ぶ**(#86)。列挙にすると source するライブラリが
    # 1 本増えるたびに同じ漏れを繰り返す。しかも漏れても出るのは警告だけで委託は成功する
    # ため、気づく機会が無い。lib-*.sh は「source 専用」を CI(harness-integrity)と
    # SessionStart hook が機械検査する規約なので(#45)、この名前で運ぶ対象を決めてよい。
    # マッチが 0 件のときはグロブ文字列そのものが残るが、[ -f ] で落ちる(nullglob 不要)。
    # **ここはフェイルオープン**: 失敗しても委託は止めない。下の解決順が $ROOT へ
    # フォールバックし、警告を出す(design §1)。
    _self_dir="$(cd "$(dirname "$_self")" 2>/dev/null && pwd || true)"
    if [ -n "$_self_dir" ]; then
      for _lib in "$_self_dir"/lib-*.sh; do
        [ -f "$_lib" ] && cp "$_lib" "$_copy_dir/" 2>/dev/null
      done
    fi
```

`_lib` の後始末は不要(直後の `exec` でプロセスイメージごと入れ替わる)。

冒頭コメント(37-51 行付近)の

```
# 共有ファイル(lib-record.sh)も同じディレクトリへ一緒にコピーし、コピー側から source する。
```

は

```
# 共有ファイル(lib-*.sh)も同じディレクトリへ一緒にコピーし、コピー側から source する。
```

に直す。**これ以外の冒頭コメントは触らない。**

---

## §2 ライブラリ解決の共通化

現行の `lib-record.sh` 解決ブロック(`_lib_dir="$(cd ...` から `unset _lib_dir _cand` まで)を
次で置き換える。**その上のコメントブロック(「---------- run record 読み出しの共有関数 ----------」
から始まる解説)は逐語で残し**、見出しだけ `# ---------- 共有ライブラリの解決と読み込み ----------`
に変え、末尾に次の 3 行を足す:

```
#
# 解決順・警告・フェイルクローズの形は 3 ファイル(lib-record / lib-forbidden / lib-probe)で
# 共通なので、resolve_lib() と warn_if_not_self_copy() に畳んである(#86)。
```

**置換後のコード**(逐語):

```bash
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

# 解決したパスを標準出力に返す。見つからなければ 1(呼び出し側がフェイルクローズする)。
resolve_lib() {
  local _name="$1" _cand
  for _cand in "${LIB_DIR:+$LIB_DIR/$_name}" "$ROOT/.claude/scripts/$_name"; do
    [ -n "$_cand" ] && [ -f "$_cand" ] && {
      printf '%s' "$_cand"
      return 0
    }
  done
  return 1
}

# 一時コピーではなくリポジトリ側から source してしまったときに警告する。
# $1 = 解決したパス / $2 = ファイル名。
warn_if_not_self_copy() {
  if [ -n "${SELF_COPY_DIR:-}" ] && [ "$1" != "$SELF_COPY_DIR/$2" ]; then
    echo "delegate-codex: 警告 — $2 の一時コピーを使えていません。委託中にこのファイルが書き換わると異常終了します。" >&2
  fi
  return 0
}

LIB_RECORD="$(resolve_lib lib-record.sh)" || {
  echo "delegate-codex: .claude/scripts/lib-record.sh が見つかりません(run record を読めないため中止します)。" >&2
  exit "$EX_FAIL"
}
# shellcheck source=lib-record.sh
. "$LIB_RECORD"
warn_if_not_self_copy "$LIB_RECORD" lib-record.sh
```

- 警告文は**現行と 1 文字も変わらない**(`$2` の展開結果が `lib-record.sh`)。
- 見つからないときのメッセージも現行の逐語。
- `LIB_DIR` は `unset` しない(以降 `resolve_lib` が使う)。

---

## §3 `lib-forbidden.sh` の切り出し

### 3-1 移す範囲(delegate-codex.sh から**削除**する)

| ブロック | 開始行(アンカー) | 終了行(アンカー) |
| --- | --- | --- |
| A | `# ---------- 委託禁止領域の定義(単一ソース) ----------` | `FORBIDDEN_PATHS=( ... )` の閉じ `)` |
| B | `# ---------- 出口検査の対象(プロジェクト固有パス)の抽出 ----------` | `unset _fp_start _fp_end` |
| C | `# 禁止領域の実ファイルを列挙する(内容ハッシュ比較 forbidden_snapshot() が使う)。` | `forbidden_snapshot()` の閉じ `}` |
| D | `# ---- package.json のライフサイクル系差分(警告のみ)のヘルパー ----` | `lifecycle_snapshot()` の閉じ `}` |

**A と B の間にある `AGENTS="AGENTS.md"` は移さない。** delegate-codex.sh 側に残し、§3-2 の
source 位置より**前**に置く(B の抽出が `$AGENTS` を読むため)。

### 3-2 delegate-codex.sh に残す source ブロック

A・B があった位置(入口検査0 の `done` の次)に、次を逐語で置く:

```bash
AGENTS="AGENTS.md"

# ---------- 委託禁止領域の定義(単一ソース): lib-forbidden.sh ----------
#
# 配列(FORBIDDEN_PATHS)・AGENTS.md §4 マーカーからの抽出(PROJECT_FORBIDDEN_PATHS)・
# 出口検査のヘルパー(forbidden_files / forbidden_snapshot / lifecycle_snapshot)は
# lib-forbidden.sh に分けてある(#86)。**source 位置を動かさないこと**。前後関係が
# そのまま防御の一部になっている:
#   - 入口検査0(find / grep / sed の存在確認)より後 … 抽出が grep と sed を使う
#   - $AGENTS の代入より後                           … 抽出元のパス
#   - --print-forbidden の分岐より前                 … あの経路は codex CLI 不在でも応答する
#   - 入口検査5-5b より前                            … pathspec 生成が FORBIDDEN_PATHS を読む
#
# **フェイルクローズ**(lib-record.sh と同じ判断)。無いまま進むと FORBIDDEN_PATHS が
# 未定義になり、出口検査は列挙 0 件 =「差分ゼロ」= 正常終了として素通しする。同時に
# --print-forbidden が空を返し、check-guard-integrity.sh degraded と
# check-forbidden-paths-doc.sh の照合まで空振りする。検査が消えたことが失敗として
# 現れない形なので、止める側に倒す。
LIB_FORBIDDEN="$(resolve_lib lib-forbidden.sh)" || {
  echo "delegate-codex: .claude/scripts/lib-forbidden.sh が見つかりません(委託禁止領域を判定できないため中止します)。" >&2
  exit "$EX_FAIL"
}
# shellcheck source=lib-forbidden.sh
. "$LIB_FORBIDDEN"
warn_if_not_self_copy "$LIB_FORBIDDEN" lib-forbidden.sh
```

C・D を削除した跡には何も置かない(§6 の見出しコメント書き換えのみ)。

### 3-3 `lib-forbidden.sh` の構成

先頭に次のヘッダを置き、その下に **A → B → C → D の順**で移したブロックを逐語で並べる。

```bash
# shellcheck shell=bash
# 委託禁止領域の単一ソース(汎用項目)と、出口検査が使う判定ヘルパー。
#
# **source 専用。** 実行ビットは付けない(shebang も付けない)。
# 命名規約: .claude/scripts/lib-*.sh は source 専用。CI(ci.yml の harness-integrity)と
# SessionStart hook が、この名前のファイルに **実行ビットが無いこと・shebang が無いこと**
# を機械検査する(#45 §10)。単体で起動する実体を lib- で始まる名前にしないこと。
# 利用側: .claude/scripts/delegate-codex.sh
#
# **source した瞬間に走るコードを含む**(PROJECT_FORBIDDEN_PATHS の抽出)。呼び出し側は
#   1) 入口検査0(find / grep / sed の存在確認)を通し、2) $AGENTS を代入してから
# source すること。source 位置の前後関係が防御の一部になっている理由は
# delegate-codex.sh 側の該当ブロックのコメントに書いてある(#86)。
#
# forbidden_files() は $RUN_DIR / $REC / $LOG / $LAST を**呼び出し時**に読む。定義は
# ここでよいが、呼ぶのは run record を組み立てた後(delegate-codex.sh の「事前
# スナップショット」以降)であること。
#
# フェイル方針: **呼び出し側でフェイルクローズ**(理由は delegate-codex.sh の source 位置)。
#
# 委託禁止領域に入るか: 入る。FORBIDDEN_PATHS の ".claude/scripts/" がディレクトリ単位
# なので(#40)、このファイルは追加作業なしで出口検査・縮退検査の対象になる。
#
# 実行中の書き換えハザード: delegate-codex.sh は起動直後に自身と lib-*.sh を一時
# ディレクトリへコピーして exec する(#15 / #86)。委託中に元ファイルが書き換わっても、
# 走っているプロセスが読む定義は変わらない。
```

---

## §4 `lib-probe.sh` の切り出し

### 4-1 移す範囲(delegate-codex.sh から**削除**する)

| 開始行(アンカー) | 終了行(アンカー) |
| --- | --- |
| `# ---- 入口検査3 の許可リスト(プローブ形式) ----` | `unset _pe`(`PROBE_ENV` 組み立てループの直後) |

その直前の 3 行

```
# 検査の機構はこのスクリプト、検査の中身は AGENTS.md 側に置く。
# delegate-codex.sh はテンプレート所有で全プロジェクトに配られるため、
# node_modules のようなスタック固有のものを決め打ちで見てはいけない。
```

は **delegate-codex.sh 側に残す**(プローブ機構そのものの説明で、移す範囲ではない)。
その次の行から `PROBE="$(sed -n ...` の前までを丸ごと移す。

### 4-2 delegate-codex.sh に残す source ブロック

削除した位置に逐語で置く:

```bash
# ---- 入口検査3 の許可リスト(プローブ形式): lib-probe.sh ----
#
# 許可コマンド(PROBE_ALLOWED_CMDS)・導通確認トークン(PROBE_VERIFY_TOKENS)・
# 形式検査(probe_format_reason / _probe_name_ok)・プローブ実行環境(PROBE_ENV)は
# lib-probe.sh に分けてある(#86)。**source 位置を動かさないこと**:
#   - 入口検査2(AGENTS.md の存在確認)より後 … 無い状態で形式検査を持っても意味がない
#   - PROBE の抽出・実行より前               … 抽出した文字列は検査を通す前に使わない
#   - PROBE_ENV の組み立ては親プロセスの PATH / HOME / TMPDIR を読む(source 時に確定する)
#
# **フェイルクローズ**(lib-record.sh / lib-forbidden.sh と同じ判断)。無いまま進むと
# probe_format_reason が未定義のまま呼ばれ、その 127 が下の「形式不適合」分岐に落ちる。
# 委託は**誤った理由**の警告を出したまま続行し、形式検査という層が消えたことは
# 失敗として現れない。
LIB_PROBE="$(resolve_lib lib-probe.sh)" || {
  echo "delegate-codex: .claude/scripts/lib-probe.sh が見つかりません(検証プローブの形式検査ができないため中止します)。" >&2
  exit "$EX_FAIL"
}
# shellcheck source=lib-probe.sh
. "$LIB_PROBE"
warn_if_not_self_copy "$LIB_PROBE" lib-probe.sh
```

### 4-3 `lib-probe.sh` の構成

先頭に次のヘッダを置き、その下に 4-1 の範囲を逐語で並べる。

```bash
# shellcheck shell=bash
# 検証プローブ(AGENTS.md の <!-- verify-probe: ... -->)の許可リストと形式検査。
#
# **source 専用。** 実行ビットは付けない(shebang も付けない)。
# 命名規約: .claude/scripts/lib-*.sh は source 専用。CI(ci.yml の harness-integrity)と
# SessionStart hook が、この名前のファイルに **実行ビットが無いこと・shebang が無いこと**
# を機械検査する(#45 §10)。単体で起動する実体を lib- で始まる名前にしないこと。
# 利用側: .claude/scripts/delegate-codex.sh
#
# ここで抽出・判定する文字列は **ホスト上の bash -c にそのまま渡りうる**(P1〜P3 の形式)。
# 許可リストを緩めるときは、必ず実測してから足すこと(手順は下の PROBE_ALLOWED_CMDS の
# コメント)。
#
# **source した瞬間に走るコードを含む**(PROBE_ENV の組み立て。親プロセスの
# PATH / HOME / TMPDIR を読む)。
#
# フェイル方針: **呼び出し側でフェイルクローズ**(理由は delegate-codex.sh の source 位置)。
#
# 委託禁止領域に入るか: 入る(".claude/scripts/" がディレクトリ単位。#40)。
#
# 実行中の書き換えハザード: delegate-codex.sh は起動直後に自身と lib-*.sh を一時
# ディレクトリへコピーして exec する(#15 / #86)。
```

---

## §5 ファイルモード

新規 2 ファイルは **実行ビット無し(100644)・shebang 無し**。

```bash
chmod 644 .claude/scripts/lib-forbidden.sh .claude/scripts/lib-probe.sh
git add .claude/scripts/lib-forbidden.sh .claude/scripts/lib-probe.sh
git ls-files -s .claude/scripts/lib-*.sh   # すべて 100644 であること
```

`core.fileMode=false` の環境では `chmod` が index に反映されないため、
`100755` で入ってしまった場合は `git update-index --chmod=-x <path>` で直す。

---

## §6 コメントだけを書き換える箇所(逐語移動の例外)

この 4 箇所以外で移動元の文面を変えない。

1. 冒頭ブロック `# 共有ファイル(lib-record.sh)も同じディレクトリへ…` → `lib-*.sh`(§1)
2. `# ---------- run record 読み出しの共有関数 ----------` → `# ---------- 共有ライブラリの解決と読み込み ----------` + 末尾 3 行追記(§2)
3. `# ---------- 出口検査(委託禁止領域)のヘルパー ----------` の直下 2 行

   ```
   # 判定対象の配列(FORBIDDEN_PATHS / PROJECT_FORBIDDEN_PATHS)はスクリプト冒頭で定義済み。
   # ここにはそれを使う関数だけを置く。
   ```

   を次に差し替える:

   ```
   # 禁止領域そのもののヘルパー(forbidden_files / forbidden_snapshot)と
   # lifecycle_snapshot() は lib-forbidden.sh へ移した(#86)。ここに残すのは
   # record_state_snapshot() —— 禁止領域ではなく run record の**検収状態**を見る層で、
   # 内容ハッシュ比較とは目的が違う(#81)。
   ```
4. `lib-record.sh` のヘッダ内

   ```
   # コピーして exec する(#15)。このファイルも同じ一時ディレクトリへ一緒にコピーされ、
   ```

   を

   ```
   # コピーして exec する(#15)。lib-*.sh は同じ一時ディレクトリへ一緒にコピーされ(#86)、
   ```

   に直す(グロブ化で「このファイルだけ」ではなくなったため)。**他は触らない。**

---

## §7 検証手順(すべて実測。Codex の枠は 1 度も使わない)

### 7-1 前後比較の基準を git から取る

`HEAD` は変更前の版なので、基準はいつでも取り直せる。

```bash
W=/tmp/claude-1000/-workspaces-claude-codex-template/212c0ca5-cea3-4587-bc59-d92eac780176/scratchpad/issue86
mkdir -p "$W"
git show HEAD:.claude/scripts/delegate-codex.sh > "$W/orig.sh"
```

`orig.sh` は自分の隣に `lib-record.sh` を持たないが、解決順の第 2 候補
(`$ROOT/.claude/scripts/`)に落ちて動く(その分の警告が stderr に出るのは想定どおり)。

### 7-2 `--print-forbidden`(#65 の短絡経路)

```bash
D=.claude/scripts/delegate-codex.sh
for a in "" "generic"; do
  diff <(bash "$W/orig.sh" --print-forbidden $a 2>/dev/null; echo "exit=$?") \
       <(bash "$D"        --print-forbidden $a 2>/dev/null; echo "exit=$?") \
    && echo "OK: --print-forbidden $a"
done
```

**両方とも差分ゼロであること。**

### 7-3 終了コードと出力の前後一致(codex exec に到達しないケースのみ)

exit 5 用のフィクスチャを作る(検査に落ちる `design.md` を置くだけ。委託は起動しない):

```bash
F=.steering/00000000-issue86-fixture
mkdir -p "$F"
printf '# design\n\n<!-- status: draft -->\n' > "$F/design.md"
: > "$F/tasklist.md"
```

比較する:

```bash
run() { bash "$1" "${@:2}" >"$W/out" 2>"$W/err"; echo "exit=$?"; cat "$W/out" "$W/err"; }
for args in "" "bogus x" "impl .steering/does-not-exist" "impl /tmp" "impl $F"; do
  diff <(run "$W/orig.sh" $args) <(run "$D" $args) && echo "OK: [$args]"
done
rm -rf "$F"
```

- **全ケースで差分ゼロ**であること(`orig.sh` 側にだけ出る `lib-record.sh の一時コピーを
  使えていません` の警告は、`$W/orig.sh` を `.claude/scripts/` にコピーして走らせれば消える。
  差分がその 1 行だけなら合格とみなしてよい —— 判定は「その行以外に差が無いこと」)。
- `impl $F` は **exit 5** を返し、`codex exec` に到達しないこと。

### 7-4 到達できない終了コード(0 / 1 / 4 / 130 / 143)の担保

これらは `codex exec` を起動しないと再現できない。**代わりに「触っていないこと」を差分で示す**:

```bash
git diff -- .claude/scripts/delegate-codex.sh
```

変更が §1 / §2 / §3-2 / §4-2 / §6 の 5 種類だけであること、
**プロンプト構築・`codex exec` の起動・出口判定・出口検査の本体に 1 行の変更も無いこと**を
目視で確認し、確認結果を `tasklist.md` の振り返りに 1 行で書く。

### 7-5 自己コピーの搬送

```bash
# 3 ファイルとも一時コピーから source できている = 「一時コピーを使えていません」が出ない
bash "$D" impl "$F" 2>&1 | grep -c '一時コピーを使えていません'   # → 0
# 明示的な無効化の経路
CODEX_DELEGATE_NO_SELF_COPY=1 bash "$D" impl "$F" 2>&1 | grep -c 'CODEX_DELEGATE_NO_SELF_COPY=1'  # → 1
# mktemp -d を失敗させたときのフェイルオープン(警告を出して続行する)
TMPDIR=/nonexistent-dir bash "$D" 2>&1 | grep -c '自身の一時コピーを作れませんでした'  # → 1
```

(`$F` は 7-3 のフィクスチャ。3 つとも実行後に `rm -rf "$F"` すること。)

### 7-6 消費側の 2 スクリプト

```bash
bash .claude/scripts/check-forbidden-paths-doc.sh && echo "OK: doc 照合"
bash .claude/scripts/check-guard-integrity.sh degraded; echo "exit=$?"
```

`degraded` は変更前と同じ出力・同じ終了コードであること(`$W/orig.sh` を使う経路ではないので、
変更前の結果は `git stash` せずとも 7-2 の `--print-forbidden` 一致で担保される。ここでは
**エラーで落ちないこと**だけを見る)。

### 7-7 構文・規約・lint

```bash
bash -n .claude/scripts/delegate-codex.sh
bash -n .claude/scripts/lib-forbidden.sh
bash -n .claude/scripts/lib-probe.sh
shellcheck .claude/scripts/delegate-codex.sh .claude/scripts/lib-forbidden.sh .claude/scripts/lib-probe.sh
git ls-files -s .claude/scripts/lib-*.sh      # すべて 100644
head -n 1 .claude/scripts/lib-forbidden.sh .claude/scripts/lib-probe.sh   # shebang が無いこと
npm run lint && npm run format:check
```

shellcheck は CI に無い(CI は `bash -n` のみ)が、ローカルにあるので通しておく。
**既存 warning が増えていないこと**を基準にする(変更前の `shellcheck delegate-codex.sh` の
出力と比べる)。

---

## §8 CHANGELOG

`docs/template-dev/CHANGELOG.md` の `---` の直後に `## 2026-09-07` の見出しを新設し、
`[auto]` 項目を 1 つ足す。**日付を遡って過去の見出しに追記しない。**

内容の骨子(実測値は §7 の後に埋める):

- `delegate-codex.sh` から `lib-forbidden.sh`(禁止領域の配列・抽出・出口検査ヘルパー)と
  `lib-probe.sh`(プローブの許可リストと形式検査)を切り出した
- 自己コピー exec の共有ファイル搬送を `lib-*.sh` のグロブに一般化した(#86)
- **振る舞いは変えていない**(終了コード・`--print-forbidden` の出力・検査の順序すべて同じ)
- 取り込む側の作業はゼロ(`/sync-template` の上書きで完結。新規 2 ファイルは
  `.claude/scripts/` 配下なので同期対象に含まれる)
- 行数の実測値(`wc -l` の前後)

## §9 記録

`.harness/decisions.jsonl` への 1 行追記は**司令塔が PR 作成前に行う**(実装者は触らない)。
