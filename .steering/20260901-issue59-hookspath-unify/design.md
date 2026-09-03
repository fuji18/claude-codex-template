# 設計: hooksPath 判定を一本化し、ポリシー空洞化検査を強化する(Issue #59)

<!-- status: ready -->

## 設計判断(先に確定させたもの)

### 判断1: サブコマンド方式を採る(`lib-*.sh` への切り出しはしない)

Issue が「どちらを採るかは設計判断」としている箇所。**`hooks-path` サブコマンド**を採る。

- `lib-*.sh` 方式は `delegate-codex.sh` の**自己コピー exec の同梱対象**に追加が要る
  (`lib-record.sh` の前例)。運搬対象が増えるほど「運び忘れると委託中に壊れる」面が広がる
- 自己コピーが守っているのは**委託中(codex exec 実行中)にファイルが書き換わる**ハザード。
  5-3 は codex exec より**前**に完結する入口検査なので、このハザードの射程外
- 前例がある: 隣の **5-4 は `bash .claude/scripts/check-protected-branch.sh` を
  リポジトリのパスからそのまま呼んでいる**。5-3 を同じ形にすると、入口検査の
  「判定を共有スクリプトに委ねる」書き方が 5-3 / 5-4 で揃う

### 判断2: `hooks-path` は検査 1(ポリシー)を回さない

5-3 はサブコマンドの標準出力をそのままエラーメッセージに載せる。ポリシー検査の指摘が
混ざると「git hook が無効」という 5-3 のメッセージと食い違う。検査 1 を
`[ "$SUBCOMMAND" != hooks-path ]` で外す。ブロックの並び順は変えない(差分を最小にする)。

### 判断3: `USES_HUSKY` の判定も共有する(5-3 の `[ -d .husky ]` を捨てる)

現行 5-3 のガードは `[ -d .husky ]` だが、D1 のガードは `USES_HUSKY`
(= `.husky/` があるか **または** `package.json` に husky 依存があるか)。**厳しい側に揃える**。

結果として挙動が 1 つ変わる: 「`package.json` に husky があるのに `.husky/` が無い」構成で
5-3 が `exit 3` になる。これは意図した変更で、その状態は git hook 層が丸ごと無い状態そのもの。
`exit 3` は「Sonnet fork にフォールバック」という無害な退避であり、破壊的な失敗ではない。

### 判断4: `USES_HUSKY` のガードは関数の**中**に置く

呼び出し側 2 箇所(D1 と `hooks-path` 分岐)に同じ `if` を書くと、このチケットが
潰している「判定の分散」を関数の外側で再生産する。ガードは関数の 1 行目に入れる。

### 判断5: 検査 1-b の照合は「前方一致」で見る(完全一致にしない)

CI の `branch-policy` ジョブは `startswith` でブランチ名を照合する
(`.github/workflows/ci.yml`)。したがって空洞化するのは「`allowedPrefixes` に
保護ブランチ名が**そのまま**入っている」場合だけではなく、**保護ブランチ名に前方一致する
接頭辞**(`main` に対する `mai`、および空文字列 `""`)すべて。CI の照合と同じ演算で見る。

誤検知しないことの確認: 既定ポリシーの `feature/` `fix/` `release/` `hotfix/` `claude/`
`dependabot/` はいずれも `main` の前方一致にならない(`release/` と `release` は別物)。

### 判断6: 検査 1-a は `protectedBranches` が非空のときだけ回す

空のときは既存の指摘 1 行で足りる。両方鳴らすと 1 つの原因に 2 行出て、
「何行出たか」で判断する degraded 手順の読みが濁る。`else` 節に入れる。

### 判断7: 5-3 はサブコマンドが `0`/`1` 以外を返したら**素通しして警告する**

`rc=2` は「使い方の誤り」= `hooks-path` を知らない古い `check-guard-integrity.sh`
(`/sync-template` の部分適用など)。ここで `exit 3` にすると、環境の同期ずれで
全委託が止まる。素通し + `stderr` 警告にする。

フェイルオープンでよい根拠: **CI の `harness-integrity` ジョブが
`bash .claude/scripts/check-guard-integrity.sh` を必ず実行する**ので、
このファイルの欠落・破損はクライアント非依存の層で必ず赤くなる。
スクリプト自体が無い場合(`[ -f ]` が偽)も同じ扱いで、これは 5-4 と同じ形。

### 判断8: 散文(AGENTS.md / degraded SKILL.md)からは判定条件を消す

「空 or 実在しない」「`.husky` 配下」といった条件の再掲をやめ、**検査コマンドを 1 本**
提示する形にする。条件を残すと、今回一本化した実体とは別に 3 つ目・4 つ目のソースが
残り続ける(#58 の申し送り 2「閉リストであることは、増やす提案が来る場所に痕跡を残す」
の裏返しで、こちらは**判定はコードにしかない**と書き切る)。

`> 値を .husky と決め打ちで比較しないでください` の注記も削る — 比較は人がしなくなるため。

---

## §1: `.claude/scripts/check-guard-integrity.sh`

### §1-1: ヘッダのサブコマンド説明を更新する(2 箇所)

**置換前**(ファイル冒頭の呼び出し元リスト内の 1 行):

```
#   - .claude/rules/mode/degraded.md … モード C 復帰時の検収(degraded サブコマンド)
```

**置換後**(1 行を 2 行にする):

```
#   - .claude/rules/mode/degraded.md … モード C 復帰時の検収(degraded サブコマンド)
#   - .claude/scripts/delegate-codex.sh … impl 入口検査 5-3(hooks-path サブコマンド)
```

**置換前**(`# ---------- サブコマンド ----------` ブロックの説明 2 行):

```
# 引数なし … 既存の自壊検知(SessionStart hook / CI の harness-integrity が呼ぶ)
# degraded … 上記に加えて、モード C(縮退)復帰時のガードレール健全性検査
```

**置換後**(3 行にする):

```
# 引数なし   … 既存の自壊検知(SessionStart hook / CI の harness-integrity が呼ぶ)
# degraded   … 上記に加えて、モード C(縮退)復帰時のガードレール健全性検査
# hooks-path … core.hooksPath の判定だけを行う(delegate-codex.sh 入口検査 5-3 が呼ぶ)。
#              5-3 が独自に「空 or 実在しない」だけを見ていたため D1 より緩く、実在する
#              無関係なディレクトリを素通ししていた(#59)。判定の実体をここに集約する。
```

### §1-2: サブコマンドの受理と使い方メッセージ

**置換前**(27〜33 行目付近):

```bash
SUBCOMMAND="${1:-default}"
case "$SUBCOMMAND" in
  default | degraded) ;;
  *)
    echo "使い方: check-guard-integrity.sh [degraded]" >&2
    exit 2
    ;;
esac
```

**置換後**:

```bash
SUBCOMMAND="${1:-default}"
case "$SUBCOMMAND" in
  default | degraded | hooks-path) ;;
  *)
    echo "使い方: check-guard-integrity.sh [degraded|hooks-path]" >&2
    exit 2
    ;;
esac
```

### §1-3: `check_hooks_path()` を定義する

`note() { echo "$1"; FOUND=1; }` の行(43 行目付近)の**直後**に、空行を 1 つ挟んで
次のブロックを挿入する。

```bash
# core.hooksPath が husky を指しているかの判定の実体。
#
# 呼び出し元は 2 つあり、同じ結果になることが要件(#59):
#   - 下の D1(degraded サブコマンド)      … モード C 復帰時の検収
#   - hooks-path サブコマンド              … delegate-codex.sh 入口検査 5-3
# かつては 5-3 が「空 or 実在しないディレクトリ」だけを見ており、実在する無関係な
# ディレクトリを指す core.hooksPath を素通ししていた。
#
# 値を .husky と決め打ちで比較しない。husky v9 が設定するのは .husky/_。
# 空・実在しないディレクトリ・.husky 配下以外は、いずれも「git hook 層が無い」状態。
#
# husky を使う構成かどうかのガードは呼び出し側ではなくこの中に置く。外に出すと
# 呼び出し元ごとに条件がずれ、このチケットが潰した分散をそのまま再生産する。
# USES_HUSKY を参照するため、その決定より後にだけ呼ぶこと。
check_hooks_path() {
  [ "$USES_HUSKY" = yes ] || return 0

  local _hooks_path
  _hooks_path="$(git config --get core.hooksPath 2>/dev/null || true)"
  if [ -z "$_hooks_path" ]; then
    note "core.hooksPath が未設定。.husky/ のフックが一切動かない(npm ci での有効化漏れか、縮退中の書き換えを疑う)"
  elif [ ! -d "$_hooks_path" ]; then
    note "core.hooksPath が実在しないディレクトリ($_hooks_path)を指している。git hook 層が無効になっている"
  else
    case "$_hooks_path" in
      .husky | .husky/*) ;;
      *) note "core.hooksPath が .husky 配下以外($_hooks_path)を指している。ベンダー非依存の git hook 層が迂回されている" ;;
    esac
  fi
}
```

### §1-4: 検査 1 を強化する

**置換前**(45〜52 行目付近。`# --- 1) 単一ソースの空洞化 ---` から `fi` まで):

```bash
# --- 1) 単一ソースの空洞化 ---
# 保護ブランチ検査の全層(PreToolUse hook / .husky/* / CI の branch-policy ジョブ)は
# いずれも protectedBranches という同じ配列を読む。ここが空になると全層が同時に、
# かつ「正常に動作したうえで素通し」という形で無効化される。層の数では防げない唯一の経路。
if [ -f "$POLICY" ] && command -v jq >/dev/null 2>&1; then
  jq -e '(.protectedBranches // []) | length > 0' "$POLICY" >/dev/null 2>&1 ||
    note "$POLICY の protectedBranches が空。保護ブランチ検査が全層(PreToolUse / .husky/* / CI)で素通しになる"
fi
```

**置換後**:

```bash
# --- 1) 単一ソースの空洞化 ---
# 保護ブランチ検査の全層(PreToolUse hook / .husky/* / CI の branch-policy ジョブ)は
# いずれも protectedBranches という同じ配列を読む。ここが空になると全層が同時に、
# かつ「正常に動作したうえで素通し」という形で無効化される。層の数では防げない唯一の経路。
#
# 「空」以外にも、全層が正常動作したまま保護が消える書き換えが 2 つある(#59)。
# #56 で branch-policy.json を委託禁止領域に入れて委託経路は塞いだが、人間の手による
# 誤編集には効かないため機械的に検出する。スキーマ検証一般には広げない —
# 「保護が空洞化する」パターンだけに絞る。
#
# hooks-path サブコマンドでは回さない。5-3 は標準出力をそのままエラーメッセージに
# 載せるため、ポリシーの指摘が混ざると「git hook が無効」という説明と食い違う。
if [ "$SUBCOMMAND" != hooks-path ] && [ -f "$POLICY" ] && command -v jq >/dev/null 2>&1; then
  if ! jq -e '(.protectedBranches // []) | length > 0' "$POLICY" >/dev/null 2>&1; then
    note "$POLICY の protectedBranches が空。保護ブランチ検査が全層(PreToolUse / .husky/* / CI)で素通しになる"
  else
    # 1-a) baseBranch が保護されているか。
    # baseBranch は PR のマージ先 = 成果物が積まれる幹。ここが protectedBranches に
    # 無いと、check-protected-branch.sh は「保護ブランチではない」と正しく判定した
    # うえで直接コミットを通す。protectedBranches を ["develop"] に差し替える改変が
    # 典型で、全層が緑のまま main への直コミットが解禁される。
    # protectedBranches が空のときは上の指摘で足りるので else 側でだけ見る。
    _base="$(jq -r '.baseBranch // "main"' "$POLICY" 2>/dev/null || echo main)"
    jq -e --arg b "$_base" '(.protectedBranches // []) | index($b)' "$POLICY" >/dev/null 2>&1 ||
      note "$POLICY の baseBranch($_base)が protectedBranches に含まれていない。PR のマージ先が無防備になり、全層が正常動作したまま直接コミットを通す"
  fi

  # 1-b) allowedPrefixes が保護ブランチ名そのものを許可していないか。
  # CI の branch-policy ジョブは PR の head ブランチ名を startswith で照合するため、
  # 保護ブランチ名に前方一致する接頭辞(例: "main"、あるいは空文字列)が 1 つでも
  # 入ると、保護ブランチから出した PR がブランチ名検査を通過する。
  # CI と同じ演算(startswith)で見る。完全一致だけを見ると "mai" や "" を取り逃す。
  while IFS="$(printf '\t')" read -r _pb _ap; do
    [ -n "$_pb" ] || continue
    note "$POLICY の allowedPrefixes に保護ブランチ '$_pb' へ前方一致する接頭辞 '${_ap}' がある。保護ブランチから出した PR が CI の branch-policy のブランチ名検査を通過する"
  done < <(jq -r '(.allowedPrefixes // []) as $ap | (.protectedBranches // [])[] | . as $b | $ap[] | select($b | startswith(.)) | "\($b)\t\(.)"' "$POLICY" 2>/dev/null)
fi
```

> 実装メモ: `IFS="$(printf '\t')"` にしているのは、ソースにリテラルのタブを置かないため。
> git のブランチ名にタブは使えないので、区切りとして安全。接頭辞が空文字列のときは
> `_ap` が空になり、メッセージは `接頭辞 '' がある` と出る(これで意図は読める)。

### §1-5: D1 を関数呼び出しに置き換える

**置換前**(104〜121 行目付近):

```bash
# --- D1) core.hooksPath が husky を指しているか ---
#
# 値を .husky と決め打ちで比較しない。husky v9 が設定するのは .husky/_。
# 空・実在しないディレクトリ・.husky 配下以外は、いずれも「git hook 層が無い」状態。
if [ "$USES_HUSKY" = yes ]; then
  HOOKS_PATH="$(git config --get core.hooksPath 2>/dev/null || true)"
  if [ -z "$HOOKS_PATH" ]; then
    note "core.hooksPath が未設定。.husky/ のフックが一切動かない(npm ci での有効化漏れか、縮退中の書き換えを疑う)"
  elif [ ! -d "$HOOKS_PATH" ]; then
    note "core.hooksPath が実在しないディレクトリ($HOOKS_PATH)を指している。git hook 層が無効になっている"
  else
    case "$HOOKS_PATH" in
      .husky | .husky/*) ;;
      *) note "core.hooksPath が .husky 配下以外($HOOKS_PATH)を指している。ベンダー非依存の git hook 層が迂回されている" ;;
    esac
  fi
fi
```

**置換後**:

```bash
# --- D1) core.hooksPath が husky を指しているか ---
#
# 判定の実体は上の check_hooks_path()。hooks-path サブコマンド(= delegate-codex.sh
# 入口検査 5-3)と同じ関数を通ることが要件(#59)。
check_hooks_path
```

### §1-6: `hooks-path` の早期終了を差し込む

**置換前**(64〜68 行目付近。既存の 2 ブロックの境目):

```bash
if [ "$USES_HUSKY" = no ] && [ "$SUBCOMMAND" != degraded ]; then
  exit "$FOUND"
fi

if [ "$USES_HUSKY" = yes ]; then
```

**置換後**:

```bash
if [ "$USES_HUSKY" = no ] && [ "$SUBCOMMAND" != degraded ]; then
  exit "$FOUND"
fi

# --- 2.5) hooks-path サブコマンドはここで終わる ---
# 見るのは core.hooksPath だけ。呼び出し元(入口検査 5-3)は「git hook が有効か」を
# 判定したいのであって、.husky/pre-commit の中身(検査 3・4)は関知しない。
# 混ぜると 5-3 が本来の理由と違う指摘で exit 3 を返す。
if [ "$SUBCOMMAND" = hooks-path ]; then
  check_hooks_path
  exit "$FOUND"
fi

if [ "$USES_HUSKY" = yes ]; then
```

---

## §2: `.claude/scripts/delegate-codex.sh` 入口検査 5-3

**置換前**(`  # ---- 5-3: git hook が有効か ----` から、その次の `exit "$EX_UNAVAIL"` と
`  fi` までの 1 ブロック全体):

```bash
  # ---- 5-3: git hook が有効か ----
  # .husky/ があるのに core.hooksPath が未設定 = husky が丸ごと無効。
  # 保護ブランチへのコミットを止めるベンダー非依存の層が存在しない状態で
  # workspace-write の委託をしない。
  # 空振り条件: .husky/ を持たないプロジェクト(Python/Go 等)ではこの検査は
  # 何も見ない。そこでは git hook 層そのものが存在しないので、判定できない。
  #
  # 「非空」だけでは足りない — 別ツールが core.hooksPath を実在しないパスに
  # 設定していると husky は無効なのにこの検査は素通りする。指すディレクトリの
  # 実在まで見る。値そのものを ".husky" と比較してはいけない: husky v9 が
  # 設定するのは ".husky/_" であり、決め打ちすると全委託が止まる(実測)。
  HOOKS_PATH="$(git config --get core.hooksPath 2>/dev/null || true)"
  if [ -d .husky ] && { [ -z "$HOOKS_PATH" ] || [ ! -d "$HOOKS_PATH" ]; }; then
    cat >&2 <<'MSG'
delegate-codex: git hook が無効です(core.hooksPath が未設定か実在しない / Codex 利用不可)。

husky が有効化されていないため、保護ブランチへのコミットを止めるベンダー非依存の
層が存在しません。sandbox はネットワーク無効なので Codex 自身では復旧できません。

  npm ci        (または npx husky)

を実行してから再委託してください。当面は Sonnet fork にフォールバック。
MSG
    exit "$EX_UNAVAIL"
  fi
```

**置換後**:

```bash
  # ---- 5-3: git hook が有効か ----
  # 保護ブランチへのコミットを止めるベンダー非依存の層が存在しない状態で
  # workspace-write の委託をしない。
  #
  # 判定の実体はここに書かない。check-guard-integrity.sh の hooks-path サブコマンドに
  # 委ねる(隣の 5-4 が check-protected-branch.sh に委ねているのと同じ形)。
  # かつてここに独自の条件を書いていたため、縮退復帰検査の D1 が見ている
  # 「.husky 配下かどうか」が抜け、実在する無関係なディレクトリを指す
  # core.hooksPath を素通ししていた(#59)。
  #
  # 空振り条件:
  #   - husky を使わない構成(Python/Go 等)ではサブコマンドが何も見ずに 0 を返す。
  #     git hook 層そのものが存在しないので判定できない
  #   - スクリプトが無い / hooks-path を知らない旧版(rc が 0・1 以外)のときは
  #     警告だけ出して素通しする。同期ずれで全委託を止めないため。この欠落は
  #     CI の harness-integrity ジョブ(同スクリプトを必ず実行する)が別途赤くする
  GUARD_INTEGRITY=".claude/scripts/check-guard-integrity.sh"
  if [ -f "$GUARD_INTEGRITY" ]; then
    HOOKS_PATH_ISSUES="$(bash "$GUARD_INTEGRITY" hooks-path 2>/dev/null)"
    case $? in
      0) ;;
      1)
        cat >&2 <<MSG
delegate-codex: git hook が無効です(Codex 利用不可)。

$HOOKS_PATH_ISSUES

husky が有効化されていないため、保護ブランチへのコミットを止めるベンダー非依存の
層が存在しません。sandbox はネットワーク無効なので Codex 自身では復旧できません。

  npm ci        (または npx husky)

を実行してから再委託してください。当面は Sonnet fork にフォールバック。
MSG
        exit "$EX_UNAVAIL"
        ;;
      *)
        echo "delegate-codex: 警告 — $GUARD_INTEGRITY hooks-path を実行できませんでした(古い版の可能性)。git hook の検査をスキップします。" >&2
        ;;
    esac
  fi
```

> 実装メモ 1: ヒアドキュメントの区切りを `<<'MSG'` から `<<MSG` に変えている
> (`$HOOKS_PATH_ISSUES` を展開するため)。本文に他の `$` は無いので副作用は無い。
>
> 実装メモ 2: `HOOKS_PATH_ISSUES="$(...)"` の直後に `case $?` を置く。間に
> 別のコマンドを挟まないこと(`$?` が上書きされる)。
>
> 実装メモ 3: 旧 5-3 が定義していた変数 `HOOKS_PATH` は削除する。
> **削除前に `grep -n 'HOOKS_PATH' .claude/scripts/delegate-codex.sh` で
> 他に参照が無いことを確かめる**(無いはずだが、あれば残す)。

---

## §3: `AGENTS.md` §1-3

**置換前**(`### 1-3. git hook が有効か確かめる` の見出しから、`### 1-4.` の直前まで):

```markdown
### 1-3. git hook が有効か確かめる

```bash
git config --get core.hooksPath
```

`.husky/` があるのに、この値が**空** または**実在しないディレクトリ**を指している場合は、作業を始めないでください。husky が丸ごと無効 = 保護ブランチへのコミットを止めるベンダー非依存の層が存在しない状態です。sandbox はネットワーク無効なので自分では復旧できません。人間に報告して停止してください。

> 値を `.husky` と決め打ちで比較しないでください。**husky v9 が設定するのは `.husky/_` です。**(`delegate-codex.sh` の入口検査 5-3 と同じ判定です)
```

**置換後**:

```markdown
### 1-3. git hook が有効か確かめる

```bash
bash .claude/scripts/check-guard-integrity.sh hooks-path
```

**1 行でも出力されたら、作業を始めないでください。** husky が丸ごと無効 = 保護ブランチへのコミットを止めるベンダー非依存の層が存在しない状態です。sandbox はネットワーク無効なので自分では復旧できません。人間に報告して停止してください。

> **判定の実体はこのスクリプトだけにあります。**`core.hooksPath` を自分で読んで良し悪しを判断しないでください(`delegate-codex.sh` の入口検査 5-3 と Claude 復帰時の検収も同じものを呼びます)。**この値を自分で書き換えることも禁止です** — 検査は状態を確認するためのもので、復旧には `npm ci` が要ります。
```

---

## §4: `.codex/skills/degraded-mode-ticket/SKILL.md` 検査3

**置換前**(`### 検査3: git hook が有効か` の見出しから、`### 検査4:` の直前まで):

```markdown
### 検査3: git hook が有効か

```bash
git config --get core.hooksPath
```

`.husky/` が存在するのに、この値が**空** または**実在しないディレクトリ**を指している場合は、作業を始めずに人間へ報告して停止してください。husky が丸ごと無効 = 保護ブランチへのコミットを止めるベンダー非依存の層が存在しない状態です。sandbox はネットワーク無効なので、あなた自身では復旧できません(`npm ci` が必要)。

> 値を `.husky` と決め打ちで比較しないでください。**husky v9 が設定するのは `.husky/_` です。**

> **この値を自分で書き換えないでください。** 検査は「有効かどうかを確認する」ためのもので、
> 通らなければ人間に報告して停止します(復旧には `npm ci` が必要で、sandbox からはできません)。
```

**置換後**:

```markdown
### 検査3: git hook が有効か

```bash
bash .claude/scripts/check-guard-integrity.sh hooks-path
```

**1 行でも出力されたら、作業を始めずに人間へ報告して停止してください。** husky が丸ごと無効 = 保護ブランチへのコミットを止めるベンダー非依存の層が存在しない状態です。sandbox はネットワーク無効なので、あなた自身では復旧できません(`npm ci` が必要)。

> **判定の実体はこのスクリプトだけにあります。**`core.hooksPath` を自分で読んで良し悪しを判断しないでください(通常モードの委託経路 `delegate-codex.sh` 入口検査 5-3 も同じものを呼びます)。

> **この値を自分で書き換えないでください。** 検査は「有効かどうかを確認する」ためのもので、
> 通らなければ人間に報告して停止します(復旧には `npm ci` が必要で、sandbox からはできません)。
```

> 実装メモ: このファイルは `.prettierignore` の対象外 = prettier が整形する。
> 編集後に `npx prettier --check .codex/skills/degraded-mode-ticket/SKILL.md` を通し、
> 落ちたら `--write` で直す。

---

## §5: 実測(`verification.md` に表で記録する)

**後始末を必ず行う。** `git config` と `.claude/branch-policy.json` は検証で書き換えるため、
各シナリオの直後に元へ戻し、最後に残留 0 を確認する。

### §5-0: 事前

```bash
bash -n .claude/scripts/check-guard-integrity.sh
bash -n .claude/scripts/delegate-codex.sh
ORIG_HOOKS_PATH="$(git config --get core.hooksPath)"; echo "ORIG=$ORIG_HOOKS_PATH"
```

`ORIG_HOOKS_PATH` は `.husky/_` のはず。**この値をメモしてから先へ進む**
(以降のシナリオは同一シェルで続けて実行する)。

### §5-1: 平常時に誤爆しないこと(受け入れ条件 4)

| # | コマンド | 期待 |
| --- | --- | --- |
| V1 | `bash .claude/scripts/check-guard-integrity.sh; echo "rc=$?"` | 出力 0 行 / `rc=0` |
| V2 | `bash .claude/scripts/check-guard-integrity.sh hooks-path; echo "rc=$?"` | 出力 0 行 / `rc=0` |
| V3 | `bash .claude/scripts/check-guard-integrity.sh degraded; echo "rc=$?"` | 出力 0 行 / `rc=0` |
| V4 | `bash .claude/scripts/check-guard-integrity.sh bogus; echo "rc=$?"` | 使い方メッセージに `[degraded\|hooks-path]` / `rc=2` |

### §5-2: hooksPath の判定が 5-3 と D1 で一致すること(受け入れ条件 1)

```bash
git config core.hooksPath /tmp
```

| # | コマンド | 期待 |
| --- | --- | --- |
| V5 | `bash .claude/scripts/check-guard-integrity.sh hooks-path; echo "rc=$?"` | `.husky 配下以外(/tmp)` の 1 行 / `rc=1` |
| V6 | `bash .claude/scripts/check-guard-integrity.sh degraded` | 同じ 1 行を含む(D1 と文言が一致すること) |
| V7 | `bash .claude/scripts/delegate-codex.sh impl .steering/20260901-issue59-hookspath-unify/; echo "rc=$?"` | `git hook が無効です` + V5 と同じ 1 行 / `rc=3` |

> V7 は入口検査 0〜4(依存の導通プローブ・Codex CLI)を通ってから 5-3 に到達するため
> 数十秒かかる。5-3 で止まるので `codex exec` は起動せず、run record も作られない。
> **もし 5-3 より手前の検査で止まった場合**は、その終了コードと理由を
> `verification.md` に記録したうえで、V5・V6 の一致と 5-3 のコード読み合わせを
> 根拠として残す(判定の実体が 1 つである以上、一致は構造的に保証される)。

続けて、旧実装が素通ししていたことの対比も記録する:

| # | コマンド | 期待 |
| --- | --- | --- |
| V8 | `[ -d /tmp ] && echo "旧 5-3 の条件(空 or 実在しない)では素通し"` | 出力あり(旧実装が緩かったことの根拠) |

**後始末**:

```bash
git config core.hooksPath "$ORIG_HOOKS_PATH"
git config --get core.hooksPath   # => .husky/_
```

未設定・実在しないディレクトリの分岐も 1 回ずつ確認する(各回のあと必ず戻す):

| # | 手順 | 期待 |
| --- | --- | --- |
| V9 | `git config --unset core.hooksPath` → `hooks-path` | `core.hooksPath が未設定` / `rc=1` |
| V10 | `git config core.hooksPath .husky/does-not-exist` → `hooks-path` | `実在しないディレクトリ` / `rc=1` |

**後始末**: `git config core.hooksPath "$ORIG_HOOKS_PATH"`

### §5-3: ポリシー空洞化検査(受け入れ条件 2・3)

`.claude/branch-policy.json` を書き換えて確認する。**各シナリオの直後に
`git checkout -- .claude/branch-policy.json` で戻す。**

| # | 改変 | 期待 |
| --- | --- | --- |
| V11 | `protectedBranches` を `["develop"]` にする | `baseBranch(main)が protectedBranches に含まれていない` の 1 行 / `rc=1` |
| V12 | `allowedPrefixes` に `"main"` を足す | `保護ブランチ 'main' へ前方一致する接頭辞 'main' がある` の 1 行 / `rc=1` |
| V13 | `allowedPrefixes` に `""` を足す | 同種の指摘が出る(接頭辞は `''` と表示) |
| V14 | `protectedBranches` を `[]` にする | **`protectedBranches が空` の 1 行だけ**(判断6 の確認。2 行にならないこと) |
| V15 | V11 の状態で `hooks-path` を実行 | 出力 0 行 / `rc=0`(判断2 の確認) |

書き換えは `jq` で行う(手編集しない):

```bash
# V11
jq '.protectedBranches = ["develop"]' .claude/branch-policy.json > /tmp/bp.json && mv /tmp/bp.json .claude/branch-policy.json
# V12
jq '.allowedPrefixes += ["main"]' .claude/branch-policy.json > /tmp/bp.json && mv /tmp/bp.json .claude/branch-policy.json
# V13
jq '.allowedPrefixes += [""]' .claude/branch-policy.json > /tmp/bp.json && mv /tmp/bp.json .claude/branch-policy.json
# V14
jq '.protectedBranches = []' .claude/branch-policy.json > /tmp/bp.json && mv /tmp/bp.json .claude/branch-policy.json
```

### §5-4: 後始末の確認

```bash
git config --get core.hooksPath        # => .husky/_
git status --short                     # branch-policy.json が変更として出ないこと
bash .claude/scripts/check-guard-integrity.sh; echo "rc=$?"   # 0 行 / rc=0
```

---

## §6: `docs/template-dev/CHANGELOG.md`

日付見出し `## 2026-09-01` を(無ければ)ファイル先頭側に作り、既存の書式に合わせて
2 項目を追記する。**既存の書式(`[auto]` / `[manual]` の印の使い方)は
ファイルの直近エントリに合わせること。**

- `.claude/scripts/check-guard-integrity.sh` / `.claude/scripts/delegate-codex.sh` —
  `core.hooksPath` の判定を `check_hooks_path()` に集約し、`hooks-path` サブコマンドを
  追加。入口検査 5-3 がこれを呼ぶようになり、D1 と同じ厳しさ(`.husky` 配下かどうかまで)
  に揃った(#59)
- `.claude/scripts/check-guard-integrity.sh` — 検査 1 に「`baseBranch` が
  `protectedBranches` に含まれるか」「`allowedPrefixes` が保護ブランチ名に前方一致する
  接頭辞を持たないか」を追加。全層が正常動作したまま保護が消える 2 パターンを検出する(#59)
- `AGENTS.md` / `.codex/skills/degraded-mode-ticket/SKILL.md` — git hook 検査の散文から
  判定条件を消し、`check-guard-integrity.sh hooks-path` への導線に統一(#59)

## §7: 品質チェック

```bash
bash -n .claude/scripts/check-guard-integrity.sh
bash -n .claude/scripts/delegate-codex.sh
npm run lint && npm run typecheck && npm test && npm run format:check
```

---

## ⚠️ V7 実行時の注意(必読)

V7 は `delegate-codex.sh` を**本当に起動する**。**必ず `git config core.hooksPath /tmp` を
先に済ませてから実行すること。** 平常設定のまま実行すると 5-3 を通過し、5-4・5-5 を経て
`codex exec` が起動する = **委託禁止領域(`.claude/scripts/`)を Codex に渡す**ことになる
(出口検査が `status=failed` / `exit 2` で止めるが、run record が残り検収状態が汚れる)。

実行直前に次を確認する:

```bash
git config --get core.hooksPath   # => /tmp であること。.husky/_ なら V7 を実行しない
```

---

## 追補(検収 1 巡目の指摘反映)

### 判断9: 絶対パスの `core.hooksPath` は「検知しない」のではなく「注記を残す」

検収 Minor 1。`check_hooks_path()` の `case` は `.husky | .husky/*` の前方一致で見るため、
`.husky/_` を指す**絶対パス**が設定されていると「`.husky` 配下以外」と報告する。

**ロジックは変えない。** 理由:

- husky v9 が設定するのは常に相対パス(`.husky/_`)。絶対パスになる正規の経路が無い
- 誤検知したときに倒れる先が安全側 — 5-3 は `exit 3`(Sonnet fork へ退避)で、
  委託を止めるだけ。縮退復帰検査は 1 行報告するだけで、何も破壊しない
- 正しく直すにはパス正規化(`realpath` で `$ROOT/.husky` と比較)が要る。
  `realpath` の可搬性・シンボリックリンク・`$ROOT` 未取得時の分岐が増え、
  守る面より増える面のほうが大きい

ただし #58 の申し送り2(「増やさないという設計判断は、増やす提案が来る場所=コードに
痕跡を残す」)がそのまま当てはまる。**判断の痕跡をコメントで残す。**

### §8: `check_hooks_path()` にコメントを 3 行足す

**置換前**(`check_hooks_path()` のコメントブロック末尾、`# USES_HUSKY を参照するため、その決定より後にだけ呼ぶこと。` の行):

```
# USES_HUSKY を参照するため、その決定より後にだけ呼ぶこと。
```

**置換後**(この 1 行を 5 行にする):

```
# USES_HUSKY を参照するため、その決定より後にだけ呼ぶこと。
#
# 比較は前方一致で行い、絶対パスの正規化はしない。husky v9 が設定するのは常に相対パス
# (.husky/_)で、絶対パスになる正規の経路が無い。仮に絶対パスが設定されていれば
# 「.husky 配下以外」と報告するが、倒れる先は安全側(5-3 は exit 3 で委託を止めるだけ)。
# realpath による正規化は可搬性とシンボリックリンクの分岐を増やすので入れない(#59)。
```

**このブロック以外は一切変更しない。**

### §9: 品質チェック

```bash
bash -n .claude/scripts/check-guard-integrity.sh
npm run lint && npm run typecheck && npm test && npm run format:check
bash .claude/scripts/check-guard-integrity.sh; echo "rc=$?"          # 0 行 / rc=0
bash .claude/scripts/check-guard-integrity.sh hooks-path; echo "rc=$?" # 0 行 / rc=0
```
