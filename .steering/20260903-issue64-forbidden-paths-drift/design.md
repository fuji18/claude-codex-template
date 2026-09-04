# 設計書

<!-- status: ready -->

## アーキテクチャ概要

判定の実体を新規スクリプトに置き、CI は**装飾だけ**を行う。既存の 2 本(`check-record-hygiene.sh` / `check-guard-integrity.sh`)と同じ分業で、手元で同じ結果を再現できることを要件にする。

```
delegate-codex.sh --print-forbidden        CLAUDE.md
   (FORBIDDEN_PATHS + AGENTS.md §4)          「### Codex への委託禁止領域(パス)」節
                 |                                    |
                 +----------------+-------------------+
                                  |
                   .claude/scripts/check-forbidden-paths-doc.sh
                     (実在するパスが節に文字列として現れるか)
                                  |
                    stdout: ずれ 1 行ずつ / exit 0|1
                                  |
                   ci.yml harness-integrity の独立ステップ
                     ::warning:: に変換するだけ(exit しない)
```

## 設計判断

### 判断1: 検査対象は `--print-forbidden` の出力全体を「実在するパス」に絞ったもの

`--print-forbidden` は**汎用項目(`FORBIDDEN_PATHS`)+ プロジェクト固有パス(`AGENTS.md` §4 マーカーから抽出)**の両方を出す。両方を検査対象にする。

- `/kickoff` フェーズ4 は**プロジェクト固有パスを `CLAUDE.md` と `AGENTS.md` の両方に書く**設計(`.claude/commands/kickoff.md` 94-95 行)。したがってプロジェクト固有パスも `CLAUDE.md` にある状態が正であり、汎用項目だけに絞る理由が無い
- マーカー内の抽出は**バックティック囲みの文字列すべて**なので、散文の語(`delegate-codex.sh`)や `<!-- verify-probe: ... -->` のような断片が混ざる。**実在検査で落ちる**(実測: このリポジトリでこの 2 件だけが混入し、実在検査で 0 件になる)。これは `delegate-codex.sh` の `forbidden_files()` が行っている実在検査と同じ解釈で、新しい規則を持ち込まない

**この判断の限界(スクリプトのコメントにも書く)**: 「まだ存在しないパス」を `FORBIDDEN_PATHS` に足した場合は検知できない。警告層であり、汎用項目はテンプレート内に実在するのが常態なので許容する。

### 判断2: 逆方向(`CLAUDE.md` にあるが単一ソースに無い)は見ない

`CLAUDE.md` の当該節には、**禁止領域ではないもの**が意図的に書かれている:

- 除外の説明 — 「`.claude/` 配下でも `skills/` / `commands/` / `agents/` / `docs/` は禁止領域に含めない」
- 判定の実体への参照 — `check-protected-branch.sh` / `check-guard-integrity.sh` / `codex-run.sh`
- 根拠文書への参照 — `docs/template-dev/codex-delegation-plan.md`

逆方向を見るとこれらが全部誤検知になる。説明文の自由度を機械検査で縛らない(Issue #64 スコープ2)方針と衝突するため入れない。

### 判断3: 節の抽出は見出しから次の見出しまで。見つからなければパス単位の検査をしない

`CLAUDE.md` は**プロジェクト所有ファイル**で、節名は改名されうる。見出しが見つからないときに全パスを「未記載」と報告すると、警告が 15 行出て意味を失う。**1 行だけ報告して終える。**

- 開始: 行頭が `### Codex への委託禁止領域` で始まる行(その行自身は本文に含めない)
- 終了: 次に現れる見出し行(`^#+ `)
- 全文検索にはしない。ずれ検知の目的は「その節に説明があるか」であり、他の節での言及を通してしまうと検査が空振りする

### 判断4: 判定の実体は新規スクリプト、CI は装飾だけ

`check-guard-integrity.sh` に相乗りさせない。あちらは**ガードレールの自壊検知 = エラー(ジョブを赤にする)**で、こちらは**文書のずれ = 警告**。同じ出力ストリームに重症度の違うものを混ぜると、呼び出し側が行ごとに severity を判別する必要が出る。

### 判断5: 警告レベルの実現方法は「独立ステップ + `if !` で受けて `::warning::` を出すだけ」

`continue-on-error` は使わない(ステップ自体が失敗扱いで UI に赤が出る)。ステップの中で終了コードを受け止め、`exit` しない。

配置は既存の "Validate harness integrity" ステップの**後**。ガードレールが壊れているときは先にそちらを直すのが先決で、警告はその後でよい。

## コンポーネント設計

### 1. `.claude/scripts/check-forbidden-paths-doc.sh`(新規)

**責務**:
- `--print-forbidden` の出力と `CLAUDE.md` 該当節の照合
- ずれを 1 行ずつ標準出力へ。装飾はしない

**終了コード**: `0` = ずれ無し(または検査対象外の構成) / `1` = ずれあり

**実装(この内容で作成する)**:

```bash
#!/bin/bash
# 委託禁止領域の単一ソース(delegate-codex.sh)と CLAUDE.md の説明節のずれを検出する。
#
# 呼び出し元:
#   - .github/workflows/ci.yml の harness-integrity ジョブ … ::warning:: に変換(ジョブは赤にしない)
#
# 背景: 禁止領域の単一ソースは 2 系統(delegate-codex.sh の FORBIDDEN_PATHS = 汎用項目 /
# AGENTS.md §4 のマーカー = プロジェクト固有パス)。CLAUDE.md「Codex への委託禁止領域(パス)」
# 節は司令塔が振り分けを判断するための説明で、手動同期のため 3 箇所目の直し漏れが起きる(#64)。
#
# 警告に留める理由: CLAUDE.md はプロジェクト所有ファイルで、説明文の書き方に自由度がある。
# 機械検査で表現を縛ると文書が硬直する。自動生成もしない(プロジェクト側の追記と衝突する)。
#
# 出力: ずれている項目を 1 行ずつ標準出力へ。装飾(::warning::)は呼び出し側の責任
#       (check-record-hygiene.sh / check-guard-integrity.sh と同じ分業)。
# 終了コード:
#   0 … ずれ無し(または検査対象外の構成)
#   1 … ずれがある
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] && cd "$ROOT" 2>/dev/null

DELEGATE=".claude/scripts/delegate-codex.sh"
MEMORY="CLAUDE.md"
HEADING="### Codex への委託禁止領域"

FOUND=0
note() { echo "$1"; FOUND=1; }

# 委託経路そのものが無い構成(Codex を使わないプロジェクト)では検査しない
[ -f "$DELEGATE" ] || exit 0
[ -f "$MEMORY" ] || exit 0

FORBIDDEN_LIST="$(bash "$DELEGATE" --print-forbidden 2>/dev/null || true)"
if [ -z "$FORBIDDEN_LIST" ]; then
  note "$DELEGATE --print-forbidden が委託禁止領域を返さない。$MEMORY との照合が行えない"
  exit "$FOUND"
fi

# CLAUDE.md の該当節だけを取り出す。節が見つからないときはパス単位の検査をしない
# (節名はプロジェクト所有ファイルの記述であり改名されうる。全パスを未記載として
#  報告すると警告が十数行出て意味を失う)。
SECTION="$(awk -v h="$HEADING" 'index($0, h) == 1 { f = 1; next } f && /^#+ / { exit } f' "$MEMORY")"
if [ -z "$SECTION" ]; then
  note "$MEMORY に「$HEADING」節が見つからない。委託禁止領域の記述ずれを検査できない(節を改名したなら check-forbidden-paths-doc.sh の HEADING も直すこと)"
  exit "$FOUND"
fi

# 末尾のワイルドカードを外してから照合する。AGENTS.md §4 は src/auth/ と src/auth/**
# の両方の書き方を許しており(delegate-codex.sh の forbidden_files() と同じ解釈)、
# CLAUDE.md 側が別の書き方をしているだけで誤検知になるのを避ける。
while IFS= read -r _p; do
  [ -n "$_p" ] || continue
  # 実在しないものは検査しない。AGENTS.md のマーカー内は散文もバックティックで囲むため、
  # 抽出結果に `delegate-codex.sh` や <!-- verify-probe: ... --> のような非パスが混ざる
  # (delegate-codex.sh 側も forbidden_files() で同じ実在検査をしている)。
  # 裏を返すと「まだ存在しないパスを FORBIDDEN_PATHS に足した」ケースは検知できない。
  # 警告層としては許容する。
  [ -e "$_p" ] || continue
  printf '%s\n' "$SECTION" | grep -qF -- "$_p" && continue
  note "委託禁止領域 '$_p' が $MEMORY の「$HEADING」節に書かれていない。単一ソース($DELEGATE の FORBIDDEN_PATHS / AGENTS.md §4)にパスを足したら、この節の説明も同時に更新すること"
done < <(printf '%s\n' "$FORBIDDEN_LIST" | sed 's/\*\{1,2\}$//' | LC_ALL=C sort -u)

exit "$FOUND"
```

**実装の要点**:
- ファイル冒頭に shebang を置き、**実行ビットを index に入れる**(`.claude/scripts/*.sh` は `lib-*.sh` 以外、`harness-integrity` が実行権限を必須にしている。`chmod +x` だけでは `core.fileMode=false` の環境で index に入らない → `git add` 後に `git update-index --chmod=+x`)
- `lib-` 接頭辞は付けない(source 専用ライブラリ扱いになり、shebang と実行ビットが逆に禁止される)

### 2. `.github/workflows/ci.yml`(`harness-integrity` ジョブ)

**責務**: スクリプトを呼び、出力行を `::warning::` に変換する。ジョブは赤にしない。

**追加するステップ(既存の "Validate harness integrity" ステップの直後)**:

```yaml
      # 委託禁止領域の単一ソース(delegate-codex.sh の FORBIDDEN_PATHS + AGENTS.md §4)と
      # CLAUDE.md の説明節のずれを検出する。CLAUDE.md はプロジェクト所有ファイルで説明文の
      # 自由度があるため、**警告に留めてジョブは赤にしない**(#64)。continue-on-error を
      # 使わないのは、ステップ自体が失敗扱いになって UI に赤が出るため。
      #
      # 末尾の exit 0 は飾りではない。Actions の既定シェルは bash -e で、
      # while ループは最後に実行したコマンドの終了コードを返す。出力が空のまま
      # 検査が非ゼロで終わると(スクリプトの欠落・実行時エラー)ループ本体が
      # 1 度も走らず read の失敗が返り、**メッセージ 1 行も無いままジョブが赤くなる**
      # (司令塔が bash -e で単体再現して確認)。異常終了そのものは、それと分かる
      # 警告 1 行に変換してから握り潰す。
      - name: Check forbidden-paths documentation drift
        run: |
          SCRIPT=.claude/scripts/check-forbidden-paths-doc.sh
          set +e
          DRIFT="$(bash "$SCRIPT")"
          RC=$?
          set -e
          if [ "$RC" -ne 0 ] && [ -z "$DRIFT" ]; then
            echo "::warning::$SCRIPT が出力なしで異常終了しました(rc=$RC。スクリプトの欠落か実行時エラー)。委託禁止領域の記述ずれ検査が働いていません"
          fi
          printf '%s\n' "$DRIFT" | while IFS= read -r line; do
            if [ -n "$line" ]; then echo "::warning::$line"; fi
          done
          exit 0
```

**この 2 行は形が決まっている(実装時に発覚 → 実測で確定した)**:

- `printf '%s'`(末尾改行なし)にすると、コマンド置換が末尾改行を落としている分と合わさって **`while read` が最終行を読み捨てる**(ずれ 2 件のうち 1 件しか警告が出ない)
- `[ -n "$line" ] && echo ...` の形にすると、`DRIFT` が空のとき `printf '%s\n' ""` の 1 行に対して条件が偽になり、ループが 1 を返して `bash -e` がステップを落とす。`if` 文にすると条件が偽でも 0 を返すため両立する

### 3. `docs/template-dev/CHANGELOG.md`

**責務**: テンプレート追従側への通知。`.claude/` / `.github/workflows/` を触る PR は CI(`record-hygiene`)が CHANGELOG の更新を必須にする。

**実装の要点**: 最新の日付節(先頭)に `- **[auto]** ...` で 1 行追記する。取り込む側に手作業は要らない(`.claude/scripts/` と `.github/workflows/` はどちらも同期対象)ため `[manual]` にはしない。日付節が当日(2026-09-03)に無ければ新しい節を先頭付近に作る。

## データフロー

1. CI が `check-forbidden-paths-doc.sh` を実行
2. スクリプトが `delegate-codex.sh --print-forbidden` を実行(自己コピー + exec を通る read-only 経路。codex CLI が無くても応答する)
3. 出力を `sed` でワイルドカード除去 → `sort -u` → 実在するものだけに絞る
4. 各パスを `CLAUDE.md` の該当節に対して固定文字列検索(`grep -qF`)
5. 見つからないものを 1 行ずつ標準出力へ、`exit 1`
6. CI が各行を `::warning::` として出力し、ステップは成功で終わる

## エラーハンドリング

| 状況 | 挙動 | 理由 |
| --- | --- | --- |
| `delegate-codex.sh` が無い | 何も出さず `exit 0` | Codex を使わないプロジェクトでは検査対象外 |
| `CLAUDE.md` が無い | 何も出さず `exit 0` | 同上(テンプレート導入直後など) |
| `--print-forbidden` が空を返す | 1 行報告して `exit 1` | 単一ソースが読めていない状態を黙って通さない |
| 該当節が見つからない | 1 行報告して `exit 1`(パス単位の検査はしない) | 節名の改名で警告が十数行出るのを避ける |
| ずれあり | ずれた数だけ報告して `exit 1` | 呼び出し側が `::warning::` に変換 |
| スクリプト自体が欠落・実行時エラー(出力が空のまま非ゼロ) | CI 側が「検査が働いていません」の警告 1 行に変換し、ステップは成功で終わる | 無言の赤は原因が読めない。検査層が消えたことは警告として見えるべきで、ジョブの赤としてではない |

## テスト戦略

このリポジトリに自動テストの枠組みは無いため、**実装者が手元で再現確認を行い、結果を報告する**(手順は `tasklist.md` フェーズ2 に記載)。確認は 3 パターン:

1. 現状 → 出力 0 行 / `exit 0`
2. `FORBIDDEN_PATHS` に実在パス(`README.md`)を一時追加 → 該当 1 行 / `exit 1`
3. 2 の状態で `CLAUDE.md` の該当節にも `README.md` を書く → 出力 0 行 / `exit 0`

**確認後は一時変更を必ず戻し、`git status --short` に `.claude/scripts/delegate-codex.sh` と `CLAUDE.md` が現れないことを確認する。**

## 影響範囲

| ファイル | 変更 |
| --- | --- |
| `.claude/scripts/check-forbidden-paths-doc.sh` | 新規(実行ビット必須) |
| `.github/workflows/ci.yml` | `harness-integrity` にステップ 1 つ追加 |
| `docs/template-dev/CHANGELOG.md` | `[auto]` 1 行追記 |

`delegate-codex.sh` / `CLAUDE.md` / `AGENTS.md` は**変更しない**(検査の入力であって、今回ずれは無い)。
