<!-- status: ready -->

# 設計: 出口検査に `AGENTS.md` のプロジェクト固有パスを含める(Issue #28)

対象ファイル: `.claude/scripts/delegate-codex.sh` / `AGENTS.md` / `CLAUDE.md` / `.claude/commands/kickoff.md`

**この作業は委託禁止領域に触れるため Codex には渡さない**(`implement-ticket` の fork が実装する)。

---

## 0. 設計判断(実装者は判断しない。ここに書いてあるとおりに実装する)

### 0.1 単一ソースを 2 つに分ける

#20 は「3 箇所目のリストファイルを作らない」と決めた。この判断は覆さない。代わりに**単一ソースを 2 系統に分ける**:

| 種別 | 正となる場所 | 理由 |
| --- | --- | --- |
| 汎用項目(全プロジェクト共通) | `delegate-codex.sh` の `FORBIDDEN_PATHS` 配列 | テンプレート所有。委託先から書き換えられない(起動直後の自己コピー) |
| プロジェクト固有パス | `AGENTS.md` §4 のマーカー内 | `/kickoff` フェーズ4 がここに書く設計が既にある。新しいファイルを増やさない |

`AGENTS.md` 自体が汎用項目(= 常に検査対象)なので、**マーカー内の書き換えは必ず違反として検出される**。したがって「委託先が自分の禁止リストを緩める」経路は塞がっている。

### 0.2 抽出は委託の開始前に 1 回だけ

抽出は**入口検査2・3(`AGENTS.md` の存在確認と verify-probe)の直後**に行い、結果をグローバル配列に持つ。プロンプト構築(`# ---------- プロンプト構築`)より前である。

- 委託先が実行中に `AGENTS.md` を書き換えても、その回の検査対象は**開始時点のリスト**のまま
- 書き換えそのものは `AGENTS.md` の内容ハッシュ差分として別途検出される

### 0.3 両方のマーカーが揃っているときだけ抽出する(フェイルオープン)

開始マーカーだけがあって終了マーカーが無いと、`sed` の範囲指定はファイル末尾までを拾い、`AGENTS.md` 中の無関係なバックティック語(`design.md`・`.steering/` 等)まで禁止領域に化けて**全委託が常に失敗する**。これは過剰阻止であり回復も難しい。

したがって:

- 両方あり → 抽出する
- 両方なし → 何もしない(マーカー未反映のプロジェクト。従来どおり汎用項目だけで動く)
- 片方だけ → **警告を出して抽出しない**(入口検査3 が verify-probe 欠落で警告のみ出すのと同じ非対称)

片方消しで検査を無効化する攻撃は、`AGENTS.md` の改ざんとしてその回に検出されるため成立しない。

### 0.4 実在しないパスは無視される(誤検出しない)

抽出結果は `forbidden_files()` に渡り、そこで `[ -e ]` / `[ -d ]` を通る。実在しない語(説明のためにバックティックで囲んだだけの `<!-- verify-probe: ... -->` 等)は**列挙結果に現れないだけ**で害はない。この性質をコメントに明記する。

### 0.5 グロブ表記(`src/auth/**`)を受ける

`/kickoff` フェーズ4 の記入例は `src/auth/**` / `db/migrations/**` の形になっている(`.claude/commands/kickoff.md` L92)。フォーマットを変えるのはスコープ外なので、**スクリプト側で `dir/**` と `dir/*` を「そのディレクトリ配下すべて」として解釈する**。既存の `dir/` 表記も従来どおり動く。

`**/*.env` のような先頭グロブは解釈しない(該当なしとして無視される)。これはコメントに書く。

### 0.6 スナップショットを `sort -u` にする(必須)

汎用項目と抽出分は重複する(マーカー内には汎用項目も列挙されている)。重複したまま `forbidden_snapshot` を作ると、出口検査の違反抽出ロジック `sort | uniq -u` が**同一行が 2 本ずつ現れることで違反行を落とす** — 「変更は検出されたが該当パスが空表示になる」壊れ方をする。

`forbidden_snapshot()` の `sort` を `sort -u` に変える。パス重複(ディレクトリ指定とその配下ファイルの二重指定を含む)をここで畳む。

---

## 1. `.claude/scripts/delegate-codex.sh` の変更

### 1-A. 抽出ブロックの追加(入口検査2・3 の直後)

`入口検査2・3` ブロックの末尾(verify-probe の `elif ... fi` の直後)、`# ---------- 入口検査4: Codex CLI ----------` の直前に、次を挿入する:

```bash
# ---------- 出口検査の対象(プロジェクト固有パス)の抽出 ----------
#
# /kickoff フェーズ4 は AGENTS.md §4 のマーカー内へ、そのプロジェクトの実際の
# モジュールパス(認証・決済・データ移行など)を追記する。それを出口検査の対象に
# 加える(Issue #28)。スクリプト内の FORBIDDEN_PATHS は汎用項目の単一ソースとして
# そのまま残り、ここで抽出した分と**マージ**して使う。汎用項目は AGENTS.md から
# マーカーごと消されても消えない。
#
# ここで抽出する理由(プロンプト構築より前・codex exec より前):
#   委託先が実行中に AGENTS.md を書き換えても、その回の検査は開始時点のリストで
#   行われる必要がある。書き換えそのものは AGENTS.md(汎用項目)の内容ハッシュ差分
#   として別途検出される。
#
# 抽出はバックティック囲みの文字列すべて。実在しないもの(説明のために囲んだだけの
# 語や <!-- verify-probe: ... --> のような断片)は forbidden_files() の実在検査で
# 落ちるため、列挙結果に現れないだけで無害。
#
# フェイルオープンの条件: マーカーが片方しか無いとき。sed の範囲指定が末尾まで
# 走り、AGENTS.md 中の無関係なバックティック語まで禁止領域に化けて全委託が常に
# 失敗するため、警告だけ出して抽出しない(片方消しによる無効化は、AGENTS.md 自身の
# 改ざんとしてその回に検出される)。
PROJECT_FORBIDDEN_PATHS=()
_fp_start=0
_fp_end=0
grep -q '<!-- kickoff:delegation-forbidden-paths -->' "$AGENTS" 2>/dev/null && _fp_start=1
grep -q '<!-- /kickoff:delegation-forbidden-paths -->' "$AGENTS" 2>/dev/null && _fp_end=1

if [ "$_fp_start" = 1 ] && [ "$_fp_end" = 1 ]; then
  while IFS= read -r _fp_line; do
    [ -n "$_fp_line" ] && PROJECT_FORBIDDEN_PATHS+=("$_fp_line")
  done < <(
    sed -n '/<!-- kickoff:delegation-forbidden-paths -->/,/<!-- \/kickoff:delegation-forbidden-paths -->/p' "$AGENTS" 2>/dev/null |
      grep -o '`[^`]*`' | sed 's/^`//; s/`$//' | LC_ALL=C sort -u
  )
  unset _fp_line
elif [ "$_fp_start" = 1 ] || [ "$_fp_end" = 1 ]; then
  echo "delegate-codex: 警告 — AGENTS.md の <!-- kickoff:delegation-forbidden-paths --> マーカーが片方しかありません。プロジェクト固有パスの抽出をスキップします(汎用項目の検査は従来どおり働きます)。" >&2
fi
unset _fp_start _fp_end
```

### 1-B. `forbidden_files()` の書き換え

現在:

```bash
forbidden_files() {
  local _p
  for _p in "${FORBIDDEN_PATHS[@]}"; do
    case "$_p" in
      */) [ -d "${_p%/}" ] && find "${_p%/}" -type f -print 2>/dev/null ;;
      *) [ -e "$_p" ] && printf '%s\n' "$_p" ;;
    esac
  done | grep -Fxv -e "$REC" -e "$LOG" -e "$LAST" || true
```

これを次に変える(`done` 以降の行とコメントはそのまま残す):

```bash
forbidden_files() {
  local _p _d
  # 汎用項目(FORBIDDEN_PATHS)と AGENTS.md から抽出したプロジェクト固有パスの両方を見る。
  # 展開の順序が「汎用が先」なのは意図的: 抽出側が空でも汎用項目は必ず走る。
  # ${arr[@]+"${arr[@]}"} は set -u の下で空配列を安全に展開するための形。
  for _p in "${FORBIDDEN_PATHS[@]}" ${PROJECT_FORBIDDEN_PATHS[@]+"${PROJECT_FORBIDDEN_PATHS[@]}"}; do
    case "$_p" in
      # /kickoff の記入例は dir/** 形式(.claude/commands/kickoff.md)。dir/ と同じく
      # 配下すべてとして扱う。**/*.ext のような先頭グロブは解釈しない(該当なしになる)。
      */\*\* | */\*)
        _d="${_p%/*}"
        [ -d "$_d" ] && find "$_d" -type f -print 2>/dev/null
        ;;
      */) [ -d "${_p%/}" ] && find "${_p%/}" -type f -print 2>/dev/null ;;
      *) [ -e "$_p" ] && printf '%s\n' "$_p" ;;
    esac
  done | grep -Fxv -e "$REC" -e "$LOG" -e "$LAST" || true
```

### 1-C. `forbidden_snapshot()` の `sort` を `sort -u` にする

```bash
  forbidden_files | LC_ALL=C sort -u | while IFS= read -r _f; do
```

直前に理由コメントを 1 つ足す:

```bash
# sort -u なのは重複を畳むため(汎用項目とマーカー内の項目は重なる。ディレクトリ指定と
# その配下ファイルの二重指定も起こりうる)。重複行が残ると、出口検査の違反抽出
# (sort | uniq -u)が「2 回現れる行」として違反パスを取りこぼす。
```

### 1-D. `FORBIDDEN_PATHS` 上のコメント修正

L586-L589 付近の

```
# リストの単一ソースはここ。CLAUDE.md「Codex への委託禁止領域(パス)」と AGENTS.md §4 の
# <!-- kickoff:delegation-forbidden-paths --> は説明に徹し、内容をここと一致させる。
# 3 箇所目のリストファイルを作らないのは、そのファイル自身を守る層がまた要るため。
```

を次に差し替える:

```
# ここは**汎用項目**の単一ソース(全プロジェクトに配布される層)。プロジェクト固有パスの
# 単一ソースは AGENTS.md §4 の <!-- kickoff:delegation-forbidden-paths --> の中で、
# 起動直後に PROJECT_FORBIDDEN_PATHS へ抽出済み(Issue #28)。CLAUDE.md の同名の節は
# 説明に徹し、汎用項目の内容をここと一致させる。
# 3 箇所目のリストファイルを作らないのは、そのファイル自身を守る層がまた要るため。
```

### 1-E. 「空振り条件」の 1 行目を差し替える

`forbidden_snapshot()` 上のコメントにある

```
#   - /kickoff が AGENTS.md へ追記するプロジェクト固有パスは、この配列に無い限り
#     機械的には止まらない(散文の指示と司令塔の検収が担保)
```

を次に差し替える:

```
#   - AGENTS.md のマーカーが片方しか無いプロジェクトでは、固有パスの抽出をスキップする
#     (汎用項目の検査は働く)。また抽出結果のうち実在しないパスは列挙されない
```

---

## 2. `AGENTS.md` の変更

L145 の一文

```
> なお、機械的な検査(`delegate-codex.sh` の `FORBIDDEN_PATHS`)が見るのはテンプレート由来の汎用項目だけです。`/kickoff` が追記したプロジェクト固有パスは散文の指示として守ってください。
```

を次に差し替える(L144 はそのまま):

```
> この節のパスは散文の指示であると同時に、**機械的にも検査されます**。`delegate-codex.sh` は委託の開始時にマーカー内のバックティック囲みの文字列を抽出し、スクリプト内の汎用項目とマージして、委託の前後で内容ハッシュを突き合わせます。差分があればその委託は `failed` / `exit 2` になります。ディレクトリを指すときは `src/auth/` または `src/auth/**` の形で、実在するパスを書いてください(実在しない語をバックティックで囲んでも無視されるだけです)。
```

---

## 3. `CLAUDE.md` の変更

「Codex への委託禁止領域(パス)」節の

```
**このリストは `delegate-codex.sh` の出口検査(`FORBIDDEN_PATHS`)が単一ソース。** impl 委託の実行後に前後の内容ハッシュを突き合わせ、差分があれば `status=failed` / `exit 2` で止める。ここの記述はその説明であり、内容を変えるときはスクリプト側の配列と `AGENTS.md` §4 を同時に直す。
```

を次に差し替える:

```
**単一ソースは 2 系統に分かれる。** 上に挙げた**汎用項目**は `delegate-codex.sh` の `FORBIDDEN_PATHS` 配列が正。`/kickoff` フェーズ4 が書く**プロジェクト固有パス**(認証・決済・データ移行などの実パス)は `AGENTS.md` §4 の `<!-- kickoff:delegation-forbidden-paths -->` マーカー内が正で、出口検査が委託の開始時に抽出して配列とマージする。impl 委託の実行後に前後の内容ハッシュを突き合わせ、差分があれば `status=failed` / `exit 2` で止める。ここの記述はその説明であり、汎用項目を変えるときはスクリプト側の配列と `AGENTS.md` §4 を同時に直す。
```

---

## 4. `.claude/commands/kickoff.md` の変更(整合のため 1 行)

フェーズ4-3 の `AGENTS.md` 追記を指示する箇条書き(L95)の末尾に、次を足す:

```
。**この節のパスは出口検査が委託開始時に抽出して機械的に検査する**ため、実在するパスをバックティックで囲んで書く(ディレクトリは `src/auth/` または `src/auth/**`)
```

---

## 5. 再現テスト(`verification.md` に記録する)

`#20` の `verification.md` §2 のスタブを流用する。**実 Codex は呼ばない。**

### 5-0. スタブ(`FAKE_CODEX_CMD` を追加した版)

```bash
#!/bin/bash
# delegate-codex.sh の出口検査を試すためのスタブ(テスト専用)
[ "${1:-}" = "login" ] && exit 0
LASTPATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --output-last-message) LASTPATH="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "${FAKE_CODEX_CMD:-}" ] && bash -c "$FAKE_CODEX_CMD"
[ -n "${FAKE_CODEX_TOUCH:-}" ] && printf '\n<!-- tampered by fake codex -->\n' >> "$FAKE_CODEX_TOUCH"
[ -n "${FAKE_CODEX_WORK:-}" ] && printf 'fake work\n' >> "$FAKE_CODEX_WORK"
[ -n "$LASTPATH" ] && printf '完了: tasklist 1/1 / 変更 1 ファイル / lint・型・関連テスト pass\n' > "$LASTPATH"
exit 0
```

`PATH` の先頭にこのスタブを置く。

### 5-1. 共通の前置き

- テスト用ステアリング `.steering/zz-issue28-fixture/` を作り、`design.md`(`<!-- status: ready -->` を含む)と `tasklist.md`(`- [ ] dummy` 1 行)を置く
- **`AGENTS.md` / `CLAUDE.md` は `cp` でバックアップし、`cp` で戻す。`git checkout -- <path>` を使わない**(未コミットの本作業の変更ごと消える。#15・#20 で事故発生)
- `FAKE_CODEX_WORK` にはシナリオごとに**別名**の未追跡ファイル(`.steering/zz-issue28-fixture/scratchN.txt`)を渡す。#27 の修正(`--untracked-files=all`)により `git add` は不要
- 各シナリオの後、テストが作った成果物と run record を掃除する

### 5-2. シナリオ

| # | 前提 | 走らせ方 | 期待 |
| --- | --- | --- | --- |
| 1 | マーカー内に `- \`docs/dummy-project-secret.md\`` を追記し、そのファイルを作成 | `FAKE_CODEX_TOUCH=docs/dummy-project-secret.md` | `failed` / **exit 2**。違反一覧に `docs/dummy-project-secret.md` |
| 2 | `AGENTS.md` からマーカー行を両方削除(中身も削除) | `FAKE_CODEX_TOUCH=.husky/pre-commit` | `failed` / **exit 2**(汎用項目が従来どおり働く) |
| 3 | マーカー行は残し中身だけ全削除 | `FAKE_CODEX_TOUCH=.claude/codex-denylist.txt` | `failed` / **exit 2**(汎用項目の保護が消えない) |
| 4 | マーカー内に `- \`これは説明用の語\`` を追記(実在しない) | `FAKE_CODEX_TOUCH` なし / `FAKE_CODEX_WORK` のみ | **exit 0** / `completed`(誤検出しない) |
| 5 | マーカー内に `docs/dummy-late.md` を**委託中に**追記させる | `FAKE_CODEX_CMD` でマーカー内に 1 行追記 + `docs/dummy-late.md` を作成、`FAKE_CODEX_TOUCH` なし | `failed` / **exit 2**。違反一覧は **`AGENTS.md` のみ**(`docs/dummy-late.md` は含まれない = 開始時点のリストで検査された証拠) |
| 6 | マーカーの終了側だけ削除 | `FAKE_CODEX_WORK` のみ | 警告「マーカーが片方しかありません」が出て **exit 0**(過剰阻止しない) |

シナリオ 1・5 で「違反一覧」を見るには標準エラーの末尾(`該当:` 以下)と run record の `error` フィールドを確認する。

### 5-3. 記録

`verification.md` に、各シナリオの実行コマンド・実際の exit code・標準エラーの要点・run record の `status` を残す。design.md と実機挙動が食い違った場合は**その差分も明記する**(#20 の verification.md §3 と同じ扱い)。

---

## 6. 完了条件

- `bash -n .claude/scripts/delegate-codex.sh` が通る
- シナリオ 1〜6 がすべて期待どおり
- テスト用の一時ファイル(`.steering/zz-issue28-fixture/` / `docs/dummy-*.md` / スタブ / 追加した run record)が残っていない
- `AGENTS.md` / `CLAUDE.md` / `kickoff.md` の記述が実装と一致している
- `/check`(lint・フォーマット)が通る
