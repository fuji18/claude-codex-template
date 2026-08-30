# 要求: rec_field() の二重実装を共有ファイルに集約する

Issue: #45(P2 / `delegate:codex` は付けない = 委託禁止領域 `.claude/scripts/` を触るため)

## 背景

`rec_field()`(run record から 1 フィールドを読む。jq があれば jq、無ければ sed フォールバック)が
2 箇所にコピーされている:

- `.claude/scripts/delegate-codex.sh:646`
- `.claude/scripts/codex-run.sh:52`

コードには「2 箇所・十数行のため共有ファイルは作らない」と注記があるが、**乖離コストは既に顕在化済み**。
sed フォールバックの末尾カンマバグ(jq 不在環境で入口検査5-5 の再入防止がフェイルオープンする Critical)を
両方で直した実績がある。同じバグを 2 回直した時点で注記の前提は崩れている。
判定ロジックを 1 箇所へ集約する既存方針(`check-protected-branch.sh` / `harness-mode.sh` /
`latest-steering.sh`)とも不整合。

## スコープ

1. `.claude/scripts/lib-record.sh` に `rec_field()` を切り出し、両スクリプトから `source` する
2. **自己コピー exec(#15)との整合**を設計で決める。`delegate-codex.sh` は起動直後に自身を
   一時ディレクトリへコピーして exec するため、共有ファイルを素朴に `source` すると
   「実行中に委託先が書き換えられるファイル」が新たに増える
3. `check-guard-integrity.sh` の自壊検知対象に共有ファイルを足すかを判断する

## スコープ外

- `delegate-codex.sh` の分割(1,043 行の単一ファイルであることは「唯一の入口」原則と
  自己コピー保護を成り立たせる設計判断。維持する)
- 他の重複箇所の洗い出し(今回は `rec_field()` に限る)
- run record のスキーマ・書式の変更
- **jq 経路と sed 経路の既存の出力差**(design.md §6)。既存の性質であり、直すなら別チケット

## 受け入れ条件

- [ ] `rec_field()` の実装が 1 箇所になっている
- [ ] jq あり / なし両方で `delegate-codex.sh` と `codex-run.sh` が従来どおり動く(実測)
- [ ] 自己コピー exec 経路で共有ファイルが正しく解決される(実測)
- [ ] 実行中に共有ファイルを書き換えられるハザードへの対処が `design.md` に記録されている
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み
