# 設計: rec_field() の二重実装を共有ファイルに集約する

<!-- status: ready -->

変更対象は **4 ファイル**:

| ファイル | 変更 |
| --- | --- |
| `.claude/scripts/lib-record.sh` | **新規**(source 専用。実行ビットは付けない) |
| `.claude/scripts/delegate-codex.sh` | 3 箇所(自己コピーブロック / source ブロックの挿入 / 旧 `rec_field` 削除) |
| `.claude/scripts/codex-run.sh` | 1 箇所(旧 `rec_field` を source に置換) |
| `docs/template-dev/CHANGELOG.md` | 追記 1 本 |

`.claude/scripts/check-guard-integrity.sh` は **変更しない**(理由は §5)。
`.claude/settings.json` / `AGENTS.md` / `CLAUDE.md` も変更しない(理由は §5)。

## 0. 計画時に確定させた事実(実装者は再調査しなくてよい)

- `delegate-codex.sh` の行構成: 自己コピー exec ブロック = 37〜83 行、`EX_*` 定数 = 85〜89 行、
  `ROOT=` / `cd "$ROOT"` = 91〜96 行、`# ---------- 引数 ----------` = 98 行、
  入口検査0〜4 = 153〜607 行、旧 `rec_field` = 642〜661 行、入口検査5-5(`rec_field` の利用) = 769 行〜
- **`ROOT` と `EX_FAIL` は入口検査より前(91 行 / 86 行)で確定している。** よって source は
  入口検査より前に置ける。ここが設計の要(§3-2)
- `FORBIDDEN_PATHS` は `.claude/scripts/` を**ディレクトリ単位**で持つ(#40)。
  `check-guard-integrity.sh` は禁止領域を `delegate-codex.sh --print-forbidden` から受け取り、
  配列を複製していない(実測: `check-guard-integrity.sh:171`)
- `codex-run.sh` は `ROOT=$(git rev-parse --show-toplevel)` の後 `cd "$ROOT"` する(22〜27 行)。
  自己コピー exec は**持たない**
- この環境には jq(`/usr/bin/jq`)と codex CLI(`codex-cli 0.149.0`)がある
- 入口検査1 は `./.claude/settings.local.json` を機密候補として検出する。
  `delegate-codex.sh` を実際に走らせる検証には `CODEX_DELEGATE_ACK_SECRETS=1` が要る
  (この検証は **§7 の必須項目には入れていない**。必須項目は ack 不要な経路だけで組んである)

## 1. 方針: 「共有ファイルも自己コピーに一緒に運ぶ」

`delegate-codex.sh` は起動直後に自身を `mktemp -d` のディレクトリへコピーして exec する(#15)。
狙いは「委託先が実行中にハーネス層を書き換えても、走っているプロセスが読むのはコピーだから壊れない」。
共有ファイルを `$ROOT/.claude/scripts/lib-record.sh` から素朴に `source` すると、
**この保護に穴が開く**(実行中に委託先が書き換えられるファイルが 1 本増える)。

採る対策は **「コピー先へ lib-record.sh も一緒に運び、自身の隣から source する」**。

| 案 | 判断 |
| --- | --- |
| **A: コピー先へ一緒に運び、自身の隣から source する** | **採用。** 自己コピーの保護範囲がそのまま共有ファイルに及ぶ。追加するのは `cp` 1 行と解決順 1 ブロック |
| B: コピー時に本文を埋め込む(生成) | 却下。コピー処理が「ファイルを運ぶ」から「スクリプトを合成する」に変わり、失敗モードが増える。得るものは A と同じ |
| C: 実行前にハッシュを取って事後照合する | 却下。**検知しかできない**(壊れた実行そのものは止まらない)。A は発生自体を防ぐ |
| D: 何もせず `$ROOT` から source する | 却下。#15 の保護に穴を開ける。この穴は「委託先がハーネス層を触る」テンプレート開発では常態 |

**解決順は「自身の隣 → `$ROOT`」の 2 段**にする。自己コピーが無効(`CODEX_DELEGATE_NO_SELF_COPY=1`)、
または `mktemp`/`cp` に失敗した経路でもスクリプトが動く必要があるため。

**フェイルの向きは 2 箇所で違える。混ぜないこと。**

- **コピーの失敗はフェイルオープン**(委託を止めない)。自己コピーは堅牢化の層であって安全検査ではない、
  という既存の判断(37〜57 行のコメント)と揃える。ただし `$ROOT` にフォールバックしたことは**警告に出す**
- **共有ファイルが 1 つも見つからない場合はフェイルクローズ**(`exit "$EX_FAIL"`)。`rec_field` は
  入口検査5-5(impl の再入防止)が使う。未定義のまま進めば `rec_field: command not found` で
  空文字列が返り、**再入防止が静かに素通しする** = このチケットが集約しようとしている
  「jq 不在時のフェイルオープン」と同じ穴が別の形で開く

## 2. 新規: `.claude/scripts/lib-record.sh`(全文)

実行ビットは付けない(`chmod +x` しない)。source 専用で、単体起動しても意味がないため。

```bash
# shellcheck shell=bash
# run record(.harness/codex-runs/*.json)を読むための共有関数。
#
# **source 専用。** 実行ビットは付けない(関数定義しか無い)。
# 利用側: .claude/scripts/delegate-codex.sh / .claude/scripts/codex-run.sh
#
# 委託禁止領域に入るか: 入る。FORBIDDEN_PATHS の ".claude/scripts/" がディレクトリ単位
# なので(#40)、このファイルは追加作業なしで出口検査・縮退検査の対象になる。
#
# 実行中の書き換えハザード: delegate-codex.sh は起動直後に自身を一時ディレクトリへ
# コピーして exec する(#15)。このファイルも同じ一時ディレクトリへ一緒にコピーされ、
# コピー側から source される。委託中に元ファイルが書き換わっても、走っている
# プロセスが読む rec_field は変わらない(design §1)。

# $1=json ファイル $2=キー名。無い/null は空文字列を返す。
#
# sed 経路は run record が「1 行 1 キー・値が 1 行に収まる」形式であることに依存する。
# #29 の検収で Minor として挙がったが、この形式で record を書いているのは
# delegate-codex.sh だけなので、既存の性質として受け入れている。
#
# sed フォールバックの既知の癖(検収で実測): クォートされていない値(pid / accepted など)
# では `[^"]*` が末尾のカンマまで飲み込む。"pid": 82711, → 82711, が返り、
# kill -0 "82711," が引数エラーで必ず失敗する = 再入防止(入口検査5-5)が jq 不在環境で
# 静かにフェイルオープンしていた。捕獲後に末尾のカンマと空白を必ず剥がす。
# クォートされた値は `[^"]*` が閉じ引用符で止まるためもともと影響を受けない。
rec_field() {
  local _out=""
  if command -v jq >/dev/null 2>&1; then
    # `// empty` は使わない。jq の // は false も falsy として捨てるため、
    # "accepted": false が「キーが無い」と区別できなくなり、sed 経路と
    # 結果が食い違う(実測)。null のときだけ空を返す形にする。
    _out="$(jq -r --arg k "$2" '.[$k] | if . == null then empty else . end' "$1" 2>/dev/null)"
  else
    _out="$(sed -n "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\},\{0,1\}[[:space:]]*$/\1/p" "$1" | head -1)"
    _out="${_out%"${_out##*[![:space:]]}"}"
    _out="${_out%,}"
    _out="${_out%"${_out##*[![:space:]]}"}"
  fi
  [ "$_out" = "null" ] && _out=""
  printf '%s' "$_out"
}
```

**関数本体は現行 2 実装と 1 文字も変えない。** 今回は集約だけで、挙動の変更は入れない。

## 3. `.claude/scripts/delegate-codex.sh` の変更(3 箇所)

### 3-1. 自己コピーブロックに「共有ファイルも運ぶ」を足す

`cp "$_self" "$_copy_dir/delegate-codex.sh" 2>/dev/null; then` の**直後の行**(`export CODEX_DELEGATE_SELF_COPY="$_copy_dir"` の直前)に挿入する:

```bash
    # source する共有ファイル(lib-record.sh)も一緒に運ぶ。運ばないと、コピーを exec
    # しているのに実行中に読むファイルがリポジトリ側に残り、自己編集ハザード対策に
    # 穴が開く(委託先が実行中に書き換えられる)。
    # **ここはフェイルオープン**: 失敗しても委託は止めない。下の解決順が $ROOT へ
    # フォールバックし、警告を出す(design §1)。
    _self_dir="$(cd "$(dirname "$_self")" 2>/dev/null && pwd || true)"
    [ -n "$_self_dir" ] && cp "$_self_dir/lib-record.sh" "$_copy_dir/lib-record.sh" 2>/dev/null
```

あわせて、ブロック冒頭(41〜44 行あたり)の説明に 1 文足す。
「そちらを exec して走る。」の直後に続ける形で:

```
# 共有ファイル(lib-record.sh)も同じディレクトリへ一緒にコピーし、コピー側から source する。
```

### 3-2. source ブロックを挿入する(位置が重要)

`cd "$ROOT" || exit "$EX_FAIL"`(96 行)の**直後**、`# ---------- 引数 ----------`(98 行)の**直前**に挿入する。

**この位置にする理由**:

- `ROOT` と `EX_FAIL` が既に確定している(フォールバック先とフェイルクローズの終了コードに要る)
- **入口検査0〜4 より前**に置くことで、`--print-forbidden` を含む**すべての起動経路**が
  この解決を通る。旧 `rec_field` の位置(642 行 = 入口検査4 の後)に置くと、codex CLI が
  無い環境では解決が一度も走らず、**壊れていても気づけない**。検証も §7 のとおり ack 不要で済む
- source は関数を定義するだけで副作用がない。入口検査より前に置いて困らない

```bash
# ---------- run record 読み出しの共有関数 ----------
#
# rec_field() は codex-run.sh と共有する(#45)。過去に sed フォールバックの同じバグ
# (末尾カンマ)を 2 箇所で直した実績があり、複製を続けるコストの方が高いと判断した。
#
# **解決順は「自身の隣 → リポジトリ」**:
#   1) 自己コピー先の一時ディレクトリ(上のブロックが lib-record.sh も一緒に運ぶ)
#   2) $ROOT/.claude/scripts/(自己コピーが無効・失敗した経路のフォールバック)
# 1 を優先するのは、リポジトリ側から source すると「コピーを exec して自己編集から
# 守る」設計に穴が開くため(委託先が実行中に書き換えられる)。
#
# **見つからなければ止める(フェイルクローズ)。** rec_field は入口検査5-5(impl の
# 再入防止)が使う。未定義のまま進むと空文字列が返って検査が素通しするだけで、
# 失敗として現れない(design §1)。
_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
LIB_RECORD=""
for _cand in "${_lib_dir:+$_lib_dir/lib-record.sh}" "$ROOT/.claude/scripts/lib-record.sh"; do
  [ -n "$_cand" ] && [ -f "$_cand" ] && {
    LIB_RECORD="$_cand"
    break
  }
done
if [ -z "$LIB_RECORD" ]; then
  echo "delegate-codex: .claude/scripts/lib-record.sh が見つかりません(run record を読めないため中止します)。" >&2
  exit "$EX_FAIL"
fi
# shellcheck source=lib-record.sh
. "$LIB_RECORD"
if [ -n "${SELF_COPY_DIR:-}" ] && [ "$LIB_RECORD" != "$SELF_COPY_DIR/lib-record.sh" ]; then
  echo "delegate-codex: 警告 — lib-record.sh の一時コピーを使えていません。委託中にこのファイルが書き換わると異常終了します。" >&2
fi
unset _lib_dir _cand
```

`SELF_COPY_DIR` は 77 行で設定済み(自己コピーが効いているときのみ非空)。
**この警告が出ない = コピー側から読めている**、が §7 の観測点になる。

### 3-3. 旧 `rec_field` を削除する

642〜661 行(コメント `# $1=json ファイル $2=キー名。…` から関数の閉じ `}` まで)を**丸ごと削除**する。
直前の `json_or_null()` と直後の `# ---------- 入口検査5: impl 専用 ----------` の間は空行 1 つにする。

削除するコメントの内容(sed の末尾カンマの癖・`// empty` を使わない理由)は
§2 の `lib-record.sh` に移してあるので、失われない。

## 4. `.claude/scripts/codex-run.sh` の変更(1 箇所)

50〜68 行(コメント 2 行 + `rec_field()` 定義)を次で置換する:

```bash
# run record のフィールド読み出し(rec_field)は delegate-codex.sh と共有する(#45)。
# こちらは自己コピー exec を持たないので、リポジトリ内のパスをそのまま読む。
LIB_RECORD="$ROOT/.claude/scripts/lib-record.sh"
if [ ! -f "$LIB_RECORD" ]; then
  echo "codex-run: $LIB_RECORD が見つかりません(run record を読めないため中止します)。" >&2
  exit 2
fi
# shellcheck source=lib-record.sh
. "$LIB_RECORD"
```

終了コード 2 は `codex-run.sh` 固有の契約(「使い方の誤り」)。
`delegate-codex.sh` の `EX_FAIL` とは別系統なので、値を揃えようとしないこと。

## 5. 変更しないファイルと、その判断

| ファイル | 判断 |
| --- | --- |
| `.claude/scripts/check-guard-integrity.sh` | **変更不要。** 禁止領域は `delegate-codex.sh --print-forbidden` から受け取っており(`:171`)、`FORBIDDEN_PATHS` は `.claude/scripts/` を**ディレクトリ単位**で持つ(#40)。`lib-record.sh` は**追加作業なしで**出口検査・縮退時の差分検査の対象になる。個別に足すと #40 が畳んだ「ファイルが増えるたびに列挙が漏れる」問題を再導入する |
| `.claude/settings.json` | 変更不要。hook 登録は増えない(`lib-record.sh` は単体で起動しない) |
| `AGENTS.md` / `CLAUDE.md` の禁止領域リスト | 変更不要。どちらも `.claude/scripts/` をディレクトリ単位で列挙済み |
| `.gitignore` | 変更不要 |

**副次的な効果を 1 つ意識しておくこと**: §3-2 の位置に置いたことで、`lib-record.sh` が消えると
`--print-forbidden` が空を返す → `check-guard-integrity.sh` が
「`--print-forbidden` が委託禁止領域を返さない」と鳴る。**フェイルクローズが検知層まで貫通する**
望ましい向きであり、意図した挙動。

## 6. 既知の jq / sed 出力差(**直さない**。スコープ外)

計画時の実測で、`codex-run.sh pending` の**サマリー行だけ** jq 経路と sed 経路で差が出ることを確認した:

```
jq  : … 出口検査): .claude/settings.json  完了: tasklist 1/1 / …
sed : … 出口検査): .claude/settings.json\n\n完了: tasklist 1/1 / …
```

`jq -r` は JSON 文字列中の `\n` を実際の改行に戻すが、sed 経路は生の 2 文字 `\n` を返す。
**これは今回の変更で入るものではなく、現行の 2 実装が最初から持っている差**(実装をそのまま
移すので、変更前後で同じ差が同じように出る)。

- **直さない。** run record の書式に手を入れる話になり、Issue の「スコープ外」に当たる
- **したがって §7 の等価性検査は「jq 経路 vs sed 経路」で比べてはいけない。**
  **変更前の同じ経路の出力**と比べること(比較用の基準出力は §7 に置いてある)

## 7. 検証(実装者はここを全部実際に走らせ、結果を控える)

### 7-0. 変更前の基準出力(計画時に取得済み。取り直さなくてよい)

```
/tmp/claude-1000/-workspaces-claude-codex-template/7ca5640f-c183-4704-9c77-604b09d7bc2f/scratchpad/baseline/
  list-jq.txt      (16 行)  codex-run.sh list --all      jq あり
  list-nojq.txt    (16 行)  codex-run.sh list --all      jq なし
  pending-jq.txt   (29 行)  codex-run.sh pending         jq あり
  pending-nojq.txt (29 行)  codex-run.sh pending         jq なし
```

**このディレクトリが消えている場合は、`git stash` で変更を退避して取り直してから戻すこと。**

### 7-1. jq を外す方法(この環境で実測済み)

`/usr/bin/jq` は他の必須コマンドと同じディレクトリにあるため、PATH からは外せない。
`command` を関数で覆って `export -f` する。**子スクリプトにも継承されることを実測で確認済み**:

```bash
nojq() {
  bash -c 'command() { if [ "$1" = -v ] && [ "$2" = jq ]; then return 1; fi; builtin command "$@"; }
           export -f command
           "$@"' _ "$@"
}
```

### 7-2. 必須の検証項目

- [ ] **構文**: `bash -n` が 3 ファイルすべてで通る
      (`lib-record.sh` / `delegate-codex.sh` / `codex-run.sh`)
- [ ] **実行ビット**: `lib-record.sh` に実行ビットが**付いていない**(`ls -l`)
- [ ] **rec_field 単体 / jq あり**: 任意の record に対し `id` `mode` `status` `accepted` `pid` を読み、
      末尾カンマ・前後空白が残らないこと
      (`bash -c '. .claude/scripts/lib-record.sh; rec_field <record.json> pid'`)
- [ ] **rec_field 単体 / jq なし**: 同じ入力を `nojq` 経由で読み、**pid に `,` が付かない**こと
      (これが過去の Critical の回帰点)
- [ ] **存在しないキー**: jq あり / なし どちらも空文字列を返す
- [ ] **`accepted: false` が空にならない**: `false` を返す(jq あり / なし 両方)。
      該当 record が無ければ一時ファイルを作って確認し、**確認後に消す**
- [ ] **codex-run.sh の等価性(4 通り)**: `list --all` / `pending` × jq あり / なし の出力が
      §7-0 の対応する基準ファイルと **`diff` で完全一致**すること
      (`pending` の jq/sed 差は §6 のとおり基準側にも入っているので、同経路同士なら一致する)
- [ ] **自己コピー経路で共有ファイルが解決される**: `bash .claude/scripts/delegate-codex.sh --print-forbidden`
      が禁止領域 10 行を出し、**stderr に「lib-record.sh の一時コピーを使えていません」警告が出ない**こと。
      警告が出なければ、コピー側から source できている(§3-2)
- [ ] **自己コピー無効でも動く**: `CODEX_DELEGATE_NO_SELF_COPY=1 bash .claude/scripts/delegate-codex.sh --print-forbidden`
      が同じ 10 行を出すこと(自己コピー無効の警告 1 行は出てよい)
- [ ] **フェイルクローズ**: `lib-record.sh` を一時的に退避(`mv`)した状態で
      `bash .claude/scripts/delegate-codex.sh --print-forbidden` が **exit 2** で
      「見つかりません」と出ること、`.claude/scripts/codex-run.sh list` が **exit 2** で
      同様に止まること。**確認後に必ず元へ戻す**
- [ ] **検知層まで貫通する**: 上の退避状態のまま `bash .claude/scripts/check-guard-integrity.sh` が
      「`--print-forbidden` が委託禁止領域を返さない」を出すこと(§5 の副次効果の確認)。
      **確認後に必ず元へ戻し、`check-guard-integrity.sh` が無出力に戻ることを確認する**
- [ ] **後始末**: `git status --short` に想定外の差分・一時ファイルが無い

### 7-3. 任意(できれば実施。できなければ報告に「未実施」と書く)

- [ ] **入口検査5-5 の実経路**: `CODEX_DELEGATE_ACK_SECRETS=1` を付けた impl 委託で
      再入防止が従来どおり働くこと。**この検証は `.claude/settings.local.json` の機密承認が要る**ため、
      環境の制約で実行できなければスキップしてよい(7-2 の単体検査で `rec_field` の
      振る舞いは押さえてある)。**実施する場合も、承認して実際に委託を走らせないこと**

## 8. CHANGELOG 追記(文面はこのとおり)

`docs/template-dev/CHANGELOG.md` の `---` の直後に、**新しい日付見出し `## 2026-08-30` を作って**
先頭(既存の `## 2026-08-29` より上)に置く:

```markdown
## 2026-08-30

**run record を読む `rec_field()` の二重実装を共有ファイルに集約した(Issue #45)。** `delegate-codex.sh` と `codex-run.sh` に同じ十数行がコピーされており、jq 不在環境で再入防止がフェイルオープンする Critical(sed フォールバックの末尾カンマ)を**両方で直した実績**がありました。同じバグを 2 回直した時点で「小さいから複製の方が安い」という前提は崩れています。

- **[auto]** `.claude/scripts/lib-record.sh` を新規追加し、両スクリプトが `source` するようにした(#45)。関数の挙動は変えていないので、`/sync-template` の上書きだけで完結します
- **[auto]** `delegate-codex.sh` の自己コピー exec(#15)は、`lib-record.sh` も同じ一時ディレクトリへ**一緒にコピー**して自身の隣から `source` するようにした。共有ファイルをリポジトリ側から読むと「実行中に委託先が書き換えられるファイル」が増え、自己編集ハザード対策に穴が開くためです。コピーに失敗した場合はリポジトリ側へフォールバックし、警告を出します(委託は止めません)
- **[auto]** 共有ファイルが 1 つも見つからない場合は**フェイルクローズ**(`delegate-codex.sh` は `exit 2`、`codex-run.sh` は `exit 2`)。`rec_field` は入口検査5-5 の再入防止が使うため、未定義のまま進むと検査が静かに素通しします
- `lib-record.sh` は `FORBIDDEN_PATHS` の `.claude/scripts/`(ディレクトリ単位・#40)に**自動的に含まれる**ため、委託禁止領域の一覧・`AGENTS.md` §4・`CLAUDE.md` の更新は不要です
```

## 9. 実装者への申し送り

- **設計判断は残っていない。** §2〜§4 のコードをそのまま入れ、§7 を全部走らせること
- **関数本体を「ついでに」改善しない。** sed 経路の癖(§6)も含めて現状のまま移す。
  改善は挙動変更であり、このチケットのスコープ外
- 迷ったら止めて報告する。`.claude/scripts/` はハーネスの中枢で、静かな劣化が最も高くつく場所
