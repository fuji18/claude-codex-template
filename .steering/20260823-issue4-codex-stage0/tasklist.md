# タスクリスト: 段階0 の残件

Issue: #4 / design: `design.md`(判断はすべてそこにある。迷ったら停止して報告する)

> **Codex に実際の委託をさせないこと。** 枠を消費する。回帰確認は入口検査1 で止まるところまで(design.md D7)。

## フェーズ1: 送信禁止パスの単一ソース化

- [x] `.claude/codex-denylist.txt` を design.md D2-1 の内容そのままで新規作成する
- [x] `.claude/scripts/delegate-codex.sh` の入口検査1 を D2-2 のコードに差し替える
  - [x] 冒頭コメントブロックを D2-2 の文面に書き換える
  - [x] denylist 不在 / 有効パターン 0 件で `EX_UNAVAIL`(3)を返す
  - [x] `-maxdepth 3` を撤廃し、`node_modules` / `.git` / `.harness` の prune を維持する
  - [x] `/` を含むパターンは `-path "./..."`、含まないパターンは `-name` に振り分ける
  - [x] `.example` / `.sample` / `.template` の除外と `head -20` を維持する
  - [x] 機密検出時の終了コードは `EX_FAIL`(2)のまま変えない
  - [x] 入口検査0・2・3 は触らない
- [x] `.claude/template-manifest.json` を D2-3 のとおり更新する
  - [x] `owned` から `".codex/prompts/"` を削除する
  - [x] `merge` の `".claude/branch-policy.json"` の直後に `".claude/codex-denylist.txt"` を追加する

## フェーズ2: 回帰確認(Codex を呼ばない)

- [x] design.md D7 の #1〜#7 を順に実行し、結果を記録する(#1〜#7 すべて期待どおり。#7 は既存の `.claude/settings.local.json` で確認、作成・削除は不要だった)
- [x] 一時ファイル(`.env` / `a/b/c/d/` / 退避したファイル)をすべて元に戻す
- [x] `git status` に意図した変更以外が無いことを確認する

## フェーズ3: 文書の更新

- [x] `docs/template-dev/codex-delegation-plan.md` を D6-1 の (a)〜(f) のとおり更新する
  - [x] (a) §10.2 にこのリポジトリの判断を追加
  - [x] (b) §11 の「認証キャッシュの永続化は未決」を決定文に置き換え
  - [x] (c) §11 に段階0 完了の項目を追加
  - [x] (d) §13 の表 #4 / #6 を差し替え
  - [x] (e) §13 直後の「現状」段落を差し替え
  - [x] (f) §7.3 に `.codex/prompts/` の言及があれば読み替え注記を足す(無ければ何もしない)
- [x] `docs/template-dev/codex-harness.html` を D6-2 の 1〜4 のとおり更新する(該当箇所が無い項目はでっち上げず報告に書く)
- [x] `README.md` に D3 の Codex 認証手順を追記する(追記のみ)

## フェーズ4: 品質チェックとコミット

- [x] `npm run lint`
- [x] `npm run format:check`(失敗したら `npm run format`)
- [x] `npm run test`
- [x] D9 のメッセージで 1 コミットにまとめる(**push と PR は司令塔が行う。ここでは作らない**)
