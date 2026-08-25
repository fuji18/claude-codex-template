<!-- status: ready -->

# 設計: 乖離の一覧と直し方

実装を正とし、ドキュメント側を寄せる。10 件。

## D1. 「強制層は 4 段」が強制層と情報提供層を混ぜている

- 実装: SessionStart hook は現在地とベースを**注入するだけ**で何も阻止しない。
  CI の `branch-policy` ジョブは PR の base とブランチ名しか見ず、直接コミットの有無は見ない。
  実際に阻止するのは PreToolUse hook / `.husky/pre-commit` / `.husky/prepare-commit-msg` の 3 実装。
- 根拠: `codex-delegation-plan.md` §11 の「Codex は SessionStart hook を強制層として挙げなかった。
  次に §8 を触るときに『強制 3 層 + 情報提供 1 層』へ書き直す」。
- 直す先: `.claude/rules/lead/branch-and-tickets.md` / `README.md`(4 段構えの 2・4 項)/
  `.claude/skills/development-guidelines/guides/process.md`(各プロジェクトの
  `docs/development-guidelines.md` の生成元なので放置すると全プロジェクトへ配られる)/
  解説 HTML §07 の見出し周辺。

## D2. `check-implementation-phase.sh` の通過パス一覧が不完全

- 実装: 通すのは `.steering/` `docs/` `.claude/` `.github/` `.husky/` と絶対パス。
- ドキュメント: `README.md` と解説 HTML が `.steering/` `docs/` `.claude/` の 3 つしか挙げていない。
- 直し: `.github/` `.husky/` を追記する。

## D3. AGENTS.md §1-3 の git hook 検査が実装より緩い

- 実装(`delegate-codex.sh` 入口検査 5-3 / `.codex/skills/degraded-mode-ticket/` 検査3):
  `.husky/` がある構成で `core.hooksPath` が**空、または実在しないディレクトリ**なら止める。
  値を `.husky` と決め打ち比較してはいけない(husky v9 が設定するのは `.husky/_`)。
- ドキュメント: AGENTS.md は「空を返した場合」しか書いていない。
- 直し: 条件を実装に合わせ、決め打ち比較の禁止も書く。

## D4. `docs/template-dev/README.md` が Codex 委託を「不採用」と説明している

- 実装: 段階0〜6 まで完了済み(`delegate-codex.sh` / `codex-run.sh` / `harness-mode.sh` /
  `.claude/rules/mode/` / `.codex/skills/` / `delegate:codex` ラベル)。
- ドキュメント: 「**不採用**(Codex は使わない方針が確定)。記録としてのみ保存」。真逆。
- 直し: 説明を実態に更新し、表に載っていない解説 HTML 3 本も追加する。

## D5. 解説 HTML(`codex-harness.html`)が段階2 時点で止まっている

- masthead: 改訂 2026-08-23 / 「段階 2 / 6 完了」/ ブランチ `feature/codex-stage-issues`。
- §01 の段落: 「段階 2 まで実装済み…残っているのは …段階4 のスコープ」。
- §10 の段階06: `未着手` チップ。実際は 2026-08-24 完了(PR #17)。
- 直し: masthead を現状(段階 6 / 6 完了・改訂 2026-08-25)に、§01 段落を実装済みの範囲に、
  段階06 を完了に。#15(自己編集ハザード)の実装済みも段階06 行に添える。

## D6. CHANGELOG が 2026-08-20 で止まっている

- `docs/template-dev/README.md` は「テンプレート側を変更したら必ずここに追記する」と定めており、
  `/sync-template` の取り込み側はこのファイルだけを読む。段階3〜6 と #15 の変更が丸ごと欠けている
  = 取り込む側は `impl` 委託・モード B/C・`delegate:codex`・自己コピー exec を知らないまま。
- 直し: `## 2026-08-23` / `## 2026-08-24` / `## 2026-08-25` を追加する(記法どおり新しいものを上に)。
  区分は `[auto]` / `[manual]` を付け、`[manual]` には「取り込む側の作業」を必ず 1 行入れる。
  併せて 2026-08-20 の項が触れている `.codex/prompts/`(実在しないと確定し登録撤回)の後始末も
  2026-08-24 の項で明示する。**過去の見出しは書き換えない**(記法の規定)。

## D7. `codex-run.sh` のヘッダに `pending` サブコマンドが無い

- 実装: `pending` は SessionStart hook が呼ぶ主要経路。`usage()` には載っているがヘッダに無い。
- 直し: ヘッダの使い方一覧に 1 行足す。

## D8. `delegate-codex.sh` の `--background` メッセージが未来形のまま

- 実装: 段階4 は完了済み(未検収委託の SessionStart 注入は動いている)が、`--background` は
  実装していない。計画書 §6 も「`--background` は未実装。前景で 1 本ずつ」と確定している。
- 直し: 「段階4で実装します」→ 未実装であることと前景運用の根拠(§6)に文言を変える。
  **処理は変えない**(引数を受けたら exit 2 のまま)。ヘッダの同趣旨のコメントも合わせる。

## D9. `session-start.sh` の冒頭コメントが 4 項目しか列挙していない

- 実装: 本体は 6 ブロック(依存 / 自壊検知 / 現在地 / lead ルール / ハーネスモード / Codex 未検収)。
- 直し: 冒頭コメントに 5) ハーネスモード注入 6) Codex 委託の未検収 を追記する。

## D10. 計画書 §3.1 のインターフェース表に実装状況が無い

- 実装: `fix-ci` は「本テンプレートでは未実装」と返し、`--background` も未実装。
- ドキュメント: §3.1 の表は 4 モードを対等に並べ、シグネチャに `[--background]` を含む。
  §6 の表(436 行)だけが「未実装」と書いており、同じ文書内で食い違う。
- 直し: §3.1 に実装状況の列/注記を足す。

## 直さないもの(判断の記録)

- `/status` に Codex 委託の未検収行が無い件: 機能追加であって乖離ではない。スコープ外。
- `.claude/skills/development-guidelines/guides/process.md` の Git Flow 記述(develop 前提):
  スキルは各プロジェクトの実態に合わせて生成する雛形であり、テンプレート既定の
  `branch-policy.json`(GitHub Flow)と食い違っていても誤りではない。D1 の 1 行だけ直す。
