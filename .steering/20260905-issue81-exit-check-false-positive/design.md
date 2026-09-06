<!-- status: ready -->

# 設計: 出口検査の誤爆を止める(#81)

## 0. 前提の確認(実装前に読む)

- 変更対象はすべて**委託禁止領域**(`.claude/scripts/` / `.claude/rules/`)。**Codex には委託しない**
- `delegate-codex.sh` は起動直後に自身と `lib-*.sh` を一時ディレクトリへコピーして exec する(#15)。編集した内容は次回起動から効く
- `set -uo pipefail`(`set -e` は無い)。既存コードの `[ 条件 ] && var=...` の書き方はそのまま踏襲してよい
- `rec_field` は `lib-record.sh`。impl 経路では入口検査0-2 が jq を保証している(#63)
- **既存コメントを削らない。** この層の保守はコメントで成立している。実態と食い違った記述は**直す**(消すのではなく書き換える)

## 1. 中心の判断

### 1-1. 守りたい性質を「不変」から「検収状態の不変」に置き換える

`.harness/codex-runs/` を禁止領域に入れた目的は「**委託先が自分の結果を `accepted: true` に書き換えたり、`status` を詐称したりできないこと**」であって、「ディレクトリが 1 バイトも変わらないこと」ではない。内容ハッシュ方式はこの目的に対して過剰で、意図された並行運用(read-only の explore / review)と衝突する。

したがって:

- **内容ハッシュ比較(`forbidden_snapshot()`)からは `.harness/codex-runs/` を外す**(B1 / C3 の解決)
- **代わりに、BEFORE 時点に存在した record の `status` / `accepted` だけを突き合わせる専用検査を足す**(守りたい性質の維持)

`FORBIDDEN_PATHS` の配列からは**外さない**。委託先が触ってよい領域になったわけではなく、`--print-forbidden` の出力・`CLAUDE.md` / `AGENTS.md` の記述・`check-forbidden-paths-doc.sh` の照合・5-5b の pathspec はすべて現状のまま維持する。**除外するのはハッシュ比較の対象からだけ**。

### 1-2. 並行 run 自身の正常な状態遷移は違反にしない

並行する explore / review は、起動時に `status=running` の record を書き、終了時に record 全体を書き直す(`write_record` は毎回 JSON を丸ごと出力する)。したがって「BEFORE で `running` だった record の `status` が変わる」ことは**正常**。

判定規則は次の 4 行に確定する(実装者はここから逸脱しない):

| BEFORE と AFTER の差 | 判定 |
| --- | --- |
| BEFORE にあった record が AFTER で**消えている** | **違反** |
| `accepted` が変化した(`false`→`true` も `true`→`false` も) | **違反** |
| `status` が変化し、かつ BEFORE の `status` が `running` **でない** | **違反** |
| `status` が変化し、BEFORE の `status` が `running` である | 許容(並行 run 自身の正常終了) |
| AFTER にしか無い record(並行 run が新規に作った) | 無視 |

自分の record(`$REC`)は常に対象外。BEFORE スナップショットを取る時点では `$REC` はまだ存在しない(`write_record "running"` は BEFORE より後)が、除外は明示的に書く。

### 1-3. 人間の `accept` / `set-status` / `prune` は、実行中は受け付けない

`accepted: false → true` という**同じバイト列の変化**を、「人間がホストで叩いた `codex-run.sh accept`」と「委託先がサンドボックス内で書き換えた」に**ファイルの内容からは区別できない**。Issue の受け入れ条件は両方を要求している(前者は `completed` で終わること / 後者は `failed` になること)ので、**書き換えが起きる側を止める**ことで両立させる。

- `codex-run.sh` の**書き込み系サブコマンド**(`accept` / `set-status` / `prune`)は、**mode=impl かつ status=running かつ pid 生存**の record があるとき `exit 1` で拒否する
- 判定は入口検査5-5 と同じ軸(`mode` / `status` / `pid` の生存)。**判定ロジックを共有化しない**(スクリプトをまたぐ source を増やすより、20 行の重複のほうが安い。`lib-*.sh` への切り出しは #86 の範囲)
- 逃げ道は `CODEX_RUN_FORCE=1`。使えば書けるが、**実行中の impl はその変更を検出して `failed` で終わる**ことをメッセージに明記する
- **これはセキュリティ層ではない。** 委託先はサンドボックス内から同じ書き換えができる(それは検出される側)。目的は「検査が鳴ったら本物」という信号の純度を保つ運用ロック。コメントにこの区別を書くこと
- 読み取り系(`list` / `pending` / `show`)は**止めない**

### 1-4. record 状態のスナップショットはバッチ化しない

`forbidden_snapshot()` はハッシュを `git hash-object --stdin-paths` の 1 プロセスに畳んでいる(#65)。record 状態は**同じことをしない** — jq を 1 record につき 1 回呼ぶ。

理由: バッチ経路とフォールバック経路の出力表現がわずかにでもズレると(`null` の扱い、壊れた record での打ち切り)、**BEFORE がバッチ・AFTER がフォールバックに落ちた瞬間に「改ざん検出」の偽陽性が出る**。それはこのチケットが潰そうとしている失敗そのもの。record 数は `prune` の既定で 20 本前後、警告閾値でも 50 本で、jq 20〜50 回(前後で 40〜100 回)は許容範囲。**この判断をコメントに残すこと**(次に #65 と同じ最適化を当てようとする人が同じ穴を掘らないため)。

### 1-5. Issue のスコープ 3(応急処置)は採らない

「BEFORE に無かったファイルすべて + 全 `.log` を除外する」案は誤爆こそ止まるが、既存 record の書き換え検出を担保できない(Issue 本文もそう書いている)。1-1 の形で置き換える。

## 2. 変更内容(ファイルごと)

### 2-1. `.claude/scripts/delegate-codex.sh`

#### (a) `forbidden_files()` — `$RUN_DIR` を列挙対象から外す

`for _p in "${FORBIDDEN_PATHS[@]}" ...; do` のループ本体の**先頭**に、`case` 判定を 1 つ足す:

```bash
    # #81: run record ディレクトリだけはハッシュ比較の対象外(関数上のコメント参照)。
    # 末尾スラッシュの有無を吸収して比較する。AGENTS.md 由来の固有パスに
    # 同じディレクトリが書かれていた場合もここで落ちる。
    case "${_p%/}" in
      "$RUN_DIR") continue ;;
    esac
```

**末尾の `grep -Fxv -e "$REC" -e "$LOG" -e "$LAST"` は残す。** 上の `case` は「`.harness/codex-runs/` という要素」を落とすだけで、固有パスに親ディレクトリ(`.harness/` 等)が書かれていれば `find` が配下を拾いうる。その場合の第 2 層として意味を持つ。**この理由を既存コメントに書き足す**(現状のコメントは「3 ファイルを除外する」理由しか書いていない)。

関数の直前のコメント(「禁止領域の実ファイルを列挙する。今回の委託自身が書く 3 ファイル…」)を、次の 3 点が読み取れる形に書き換える:

1. `.harness/codex-runs/` は**列挙しない**。理由は「守りたいのは検収状態であってバイト列ではない」+「意図された並行運用(explore / review)と衝突する」(#81)
2. 検収状態は `record_state_snapshot()` が別に見る(層が消えたのではなく移った)
3. 自分の 3 ファイルの除外は、親ディレクトリ経由で配下が拾われた場合の第 2 層として残してある

#### (b) `record_state_snapshot()` を新設する

`forbidden_snapshot()` の**直後**、`lifecycle_snapshot()` の**直前**に置く。

```bash
# ---- run record の検収状態(委託前後で突き合わせる)のヘルパー ----
#
# .harness/codex-runs/ を内容ハッシュ比較から外した代わりの層(#81)。守りたいのは
# 「委託先が既存 record の accepted / status を書き換えないこと」であって、ディレクトリが
# 1 バイトも変わらないことではない。ハッシュ方式は意図された並行運用(read-only の
# explore / review は入口検査5 を通らず並行できる)と衝突し、正常に完了した impl を
# 「委託禁止領域が変更されました」で failed にしていた(B1)。
#
# 1 行 = `<record のファイル名> <status> <accepted>`。自分の record($REC)は除く。
#
# **バッチ化しない(#81 design 1-4)。** forbidden_snapshot() は #65 で
# git hash-object --stdin-paths の 1 プロセスに畳んだが、ここで同じことをすると
# バッチ経路とフォールバック経路の表現差(null の扱い・壊れた record での打ち切り)が
# そのまま「BEFORE と AFTER の不一致」= 改ざんの偽陽性になる。潰したい失敗そのものなので、
# jq は 1 record につき 1 回でよい(prune の既定で 20 本前後、警告閾値でも 50 本)。
#
# 空振り条件:
#   - jq が無ければ全 record が UNREADABLE になる。前後で同じ扱いなので差分は出ない
#     (impl 経路では入口検査0-2 が jq を保証している)
#   - 割り込みで出口検査に到達しなかった場合は forbidden_snapshot() と同じ限界を持つ
record_state_snapshot() {
  local _f _line
  [ -d "$RUN_DIR" ] || return 0
  for _f in "$RUN_DIR"/*.json; do
    [ -f "$_f" ] || continue
    [ "$_f" = "$REC" ] && continue
    # status / accepted を 1 回の jq で取る。キーが無い/null は MISSING に正規化する
    # (rec_field の「null は空文字列」と違い、空行にすると読み戻しでフィールドがずれる)。
    _line="$(jq -r '[(.status // "MISSING"), (if .accepted == null then "MISSING" else (.accepted | tostring) end)] | join(" ")' "$_f" 2>/dev/null)"
    [ -n "$_line" ] || _line="UNREADABLE UNREADABLE"
    printf '%s %s\n' "${_f##*/}" "$_line"
  done | LC_ALL=C sort
}
```

#### (c) BEFORE スナップショットを取る

`if [ "$MODE" = "impl" ]; then` の事前スナップショットのブロック(`FORBIDDEN_BEFORE` / `LIFECYCLE_BEFORE` を取っている場所)に 1 行足す:

```bash
  RECSTATE_BEFORE="$(record_state_snapshot)"
```

`FORBIDDEN_BEFORE` の**直後**に置く(読む順序を検査の順序と揃える)。

#### (d) 出口検査を足す

**禁止領域の差分検査ブロックの直後・ライフサイクル警告ブロックの直前**に、新しい `if [ "$MODE" = "impl" ]; then ... fi` を足す。位置の理由は禁止領域検査と同じ(判定行より前・`CODEX_EXIT` の分岐より前)なので、**その旨をコメントに 1 行書いて既存ブロックのコメントを参照させる**。

```bash
# ---------- 出口検査: run record の検収状態 ----------
#
# .harness/codex-runs/ を内容ハッシュ比較から外した代わりの層(#81)。位置の理由は
# 直前の禁止領域検査と同じ(判定行より前・CODEX_EXIT の分岐より前)。
#
# 違反の定義(design 1-2):
#   - BEFORE にあった record が消えている
#   - accepted が変化した(false→true も true→false も)
#   - status が変化し、かつ BEFORE の status が running でない
# BEFORE で running だった record の status 変化は、並行する explore / review 自身の
# 正常終了なので違反にしない。AFTER にしか無い record(並行 run の新規作成)は無視する。
if [ "$MODE" = "impl" ]; then
  RECSTATE_AFTER="$(record_state_snapshot)"
  REC_VIOLATIONS=""
  while read -r _rid _rst _racc; do
    [ -n "${_rid:-}" ] || continue
    _aline="$(printf '%s\n' "$RECSTATE_AFTER" | awk -v id="$_rid" '$1 == id { print; exit }')"
    if [ -z "$_aline" ]; then
      REC_VIOLATIONS="${REC_VIOLATIONS}${REC_VIOLATIONS:+ }${_rid}(削除された)"
      continue
    fi
    _aacc="$(printf '%s\n' "$_aline" | awk '{ print $3 }')"
    if [ "$_aacc" != "$_racc" ]; then
      REC_VIOLATIONS="${REC_VIOLATIONS}${REC_VIOLATIONS:+ }${_rid}(accepted: $_racc → $_aacc)"
      continue
    fi
    _ast="$(printf '%s\n' "$_aline" | awk '{ print $2 }')"
    if [ "$_ast" != "$_rst" ] && [ "$_rst" != "running" ]; then
      REC_VIOLATIONS="${REC_VIOLATIONS}${REC_VIOLATIONS:+ }${_rid}(status: $_rst → $_ast)"
    fi
  done <<<"$RECSTATE_BEFORE"

  if [ -n "$REC_VIOLATIONS" ]; then
    REC_ERR="run record の検収状態が書き換えられました: $REC_VIOLATIONS"
    [ "$CODEX_EXIT" -ne 0 ] && REC_ERR="$REC_ERR (codex exit=$CODEX_EXIT / $ERR3)"
    add_host_notice "⚠️ run record の検収状態が書き換えられました(出口検査): $REC_VIOLATIONS"
    write_record "failed" "$SUMMARY" "$REC_ERR" ""
    emit "failed" "$EX_FAIL"
    cat >&2 <<'MSG'
delegate-codex: 既存 run record の検収状態(status / accepted)が変更されました(出口検査)。

run record は「会話に依存しない状態の正」で、accepted は検収の通過を表します。
委託先がこれを書き換えると、未検収の成果が検収済みに見えます。委託の成果をそのまま
採用しないでください。

  bash .claude/scripts/codex-run.sh show <id>

で内容を確認してください。人間が委託の実行中に codex-run.sh accept / set-status /
prune を叩いた場合も同じ検出になります(その経路は実行中は拒否されます。
CODEX_RUN_FORCE=1 で強行した場合はここで鳴ります)。

該当:
MSG
    printf '%s\n' "$REC_VIOLATIONS" | tr ' ' '\n' | sed 's/^/  /' >&2
    exit "$EX_FAIL"
  fi
fi
```

`while ... done <<<"$RECSTATE_BEFORE"` はヒアストリングであってパイプではない(サブシェルにならず `REC_VIOLATIONS` が残る)。**パイプに書き換えないこと。**

ループで使うローカル変数(`_rid` / `_rst` / `_racc` / `_aline` / `_aacc` / `_ast`)はトップレベルなので `local` を付けられない。既存コードと同じくそのまま使う。

#### (e) 実態と食い違うコメントを直す(必須)

| 場所 | 現状の記述 | 直し方 |
| --- | --- | --- |
| `FORBIDDEN_PATHS` 配列の直前のコメント | `.harness/*` の説明が無い | 配列末尾の `.harness/codex-runs/` について「**列挙は残すがハッシュ比較の対象外**。検収状態は出口検査の `record_state_snapshot()` が見る(#81)」を 2〜3 行で足す |
| `RUN_WARN_THRESHOLD` の直前(「溜まるほど出口検査の `forbidden_snapshot()` が前後 2 回ハッシュするファイル数が増える」) | #81 で**偽になった** | 「ハッシュ比較の対象からは外れた(#81)ので委託ごとのハッシュコストは増えない。閾値の意味は**検収キューとしての可読性と `record_state_snapshot()` の jq 回数**に変わった」と書き換える。閾値の値(50)と警告文は変えない |
| `forbidden_snapshot()` の空振り条件の箇条書き「`.harness/codex-runs/` が溜まるほど対象ファイル数は増えるが…」 | #81 で**偽になった** | この箇条書きを「`.harness/codex-runs/` は対象外(#81)。検収状態は `record_state_snapshot()` が見る」に置き換える |
| `forbidden_snapshot()` 冒頭の「内容ハッシュで比べる理由 1.」の `.harness/mode と .harness/codex-runs/ は .gitignore 済みで…` | `codex-runs` はもう対象外 | `.harness/mode` だけを挙げる形に直し、`codex-runs` は別層である旨を 1 行添える |
| バッチ化のコメント「委託の前後 2 回走り、`.harness/codex-runs/` の件数に線形だったプロセス起動が消える」 | 経緯の説明として**残す**が誤読を生む | 文末に「(このディレクトリ自体は #81 で対象外になった。ここの記述は #65 当時の経緯)」を足す |
| 5-5b の「検査対象外: `.harness/mode` と `.harness/codex-runs/` 配下。…出口検査の内容ハッシュ比較だけが見る層として残る」 | 後半が偽 | 「`.harness/mode` は出口検査の内容ハッシュ比較が、`.harness/codex-runs/` は `record_state_snapshot()` が見る(#81)」に直す |
| 禁止領域違反の stderr メッセージ本文の「(AGENTS.md の verify-probe / .husky/\* / .github/workflows/\* / run record)」 | run record はこの検査の対象外になった | 列挙から `run record` を外す |

### 2-2. `.claude/scripts/codex-run.sh`

#### (a) `require_no_running_impl()` を新設する

`write_field()` の直前に置く。

```bash
# impl 委託が実行中なら書き込み系サブコマンドを拒否する(#81)。
#
# **セキュリティ層ではない。** 委託先はサンドボックス内から同じ書き換えができる
# (それは delegate-codex.sh の出口検査が検出する)。ここで止める理由は信号の純度:
# 出口検査は「BEFORE 時点にあった record の status / accepted が変わっていないか」を
# 見るが、ファイルの内容からは「人間が叩いた accept」と「委託先の書き換え」を
# 区別できない。人間側を実行中だけ止めることで、検査が鳴ったときに本物だと言える。
#
# 判定軸は delegate-codex.sh の入口検査5-5 と同じ(mode=impl / status=running / pid 生存)。
# **ロジックは共有化しない** — スクリプトをまたぐ source を増やすより 20 行の重複のほうが
# 安い(lib-*.sh への切り出しは #86 の範囲)。
#
# 逃げ道: CODEX_RUN_FORCE=1。強行した書き換えは実行中の impl の出口検査で検出され、
# その委託は failed / exit 2 になる。
#
# 空振り条件: jq が無ければ何も判定せず通す(呼び出し元は require_jq を通しているので
# 実際には到達しない)。pid が数字でない record と、プロセスが居ない running 残置 record は
# 実行中とみなさない(5-5 と同じ扱い)。
require_no_running_impl() {
  local _f _pid _rid
  [ "${CODEX_RUN_FORCE:-}" = "1" ] && return 0
  [ -d "$RUN_DIR" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  for _f in "$RUN_DIR"/*.json; do
    [ -f "$_f" ] || continue
    [ "$(rec_field "$_f" mode)" = "impl" ] || continue
    [ "$(rec_field "$_f" status)" = "running" ] || continue
    _pid="$(rec_field "$_f" pid)"
    case "$_pid" in
      '' | *[!0-9]*) continue ;;
    esac
    kill -0 "$_pid" 2>/dev/null || continue
    _rid="$(rec_field "$_f" id)"
    echo "codex-run: impl 委託が実行中です(id=$_rid pid=$_pid)。実行中は record の書き換えを受け付けません。" >&2
    echo "  委託の終了を待ってから再実行してください。実行中の record 書き換えは、その委託の出口検査で「検収状態が書き換えられた」として failed / exit 2 になります(#81)。" >&2
    echo "  どうしても今書き換える場合は CODEX_RUN_FORCE=1 を付けてください(実行中の委託は失敗します)。" >&2
    exit 1
  done
}
```

#### (b) 呼び出しを足す

`cmd_accept` / `cmd_set_status` / `cmd_prune` の **`require_jq` の直後**に `require_no_running_impl` を 1 行足す。読み取り系(`list` / `pending` / `show`)には**足さない**。

#### (c) ヘッダのコメントを更新する

- 使い方一覧の下、終了コードの節に「`1` … 対象が無い・値が不正・**impl 委託の実行中(#81)**」と足す
- 環境変数の説明が無いので、`jq の扱い` の節の後に 2 行足す:
  ```
  # 環境変数:
  #   CODEX_RUN_FORCE=1  impl 委託の実行中でも書き込み系(accept / set-status / prune)を強行する(#81)
  ```
- `usage()` の出力にも `CODEX_RUN_FORCE` の 1 行を足す

### 2-3. `.claude/rules/lead/delegation-policy.md`

「並行数は **1 本まで**(同一ワーキングツリーを共有するため)…」の箇条書きの末尾に 1 文足す(**行を増やさず同じ箇条書きの中に収める**):

> read-only の explore / review はこの検査を通らず並行できる。**並行しても impl の出口検査は誤爆しない**(run record は内容ハッシュ比較の対象外で、既存 record の `accepted` / `status` だけを突き合わせる。#81)。ただし impl の実行中は `codex-run.sh` の書き込み系(`accept` / `set-status` / `prune`)が拒否される。

### 2-4. `docs/template-dev/codex-delegation-plan.md`

- **§12.7 相当(5-5b の段落、`空振り条件:` の文)**: 「`.harness/mode` / `.harness/codex-runs/` は `.gitignore` 済みで git 追跡外のためこの層では見えない」の後ろに「`.harness/codex-runs/` の検収状態は出口検査の `record_state_snapshot()` が別に見る(#81)」を足す
- **§12.8 の冒頭**: 「出口検査の `forbidden_snapshot()` はこのディレクトリ配下を**委託の前後 2 回**ハッシュするため、record 数に比例して委託ごとのコストが増える」を、**#81 で対象外になった**事実に書き換える。代わりに残るコストは `record_state_snapshot()` の jq 呼び出し(record 数に比例)であること、閾値 50 件の警告と手動 prune の 2 層構成は変わらないことを書く

### 2-5. `docs/template-dev/CHANGELOG.md`

先頭の日付節(2026-09-05 が既にあればその中)に `[auto]` エントリを 1 つ足す。既存エントリの書式(太字の見出し + `(#81)` + 何をどう変えたか + 取り込む側の作業があれば `[manual]`)に揃える。含める要点:

- `.harness/codex-runs/` を出口検査の**内容ハッシュ比較から外した**。read-only の explore / review を並行させると、正常に完了した impl が `failed` / `exit 2` になっていた(B1)
- 代わりに **BEFORE 時点に存在した record の `status` / `accepted` だけを突き合わせる出口検査**を足した。守りたい性質(委託先が検収状態を書き換えない)は維持
- `codex-run.sh` の書き込み系(`accept` / `set-status` / `prune`)は **impl 委託の実行中は拒否する**(`CODEX_RUN_FORCE=1` で強行可能)
- `FORBIDDEN_PATHS` の配列は変えていない(`--print-forbidden` の出力・`CLAUDE.md` / `AGENTS.md` の記述は現状のまま)

## 3. やらないこと(スコープガード)

- `FORBIDDEN_PATHS` から `.harness/codex-runs/` を削除しない
- explore / review の並行数を制限しない
- run record の自動削除を入れない
- `RUN_WARN_THRESHOLD` の値(50)と `prune` の既定(`--keep 20`)を変えない
- 5-5 / 5-5b の判定ロジックを共有関数に切り出さない(#86 の範囲)
- `CLAUDE.md` / `AGENTS.md` を編集しない(禁止領域の一覧は変わらないため)

## 4. 既知の落とし穴

- `record_state_snapshot()` の出力が空のとき、`while read <<<""` は 1 回だけ空行を読む。`[ -n "${_rid:-}" ] || continue` を必ず入れる
- `awk -v id="$_rid" '$1 == id'` は文字列比較。record のファイル名(`20260905-143200-48213.json`)に空白は入らない前提で組んである
- `RECSTATE_BEFORE` は `MODE=impl` のときしか代入されない。新しい出口検査ブロックを `if [ "$MODE" = "impl" ]` の中に置くこと(`set -u` の下で未定義参照になる)
- `codex-run.sh` の `require_no_running_impl` を `cmd_list` / `cmd_pending` に付けない。SessionStart hook が `pending` を叩くため、実行中の委託があるとセッションが開けなくなる

## 5. 検証(実装後に必ず回す。結果は `verification.md` に記録する)

すべて `CODEX_DELEGATE_NO_SELF_COPY=1` を付けずに回す(既定経路を見る)。

### V1: 構文と整形

```bash
bash -n .claude/scripts/delegate-codex.sh && bash -n .claude/scripts/codex-run.sh && echo "V1 PASS"
npx prettier --check .steering/20260905-issue81-exit-check-false-positive/*.md .claude/rules/lead/delegation-policy.md docs/template-dev/CHANGELOG.md
```

### V2: 禁止領域の一覧が変わっていないこと

```bash
bash .claude/scripts/delegate-codex.sh --print-forbidden | LC_ALL=C sort -u > /tmp/fp-after.txt
git stash && bash .claude/scripts/delegate-codex.sh --print-forbidden | LC_ALL=C sort -u > /tmp/fp-before.txt && git stash pop
diff /tmp/fp-before.txt /tmp/fp-after.txt && echo "V2 PASS(出力は不変)"
```

`git stash` が使えない状況なら、`.harness/codex-runs/` と `.claude/settings.local.json` を含む 17 行が出ることを目視で確認し、その旨を記録する。

```bash
bash .claude/scripts/check-forbidden-paths-doc.sh && echo "V2b PASS"
```

### V3: `record_state_snapshot()` の単体確認

`delegate-codex.sh` を source せずに関数だけを取り出すのは難しいので、**ダミー record を置いて `codex-run.sh list` 経由で読めることを確認**し、加えて次の 1 行で jq 式そのものを確かめる:

```bash
mkdir -p /tmp/rec-t && printf '{"id":"x","status":"completed","accepted":false}\n' > /tmp/rec-t/x.json
jq -r '[(.status // "MISSING"), (if .accepted == null then "MISSING" else (.accepted | tostring) end)] | join(" ")' /tmp/rec-t/x.json
# → "completed false" が出ること
printf '{"id":"y"}\n' > /tmp/rec-t/y.json
jq -r '[(.status // "MISSING"), (if .accepted == null then "MISSING" else (.accepted | tostring) end)] | join(" ")' /tmp/rec-t/y.json
# → "MISSING MISSING" が出ること
rm -rf /tmp/rec-t
```

### V4: 並行 explore が impl を落とさないこと(B1 の再現テスト)

Codex CLI が使えない環境では `codex exec` を起こせない。その場合は**代替として、出口検査のロジックだけを再現**する:

```bash
# BEFORE 相当(running の並行 run が 1 本ある状態)
B='a.json running false
b.json completed true'
# AFTER 相当(並行 run が completed になり、新しい record が増えた)
A='a.json completed false
b.json completed true
c.json running false'
```

この 2 つを新しい出口検査ブロックと同じ比較規則に通し、**違反 0 件**になることを確認する(規則は design 1-2 の表)。確認方法は実装者に任せるが、**実際に走らせたコマンドと出力を `verification.md` に貼ること**。

### V5: 守りたい性質が消えていないこと

V4 と同じ形で、次の 3 ケースが**それぞれ違反として拾われる**ことを確認する:

| ケース | BEFORE | AFTER | 期待 |
| --- | --- | --- | --- |
| accepted の書き換え | `a.json completed false` | `a.json completed true` | 違反 |
| 完了済み record の status 詐称 | `a.json failed false` | `a.json completed false` | 違反 |
| record の削除 | `a.json completed false` | (行なし) | 違反 |

### V6: `codex-run.sh` の実行中ロック

```bash
# 実行中の impl record を偽装する(自分の pid を使う)
mkdir -p .harness/codex-runs
cat > .harness/codex-runs/v6-test.json <<JSON
{"id":"v6-test","mode":"impl","status":"running","pid":$$,"accepted":false}
JSON
bash .claude/scripts/codex-run.sh accept v6-test; echo "exit=$?"
# → 拒否メッセージ + exit=1
CODEX_RUN_FORCE=1 bash .claude/scripts/codex-run.sh accept v6-test; echo "exit=$?"
# → accepted: v6-test + exit=0
bash .claude/scripts/codex-run.sh pending >/dev/null; echo "pending exit=$?"
# → 0(読み取り系は止めない)
rm -f .harness/codex-runs/v6-test.json
```

**後始末を必ず行う**(`v6-test.json` を消す)。消し忘れると次回委託の 5-5 が pid 再利用で誤検知しうる。

### V7: ガードレールの健全性

```bash
bash .claude/scripts/check-guard-integrity.sh && echo "V7 PASS(無出力・exit 0)"
```
