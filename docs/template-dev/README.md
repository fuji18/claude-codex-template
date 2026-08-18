# template-dev/ - テンプレート開発の記録

このディレクトリは**テンプレート自体の開発記録**であり、テンプレートから作られたプロジェクトの成果物ではない。
`docs/ideas/` と異なり、`/setup-project` や `/kickoff` の読み込み対象外。

| ファイル | 内容 |
|---|---|
| `CHANGELOG.md` | **テンプレート利用側が `/sync-template` で読む変更履歴**(`[auto]` / `[manual]` 区分)。テンプレート側を変更したら必ずここに追記する |
| `cost-model.md` | トークンコストの実測値と、モデル運用・コンテキスト管理の判断根拠。ルールファイル(`.claude/rules/`)は subagent 起動のたびに全量ロードされるため、根拠はここに分離する |
| `initial-requirements.example.md` | `docs/ideas/initial-requirements.md` の記入例(「早起きは三文の得」) |
| `dependabot-product.example.yml` | プロダクト開発向け `.github/dependabot.yml` の記入例 |
| `harness-setup-v2.md` | ハーネス層(`/harness-setup`)の設計判断の記録 |
| `harness-setup-v1-draft.txt` | ハーネススキルの最初の下書き(v1) |
| `cursor-coexistence-plan.md` | **Cursor 主環境 + 実装を Composer に委託**する構成の導入手順と運用ルール。**保留**(先に「実装フェーズだけ Sonnet に切替」を採用したため。足りなかった場合の次の手段) |
| `codex-delegation-plan.md` | Codex(codex-plugin-cc)委託の統合案。**不採用**(Codex は使わない方針が確定)。記録としてのみ保存 |

プロダクト開発を開始したら、このディレクトリは**丸ごと削除してよい**(原本はテンプレートリポジトリに残っている)。プロジェクト開始後も参照が続くガイド(MCP 導入ガイド・serena 再導入手順)は `.claude/docs/` にあり、このディレクトリには含まれない。
