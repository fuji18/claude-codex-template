# 検証記録: Issue #37 チケット記録の機械的検査

対象: `.steering/20260827-issue37-record-hygiene-ci/design.md` §6・§7

## design.md §6 手元検証(検証1〜11)

作業ディレクトリ: リポジトリルート。`S=.claude/scripts/check-record-hygiene.sh`

### 検証1: トリガパスを変更し CHANGELOG 無し

```
CHANGED_FILES=$'.claude/scripts/foo.sh' PR_LABELS='' TICKET_ISSUES='' bash "$S"; echo "rc=$?"
```

出力:
```
ERROR|テンプレート同期の対象(.claude/scripts/foo.sh)を変更していますが docs/template-dev/CHANGELOG.md が更新されていません。...(ラベル 'no-changelog' 案内)
rc=1
```

期待どおり(ERROR 1 件 / rc=1)。

### 検証2: CHANGELOG も変更されている

```
CHANGED_FILES=$'.claude/scripts/foo.sh\ndocs/template-dev/CHANGELOG.md' PR_LABELS='' TICKET_ISSUES='' bash "$S"; echo "rc=$?"
```

出力: なし / `rc=0`

期待どおり。

### 検証3: 逃げ道ラベル(no-changelog)

```
CHANGED_FILES=$'.claude/scripts/foo.sh' PR_LABELS=$'no-changelog' TICKET_ISSUES='' bash "$S"; echo "rc=$?"
```

出力:
```
NOTICE|CHANGELOG 検査はラベル 'no-changelog' によりスキップされました(検出した変更: .claude/scripts/foo.sh)
rc=0
```

期待どおり(NOTICE 1 件 / rc=0)。

### 検証4: トリガ外のパスのみ

```
CHANGED_FILES=$'docs/prd.md\nsrc/index.ts' PR_LABELS='' TICKET_ISSUES='' bash "$S"; echo "rc=$?"
```

出力: なし / `rc=0`

期待どおり。

### 検証5: AGENTS.md(完全一致トリガ)と前方一致の非マッチ

```
CHANGED_FILES=$'AGENTS.md' PR_LABELS='' TICKET_ISSUES='' bash "$S"; echo "rc=$?"
```
出力: `ERROR|...` / `rc=1`

```
CHANGED_FILES=$'AGENTS.md.bak' PR_LABELS='' TICKET_ISSUES='' bash "$S"; echo "rc=$?"
```
出力: なし / `rc=0`

期待どおり(AGENTS.md は鳴る、AGENTS.md.bak は鳴らない)。

### 検証6: 記録済み Issue(#29)

```
CHANGED_FILES='' PR_LABELS='' TICKET_ISSUES=$'29' bash "$S"; echo "rc=$?"
```

出力: なし / `rc=0`

期待どおり(`.harness/decisions.jsonl` に実在の `"issue":29` がヒット)。

### 検証7: 未記録 Issue(#37)

```
CHANGED_FILES='' PR_LABELS='' TICKET_ISSUES=$'37' bash "$S"; echo "rc=$?"
```

出力:
```
ERROR|この PR は ticket #37 をクローズしますが、.harness/decisions.jsonl に "issue": 37 の行がありません。...
rc=1
```

期待どおり。

### 検証8: 桁の誤マッチをしない(#2)

```
CHANGED_FILES='' PR_LABELS='' TICKET_ISSUES=$'2' bash "$S"; echo "rc=$?"
```

出力:
```
ERROR|この PR は ticket #2 をクローズしますが、.harness/decisions.jsonl に "issue": 2 の行がありません。...
rc=1
```

期待どおり(`"issue":20` 等の桁違いに誤マッチしていない)。

### 検証9: decisions の逃げ道ラベル

```
CHANGED_FILES='' PR_LABELS=$'no-decision-record' TICKET_ISSUES=$'37' bash "$S"; echo "rc=$?"
```

出力:
```
NOTICE|decisions.jsonl 検査(#37)はラベル 'no-decision-record' によりスキップされました
rc=0
```

期待どおり。

### 検証10: 両方の違反が同時に出る

```
CHANGED_FILES=$'.husky/pre-commit' PR_LABELS='' TICKET_ISSUES=$'37' bash "$S"; echo "rc=$?"
```

出力: ERROR が 2 行(CHANGELOG 未更新 / decisions.jsonl 未記録)/ `rc=1`

期待どおり。

### 検証11: 構文と実行権限

```
bash -n "$S" && echo "syntax ok"
git ls-files -s "$S"
```

出力:
```
syntax ok
100755 b673ab184e967175f13849b859bbb4a5d2cdd0a5 0	.claude/scripts/check-record-hygiene.sh
```

期待どおり(構文 OK、モード 100755)。

## yaml 構文検証

```
python3 -c "import sys,yaml;yaml.safe_load(open('.github/workflows/record-hygiene.yml'))" && echo "yaml ok"
```

結果: `ModuleNotFoundError: No module named 'yaml'`(このコンテナに PyYAML が入っていない)。

design.md §6 の指示どおり **スキップ**。実 PR での起動(record-hygiene ワークフローの実行)が最終確認となる。代替の Node.js 読み込みチェックは行わなかった(yaml パースの妥当性検証にはならないため、実 PR 確認に委ねる方が確実と判断)。

## npm run format:check

```
npm run format:check
```

結果: `All matched files use Prettier code style!`(整形不要、`npm run format` の実行は不要だった)。

## 触っていないことの確認

```
git status --short
```

出力:
```
 M .claude/rules/lead/delegation-policy.md
A  .claude/scripts/check-record-hygiene.sh
 M .claude/template-manifest.json
?? .github/workflows/record-hygiene.yml
?? .steering/20260827-issue37-record-hygiene-ci/
```

`docs/template-dev/CHANGELOG.md` / `.harness/decisions.jsonl` / `.github/workflows/ci.yml` はいずれも変更なし。design.md §5 の指示どおり、実装フェーズでは触っていない。

## 検収(司令塔 / 2026-08-27)

`test-runner`: lint / typecheck / format:check / test / `bash -n` / `check-guard-integrity.sh` / manifest の JSON 妥当性 — すべてパス、自動修正なし。

`code-reviewer`: 0 critical / 1 major / 4 minor。

### 採用した指摘

| 指摘 | 対応 |
| --- | --- |
| **[Major]** `Collect PR facts` が `set -uo pipefail` のみで、`gh api` が rate limit や一時障害で失敗しても緑のまま次へ進む(`changed.txt` / `tickets.txt` が空 → 「違反なし」)。**このチケットが塞ごうとしている「記録漏れが静かに見逃される」事象が API 障害経路で再現する** | `Collect PR facts` を `set -euo pipefail` に変更。判定ステップ側は `-e` を付けない(`exit 1` でステップが打ち切られ `rc` の捕捉と annotation / Summary に到達できなくなる)。両ステップに理由をコメントで明記した |
| **[Minor]** `design.md` の根拠が「owned / merge に対応する」と書かれており、実装(4 系統)より広く読める | `design.md` の決定事項表を「4 系統に限定する / 拡大は別チケット」に精緻化した。実装は変更なし(FR-1 どおり) |
| **[Minor]** `GH_TOKEN` の取り方が `template-update-check.yml`(`github.token`)と不統一 | `${{ github.token }}` に統一した |

### 採用しなかった指摘

| 指摘 | 不採用の理由 |
| --- | --- |
| **[Minor]** `Closes #12, #13` のカンマ区切りで 2 件目以降を拾えない | GitHub 自身がカンマ区切りを close 扱いしない(キーワードは Issue ごとに繰り返す必要がある)。実装は GitHub の挙動と一致しており、拾えない番号はそもそもクローズもされない。加えて本テンプレートの運用は 1 Issue = 1 PR |
| **[Minor / 参考]** PR ブランチのスクリプトをそのまま実行するため、同一 PR 内でスクリプトを無効化できる | `ci.yml` の `harness-integrity`(`check-guard-integrity.sh`)と同型の既存パターンで、本 PR が新たに悪化させたものではない。ここだけ別経路にすると既存層と非対称になる |

### 反映後の再確認

- `npm run format:check` — 変更後のワークフローで再実行して通した(下記コマンド参照)
- `.github/workflows/record-hygiene.yml` の差分は `set -euo pipefail` / `github.token` / コメント 2 箇所のみ。判定ロジック(`check-record-hygiene.sh`)は無変更のため、§6 の検証 1〜11 の結果はそのまま有効
