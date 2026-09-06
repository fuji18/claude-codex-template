# 設計: 名乗らないコミットの逆向き検査(D0)

<!-- status: ready -->

## 決めたこと(実装者は設計判断をしない)

### 判断1: 検査の名前と置き場所は「D0」/ D2.5 の後・D3 の前

番号 `D0` は**実行順ではなく依存関係**を表す。D3 / D4 の対象選定(`--grep='Codex-authored'`)
そのものの前提を見る検査なので 0 番。物理的な位置は D2.5 の直後・D3 の直前に置く。

- D1 / D2 / D2.5 は「`.git` の状態 = 次に git を叩いた瞬間に発火するホスト実行ベクタ」の系統で、
  `degraded.md` は push 前にこれを回すよう指示している。ここを先頭のまま動かさない
- D0 / D3 / D4 は「縮退中コミット」の系統。その中では D0 が最初に来る

出力順は D1 → D2 → D2.5 → **D0** → D3 → D4 になる。番号が実行順と一致しない理由は
スクリプト内のコメントに 1 行書く。

### 判断2: `$DEGRADED_RANGE` の解決を D3 の中から共通ブロックへ引き上げる

D0 / D3 / D4 の 3 つが同じ範囲を使うため、範囲解決を D0 の前に移す。
`DELEGATE=".claude/scripts/delegate-codex.sh"` の代入は **D3 のブロックに残す**
(D3 だけが使うため)。**D3 / D4 のループ本体には一切手を入れない**(#58 の判断を維持)。

### 判断3: マージコミットは `--no-merges` で除く

保護ブランチ層は取り込み(`git merge` / `git pull`)を通す設計で、人間の取り込みコミットが
トレーラーを持たないのは正常。除かないと取り込みのたびに確実に誤検知する。

### 判断4: ベースが解決できず全履歴フォールバックに落ちたときは D0 をスキップし、理由を報告する

`DEGRADED_RANGE` が `HEAD`(全履歴)に落ちた場合、縮退モード以前の全コミットがトレーラーを
持たないのは当然で、そのまま回すと履歴全部が報告されて信号が消える。
`GUARD_DEGRADED_RANGE` による上書きは「テスト実行者が範囲を選んでいる」ので**解決済みとして扱う**。

スキップの報告にも `note` を使う(= `FOUND=1`)。D3 が
`--print-forbidden が委託禁止領域を返さない` を `note` で報告している先例に揃える。

### 判断5: 報告フォーマットは 1 コミット 1 行、`%h %s` を載せる

人間が `git show` を打つ前に切り分けられるよう、短縮 SHA と件名を出す。

## 実装(このとおりに置き換える)

対象: `.claude/scripts/check-guard-integrity.sh`

### 置換前(現状 305〜330 行付近)

```bash
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
```

### 置換後

```bash
# --- 縮退中コミットを見る検査(D0 / D3 / D4)の共通範囲 ---
#
# 検査範囲: 既定は branch-policy.json の baseBranch(origin/ 付きを優先)から HEAD まで。
# ベースが解決できないときは HEAD の全履歴を見る(実測 0.185s / 84 コミット)。
# GUARD_DEGRADED_RANGE で上書きできる(再現テスト用)。
#
# DEGRADED_BASE_RESOLVED は「範囲の始点が実在するベースで抑えられているか」を持つ。
# 全履歴フォールバックのときだけ no になり、D0 はその場合スキップする(理由は D0 のコメント)。
DEGRADED_RANGE="${GUARD_DEGRADED_RANGE:-}"
DEGRADED_BASE_RESOLVED=yes
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
  if [ -z "$DEGRADED_RANGE" ]; then
    DEGRADED_RANGE="HEAD"
    DEGRADED_BASE_RESOLVED=no
  fi
fi

# --- D0) 名乗らないコミットが範囲に紛れていないか ---
#
# D3 / D4 は対象コミットを `git log --grep='Codex-authored'` で選ぶ。このトレーラーは
# Codex 自身が付けるもの(AGENTS.md §5 / .codex/skills/degraded-mode-ticket/)なので、
# 付けなければ両検査の対象から外れる。トレーラーは「上限で殺されて codex-log.md を
# 書けなくても各コミットが自分で名乗る」という可用性のための識別手段であって、
# 敵対的な相手への防御ではない(codex-delegation-plan.md §2.3 の 3 条件)。
#
# モード C では定義上 Claude はコミットしない(.claude/rules/mode/degraded.md「復帰時の検収」)
# ため、範囲内の全コミットがトレーラーを持つのが正常。逆向きに「持たないコミット」を
# 列挙すれば、名乗らずに紛れ込んだものが出る。
#
# 番号が D0 なのは実行順ではなく依存関係を表す(D3 / D4 の対象選定そのものの前提を見る検査)。
# 物理的には D3 / D4 の直前に置く — その 2 つが対象外にしているコミットの存在を、
# 先に人間へ知らせるため。D1〜D2.5 を先頭のまま動かさないのは、あちらが
# 「次に git を叩いた瞬間に発火するベクタ」で push 前に読む必要があるから。
#
# 報告のみで停止しない(D1〜D4 と同じ方針。この検査はセキュリティ境界ではなく検出と報告)。
#
# 誤検知の条件:
#   - 縮退モードに入る前に人間が積んだコミットが範囲に含まれる場合(ベースに追い付いて
#     いないブランチで起きる)。復帰検収では git log の日付で切り分ける
#   - GUARD_DEGRADED_RANGE を再現テストで上書きした場合(範囲の意味が変わる)
#   - マージコミットは --no-merges で除いてある。保護ブランチ層は取り込み(git merge /
#     git pull)を通す設計で、人間の取り込みコミットがトレーラーを持たないのは正常
if [ "$DEGRADED_BASE_RESOLVED" = no ]; then
  # 全履歴に落ちた状態で回すと、縮退モード以前の全コミットが報告されて信号が消える。
  note "縮退中コミットの範囲を抑えるベース(branch-policy.json の baseBranch)が解決できないため、名乗らないコミットの検査(D0)をスキップした。GUARD_DEGRADED_RANGE で範囲を与えるか、git log --no-merges --grep='Codex-authored' --invert-grep で手元で確認すること"
else
  while IFS= read -r _entry; do
    [ -n "$_entry" ] || continue
    note "縮退中の範囲 $DEGRADED_RANGE に Codex-authored トレーラーを持たないコミットがある: $_entry。縮退中に Claude はコミットしない設計のため、誰が積んだものかを確認すること(このコミットは D3 / D4 の検査対象から外れている)"
  done < <(git log --no-merges --grep='Codex-authored' --invert-grep --format='%h %s' "$DEGRADED_RANGE" 2>/dev/null)
fi

# --- D3) 縮退中コミットの差分が委託禁止領域に触れていないか ---
#
# 縮退中のコミットは Codex-authored トレーラーで自分を名乗る(.codex/skills/
# degraded-mode-ticket/SKILL.md §3)。禁止領域の一覧は delegate-codex.sh が単一ソースで、
# --print-forbidden から受け取る(配列を複製しない)。検査範囲は上の共通ブロックで解決済み。
DELEGATE=".claude/scripts/delegate-codex.sh"

FORBIDDEN_LIST=""
```

**これ以降(`if [ -f "$DELEGATE" ]; then` 以降)は 1 文字も変更しない。**

## ドキュメント更新(3 箇所)

### (a) `.claude/rules/mode/degraded.md` 手順 1

現在の説明段落:

```
   縮退モードは `.git` が書き込み可能な唯一の経路で、`core.hooksPath` の書き換え・
   `.git/hooks/` への直書き・`.git/config` のホストコマンド実行ベクタ・禁止領域を触った
   `Codex-authored` コミット・**`Codex-authored` コミットによる `package.json` の変更**
   を検出する。
```

の直後(`**1 行でも出力されたら…**` の前)に次の 1 行を足す:

```
   **`Codex-authored` を名乗らないコミットが範囲に紛れていないか**も併せて見る(縮退中は
   Claude がコミットしない設計のため、名乗らないコミットは他の検査の対象外になっている)。
```

### (b) `docs/template-dev/codex-delegation-plan.md` §2.3 の 3 条件・条件 2

条件 2 の「理由」セルの末尾に次を足す(セル内なので `<br>` は使わず、同じ文の続きとして書く):

```
。**このトレーラーは可用性のための識別手段であって、敵対的な相手への防御ではない**(付けなければ復帰検査 D3 / D4 の対象から外れる)。名乗らないコミットの検出は `check-guard-integrity.sh degraded` の D0 が担う
```

### (c) `docs/template-dev/CHANGELOG.md`

既存の `## 2026-09-06` 見出しの**既存項目の先頭**に `[auto]` 項目を 1 つ足す
(日付見出しは新規に作らない。今日の日付見出しが既にあるため):

```
- `check-guard-integrity.sh degraded` に **D0(名乗らないコミットの検出)** を追加しました。
  縮退中の範囲に `Codex-authored` トレーラーを持たないコミットがあれば報告します(マージ
  コミットは除外、ベースが解決できないときはスキップして理由を報告)。既定サブコマンドの
  挙動は変えていないため CI の `harness-integrity` に影響はありません(Issue #84)。
```

区分は `[auto]`(取り込む側の作業はゼロ)。

## 変更しないもの

- D3 / D4 のループ本体(`git log --grep='Codex-authored'` の 2 箇所)
- 既定サブコマンド / `hooks-path` サブコマンドの経路(`[ "$SUBCOMMAND" = degraded ] || exit` より前)
- `.husky/*` / `AGENTS.md` / `.codex/`(スコープ外)
