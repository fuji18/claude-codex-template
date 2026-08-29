# 設計: チケット記録の機械的検査(Issue #37)

<!-- status: ready -->

## 0. 決定事項(実装者は設計判断をしない)

| 論点 | 決定 | 根拠 |
| --- | --- | --- |
| 判定を落とすか警告にとどめるか | **落とす(exit 1)**。加えて `::error::` annotation と Job Summary に必ず出す | 散文の運用ルールでは 4 回 → 8 回と再発が悪化した。警告だけの層をもう 1 枚足しても同じ結果になる。逃げ道ラベルがあるので過剰ブロックにはならない |
| `decisions.jsonl` チェックの起動点 | **PR 時**(マージ後でも次チケット着手時でもない) | 記録の値(往復回数・検収の指摘数)は **PR 作成前の検収で確定している**。実際 #29 の記録コミット `1dc687d` はマージ前のブランチ上にある。「マージ後に司令塔が書く」は実運用と食い違っており、PR 時に寄せれば必ず落ちるという Issue の懸念は生じない |
| 置き場所 | **新規ワークフロー `.github/workflows/record-hygiene.yml`**(`ci.yml` に同居させない) | 逃げ道ラベルの付与とボディ編集で再判定させるため `pull_request` の `types` を広げる必要がある。`ci.yml` で広げると `quality`(npm ci + lint + test)までラベル操作のたびに再実行される |
| 判定ロジックの実体 | **`.claude/scripts/check-record-hygiene.sh`**(入力はすべて環境変数) | yaml 内にロジックを埋めると手元で再現できない。既存の `check-guard-integrity.sh` と同じ「スクリプトが判定し、ワークフローは annotation に変換するだけ」の形に揃える。`ci.yml` の `harness-integrity` が `.claude/scripts/*.sh` に `bash -n` と実行権限検査をかけるため、この層に置くと自動で構文検査も付く |
| 逃げ道 | ラベル 2 つ。`no-changelog` / `no-decision-record` | 1 つにまとめると片方を外すためにもう片方まで外れる |
| 対象 Issue の絞り込み | close キーワードで参照される Issue のうち **`ticket` ラベルが付いているもの**だけ | `/fix-issue` のバグ Issue やドキュメント PR で鳴らせない。ラベル照会は `gh api` + `GITHUB_TOKEN` で完結し、シークレット追加は不要 |
| CHANGELOG のトリガパス | `.claude/` / `.husky/` / `.codex/` / `AGENTS.md` の **4 系統に限定する** | Issue #37 のスコープがこの 4 つ。`template-manifest.json` の owned / merge は `.github/workflows/*.yml` や `.gitignore` も含むが、**今回は広げない**(記録漏れの実績があるのはこの 4 系統)。`docs/` を入れないのは、CHANGELOG 自身と解説 HTML だけを直す PR で毎回鳴ると検知性が落ちるため。拡大は別チケットで検討する |

## 1. 新規: `.claude/scripts/check-record-hygiene.sh`

新規作成し、**実行権限を付ける**(`git update-index --chmod=+x .claude/scripts/check-record-hygiene.sh`。`core.fileMode=false` の環境では `chmod +x` だけでは index に反映されず `harness-integrity` が落ちる)。

全文:

```bash
#!/usr/bin/env bash
# チケット完了時の記録漏れ(CHANGELOG / decisions.jsonl)を機械的に検出する。
#
# なぜこの層に置くか: この 2 つの記録は散文の運用ルールだけでは 2 度守られなかった
# (CHANGELOG は 4 回連続 → 8 回連続と再発が悪化し、decisions.jsonl は検収フローから
# 外れた分岐で欠落した)。CI は Claude の枠を消費しない(.claude/rules/lead/review-policy.md)
# ため、機械的に判定できる部分はここに寄せる。
#
# 入力はすべて環境変数。CI(.github/workflows/record-hygiene.yml)からも手元からも
# 同じ形で渡せるようにしてあり、このスクリプト自身は gh にもネットワークにも依存しない
# (PR の事実を集めるのは呼び出し側の責務)。
#
#   CHANGED_FILES  改行区切りの変更パス一覧(リポジトリルート相対)
#   PR_LABELS      改行区切りの PR ラベル名
#   TICKET_ISSUES  改行区切りの Issue 番号。本 PR がクローズし、かつ ticket ラベルが
#                  付いているものだけを呼び出し側が絞り込んで渡す
#
# 出力は 1 行 1 件の "ERROR|メッセージ" / "NOTICE|メッセージ"。
# ERROR が 1 件でもあれば exit 1、無ければ exit 0。
#
# set -e は使わない。違反を数え上げてから終了コードを決めるため。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

CHANGELOG_PATH="docs/template-dev/CHANGELOG.md"
DECISIONS_PATH=".harness/decisions.jsonl"
CHANGELOG_ESCAPE_LABEL="no-changelog"
DECISIONS_ESCAPE_LABEL="no-decision-record"

# CHANGELOG の追記を要求する変更対象。末尾が / のものはディレクトリ配下すべてを指す
# (.claude/template-manifest.json の owned / merge の面に対応する)。
CHANGELOG_TRIGGERS=(".claude/" ".husky/" ".codex/" "AGENTS.md")

CHANGED_FILES="${CHANGED_FILES:-}"
PR_LABELS="${PR_LABELS:-}"
TICKET_ISSUES="${TICKET_ISSUES:-}"

errors=0

emit_error() {
  printf 'ERROR|%s\n' "$1"
  errors=$((errors + 1))
}

emit_notice() {
  printf 'NOTICE|%s\n' "$1"
}

has_label() {
  printf '%s\n' "$PR_LABELS" | grep -qxF "$1"
}

changed_contains() {
  printf '%s\n' "$CHANGED_FILES" | grep -qxF "$1"
}

# --- 検査1: CHANGELOG の記載漏れ ---
# while はヒアストリングで回す(パイプにすると subshell になり triggered が残らない)。
triggered=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  for p in "${CHANGELOG_TRIGGERS[@]}"; do
    case "$p" in
      */) case "$f" in "$p"*) triggered="$f" ;; esac ;;
      *) [ "$f" = "$p" ] && triggered="$f" ;;
    esac
    [ -n "$triggered" ] && break
  done
  [ -n "$triggered" ] && break
done <<< "$CHANGED_FILES"

if [ -n "$triggered" ]; then
  if changed_contains "$CHANGELOG_PATH"; then
    :
  elif has_label "$CHANGELOG_ESCAPE_LABEL"; then
    emit_notice "CHANGELOG 検査はラベル '${CHANGELOG_ESCAPE_LABEL}' によりスキップされました(検出した変更: ${triggered})"
  else
    emit_error "テンプレート同期の対象(${triggered})を変更していますが ${CHANGELOG_PATH} が更新されていません。/sync-template は syncedAt 以降の日付見出しだけを読むため、ここが欠けると取り込む側は [manual] 項目に気づけません。追記が不要な変更(リバート・誤字修正など)ならラベル '${CHANGELOG_ESCAPE_LABEL}' を付けてください"
  fi
fi

# --- 検査2: decisions.jsonl の記載漏れ ---
while IFS= read -r n; do
  [ -n "$n" ] || continue
  if has_label "$DECISIONS_ESCAPE_LABEL"; then
    emit_notice "decisions.jsonl 検査(#${n})はラベル '${DECISIONS_ESCAPE_LABEL}' によりスキップされました"
    continue
  fi
  if [ ! -f "${REPO_ROOT}/${DECISIONS_PATH}" ]; then
    emit_error "${DECISIONS_PATH} がありません(#${n} の委託判断を記録できません)"
    continue
  fi
  # "issue":29 が "issue":295 に誤マッチしないよう、直後を , か } に限定する
  if ! grep -Eq "\"issue\"[[:space:]]*:[[:space:]]*${n}[[:space:]]*[,}]" "${REPO_ROOT}/${DECISIONS_PATH}"; then
    emit_error "この PR は ticket #${n} をクローズしますが、${DECISIONS_PATH} に \"issue\": ${n} の行がありません。.claude/rules/lead/delegation-policy.md「実測の記録」に従い、PR を出す前に 1 行追記してください(往復回数と検収の指摘数は検収時点で確定しています)。記録が不要な場合はラベル '${DECISIONS_ESCAPE_LABEL}' を付けてください"
  fi
done <<< "$TICKET_ISSUES"

[ "$errors" -eq 0 ] || exit 1
exit 0
```

## 2. 新規: `.github/workflows/record-hygiene.yml`

全文:

```yaml
name: Record Hygiene

# チケット完了時の記録漏れ(CHANGELOG / decisions.jsonl)の機械的検査。
# ci.yml に同居させないのは、逃げ道ラベルの付与とボディ編集で即座に再判定させるために
# pull_request の types を広げる必要があり、ci.yml で広げると quality ジョブ
# (npm ci + lint + typecheck + test)までラベル操作のたびに再実行されるため。
on:
  pull_request:
    types: [opened, synchronize, reopened, edited, labeled, unlabeled]

concurrency:
  group: record-hygiene-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  record-hygiene:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
      pull-requests: read
      issues: read
    steps:
      - name: Checkout repository
        uses: actions/checkout@v7
        with:
          fetch-depth: 1

      # PR の「事実」の収集だけをここで行う(判定はしない)。
      # 判定は .claude/scripts/check-record-hygiene.sh に集約してあり、
      # 手元から同じ環境変数を渡せば同じ結果が再現できる。
      - name: Collect PR facts
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
          # PR ボディは環境変数経由で渡す(${{ }} を run に直接展開しない)
          PR_BODY: ${{ github.event.pull_request.body }}
        run: |
          set -uo pipefail

          # 変更ファイル一覧。--paginate で 100 件を超える PR でも取りこぼさない
          gh api --paginate "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/files" \
            --jq '.[].filename' > "${RUNNER_TEMP}/changed.txt"

          # ラベルはイベントペイロードから読む(API 呼び出し不要)
          jq -r '.pull_request.labels[].name' "$GITHUB_EVENT_PATH" > "${RUNNER_TEMP}/labels.txt"

          # PR ボディの close キーワードから Issue 番号を拾う
          printf '%s' "$PR_BODY" \
            | grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]+#[0-9]+' \
            | grep -oE '[0-9]+' | sort -u > "${RUNNER_TEMP}/closes.txt" || true

          # そのうち ticket ラベルが付いているものだけを検査対象にする
          # (/fix-issue のバグ Issue や単発のドキュメント PR で鳴らせないため)
          : > "${RUNNER_TEMP}/tickets.txt"
          while IFS= read -r n; do
            [ -n "$n" ] || continue
            if gh api "repos/${GITHUB_REPOSITORY}/issues/${n}" --jq '.labels[].name' 2>/dev/null \
                 | grep -qx 'ticket'; then
              echo "$n" >> "${RUNNER_TEMP}/tickets.txt"
            fi
          done < "${RUNNER_TEMP}/closes.txt"

          echo "changed=$(wc -l < "${RUNNER_TEMP}/changed.txt") tickets=$(tr '\n' ' ' < "${RUNNER_TEMP}/tickets.txt")"

      - name: Check record hygiene
        run: |
          # GitHub Actions の run: の既定シェルは `bash -e {0}`。set -uo pipefail を
          # 書いても -e は残るため、明示的に切る(残すとスクリプトの exit 1 で
          # ステップが即座に打ち切られ、annotation / Job Summary が出ない)。
          set +e
          set -uo pipefail

          OUT="$(CHANGED_FILES="$(cat "${RUNNER_TEMP}/changed.txt")" \
                 PR_LABELS="$(cat "${RUNNER_TEMP}/labels.txt")" \
                 TICKET_ISSUES="$(cat "${RUNNER_TEMP}/tickets.txt")" \
                 bash .claude/scripts/check-record-hygiene.sh)"
          rc=$?

          if [ -n "$OUT" ]; then
            printf '%s\n' "$OUT" | while IFS='|' read -r level msg; do
              case "$level" in
                ERROR) echo "::error title=チケット記録の漏れ::$msg" ;;
                NOTICE) echo "::notice title=チケット記録の検査スキップ::$msg" ;;
              esac
            done
          fi

          {
            echo "## チケット記録の検査"
            echo
            if [ -z "$OUT" ]; then
              echo "記録漏れは検出されませんでした。"
            else
              printf '%s\n' "$OUT" | while IFS='|' read -r level msg; do
                case "$level" in
                  ERROR) echo "- ❌ $msg" ;;
                  NOTICE) echo "- ⏭️ $msg" ;;
                esac
              done
            fi
          } >> "$GITHUB_STEP_SUMMARY"

          exit "$rc"
```

## 3. 変更: `.claude/template-manifest.json`

`owned` 配列の `".github/workflows/template-update-check.yml"` の直後に 1 行足す:

```json
    ".github/workflows/record-hygiene.yml",
```

(`.claude/scripts/` は既に `owned` にディレクトリで入っているため、スクリプト側の追加は不要。)

## 4. 変更: `.claude/rules/lead/delegation-policy.md`

末尾の「### 実測の記録」節を、以下で**まるごと置き換える**:

```markdown
### 実測の記録

チケット完了時に `.harness/decisions.jsonl` へ 1 行追記する(委託先・往復回数・検収の指摘数)。**上の閾値は初期値**であり、この実測で上下させる。

**書くのは PR を出す前**(検収が終わり、往復回数と指摘数が確定した時点)。マージ後に回すと記録そのものが落ちる — #23 は司令塔が検収指摘の反映まで自分で手を動かし、通常の検収フローから外れた分岐で欠落した。事後に埋めても `review_findings` は再構成値にしかならず、他エントリと精度が揃わない。

この 2 つの記録は CI(`.github/workflows/record-hygiene.yml`)が機械的に検査する。判定の実体は `.claude/scripts/check-record-hygiene.sh` で、環境変数を渡せば手元でも同じ結果を再現できる。

| 検査 | 落ちる条件 | 逃げ道ラベル |
| --- | --- | --- |
| `docs/template-dev/CHANGELOG.md` | `.claude/` / `.husky/` / `.codex/` / `AGENTS.md` を変更した PR で CHANGELOG が未更新 | `no-changelog` |
| `.harness/decisions.jsonl` | PR が `ticket` ラベル付き Issue を `Closes #N` でクローズするのに `"issue": N` の行が無い | `no-decision-record` |

**逃げ道ラベルは司令塔が理由を添えて付ける。** 鳴りっぱなしを避けるための弁であって、既定の回避手段ではない。
```

## 5. 触らないもの

- `docs/template-dev/CHANGELOG.md` — **実装フェーズでは一切触らない。** このファイルを PR の差分に入れた瞬間に検査1 が緑になり、「検出できること」(受け入れ条件1)を実 PR で確認できなくなる。CHANGELOG の記法追記と `## 2026-08-27` 節は、検出を確認したあとに司令塔が書く(`tasklist.md` の司令塔担当タスク)
- `.harness/decisions.jsonl` — 同じ理由。検収完了後に司令塔が 1 行追記する
- `ci.yml` — 触らない
- ラベル `no-changelog` / `no-decision-record` の作成 — `gh label create` は司令塔が行う

## 6. 手元での検証(実装者が行う)

`.harness/decisions.jsonl` は実在の `"issue":29` の行を持つので、そのまま fixture として使える。作業ディレクトリはリポジトリルート。

```bash
S=.claude/scripts/check-record-hygiene.sh

# 検証1: トリガパスを変更し CHANGELOG 無し → ERROR 1 件 / exit 1
CHANGED_FILES=$'.claude/scripts/foo.sh' PR_LABELS='' TICKET_ISSUES='' bash "$S"; echo "rc=$?"
# 期待: ERROR|... が 1 行 / rc=1

# 検証2: CHANGELOG も変更されている → 出力なし / exit 0
CHANGED_FILES=$'.claude/scripts/foo.sh\ndocs/template-dev/CHANGELOG.md' PR_LABELS='' TICKET_ISSUES='' bash "$S"; echo "rc=$?"
# 期待: 出力なし / rc=0

# 検証3: 逃げ道ラベル → NOTICE 1 件 / exit 0
CHANGED_FILES=$'.claude/scripts/foo.sh' PR_LABELS=$'no-changelog' TICKET_ISSUES='' bash "$S"; echo "rc=$?"
# 期待: NOTICE|... が 1 行 / rc=0

# 検証4: トリガ外のパスのみ → 出力なし / exit 0
CHANGED_FILES=$'docs/prd.md\nsrc/index.ts' PR_LABELS='' TICKET_ISSUES='' bash "$S"; echo "rc=$?"
# 期待: 出力なし / rc=0

# 検証5: AGENTS.md(完全一致のトリガ) → ERROR / exit 1
CHANGED_FILES=$'AGENTS.md' PR_LABELS='' TICKET_ISSUES='' bash "$S"; echo "rc=$?"
# 期待: ERROR|... / rc=1
# 参考: AGENTS.md.bak のような前方一致は鳴らないこと
CHANGED_FILES=$'AGENTS.md.bak' PR_LABELS='' TICKET_ISSUES='' bash "$S"; echo "rc=$?"
# 期待: 出力なし / rc=0

# 検証6: 記録済み Issue(#29 は decisions.jsonl に実在) → 出力なし / exit 0
CHANGED_FILES='' PR_LABELS='' TICKET_ISSUES=$'29' bash "$S"; echo "rc=$?"
# 期待: 出力なし / rc=0

# 検証7: 未記録 Issue → ERROR / exit 1
CHANGED_FILES='' PR_LABELS='' TICKET_ISSUES=$'37' bash "$S"; echo "rc=$?"
# 期待: ERROR|... / rc=1

# 検証8: 桁の誤マッチをしない(#2 は decisions.jsonl に無い。"issue":20 等に誤マッチしないこと)
CHANGED_FILES='' PR_LABELS='' TICKET_ISSUES=$'2' bash "$S"; echo "rc=$?"
# 期待: ERROR|... / rc=1

# 検証9: decisions の逃げ道ラベル → NOTICE / exit 0
CHANGED_FILES='' PR_LABELS=$'no-decision-record' TICKET_ISSUES=$'37' bash "$S"; echo "rc=$?"
# 期待: NOTICE|... / rc=0

# 検証10: 両方の違反が同時に出る → ERROR 2 件 / exit 1
CHANGED_FILES=$'.husky/pre-commit' PR_LABELS='' TICKET_ISSUES=$'37' bash "$S"; echo "rc=$?"
# 期待: ERROR|... が 2 行 / rc=1

# 検証11: 構文と実行権限(CI の harness-integrity と同じ検査)
bash -n "$S" && echo "syntax ok"
git ls-files -s "$S"   # 期待: モードが 100755
```

**yaml の構文検証**(実装者が行う):

```bash
python3 -c "import sys,yaml;yaml.safe_load(open('.github/workflows/record-hygiene.yml'))" && echo "yaml ok"
# python3 に PyYAML が無い環境では代替として:
node -e "console.log(require('fs').readFileSync('.github/workflows/record-hygiene.yml','utf8').length)"
```

PyYAML が無ければスキップしてよい(実 PR での起動が最終確認)。ただし**スキップした場合は verification.md に明記する**。

## 7. 品質チェック

`npm run format:check` は `.github/workflows/*.yml` と `.json` を対象に含む。**prettier が整形を要求する場合は `npm run format` を実行してから再確認する**。`npm run lint` / `typecheck` / `test` は本変更の対象外だが、`/check` で一括して通す。

## 8. 記録(実装者が書く)

`.steering/20260827-issue37-record-hygiene-ci/verification.md` に、§6 の各検証の実行コマンドと実際の出力(rc を含む)を残す。期待と違った場合は**修正せずに停止して報告する**。
