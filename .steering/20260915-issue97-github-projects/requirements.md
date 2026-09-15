# 要求内容: GitHub Projects による開発管理の導入(スラッシュコマンド 3 本)

## 概要

GitHub Projects(Projects v2)を「チケット進捗の可視化層」としてテンプレートに組み込む。導入(`/enable-github-projects`)・診断(`/github-projects-status`)・次の一手の提示(`/github-projects-next`)の 3 コマンドを追加し、既存の Issues + ラベル運用を**置き換えず**に投影する。

## 背景

- 現行テンプレートのチケット運用は **GitHub Issues + ラベル(`ticket` / `P0`-`P2` / `in-progress` / `delegate:codex`)+ open/closed** で完結しており、`/next-ticket`・`/status`・SessionStart hook がすべてこの事実を読む(`.claude/rules/lead/branch-and-tickets.md`)。
- 一方で「フェーズをまたいだ全体像」「着手待ちの列」「レビュー待ちの滞留」は Issue 一覧では見えない。数日空けて戻ったときの現在地把握が `/status` の 1 行報告に依存している。
- Projects を足すと**状態の正が 2 つに増える**危険がある。ラベルとボードが食い違ったまま `/next-ticket` が走ると、選定の根拠が壊れる。したがって「どちらが正か」を設計で固定することが導入の前提条件になる。
- Codex 委託(sandbox)は**ネットワーク無効かつ Issue 操作禁止**(`AGENTS.md` §3)。Projects 同期をどの実行主体が担うかを、既存のモード A/B/C と矛盾しない形で決める必要がある。

## 実装対象の機能

### 1. `/enable-github-projects`(導入)

- 新規 Project の作成、または既存 Project への接続を選べる。
- 接続情報・フィールド ID・Status 選択肢の対応を `.claude/projects-policy.json` に保存する(**秘密情報は保存しない**)。
- 既存の open な `ticket` Issue を Project に一括追加し、初期 Status を投影する。
- GitHub 側の組み込みワークフロー(Auto-add / closed→Done / PR merged→Done)の有効化手順を提示し、**人間が UI で実施したことを自己申告として記録**する(API から設定できないため)。
- 再実行時は既存設定を読み、**重複作成・重複追加をしない**(差分だけを適用する)。

### 2. `/github-projects-status`(診断・読み取り専用)

- 接続設定・認証スコープ・Project の実在・フィールド対応・同期差分(drift)・組み込みワークフローの申告状態を確認する。
- **確認できない項目は「未確認」と表示し、正常と断定しない**(特に組み込みワークフローは API から読めないため常に自己申告扱い)。
- 問題があれば復旧手順(コマンド 1 行または人間の手作業)を提示する。
- 何も書き込まない。

### 3. `/github-projects-next`(次の一手の提示・読み取り専用)

- 次に着手すべき Issue 候補を最大 3 件、選定理由つきで提示する。
- 判定材料: 優先度ラベル / `depends:` の解決状況 / `in-progress` の有無 / 対応するオープン PR の有無 / `.steering/` の `design.md` 完成マーカー / Project ボード上の並び順。
- **着手はしない。** 実装開始は `/next-ticket [番号]` の明示実行に委ねる(自動着手は初版では実装しない)。

## 受け入れ条件

### 共通

- [ ] `.claude/projects-policy.json` が存在しない、または `enabled: false` のとき、3 コマンドと既存コマンドへの差し込みは**すべて no-op**で、既存フロー(`/next-ticket` 等)の挙動が導入前と一致する
- [ ] 追跡対象ファイル・コマンド出力・会話のいずれにもトークン等の秘密情報が現れない(保存するのは owner 名・Project 番号・GraphQL node ID のみ)
- [ ] Codex(sandbox)は Projects を一切操作しない。`AGENTS.md` にその旨が明記されている
- [ ] 新規スクリプトは `.claude/scripts/` に 1 本だけ置き、3 コマンドと既存コマンドはすべてそれを経由する(同じ `gh` 手順を散文で二重に書かない)

### `/enable-github-projects`

- [ ] 認証スコープ不足を検出したとき、書き込みを一切行わずに停止し、人間が行う復旧手順(スコープ付与 / トークン種別の制約)を提示する
- [ ] 2 回連続で実行しても Project・フィールド・アイテムが重複しない
- [ ] 途中で失敗したとき `enabled: true` にならない(部分導入を「有効」と誤認しない)
- [ ] 書き込みを伴うステップ(Project 作成・既存 Issue の一括追加)の前に人間の承認を取る

### `/github-projects-status`

- [ ] 未導入 / 認証切れ / Project 削除済み / フィールド構成変更 / drift あり の各状態で、対応する診断行と復旧手順が出る
- [ ] 組み込みワークフローの状態は常に「未確認(自己申告: 日付)」として表示される
- [ ] 読み取り専用である(`gh` の書き込み系サブコマンドを呼ばない)

### `/github-projects-next`

- [ ] `in-progress` の Issue が既にあるときは新規候補を推さず、その作業の再開・PR 確認を提示する
- [ ] 候補ごとに「なぜ今それか」を、優先度・依存・design の完成状態・ボード順のどれに基づくか明示して 1〜2 行で示す
- [ ] `/next-ticket` を自動起動しない。着手条件(人間の承認・`in-progress` の空き・依存解決・`design.md` の `ready`)を提示して終わる

## 成功指標

- 導入済みプロジェクトで、Issue の状態変化(着手・PR 作成・マージ)が**追加の人手なしに**ボードへ反映される(反映経路は組み込みワークフロー + コマンド実行時の投影の 2 層)。
- `/github-projects-status` の drift 件数が、通常運用の定常状態で 0 になる。
- 導入による Claude のトークン消費増が、1 チケットあたり数行のコマンド出力に収まる(長いログを司令塔に返さない)。

## スコープ外(初版では実装しない)

- **GitHub Actions による定期同期**(Secret 登録が必須になるため。初版は Secret を 1 つも要求しない設計)
- **自動着手**(候補提示から `/next-ticket` の自動実行へ進む機能)。設定キーの予約のみ行い、実装はしない
- Iteration(スプリント)・Estimate・ロードマップビューなどの追加フィールド運用
- Status 選択肢そのものの自動整備(GraphQL `updateProjectV2Field`)。初版は人間が UI で整え、コマンドは**読み取って対応付ける**
- Projects (classic) への対応
- Codex 側からの Projects 参照・更新(sandbox はネットワーク無効。恒久的に対象外)

## 参照ドキュメント

- `.claude/rules/lead/branch-and-tickets.md` — チケット運用(Issues + ラベル)の現行仕様
- `.claude/rules/lead/delegation-policy.md` — 委託禁止領域と委託粒度
- `AGENTS.md` §3 / §4 — Codex の禁止事項と委託禁止領域
- `.claude/commands/next-ticket.md` / `kickoff.md` / `setup-tickets.md` / `status.md` — 差し込み先
- GitHub 公式ドキュメント(2026-09-15 時点で確認):
  - Automating projects using Actions — `GITHUB_TOKEN` は Projects にアクセスできない
  - REST API endpoints for Projects(API version `2026-03-10`)
  - gh CLI マニュアル `gh project` — 最小スコープは `project`
  - Built-in automations — 既定で有効なのは「closed → Done」「PR merged → Done」の 2 つ
