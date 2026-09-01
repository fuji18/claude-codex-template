# 設計: モード C 復帰検査に `.git/config` の実行ベクタ検査(D2.5)を追加する(Issue #58)

<!-- status: ready -->

実装者は設計判断をしない。本ファイルに書かれた内容を、指定のファイルに指定の形で反映するだけでよい。
§0 の判断はすべて**司令塔が実測で確定済み**。再検討しないこと。

---

## §0. 設計判断(確定済み。実装者は判断しない)

### 判断1: 倒し方は「報告のみ」。停止しない

`note` で出力して `FOUND=1` にするだけ。既存の D1/D2/D3 とまったく同じ倒し方に揃える。
Issue のスコープ 1 に「報告のみか停止かは設計判断」とあるが、**報告のみで確定**。理由:

- D2.5 の対象キーには**正当な用途がある**(`core.pager` を好みで設定する開発者は普通にいる)。
  停止にすると、縮退と無関係な平常運用が止まる
- この検査は**セキュリティ境界ではない**(要件のスコープ外に明記)。検出して人間に判断させるのが役割

### 判断2: 検査範囲は `--local` のみ。`--global` / `--system` は見ない

Issue のスコープ外に合致するが、**それ以上に実測上の必然**がある。この devcontainer の実測値:

```
--global: credential.helper=!f() { ... vscode-remote-containers-*.js git-credential-helper $*; }; f
--system: credential.helper=!f() { ... }(同上)
--local : core.hookspath=.husky/_ ほか。危険キーは 1 つも無い
```

つまり **devcontainer は既定で `credential.helper` の `!` 形式(shell 実行)を global/system に置いている**。
グローバルを混ぜた瞬間、平常の devcontainer で必ず誤爆する = 受け入れ条件 2 を満たせない。
`--local` に限定すれば誤爆しない(実測で確認済み)。縮退中の Codex が書けるのもローカルだけ。

### 判断3: 「既知の安全な値の除外リスト」は作らない。**値ごと報告して人間に判定させる**

Issue のスコープ 2 の指示どおり。除外リストは、値を少し変えるだけで回避できるうえ、
`--local` 限定なら誤爆源が実測で存在しないため、そもそも要らない。

### 判断4: 対象キーは以下で確定(増減しない)

| キー(git が返す正規化後の形) | 報告理由(出力に載せる文言) |
| --- | --- |
| `core.fsmonitor` | `git status 等のたびに実行される` |
| `core.sshcommand` | `push / fetch のたびに実行される` |
| `core.pager` | `log / diff 等のたびに実行される` |
| `credential.helper` / `credential.<url>.helper` | `push / fetch の認証時に実行される` |
| `filter.<name>.clean` / `filter.<name>.smudge` | `add / checkout のたびに実行される` |
| `include.path` / `includeif.<cond>.path` | `別ファイルの設定を取り込む(実行ベクタの間接注入)` |
| `alias.<name>`(**値が `!` で始まるものだけ**) | `git <alias> 実行時に shell が走る` |

補足2点:

- **`includeif.*.path` を含める**のは、`include.path` と**まったく同一の経路**だから。
  `include.path` だけ見て `includeIf` を見逃すのは、このチケットが是正しようとしている
  「検査の非対称」そのものになる。git はセクション名を小文字化して返すため、キーは `includeif.` 始まりになる
- **`alias.*` は `!` 形式だけ**。Issue の技術メモは「`!` 無しでも `git` サブコマンドの入れ替えは可能」と
  懸念しているが、**実測の結果これは成り立たない**。`git config --local alias.status '!echo HIJACKED'` を
  仕込んでも `git status` は本来の動作をした(git は組み込みサブコマンドを上書きするエイリアスを無視する)。
  したがって `!` の無いエイリアスは既存コマンドの乗っ取り経路にならず、**新規のエイリアス名を人間が
  自分で叩いたときだけ**問題になる = `!` 形式に絞ってよい。この実測結果は `verification.md` に記録すること

### 判断5: `git config --local --list -z`(NUL 区切り)で読む

git config の値は改行を含み得る。改行区切りで読むと 1 レコードが複数行に割れる。
`-z` は `key\nvalue\0` 形式を返す(実測で確認済み)ので、レコード境界が値の中身に影響されない。

### 判断6: 出力する値は 1 行目のみ・120 文字で切る

値が長大・多行でも `note` の 1 行に収める。切り詰めた場合は末尾に `…` を付ける。

### 判断7: D2.5 は `USES_HUSKY` に依存しない

D1 は husky を使う構成でのみ意味があるので `if [ "$USES_HUSKY" = yes ]` の中にある。
D2.5 は husky と無関係(git 自体の実行ベクタ)なので**無条件で実行する**。

### 判断8: 抑制用の環境変数(オプトアウト)は作らない

停止しない検査なので逃げ道が要らない。YAGNI。

---

## §1. `.claude/scripts/check-guard-integrity.sh` に D2.5 を追加する

### 挿入位置

**D2 のブロックの直後、D3 のコメント(`# --- D3) 縮退中コミットの差分が…`)の直前。**
現行ファイルでは D2 の `done < <(find "$GIT_HOOKS_DIR" ... )` を閉じる `fi` の次の空行の後になる。

D1/D2/D3 の既存コードは**一切変更しない**。

### 挿入する内容(この通りに入れる)

```bash
# --- D2.5) .git/config にホストコマンド実行ベクタが仕込まれていないか ---
#
# 縮退モードは .git を writable_roots に渡す = .git/config を丸ごと書ける唯一の経路。
# D1 は core.hooksPath という 1 キーしか見ないが、config には「次に人間や Claude が git を
# 叩いた瞬間にホストコマンドを実行する」キーが他にもある。とくに core.fsmonitor は
# git status で発火するため、復帰検収(D1〜D3)より先に走り得る。
#
# 倒し方は D1/D2 と同じ「報告のみ」。対象キーには正当な用途もあるため停止はしない
# (この検査はセキュリティ境界ではなく検出と報告。docs/template-dev/codex-delegation-plan.md §2.3)。
#
# 検査範囲はローカル設定のみ。縮退中の Codex が書けるのがローカルだけであることに加え、
# devcontainer は --global / --system に credential.helper の `!` 形式を既定で置いており、
# 混ぜると平常運用で必ず誤爆する(実測)。
#
# alias.* は `!` 形式(shell 実行)だけを対象にする。git は組み込みサブコマンドを上書きする
# エイリアスを無視するため(実測: alias.status に `!` 形式を仕込んでも git status は本来の動作)、
# `!` の無いエイリアスは既存コマンドの乗っ取り経路にならない。
#
# 値は改行を含み得るので -z(NUL 区切りの key\nvalue)で読む。改行区切りだと 1 レコードが割れる。
while IFS= read -r -d '' _rec; do
  [ -n "$_rec" ] || continue
  _key="${_rec%%$'\n'*}"
  case "$_rec" in
    *$'\n'*) _val="${_rec#*$'\n'}" ;;
    *) _val="" ;;
  esac

  _why=""
  case "$_key" in
    core.fsmonitor) _why="git status 等のたびに実行される" ;;
    core.sshcommand) _why="push / fetch のたびに実行される" ;;
    core.pager) _why="log / diff 等のたびに実行される" ;;
    credential.helper | credential.*.helper) _why="push / fetch の認証時に実行される" ;;
    filter.*.clean | filter.*.smudge) _why="add / checkout のたびに実行される" ;;
    include.path | includeif.*.path) _why="別ファイルの設定を取り込む(実行ベクタの間接注入)" ;;
    alias.*)
      case "$_val" in
        '!'*) _why="git <alias> 実行時に shell が走る" ;;
      esac
      ;;
  esac
  [ -n "$_why" ] || continue

  _shown="${_val%%$'\n'*}"
  [ "${#_shown}" -le 120 ] || _shown="${_shown:0:120}…"
  note ".git/config(local)に $_key=$_shown が設定されている($_why)。縮退中に仕込まれたものでないか値を確認すること"
done < <(git config --local --list -z 2>/dev/null)
```

### 注意点(実装者向け)

- スクリプト冒頭は `set -uo pipefail`。上のコードは全分岐で `_val` / `_why` / `_shown` を代入してから
  参照するので `-u` に抵触しない。**変数名を変えない**(既存コードのローカル変数と衝突しないよう `_` 始まりにしてある)
- `note` は既存のシェル関数(`echo` して `FOUND=1`)。**再定義しない**
- `git config --local --list -z` はローカル設定が空でも exit 0 ではない場合があるため `2>/dev/null` を付け、
  `while` が 0 レコードで終わるのに任せる(`|| true` は不要 — プロセス置換なので終了コードは伝播しない)

---

## §2. `docs/template-dev/codex-delegation-plan.md` §12.3 に push 前検査を入れる

### 変更1: 手順 7 を書き換える(**手順の番号は増やさない**)

現行:

```
7. **人間が区切りごとに push する** — Codex はネットワーク無効かつ push 禁止(§7.1)なので、これをしない限りコミットはローカルに留まり CI に届かない(§9)
```

置換後:

```
7. **人間が区切りごとに push する** — Codex はネットワーク無効かつ push 禁止(§7.1)なので、これをしない限りコミットはローカルに留まり CI に届かない(§9)。**push の前に `bash .claude/scripts/check-guard-integrity.sh degraded` を回す** — D2.5 が見る `core.sshCommand` / `credential.helper` は push の瞬間に発火するため、手順 8 の復帰検収まで待つと検査が間に合わない
```

**新しい手順番号を足さない理由**: このドキュメント内の他の箇所が手順番号を参照しており
(§9 付近の「(§12.3 手順 6)」など)、番号がずれると参照が壊れる。

### 変更2: 上記の「(§12.3 手順 6)」の参照ずれを直す

`docs/template-dev/codex-delegation-plan.md` の §9 付近(現行 729 行目)に次の記述がある:

```
**区切りごとに人間が `git push` する**ところまでが緩和策の中身になる(§12.3 手順 6)
```

§12.3 の push は**手順 7** であり、手順 6 は「Codex が codex-log.md に追記する」なので参照が 1 つずれている。
`(§12.3 手順 6)` を `(§12.3 手順 7)` に直す。**この 1 語だけ**を変える(周囲の文は触らない)。

---

## §3. `.claude/rules/mode/degraded.md` に push 前検査の順序を反映する

このファイルは SessionStart hook が**司令塔のコンテキストに毎回注入する**。行数の追加は最小にする
(`context-management.md`「ルールを追記するときの置き場所」)。

### 変更内容

「### 復帰時の検収(§2.3)」の手順 1 の説明ブロック(コードブロックの直後、`**1 行でも出力されたら…**` の行)の
**直後に、次の 1 行だけ**を足す:

```
   検査対象は `core.hooksPath` / `.git/hooks/` の直書き(D1・D2)、`.git/config` のホストコマンド実行ベクタ(D2.5)、禁止領域を触った `Codex-authored` コミット(D3)。**縮退中に人間が push するときも、push の前にこの検査を回す**(`core.sshCommand` / `credential.helper` は push の瞬間に発火するため、復帰まで待つと間に合わない。`docs/template-dev/codex-delegation-plan.md` §12.3 手順 7)。
```

インデントは既存の手順 1 のブロック(スペース 3 個)に合わせる。**他の行・他の手順は変更しない。**

---

## §4. 検証(実測。結果は `verification.md` に記録する)

すべて**このリポジトリのワーキングツリー**で行う。`.git/config` を一時的に汚すので、
**各シナリオは設定と復元を同一コマンド行で行い、消し忘れが起きない形にする。**

### §4-0 事前確認

```bash
bash -n .claude/scripts/check-guard-integrity.sh          # 構文チェック(exit 0)
git config --local --list | grep -cE '^(core\.(fsmonitor|sshcommand|pager)|credential\.|filter\.|include\.|includeif\.|alias\.)'   # 0 であること
```

### §4-1 誤爆しないこと(受け入れ条件 2)

```bash
bash .claude/scripts/check-guard-integrity.sh degraded; echo "exit=$?"
```

**期待**: D2.5 由来の行(`.git/config(local)に` で始まる行)が **0 行**。
(D3 由来の行が出る可能性はある。その場合は D2.5 の行だけが 0 であることを確認し、
出た行を `verification.md` に「本チケットとは無関係」として記録する)

### §4-2 各キーが検出されること

下表の各行について、**1 行のコマンドで「設定 → 検査 → 復元」**を行う。テンプレート:

```bash
git config --local <KEY> '<VALUE>'; bash .claude/scripts/check-guard-integrity.sh degraded | grep -F '<KEY>'; git config --local --unset-all <KEY>
```

| # | KEY | VALUE | 期待 |
| --- | --- | --- | --- |
| C1 | `core.fsmonitor` | `echo pwned` | 検出(**受け入れ条件 1**) |
| C2 | `core.sshCommand` | `ssh -o ProxyCommand=curl evil` | 検出 |
| C3 | `core.pager` | `sh -c "echo pwned"` | 検出 |
| C4 | `credential.helper` | `!echo pwned` | 検出 |
| C5 | `credential.https://example.com.helper` | `!echo pwned` | 検出(URL 付きサブセクション形) |
| C6 | `filter.evil.clean` | `sh -c "echo pwned"` | 検出 |
| C7 | `filter.evil.smudge` | `sh -c "echo pwned"` | 検出 |
| C8 | `include.path` | `/tmp/evil.cfg` | 検出 |
| C9 | `alias.evil` | `!echo pwned` | 検出 |
| C10 | `alias.harmless` | `status --short` | **検出しない**(`!` 無しは対象外。判断4) |

C10 だけは `grep -F 'alias.harmless'` が**何も返さない**(grep の exit 1)ことを確認する。

### §4-3 値の切り詰めと多行値

```bash
git config --local core.pager "$(printf 'AAAA%.0s' {1..200})"; bash .claude/scripts/check-guard-integrity.sh degraded | grep -F 'core.pager'; git config --local --unset-all core.pager
```

**期待**: 出力が 1 行に収まり、末尾が `…` で切れている。

### §4-4 後始末

```bash
git config --local --list | grep -cE '^(core\.(fsmonitor|sshcommand|pager)|credential\.|filter\.|include\.|includeif\.|alias\.)'   # 0 に戻っていること
git status --short   # .git/config はワークツリー外なので差分に出ないが、意図しない変更が無いことを確認
```

**重要**: 検証で `.git/config` に足したキーが 1 つでも残っていたら、以降のすべての検査が汚染される。
§4-4 を必ず実行し、結果を `verification.md` に記録する。

---

## §5. `docs/template-dev/CHANGELOG.md` に追記する

**既存の `## 2026-08-31` 見出しの中**に追記する(今日の日付。新しい見出しを作らない)。
その見出しの中では**既存の Issue #56 の記述より上**に置く(新しいものを上に)。

書く内容(この形で):

```markdown
**モード C 復帰検査に `.git/config` のホストコマンド実行ベクタ検査(D2.5)を足した(Issue #58)。** 縮退モードは `.git` を writable_roots に渡すため、委託先が `.git/config` を丸ごと書けます。D1(`core.hooksPath`)と D2(`.git/hooks/` 直書き)は見ていましたが、`core.fsmonitor` のように**復帰検収より先に発火する**キーが検査対象外でした。

- **[auto]** `check-guard-integrity.sh degraded` に D2.5 を追加。`core.fsmonitor` / `core.sshCommand` / `core.pager` / `credential.*.helper` / `filter.*.clean|smudge` / `include.path` / `includeIf.*.path` / `alias.*`(`!` 形式のみ)を**値ごと報告**します。D1/D2 と同じく**報告のみで停止はしません**
- **[auto]** 検査範囲は `--local` のみです。devcontainer は `--global` / `--system` に `credential.helper` の `!` 形式を既定で置いているため、混ぜると平常運用で必ず誤爆します(実測)
- **[auto]** `alias.*` は `!` 形式だけが対象です。git は組み込みサブコマンドを上書きするエイリアスを無視するため(実測)、`!` の無いエイリアスは既存コマンドの乗っ取り経路になりません
- **[manual]** **モード C を運用しているプロジェクトは、push の前に `bash .claude/scripts/check-guard-integrity.sh degraded` を回す運用に変えてください。** `core.sshCommand` / `credential.helper` は push の瞬間に発火するため、Claude 復帰時の検収まで待つと検査が間に合いません(§12.3 手順 7 / `.claude/rules/mode/degraded.md` に反映済み)
```

---

## §6. 品質チェック

```bash
bash -n .claude/scripts/check-guard-integrity.sh
npm run lint
npm run typecheck
npm run format:check
```

`format:check` が `.md` の整形差分を出したら `npm run format` で直す。

---

# 追補(検収 1 巡目の指摘を受けた確定判断)

code-reviewer の指摘(Critical 0 / Major 1 / Minor 3)に対する司令塔の判断。
**実装者はここでも判断をしない。** 以下をそのまま反映する。

## §0 判断9(追加): 対象キーを 7 パターン増やす(Major 指摘を採用)

判断4 の表は「D1 が 1 キーしか見ていないのは非対称」という本チケットの動機に対して、
**D2.5 の中に同じ非対称を残していた**。倒し方(報告のみ・値ごと報告)は変えず、表だけを広げる。
追加はいずれも `case` パターン 1 行で、複雑さは増えない。

| 追加するキー | 報告理由(出力に載せる文言) | 採用理由 |
| --- | --- | --- |
| `url.<base>.insteadof` / `url.<base>.pushinsteadof` | `fetch / push / clone の URL を書き換える(ext::sh 形式でコマンド実行になり得る)` | **最重要**。`ext::sh -c` へのリライトは既知の git RCE 手口で、`credential.helper` より発火条件が緩く通常の fetch / push で即発火する |
| `core.editor` / `sequence.editor` | `git commit(-m 無し)/ rebase -i のときに実行される` | §12.3 の運用は人間が手で commit / rebase する前提 |
| `core.gitproxy` | `プロキシ経由の接続時に実行される` | 同じ `.git/config` 1 ファイルで完結する実行ベクタ |
| `diff.<driver>.command` | `git diff のたびに実行される(.gitattributes 経由)` | 同上 |
| `merge.<name>.driver` | `マージ解決のたびに実行される(.gitattributes 経由)` | 同上 |

**誤爆リスクの判定**: いずれも `--local` に既定で置かれるものではない(このリポジトリの
`git config --local --list` に 1 件も無いことを確認済み)。判断2・判断3 は変えない。

### 実装: `check-guard-integrity.sh` の D2.5 の `case "$_key" in` に以下を追加する

既存の分岐は変更しない。`alias.*)` の分岐の**直前**に挿入する(`alias.*` は最後に置く)。

```bash
    core.editor | sequence.editor) _why="git commit(-m 無し)/ rebase -i のときに実行される" ;;
    core.gitproxy) _why="プロキシ経由の接続時に実行される" ;;
    url.*.insteadof | url.*.pushinsteadof) _why="fetch / push / clone の URL を書き換える(ext::sh 形式でコマンド実行になり得る)" ;;
    diff.*.command) _why="git diff のたびに実行される(.gitattributes 経由)" ;;
    merge.*.driver) _why="マージ解決のたびに実行される(.gitattributes 経由)" ;;
```

### 検証に追加するシナリオ(§4-2 の表に足す。手順は同一)

| # | KEY | VALUE | 期待 |
| --- | --- | --- | --- |
| C11 | `url.https://evil.example.com/.insteadOf` | `https://github.com/` | 検出 |
| C12 | `url.https://evil.example.com/.pushInsteadOf` | `https://github.com/` | 検出 |
| C13 | `core.editor` | `sh -c "echo pwned"` | 検出 |
| C14 | `sequence.editor` | `sh -c "echo pwned"` | 検出 |
| C15 | `core.gitProxy` | `sh -c "echo pwned"` | 検出 |
| C16 | `diff.evil.command` | `sh -c "echo pwned"` | 検出 |
| C17 | `merge.evil.driver` | `sh -c "echo pwned"` | 検出 |
| C18 | `includeIf.gitdir:/workspaces/.path` | `/tmp/evil.cfg` | 検出(1 巡目で未実測だった `includeIf` 形。**司令塔が実測済み**: 検出を確認・残留 0 件。`verification.md` に「司令塔が実測」と明記して転記すること) |

`--unset-all` でサブセクション付きキーを消したあと、空セクションが残ることがある。
後始末(§4-4)では `git config --local --remove-section '<section>'` も併用し、
**§4-4 のカウントが 0 になるまで**確認する。

### CHANGELOG(§5)の該当行を差し替える

追記済みの 1 つ目の `[auto]` 項目のキー列挙を、追加後の全キーに合わせて書き直す:

```markdown
- **[auto]** `check-guard-integrity.sh degraded` に D2.5 を追加。`core.fsmonitor` / `core.sshCommand` / `core.pager` / `core.editor` / `sequence.editor` / `core.gitProxy` / `credential.*.helper` / `url.*.insteadOf|pushInsteadOf` / `filter.*.clean|smudge` / `diff.*.command` / `merge.*.driver` / `include.path` / `includeIf.*.path` / `alias.*`(`!` 形式のみ)を**値ごと報告**します。D1/D2 と同じく**報告のみで停止はしません**
```

## §7(追加): `.codex/skills/degraded-mode-ticket/SKILL.md` の検出範囲の記述を更新する(Minor 指摘を採用)

同ファイル 197 行目付近の表が `check-guard-integrity.sh degraded` の検出範囲を
「`core.hooksPath` の書き換え・`.git/hooks/` への直書き」としか書いていない。
Codex 自身が読む説明が検査範囲を過小に伝えたままになるため直す。

**該当セルの記述に `.git/config` の実行ベクタ(D2.5)を足すだけ**にする(表の構造・他の行は変えない)。
実装前に該当箇所を読み、既存の言い回しに合わせて最小の語句追加で済ませること。

## §8(追加): `.claude/rules/mode/degraded.md` の重複を解消する(Minor 指摘を採用)

1 巡目の追記は、直前の既存文が既に列挙している D1/D2/D3 の内容を**もう一度列挙**しており、
司令塔のコンテキストに毎回注入されるファイルとしては冗長。次の形に整理する
(**正味の行数を増やさない**)。

現行(手順 1 の説明ブロック):

```
   縮退モードは `.git` が書き込み可能な唯一の経路で、`core.hooksPath` の書き換え・
   `.git/hooks/` への直書き・禁止領域を触った `Codex-authored` コミットを検出する。
   **1 行でも出力されたら、その内容を人間に報告してから検収を続ける。**
   検査対象は `core.hooksPath` / `.git/hooks/` の直書き(D1・D2)、`.git/config` のホストコマンド実行ベクタ(D2.5)、禁止領域を触った `Codex-authored` コミット(D3)。**縮退中に人間が push するときも、push の前にこの検査を回す**(`core.sshCommand` / `credential.helper` は push の瞬間に発火するため、復帰まで待つと間に合わない。`docs/template-dev/codex-delegation-plan.md` §12.3 手順 7)。
```

置換後:

```
   縮退モードは `.git` が書き込み可能な唯一の経路で、`core.hooksPath` の書き換え・
   `.git/hooks/` への直書き・`.git/config` のホストコマンド実行ベクタ・禁止領域を触った
   `Codex-authored` コミットを検出する。
   **1 行でも出力されたら、その内容を人間に報告してから検収を続ける。**
   **縮退中に人間が push するときも、push の前にこの検査を回す**(`core.sshCommand` / `credential.helper` は push の瞬間に発火するため、復帰まで待つと間に合わない。`docs/template-dev/codex-delegation-plan.md` §12.3 手順 7)。
```

## §9(追加): `verification.md` に環境依存の注記を 1 行足す(Minor 指摘を採用)

判断2 の根拠(`--global` / `--system` に `credential.helper` の `!` 形式がある)は
**この devcontainer 1 インスタンスの実測値**である。テンプレートとして配布された先では
構成が違い得る。`verification.md` の末尾に次の 1 行を足す:

```markdown
**注記(環境依存)**: 判断2 の根拠(`--global` / `--system` に `credential.helper` の `!` 形式が既定で置かれている)は、このテンプレートリポジトリの devcontainer 1 インスタンスでの実測値。配布先の devcontainer 構成では成立しないことがあるため、`--local` 限定という設計判断を見直す場合はその環境で再実測すること。
```

## 見送った指摘

なし(Major 1 / Minor 3 をすべて採用)。

---

# 追補2(検収 2 巡目の指摘を受けた確定判断)

code-reviewer 2 巡目の結果は Critical 0 / Major 0 / Minor 1。

## §10 判断10: 対象キーが「閉リスト」であることをコード側に明記する(Minor 指摘を採用)

指摘は「`core.askpass` / `http.proxy` / `gpg.program` 等の同種ベクタがスコープ外のまま。
判断4 で意図的にクローズしたリストだが、その旨がコードから読み取れないため将来
同じ『非対称』指摘が再発しうる」というもの。**対象キーは増やさない**(判断4 を維持)。
足すのは意図の明記だけ。

`check-guard-integrity.sh` の D2.5 ヘッダコメントの「alias.* は `!` 形式〜」ブロックの
**直前**に、次の 1 ブロックを挿入する(既存のコメント行は変更しない):

```bash
# 対象キーは網羅リストではなく、.git/config 単体で完結する既知の主要ベクタに絞った閉リスト。
# 増減は設計判断(.steering/20260831-issue58-git-config-vectors/design.md 判断4)を経由すること。
```

他のファイルは変更しない。
