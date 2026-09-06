# 検証記録: 出口検査の誤爆を止める(Issue #81)

design.md §5 の V1〜V7 をすべて `CODEX_DELEGATE_NO_SELF_COPY=1` を付けずに回した(既定経路)。

## V1: 構文と整形

```bash
bash -n .claude/scripts/delegate-codex.sh && bash -n .claude/scripts/codex-run.sh && echo "V1 PASS"
```

結果: `V1 PASS`

```bash
npx prettier --check .steering/20260905-issue81-exit-check-false-positive/*.md .claude/rules/lead/delegation-policy.md docs/template-dev/CHANGELOG.md
```

結果: `All matched files use Prettier code style!`(`docs/template-dev/codex-delegation-plan.md` /
`.claude/scripts/delegate-codex.sh` / `.claude/scripts/codex-run.sh` も個別に prettier を通し、
同じく問題なし)。

## V2: 禁止領域の一覧が変わっていないこと

```bash
bash .claude/scripts/delegate-codex.sh --print-forbidden | LC_ALL=C sort -u > /tmp/fp-after.txt
git stash && bash .claude/scripts/delegate-codex.sh --print-forbidden | LC_ALL=C sort -u > /tmp/fp-before.txt && git stash pop
diff /tmp/fp-before.txt /tmp/fp-after.txt && echo "V2 PASS(出力は不変)"
```

結果: `diff` 差分なし → `V2 PASS(出力は不変)`。`.harness/codex-runs/` を含む一覧は実装前後で完全一致した。

```bash
bash .claude/scripts/check-forbidden-paths-doc.sh && echo "V2b PASS"
```

結果: `V2b PASS`

## V3: `record_state_snapshot()` の単体確認

```bash
mkdir -p /tmp/rec-t && printf '{"id":"x","status":"completed","accepted":false}\n' > /tmp/rec-t/x.json
jq -r '[(.status // "MISSING"), (if .accepted == null then "MISSING" else (.accepted | tostring) end)] | join(" ")' /tmp/rec-t/x.json
printf '{"id":"y"}\n' > /tmp/rec-t/y.json
jq -r '[(.status // "MISSING"), (if .accepted == null then "MISSING" else (.accepted | tostring) end)] | join(" ")' /tmp/rec-t/y.json
rm -rf /tmp/rec-t
```

結果:

- `x.json`(`status`/`accepted` あり)→ `completed false`(期待どおり)
- `y.json`(両方欠損)→ `MISSING MISSING`(期待どおり)

## V4/V5: 出口検査の比較ロジック(design 1-2 の表)の再現テスト

Codex CLI を使わず、`record_state_snapshot()` の出力を模した BEFORE/AFTER 文字列を
新しい出口検査ブロックと同一のループ(`awk` による突き合わせ)に通すシェル関数を
スクラッチパッドに作成し(`recstate-check.sh`)、実際に走らせて確認した。

### V4: 並行 explore が impl を落とさないこと(B1 の再現テスト)

```bash
B='a.json running false
b.json completed true'
A='a.json completed false
b.json completed true
c.json running false'
```

結果: `NO VIOLATIONS`(違反 0 件)。BEFORE で `running` だった `a.json` の `status` 変化
(並行 explore/review 自身の正常終了)は違反にならず、AFTER にしか無い `c.json`
(並行 run の新規作成)も無視されることを確認した。

### V5: 守りたい性質が消えていないこと

| ケース | BEFORE | AFTER | 結果 |
| --- | --- | --- | --- |
| accepted の書き換え | `a.json completed false` | `a.json completed true` | `VIOLATIONS: a.json(accepted: false → true)` |
| 完了済み record の status 詐称 | `a.json failed false` | `a.json completed false` | `VIOLATIONS: a.json(status: failed → completed)` |
| record の削除 | `a.json completed false` | (行なし) | `VIOLATIONS: a.json(削除された)` |

3 ケースすべてが期待どおり違反として拾われた。

## V6: `codex-run.sh` の実行中ロック

```bash
mkdir -p .harness/codex-runs
cat > .harness/codex-runs/v6-test.json <<JSON
{"id":"v6-test","mode":"impl","status":"running","pid":$$,"accepted":false}
JSON
bash .claude/scripts/codex-run.sh accept v6-test; echo "exit=$?"
```

結果: 拒否メッセージ(`codex-run: impl 委託が実行中です(id=v6-test pid=...)。実行中は
record の書き換えを受け付けません。`)+ `exit=1`

```bash
CODEX_RUN_FORCE=1 bash .claude/scripts/codex-run.sh accept v6-test; echo "exit=$?"
```

結果: `accepted: v6-test` + `exit=0`

```bash
bash .claude/scripts/codex-run.sh pending >/dev/null; echo "pending exit=$?"
```

結果: `pending exit=0`(読み取り系は止めないことを確認)

後始末: `rm -f .harness/codex-runs/v6-test.json` を実行し、`git status --porcelain` で
`.harness/codex-runs/` 配下に変更が残っていないことを確認した。

## V7: ガードレールの健全性

```bash
bash .claude/scripts/check-guard-integrity.sh && echo "V7 PASS(無出力・exit 0)"
```

結果: 標準出力・標準エラーとも空、`exit=0`。

## まとめ

V1〜V7 すべてで期待どおりの結果を得た。`.harness/codex-runs/` を内容ハッシュ比較の対象から
外しても `FORBIDDEN_PATHS` / `--print-forbidden` の出力は変わらず(V2)、並行 explore/review が
impl を誤って `failed` にする経路は再現テストで消えたことを確認した(V4)。一方で
`accepted` の書き換え・`status` の詐称・record の削除は引き続き違反として検出される(V5)。
`codex-run.sh` の書き込み系は impl 実行中のみ拒否され、`CODEX_RUN_FORCE=1` で強行可能、
読み取り系(`pending`)は影響を受けない(V6)。

## 検収の指摘反映(code-reviewer 1 巡目 Minor 4件)の再検証(T24〜T29)

T20〜T23(`cmd_prune --dry-run` の実行中ロック除外 / `record_state_snapshot()` の識別子から
`.json` を落とす / `delegation-policy.md` の句点 / `RECSTATE_BEFORE` の窓についてのコメント)
を反映した後、design §5 を回し直した。

### T24: V1 相当(構文・整形)

```bash
bash -n .claude/scripts/delegate-codex.sh && bash -n .claude/scripts/codex-run.sh && echo "SYNTAX PASS"
npx prettier --check .steering/20260905-issue81-exit-check-false-positive/*.md .claude/rules/lead/delegation-policy.md docs/template-dev/CHANGELOG.md
```

結果: `SYNTAX PASS`、`All matched files use Prettier code style!`

### T25: `cmd_prune --dry-run` は実行中ロックの対象外であること

自分の pid を使った `status=running / mode=impl` の偽装 record を置いて確認した:

```bash
bash .claude/scripts/codex-run.sh prune --dry-run   # → exit=0(通る)
bash .claude/scripts/codex-run.sh prune             # → exit=1(拒否)
bash .claude/scripts/codex-run.sh accept t25-test   # → exit=1(拒否)
bash .claude/scripts/codex-run.sh set-status t25-test completed  # → exit=1(拒否)
```

結果: `prune --dry-run` のみ通り(`残す: t25-test (直近 20 本)` / `削除対象の record はありません`
/ `exit=0`)、フラグなしの `prune` と `accept` / `set-status` は同じ拒否メッセージで `exit=1`。
後始末(`rm -f .harness/codex-runs/t25-test.json`)実施済み、`git status --porcelain` で
`.harness/codex-runs/` 配下に変更なしを確認。

### T26: `record_state_snapshot()` の識別子が `.json` なしになること

`record_state_snapshot()` の本体を切り出して単体実行し、出力の 1 列目が
`20260905-999999-12345`(`.json` なし)になることを確認した。加えて、実際の
`.harness/codex-runs/` に偽装 record(`t26-test.json`)を置いて
`bash .claude/scripts/codex-run.sh show t26-test`(`.json` を付けない ID)を実行し、
`exit=0` で record が引けることを確認した。後始末実施済み。

### T27: V5 の再実行(識別子の形を変えた後)

比較ロジック(BEFORE/AFTER の突き合わせ)をそのままシェル関数として再現し、
`.json` なしの識別子で 3 ケースを実行した:

| ケース | BEFORE | AFTER | 結果 |
| --- | --- | --- | --- |
| accepted の書き換え | `a completed false` | `a completed true` | `VIOLATIONS: a(accepted: false → true)` |
| status 詐称 | `a failed false` | `a completed false` | `VIOLATIONS: a(status: failed → completed)` |
| record の削除 | `a completed false` | (行なし) | `VIOLATIONS: a(削除された)` |
| 並行 explore 正常終了(比較用) | `a running false` / `b completed true` | `a completed false` / `b completed true` / `c running false` | `VIOLATIONS: []`(違反なし) |

3 ケースとも期待どおり違反として拾われ、並行 run の正常な状態遷移は引き続き違反にならないことを確認した。

### T28: ガードレールの健全性

```bash
bash .claude/scripts/check-guard-integrity.sh; echo "exit=$?"
```

結果: 無出力・`exit=0`。
