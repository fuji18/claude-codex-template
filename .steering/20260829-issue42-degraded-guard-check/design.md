<!-- status: ready -->

# 設計: モード C(縮退)復帰時のガードレール健全性検査(Issue #42)

実装者へ: このファイルに書かれた内容だけで完結する。設計判断は残していない。
迷ったら**停止して報告**すること(推測で進めない)。

---

## §0. 設計判断(司令塔が確定済み。実装者は判断しない)

### 判断1: 別スクリプトではなく `check-guard-integrity.sh` に**サブコマンドで相乗り**する

- 「ガードレールが生きているか」の判定実体を 1 ファイルに保つ(`check-protected-branch.sh` /
  `harness-mode.sh` / `latest-steering.sh` と同じ思想)
- ただし**既定(引数なし)の挙動は一切変えない**。縮退検査は `degraded` サブコマンドでのみ走る
- 既定に混ぜてはいけない理由(コストではなく**誤検知**):
  CI の fresh checkout では `core.hooksPath` が未設定なのが正常で、`.git/hooks/` には
  git 同梱の sample しか無い。既定に入れると `harness-integrity` ジョブが恒常的に赤くなる
- git 履歴走査のコストは実測 0.185s(84 コミット / `git log --grep`)。手動実行のみなので問題にならない

### 判断2: 禁止領域の一覧は `delegate-codex.sh --print-forbidden` から取る

配列をコピーしない(スコープ外に明記)。`delegate-codex.sh` に一覧を出すだけのモードを足し、
`check-guard-integrity.sh` はその出力を読む。**汎用項目(`FORBIDDEN_PATHS`)と
`AGENTS.md` §4 マーカー内のプロジェクト固有パスの両方**を出す。

そのために `FORBIDDEN_PATHS` 配列とプロジェクト固有パスの抽出ブロックを、
**入口検査1(機密)より前**へ移動する。`--print-forbidden` は codex CLI が無くても
応答できる必要があるため(入口検査4 に到達してはいけない)。

## §1. 変更対象ファイル(6 つ)

| ファイル | 変更内容 |
| --- | --- |
| `.claude/scripts/delegate-codex.sh` | `--print-forbidden` モードの追加 + 定義ブロック 2 つの移動 |
| `.claude/scripts/check-guard-integrity.sh` | 引数解釈 + 縮退検査 D1〜D3 の追加 |
| `.claude/rules/mode/degraded.md` | 復帰手順に検査コマンドを 1 行追加 |
| `.codex/skills/degraded-mode-ticket/SKILL.md` | §5「やらないこと」に `.git/` 配下の改変を追加 |
| `docs/template-dev/CHANGELOG.md` | 既存の `## 2026-08-29` 見出しに追記 |
| `.steering/20260829-issue42-degraded-guard-check/verification.md` | 実測結果(§6) |

**これ以外のファイルを変更しない。**

---

## §2. `.claude/scripts/delegate-codex.sh`

### 2-1. 定義ブロック 2 つを上へ移動する(内容は変えない)

移動するのは次の 2 つ。**中身の行は 1 文字も変えない**(移動だけ)。

- **A**: 現在の 673〜713 行(`# ---------- 出口検査の対象(委託禁止領域)----------` の
  コメント塊 + `FORBIDDEN_PATHS=( ... )` 配列。`)` の行まで)
- **B**: 現在の 270〜309 行(`# ---------- 出口検査の対象(プロジェクト固有パス)の抽出 ----------`
  のコメント塊 + `PROJECT_FORBIDDEN_PATHS=()` から `unset _fp_start _fp_end` まで)

加えて `AGENTS="AGENTS.md"`(現在 239 行)を移動先へ持ち上げ、**239 行の代入は削除する**
(直後の `if [ ! -f "$AGENTS" ]` はそのまま残す)。

**移動先**: 入口検査0(`for _cmd in find grep sed head tail tr sort uniq; do ... done`)の
直後、`# ---------- 入口検査1: 機密ファイル ----------` の直前。並び順は次のとおり。

```
入口検査0(既存)
  ↓
A: 委託禁止領域の定義(FORBIDDEN_PATHS)
  ↓
AGENTS="AGENTS.md"
  ↓
B: プロジェクト固有パスの抽出(PROJECT_FORBIDDEN_PATHS)
  ↓
2-2 の --print-forbidden ブロック(新規)
  ↓
入口検査1: 機密ファイル(既存)
```

移動に伴うコメントの手当ては 2 箇所だけ:

- **A の見出し行**(現在の 673 行)を次に差し替える:

  ```bash
  # ---------- 委託禁止領域の定義(単一ソース) ----------
  #
  # 出口検査(§末尾)と --print-forbidden の両方がここを読む。入口検査より前に置くのは、
  # --print-forbidden が codex CLI 不在でも応答できる必要があるため(入口検査4 に到達しない)。
  ```

  以降の `#` コメント行(674〜712 相当)と配列本体はそのまま続ける。

- **A を抜いた跡地**(現在の `forbidden_files()` の直前)に、次の 4 行を置く:

  ```bash
  # ---------- 出口検査(委託禁止領域)のヘルパー ----------
  #
  # 判定対象の配列(FORBIDDEN_PATHS / PROJECT_FORBIDDEN_PATHS)はスクリプト冒頭で定義済み。
  # ここにはそれを使う関数だけを置く。
  ```

  B を抜いた跡地には何も残さない(前後の空行が二重にならないよう詰める)。

### 2-2. `--print-forbidden` モードの追加

**(a) `usage()`** — `impl` の行の下に 1 行足す:

```
  --print-forbidden                  委託禁止領域の一覧を 1 行 1 パスで出力(read-only)
```

**(b) モード検証の `case "$MODE" in`** — 受理リストに足す:

```bash
case "$MODE" in
  explore | review | impl | --print-forbidden) ;;
```

**(c) TARGET 必須チェック** — `--print-forbidden` は target を取らないので除外する:

```bash
if [ "$MODE" != "--print-forbidden" ] && [ -z "$TARGET" ]; then
```

**(d) 出力ブロック**(§2-1 で決めた位置に新規追加):

```bash
# ---------- --print-forbidden: 一覧だけを出力して終了 ----------
#
# 他スクリプト(check-guard-integrity.sh degraded)が禁止領域の判定に使う出力口。
# 配列を複製させないために置く。ここが単一ソースであり続ける。
# 出力は 1 行 1 パス(末尾 / はディレクトリ配下すべて)。
if [ "$MODE" = "--print-forbidden" ]; then
  printf '%s\n' "${FORBIDDEN_PATHS[@]}"
  if [ "${#PROJECT_FORBIDDEN_PATHS[@]}" -gt 0 ]; then
    printf '%s\n' "${PROJECT_FORBIDDEN_PATHS[@]}"
  fi
  exit 0
fi
```

**注意**: 冒頭の自己コピー exec / 入口検査0 はそのまま通す(通しても codex を必要としない)。
入口検査1 以降には到達させない。

---

## §3. `.claude/scripts/check-guard-integrity.sh`

### 3-1. 冒頭コメントの終了コード表を差し替える

```bash
# 出力: 壊れている項目を 1 行ずつ標準出力へ。装飾(⚠️ / ::error::)は呼び出し側の責任。
# 終了コード:
#   0 … 健全(または検査対象外の構成)
#   1 … 壊れている項目がある
#   2 … 使い方の誤り(未知のサブコマンド)
```

呼び出し元コメント(既存 3 行)の下に 1 行足す:

```bash
#   - .claude/rules/mode/degraded.md … モード C 復帰時の検収(degraded サブコマンド)
```

### 3-2. 引数解釈を追加する(`set -uo pipefail` の直後、`ROOT=` の前)

```bash
# ---------- サブコマンド ----------
#
# 引数なし … 既存の自壊検知(SessionStart hook / CI の harness-integrity が呼ぶ)
# degraded … 上記に加えて、モード C(縮退)復帰時のガードレール健全性検査
#
# 分けている理由はコストではなく誤検知。縮退検査は「作業ツリーの .git と縮退中コミット」を
# 見る検査で、CI の fresh checkout では core.hooksPath が未設定・.git/hooks/ が sample だけ
# なのが正常。既定に混ぜると harness-integrity ジョブが恒常的に赤くなる。
SUBCOMMAND="${1:-default}"
case "$SUBCOMMAND" in
  default | degraded) ;;
  *)
    echo "使い方: check-guard-integrity.sh [degraded]" >&2
    exit 2
    ;;
esac
```

### 3-3. セクション 2 の早期 exit を条件分岐に変える

変更前(1 行):

```bash
[ "$USES_HUSKY" = yes ] || exit "$FOUND"
```

変更後:

```bash
if [ "$USES_HUSKY" = no ] && [ "$SUBCOMMAND" != degraded ]; then
  exit "$FOUND"
fi
```

そのうえで、**既存のセクション 3・4 を `if [ "$USES_HUSKY" = yes ]; then ... fi` で囲む**
(husky を持たない構成では従来どおり実行しない)。中の行はインデントを 2 つ深くするだけで
内容は変えない。囲む範囲は `GUARD=".claude/scripts/check-protected-branch.sh"` を使う
セクション 3 の先頭コメントから、セクション 4 の `done`(for ループの終わり)まで。

末尾の `exit "$FOUND"` はそのまま最後に残す。

### 3-4. 縮退検査を追加する(セクション 4 の `fi` の後、末尾の `exit "$FOUND"` の前)

```bash
[ "$SUBCOMMAND" = degraded ] || exit "$FOUND"

# ============================================================
# 以下はモード C(縮退)復帰時の検査(degraded サブコマンドのみ)
# ============================================================
#
# 縮退モードは delegate-codex.sh を通らない唯一の経路で、入口検査も出口検査も掛からない。
# さらに .git を writable_roots に渡す設計のため、委託先自身が husky 層を無効化できる。
# 復帰時の検収でここを機械的に確かめる(根拠: docs/template-dev/codex-delegation-plan.md §2.3)。

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

# --- D2) .git/hooks/ に直書きされたフックが無いか ---
#
# core.hooksPath が .husky/_ を指している間 .git/hooks/ は参照されないが、hooksPath を
# 戻す 1 行と組み合わせれば有効になる。置かれていること自体を異常として扱う。
# git 同梱の *.sample と、実行権の無いファイルは除く。
GIT_HOOKS_DIR="$(git rev-parse --git-path hooks 2>/dev/null || true)"
if [ -n "$GIT_HOOKS_DIR" ] && [ -d "$GIT_HOOKS_DIR" ]; then
  while IFS= read -r _h; do
    [ -n "$_h" ] || continue
    note "$_h が直書きされている(git 同梱の *.sample 以外の実行可能フック)。core.hooksPath を戻すだけで .husky/ を迂回できる状態"
  done < <(find "$GIT_HOOKS_DIR" -maxdepth 1 -type f -perm -u+x ! -name '*.sample' 2>/dev/null | LC_ALL=C sort)
fi

# --- D3) 縮退中コミットの差分が委託禁止領域に触れていないか ---
#
# 縮退中のコミットは Codex-authored トレーラーで自分を名乗る(.codex/skills/
# degraded-mode-ticket/SKILL.md §3)。禁止領域の一覧は delegate-codex.sh が単一ソースで、
# --print-forbidden から受け取る(配列を複製しない)。
#
# 検査範囲: 既定は branch-policy.json の baseBranch(origin/ 付きを優先)から HEAD まで。
# ベースが解決できないときは HEAD の全履歴を見る(実測 0.185s / 84 コミット)。
# GUARD_DEGRADED_RANGE で上書きできる(再現テスト用)。
DELEGATE=".claude/scripts/delegate-codex.sh"

DEGRADED_RANGE="${GUARD_DEGRADED_RANGE:-}"
if [ -z "$DEGRADED_RANGE" ]; then
  BASE=""
  if [ -f "$POLICY" ] && command -v jq >/dev/null 2>&1; then
    BASE="$(jq -r '.baseBranch // empty' "$POLICY" 2>/dev/null || true)"
  fi
  if [ -n "$BASE" ]; then
    for _ref in "origin/$BASE" "$BASE"; do
      if git rev-parse --verify --quiet "$_ref" >/dev/null 2>&1; then
        DEGRADED_RANGE="$_ref..HEAD"
        break
      fi
    done
  fi
  [ -n "$DEGRADED_RANGE" ] || DEGRADED_RANGE="HEAD"
fi

FORBIDDEN_LIST=""
if [ -f "$DELEGATE" ]; then
  FORBIDDEN_LIST="$(bash "$DELEGATE" --print-forbidden 2>/dev/null || true)"
fi

if [ -z "$FORBIDDEN_LIST" ]; then
  note "$DELEGATE --print-forbidden が委託禁止領域を返さない。縮退中コミットの差分検査が行えない"
else
  # 一覧の各行を Codex-authored コミットの変更パスに当てる。
  # 末尾 /** /* /  はディレクトリ配下すべて、それ以外は完全一致(delegate-codex.sh の
  # forbidden_files() と同じ解釈)。
  is_forbidden() {
    local _path="$1" _p _d
    while IFS= read -r _p; do
      [ -n "$_p" ] || continue
      case "$_p" in
        */\*\* | */\*)
          _d="${_p%/*}"
          case "$_path" in "$_d"/*) return 0 ;; esac
          ;;
        */) case "$_path" in "$_p"*) return 0 ;; esac ;;
        *) [ "$_path" = "$_p" ] && return 0 ;;
      esac
    done <<EOF_FORBIDDEN
$FORBIDDEN_LIST
EOF_FORBIDDEN
    return 1
  }

  while IFS= read -r _sha; do
    [ -n "$_sha" ] || continue
    while IFS= read -r _f; do
      [ -n "$_f" ] || continue
      is_forbidden "$_f" &&
        note "縮退中のコミット $_sha が委託禁止領域 $_f を変更している。マージ前に内容を確認すること(delegate-codex.sh の出口検査が掛かっていない経路)"
    done < <(git show --pretty=format: --name-only "$_sha" 2>/dev/null)
  done < <(git log --grep='Codex-authored' --format='%h' "$DEGRADED_RANGE" 2>/dev/null)
fi
```

**実装上の注意**:

- `is_forbidden` のヒアドキュメント終端は `EOF_FORBIDDEN`。ファイル内で衝突しない語を使うこと
- `note()` は既存の関数(標準出力に 1 行 + `FOUND=1`)。新しい出力形式を作らない
- `$POLICY` は既存変数(`.claude/branch-policy.json`)。再定義しない
- `git show --pretty=format: --name-only` はマージコミットで空を返すが、縮退中コミットは
  マージではないので問題にならない

---

## §4. `.claude/rules/mode/degraded.md`

`### 復帰時の検収(§2.3)` の番号付きリストを次に差し替える(**1 を新設して 2〜5 に繰り下げ**)。

```markdown
### 復帰時の検収(§2.3)

1. **ガードレールの健全性を機械検査する(最初にこれを回す)**

   ```bash
   bash .claude/scripts/check-guard-integrity.sh degraded && echo "ガードレール健全"
   ```

   縮退モードは `.git` が書き込み可能な唯一の経路で、`core.hooksPath` の書き換え・
   `.git/hooks/` への直書き・禁止領域を触った `Codex-authored` コミットを検出する。
   **1 行でも出力されたら、その内容を人間に報告してから検収を続ける。**
2. `git log --grep 'Codex-authored' --oneline` で縮退中のコミットを特定する
3. `.steering/[dir]/codex-log.md` を読む。**「設計判断」欄は必ず回収する**(`design.md` に無い判断が下されている可能性がある)
4. 通常フローの検収(`/check` + `code-reviewer`)を回す
5. PR を作る(縮退中は Codex が PR を作らない設計 = キューとして設計されている)
```

末尾の「根拠:」行は変更しない。

---

## §5. `.codex/skills/degraded-mode-ticket/SKILL.md`

`## 5. やらないこと` の表に **1 行追加**する(`**`.harness/mode` の書き換え**` の行の下)。

```markdown
| **`.git/` 配下の改変**           | `core.hooksPath` の書き換え・`.git/hooks/` への直書きは、`.husky/` のガードレールを無効化します。`.git` への書き込み許可は**コミットを積むためだけ**に渡されています。Claude 復帰時に `check-guard-integrity.sh degraded` が機械的に検出します |
```

あわせて `### 検査3: git hook が有効か` の引用ブロック(`> 値を `.husky` と決め打ちで…`)の
直後に、次の 1 行を追加する。

```markdown
> **この値を自分で書き換えないでください。** 検査は「有効かどうかを確認する」ためのもので、
> 通らなければ人間に報告して停止します(復旧には `npm ci` が必要で、sandbox からはできません)。
```

---

## §6. 実測(verification.md に記録する)

`.steering/20260829-issue42-degraded-guard-check/verification.md` を新規作成し、
次の 5 シナリオを**使い捨て git リポジトリ**で実行した結果(コマンドと出力)を貼る。

使い捨てリポジトリの作り方(このリポジトリを汚さないこと):

```bash
WORK="$(mktemp -d)"
git -C "$WORK" init -q
cp -r .claude .husky .codex AGENTS.md package.json "$WORK"/ 2>/dev/null
cd "$WORK" && git add -A && git commit -q -m "chore: baseline" && cd -
```

| # | シナリオ | 期待 |
| --- | --- | --- |
| 1 | 何も壊れていない状態で `check-guard-integrity.sh degraded` | 出力なし / exit 0 |
| 2 | `git config core.hooksPath .git/hooks` に書き換え | `core.hooksPath が .husky 配下以外` を出力 / exit 1 |
| 3 | `.git/hooks/pre-commit` を実行可能で直書き | その行を出力 / exit 1。**`.git/hooks/pre-commit.sample` のままでは鳴らない**ことも確認 |
| 4 | `AGENTS.md` を変更した `Codex-authored: true` コミットを積む | `委託禁止領域 AGENTS.md を変更している` を出力 / exit 1 |
| 5 | 禁止領域外(例 `README.md`)だけの `Codex-authored` コミット | 出力なし / exit 0 |

加えて**このリポジトリ**で次の 2 つを確認して記録する。

- `bash .claude/scripts/check-guard-integrity.sh` (引数なし)が従来どおり無出力 / exit 0
- `bash .claude/scripts/delegate-codex.sh --print-forbidden` が 10 行(汎用項目)以上を出力し、
  **codex CLI の有無にかかわらず** exit 0 で返る
- `bash .claude/scripts/check-guard-integrity.sh bogus` が使い方を stderr に出して exit 2

---

## §7. CHANGELOG(`docs/template-dev/CHANGELOG.md`)

**既存の `## 2026-08-29` 見出しの中**に追記する(新しい日付見出しは作らない。今日は 2026-08-29)。
`## 2026-08-29` 直下の既存本文の**末尾**、`## 2026-08-27` の直前に置く。

```markdown
**モード C(縮退)復帰時のガードレール健全性を機械検査するようにした(Issue #42)。** 縮退モードは `delegate-codex.sh` を通らない唯一の経路で、入口検査も出口検査も掛かりません。さらに `.git` を `writable_roots` に渡す設計のため、**委託先自身が `core.hooksPath` を書き換えて husky 層を無効化できる**状態でした。復帰時検収に機械的な確認ステップが無く、人間が読み飛ばせば検出機会が消えます。

- **[auto]** **`check-guard-integrity.sh` に `degraded` サブコマンドを追加した**(#42)。`core.hooksPath` が `.husky` 配下を指しているか / `.git/hooks/` に直書きフックが無いか / `Codex-authored` コミットの差分が委託禁止領域に触れていないかを検査します。**引数なしの既存呼び出し(SessionStart hook / CI の `harness-integrity`)の挙動は変わりません**(CI の fresh checkout では `core.hooksPath` 未設定が正常なため、既定に混ぜると恒常的に赤くなる)
- **[auto]** **`delegate-codex.sh` に `--print-forbidden` を追加した**(#42)。委託禁止領域の一覧を 1 行 1 パスで出力するだけの read-only モードです。`check-guard-integrity.sh degraded` がこれを読むことで、パス一覧の単一ソースが `delegate-codex.sh` のまま保たれます(配列は複製していません)。あわせて `FORBIDDEN_PATHS` の定義位置を入口検査より前へ移しました(codex CLI が無くても一覧を引けるようにするため)
- **[auto]** `.claude/rules/mode/degraded.md` の復帰手順の先頭に上記コマンドを組み込み、`.codex/skills/degraded-mode-ticket/SKILL.md` §5 に「`.git/` 配下を改変しない」を明記しました
```

---

## §8. 完了条件

- `npm run lint` 相当(`/check`)が通る
- §6 の 5 シナリオ + 3 確認がすべて期待どおりで、`verification.md` に記録されている
- `tasklist.md` がすべて `- [x]`
