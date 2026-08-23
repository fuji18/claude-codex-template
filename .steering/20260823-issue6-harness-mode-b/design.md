<!-- status: ready -->

# 設計: 段階4 — モード B(節約)

対象 Issue: #6 / 根拠: `docs/template-dev/codex-delegation-plan.md` §2.1 / §2.2 / §2.6 / §3.4 / §12.2

## 0. 全体像

| # | 成果物 | 種別 |
| --- | --- | --- |
| 1 | `.claude/scripts/harness-mode.sh` | **新規** |
| 2 | `.claude/scripts/delegate-codex.sh` のモード読み取りを 1 に差し替え | 変更 |
| 3 | `.claude/scripts/codex-run.sh` に `pending` サブコマンド追加 | 変更 |
| 4 | `.claude/rules/mode/econ.md` / `.claude/rules/mode/degraded.md` | **新規** |
| 5 | `.claude/hooks/session-start.sh` にモード注入と未検収注入を追加 | 変更 |
| 6 | `.claude/commands/add-feature.md` / `fix-issue.md` の PR 手順に draft 分岐 | 変更 |
| 7 | `README.md` のディレクトリ説明 | 変更 |
| 8 | `docs/template-dev/codex-delegation-plan.md` の §11 段階4 行と完了記録 | 変更 |
| 9 | `.harness/decisions.jsonl` に測定方法とベースラインを追記 | 変更(追記のみ) |

**設計の芯**: モードの読み手は Claude と Codex の 2 系統ある。**判定の実体を 1 ファイル(`harness-mode.sh`)に集約する**ことを要件とする(`check-protected-branch.sh` / `latest-steering.sh` と同じ既存の作法)。どちらかだけが古い規則で動いても誰も気づかない、という事故がこのリポジトリでは既に 2 回起きている。

---

## 1. `.claude/scripts/harness-mode.sh`(新規)

**全文をこのとおり作る。**

```bash
#!/bin/bash
# ハーネスモード(normal / econ / degraded)の唯一の読み取り経路。
#
#   bash .claude/scripts/harness-mode.sh
#     → normal / econ / degraded のいずれか 1 行を stdout に出す(必ず有効値)
#
# 読む順序は固定する(§2.2): CODEX_HARNESS_MODE > .harness/mode > normal。
# 読み手が 2 系統(Claude の SessionStart / Codex 側の delegate-codex.sh・AGENTS.md)
# あるため、判定の実体をここに集約する。どちらかだけが古い規則で動いても
# 誰も気づかないのが、このリポジトリで繰り返し起きている事故の形。
#
# 不正な値は normal に倒し、警告は stderr に出す(呼び出し側の stdout を汚さない)。
# 終了コードは常に 0。モードの読み取りで作業が止まる方が害が大きい。
#
# 参照: docs/template-dev/codex-delegation-plan.md §2.2
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[ -n "$ROOT" ] && cd "$ROOT" 2>/dev/null

MODE="${CODEX_HARNESS_MODE:-}"
if [ -z "$MODE" ] && [ -f .harness/mode ]; then
  # 前後の空白と改行をすべて落とす。人間が echo で書くファイルなので、
  # 改行の有無や末尾スペースに挙動を依存させない。
  MODE="$(tr -d '[:space:]' <.harness/mode 2>/dev/null || true)"
fi
[ -n "$MODE" ] || MODE="normal"

case "$MODE" in
  normal | econ | degraded) ;;
  *)
    echo "⚠️ ハーネスモードの値が不正: '$MODE'(.harness/mode か CODEX_HARNESS_MODE)。normal として扱う。有効値: normal / econ / degraded" >&2
    MODE="normal"
    ;;
esac

printf '%s\n' "$MODE"
exit 0
```

**実行権限**: 作成後に `chmod +x` と **`git update-index --chmod=+x .claude/scripts/harness-mode.sh`** の両方を行う。ディスク側だけでは `core.fileMode=false` の環境で index に反映されず、CI の `harness-integrity` が落ちる(既知の踏み方。SessionStart hook が警告する)。

---

## 2. `.claude/scripts/delegate-codex.sh` の差し替え

現在の `# ---------- ハーネスモード ----------` ブロック(`HMODE="${CODEX_HARNESS_MODE:-}"` から `[ -n "$HMODE" ] || HMODE="normal"` までの 5 行)を、次に置き換える。**コメントブロックの見出し行(`# ---------- ハーネスモード ----------`)は残す。**

```bash
# 読む順序は固定する: プロンプト経由の上書き > .harness/mode > normal。
# 判定の実体は harness-mode.sh に集約する(SessionStart hook と同じ結果になることが要件)。
# AGENTS.md 側にも同じ順序を書いてある(モード C はこの経路を通らないため)。
# スクリプトが消えていても委託自体は止めない(normal に倒す)。
HMODE=""
if [ -f .claude/scripts/harness-mode.sh ]; then
  HMODE="$(CODEX_HARNESS_MODE="${CODEX_HARNESS_MODE:-}" bash .claude/scripts/harness-mode.sh 2>/dev/null || true)"
fi
[ -n "$HMODE" ] || HMODE="normal"
```

- `CODEX_HARNESS_MODE=... bash ...` と明示的に渡すのは、呼び出し元が `export` していない場合にも上書きを効かせるため
- 挙動の差分は「不正値が `normal` に倒れるようになる」ことだけ。従来は不正値がそのまま run record の `harnessMode` に入っていた

---

## 3. `.claude/scripts/codex-run.sh` に `pending` を追加

### 3.1 なぜ hook に直書きしないか

§3.4 は hook に 15 行のインライン実装を例示しているが、**採用しない**。`list` と `pending` は同じ判定(未検収・プロセス不在・別ブランチ)を持つため、2 箇所に散らすと片方だけが古くなる。`rec_field` / `find_record` の既存資産もここにある。

### 3.2 usage の更新

`usage()` のヒアドキュメントに 1 行足す(`list` の直後):

```
  pending               SessionStart 注入用に未検収 record を整形して出す(無ければ何も出さない)
```

### 3.3 `cmd_pending` の実装

`cmd_list` の直後に次の関数を追加する。

```bash
# SessionStart hook 用。未検収 record を「現在地」ブロックに貼れる形で出す。
# 見つからなければ**何も出さない**(list と違い「ありません」も出さない。
# 注入先はセッションのコンテキストであり、無い情報に行を使わない)。
cmd_pending() {
  local _f _id _mode _status _branch _steering _target _summary _log _pid _started _ended
  local _cur_branch _now _start_epoch _stale _out="" _count=0

  [ -d "$RUN_DIR" ] || exit 0

  _cur_branch="$(git branch --show-current 2>/dev/null || true)"
  _now="$(date -u +%s 2>/dev/null || echo 0)"

  for _f in "$RUN_DIR"/*.json; do
    [ -f "$_f" ] || continue
    [ "$(rec_field "$_f" accepted)" = "true" ] && continue

    _id="$(rec_field "$_f" id)"
    _mode="$(rec_field "$_f" mode)"
    _status="$(rec_field "$_f" status)"
    _branch="$(rec_field "$_f" branch)"
    _steering="$(rec_field "$_f" steering)"
    _target="$(rec_field "$_f" target)"
    _summary="$(rec_field "$_f" summary)"
    _log="$(rec_field "$_f" log)"
    _started="$(rec_field "$_f" startedAt)"
    _ended="$(rec_field "$_f" endedAt)"

    # status=running は信用しすぎない(§3.4)。スクリプトが終了時に書く値なので、
    # レート上限・OOM・端末切断で殺されると running のまま残る。
    if [ "$_status" = "running" ]; then
      _pid="$(rec_field "$_f" pid)"
      if [ -z "$_pid" ] || ! kill -0 "$_pid" 2>/dev/null; then
        _status="running(プロセス不在 = 異常終了の可能性。tasklist.md と git diff で実態を確認せよ)"
      fi
    fi

    # 7 日以上前の未検収は「古い記録」として調子を落とす(§3.4)。消さずに、
    # 現役の警告と区別する。毎セッション同じ警告が出続けると読まれなくなる。
    _stale=0
    if [ "$_now" != "0" ] && [ -n "$_started" ]; then
      _start_epoch="$(date -u -d "$_started" +%s 2>/dev/null || true)"
      if [ -n "$_start_epoch" ] && [ "$((_now - _start_epoch))" -gt 604800 ]; then
        _stale=1
      fi
    fi

    _count=$((_count + 1))
    _out="${_out}  - ${_id} / mode=${_mode} / 対象 ${_steering:-$_target}"
    [ "$_stale" = "1" ] && _out="${_out}(古い記録: 7 日以上前)"
    if [ -n "$_branch" ] && [ -n "$_cur_branch" ] && [ "$_branch" != "$_cur_branch" ]; then
      _out="${_out} [別ブランチ: ${_branch}]"
    fi
    _out="${_out}"$'\n'"    状態: ${_status}${_started:+(${_started}${_ended:+ → ${_ended}})}"$'\n'
    _out="${_out}    サマリー: ${_summary:-なし}"$'\n'
    _out="${_out}    ログ: ${_log:-なし}"$'\n'

    # 行動を促すのは「今のブランチの・古くない」委託だけにする(§3.4)。
    # 別ブランチ・古い記録にまで手順を出すと、警告そのものが読み飛ばされる。
    if [ "$_stale" = "0" ] && { [ -z "$_branch" ] || [ -z "$_cur_branch" ] || [ "$_branch" = "$_cur_branch" ]; }; then
      _out="${_out}    → 検収を通したら \`bash .claude/scripts/codex-run.sh accept ${_id}\`"$'\n'
    fi
  done

  [ "$_count" -eq 0 ] && exit 0

  echo "- Codex 委託(未検収): ${_count} 件"
  printf '%s' "$_out"
  exit 0
}
```

### 3.4 ディスパッチ

末尾のサブコマンド分岐(`case` 文)に `pending` を足す。`list` の隣に置く:

```bash
  pending) cmd_pending ;;
```

※ `case` 文の正確な現行形は実装時にファイル末尾を読んで合わせること。既存の分岐の書き方に揃える。

### 3.5 モード B での「検収」の読み替え

モード B では `/check` も `code-reviewer` も回さない。上の `→` 行は「検収を通したら accept」とだけ書き、**検収の中身をモード別に分岐させない**(hook 側で econ のルールが同時に注入され、そちらが「検収は CI に委ねる」と定義する)。分岐を足すと 2 箇所が独立に古くなる。

---

## 4. `.claude/rules/mode/*.md`(新規)

### 4.1 置き場所の判断

- `.claude/rules/lead/` に常設しない: そこは**毎セッション必ず注入される**。既定モード(`normal`)のセッションでも数十行を毎回払うことになり、モード B が節約しようとしているコンテキストそのものを食う
- `.claude/rules/`(直下)に置かない: そこは CLAUDE.md が `@` インポートし、**全サブエージェントに載る**。モードの作法は司令塔だけの関心事
- したがって **`.claude/rules/mode/` を新設し、hook が `normal` 以外のときだけ該当ファイルを注入する**
- `.claude/rules/` はマニフェストの `owned` 配下なので、**`template-manifest.json` の変更は不要**

### 4.2 `.claude/rules/mode/econ.md`(全文)

```markdown
<!-- テンプレート所有ファイル: /sync-template で上書きされます。 -->
<!-- SessionStart hook が .harness/mode = econ のときにのみ注入します。サブエージェントには載りません。 -->

## 現在のハーネスモード: B(節約 / `.harness/mode` = `econ`)

Claude の週枠を温存する運用。**モードの切替を宣言するのは人間**(`/usage` の残枠を見て判断する)。Claude は自動で降格も復帰もしないし、`.harness/mode` を自分で書き換えない。

### 司令塔の作法

1. **`design.md` を書き切り、完成マーカーを `<!-- status: ready -->` にしたらセッションを閉じる。** 検収まで待たない
2. **`/check` も `code-reviewer` も回さない。** 機械的検証は CI に、スペック整合は枠が戻ってからの一括レビューに委ねる
3. 実装委託(`delegate-codex.sh impl`)は**人間がターミナルから叩く**。Claude セッションを開けたまま待たない
4. 委託後の `/commit` → `push` → **draft PR** は、最小コンテキストの新セッションで行う

検収を飛ばした分の担保は、ベンダー中立ガードレール(`.husky/*`)と CI(`ci.yml`)。

### PR は draft で積み、マージしない

- **draft は作法ではなく節約の実体。** `claude-code-review.yml` は `draft == false` のときだけ走るため、draft のままなら Claude レビューが起動しない。非 draft で開くと、このモードが温存しようとしているまさにその枠を PR ごとに消費する
- `ci.yml` の `pull_request` トリガは draft でも発火する。**機械的検証は受けたままレビューだけを止められる**
- PR を作るときは **`--draft` を必ず付ける**。PR ボディの「検証」節には `/check` 済みのチェックを付けず、**「モード B のため検収未実施(CI に委ねる)」と明記する**
- 積んだ PR は**マージしない**。枠が戻ったら人間が `gh pr ready [番号]` で切り替える → `types: [opened, ready_for_review]` により**レビューが自動起動する**(手動で呼び直す必要はない)
- 急ぐ場合の例外は**ユーザーが明示的に判断する**。司令塔の裁量で非 draft を既定にしない

### 手順の順序を逆にしない

`ci.yml` のトリガは `push: [main, develop]` と `pull_request` だけで、**作業ブランチへの push だけでは CI は走らない**。「CI が緑なら PR を作る」は因果が逆で、**draft PR を作って初めて CI が動く**。このモードは検収を CI に預ける設計なので、取り違えると検収が丸ごと空振りする。

根拠: `docs/template-dev/codex-delegation-plan.md` §2.1 / §2.6 / §12.2
```

### 4.3 `.claude/rules/mode/degraded.md`(全文)

```markdown
<!-- テンプレート所有ファイル: /sync-template で上書きされます。 -->
<!-- SessionStart hook が .harness/mode = degraded のときにのみ注入します。サブエージェントには載りません。 -->

## 現在のハーネスモード: C(縮退 / `.harness/mode` = `degraded`)

**このモードは「Claude が動かない期間」のために宣言されたもの。** あなた(Claude)が起動しているということは、次のどちらかが起きている:

1. **枠が回復した** → 縮退中に Codex が積んだ成果を検収し、PR に合流させる(下記)
2. **モードの戻し忘れ** → 同じ手順で未検収の成果が無いことを確かめる

どちらの場合も、合流後に**人間へ `.harness/mode` を `normal` か `econ` に戻すよう促す**。**`.harness/mode` は Claude が書き換えない**(切替の宣言は人間の担当)。

### 復帰時の検収(§2.3)

1. `git log --grep 'Codex-authored' --oneline` で縮退中のコミットを特定する
2. `.steering/[dir]/codex-log.md` を読む。**「設計判断」欄は必ず回収する**(`design.md` に無い判断が下されている可能性がある)
3. 通常フローの検収(`/check` + `code-reviewer`)を回す
4. PR を作る(縮退中は Codex が PR を作らない設計 = キューとして設計されている)

根拠: `docs/template-dev/codex-delegation-plan.md` §2.3 / §12.3
```

---

## 5. `.claude/hooks/session-start.sh` の改訂

### 5.1 追加位置

現行の構成は `1) 依存 → 自壊検知 → 4) lead ルール注入 → 2) serena 検知 → 3) 現在地`。**`4) 司令塔専用ルールの注入` ブロックの直後、`2) serena` の直前**に次の 2 ブロックを追加する。

### 5.2 モード注入(全 source)

```bash
# --- 5) ハーネスモードの注入(全 source: startup / resume / clear / compact) ---
# モードは推測させない(§2.2)。単一ソースは .harness/mode で、読み取りの実体は
# harness-mode.sh に集約してある(Codex 側 = delegate-codex.sh と同じ結果になることが要件)。
# normal のときは何も出さない: 既定モードのセッションで毎回数十行を注入するのは、
# モード B が節約しようとしているコンテキストそのものを食う。
HMODE="normal"
if [ -f .claude/scripts/harness-mode.sh ]; then
  # 不正値の警告は stderr に出る。stderr はコンテキストに載らないため、拾って stdout に回す。
  HMODE_WARN="$(bash .claude/scripts/harness-mode.sh 2>&1 >/dev/null || true)"
  HMODE="$(bash .claude/scripts/harness-mode.sh 2>/dev/null || echo normal)"
  [ -n "$HMODE_WARN" ] && printf '%s\n' "$HMODE_WARN"
fi
[ -n "$HMODE" ] || HMODE="normal"

if [ "$HMODE" != "normal" ] && [ -f ".claude/rules/mode/$HMODE.md" ]; then
  echo "# ハーネスモード(SessionStart 注入 / 切替を宣言するのは人間です)"
  echo
  cat ".claude/rules/mode/$HMODE.md"
  echo
fi
```

### 5.3 未検収委託の取得(全 source)

```bash
# --- 6) Codex 委託の未検収(§3.4) ---
# 判定の実体は codex-run.sh に集約する(list と同じ規則になることが要件)。
# 「現在地」ブロックが出る source ではその中に混ぜ、出ない source(通常の startup)では
# 単独の見出しで出す。モード B の実運用では「司令塔がセッションを閉じる → 人間が委託 →
# 新セッションを開く」が既定経路であり、再開が /clear とは限らない。
CODEX_PENDING=""
if [ -f .claude/scripts/codex-run.sh ]; then
  CODEX_PENDING="$(bash .claude/scripts/codex-run.sh pending 2>/dev/null || true)"
fi
```

### 5.4 現在地ブロックへの差し込み

現行の `3) resume / clear 時の現在地オリエンテーション` の中、**`in-progress チケット` を出す `if command -v gh ...` ブロックの直後**(= `LATEST_STEERING=` の行の直前)に 1 行入れる:

```bash
  [ -n "$CODEX_PENDING" ] && printf '%s\n' "$CODEX_PENDING"
```

### 5.5 現在地ブロックが出ない source への `else`

現行の `if [ "$SOURCE" = "resume" ] || ... ; then ... fi` の `fi` を、次の `else` 付きに変える:

```bash
else
  # 現在地ブロックが出ない source(通常の startup)でも、未検収委託だけは出す。
  # 委託を挟んだ再開は /clear とは限らない(モード B ではセッションを閉じるのが既定)。
  if [ -n "$CODEX_PENDING" ]; then
    echo "## Codex 委託(未検収)"
    printf '%s\n' "$CODEX_PENDING"
  fi
fi
```

### 5.6 CI の自壊検知との整合(§8.1)

- 新規スクリプト `harness-mode.sh` は `.claude/scripts/*.sh` のループに自動で入るため、`ci.yml` の `harness-integrity` は**変更不要**(実行権限と `bash -n` が自動で検査される)
- ただし **git index 上の実行権限**(`100755`)を忘れると CI が落ちる。§1 の `git update-index --chmod=+x` を必ず行う
- `check-guard-integrity.sh`(husky ↔ 共有スクリプトの検査)は**触らない**。あれは保護ブランチ強制層の検査であって、オリエンテーション層は対象外

---

## 6. コマンドの改訂(draft PR)

### 6.1 `.claude/commands/add-feature.md`

**ステップ6(検証)の見出し直後**に次の引用ブロックを足す(番号付きリストの 1 の前):

```markdown
> **ハーネスモードが `econ`(モード B)のときは、このステップを丸ごと飛ばしてステップ7へ進む。** `/check` も `code-reviewer` も回さず、機械的検証は CI に、スペック整合は枠が戻ってからの一括レビューに委ねる(§2.6)。モードは `bash .claude/scripts/harness-mode.sh` で確認する。
```

**ステップ8 の 2(GitHub PR を作成する)** の箇条書きのうち「ボディ」の項目の直後(コード例の直前)に、次を足す:

```markdown
   - **ハーネスモードが `econ` の場合は `--draft` を付ける**(`bash .claude/scripts/harness-mode.sh` で確認する)。draft は作法ではなく節約の実体で、`claude-code-review.yml` は `draft == false` のときしか走らない。`ci.yml` は draft でも走るため、**機械的検証は受けたままレビューだけを止められる**。この PR は**マージしない**(枠が戻ったら人間が `gh pr ready [番号]` に切り替え、自動レビューを起動させる)。「検証」節には `/check` 済みのチェックを付けず「モード B のため検収未実施(CI に委ねる)」と書く
```

### 6.2 `.claude/commands/fix-issue.md`

PR 作成のコード例の**直前**に、次の 1 行を足す:

```markdown
- **ハーネスモードが `econ` の場合は `--draft` を付ける**(`bash .claude/scripts/harness-mode.sh` で確認する)。理由と運用は `.claude/rules/mode/econ.md`(モード B のセッションには自動注入される)
```

### 6.3 `/next-ticket` は変更しない

`/next-ticket` の実装ステップは `/add-feature` のフローを参照する構造なので、6.1 で足りる。

---

## 7. ドキュメント

### 7.1 `README.md`

ディレクトリ構造の `mode` 行を、値が分かる形に差し替える:

```
                       ├ mode            … Codex 併用時の運用モード(normal / econ / degraded。切替は人間が宣言。gitignore 済み)
```

さらに `.claude/` ツリーの `rules/` の配下に 1 行足す。既存は `│   └── lead/` の 1 行なので、`lead/` を `├──` に変えたうえで:

```
│   ├── lead/          司令塔専用ルール(SessionStart hook が注入。サブエージェントには載らない)
│   └── mode/          モード別の司令塔ルール(SessionStart hook が normal 以外のときだけ注入)
```

### 7.2 `docs/template-dev/codex-delegation-plan.md`

1. §11 の表の **段階4 の行**を、段階3 と同じ形式で完了表記にする:
   `| **4. モード B** ✅ **完了(2026-08-23)** | ... |`
2. §11 の箇条書きの末尾(段階3 完了記録の直後)に **段階4 完了記録**を追加する。含める内容:
   - `harness-mode.sh` に読み取りを集約したこと(読み手 2 系統の一致が要件であること)
   - SessionStart 注入は `/clear` だけでなく **`startup` でも出す**ようにしたこと、およびその理由(モード B の既定経路は「セッションを閉じる → 新セッション」)
   - `codex-run.sh pending` に集約し、hook にインライン実装を置かなかったこと(§3.4 の例示との差分)
   - **draft PR の実機確認結果**(実際の PR 番号・`ci.yml` が走ったこと・`claude-code-review.yml` が走らなかったことを Actions の実績で示す)。**この項目は司令塔が PR 作成後に記入する。実装者は「[PR 作成後に司令塔が記入]」と placeholder を置く**
   - **週枠の実効寿命は本チケットでは実測できない**こと、代わりに測定方法とベースラインを `.harness/decisions.jsonl` に記録したこと(既知の逸脱)
3. §3.4 の hook インライン実装例の直後に 1 行注記する:
   `> **実装は hook 直書きではなく \`codex-run.sh pending\` に集約した(段階4)。** \`list\` と判定(未検収・プロセス不在・別ブランチ)を共有するため。`

### 7.3 `.harness/decisions.jsonl`(追記のみ・削除禁止)

次の 1 行をそのまま追記する:

```json
{"date":"2026-08-23","topic":"mode-b-weekly-budget-baseline","issue":6,"steering":".steering/20260823-issue6-harness-mode-b/","measure":{"metric":"1 チケットあたりの司令塔(Opus)出力トークンと、週枠の到達日","source":"/usage の属性別内訳(モデル別・セッション別)","baseline_mode":"normal","compare_at":"段階6(#8)完了時点で econ 運用分と比較する"},"note":"「週枠の実効寿命がどれだけ延びたか」は 1 チケットでは測れない縦断指標のため、本チケットでは測定方法とベースラインの定義のみ行う。段階5・段階6 の消化時に同形式で追記する。"}
```

**数値を捏造しないこと。** `/usage` は Claude Code の対話コマンドでスクリプトからは取得できない。実装者は上の行をそのまま追記するだけでよい。

---

## 8. 検証手順(実装者が実行する)

すべて `bash` で実行できる。**実際に `.harness/mode` を書き換えるため、検証の最後に必ず元へ戻す**(`.harness/mode` は gitignore 済みだが、消し忘れると以降のセッションが econ で始まる)。

| # | 手順 | 期待 |
| --- | --- | --- |
| V1 | `.harness/mode` が無い状態で `bash .claude/scripts/harness-mode.sh` | `normal` |
| V2 | `echo econ > .harness/mode` して同上 | `econ` |
| V3 | `echo bogus > .harness/mode` して同上 | stdout は `normal`、stderr に警告 |
| V4 | `.harness/mode` が `econ` のまま `CODEX_HARNESS_MODE=degraded bash .claude/scripts/harness-mode.sh` | `degraded`(env が勝つ) |
| V5 | `echo econ > .harness/mode` した状態で `echo '{"source":"startup"}' \| bash .claude/hooks/session-start.sh` | 出力に `## 現在のハーネスモード: B(節約` が含まれる |
| V6 | `rm -f .harness/mode` して V5 と同じ | モードのブロックが**出ない** |
| V7 | `bash .claude/scripts/codex-run.sh pending` | 既存 record は `accepted:true` のみのため**何も出さない**(終了コード 0) |
| V8 | 検証用 record を作る(下記)→ `pending` | `- Codex 委託(未検収): 1 件` と詳細行が出る |
| V9 | V8 の record の `branch` を別名にする → `pending` | `[別ブランチ: ...]` が付き、`→ 検収...` の行が**出ない** |
| V10 | V8 の record の `startedAt` を 10 日前にする → `pending` | `(古い記録: 7 日以上前)` が付き、`→ 検収...` の行が**出ない** |
| V11 | V8 の record を `status:"running"`・`pid` を存在しない値(例 `999999`)にする → `pending` | `running(プロセス不在 ...)` と表示される |
| V12 | V8 の record がある状態で `echo '{"source":"startup"}' \| bash .claude/hooks/session-start.sh` | `## Codex 委託(未検収)` の見出し付きで出る |
| V13 | 同上で `{"source":"clear"}` | 「現在地」ブロックの**中**(in-progress チケットの直後)に出る。単独見出しは出ない |
| V14 | `jq` が無い状態で V8 を再実行(`PATH` を絞る等。作れなければ「実施不可」と tasklist に記録する) | jq 経路と**同じ出力**になる(`rec_field` の sed フォールバック。段階3 で Critical を出した経路) |
| V15 | 変更した全スクリプトに `bash -n` | 構文エラーなし |
| V16 | `git ls-files -s .claude/scripts/harness-mode.sh` | `100755` で始まる |

**V8 の検証用 record**(作成後は必ず削除する):

```bash
mkdir -p .harness/codex-runs
cat > .harness/codex-runs/99999999-000000-1.json <<'JSON'
{
  "id": "99999999-000000-1",
  "mode": "impl",
  "target": ".steering/20260823-issue6-harness-mode-b/",
  "steering": ".steering/20260823-issue6-harness-mode-b/",
  "branch": "feature/issue6-harness-mode-b",
  "harnessMode": "econ",
  "codexSessionId": null,
  "pid": 999999,
  "status": "completed",
  "startedAt": "2026-08-23T10:00:00Z",
  "endedAt": "2026-08-23T10:05:00Z",
  "resetAt": null,
  "summary": "検証用のダミー record",
  "error": null,
  "log": ".harness/codex-runs/99999999-000000-1.log",
  "accepted": false
}
JSON
```

**後始末(必須)**: `rm -f .harness/codex-runs/99999999-000000-1.json .harness/mode`

`.harness/codex-runs/` と `.harness/mode` は gitignore 済みだが、**残すと以降のセッションに偽の未検収が出続ける**。

---

## 9. やらないこと(実装者向けの明示)

- 非 draft PR を機械的にブロックする PreToolUse hook を足さない(スコープ外)
- `.harness/mode` を書き換えるコマンド/スキルを作らない(切替の宣言は人間の担当。§2.2)
- `docs/template-dev/codex-harness.html` を更新しない(スコープ外)
- `docs/development-guidelines.md` は**このリポジトリには存在しない**(プロジェクト開始後に生成される)。作らない
- `.claude/template-manifest.json` を変更しない(`.claude/rules/` は既に `owned` 配下)
