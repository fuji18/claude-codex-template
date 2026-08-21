# 要求内容

## 概要

保護ブランチへの直接コミットを防ぐ検査を、Claude Code 専用の PreToolUse hook から **git hook(`.husky/pre-commit`)へ移植**し、ベンダー非依存の防衛線にする。

## 背景

`docs/template-dev/codex-delegation-plan.md`(2026-08-18 改訂)の**段階1**。Codex 併用構成では、実装フェーズを Codex に移管し、縮退モード(Claude 上限到達時)では Codex にコミット権まで与える方針を決めた。

しかし現状、保護ブランチへの直接コミットを止める層は以下しかない:

| 層 | Claude | Codex / 人手 / 他ツール |
| --- | --- | --- |
| `check-branch-policy.sh`(PreToolUse hook) | ✅ 効く | ❌ **効かない** |
| `.husky/pre-commit` | `lint-staged` のみ | `lint-staged` のみ |
| CI の `branch-policy` ジョブ | ✅ | ✅ ただし **PR の base とブランチ名しか見ない**。「main に直接コミットされたか」は検査対象外 |

つまり **Codex にコミットを許した瞬間、`main` への直接コミットをローカルで止めるものが存在しなくなる**。これは Codex 導入の前提条件であり、Codex 契約前に独立して価値がある(手動コミット・将来の任意ツールも同じ穴を持つため)。

## 実装対象の機能

### 1. 保護ブランチ検査スクリプト(新規・共有)

- `.claude/scripts/check-protected-branch.sh` を新設する
- `.claude/branch-policy.json` の `protectedBranches` を読み、現在のブランチが該当したら非ゼロで終了する
- **呼び出し元を問わず同じ判定になる**こと(`latest-steering.sh` を hook・fork・スキルで共有しているのと同じ思想)

### 2. `.husky/pre-commit` からの呼び出し

- `lint-staged` の**前**に検査を実行し、違反なら commit を中断する
- ベンダー非依存(Claude / Codex / 人間の手動コミットすべてに効く)

### 3. `check-branch-policy.sh` の重複排除

- 現在インラインで持っている `protectedBranches` 判定を、新スクリプトの呼び出しに置き換える
- 二層が別々のロジックを持つと判定がずれるため、**ルールの実体を 1 箇所にする**

## 受け入れ条件

### 保護ブランチ検査スクリプト

- [ ] 保護ブランチ(`main`)上で実行すると非ゼロ終了し、stderr に理由と対処法が出る
- [ ] 作業ブランチ(`feature/*`)上で実行すると 0 終了し、何も出力しない
- [ ] `.claude/branch-policy.json` が存在しない場合は 0 終了(フェイルオープン。CI の `branch-policy` ジョブと同じ挙動)
- [ ] `jq` が無い場合は 0 終了(フェイルオープン)
- [ ] detached HEAD(rebase / bisect 中)では 0 終了(`git branch --show-current` が空を返すため)
- [ ] リポジトリ外・git 管理外のディレクトリで実行しても異常終了しない
- [ ] 実行権限(`+x`)が付いている(SessionStart hook が権限落ちを検知する対象になる)

### `.husky/pre-commit`

- [ ] 保護ブランチ上では `lint-staged` に到達せず中断する
- [ ] 作業ブランチ上では従来どおり `lint-staged` が走る
- [ ] スクリプトが存在しない場合でも `lint-staged` は動く(テンプレート同期の途中状態で commit 不能にしない)

### `check-branch-policy.sh`

- [ ] 保護ブランチ上での直接コミットを従来どおり exit 2 でブロックする(挙動の後退がない)
- [ ] PR 作成コマンドの base 検査は変更しない

## 成功指標

- 保護ブランチへの直接コミットを止める層が **Claude 依存の 1 層から、ベンダー非依存を含む 2 層**になる
- 保護ブランチ判定のロジックが **1 ファイルに集約**される

## スコープ外

以下はこのフェーズでは実装しない:

- `delegate-codex.sh` の実装(段階2 以降)
- AGENTS.md / `.codex/config.toml` の生成(段階2)
- `.harness/mode` とモード切替(段階4)
- 危険コマンド検査(`block-dangerous-cmds.sh`)のベンダー中立化 — サンドボックス側で張る方針のため(計画 §8)
- `--no-verify` によるバイパスの封鎖 — git の仕様上ローカルでは塞げない。最終的な砦は CI とリモートのブランチ保護

## 参照ドキュメント

- `docs/template-dev/codex-delegation-plan.md` §8(ガードレールのベンダー中立化)/ §11(段階導入)
- `.claude/branch-policy.json` — ブランチ戦略の機械可読な単一ソース
- `.claude/rules/lead/branch-and-tickets.md` — 強制層は 3 段という既存の設計意図
