---
description: ドキュメントの詳細レビューをサブエージェントで実行
---

# ドキュメントレビュー

`docs/` のドキュメントの詳細レビューを `doc-reviewer` subagent(Sonnet)に委譲するコマンド。**レビュー観点・出力形式は `doc-reviewer` の定義(`.claude/agents/doc-reviewer.md`)が正**で、ここには重複記述しない。

**引数:** ドキュメントパス(例: `/review-docs docs/product-requirements.md`)

## 手順

1. 指定されたドキュメントの存在を確認する。引数がない場合は `docs/` の一覧を提示して対象を確認する
2. Agent ツールで `doc-reviewer` subagent を起動する。プロンプトにはドキュメントパスと(あれば)重点観点だけを渡す(ファイル内容は貼らず、subagent 自身に読ませる)
3. 返ってきた指摘リストをそのままユーザーに提示し、`[必須]` の指摘があれば修正を提案する
