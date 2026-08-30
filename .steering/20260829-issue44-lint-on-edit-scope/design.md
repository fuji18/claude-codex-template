# 設計: lint-on-edit.sh を編集ファイル単位に絞る

<!-- status: ready -->

対象ファイルは **`.claude/scripts/lint-on-edit.sh` の全面書き換え 1 本**と、
`docs/template-dev/CHANGELOG.md` への追記 1 本。新規ファイルは作らない。
`.claude/settings.json` の hook 登録(パス・`async: true`・`timeout: 120`)は**変更しない**。

## 0. 計画時の実測(すべて本リポジトリ / devcontainer で計測済み)

判断の前提になるので先に置く。実装者はこれを再計測しなくてよい。

| コマンド | 実測 |
| --- | --- |
| `npm run --silent lint`(現行) | 25.5 s |
| `npx --no-install eslint src/index.ts` | 14.7 s |
| `./node_modules/.bin/eslint src/index.ts` | 14.2 s / 13.8 s |
| `./node_modules/.bin/eslint .`(全体) | 14.0 s |
| `npm run --silent typecheck`(現行) | 3.7 s |
| `./node_modules/.bin/tsc --noEmit` | 1.2 s |
| `tsc --noEmit --incremental`(1 回目 / 2 回目) | 2.5 s / 1.7 s |

読み取れること:

- **いま支配的なのは eslint の起動コストで、ファイル数ではない**(全体 14.0 s ≒ 単体 14.2 s)。
  現行の 25.5 s との差 11 s は `npm run` のラッパ分。**`npm run` をやめて直接バイナリを叩くだけで
  約 11 s 減る**
- 単体化の効き目は**いまの CPU ではなく (a) コンテキスト量 (b) 将来のスケール**。Issue の狙いどおり
- `--incremental` は**現時点では 0.5〜1.3 s 遅い**(buildinfo の書き出し分)。それでも採用する理由は §3

## 1. 全体方針(3 つの決定)

| # | 決定 | 一言の根拠 |
| --- | --- | --- |
| 1 | eslint は**編集した 1 ファイルだけ**に掛ける。呼び出しは `npm run` ではなく `node_modules/.bin/eslint` | 無関係な既存エラーを載せない / npm ラッパ 11 s を削る |
| 2 | tsc は**全体検査を維持する**(Issue の選択肢 a)。ただし**出力は編集ファイルの行だけ通し、残りは件数 1 行に畳む**。`--incremental` + 専用 buildinfo を使う | 型は 1 ファイルでは決まらない。だが「無関係な既存エラーを載せない」は出力側で満たせる |
| 3 | ロックの穴は**塞ぐ**。スキップではなく**キューに積んで先行プロセスが拾う**(coalescing) | 穴は「最後の編集が無検査」という静かな取りこぼし。eslint 14 s はロック撤去には長すぎる |

## 2. 決定 1 の詳細(eslint)

- 呼ぶのは `node_modules/.bin/eslint`。`[ -x ]` で存在を確認し、無ければ**黙って何もしない**
  (hook はフェイルオープン。`npm ci` 前の環境で毎編集ごとにエラーを吐かせない)
- フラグは 2 つ。実測で挙動を確認済み:
  - `--no-warn-ignored` — `dist/` など ignores 対象を編集したとき
    「File ignored because of a matching ignore pattern」の警告が出るのを止める(実測: 付けないと出る)
  - `--no-error-on-unmatched-pattern` — 対象外パスで
    「Oops! Something went wrong!」+ `exit 2` が出るのを止める(実測: 付けないと出る)
- 渡すのは**プロジェクトルートからの相対パス**。絶対パスでも eslint は動く(実測 exit 0)が、
  §4 の tsc 出力との突き合わせが相対パス基準なので、両者で表記を揃える

## 3. 決定 2 の詳細(tsc)

### なぜ選択肢 b(hook から落とす)を採らないか

「fork の自己修復(`review-policy.md` 三層の第 1 層)と重複するから落とす」は一見筋が通るが、
**hook の役割は fork の代替ではなく、編集直後の即時フィードバック**である。落とすと、fork が
タスク末尾で品質チェックを回すまで型エラーに気付けず、誤った前提の上に後続タスクが積み上がる。
実測 1.2〜2.5 s の非同期処理を削って得るものが釣り合わない。

### なぜ「全体検査 + 出力の絞り込み」なのか

型は 1 ファイルでは決まらない。単体ファイルの型チェックという操作自体が存在しない
(`tsc file.ts` は tsconfig を無視した別物になる)。一方で受け入れ条件の
「無関係な既存エラーが載らない」は**出力側で**満たせる。よって検査は全体、出力は絞る。

**編集ファイル以外のエラーを完全に隠すのではなく、件数 1 行だけ残す。** 自分の編集が
他ファイルを壊した場合(シグネチャ変更で呼び出し側が落ちる等)に、存在だけは伝わる必要がある。
1 行ならコンテキストへの影響は無視できる。

### なぜ `--incremental` を採るのか(いまは遅いのに)

実測では現時点 0.5〜1.3 s の**持ち出し**になる。それでも採る:

- buildinfo 書き出しコストはほぼ一定、全体再検査コストはプログラム規模に比例する。
  交差点は早い(src が数十ファイルの規模)
- このチケットの主題が「コードが育つと線形に高くなる」ことへの対処であり、
  **育った後に効く選択**を今入れておくのが目的に合う
- 非同期 hook の 1 秒弱は体感に出ない

buildinfo は `.claude/.lint-on-edit.tsbuildinfo` に置く。`npm run build` / `npm run typecheck` と
**buildinfo を共有しない**(`--tsBuildInfoFile` で明示)。`.gitignore` の `*.tsbuildinfo` に既に
マッチするので追記は不要(確認済み)。同時実行による破損は §5 のロックが 1 本に絞ることで防ぐ。

### 対象拡張子

型検査を回すのは **`.ts` / `.tsx` のみ**。`tsconfig.json` は `allowJs` を有効にしていないため、
`.js` / `.mjs` / `.cjs` の編集は型プログラムに影響しない。eslint は従来どおり 5 拡張子すべてに掛ける。

### 出力の絞り込み仕様(実測した tsc の出力形式に基づく)

非 TTY の `tsc --noEmit` は、行頭から `相対パス(行,列): error TSxxxx: メッセージ` の 1 行 1 エラー形式で、
サマリ行(`Found N errors`)は出ない(実測で確認済み)。また `--incremental` の 2 回目以降も、
変更が無ければ**キャッシュから同じエラー行を再出力する**(実測で確認済み)ため、
「2 回目は黙る」ことを心配しなくてよい。

- 編集ファイルの行 = **行頭が `<相対パス>(` で始まる行**。`grep -F` の部分一致だと
  `x/src/a.ts(...)` が `src/a.ts` の行として誤検出されるので、
  **`awk -v p="$rel(" 'index($0, p) == 1'` で行頭に固定する**
- それ以外の件数 = `: error TS` を含む全行数 − 上記のうち `: error TS` を含む行数

## 4. 決定 3 の詳細(ロック / 連続編集)

### 現行の穴(実測に基づく評価)

`mkdir` に失敗したら即 `exit 0`。eslint の実測が 14 s なので、**14 秒の窓に入った編集はすべて捨てられる**。
実装フェーズの連続編集はこの窓に容易に収まるため、「最後の編集が無検査」は例外ではなく常態に近い。

### 採る方式: coalescing キュー(穴を塞ぐ)

- ロックを取れなかったプロセスは、**捨てずに `$LOCK/queue` へ自分のパスを 1 行追記して終了する**
- ロックを保持しているプロセスは、自分の検査が終わったあとキューを読み、**空になるまで処理し続ける**
- 同一ファイルの重複は `awk '!seen[$0]++'` で 1 本に畳む

これで「同時に走るのは常に 1 本」(= CPU と buildinfo の保護)と
「どの編集も最終的に検査される」を両立する。ロック撤去案は採らない —
eslint 14 s では連続編集がそのまま多重起動になり、CPU を素直に食う。

### 残る穴(許容する。実装者はここを塞ごうとしないこと)

- キューが空だと判定してから `rm -rf "$LOCK"`(trap)までの**マイクロ秒オーダーの窓**に
  積まれた 1 本は失われる
- 追記(`>>`)と切り詰め(`: >`)が交差した場合も同様に 1 本失われうる

現行の「14 秒の窓」から「マイクロ秒の窓」への縮小であり、これ以上は
ファイルロック方式(`flock`)への作り替えが必要になる。hook の重要度に対して過剰なので**許容する**。
この判断を script の冒頭コメントにも 1 行残すこと。

## 5. 完成後の `.claude/scripts/lint-on-edit.sh`(この内容で全面置換する)

> **【改訂あり】この節のスクリプトは §8 で置き換えられた。** 検収レビューで
> 「SIGKILL でロックが孤立すると以降すべての編集が無検査になる」欠陥が出たため。
> **実装は §8 に従うこと。** §1〜§4 の方針そのものは変わっていない。

```bash
#!/bin/bash
# PostToolUse(Edit|Write) async hook: TS/JS ファイルの編集後に lint と型チェックを走らせる。
#
# 設計の根拠は .steering/20260829-issue44-lint-on-edit-scope/design.md。要点は 3 つ:
#   1. eslint は編集した 1 ファイルだけに掛ける。全体 lint は編集と無関係な既存エラーを
#      毎編集ごとにコンテキストへ載せ、ファイル数に比例して太る
#   2. tsc は全体を検査する(型は 1 ファイルでは決まらない)が、出力は編集ファイルの行だけ通し、
#      それ以外は件数 1 行に畳む。--incremental で再検査コストを差分に寄せる
#   3. 多重起動は「スキップ」ではなく「キューに積んで先行プロセスが拾う」(coalescing)。
#      旧実装は実行中に入った編集を捨てており、連続編集の最後の 1 本が常に無検査だった。
#      キューが空だと判定してからロック解放までのマイクロ秒の窓だけは残るが、
#      旧実装の「検査時間ぶんの窓」からの縮小で十分と判断して許容する
set -uo pipefail

f="$(jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null)"
[ -n "$f" ] || exit 0
case "$f" in
  *.ts | *.tsx | *.js | *.mjs | *.cjs) ;;
  *) exit 0 ;;
esac

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

LOCK=".claude/.lint-on-edit.lock"
QUEUE="$LOCK/queue"
ESLINT="node_modules/.bin/eslint"
TSC="node_modules/.bin/tsc"
TSBUILDINFO=".claude/.lint-on-edit.tsbuildinfo"

if ! mkdir "$LOCK" 2>/dev/null; then
  printf '%s\n' "$f" >>"$QUEUE" 2>/dev/null || true
  exit 0
fi
trap 'rm -rf "$LOCK" 2>/dev/null' EXIT

# 編集ファイル 1 本を検査する。プロジェクト外・削除済みのパスは黙って捨てる。
run_checks() {
  local target="$1" rel out mine mine_count total

  case "$target" in
    "$PWD"/*) rel="${target#"$PWD"/}" ;;
    /*) return 0 ;;
    *) rel="$target" ;;
  esac
  [ -f "$rel" ] || return 0

  # --no-warn-ignored: ignores 対象ファイルを編集したときの警告を出さない
  # --no-error-on-unmatched-pattern: 対象外パスでの定型エラー(exit 2)を出さない
  if [ -x "$ESLINT" ]; then
    "$ESLINT" --no-warn-ignored --no-error-on-unmatched-pattern "$rel" 2>&1 | tail -20
  fi

  # allowJs 無効のため、型プログラムに載るのは .ts / .tsx だけ
  case "$rel" in
    *.ts | *.tsx) ;;
    *) return 0 ;;
  esac
  [ -x "$TSC" ] || return 0

  out="$("$TSC" --noEmit --incremental --tsBuildInfoFile "$TSBUILDINFO" 2>&1)" || true
  [ -n "$out" ] || return 0

  # 編集ファイルの行だけ通す(行頭一致。grep -F の部分一致では別ファイルを拾う)
  mine="$(printf '%s\n' "$out" | awk -v p="$rel(" 'index($0, p) == 1')"
  [ -z "$mine" ] || printf '%s\n' "$mine" | head -20

  total="$(printf '%s\n' "$out" | grep -c ': error TS' || true)"
  mine_count="$(printf '%s\n' "$mine" | grep -c ': error TS' || true)"
  if [ "$((total - mine_count))" -gt 0 ]; then
    echo "(このファイル以外に型エラー $((total - mine_count)) 件。全体は npm run typecheck で確認する)"
  fi
}

run_checks "$f"

# 検査中に積まれた編集を拾う。キューが空になるまで繰り返す。
while [ -s "$QUEUE" ]; do
  pending="$(cat "$QUEUE" 2>/dev/null)"
  : >"$QUEUE"
  while IFS= read -r q; do
    [ -n "$q" ] && run_checks "$q"
  done <<<"$(printf '%s\n' "$pending" | awk '!seen[$0]++')"
done

exit 0
```

## 6. CHANGELOG への追記(`docs/template-dev/CHANGELOG.md`)

見出し `## 2026-08-29` は**既に存在する**。その見出しの直下(既存の本文の**後ろ**、
次の日付見出しの前)に以下を追記する。新しい日付見出しは作らない。

```markdown
**PostToolUse の lint hook を編集ファイル単位に絞った(Issue #44)。** 編集のたびに全体 eslint と
全体 tsc を回し、`tail -20` の中身が毎回コンテキストへ載っていました。

- **[auto]** `.claude/scripts/lint-on-edit.sh` を書き換え。eslint は編集した 1 ファイルだけに掛け、
  呼び出しを `npm run` から `node_modules/.bin/eslint` へ変更(実測 25.5 s → 14.2 s。差分の大半は
  npm ラッパの起動コスト)。型チェックは全体検査を維持したまま、**出力を編集ファイルの行だけに絞り、
  それ以外は件数 1 行に畳む**(型は 1 ファイルでは決まらないため検査は絞れないが、
  コンテキストに載る量は絞れる)。`--incremental` + 専用 buildinfo
  (`.claude/.lint-on-edit.tsbuildinfo`、`*.tsbuildinfo` で既に gitignore 済み)を導入
- **[auto]** 同 hook の多重起動対策を「スキップ」から「キューに積んで先行プロセスが拾う」に変更。
  旧実装は実行中に入った編集を捨てており、**連続編集の最後の 1 本が常に無検査**だった
```

## 7. 実装者への注意

- **`.claude/settings.json` は触らない。** hook の登録内容は現行のままで正しい
- **`.gitignore` は触らない。** `*.tsbuildinfo` と `.claude/.lint-on-edit.lock` が既にある
- この hook 自体が `.sh` を対象にしないため、作業中に自分の変更で hook が誤発火することはない
- 検証手順は `tasklist.md` に書いてある。**実際にスクリプトを走らせて確かめること**

---

## 8. 改訂: 検収指摘の反映(§5 を置き換える)

検収(`code-reviewer`)で 1 Major / 3 Minor。司令塔の判断は以下。

| # | 指摘 | 判断 |
| --- | --- | --- |
| Major | SIGKILL(hook `timeout: 120`)で `trap` が発火せずロックが孤立すると、以降**誰もロックを取れず全編集が無検査**になり、キューだけが積み上がる | **直す。** §4 で許容したのは「マイクロ秒の窓」だけであり、これは別物。しかも coalescing にしたことでドレインが長引く経路ができ、timeout 到達は理論値ではなく現実的(例: 8 ファイル × 16 s = 128 s > 120 s) |
| Minor | `local a b c` は `set -u` 下で未初期化。現状実害はないが将来の落とし穴 | **直す。** 明示的に空値 / 0 で初期化する |
| Minor | パス判定が `$PWD` の字面一致依存。シンボリックリンク経由だと `return 0` で**黙って無検査** | **直す。** フェイルオープンかつ無言なので最も気付けない。`realpath` で両辺を正規化する(取れない環境では従来どおりの字面比較にフォールバック) |
| Minor | `$LOCK` 不在時に `>>"$QUEUE"` のリダイレクト自体が失敗しうる | **下の (a) で解消する。** キューをロックディレクトリの外に出すため、`.claude/` さえあれば書ける |

### 対策 (a): キューをロックの外に出す

キューを `$LOCK/queue` に置くと `rm -rf "$LOCK"` で消えるため、**打ち切って持ち越す**ことができない。
`.claude/.lint-on-edit.queue` に移す。あわせてロック取得時刻の基準として `$LOCK/started` を置く
(キューが中にあるとファイル作成でロックディレクトリの mtime が動き、経過時間の判定が狂う)。

### 対策 (b): 孤立ロックの奪取

`STALE_AFTER=300`(settings.json の `timeout: 120` より十分大きく取る)を超えて残っている
ロックは、`trap` が発火しなかった残骸とみなして `rm -rf` してから取り直す。
2 プロセスが同時に「stale だ」と判断しても `mkdir` は 1 本しか成功しないので、
負けた側は従来どおりキューへ積んで終わる。

### 対策 (c): ドレインの打ち切り

`DRAIN_DEADLINE=90` 秒を超えたら残りをキューへ書き戻して終了する。次回の hook 起動が
ロックを取って続きを処理する。**SIGKILL される前に自分で降りる**ことで (b) の出番自体を減らす。

### 変わらないこと

§4 の「キューが空だと判定してからロック解放までのマイクロ秒の窓」は引き続き**許容する**。
`flock` への作り替えが必要で、hook の重要度に対して過剰。

### `.gitignore` の変更(§7 の「触らない」を上書きする)

キューが増えるため、既存の 1 行を書き換える(**追加ではなく置換**):

```diff
-.claude/.lint-on-edit.lock
+.claude/.lint-on-edit.*
```

`*.tsbuildinfo` の行はそのまま残す(重複して困るものではない)。

### 改訂後の `.claude/scripts/lint-on-edit.sh`(この内容で全面置換する)

> **【再改訂あり】この節のスクリプトは §9 で置き換えられた。** §8 の方針(対策 a/b/c)は
> そのまま有効だが、奪取の実装が非アトミックで二重取得しうることが再レビューで判明した。
> **実装は §9 に従うこと。**

```bash
#!/bin/bash
# PostToolUse(Edit|Write) async hook: TS/JS ファイルの編集後に lint と型チェックを走らせる。
#
# 設計の根拠は .steering/20260829-issue44-lint-on-edit-scope/design.md。要点は 4 つ:
#   1. eslint は編集した 1 ファイルだけに掛ける。全体 lint は編集と無関係な既存エラーを
#      毎編集ごとにコンテキストへ載せ、ファイル数に比例して太る
#   2. tsc は全体を検査する(型は 1 ファイルでは決まらない)が、出力は編集ファイルの行だけ通し、
#      それ以外は件数 1 行に畳む。--incremental で再検査コストを差分に寄せる
#   3. 多重起動は「スキップ」ではなく「キューに積んで先行プロセスが拾う」(coalescing)。
#      旧実装は実行中に入った編集を捨てており、連続編集の最後の 1 本が常に無検査だった
#   4. この hook は SIGKILL され得る(settings.json の timeout: 120)。trap が発火せず
#      ロックが孤立すると以降すべての編集が無検査になるため、(a) キューはロックの外に置き、
#      (b) 古すぎるロックは奪取し、(c) ドレインは timeout の手前で自分から降りる。
#      キューが空だと判定してからロック解放までのマイクロ秒の窓だけは残るが、
#      flock への作り替えは hook の重要度に対して過剰と判断して許容する
set -uo pipefail

f="$(jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null)"
[ -n "$f" ] || exit 0
case "$f" in
  *.ts | *.tsx | *.js | *.mjs | *.cjs) ;;
  *) exit 0 ;;
esac

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

LOCK=".claude/.lint-on-edit.lock"
STAMP="$LOCK/started"
QUEUE=".claude/.lint-on-edit.queue"
ESLINT="node_modules/.bin/eslint"
TSC="node_modules/.bin/tsc"
TSBUILDINFO=".claude/.lint-on-edit.tsbuildinfo"

STALE_AFTER=300    # settings.json の hook timeout(120s)より十分大きく取る
DRAIN_DEADLINE=90  # SIGKILL される前に自分から降りる

started_at="$(date +%s)"
root="$(realpath . 2>/dev/null || printf '%s' "$PWD")"

# ロックを取る(0 = 取れた)。孤立ロックは STALE_AFTER 経過後に奪取する。
acquire_lock() {
  local born="" age=0
  mkdir "$LOCK" 2>/dev/null && { : >"$STAMP" 2>/dev/null; return 0; }
  born="$(stat -c %Y "$STAMP" 2>/dev/null || stat -c %Y "$LOCK" 2>/dev/null || printf '%s' "$started_at")"
  age=$(( started_at - born ))
  [ "$age" -gt "$STALE_AFTER" ] || return 1
  rm -rf "$LOCK" 2>/dev/null || true
  mkdir "$LOCK" 2>/dev/null && { : >"$STAMP" 2>/dev/null; return 0; }
  return 1
}

if ! acquire_lock; then
  printf '%s\n' "$f" >>"$QUEUE" 2>/dev/null || true
  exit 0
fi
trap 'rm -rf "$LOCK" 2>/dev/null' EXIT

expired() { [ $(( $(date +%s) - started_at )) -ge "$DRAIN_DEADLINE" ]; }

# 編集ファイル 1 本を検査する。プロジェクト外・削除済みのパスは黙って捨てる。
run_checks() {
  local target="$1" abs="" rel="" out="" mine="" mine_count=0 total=0

  # シンボリックリンク経由で $PWD と字面が食い違うと無検査になるため正規化する
  abs="$(realpath "$target" 2>/dev/null || printf '%s' "$target")"
  case "$abs" in
    "$root"/*) rel="${abs#"$root"/}" ;;
    /*) return 0 ;;
    *) rel="$abs" ;;
  esac
  [ -f "$rel" ] || return 0

  # --no-warn-ignored: ignores 対象ファイルを編集したときの警告を出さない
  # --no-error-on-unmatched-pattern: 対象外パスでの定型エラー(exit 2)を出さない
  if [ -x "$ESLINT" ]; then
    "$ESLINT" --no-warn-ignored --no-error-on-unmatched-pattern "$rel" 2>&1 | tail -20
  fi

  # allowJs 無効のため、型プログラムに載るのは .ts / .tsx だけ
  case "$rel" in
    *.ts | *.tsx) ;;
    *) return 0 ;;
  esac
  [ -x "$TSC" ] || return 0

  out="$("$TSC" --noEmit --incremental --tsBuildInfoFile "$TSBUILDINFO" 2>&1)" || true
  [ -n "$out" ] || return 0

  # 編集ファイルの行だけ通す(行頭一致。grep -F の部分一致では別ファイルを拾う)
  mine="$(printf '%s\n' "$out" | awk -v p="$rel(" 'index($0, p) == 1')"
  [ -z "$mine" ] || printf '%s\n' "$mine" | head -20

  total="$(printf '%s\n' "$out" | grep -c ': error TS' || true)"
  mine_count="$(printf '%s\n' "$mine" | grep -c ': error TS' || true)"
  if [ "$((total - mine_count))" -gt 0 ]; then
    echo "(このファイル以外に型エラー $((total - mine_count)) 件。全体は npm run typecheck で確認する)"
  fi
}

run_checks "$f"

# 検査中に積まれた編集を拾う。期限を超えたら残りをキューへ戻し、次回の起動に任せる。
while [ -s "$QUEUE" ]; do
  expired && break
  pending="$(cat "$QUEUE" 2>/dev/null)"
  : >"$QUEUE"
  while IFS= read -r q; do
    [ -n "$q" ] || continue
    if expired; then
      printf '%s\n' "$q" >>"$QUEUE" 2>/dev/null || true
      continue
    fi
    run_checks "$q"
  done <<<"$(printf '%s\n' "$pending" | awk '!seen[$0]++')"
done

exit 0
```

### CHANGELOG の追記(§6 の 2 項目めを差し替える)

§6 の 2 項目め(coalescing の項)を、次の文面に**置き換える**。1 項目めはそのまま。

```markdown
- **[auto]** 同 hook の多重起動対策を「スキップ」から「キューに積んで先行プロセスが拾う」に変更。
  旧実装は実行中に入った編集を捨てており、**連続編集の最後の 1 本が常に無検査**だった。
  あわせて、hook が `timeout` で強制終了されたときにロックが残り続けて**以降すべての編集が
  無検査になる**経路を塞いだ(古いロックの奪取 + 期限前の自主停止 + キューをロックの外に配置)
```

---

## 9. 再改訂: 再レビュー指摘の反映(§8 のスクリプトを置き換える)

再レビューで 1 Major / 3 Minor。判断は以下。**方針(§1〜§4、§8 の対策 a/b/c)は変えない。実装の直し。**

| # | 指摘 | 判断 |
| --- | --- | --- |
| Major | 孤立ロックの奪取が `rm -rf` → `mkdir` の 2 段で非アトミック。同時に stale と判定した 2 本が**両方「取れた」状態になる**(レビュー側で再現済み) | **直す。** §3 の「同時実行による破損はロックが 1 本に絞ることで防ぐ」という前提そのものが崩れるため。`mv` による所有権の取り合いに変える |
| Minor | `stat` が無い環境では `born == started_at` となり `age` が常に 0。**一度孤立したロックが永久に奪取されない**(= 塞いだはずの Major に逆戻り) | **直す。** `stat -c` は GNU 依存。`find -mmin` に置き換えると BSD 環境でも同じ意味で動くので、フォールバックの分岐自体が不要になる |
| Minor | ドレインが `cat` → 切り詰めの一括処理なので、SIGKILL 時に失われるのは「1 本」ではなく**未処理分すべて** | **直す(実装側)。** 1 件ずつ取り出す形にすれば、記述どおり「失われるのは 1 本」になる。文書を実装に合わせて緩めるのではなく、実装を文書に合わせる |
| Minor | `$STAMP` 不在時に `$LOCK` の mtime へフォールバックする設計は妥当(指摘ではなく確認) | **対応不要** |

なお指摘に付いていた行番号(341 / 400-411)はファイル実長(約 110 行)と合わない。**指摘のロジック自体は正しい**ので採用するが、行番号は参照しないこと。

### 変わらないこと(許容する穴)

キューから 1 件取り出した直後に SIGKILL された場合、その 1 件は失われる。また `head` と
切り詰めの間に別プロセスが追記した 1 行も失われうる。**どちらも「1 本」で収まる**ので
§4 の記述と一致する。ここから先は `flock` への作り替えが必要で、hook の重要度に対して過剰。

### 再改訂後の `.claude/scripts/lint-on-edit.sh`(この内容で全面置換する)

> **【再々改訂あり】この節のスクリプトは §10 で置き換えられた。** `mv` による奪取でも
> 二重取得が実測で再現した(20 本同時実行で 2 本が取得成功)。自前ロックを直す方向を
> やめて `flock` に置き換える。**実装は §10 に従うこと。**

```bash
#!/bin/bash
# PostToolUse(Edit|Write) async hook: TS/JS ファイルの編集後に lint と型チェックを走らせる。
#
# 設計の根拠は .steering/20260829-issue44-lint-on-edit-scope/design.md。要点は 4 つ:
#   1. eslint は編集した 1 ファイルだけに掛ける。全体 lint は編集と無関係な既存エラーを
#      毎編集ごとにコンテキストへ載せ、ファイル数に比例して太る
#   2. tsc は全体を検査する(型は 1 ファイルでは決まらない)が、出力は編集ファイルの行だけ通し、
#      それ以外は件数 1 行に畳む。--incremental で再検査コストを差分に寄せる
#   3. 多重起動は「スキップ」ではなく「キューに積んで先行プロセスが拾う」(coalescing)。
#      旧実装は実行中に入った編集を捨てており、連続編集の最後の 1 本が常に無検査だった
#   4. この hook は SIGKILL され得る(settings.json の timeout: 120)。trap が発火せず
#      ロックが孤立すると以降すべての編集が無検査になるため、キューはロックの外に置き、
#      古すぎるロックは奪取し、ドレインは timeout の手前で自分から降りる。
#      失われうるのは「取り出し済みの 1 件」までで、そこは許容する(flock への作り替えは過剰)。
set -uo pipefail

f="$(jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null)"
[ -n "$f" ] || exit 0
case "$f" in
  *.ts | *.tsx | *.js | *.mjs | *.cjs) ;;
  *) exit 0 ;;
esac

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

LOCK=".claude/.lint-on-edit.lock"
STAMP="$LOCK/started"
QUEUE=".claude/.lint-on-edit.queue"
ESLINT="node_modules/.bin/eslint"
TSC="node_modules/.bin/tsc"
TSBUILDINFO=".claude/.lint-on-edit.tsbuildinfo"

STALE_MINUTES=5    # settings.json の hook timeout(120s)より十分大きく取る
DRAIN_DEADLINE=90  # SIGKILL される前に自分から降りる

started_at="$(date +%s)"
root="$(realpath . 2>/dev/null || printf '%s' "$PWD")"

# ロックが取り残された残骸か(= 一定時間更新されていないか)。
# stat -c は GNU 依存なので find -mmin を使う(BSD 環境でも同じ意味になる)。
lock_is_stale() {
  local probe="$LOCK"
  [ -e "$STAMP" ] && probe="$STAMP"
  [ -n "$(find "$probe" -maxdepth 0 -mmin +"$STALE_MINUTES" 2>/dev/null)" ]
}

# ロックを取る(0 = 取れた)。
acquire_lock() {
  local reclaimed=""
  mkdir "$LOCK" 2>/dev/null && { : >"$STAMP" 2>/dev/null; return 0; }
  lock_is_stale || return 1
  # 奪取は「消してから作る」にしない。rm -rf → mkdir は非アトミックで、
  # 同時に stale と判定した 2 本が両方「取れた」状態になりうる。
  # mv は 1 本しか成功しないので、これが所有権の取り合いになる。
  reclaimed="$LOCK.reclaim.$$"
  mv "$LOCK" "$reclaimed" 2>/dev/null || return 1
  rm -rf "$reclaimed" 2>/dev/null || true
  mkdir "$LOCK" 2>/dev/null || return 1
  : >"$STAMP" 2>/dev/null
  return 0
}

if ! acquire_lock; then
  printf '%s\n' "$f" >>"$QUEUE" 2>/dev/null || true
  exit 0
fi
trap 'rm -rf "$LOCK" 2>/dev/null' EXIT

expired() { [ $(( $(date +%s) - started_at )) -ge "$DRAIN_DEADLINE" ]; }

# 編集ファイル 1 本を検査する。プロジェクト外・削除済みのパスは黙って捨てる。
run_checks() {
  local target="$1" abs="" rel="" out="" mine="" mine_count=0 total=0

  # シンボリックリンク経由で $PWD と字面が食い違うと無検査になるため正規化する
  abs="$(realpath "$target" 2>/dev/null || printf '%s' "$target")"
  case "$abs" in
    "$root"/*) rel="${abs#"$root"/}" ;;
    /*) return 0 ;;
    *) rel="$abs" ;;
  esac
  [ -f "$rel" ] || return 0

  # --no-warn-ignored: ignores 対象ファイルを編集したときの警告を出さない
  # --no-error-on-unmatched-pattern: 対象外パスでの定型エラー(exit 2)を出さない
  if [ -x "$ESLINT" ]; then
    "$ESLINT" --no-warn-ignored --no-error-on-unmatched-pattern "$rel" 2>&1 | tail -20
  fi

  # allowJs 無効のため、型プログラムに載るのは .ts / .tsx だけ
  case "$rel" in
    *.ts | *.tsx) ;;
    *) return 0 ;;
  esac
  [ -x "$TSC" ] || return 0

  out="$("$TSC" --noEmit --incremental --tsBuildInfoFile "$TSBUILDINFO" 2>&1)" || true
  [ -n "$out" ] || return 0

  # 編集ファイルの行だけ通す(行頭一致。grep -F の部分一致では別ファイルを拾う)
  mine="$(printf '%s\n' "$out" | awk -v p="$rel(" 'index($0, p) == 1')"
  [ -z "$mine" ] || printf '%s\n' "$mine" | head -20

  total="$(printf '%s\n' "$out" | grep -c ': error TS' || true)"
  mine_count="$(printf '%s\n' "$mine" | grep -c ': error TS' || true)"
  if [ "$((total - mine_count))" -gt 0 ]; then
    echo "(このファイル以外に型エラー $((total - mine_count)) 件。全体は npm run typecheck で確認する)"
  fi
}

declare -A drained=()

run_checks "$f"
drained["$f"]=1

# 検査中に積まれた編集を 1 件ずつ拾う。キューを丸ごと読んで切り詰めると
# SIGKILL 時に未処理分がまとめて消えるため、1 件ずつ取り出して窓を 1 本に抑える。
# 同じパスは 1 回だけ検査する(検査は常にその時点のファイル内容を読むので、
# 重複を畳んでも最新の状態が検査される)。
while [ -s "$QUEUE" ]; do
  expired && break
  q="$(head -n 1 "$QUEUE" 2>/dev/null)"
  { tail -n +2 "$QUEUE" >"$QUEUE.tmp" 2>/dev/null && mv "$QUEUE.tmp" "$QUEUE" 2>/dev/null; } || break
  [ -n "$q" ] || continue
  [ -n "${drained["$q"]:-}" ] && continue
  drained["$q"]=1
  run_checks "$q"
done

exit 0
```

### CHANGELOG

§8 末尾で指定した文面のままでよい(**追加の変更は不要**)。実装の直しであって、
利用側から見た挙動の説明は変わらないため。

---

## 10. 再々改訂: 自前ロックをやめて `flock` にする(§9 のスクリプトを置き換える)

### なぜ方針ごと変えるか

§9 の `mv` による奪取を司令塔が実測したところ、**20 本同時実行で 2 本が取得に成功した**。

原因は「`mv` はアトミックだが、**奪う対象が本当に残骸かどうかは保証しない**」こと。
A が奪取して新しいロックを作った直後に、先に stale と判定していた B がその**新しいロックを** `mv`
してしまう。判定と奪取をアトミックにしない限り、この形は塞がらない
(判定後に再検査する案も、検査と `mv` の間に同じ窓が開くだけで解決しない)。

**自前ロックの修正は 2 回連続で失敗した。** 同じアプローチを繰り返さない
(`spec-driven.md`「同じエラーの修正に 2 回連続で失敗したら、同じアプローチを繰り返さない」)。

### `flock` にすると何が消えるか

司令塔の実測(devcontainer / util-linux 2.38.1):

- 20 本同時実行で **ENTER / LEAVE が一度も交差せず、完全に直列化された**
- ロック保持プロセスを `kill -9` した直後に、**後続が問題なくロックを取得できた**
  = カーネルが fd の解放時にロックを外すため、**孤立ロックという状態が存在しない**

これにより、§8 / §9 で積み上げた仕掛けが**まるごと不要になる**:

| 消えるもの | 理由 |
| --- | --- |
| 孤立ロックの奪取(`STALE_MINUTES` / `$LOCK/started` / `mv` 奪取) | 孤立が起きない |
| ドレイン期限(`DRAIN_DEADLINE`) | 待つのはカーネル。自分で降りる必要がない |
| キューファイル(`.claude/.lint-on-edit.queue`)と重複畳み込み | 待ち合わせに変わるので、キューを自前で持たない |
| `.gitignore` の変更 | キューも buildinfo も無くなるので、**元の 1 行に戻す** |

### スキップ穴はどうなるか

`flock -n`(取れなければ即諦める)ではなく **`flock -w 100`(待ってから実行する)** を使う。
待ち行列に入った編集は順番が来たら検査されるので、**旧実装の「実行中の編集は捨てる」穴は塞がる**。

- 待ち時間は `LOCK_WAIT=100` 秒。`settings.json` の `timeout: 120` の**内側**に収める
  (timeout に食い込ませて SIGKILL されるより、自分で諦めるほうが行儀がよい)
- 100 秒待っても順番が来ないほどの連続編集では、その回の検査は落ちる。**これは許容する** —
  検査は常にその時点のファイル内容を読むので、後続の編集で検査される
- `flock` が無い環境では**ロックなしで実行する**。相互排他が失われるだけで、検査そのものは正しく動く

### `--incremental` をやめる(§3 の決定を差し戻す)

`--incremental` を採った理由は将来のスケールだった。だが buildinfo は**共有される可変資源**で、
その保護のために相互排他が要る。**`flock` が無い環境ではロックなしで走る**ため、そこで
buildinfo の同時書き込みが起こりうる。

一方 §0 の実測では、**現時点では `--incremental` のほうが 0.5〜1.3 秒遅い**(`tsc --noEmit` 1.2 s /
`--incremental` 1.7〜2.5 s)。**いま遅く、かつ保護コストを生む**キャッシュを抱える理由がないので外す。
将来 `src/` が育って全体検査が重くなったら、そのとき改めて入れ直す判断をすればよい。

`.claude/.lint-on-edit.tsbuildinfo` は**作業ツリーから削除する**(追跡されていないので git 上の変更は無い)。

### 再々改訂後の `.claude/scripts/lint-on-edit.sh`(この内容で全面置換する)

```bash
#!/bin/bash
# PostToolUse(Edit|Write) async hook: TS/JS ファイルの編集後に lint と型チェックを走らせる。
#
# 設計の根拠は .steering/20260829-issue44-lint-on-edit-scope/design.md。要点は 3 つ:
#   1. eslint は編集した 1 ファイルだけに掛ける。全体 lint は編集と無関係な既存エラーを
#      毎編集ごとにコンテキストへ載せ、ファイル数に比例して太る
#   2. tsc は全体を検査する(型は 1 ファイルでは決まらない)が、出力は編集ファイルの行だけ通し、
#      それ以外は件数 1 行に畳む
#   3. 多重起動は flock で待ち合わせる。自前の mkdir ロックには (a) 実行中に入った編集を
#      無検査で捨てる (b) 強制終了でロックが孤立する の 2 つの穴があり、(b) を塞ごうとすると
#      「残骸かどうかの判定」と「奪取」がアトミックにならず二重取得が起きる(実測で再現)。
#      flock はプロセスが死ねばカーネルが解放するので、この問題自体が消える。
set -uo pipefail

f="$(jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null)"
[ -n "$f" ] || exit 0
case "$f" in
  *.ts | *.tsx | *.js | *.mjs | *.cjs) ;;
  *) exit 0 ;;
esac

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

LOCK=".claude/.lint-on-edit.lock"
LOCK_WAIT=100   # settings.json の hook timeout(120s)の内側に収める
ESLINT="node_modules/.bin/eslint"
TSC="node_modules/.bin/tsc"

root="$(realpath . 2>/dev/null || printf '%s' "$PWD")"

# 編集ファイル 1 本を検査する。プロジェクト外・削除済みのパスは黙って捨てる。
run_checks() {
  local target="$1" abs="" rel="" out="" mine="" mine_count=0 total=0

  # シンボリックリンク経由で $PWD と字面が食い違うと無検査になるため正規化する
  abs="$(realpath "$target" 2>/dev/null || printf '%s' "$target")"
  case "$abs" in
    "$root"/*) rel="${abs#"$root"/}" ;;
    /*) return 0 ;;
    *) rel="$abs" ;;
  esac
  [ -f "$rel" ] || return 0

  # --no-warn-ignored: ignores 対象ファイルを編集したときの警告を出さない
  # --no-error-on-unmatched-pattern: 対象外パスでの定型エラー(exit 2)を出さない
  if [ -x "$ESLINT" ]; then
    "$ESLINT" --no-warn-ignored --no-error-on-unmatched-pattern "$rel" 2>&1 | tail -20
  fi

  # allowJs 無効のため、型プログラムに載るのは .ts / .tsx だけ
  case "$rel" in
    *.ts | *.tsx) ;;
    *) return 0 ;;
  esac
  [ -x "$TSC" ] || return 0

  out="$("$TSC" --noEmit 2>&1)" || true
  [ -n "$out" ] || return 0

  # 編集ファイルの行だけ通す(行頭一致。grep -F の部分一致では別ファイルを拾う)
  mine="$(printf '%s\n' "$out" | awk -v p="$rel(" 'index($0, p) == 1')"
  [ -z "$mine" ] || printf '%s\n' "$mine" | head -20

  total="$(printf '%s\n' "$out" | grep -c ': error TS' || true)"
  mine_count="$(printf '%s\n' "$mine" | grep -c ': error TS' || true)"
  if [ "$((total - mine_count))" -gt 0 ]; then
    echo "(このファイル以外に型エラー $((total - mine_count)) 件。全体は npm run typecheck で確認する)"
  fi
}

# 先行プロセスの完了を待ってから検査する(スキップしない = 連続編集でも取りこぼさない)。
# 待ちきれなければこの回は諦める。hook の timeout に食い込ませて SIGKILL されるより行儀がよく、
# 検査は常にその時点の内容を読むので、後続の編集で検査される。
if command -v flock >/dev/null 2>&1; then
  if { exec 9>"$LOCK"; } 2>/dev/null; then
    flock -w "$LOCK_WAIT" 9 || exit 0
  fi
fi

run_checks "$f"
exit 0
```

### `.gitignore`(§8 の変更を差し戻す)

```diff
-.claude/.lint-on-edit.*
+.claude/.lint-on-edit.lock
```

### CHANGELOG(§8 で指定した文面を、次の 2 項目に差し替える)

```markdown
- **[auto]** `.claude/scripts/lint-on-edit.sh` を書き換え。eslint は編集した 1 ファイルだけに掛け、
  呼び出しを `npm run` から `node_modules/.bin/eslint` へ変更(実測 25.5 s → 14.2 s。差分の大半は
  npm ラッパの起動コスト)。型チェックは全体検査を維持したまま、**出力を編集ファイルの行だけに絞り、
  それ以外は件数 1 行に畳む**(型は 1 ファイルでは決まらないため検査は絞れないが、
  コンテキストに載る量は絞れる)
- **[auto]** 同 hook の多重起動対策を、自前の `mkdir` ロックから **`flock` による待ち合わせ**に変更。
  旧実装は実行中に入った編集を**無検査で捨てて**おり、連続編集の最後の 1 本が常に無検査だった。
  `flock` はプロセスが強制終了されてもカーネルが解放するため、`timeout` で kill されたロックが
  残り続けて以降ずっと無検査になる事故も起きない(`flock` が無い環境ではロックなしで実行する)
```
