# 要求: 実装とドキュメント記載の乖離を解消する

## 背景

段階0〜6(Codex 併用ハーネス)と #15(自己編集ハザード)が短期間に連続でマージされた結果、
実装は進んだがそれを説明するドキュメント側に取り残しが出ている。ユーザーからの依頼は
「実装に各ドキュメントの記載を照らし合わせ、乖離があれば修正する」。

## スコープ

読み合わせの対象(ドキュメント側):

- `README.md` / `CLAUDE.md` / `AGENTS.md`
- `.claude/rules/**`(共通ルール・司令塔ルール・モードルール)
- `.claude/commands/**` / `.claude/skills/**` / `.claude/agents/**`
- `docs/template-dev/`(計画書 `codex-delegation-plan.md`・`CHANGELOG.md`・`README.md`・解説 HTML)
- スクリプト冒頭の仕様コメント(コード内ドキュメント)

突き合わせる実装:

- `.claude/scripts/*.sh` / `.claude/hooks/session-start.sh` / `.husky/*`
- `.github/workflows/*` / `.claude/settings.json` / `.claude/template-manifest.json`
- `.codex/config.toml` / `.codex/skills/`

## 受け入れ条件

- 見つかった乖離をすべて「実装が正」に寄せて記述を直す(実装側の挙動は変えない)
- 例外: 実装コメントが未来形のまま古くなっているもの(`--background は段階4で実装します` 等)は
  コメント文言のみ実態に合わせる。処理は変更しない
- 品質チェック(`/check` 相当)が通る

## スコープ外

- 機能追加(`/status` への Codex 委託行の追加など)
- `.harness/mode` の書き換え(切替の宣言は人間の担当)
