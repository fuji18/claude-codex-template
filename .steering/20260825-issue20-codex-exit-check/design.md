<!-- status: ready -->

# 設計: Codex 委託の出口検査

対象ファイル(この 3 つ以外は触らない):

1. `.claude/scripts/delegate-codex.sh`
2. `CLAUDE.md`
3. `AGENTS.md`

加えて `.steering/20260825-issue20-codex-exit-check/verification.md` を新規作成する(§5)。

---

## 0. 設計判断(実装者は判断しない。ここに書いてある通りにする)

### 0.1 リストの単一ソースはスクリプト内の配列にする

`CLAUDE.md` / `AGENTS.md` の 2 箇所は既にコピーが存在する。3 箇所目のファイル
(`.claude/codex-forbidden-paths.txt` 等)を作ると、そのファイル自身を保護する層が
さらに必要になり、入れ子が増えるだけで得がない。

`delegate-codex.sh` は**起動直後に自身を一時ディレクトリへコピーして exec する**
(自己編集ハザード対策、スクリプト冒頭)。したがって実行中のプロセスが読むリストは
委託先から書き換え不能で、スナップショットのような追加の防御が要らない。

散文 2 箇所は説明に徹し、内容だけを配列と一致させる。

### 0.2 git status ではなく「内容ハッシュのスナップショット比較」で判定する

Issue のスコープには `git diff --name-only` 系の突き合わせと書かれているが、
それだけでは 3 つ取りこぼす。**採用するのは内容ハッシュ方式**:

| 取りこぼし | 理由 | ハッシュ方式ならどうなるか |
| --- | --- | --- |
| `.harness/mode` / `.harness/codex-runs/` | `.gitignore` 済み(`.gitignore:53-54`)で `git diff` にも `git ls-files --others --exclude-standard` にも出ない | 追跡状態に依存しないので検出できる |
| モード C(`degraded`)で Codex がコミットした変更 | 作業ツリー比較だけでは HEAD に入った差分が消える | 同上 |
| 委託前から dirty な禁止領域ファイル | パス単位の突き合わせだと誤検出する | 内容が同じなら差分ゼロ = 誤検出しない |

ハッシュは `git hash-object` を使う。git はこのスクリプトの動作前提(冒頭で
`git rev-parse --show-toplevel` に失敗したら即 `exit 2`)なので新規依存にならず、
`sha256sum` / `shasum` の環境差も踏まない。追跡外・`.gitignore` 済みのファイルにも使える。

### 0.3 判定行より前、かつ `CODEX_EXIT` の分岐より前に置く

Issue には「`write_record "completed"` の直前」とあるが、実際にはもっと前に置く。

- `判断待ち` / `失敗` で戻ってきた委託でも、禁止領域が書き換わっていれば脱出経路は
  成立している。委託先の自己申告より優先して司令塔に見せる必要がある
- レート上限・認証失敗・異常終了(`CODEX_EXIT != 0`)の分岐は無条件 `exit` なので、
  その後ろに置くと**その経路が丸ごと素通しになる**。「改ざんしてから上限に当たった」
  セッションが `rate-limited` として静かに記録されるのが最悪のケース(初版はこの穴を
  残しており、検収で P0 として指摘された)

したがって `SUMMARY` の代入直後・`if [ "$CODEX_EXIT" -ne 0 ]` の直前に、
`if [ "$MODE" = "impl" ]` だけを条件として置く。出口検査は他のどの終了理由よりも優先し、
上限で終わった委託であっても禁止領域が変わっていれば `failed` / `exit 2` を返す。

これは Issue の範囲を狭めるのではなく広げる向きの変更なので、受け入れ条件はすべて満たす。

### 0.4 既知の空振り条件(コメントとして必ずスクリプトに書く)

- `/kickoff` フェーズ4 が `AGENTS.md` へ追記する**プロジェクト固有パス**は、この配列に
  無い限り機械的には止まらない(散文の指示と司令塔の検収が担保)
- `git hash-object` が前後どちらの時点でも同じように失敗した場合、その差分は検出できない
- `explore` / `review` は `--sandbox read-only` なので出口検査そのものを行わない

---

## 1. `delegate-codex.sh` の変更

### 1-A. 入口検査0 の依存コマンドに `sort` と `uniq` を足す

現在の該当行(151-162 行目付近):

```bash
for _cmd in find grep sed head tail tr; do
```

を次に変える:

```bash
for _cmd in find grep sed head tail tr sort uniq; do
```

理由: 出口検査の差分抽出が `sort` / `uniq` に依存する。`tree_snapshot` も既に `sort` を
使っているのに宣言されていなかった。「検査が静かに素通しする状態を作らない」という
入口検査0 の趣旨に合わせて宣言側に足す。**コメントは既存のものをそのまま残す。**

### 1-B. 禁止パスリストと 2 つのヘルパー関数を追加する

**挿入位置**: `# ---- 事前スナップショット(exit 0 の裏取りに使う。impl 以外では取らない) ----`
のコメントブロックの直前(`SANDBOX="read-only"` / `[ "$MODE" = "impl" ] && SANDBOX="workspace-write"`
の直後)。

`RUN_ID` / `REC` / `LOG` / `LAST` が確定している位置より後であることが必須(除外に使う)。

```bash
# ---------- 出口検査の対象(委託禁止領域)----------
#
# 入口検査が 5 系統あるのに出口が素通しだった穴を塞ぐ層。--sandbox workspace-write の
# Codex はワークツリー内なら禁止領域も書けてしまい、書かれた先の一部は**後でサンドボックスの
# 外で実行される**:
#   - AGENTS.md の <!-- verify-probe: ... --> は、次回委託時に入口検査3 がホスト上の
#     bash -c にそのまま渡す(サンドボックス内で 1 行書く → 次回起動でホスト実行)
#   - .husky/* / .claude/scripts/* はホストの git・Claude セッションが実行する
#   - .github/workflows/* は非 fork PR で CLAUDE_CODE_OAUTH_TOKEN に触れる定義そのもの
#
# リストの単一ソースはここ。CLAUDE.md「Codex への委託禁止領域(パス)」と AGENTS.md §4 の
# <!-- kickoff:delegation-forbidden-paths --> は説明に徹し、内容をここと一致させる。
# 3 箇所目のリストファイルを作らないのは、そのファイル自身を守る層がまた要るため。
# このスクリプトは起動直後に自身をコピーして exec するので、実行中のプロセスが読む
# この配列は委託先から書き換えられない。
#
# 末尾が / のものはディレクトリ配下すべてが対象。
FORBIDDEN_PATHS=(
  ".claude/scripts/delegate-codex.sh"
  ".claude/scripts/check-protected-branch.sh"
  ".husky/pre-commit"
  ".husky/prepare-commit-msg"
  ".claude/codex-denylist.txt"
  "AGENTS.md"
  ".github/workflows/"
  ".harness/mode"
  ".harness/codex-runs/"
)

# 禁止領域の実ファイルを列挙する。今回の委託自身が書く 3 ファイル(run record・生ログ・
# last message)は当然変わるので除外する。除外しないと全ての impl 委託が必ず違反になる。
forbidden_files() {
  local _p
  for _p in "${FORBIDDEN_PATHS[@]}"; do
    case "$_p" in
      */) [ -d "${_p%/}" ] && find "${_p%/}" -type f -print 2>/dev/null ;;
      *) [ -e "$_p" ] && printf '%s\n' "$_p" ;;
    esac
  done | grep -Fxv -e "$REC" -e "$LOG" -e "$LAST"
}

# `<hash> <path>` を path 順に並べたスナップショット。git status 系ではなく内容ハッシュで
# 比べる理由は 3 つ:
#   1. .harness/mode と .harness/codex-runs/ は .gitignore 済みで git diff にも
#      git ls-files --others --exclude-standard にも出ない
#   2. モード C では Codex がコミットするため、作業ツリー比較だけでは取りこぼす
#   3. 委託前から dirty だったファイルを誤検出しない(内容が同じなら差分ゼロ)
#
# ハッシュに git hash-object を使うのは、git がこのスクリプトの動作前提であり
# (git リポジトリ外では冒頭で落とす)、追跡外・.gitignore 済みのファイルにも効くため。
#
# 空振り条件:
#   - /kickoff が AGENTS.md へ追記するプロジェクト固有パスは、この配列に無い限り
#     機械的には止まらない(散文の指示と司令塔の検収が担保)
#   - git hash-object が前後どちらの時点でも同じように失敗した場合、差分は検出できない
#   - explore / review は read-only なのでこの検査を行わない
forbidden_snapshot() {
  local _f _h
  forbidden_files | LC_ALL=C sort | while IFS= read -r _f; do
    _h="$(git hash-object -- "$_f" 2>/dev/null)"
    printf '%s %s\n' "${_h:-UNREADABLE}" "$_f"
  done
}
```

### 1-C. 事前スナップショットに 1 行足す

現在:

```bash
if [ "$MODE" = "impl" ]; then
  TREE_BEFORE="$(tree_snapshot)"
  HEAD_BEFORE="$(git rev-parse HEAD 2>/dev/null || echo none)"
  DONE_BEFORE="$(count_done)"
fi
```

変更後(最後に 1 行追加するだけ):

```bash
if [ "$MODE" = "impl" ]; then
  TREE_BEFORE="$(tree_snapshot)"
  HEAD_BEFORE="$(git rev-parse HEAD 2>/dev/null || echo none)"
  DONE_BEFORE="$(count_done)"
  FORBIDDEN_BEFORE="$(forbidden_snapshot)"
fi
```

### 1-D. 出口検査の本体を追加する

**挿入位置**: `if [ "$MODE" = "impl" ]; then` (出口判定側、`VERDICT="$(grep -hE ...`
の直前にあるコメントブロックより前)の**直後**。つまり impl ブロックの先頭。

追加するコード:

```bash
  # ---- 出口検査: 委託禁止領域への差分 ----
  #
  # 判定行(完了 / 判断待ち / 失敗)より前に置く。判断待ち・失敗で戻ってきた委託でも
  # 禁止領域が書き換わっていれば脱出経路は成立しているため、委託先の自己申告より
  # 優先して司令塔に見せる。
  FORBIDDEN_AFTER="$(forbidden_snapshot)"
  if [ "$FORBIDDEN_AFTER" != "$FORBIDDEN_BEFORE" ]; then
    # 前後のスナップショットを合わせて「1 回しか出てこない行」を拾う。
    # 変更 = 旧ハッシュ行と新ハッシュ行が 1 本ずつ、追加/削除 = 片方だけ。
    # そこからパス部分だけを取り出して重複を畳む。
    VIOLATIONS="$(
      printf '%s\n%s\n' "$FORBIDDEN_BEFORE" "$FORBIDDEN_AFTER" |
        grep -v '^[[:space:]]*$' | LC_ALL=C sort | uniq -u |
        sed 's/^[^ ]* //' | LC_ALL=C sort -u
    )"
    VIOL_LINE="$(printf '%s' "$VIOLATIONS" | tr '\n' ' ')"
    SUMMARY="⚠️ 委託禁止領域が変更されました(出口検査): $VIOL_LINE

$SUMMARY"
    write_record "failed" "$SUMMARY" "委託禁止領域が変更されました: $VIOL_LINE" ""
    emit "failed" "$EX_FAIL"
    cat >&2 <<'MSG'
delegate-codex: 委託禁止領域のファイルが変更されました(出口検査)。

これらはサンドボックスの外で実行される層(AGENTS.md の verify-probe / .husky/* /
.github/workflows/* / run record)です。委託の成果をそのまま採用しないでください。

  git diff -- <該当パス>

で内容を確認し、意図しない変更は破棄してから検収してください。

該当:
MSG
    printf '%s\n' "$VIOLATIONS" | sed 's/^/  /' >&2
    exit "$EX_FAIL"
  fi

```

**注意**: `SUMMARY` は既にこの時点で代入済み(`[ -f "$LAST" ] && SUMMARY="$(head -c 2000 "$LAST")"`)。
`write_record` / `emit` / `EX_FAIL` も定義済み。新しい変数は増やさない。

---

## 2. `CLAUDE.md` の変更

`## プロジェクト固有ルール` → `### Codex への委託禁止領域(パス)` 節。

現在の箇条書き 3 項目の**後ろに**次の 3 項目を追記する(既存 3 項目は一字も変えない):

```markdown
- `AGENTS.md` — 委託先の憲法。入口検査3 の `<!-- verify-probe: ... -->` は次回委託時にホスト上の `bash -c` へそのまま渡されるため、書き換えを許すとサンドボックス外でのコマンド実行経路になる
- `.github/workflows/` — 非 fork PR で `CLAUDE_CODE_OAUTH_TOKEN` にアクセスできるワークフロー定義そのもの
- `.harness/mode` / `.harness/codex-runs/` — ハーネスモードと run record。委託先が自分の結果を `accepted` に書き換えたりモードを詐称したりできてはならない
```

さらに、その下にある段落:

```markdown
**機密の送信禁止(`.claude/codex-denylist.txt`)とは別の層。** denylist は該当ファイルが存在するだけで委託を止めるフェイルクローズ検査、こちらは司令塔が「どのチケットを渡すか」を決める振り分け判断。
```

の**直後に**次の 1 段落を追加する:

```markdown
**このリストは `delegate-codex.sh` の出口検査(`FORBIDDEN_PATHS`)が単一ソース。** impl 委託の実行後に前後の内容ハッシュを突き合わせ、差分があれば `status=failed` / `exit 2` で止める。ここの記述はその説明であり、内容を変えるときはスクリプト側の配列と `AGENTS.md` §4 を同時に直す。
```

---

## 3. `AGENTS.md` の変更

### 3-A. マーカー内のリスト(134-138 行目)

`<!-- kickoff:delegation-forbidden-paths -->` と `<!-- /kickoff:delegation-forbidden-paths -->`
の間にある既存 3 行の**後ろに**次を追記する。**マーカー行は消さない。既存 3 行も変えない。**

```markdown
- `AGENTS.md` — このファイル自身。冒頭の `<!-- verify-probe: ... -->` は次回の委託時にホスト側で実行されるため、あなたが書き換えるとサンドボックスの外へ影響が出ます
- `.github/workflows/` — CI 定義そのもの。ここを書き換えると認証済みトークンに触れられます
- `.harness/mode` / `.harness/codex-runs/` — ハーネスモードと委託の実行記録。自分の結果を承認済みにすることはできません
```

### 3-B. 節の導入文(132 行目)

現在:

```markdown
以下のパスに触れる変更は**委託の対象外**です。タスクがこれらの変更を求めている場合、**変更せずに停止して報告してください**(モード C では `codex-log.md` に記録して、その項目だけ飛ばします)。
```

この直後に次の 1 行を追加する:

```markdown
これは機械的にも検査されます。委託の終了時に上記パスの内容ハッシュが照合され、差分があると委託全体が `failed` として扱われます(あなたの報告内容にかかわらず)。他の作業が正しくても巻き添えで無効になるため、触らないでください。
```

### 3-C. マーカー下の注記(140 行目)

現在の `> 上の項目はテンプレート由来の**汎用項目**で、…` の段落の末尾に、次の文を足す:

```markdown
なお、機械的な検査(`delegate-codex.sh` の `FORBIDDEN_PATHS`)が見るのはテンプレート由来の汎用項目だけです。`/kickoff` が追記したプロジェクト固有パスは散文の指示として守ってください。
```

---

## 4. 検証(実装者が実行する)

`.claude/scripts/delegate-codex.sh` を編集したら、まず構文だけ確認する:

```bash
bash -n .claude/scripts/delegate-codex.sh
```

次に §5 の再現テストを 3 シナリオとも実行し、結果を `verification.md` に書く。

最後に、変更したファイルだけを対象に品質チェックを回す:

```bash
npx prettier --check CLAUDE.md AGENTS.md .steering/20260825-issue20-codex-exit-check/*.md
```

(`--write` で直してよい。`npm run format` のような全体フォーマットは禁止。)

---

## 5. 再現テスト(`verification.md` に手順と実行結果を残す)

実 Codex を呼ばずに検査を通すため、**`codex` のスタブを PATH の先頭に置いて**
`delegate-codex.sh impl` を回す。スタブは 3 シナリオ共通で、環境変数で挙動を変える。

### 5-0. 準備

```bash
set -u
WORK="$(mktemp -d)"
cat > "$WORK/codex" <<'STUB'
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
[ -n "${FAKE_CODEX_TOUCH:-}" ] && printf '\n<!-- tampered by fake codex -->\n' >> "$FAKE_CODEX_TOUCH"
[ -n "${FAKE_CODEX_WORK:-}" ] && printf 'fake work\n' >> "$FAKE_CODEX_WORK"
[ -n "$LASTPATH" ] && printf '完了: tasklist 1/1 / 変更 1 ファイル / lint・型・関連テスト pass\n' > "$LASTPATH"
exit 0
STUB
chmod +x "$WORK/codex"

S=".steering/99999999-exit-check-probe"
mkdir -p "$S"
printf '<!-- status: ready -->\n\n# ダミー\n' > "$S/design.md"
printf -- '- [ ] ダミータスク\n' > "$S/tasklist.md"
printf 'scratch\n' > "$S/scratch.txt"
```

`FAKE_CODEX_WORK` に `$S/scratch.txt` を渡すことで、成果実在確認(作業ツリーの変化)を通す。

### 5-1. シナリオ1 — 禁止領域を書き換えた委託は failed / exit 2

```bash
PATH="$WORK:$PATH" FAKE_CODEX_TOUCH="AGENTS.md" FAKE_CODEX_WORK="$S/scratch.txt" \
  CODEX_DELEGATE_ACK_SECRETS=1 \
  .claude/scripts/delegate-codex.sh impl "$S"; echo "exit=$?"
git checkout -- AGENTS.md
```

期待: `status=failed` / `exit=2` / stderr に `AGENTS.md` が列挙される。
`.harness/codex-runs/<id>.json` の `status` が `failed`、`error` に該当パスが入る。

同じ手順を `FAKE_CODEX_TOUCH=".husky/pre-commit"` と
`FAKE_CODEX_TOUCH=".github/workflows/ci.yml"` でも 1 回ずつ実行する
(各回のあとに `git checkout -- <そのパス>` で戻す)。

### 5-2. シナリオ2 — 禁止領域に触れない委託は completed / exit 0(誤検出なし)

```bash
PATH="$WORK:$PATH" FAKE_CODEX_WORK="$S/scratch.txt" CODEX_DELEGATE_ACK_SECRETS=1 \
  .claude/scripts/delegate-codex.sh impl "$S"; echo "exit=$?"
```

期待: `status=completed` / `exit=0`。

### 5-3. シナリオ3 — 委託前から dirty な禁止領域ファイルを誤検出しない

```bash
printf '\n<!-- pre-existing local edit -->\n' >> AGENTS.md
PATH="$WORK:$PATH" FAKE_CODEX_WORK="$S/scratch.txt" CODEX_DELEGATE_ACK_SECRETS=1 \
  .claude/scripts/delegate-codex.sh impl "$S"; echo "exit=$?"
git checkout -- AGENTS.md
```

期待: `status=completed` / `exit=0`(委託中は AGENTS.md が変わっていないため)。

### 5-4. 後片付け(必ず実行する)

```bash
rm -rf "$S" "$WORK"
git status --short          # AGENTS.md / .husky/pre-commit / .github/workflows/ci.yml が
                            # 元に戻っていること。意図した 3 ファイル以外の変更が無いこと
```

`.harness/codex-runs/` に残ったテスト用 run record は `.gitignore` 済みなので
コミットには影響しないが、紛らわしいので削除してよい(`id` はテスト実行時のタイムスタンプ)。

### 5-5. `verification.md` に書くこと

- 上の 5 シナリオ(1 は 3 パス分)の**実際の出力**(`status=` の行と `exit=` の値)
- スタブスクリプトの全文(再現に必要なため)
- 想定と違った点があればその内容
