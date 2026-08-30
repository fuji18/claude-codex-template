<!-- status: ready -->

# 設計: running 残置 record の検出時に禁止領域の git diff を機械確認する

## 0. 変更対象ファイル

| ファイル | 変更内容 |
| --- | --- |
| `.claude/scripts/delegate-codex.sh` | 入口検査5-5 に「残置 record の id を集める」処理を足し、ループ直後に新しい検査ブロック(5-5b)を追加する |
| `docs/template-dev/codex-delegation-plan.md` | §12.7 の再入防止(5-5)の段落を、止める条件と空振り条件を含む記述に差し替える |
| `docs/template-dev/CHANGELOG.md` | `## 2026-08-30` 見出しに項目を追記する(見出しは #45 で既にある。**新しい日付見出しを作らない**) |

`CLAUDE.md` / `AGENTS.md` / `FORBIDDEN_PATHS` の一覧は変更しない(検査対象の定義は増やしていない)。

## 1. 設計判断: dirty のとき「止める」に倒す(根拠)

Issue のスコープ2(a: 警告を強めて続行 / b: `exit` で止める)について **b(止める)** を採る。

- **既存方針との一貫性**: 5-5 は「pid 再利用による誤検知は止める側に倒す」という非対称を既に採っている。同じ検査区画で逆向きの非対称を混ぜない
- **コストの非対称**: 通したコスト = 改ざんの検出機会を**恒久的に**失う。止めたコスト = `codex-run.sh set-status` 1 コマンド。後者が明確に小さい
- **合成条件なので正常系では起きない**: 「running 残置 record がある」かつ「禁止領域が dirty」の同時成立が条件。前者は既に異常事態(強制終了の疑い)である

### 誤爆する条件(承知のうえで受け入れる。文書化して閉じる)

**司令塔が禁止領域を正当に編集している最中(テンプレート自体の改修中など)に、過去の running 残置 record が残っていると止まる。**

- 解除は record を実態に合わせるだけでよく(`bash .claude/scripts/codex-run.sh set-status <id> failed`)、**編集中の差分を捨てる必要はない**。この点をエラーメッセージに明記する
- 残置 record を放置したまま委託を重ねる状態こそが塞ぎたい穴なので、この誤爆は「先に record を始末させる」催促として機能する
- この段落の要旨をスクリプトのコメントと `codex-delegation-plan.md` §12.7 の両方に残す

## 2. `delegate-codex.sh` の変更(逐語)

### 2-1. 残置 id を集める(5-5 のループ)

`if [ -d "$RUN_DIR" ]; then` の**直前**に初期化を 1 行足す:

```bash
  _stale_ids=""
  if [ -d "$RUN_DIR" ]; then
```

ループ末尾の既存 2 行(警告)は**そのまま残し**、その直後に追記する:

```bash
      # プロセスが居ない running = 強制終了の疑い。止めはしないが必ず知らせる。
      echo "delegate-codex: 警告 — 過去の委託 $_rid が status=running のまま残っています(プロセス不在 = 強制終了の可能性)。" >&2
      echo "  回復手順は codex-delegation-plan.md §12.6。tasklist.md と git diff --stat を突き合わせてから続けてください。" >&2
      _stale_ids="${_stale_ids}${_stale_ids:+ }$_rid"
```

### 2-2. 新しい検査ブロック(5-5b)

`if [ -d "$RUN_DIR" ]; then ... fi` を閉じた **直後**、`if [ "$MODE" = "impl" ]` を閉じる `fi` の**手前**に置く。全文を以下のとおり挿入する(コメント含む):

```bash
  # ---- 5-5b: running 残置 record があるとき、禁止領域が dirty なら止める(Issue #46)----
  #
  # 出口検査(禁止領域の内容ハッシュを前後で比べる層)は、SIGINT / SIGTERM で
  # codex exec の途中に死ぬと到達しない。その状態で禁止領域が書き換わっていると、
  # 次回委託の BEFORE スナップショットが改ざん後の内容を「元からあったもの」として
  # 取り込み、以後その改ざんは恒久的に検出できない。status=running のまま残った
  # record がその唯一の手掛かりなので、人間が上の警告を読み飛ばしても効くように
  # 機械検査をここに置く。
  #
  # 止める側に倒す理由: 5-5 が pid 再利用の誤検知を「止める側」に倒している既存方針と
  # 揃える。通したコスト(改ざんの検出機会を恒久的に失う)が、止めたコスト
  # (record を実態に合わせる 1 コマンド)より大きい。
  #
  # 誤爆する条件(承知のうえ): 司令塔が禁止領域を正当に編集している最中に、過去の
  # running 残置 record が残っていると止まる。テンプレート自体の改修中は現実に起きる。
  # 解除は record を実態に合わせるだけでよく、編集中の差分を捨てる必要はない。残置
  # record を放置したまま委託を重ねる状態こそが塞ぎたい穴なので、この誤爆は「先に
  # record を始末させる」催促として機能する。
  #
  # 検査対象外: .harness/mode と .harness/codex-runs/ 配下。どちらも .gitignore 済みで、
  # git diff にも git ls-files --others --exclude-standard にも出ない(git 追跡外)。
  # ここでは見られないため、出口検査の内容ハッシュ比較だけが見る層として残る。
  #
  # 空振り条件: コミットが 1 つも無いリポジトリ(HEAD が無い)と、git 側が失敗した場合は
  # 確認できないため警告だけ出して通す。
  if [ -n "$_stale_ids" ]; then
    _forb_dirty=""
    if git rev-parse --verify -q HEAD >/dev/null 2>&1 &&
      _forb_diff="$(git diff HEAD --name-only -- "${FORBIDDEN_PATHS[@]}" ${PROJECT_FORBIDDEN_PATHS[@]+"${PROJECT_FORBIDDEN_PATHS[@]}"} 2>/dev/null)" &&
      _forb_new="$(git ls-files --others --exclude-standard -- "${FORBIDDEN_PATHS[@]}" ${PROJECT_FORBIDDEN_PATHS[@]+"${PROJECT_FORBIDDEN_PATHS[@]}"} 2>/dev/null)"; then
      _forb_dirty="$(
        printf '%s\n%s\n' "$_forb_diff" "$_forb_new" |
          grep -v '^[[:space:]]*$' | LC_ALL=C sort -u || true
      )"
    else
      echo "delegate-codex: 警告 — 禁止領域の差分を確認できませんでした(コミットがまだ無い、または git が失敗)。出口検査の基準が汚染されていないか手で確認してください。" >&2
    fi
    if [ -n "$_forb_dirty" ]; then
      cat >&2 <<MSG
delegate-codex: 中断された委託(status=running のまま残った record: $_stale_ids)があり、
かつ委託禁止領域に未コミットの変更があります。

この状態で新しい委託を始めると、出口検査の基準(BEFORE スナップショット)がこの変更を
「元からあったもの」として取り込み、以後この変更を検出できなくなります。

  1. 差分を確認する:              git diff HEAD -- <該当パス>
  2. 意図しない変更は破棄する:    git checkout -- <該当パス>
  3. 残置 record を実態に合わせる:
       bash .claude/scripts/codex-run.sh set-status <id> failed

意図した編集(司令塔がハーネス層を改修中など)であれば 3 だけで通ります。差分を捨てる
必要はありません。回復手順の全文は docs/template-dev/codex-delegation-plan.md §12.6。

該当:
MSG
      printf '%s\n' "$_forb_dirty" | sed 's/^/  /' >&2
      exit "$EX_FAIL"
    fi
    unset _forb_dirty _forb_diff _forb_new
  fi
  unset _stale_ids
```

### 2-3. 実装上の注意(推測しないための確定事項)

- **`set -uo pipefail` が有効**(`set -e` は無い)。空配列の展開は `${arr[@]+"${arr[@]}"}` の形を使う(既存 `forbidden_files()` と同じ)。`grep -v` が 0 行になると pipefail で非ゼロになるため `|| true` を必ず付ける
- **`git diff` / `git ls-files` は、存在しないパスや変則的なグロブを pathspec に渡してもエラーにならない**(実測済み)。`PROJECT_FORBIDDEN_PATHS` に `dir/**` 形式や説明用の断片が混ざっていても落ちない
- ヒアドキュメントの区切りは `MSG`(**クォートしない**)。`$_stale_ids` を展開するため。本文に他の `$` やバックティックを入れないこと
- 挿入位置は入口検査5(`if [ "$MODE" = "impl" ]` ブロック)の中。`explore` / `review` はこの区画を通らない(read-only なので従来どおり並行できる)
- 検査対象パスは `FORBIDDEN_PATHS` と `PROJECT_FORBIDDEN_PATHS` を**そのまま参照する**。配列を複製しない(単一ソースを崩さない)
- `bash -n .claude/scripts/delegate-codex.sh` と `shellcheck`(あれば)を通す

## 3. `codex-delegation-plan.md` §12.7 の更新

§12.7 末尾の「再入防止(5-5)では、…」で始まる段落の**最後の一文の前**(read-only の explore / review に関する記述の前)に、以下の趣旨を 2〜3 文で追記する:

- `status=running` のまま残った record を検出したときは、警告に加えて**禁止領域が dirty でないかを機械確認する**(`git diff HEAD` + `git ls-files --others --exclude-standard`)。dirty なら `exit 2` で止める
- 止める理由は、中断で出口検査に到達しなかった委託の改ざんが、次回委託の BEFORE スナップショットに取り込まれて恒久的に検出不能になるため
- **誤爆**: 司令塔が禁止領域を正当に編集している最中は止まる。`codex-run.sh set-status <id> failed` で残置 record を始末すれば通る(差分を捨てる必要はない)
- **空振り条件**: `.harness/mode` / `.harness/codex-runs/` は `.gitignore` 済みで git 追跡外のためこの層では見えない。コミットが 1 つも無いリポジトリでも確認できない

§12.7 の表(入口検査の一覧)には行を足さない。5-5 の枠内の強化であり、新しい終了コードも増えていない。

## 4. `CHANGELOG.md` の追記

既存の `## 2026-08-30` 見出しの直下(#45 の段落の**上**)に、以下の形で追記する。**新しい日付見出しを作らない**(同日のため)。

- 導入文 1 段落: 中断された委託が残す穴(BEFORE スナップショットの汚染)と、これまで警告しかなかったこと
- **[auto]** の項目 1〜2 行: 入口検査5-5 が残置 record を見つけたとき、禁止領域が dirty なら `exit 2` で止めるようになった。**誤爆条件**(ハーネス層を改修中に残置 record があると止まる)と解除方法(`codex-run.sh set-status <id> failed`)を必ず書く
- 取り込む側の追加作業は無いので `[manual]` にはしない

## 5. 実測(受け入れ条件1・2 の確認手順)

**実際の Codex 枠を消費しないこと。** `codex` のスタブを PATH の先頭に置いて確認する。

### 5-0. 準備(スタブと使い捨てステアリング)

```bash
TMP="$(mktemp -d)"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/codex" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$TMP/bin/codex"

mkdir -p .steering/29991231-issue46-probe
printf '<!-- status: ready -->\n\n# probe\n' > .steering/29991231-issue46-probe/design.md
printf -- '- [ ] probe\n' > .steering/29991231-issue46-probe/tasklist.md
```

残置 record(`status=running` かつ**存在しない pid**)を置く。pid は `for p in $(seq 30000 32000); do kill -0 $p 2>/dev/null || { echo $p; break; }; done` で空いている番号を 1 つ選ぶ:

```bash
cat > .harness/codex-runs/issue46-probe.json <<JSON
{
  "id": "issue46-probe",
  "mode": "impl",
  "target": ".steering/29991231-issue46-probe/",
  "steering": ".steering/29991231-issue46-probe/",
  "pid": <空いている pid>,
  "status": "running",
  "accepted": false
}
JSON
```

### 5-1. clean のとき警告のみ(受け入れ条件2)

**実装の変更をコミットしてから**行う(`delegate-codex.sh` 自身が禁止領域なので、未コミットのままでは必ず dirty 判定になる)。

```bash
git status --porcelain -- .claude .husky .github AGENTS.md   # 空であることを確認
PATH="$TMP/bin:$PATH" bash .claude/scripts/delegate-codex.sh impl .steering/29991231-issue46-probe/; echo "exit=$?"
```

**期待**: 「status=running のまま残っています」の警告が出て**先へ進む**(5-5b では止まらない)。その先はスタブが何もしないため成果の実在確認で `exit 2` になるが、これは別の検査であり期待どおり。標準エラーに「委託禁止領域に未コミットの変更があります」が**出ないこと**を確認する。

### 5-2. dirty のとき止まる(受け入れ条件1)

```bash
printf '\n' >> .claude/scripts/check-protected-branch.sh    # 禁止領域を dirty にする
PATH="$TMP/bin:$PATH" bash .claude/scripts/delegate-codex.sh impl .steering/29991231-issue46-probe/; echo "exit=$?"
git checkout -- .claude/scripts/check-protected-branch.sh   # 必ず戻す
```

**期待**: `exit=2`。メッセージに残置 record の id・該当パス(`.claude/scripts/check-protected-branch.sh`)・`set-status` の回復手順が出る。**`codex` スタブが呼ばれる前に止まる**こと(5-1 と違い run record が新規に作られない)。

### 5-3. 後片付け(必ず行う)

```bash
rm -f .harness/codex-runs/issue46-probe.json
rm -rf .steering/29991231-issue46-probe "$TMP"
# 5-1 で作られたテスト用 run record(id が日付-pid 形式のもの)も削除する
git status --porcelain   # 意図した変更だけが残っていることを確認
```

`.harness/codex-runs/` と使い捨てステアリングは**コミットしない**。実測の結果(出力の要点)は `tasklist.md` の該当項目に 1 行で残す。

---

## 6. 改訂(検収 1 巡目の指摘反映 / 2026-08-30)

code-reviewer の Critical 1・Major 1・Minor 1 を採用する。**採用理由と実測**は司令塔が確認済み。

### 6-1. 指摘の要点(実測で再現)

`FORBIDDEN_PATHS` / `PROJECT_FORBIDDEN_PATHS` の要素を**そのまま** pathspec に渡していると、以下が起きる。

- **Critical(無音のフェイルオープン)**: `PROJECT_FORBIDDEN_PATHS` は `AGENTS.md` のバックティック断片を無検証で抽出したもの。git の **magic pathspec**(`:(exclude)...` / `:!...`)が紛れ込むと、他の一致結果ごと除外される。実測:

  ```
  git diff HEAD --name-only -- ".claude/scripts/" ":(exclude).claude/scripts/delegate-codex.sh"
  → 出力なし(実際は delegate-codex.sh が dirty)
  ```

  中断した委託が `AGENTS.md` に断片を仕込んでから死ぬと、**次回起動でこの検査自身が無効化される**。塞ごうとしている穴を検査が再現してしまう。既存コメント(`:269-271`)の「実在しない断片は `forbidden_files()` の実在検査で落ちるので無害」という前提は、**実在検査を経由しない新しい消費者**である 5-5b には効かない。
- **Major(出口検査との乖離)**: `forbidden_files()` は `case` で `*/**` / `*/*` / 末尾 `/` だけをディレクトリ扱いし、それ以外はリテラルの実在検査に落とす。5-5b は git 側の glob 解釈が効くため、あちらが無視する変則グロブ(`src/**/*.ts` 等)で**保護対象でないファイルを誤ってブロック**しうる。

### 6-2. 対処(2 段構え)

**採用しなかった案**: `forbidden_files()` の再利用。あの関数は `$REC` / `$LOG` / `$LAST`(run record 節でしか定義されない)を参照するため、5-5b の位置では `set -u` で落ちる。関数を分割してまで共有するのは、この層が見るのが「git 追跡ファイルだけ」で対象が元々狭いことに見合わない。

1. **pathspec を正規化してから渡す**(`forbidden_files()` と同じ case 規則に揃える)
2. **git 側でも magic / glob 解釈を止める**(`GIT_LITERAL_PATHSPECS=1`)。literal でもディレクトリ指定は配下すべてに一致することを実測済み(`.claude/scripts/` / `.claude/scripts` の両形で確認)

多層にするのは、片方だけだと「環境変数が効かない git 実装」「`:` 以外の magic 記法の追加」のどちらかで再び無音になるため。

### 6-3. 差し替える実装(§2-2 のブロック内)

`if [ -n "$_stale_ids" ]; then` の直後に正規化を足す:

```bash
    # pathspec は正規化してから渡す(#46 検収指摘)。PROJECT_FORBIDDEN_PATHS は AGENTS.md の
    # バックティック断片を無検証で抽出したものなので、git の magic pathspec(`:(exclude)...`)
    # が紛れ込みうる。混ざると他の一致結果ごと除外され、この検査が exit 0 のまま無音で
    # 空振りする(実測)。中断した委託が AGENTS.md に断片を仕込んでから死ねば、次回起動で
    # この検査自身が無効化される — 塞ごうとしている穴を検査が再現してしまう。
    # 末尾グロブの畳み方は forbidden_files() の case と同じ規則に揃える。揃えないと、
    # 出口検査が無視する変則グロブ(src/**/*.ts 等)を git が解釈し、保護対象でない
    # ファイルで誤ってブロックする。
    _forb_specs=()
    for _p in "${FORBIDDEN_PATHS[@]}" ${PROJECT_FORBIDDEN_PATHS[@]+"${PROJECT_FORBIDDEN_PATHS[@]}"}; do
      case "$_p" in
        :*) continue ;;
        */\*\* | */\*) _forb_specs+=("${_p%/*}") ;;
        *) _forb_specs+=("$_p") ;;
      esac
    done
    unset _p
```

git 呼び出しは `GIT_LITERAL_PATHSPECS=1` を付け、正規化後の配列を渡す形に差し替える。**配列が空になった場合は git を呼ばない**(pathspec 無しの `git diff` はリポジトリ全体に一致し、過剰ブロックになるため):

```bash
    if [ "${#_forb_specs[@]}" -gt 0 ] &&
      git rev-parse --verify -q HEAD >/dev/null 2>&1 &&
      _forb_diff="$(GIT_LITERAL_PATHSPECS=1 git diff HEAD --name-only -- "${_forb_specs[@]}" 2>/dev/null)" &&
      _forb_new="$(GIT_LITERAL_PATHSPECS=1 git ls-files --others --exclude-standard -- "${_forb_specs[@]}" 2>/dev/null)"; then
```

`else` 側の警告文は「(コミットがまだ無い、または git が失敗)」を **「(検査対象パスが空、コミットがまだ無い、または git が失敗)」** に直す。ブロック末尾の `unset` に `_forb_specs` を足す。

**空振り条件のコメント**(§2-2 の「空振り条件:」)にも 1 行足す: `PROJECT_FORBIDDEN_PATHS` に `:` で始まる断片が入っていた場合は**その要素を捨てる**(検査対象から外れるが、他の要素の検査は働く)。

### 6-4. ドキュメントの追記(Minor 対応)

- `codex-delegation-plan.md` §12.7 の 5-5b の文の**空振り条件**に、「`AGENTS.md` 由来のプロジェクト固有パスは git pathspec としてそのまま解釈されるため、magic pathspec(`:` 始まり)は取り込まず、`GIT_LITERAL_PATHSPECS=1` で glob 解釈も止めている」旨を 1 文足す
- `CHANGELOG.md` の `[auto]` 項目に、同趣旨を 1 文足す(取り込む側の作業は増えないので `[manual]` にしない)

### 6-5. 追加の実測(受け入れ条件に上乗せ)

§5 の 5-1 / 5-2 に加えて、**magic pathspec を混ぜても dirty を検出できること**を確認する。`AGENTS.md` を書き換えずに確認するため、5-5b の pathspec 構築と同じ形をシェルで再現する形でよい:

```bash
# 期待: delegate-codex.sh が出力される(magic が無視される)
GIT_LITERAL_PATHSPECS=1 git diff HEAD --name-only -- ".claude/scripts/" ":(exclude).claude/scripts/delegate-codex.sh"
```

`AGENTS.md` のマーカー内に一時的に `` `:(exclude).claude/scripts/delegate-codex.sh` `` を足して 5-2 の手順を再実行し、**それでも exit 2 で止まる**ことまで確認できるならそちらを優先する(**確認後は `git checkout -- AGENTS.md` で必ず戻す**)。結果は `tasklist.md` に 1 行で残す。
