# 要求内容

## 概要

委託禁止領域の単一ソース(`delegate-codex.sh --print-forbidden`)と `CLAUDE.md`「Codex への委託禁止領域(パス)」節の記述ずれを、CI(`harness-integrity` ジョブ)で**警告として**検出する。

## 背景

禁止領域の単一ソースは 2 系統に分かれている。

- **汎用項目** … `.claude/scripts/delegate-codex.sh` の `FORBIDDEN_PATHS` 配列
- **プロジェクト固有パス** … `AGENTS.md` §4 の `<!-- kickoff:delegation-forbidden-paths -->` マーカー内(委託の開始時に抽出してマージ)

この 2 系統は機械が読む正であり、設計として明快。一方 `CLAUDE.md` の同名の節は **司令塔が振り分けを判断するための説明**で、**手動同期**になっている。パスを足すときの 3 箇所目の直し漏れは #56 のように現に発生しうる。

`--print-forbidden` という**機械可読な出力口がすでにある**ため、CI で安価に検査できる(Issue #64 / レビュー A4・P2)。

## 実装対象の機能

### 1. 記述ずれの検査スクリプト

- `.claude/scripts/check-forbidden-paths-doc.sh` を新設する
- `delegate-codex.sh --print-forbidden` の出力(汎用 + プロジェクト固有)のうち**実在するパス**が、`CLAUDE.md` の該当節に文字列として現れるかを検査する
- ずれを 1 行ずつ標準出力へ返す。装飾(`::warning::`)は呼び出し側の責任(`check-record-hygiene.sh` / `check-guard-integrity.sh` と同じ分業)
- 手元でも同じ結果を再現できる(引数・環境変数なしで実行可能)

### 2. CI(`harness-integrity`)への配線

- 既存の "Validate harness integrity" ステップとは**独立したステップ**として追加する
- 検出時は `::warning::` を出すだけで、**ジョブを赤にしない**

## 受け入れ条件

### 記述ずれの検査スクリプト

- [ ] 現状のリポジトリ(`main` 相当)で警告が 0 件になる
- [ ] `FORBIDDEN_PATHS` に実在するパスを 1 つ足して `CLAUDE.md` を更新しないと、そのパスが 1 行で報告され `exit 1` になる
- [ ] 同じ状態で `CLAUDE.md` の該当節にもそのパスを書けば警告が消え `exit 0` になる
- [ ] `CLAUDE.md` に該当節が無い場合は、パス単位の検査をせず 1 行だけ報告する
- [ ] `delegate-codex.sh` が無い構成(Codex を使わないプロジェクト)では何も報告せず `exit 0`

### CI への配線

- [ ] 警告が出てもジョブが赤にならない(`harness-integrity` は成功のまま)
- [ ] 検出行が GitHub Actions の警告注釈(`::warning::`)として表示される

### 記録

- [ ] `docs/template-dev/CHANGELOG.md` に追記済み

## 成功指標

- 禁止領域にパスを足す PR で、`CLAUDE.md` の追記漏れがレビュー前に機械的に気づける
- 誤検知が 0 件(現状のリポジトリで警告が出ない)

## スコープ外

- `CLAUDE.md` の当該節の**自動生成**(プロジェクト所有ファイルであり、`/sync-template` の上書き対象外。生成物にするとプロジェクト側の追記と衝突する)
- **逆方向の検査**(`CLAUDE.md` に書かれているが単一ソースに無いパス)。判断の根拠は `design.md` 判断2
- `AGENTS.md` §4 マーカーとの**個別照合**(抽出経路が機械化済みで、`--print-forbidden` の出力に既に含まれる)
- `--print-forbidden` 自体の高速化(別チケット #65)

## 参照ドキュメント

- Issue #64
- `CLAUDE.md`「Codex への委託禁止領域(パス)」節
- `.claude/rules/lead/delegation-policy.md`
- `docs/template-dev/codex-delegation-plan.md` §9
