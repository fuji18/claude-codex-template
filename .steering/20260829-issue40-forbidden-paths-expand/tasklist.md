# タスクリスト: 委託禁止領域に CI/hook の判定実体を含める(Issue #40)

design.md の §番号に対応する。上から順に消化する。

## 実装

- [x] §1-1 `.claude/scripts/delegate-codex.sh` の `FORBIDDEN_PATHS` を 10 項目に置き換える
- [x] §1-2 配列直上のコメントを更新する(680 行の 1 行を 2 行に + ディレクトリ指定の理由の段落を挿入)
- [x] §2 `AGENTS.md` §4 のマーカー内を置き換える(マーカー行は動かさない)
- [x] §3 `CLAUDE.md`「Codex への委託禁止領域(パス)」節の箇条書きを置き換え、スコープ外の 1 行を追記する
- [x] 3 箇所の記述が一致していることを目視で突き合わせる

## 検証

- [x] §4-0 `bash -n` を通し、スタブ Codex と使い捨てステアリングを用意する
- [x] §4-1 S1(`check-record-hygiene.sh` 改ざん)が exit 2 / `status=failed` で止まることを実測する
- [x] §4-1 S2(`.claude/hooks/session-start.sh` 改ざん)を実測する
- [x] §4-1 S3(`.claude/settings.json` 改ざん)を実測する
- [x] §4-1 S4(禁止領域に触れない通常委託)が従来どおり成功することを実測する(回帰確認)
- [x] §4-2 スナップショットのコストを 1 回計測する(S4 の全体所要時間を計測。real 0m7.856s)
- [x] §4 実測結果を `verification.md` に表で記録する
- [x] §4-3 使い捨てステアリング・scratch・スタブを後始末し、`git status` が汚れていないことを確認する

## 記録

- [x] §5 `docs/template-dev/CHANGELOG.md` に `## 2026-08-29` 見出しを新設して追記する
- [x] §6 品質チェック(`bash -n` / lint / 型 / テスト)を通す(`bash -n` OK / `eslint .` OK / `tsc --noEmit` OK。変更が `.sh` / `.md` のみのため `vitest` 対象コードへの影響なし)
