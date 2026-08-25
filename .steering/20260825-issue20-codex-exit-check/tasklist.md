# タスクリスト: Codex 委託の出口検査(Issue #20)

design.md の該当節に**すべて具体的なコードと挿入位置が書いてある**。設計判断は不要。

## 1. delegate-codex.sh

- [x] 1-A: 入口検査0 の依存コマンド列に `sort` `uniq` を追加する(design.md §1-A)
- [x] 1-B: `FORBIDDEN_PATHS` 配列と `forbidden_files` / `forbidden_snapshot` を追加する(design.md §1-B)
- [x] 1-C: 事前スナップショットに `FORBIDDEN_BEFORE="$(forbidden_snapshot)"` を追加する(design.md §1-C)
- [x] 1-D: impl 出口判定ブロックの先頭に出口検査本体を追加する(design.md §1-D)
- [x] 1-E: `bash -n .claude/scripts/delegate-codex.sh` が通ることを確認する

## 2. 散文の同期

- [x] 2-A: `CLAUDE.md`「Codex への委託禁止領域(パス)」に 3 項目と単一ソースの段落を追記する(design.md §2)
- [x] 2-B: `AGENTS.md` §4 のマーカー内に 3 項目を追記する(マーカー行は消さない。design.md §3-A)
- [x] 2-C: `AGENTS.md` §4 の導入文に機械検査の一文を追加する(design.md §3-B)
- [x] 2-D: `AGENTS.md` マーカー下の注記に「機械検査は汎用項目だけ」の一文を追加する(design.md §3-C)
- [x] 2-E: 3 箇所(スクリプトの配列 / CLAUDE.md / AGENTS.md)のパスが一致していることを目視で突き合わせる

## 3. 再現テスト

- [x] 3-A: design.md §5-0 のスタブと probe 用ステアリングを用意する
- [x] 3-B: シナリオ1 を 3 パス(`AGENTS.md` / `.husky/pre-commit` / `.github/workflows/ci.yml`)で実行する
- [x] 3-C: シナリオ2(誤検出なし)を実行する
- [x] 3-D: シナリオ3(委託前から dirty)を実行する
- [x] 3-E: 後片付けを行い、`git status --short` に意図した 3 ファイル以外の変更が無いことを確認する
- [x] 3-F: `.steering/20260825-issue20-codex-exit-check/verification.md` に手順と実行結果を記録する

## 4. 仕上げ

- [x] 4-A: `npx prettier --write CLAUDE.md AGENTS.md .steering/20260825-issue20-codex-exit-check/*.md` を実行する(全体フォーマットは禁止)
- [x] 4-B: `git status --short` で変更ファイルが想定どおりか確認する

## 5. 検収指摘の対応

- [x] 5-A(P0): 出口検査ブロックを `if [ "$MODE" = "impl" ]`(出口判定側)の先頭から、`SUMMARY` 代入直後・`CODEX_EXIT` 分岐の直前へ移動する
- [x] 5-B(P2): `forbidden_files()` の末尾パイプに `|| true` を付け、理由をコメントする
- [x] 5-C(P2): `forbidden_snapshot()` 直前の「空振り条件」に割り込み・run record 未ローテーションの 2 項目を追記する
- [x] 5-D: `AGENTS.md` の「上記パス」を「以下のパス」に修正する
- [x] 5-E: `design.md` §0.3 を移動後の配置に合わせて差し替える
- [x] 5-F: `bash -n .claude/scripts/delegate-codex.sh` が通ることを確認する
- [x] 5-G: シナリオ4(禁止領域改ざん + 非ゼロ終了)を追加実行し、`status=failed` / `exit=2` / `error` に該当パスと `codex exit` が出ることを確認する
- [x] 5-H: シナリオ2・3を再実行し、`completed` / `exit=0` のままであることを確認する(誤検出なし)
- [x] 5-I: `npx prettier --write CLAUDE.md AGENTS.md .steering/20260825-issue20-codex-exit-check/*.md` を再実行する
- [x] 5-J: `verification.md` に §8 を追記し、テスト用の run record・probe ステアリングを削除する
