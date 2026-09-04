# 要件: 出口検査の固定費を下げる(Issue #65)

## 背景

委託 1 本あたりの固定費に、伸びる要素が 2 つある。いずれも現時点で実害は無いが、
禁止領域の追加(#56)で対象パスが増えたため、安いうちに直す。

1. `forbidden_snapshot()` がファイルごとに `git hash-object` をプロセス起動する
   (`delegate-codex.sh`)。impl 委託の前後 2 回走り、`.harness/codex-runs/` の
   件数に線形に伸びる
2. `--print-forbidden`(`check-guard-integrity.sh degraded` が呼ぶ read-only の
   一覧出力)も、自己コピー + `mktemp -d` + `exec` を通る

## スコープ(やること)

1. `forbidden_snapshot()` を `git hash-object --stdin-paths` の 1 プロセスに置き換える。
   **不在ファイル・ディレクトリ・読めないファイルの扱いを一切変えない**
2. `--print-forbidden` を自己コピー `exec` の前で短絡させる
3. 変更前後で同じ入力に対し同じスナップショットが出ることを実測で確認する

## スコープ外

- `delegate-codex.sh` の分割(レビュー A3)
- `.harness/codex-runs/` の prune 閾値の変更
- シェルスクリプト用のテストスイート新設(このリポジトリには存在しない。
  検証は使い捨てドライバで行い、結果を `verification.md` に残す)

## 受け入れ条件

- [x] 同一ツリーで変更前後のスナップショット出力が完全一致する
- [x] 不在パス・ディレクトリ・読めないファイルを含む構成で挙動が変わらない
- [x] 上記の構成でも改ざん(内容の 1 バイト変更)が差分として検出される
- [x] `--print-forbidden` が短絡後も `check-guard-integrity.sh degraded` から正しく使える
- [x] 短絡が explore / review / impl に波及していない(自己コピーは従来どおり働く)
- [x] `docs/template-dev/CHANGELOG.md` に追記済み

## 非機能

- 入口検査0 が保証していない外部コマンド(`paste` / `awk` / `wc` 等)を新たに使わない。
  使えるのは `find grep sed head tail tr sort uniq` と bash 組み込み、および git

## 根拠

- Issue #65 / Codex 併用ハーネス実装レビュー(2026-08-31)C3、優先度表 P2
- 該当: `.claude/scripts/delegate-codex.sh` の `forbidden_snapshot()` と冒頭の自己コピーブロック
