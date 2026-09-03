# 設計: 検収時のホスト実行の明文化と、ライフサイクル差分の警告層

<!-- status: ready -->

司令塔(Opus)が下した設計判断はこのファイルに書き切ってある。**実装者は設計判断を行わない。**
判断が必要になったら「判断待ち」で停止すること。

## 0. 司令塔が下した設計判断(3 つ)

### 判断 D-1: C4 の既定は `delegate-codex.sh review`。`/code-review ultra` は昇格先

**200 行以上かつ重要変更のレビューは `delegate-codex.sh review` を既定とし、`/code-review ultra` は昇格先とする。両方は回さない。**

理由は起動主体とコスト:

- `/code-review ultra` は**ユーザー起動 + 課金**で、司令塔からは起動できない。かつ温存したい Claude 枠を消費する
- `delegate-codex.sh review` は read-only で司令塔が自分で起動でき、別ベンダーの第二意見にもなる

`/code-review ultra` をユーザーに**提案する**のは次の 2 つだけ:

1. **その差分自体を Codex が書いた**(impl 委託の成果)— 同じベンダーに自分の成果をレビューさせても第二意見にならない
2. **Codex が使えない**(`exit 3` / レート上限)

### 判断 D-2: モード別の担保先(検収を飛ばすモードで層が消えないようにする)

| モード | 担保 |
| --- | --- |
| A(通常) | 司令塔が `/check` の**前に**目視 + `delegate-codex.sh` 出口検査の警告 |
| B(節約) | 検収を飛ばすため、**draft PR を作る前に人間が目視する**。出口検査の警告は委託を叩いた人間の端末に出る |
| C(縮退) | **`delegate-codex.sh` を通らないため出口検査が効かない。**`check-guard-integrity.sh degraded` の新検査 D4 が報告する(復帰検収と、縮退中の push 前) |

モード C を出口検査で担保できないのがこの判断の要点。モード C は `.codex/skills/degraded-mode-ticket` で Codex が直接動くため、`delegate-codex.sh` の出口検査は 1 度も走らない。既に「復帰時に最初に回す」「縮退中の push 前にも回す」導線がある `check-guard-integrity.sh degraded` に相乗りさせる。

### 判断 D-3: 警告は「ブロックしない」。過検出側に倒す

`package.json` は委託禁止領域に**入れない**(スコープ外で確定済み)。正当な `scripts` 変更が普通にあるため、止めると層そのものが無視されるようになる。したがって:

- `delegate-codex.sh` 側は SUMMARY と stderr に警告を出すだけで、`status` / 終了コードを変えない
- `jq` が無い環境ではファイル全体のハッシュに落ちる(依存追加でも鳴る)。**過検出側に倒す**。`jq` は入口検査0 の必須コマンド一覧に無いため必須化しない(それは Issue #63 の担当)

---

## 1. `docs/template-dev/codex-delegation-plan.md` §9 への追記

### 挿入位置

§9 の箇条書きのうち **「**サンドボックスの穴**: Codex の内部コマンドは …」の項目の直後**(次の「**`.codex/` は Codex 自身が書き込めない**」より前)。関連する話題を隣に置く。

### 挿入する本文(そのまま入れる)

```markdown
- **検収時のホスト実行は塞げない(受容する判断)**: sandbox(ネットワーク無効 + `workspace-write`)が守るのは**委託が動いている間だけ**で、委託が終わった時点から先は「委託成果をホスト上・ネットワーク有効で実行する」行為になる。太い経路は 3 つあり、いずれも**原理的に塞げない**:
  - **`package.json` の `scripts`** — `/check` / `test-runner` が回す `npm test` / `npm run lint`。`package.json` は委託禁止領域に**入れていない**(依存やスクリプトを触る正当な委託が多く、禁止すると委託の余地を過度に狭めるため)
  - **`lint-staged` の設定**(同じく `package.json` 内)— `.husky/pre-commit` から呼ばれるので、コミットの瞬間にホスト上で走る
  - **テストコードそのもの** — 委託成果を実行しないと検収が成立しない以上、定義上避けられない

  `AGENTS.md` の verify-probe 形式検査(入口検査3)が塞いだのは「AGENTS.md 改ざん → 次回委託時のホスト実行」という**細い**経路にすぎない。上の 3 つはそれより太く、かつ塞ぐと委託そのものが成立しなくなる。実質の境界は **devcontainer** であり、その devcontainer は bubblewrap(sandbox の実体)のために `--security-opt seccomp=unconfined` で動いていて**既定より弱い**(§10.6)。

  **これは受容する判断であって、塞げるふりをしない。** 「委託成果のコードはいずれホスト上で実行する」以上、残せるのは検収の作法と警告層だけになる:

  | 層 | 中身 |
  | --- | --- |
  | 作法 | `package.json` のライフサイクル系差分(`scripts` / `lint-staged` / `prepare`)は `/check` を回す**前に**目視する(`.claude/rules/lead/review-policy.md`。`code-reviewer` の重点範囲にも入れてある) |
  | 警告(モード A/B) | `delegate-codex.sh` の出口検査が、impl 委託の前後で当該節に差分があれば警告する。**ブロックはしない**(正当な変更が普通にあり、止めると層が無視されるため) |
  | 警告(モード C) | モード C は `delegate-codex.sh` を通らないため出口検査が効かない。`check-guard-integrity.sh degraded` の **D4** が `Codex-authored` コミットの `package.json` 変更を報告する(復帰検収と、縮退中の push 前に回す) |

  **残る限界**: どの層も「人間が差分を読む」ことに帰着する。テストコード自体の悪性は差分検査では捕まらない。ここを機械的に塞ぐには検収を sandbox 内で回す仕組みが要るが、規模が別チケットになる(Issue #60 のスコープ外)。
```

---

## 2. `.claude/rules/lead/review-policy.md` への追記

### 2-1. 三層表の直後(`/check` を「実装中に…」の行の**直後**)に挿入

```markdown
- **`/check` を回す前に `package.json` のライフサイクル系差分を目視する**(`scripts` / `lint-staged` / `prepare`)。`npm test` / `npm run lint` / `lint-staged` は**委託成果をホスト上・ネットワーク有効で実行する**経路で、sandbox はここを守らない(根拠: `docs/template-dev/codex-delegation-plan.md` §9)。委託を挟んだ差分では必ず見る:

  ```bash
  git diff -- package.json
  ```

  検収を飛ばすモードでも層が消えないよう、担保先をモードごとに決めてある:

  | モード | 担保 |
  | --- | --- |
  | A(通常) | 司令塔がこの目視を行う + `delegate-codex.sh` 出口検査の警告 |
  | B(節約) | **draft PR を作る前に人間が目視する**(`.claude/rules/mode/econ.md`) |
  | C(縮退) | `delegate-codex.sh` を通らないため出口検査が効かない。`check-guard-integrity.sh degraded` の D4 が報告する(`.claude/rules/mode/degraded.md`) |
```

### 2-2. `Agent Teams 並行レビュー / /code-review ultra` の項目を D-1 の結論に差し替える

**現行の行**(これを置き換える):

```markdown
- **Agent Teams 並行レビュー / `/code-review ultra`**: **200 行以上 かつ 重要変更(認証・決済・データ移行・アーキテクチャ変更)** のときのみ提案する。通常の大きめ差分には使わない
```

**差し替え後**:

```markdown
- **200 行以上 かつ 重要変更(認証・決済・データ移行・アーキテクチャ変更)のレビュー**: **既定は `delegate-codex.sh review`**。`/code-review ultra` と Agent Teams 並行レビューは**昇格先**であって、既定と併用しない(同じ発動条件に 2 つの手段を割り当てると両方回す運用崩れになる。#60 / C4)
  - 理由は起動主体とコスト: `/code-review ultra` は**ユーザー起動 + 課金**で司令塔からは起動できず、温存したい Claude 枠を消費する。`delegate-codex.sh review` は read-only で司令塔が自分で起動でき、別ベンダーの第二意見にもなる
  - `/code-review ultra` を**ユーザーに提案する**のは次の 2 つだけ: (1) **その差分自体を Codex が書いた**(impl 委託の成果。同じベンダーの自己レビューは第二意見にならない)、(2) **Codex が使えない**(`exit 3` / レート上限)
  - 通常の大きめ差分にはどちらも使わない(主レビューは実装中の `code-reviewer`)
```

---

## 3. `.claude/rules/lead/delegation-policy.md` への追記(D-1 の同一結論)

### 3-1. 粒度表の「**重要変更のレビュー**」行の判定基準セルを差し替える

**現行**: `| **重要変更のレビュー** | `delegate-codex.sh review` | 200 行以上かつ認証・決済・データ移行・アーキテクチャ変更 | `/code-review ultra` の発動条件と同一 |`

**差し替え後**(4 列目のみ変更):

```
| **重要変更のレビュー** | `delegate-codex.sh review` | 200 行以上かつ認証・決済・データ移行・アーキテクチャ変更 | **この条件の既定はこちら。**`/code-review ultra` は昇格先で、併用しない(下記) |
```

### 3-2. 表の直下の箇条書き(「最小は…」「最大は…」「並行数は…」)の**直後**に追記

```markdown
### 重要変更のレビューは `delegate-codex.sh review` が既定(`/code-review ultra` は昇格先)

**200 行以上かつ重要変更(認証・決済・データ移行・アーキテクチャ変更)のレビューは `delegate-codex.sh review` を既定とし、`/code-review ultra` は昇格先とする。両方は回さない。** かつては同じ発動条件に別々の手段が割り当たっていて、両方回す運用崩れの余地があった(#60 / C4)。

- **理由は起動主体とコスト**: `/code-review ultra` は**ユーザー起動 + 課金**で司令塔からは起動できず、温存したい Claude 枠を消費する。`delegate-codex.sh review` は read-only で司令塔が自分で起動でき、別ベンダーの第二意見にもなる
- **`/code-review ultra` をユーザーに提案するのは 2 つだけ**: (1) **その差分自体を Codex が書いた**(impl 委託の成果。自己レビューは第二意見にならない)、(2) **Codex が使えない**(`exit 3` / レート上限)

同じ結論を `.claude/rules/lead/review-policy.md` にも書いてある。**片方だけ直さないこと。**
```

---

## 4. `.claude/rules/mode/econ.md`(モード B)への追記

「### 司令塔の作法」の番号付きリストに項目を挿入する。**現行の 5 番(`decisions.jsonl` を書く前に…)の直前**に入れ、以降の番号を繰り下げる(現行 5 → 6)。

```markdown
5. **委託を挟んだら、draft PR を作る前に `git diff -- package.json` でライフサイクル系(`scripts` / `lint-staged` / `prepare`)を目視する。** このモードは検収を CI に預けるが、**CI が回す `npm test` 自体が委託成果**である以上、ここを見ないと層が 1 枚も残らない(根拠: `docs/template-dev/codex-delegation-plan.md` §9)
```

---

## 5. `.claude/rules/mode/degraded.md`(モード C)への追記

### 5-1. 手順 1 の説明文に D4 を足す

**現行の文**: 「縮退モードは `.git` が書き込み可能な唯一の経路で、`core.hooksPath` の書き換え・`.git/hooks/` への直書き・`.git/config` のホストコマンド実行ベクタ・禁止領域を触った `Codex-authored` コミットを検出する。」

**差し替え後**: 末尾に 1 項目足す。

```
   縮退モードは `.git` が書き込み可能な唯一の経路で、`core.hooksPath` の書き換え・
   `.git/hooks/` への直書き・`.git/config` のホストコマンド実行ベクタ・禁止領域を触った
   `Codex-authored` コミット・**`Codex-authored` コミットによる `package.json` の変更**
   を検出する。
```

### 5-2. 「### 復帰時の検収(§2.3)」の手順 4 の直前(= 手順 3 の直後)に手順を挿入し、以降を繰り下げる

現行の 4(通常フローの検収)→ 5、5(PR を作る)→ 6 になる。挿入する新しい 4:

```markdown
4. **`git diff [base]..HEAD -- package.json` でライフサイクル系(`scripts` / `lint-staged` / `prepare`)を目視する。** モード C は `delegate-codex.sh` を通らないため、出口検査の同種の警告が 1 度も走っていない。次の手順で回す `/check` は**委託成果をホスト上で実行する**ので、実行前に見る(根拠: `docs/template-dev/codex-delegation-plan.md` §9)。手順 1 の D4 が該当コミットを名指ししていれば必ず確認する
```

---

## 6. `.claude/agents/code-reviewer.md` への追記

「## チェック観点(優先順)」の **1. セキュリティ** の行の直下に、サブ項目として足す(番号は振り直さない)。

```markdown
1. **セキュリティ**: XSS / CSRF / 認可漏れ / SQL injection / 機密情報のログ出力 / PII の扱い
   - **委託成果のホスト実行経路**: `package.json` の `scripts` / `lint-staged` / `prepare` に差分があれば**必ず内容を読む**。これらは検収(`npm test` / `npm run lint` / `lint-staged`)がサンドボックスの**外**で実行する経路で、委託先が書き換えられる(根拠: `docs/template-dev/codex-delegation-plan.md` §9)
```

---

## 7. `.claude/scripts/delegate-codex.sh` — 出口検査に警告を足す

### 7-1. ヘルパー関数を追加する

**挿入位置**: `forbidden_snapshot()` の閉じ `}` の直後、「`# ---- 事前スナップショット(exit 0 の裏取りに使う。impl 以外では取らない) ----`」のコメントより**前**。

```bash
# ---- package.json のライフサイクル系差分(警告のみ)のヘルパー ----
#
# sandbox が守るのは委託の実行中だけで、検収で回す npm test / npm run lint /
# lint-staged は「委託成果をホスト上・ネットワーク有効で実行する」経路になる
# (codex-delegation-plan.md §9)。package.json は委託禁止領域に入れない判断なので
# (依存や scripts を触る正当な委託が多い)、ここは警告だけを出す層にする。
#
# ブロックしない理由: 正当な scripts 変更が普通にあり、止めると層そのものが無視される。
#
# jq があるときはライフサイクル節だけを抜き出して比べる(prepare は scripts の中の
# キーなので scripts を見れば覆う)。jq が無いときはファイル全体のハッシュに落ちるため
# 依存追加でも鳴るが、警告しか出さない層なので過検出側に倒す。jq を必須化しないのは
# 入口検査0 の必須コマンド一覧に無いため(必須化は Issue #63 の担当)。
#
# 空振り条件: package.json が無いプロジェクトでは常に空文字列になり、前後が一致して
# 何も出ない(Node 以外のスタックでは正しい挙動)。
lifecycle_snapshot() {
  [ -f package.json ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -S '{scripts: .scripts, "lint-staged": ."lint-staged"}' package.json 2>/dev/null ||
      git hash-object -- package.json 2>/dev/null || true
  else
    git hash-object -- package.json 2>/dev/null || true
  fi
}
```

### 7-2. 事前スナップショットを取る

`FORBIDDEN_BEFORE="$(forbidden_snapshot)"` の**直後**に 1 行足す(同じ `if [ "$MODE" = "impl" ]; then` ブロック内):

```bash
  LIFECYCLE_BEFORE="$(lifecycle_snapshot)"
```

### 7-3. 出口検査の警告ブロックを追加する

**挿入位置**: 禁止領域の出口検査(`if [ "$MODE" = "impl" ]; then` … `fi`)の閉じ `fi` の**直後**、`if [ "$CODEX_EXIT" -ne 0 ]; then` の**前**。

位置の理由は禁止領域検査と同じで、**レート上限・異常終了の無条件 exit より前に置かないと丸ごと素通しになる**ため。ただし禁止領域検査と違い、ここは `exit` しない。

```bash
# ---------- 出口検査(警告のみ): package.json のライフサイクル系差分 ----------
#
# 禁止領域の検査と違い **ブロックしない**(判断 D-3 / codex-delegation-plan.md §9)。
# 位置は禁止領域検査の直後・CODEX_EXIT の分岐より前で、上限や失敗で終わった委託でも
# 警告が出るようにしてある。rate-limited の経路は SUMMARY を捨てる(write_record に
# 空文字列を渡す)ので、stderr にも同じ内容を書く。
if [ "$MODE" = "impl" ]; then
  LIFECYCLE_AFTER="$(lifecycle_snapshot)"
  if [ "$LIFECYCLE_AFTER" != "$LIFECYCLE_BEFORE" ]; then
    SUMMARY="⚠️ package.json のライフサイクル系(scripts / lint-staged / prepare)に差分があります。
/check を回す前に \`git diff -- package.json\` で内容を確認してください
(検収は委託成果をホスト上・ネットワーク有効で実行します。codex-delegation-plan.md §9)。

$SUMMARY"
    cat >&2 <<'MSG'
delegate-codex: 警告 — package.json のライフサイクル系(scripts / lint-staged / prepare)に
差分があります。これらは検収(npm test / npm run lint / lint-staged)がサンドボックスの
外で実行する経路です。/check を回す前に内容を確認してください:

  git diff -- package.json

これは警告です。委託は失敗にしていません。
MSG
  fi
fi
```

**注意(実装者向け)**: `SUMMARY` の代入はダブルクォート内なので、`\`git diff …\`` のバックスラッシュ・エスケープをそのまま維持すること。stderr 側は `<<'MSG'`(クォート付きヒアドキュメント)なので展開されない。

---

## 8. `.claude/scripts/check-guard-integrity.sh` — D4 を足す

**挿入位置**: D3 のブロック(`fi` で閉じる `if [ -z "$FORBIDDEN_LIST" ]; then … else … fi`)の**直後**、最終行の `exit "$FOUND"` の**前**。

`DEGRADED_RANGE` は D3 の手前で確定済みなのでそのまま使える。**D3 の `else` の内側に入れないこと**(`--print-forbidden` が失敗したときに D4 まで一緒に落ちる)。

```bash
# --- D4) 縮退中コミットが package.json を変更していないか ---
#
# モード C は delegate-codex.sh を通らないため、出口検査の同種の警告
# (scripts / lint-staged / prepare の差分)が 1 度も走らない。ここが唯一の層になる。
#
# 判定は「Codex-authored コミットが package.json を変更したか」までで、節の中身までは
# 見ない。このスクリプトは jq を必須にしていないうえ、報告先の人間はどのみち
# git diff を読む必要があるため。D1/D2/D3 と同じく報告のみで停止しない。
while IFS= read -r _sha; do
  [ -n "$_sha" ] || continue
  if git show --pretty=format: --name-only "$_sha" 2>/dev/null | grep -Fxq 'package.json'; then
    note "縮退中のコミット $_sha が package.json を変更している。scripts / lint-staged / prepare に差分が無いか git diff で確認すること(検収でホスト上・ネットワーク有効で実行される。codex-delegation-plan.md §9)"
  fi
done < <(git log --grep='Codex-authored' --format='%h' "$DEGRADED_RANGE" 2>/dev/null)
```

---

## 9. `docs/template-dev/CHANGELOG.md` への追記

**先頭の `---` 区切りの直後**に、新しい日付見出し `## 2026-09-03` を作って置く(既存の `## 2026-09-01` より上)。

```markdown
## 2026-09-03

**検収時のホスト実行をリスクとして明文化し、`package.json` ライフサイクル差分の警告層を足した(Issue #60)。** sandbox(ネットワーク無効 + `workspace-write`)が守るのは**委託が動いている間だけ**で、検収で回す `npm test` / `npm run lint` / `lint-staged` は「委託成果をホスト上・ネットワーク有効で実行する」行為になります。`package.json` の `scripts` は委託禁止領域の**外**(依存や scripts を触る正当な委託が多いため意図的に外してある)なので、委託先が自由に書き換えられます。**塞げないので受容し、作法と警告層だけを残す**という判断です。

- **[auto]** `delegate-codex.sh` の出口検査に、impl 委託の前後で `package.json` の `scripts` / `lint-staged` に差分があれば**警告する**層を追加しました。**ブロックはしません**(正当な変更が普通にあり、止めると層が無視されるため)。`jq` があれば当該節だけを、無ければファイル全体のハッシュを比べます
- **[auto]** `check-guard-integrity.sh degraded` に **D4** を追加しました。モード C は `delegate-codex.sh` を通らないため出口検査が効きません。`Codex-authored` コミットが `package.json` を変更していれば報告します(D1〜D3 と同じく報告のみ)
- **[auto]** `code-reviewer` の重点範囲に「`package.json` の `scripts` / `lint-staged` / `prepare` に差分があれば必ず内容を読む」を追加しました
- **[manual]** **200 行以上かつ重要変更のレビューは `delegate-codex.sh review` を既定とし、`/code-review ultra` は昇格先(併用しない)に決めました。** 従来は `delegation-policy.md` と `review-policy.md` が同じ発動条件に別の手段を割り当てており、両方回す余地がありました。**取り込む側の作業**: 重要変更のレビュー手段を独自に運用していた場合、どちらを既定にするか揃えてください(`/code-review ultra` はユーザー起動 + 課金で、司令塔からは起動できません)
- **[manual]** **モード B / C を運用しているプロジェクトは、検収手順に `git diff -- package.json` の目視を追加してください。** モード B は draft PR を作る前に、モード C は復帰検収の `/check` より前に見ます(`.claude/rules/mode/econ.md` / `degraded.md` に反映済み)
```

---

## 10. 検証(実装者が実測して `verification.md` に残す)

`.steering/20260903-issue60-host-exec-risk/verification.md` を作り、**実際に実行した出力を貼る**。推測で書かない。

1. **構文**: `bash -n .claude/scripts/delegate-codex.sh` と `bash -n .claude/scripts/check-guard-integrity.sh` が通る
2. **既存動作の非破壊**: `bash .claude/scripts/check-guard-integrity.sh` と `bash .claude/scripts/check-guard-integrity.sh degraded` が現状のリポジトリで従来どおり(D4 の誤爆が無いこと)
3. **D4 が鳴ること**: 一時ブランチで `package.json` に無害な差分(例: `scripts` に `"noop-issue60": "true"` を足す)を作り、コミットメッセージに `Codex-authored` トレーラーを入れてコミットしてから `GUARD_DEGRADED_RANGE=HEAD~1..HEAD bash .claude/scripts/check-guard-integrity.sh degraded` を実行し、D4 の行が出ることを確認する。**確認後、その一時コミットとブランチは必ず破棄する**(`git checkout` で作業ブランチに戻り、一時ブランチを削除する)
4. **出口検査の警告(受け入れ条件 3)**: `codex` CLI を実際に回さずに、`lifecycle_snapshot()` と警告ブロックの挙動を確認する。最小の確認手順:
   - `lifecycle_snapshot` 相当を手で 2 回評価し、`scripts` を書き換えた前後で戻り値が変わることを示す(`jq -S '{scripts: .scripts, "lint-staged": ."lint-staged"}' package.json` の出力を書き換え前後で比較する)
   - **警告がブロックしないこと**は、追加したブロックに `exit` / `write_record "failed"` / `emit` が含まれておらず、後続の判定(`CODEX_EXIT` 分岐・VERDICT 判定・成果実在確認)へそのまま落ちることをコードで示す(該当行を引用する)
   - `codex` CLI が使える環境なら実委託で確認してよいが、**必須にはしない**(CI にも devcontainer にも Codex は入っていない)
5. **`/check`**: `npm run lint` 等のプロジェクト標準チェックが通る

## 11. 触ってはいけないもの

- `package.json` を `FORBIDDEN_PATHS` に足さない(スコープ外で確定済み)
- `.devcontainer/` の `seccomp` 設定を変えない
- 警告を `exit` / `status=failed` に昇格させない
- 既存の D1 / D2 / D2.5 / D3、および禁止領域の出口検査のロジックを変更しない(**足すだけ**)
- `.harness/decisions.jsonl` は司令塔が PR 前に書く。実装者は触らない

---

## 12. 検収指摘への対応(司令塔の判断 / 1 巡目 = Critical 0 / Major 0 / Minor 4)

### Minor 1(§2.3 の手順リストが `degraded.md` と乖離)— **採用。ただし単一ソース化で直す**

指摘は正しい。`codex-delegation-plan.md` §2.3 の「Claude 復帰時の手順」(6 項目)は、`degraded.md` 側に足した手順(D1〜D4 のガードレール検査、`package.json` の目視)を 1 つも反映していない。**しかもこれは今回始まった乖離ではない** — #42(ガードレール健全性検査)/ #58(D2.5)/ #59 でも `degraded.md` だけを更新してきており、`degraded.md` 末尾が「根拠: §2.3」と書いている先が実際には古い手順のままになっている。

**1 行足して追随させる方式は採らない。** 同じ手順を 2 箇所に置き続ける限り、次のチケットでまた開く。このプロジェクトが `check-protected-branch.sh` / `branch-policy.json` / `latest-steering.sh` / `check_hooks_path()` で繰り返し採ってきた「判定と手順の実体は 1 箇所」に揃える。

**やること**: `codex-delegation-plan.md` §2.3 の「Claude 復帰時の手順:」から始まる 6 項目の番号付きリストを、**丸ごと次の文に置き換える**。

```markdown
Claude 復帰時の手順は **`.claude/rules/mode/degraded.md`「復帰時の検収」が単一ソース**(モード C のセッションに実際に注入されるのはそちらであり、この節を読んで動く経路は無い)。ここでは設計意図だけを述べる:

- **ガードレールの健全性検査を最初に回す**(`check-guard-integrity.sh degraded`)。モード C は `.git` が書き込み可能な唯一の経路で、入口検査も出口検査も掛かっていない
- **`codex-log.md` の「設計判断」欄を `design.md` へ回収する**(§2.3.1)。ここが例外を閉じる工程
- **通常フローの検収(`/check` + `code-reviewer`)を省略しない**。モード C の成果は、それまで一度も検証されていない
- **Issue のラベル・コメント更新はここでまとめて行う**(モード C 中は sandbox がネットワーク無効なので保留されている)

手順を増やすときは `degraded.md` 側だけを直す。**この節に手順を書き戻さないこと**(#42 / #58 / #59 / #60 で実際に乖離した)。
```

**注意**: §2.3.1 以降の小節、および「モード C を始める前の 3 条件」の表・`codex-log.md` のテンプレートは**そのまま残す**(乖離しているのは復帰手順のリストだけ)。

### Minor 3(D4 が D3 と同じ `git log` を再実行)— **不採用。ただし意図をコメントに残す**

共有化は `DEGRADED_RANGE` の SHA 取得を D3 の `done < <(...)` 行ごと書き換えることになり、**§11 で禁じた「既存の D1/D2/D2.5/D3 を変更しない」に抵触する**。security-critical なスクリプトで変更面を広げない判断を、0.185s / 84 コミット(実測)のために崩さない。

ただし #59 の振り返りで「**意図的に見ないもの・意図的に重複させたものはその場でコメントを書く**」を既定にしたので、痕跡だけ残す。

**やること**: `check-guard-integrity.sh` の **D4 のコメントブロックの末尾**(`# 見ない。…報告のみで停止しない。` の行の直後)に 2 行足す。**D3 側は 1 文字も触らない。**

```bash
# git log を D3 と重複して回しているのは意図的。共有化には D3 のループ本体を書き換える
# 必要があり、実測 0.185s / 84 コミットに対して security-critical な差分を広げる方が高い。
```

### Minor 2(CHANGELOG の `[manual]` 判定)— **不採用(現状維持)**

`.claude/rules/` はマニフェスト上 `owned` = 自動上書きなので、**ファイルの取り込み作業**はゼロという指摘はそのとおり。ただしこのリポジトリの `[manual]` は「取り込む側に**判断・確認**が要る」意味でも一貫して使われてきた — 2026-09-01 の項目も、テンプレート所有ファイル(`AGENTS.md` / `.codex/skills/`)に対して「独自にカスタマイズしていた場合、…確認してください」という形で `[manual]` を付けている。今回の 2 項目(重要変更のレビュー手段の既定変更 / モード B・C の検収手順追加)はどちらも**取り込む側の運用が変わる**ため、この用法に一致する。`⚠️` を付けていないのも正しい(既存の運用は壊れない)。**変更しない。**

### Minor 4(`verification.md` が `lifecycle_snapshot()` を直接呼んでいない)— **不採用(現状維持)**

design §10 手順 4 が明示的に許容した水準であり、記載に嘘も推測も無い。加えて `delegate-codex.sh` は**起動直後に自身を一時ディレクトリへコピーして `exec` する**(#15)ため素直に `source` できず、関数を直接呼ぶには抽出が要る。得られる確度の差に見合わない。

**ただし残る限界は事実**: 警告ブロックは end-to-end で 1 度も実行されていない(この環境に `codex` CLI が無い)。これは `verification.md` §4 に既に書かれているので追記不要。
