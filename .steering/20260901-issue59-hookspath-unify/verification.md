# 実測: hooksPath 判定を一本化し、ポリシー空洞化検査を強化する(Issue #59)

design.md §5 の実測記録。各シナリオは後始末込みで実行済み(`git status --short` clean を最終確認)。

## §5-0: 事前

```
bash -n .claude/scripts/check-guard-integrity.sh  → OK
bash -n .claude/scripts/delegate-codex.sh          → OK
ORIG_HOOKS_PATH = .husky/_
```

## §5-1: 平常時に誤爆しないこと(受け入れ条件 4)

| # | コマンド | 結果 |
| --- | --- | --- |
| V1 | `check-guard-integrity.sh` | 出力 0 行 / `rc=0` |
| V2 | `check-guard-integrity.sh hooks-path` | 出力 0 行 / `rc=0` |
| V3 | `check-guard-integrity.sh degraded` | 出力 0 行 / `rc=0` |
| V4 | `check-guard-integrity.sh bogus` | `使い方: check-guard-integrity.sh [degraded\|hooks-path]` / `rc=2` |

> **バグ修正(実装メモ)**: 当初 design.md §1-4 のとおり jq を
> `select($b | startswith(.))` で実装したところ、V1 で
> `allowedPrefixes` の既定 6 件すべて(`feature/` 等)が誤検知された。
> 原因は jq の引数評価規則: `$b | startswith(.)` の `.` は呼び出し元の
> パイプ入力(`$b` 自身)を指し、`$ap[]` の値を指さない。
> `. as $prefix | select($b | startswith($prefix))` に修正して解消
> (CI 側 `.github/workflows/ci.yml` の `branch-policy` ジョブが使う
> `. as $p | select($h | startswith($p))` と同じ束縛パターンに揃えた)。
> 設計判断(閾値やロジックの変更)ではなく、design.md 自身が要求する
> 受け入れ条件(V1 で 0 行)を満たすための jq 構文修正。

## §5-2: hooksPath の判定が 5-3 と D1 で一致すること(受け入れ条件 1)

`git config core.hooksPath /tmp` を設定して実施。

| # | コマンド | 結果 |
| --- | --- | --- |
| V5 | `check-guard-integrity.sh hooks-path` | `core.hooksPath が .husky 配下以外(/tmp)を指している。ベンダー非依存の git hook 層が迂回されている` / `rc=1` |
| V6 | `check-guard-integrity.sh degraded` | V5 と同一の行を含む(D1 と文言一致を確認) |
| V7 | `delegate-codex.sh impl .steering/20260901-issue59-hookspath-unify/`(要 `CODEX_DELEGATE_ACK_SECRETS=1`。ワークツリーの `.claude/settings.local.json` が機密候補として検出されたため。中身は devcontainer 由来の権限設定のみで実害なし) | `git hook が無効です` + V5 と同じ 1 行 / `rc=3` |
| V8 | `[ -d /tmp ] && echo ...` | 出力あり(旧 5-3 の緩い条件では素通ししていたことの対比根拠) |
| V9 | `core.hooksPath` 未設定 → `hooks-path` | `core.hooksPath が未設定。...` / `rc=1` |
| V10 | `core.hooksPath=.husky/does-not-exist` → `hooks-path` | `core.hooksPath が実在しないディレクトリ(.husky/does-not-exist)を指している。...` / `rc=1` |

各回後 `git config core.hooksPath .husky/_` で復元済み。

## §5-3: ポリシー空洞化検査(受け入れ条件 2・3)

| # | 改変 | 結果 |
| --- | --- | --- |
| V11 | `protectedBranches = ["develop"]` | `baseBranch(main)が protectedBranches に含まれていない` の 1 行 / `rc=1` |
| V12 | `allowedPrefixes += ["main"]` | `保護ブランチ 'main' へ前方一致する接頭辞 'main' がある` の 1 行 / `rc=1` |
| V13 | `allowedPrefixes += [""]` | `保護ブランチ 'main' へ前方一致する接頭辞 '' がある` の 1 行 / `rc=1` |
| V14 | `protectedBranches = []` | `protectedBranches が空` の 1 行だけ(判断6 の確認どおり 2 行にならず) |
| V15 | V11 の状態で `hooks-path` | 出力 0 行 / `rc=0`(判断2 の確認どおり) |

各回後 `git checkout -- .claude/branch-policy.json` で復元済み。

## §5-4: 後始末の確認

```
git config --get core.hooksPath  → .husky/_
git status --short               → branch-policy.json は変更として出ない
check-guard-integrity.sh; rc=$?  → 出力 0 行 / rc=0
```

すべて期待どおり。
