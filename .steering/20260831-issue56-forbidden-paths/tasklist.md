# タスクリスト: 委託禁止領域の適用漏れを塞ぐ(Issue #56)

design.md の §番号に対応する。上から順に消化する。

## 実装

- [x] §1-1 `.claude/scripts/delegate-codex.sh` の `FORBIDDEN_PATHS` を 15 項目に置き換える
- [x] §1-2(a) 「サンドボックスの外で実行される」箇条書きの直後に 10 行を挿入する
- [x] §1-2(b) 末尾の原則の段落(3 行)を 9 行に置き換える
- [x] §2 `AGENTS.md` §4 のマーカー内に 5 行を挿入する(マーカー行は動かさない / 説明文に他の実在パスをバッククォートで書かない)
- [x] §3-1 `CLAUDE.md` の箇条書きに 5 行を挿入する
- [x] §3-2 `CLAUDE.md` の原則 1 行を 3 系統の記述に置き換える(除外リストから `rules/` を外す)
- [x] 3 箇所(配列 / `AGENTS.md` マーカー / `CLAUDE.md`)の列挙が一致していることを突き合わせる

## 検証

- [x] §4-0 `bash -n` と `--print-forbidden`(15 項目)を通し、残置 record を確認し、スタブ Codex と使い捨てステアリングを用意する
- [x] §4-1 S1(`.claude/branch-policy.json` 改ざん)が exit 2 / `status=failed` で止まることを実測する
- [x] §4-1 S2(`.claude/rules/lead/model-strategy.md` 改ざん)を実測する
- [x] §4-1 S3(`.claude/rules/spec-driven.md` 改ざん)を実測する
- [x] §4-1 S4(`CLAUDE.md` 改ざん)を実測する
- [x] §4-1 S5(`.mcp.json` 改ざん)を実測する
- [x] §4-1 S6(`.codex/config.toml` 改ざん)を実測する
- [x] §4-1 S7(禁止領域に触れない通常委託)が exit 0 で通ることを実測する(誤爆しないことの確認)
- [x] §4-2 S8(`.mcp.json` を退避した状態の通常委託)が exit 0 で通ることを実測する(不在パス回帰)
- [x] §4-3 S7 の全体所要時間を 1 回計測する
- [x] §4 実測結果を `verification.md` に表で記録する
- [x] §4-4 後始末(使い捨てステアリング・scratch・スタブ・バックアップの削除、退避ファイルの復元確認、`git status` / `git diff --stat` の確認)

## 記録

- [x] §5 `docs/template-dev/CHANGELOG.md` に `## 2026-08-31` 見出しを新設して追記する
- [x] §6 品質チェック(`bash -n` / eslint / tsc / prettier --check)を通す

---

## 申し送り(振り返り)

- **完了**: 21/21。往復 1 回・レビュー 1 巡(Critical 0 / Major 0 / Minor 3)。品質チェックは全項目パス
- **次のチケットへの申し送り**: 検証の型(スタブ Codex + 使い捨てステアリング)を再利用するとき、`env -i` 許可リストの補正(`CODEX_DELEGATE_ENV_ALLOW`)は #40 の `verification.md` にしか残っておらず、design.md §4 のテンプレートには入っていない。次に同じ型を使うチケットでは design.md 側に先に書く(レビュー Minor 1)
- **意図的に見送ったもの**(いずれも別 Issue が立っている):
  - `check-guard-integrity.sh` のポリシー整合検査の強化 → #59
  - `CLAUDE.md` と `--print-forbidden` の記述ずれの CI 機械検査 → #64
  - `forbidden_snapshot()` の `git hash-object` バッチ化(禁止領域が 10→15 項目に増えた分の固定費)→ #65
- **`.codex/` の前提**: 「Codex 自身は `.codex/` に書けない」は codex-cli v0.149.0 の実測依存。CLI 更新で正常委託が誤爆する可能性は受容済み(`CODEX_HOME` のプロジェクト内オーバーライドが無いことはレビューで確認)
