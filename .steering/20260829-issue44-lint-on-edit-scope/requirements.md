# 要求: lint-on-edit.sh を編集ファイル単位に絞る

出典: GitHub Issue #44(P2 / `delegate:codex` は付けない = `.claude/scripts/` は委託禁止領域)

## 背景

`.claude/scripts/lint-on-edit.sh` は PostToolUse(async)hook で、TS/JS ファイルを編集するたびに
**プロジェクト全体の eslint と全体 tsc** を回し、それぞれ `tail -20` を出力している。

問題は 2 つ。

1. **コンテキストと CPU がファイル数に比例して太る。** 出力される `tail -20` には編集と無関係な
   既存エラーが混ざり、それが毎編集ごとに司令塔/実装者のコンテキストへ載り、以降のターンで
   再送され続ける(`.claude/rules/lead/context-management.md`「キャッシュを効かせるより
   キャッシュ対象を小さく保つ」)
2. **ロックにスキップ穴がある。** `mkdir` ロックが取れなければ即 `exit 0` するため、
   先行プロセスの実行中に入った編集は**検査されずに捨てられる**。先行プロセスは古い状態を
   見ているので、「先行が結果を返すから良い」は成立しない。連続編集の最後の 1 本が
   常に無検査になる。

## 受け入れ条件(Issue のもの)

- [ ] TS ファイルを編集したとき、その 1 ファイルの lint エラーが検出される
- [ ] 無関係な既存エラーがコンテキストに載らない(絞り込みが効いている)
- [ ] 連続編集時の挙動を実測し、スキップ穴の扱い(塞いだ / 許容した)が `design.md` に記録されている
- [ ] tsc の扱いの判断根拠が記録されている
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み

## スコープ外(Issue のもの)

- prettier / lint-staged / CI `format:check` の 3 重化の解消
- `/check`(`test-runner`)との統合。三層の役割分担は `review-policy.md` の設計どおり
