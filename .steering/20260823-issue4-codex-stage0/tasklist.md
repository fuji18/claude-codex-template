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

## フェーズ5: 検収の指摘対応(司令塔)

- [x] レビュー Minor 1・2: denylist ヘッダに書式の制約を明記(先頭 `/` 禁止・`#` 使用不可)
- [x] レビュー Minor 3: `requirements.md` の受け入れ条件をチェック済みに更新
- [x] §6 マニフェスト表の `.codex/prompts/` 行を「登録撤回」に更新(§13 #4 と整合)
- [x] §11「残るのはデータガバナンス判断と環境の恒久化」の現在形を解消
- [x] §13 #5 の代替欄「mounts の要否を #4 で判断する」を決定済みに更新

## 振り返り(申し送り)

**このチケットで確定したこと**

- `.codex/prompts/` は Codex CLI v0.149.0 に**存在しない**。カスタムプロンプトの仕組みは skills に置き換わっている。**段階5(#7)の成果物は `.codex/skills/` か `docs/playbook/codex-standalone.md` のどちらか**になる。`.codex/skills/` が project スコープで実際に効くかは #7 で実機確認する(バイナリに `/.codex/skills` の文字列はある)
- `resetAt` は `codex exec --json` から取れない。**段階3(#5)で `impl` の終了コード 4 を実装するとき、`resetAt` は原則 `null` である前提で設計すること。**上限時のエラー出力に出れば埋まる、というだけの扱いにする
- 認証キャッシュは永続化しない方針。**devcontainer をリビルドしたら `codex login` が要る**。段階3 以降で「委託したら exit 3 が返る」ときは、まずこれを疑う

**次のチケットへの申し送り**

- 段階2 の価値判定で、**Codex 側の切り分けの方がこのリポジトリの文書より精密だった**例が出た(強制層の数え方)。§8 の「強制層は 4 段」は「**強制 3 層 + 情報提供 1 層**」へ書き直す必要がある。`.claude/rules/lead/branch-and-tickets.md` にも同じ記述があるため、次に §8 を触るチケットで両方まとめて直す(このチケットのスコープ外なので手を付けていない)
- **発見2(`exit 0` がタスク成否を表さない)は未解消のまま。**段階3(#5)の終了コード契約はここを塞ぐのが主眼になる
- `delegate-codex.sh` の入口検査には**自動テストが無い**(今回も手動 7 ケース)。段階3 で `impl` を足すと検査の分岐がさらに増えるため、**#5 でテストの自動化を検討する価値がある**
