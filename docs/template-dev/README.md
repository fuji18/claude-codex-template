# template-dev/ - テンプレート開発の記録

このディレクトリは**テンプレート自体の開発記録**であり、テンプレートから作られたプロジェクトの成果物ではない。
`docs/ideas/` と異なり、`/setup-project` や `/kickoff` の読み込み対象外。

| ファイル | 内容 |
|---|---|
| `CHANGELOG.md` | **テンプレート利用側が `/sync-template` で読む変更履歴**(`[auto]` / `[manual]` 区分)。テンプレート側を変更したら必ずここに追記する |
| `cost-model.md` | トークンコストの実測値と、モデル運用・コンテキスト管理の判断根拠。ルールファイル(`.claude/rules/`)は subagent 起動のたびに全量ロードされるため、根拠はここに分離する |
| `econ-measurement.md` | **モード B(econ)の効果測定の設計**(何を・いつ・どう記録し、どの条件で結論を出すか)。記録の実体は `.harness/decisions.jsonl` の `usage` フィールド |
| `initial-requirements.example.md` | `docs/ideas/initial-requirements.md` の記入例(「早起きは三文の得」) |
| `dependabot-product.example.yml` | プロダクト開発向け `.github/dependabot.yml` の記入例 |
| `harness-setup-v2.md` | ハーネス層(`/harness-setup`)の設計判断の記録 |
| `harness-setup-v1-draft.txt` | ハーネススキルの最初の下書き(v1) |
| `cursor-coexistence-plan.md` | **Cursor 主環境 + 実装を Composer に委託**する構成の導入手順と運用ルール。**保留**(先に「実装フェーズだけ Sonnet に切替」を採用したため。足りなかった場合の次の手段) |
| `codex-delegation-plan.md` | **Codex 併用ハーネスの正典**(採用済み)。委託経路 `delegate-codex.sh`・3 モード運用(normal / econ / degraded)・ベンダー中立ガードレール・段階導入の記録。**段階0〜6 まで実装完了(2026-08-24)**。スクリプトやルールのコメントが `§n` で参照する先はこのファイル |
| `codex-harness.html` | 上記の**解説ページ**(図と折り畳みの検討メモつき)。正は `codex-delegation-plan.md` 側で、こちらは読み物 |
| `codex-harness-review.html` | Codex 併用ハーネスの実装レビュー記録 |
| `vendor-neutral-guard-review.html` | ベンダー中立ブランチガード(段階1)のレビュー指摘まとめ |

プロダクト開発を開始したら、このディレクトリは**丸ごと削除してよい**(原本はテンプレートリポジトリに残っている)。プロジェクト開始後も参照が続くガイド(MCP 導入ガイド・serena 再導入手順)は `.claude/docs/` にあり、このディレクトリには含まれない。
