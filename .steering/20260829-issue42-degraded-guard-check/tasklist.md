# タスクリスト: モード C 復帰時のガードレール健全性検査(Issue #42)

設計は `design.md` に書き切ってある。**設計判断が必要になったら停止して報告する**(推測で進めない)。

## 1. `delegate-codex.sh` に `--print-forbidden` を足す(design.md §2)

- [x] 1-1. `FORBIDDEN_PATHS` の定義ブロック(A)と `PROJECT_FORBIDDEN_PATHS` の抽出ブロック(B)、`AGENTS="AGENTS.md"` を入口検査0 の直後へ移動する(§2-1)
- [x] 1-2. A の見出しコメントを差し替え、A/B の跡地にポインタコメントを置く(§2-1)
- [x] 1-3. `usage()` / モード検証 `case` / TARGET 必須チェックを更新する(§2-2 a〜c)
- [x] 1-4. `--print-forbidden` の出力ブロックを追加する(§2-2 d)
- [x] 1-5. `bash -n .claude/scripts/delegate-codex.sh` が通り、`--print-forbidden` が汎用項目 10 行を出力して exit 0 になることを確認する

## 2. `check-guard-integrity.sh` に `degraded` サブコマンドを足す(design.md §3)

- [x] 2-1. 冒頭コメント(呼び出し元・終了コード表)を更新する(§3-1)
- [x] 2-2. 引数解釈 `SUBCOMMAND` を追加する(§3-2)
- [x] 2-3. セクション 2 の早期 exit を条件分岐に変え、セクション 3・4 を `if [ "$USES_HUSKY" = yes ]` で囲む(§3-3)
- [x] 2-4. 縮退検査 D1(`core.hooksPath`)/ D2(`.git/hooks/`)/ D3(`Codex-authored` コミットの禁止領域差分)を追加する(§3-4)。**D2 は design.md の `git rev-parse --git-path hooks` ではなく `git rev-parse --git-dir` + `/hooks` を使うよう変更した**(前者は core.hooksPath を尊重してその値を返すため、`.husky/_` を指す健全な状態でも正規フックを「直書き」と誤検知した。実測で確認)
- [x] 2-5. `bash -n` が通り、**引数なしの呼び出しが従来どおり無出力 / exit 0** であることを確認する

## 3. 手順書への組み込み(design.md §4・§5)

- [x] 3-1. `.claude/rules/mode/degraded.md` の復帰手順に検査コマンドを 1 として追加し、既存項目を繰り下げる
- [x] 3-2. `.codex/skills/degraded-mode-ticket/SKILL.md` §5 に `.git/` 配下の改変を追加し、検査3 に注意書きを 1 行足す

## 4. 実測(design.md §6)

- [x] 4-1. 使い捨て git リポジトリでシナリオ 1〜5 を実行する
- [x] 4-2. このリポジトリで引数なし / `--print-forbidden` / 未知サブコマンドの 3 確認を行う
- [x] 4-3. 結果を `verification.md` に記録する(コマンドと出力をそのまま貼る)

## 5. 仕上げ

- [x] 5-1. `docs/template-dev/CHANGELOG.md` の既存 `## 2026-08-29` 見出しに追記する(design.md §7)
- [x] 5-2. 品質チェック(`/check` 相当)を通す

## 振り返り(司令塔)

- **fork 往復 0 回**(#22・#27・#28・#24・#29・#37・#40・#41 に続き 9 回連続)。design.md に
  移動対象の行番号・差し替え文面・新規ブロックの全文・検証 5 シナリオまで書き切った
- **design.md の指定に 1 箇所の誤りがあり、実装者が実測で見つけて直した**(D2)。
  `git rev-parse --git-path hooks` は `core.hooksPath` を尊重してその値を返すため、
  `.husky/_` を指す健全な状態で正規フックを「直書き」と誤検知する。`--git-dir` から
  `/hooks` を組み立てる形に変更済み。**受け入れ条件に「正常系で誤検知しない」を
  置いていたことが効いた** — 異常系だけを検証していたら通っていた
- **検収指摘 2 件はいずれも Minor。** 1 件(decisions.jsonl 未記載)は本記録で解消。
  1 件(`is_forbidden()` に実在検査が無い)は**不採用**: D3 が突き合わせるのは作業ツリーの
  実ファイルではなく**コミットの差分パス**で、`[ -e ]` を足すと禁止領域のファイルを
  削除・リネームしたコミットを検出できなくなる(フェイルオープン)
- **申し送り**: `.claude/scripts/` を触るチケットが #40・#41・#42 と 3 連続。
  委託禁止領域が広がるほど fork 経路の比重が上がるので、`delegation-policy.md` の
  閾値見直しのタイミングで実測(`.harness/decisions.jsonl`)を見返すこと
