# 要件: Claude レビューの skip を可視化する(Issue #12)

## 背景

`claude-code-review.yml` / `claude.yml` は、シークレット未設定の配布先で壊れないよう本体ステップを
`if: env.CLAUDE_TOKEN != ''` で守っている。**このガード自体は正しい。**

問題は skip が**無言**であること。ステップが skip されてもジョブは `success` を返すため、
PR 上では「レビュー通過」と区別がつかない。

実測(2026-08-24、本リポジトリ):

- Actions シークレット 0 件(`CLAUDE_CODE_OAUTH_TOKEN` 未登録)
- `claude-code-review.yml` の直近 5 実行すべてで `Run Claude Code Review` = `skipped` / ジョブ = `success`
- PR #10・#11 に投稿されたレビュー・コメントは 0 件

= **このリポジトリで Claude レビューは一度も実行されていない。**

`delegate-codex.sh` が「成果の実在確認」で潰した **「`exit 0` がタスクの成否を表さない」問題と同型**。
委託経路には検査を入れたのに、レビュー経路には無い。

## 影響

- `.claude/rules/lead/review-policy.md` の「PR 時の最終ゲート(自動 1 回)」に受け皿が無い
- モード B(節約)の出口「draft で積み、枠が戻ったら `gh pr ready` でまとめてレビュー」が成立せず、
  **出口の無いキュー**になる

## 方針(制約)

**ガードは外さない。** シークレット未設定の配布先でジョブを fail させると、レビューと無関係な PR まで
赤くなる。直すのは「沈黙」であって「skip」ではない。

## 受け入れ条件

- [ ] シークレット未設定の状態で PR を開くと、run の annotation と job summary に「レビュー未実行」が出る
- [ ] ジョブの結論は `success` のまま(赤くならない)
- [ ] `claude.yml` でも同様に、`@claude` に応答できないことが run 上に残る
- [ ] README にシークレット登録の手順があり、`success` がレビュー通過を意味しないことが書かれている
- [ ] 実機で 1 回確認する(この Issue の PR 自体が確認機会)

## スコープ外

- シークレットの登録そのもの(人間の作業)
- `if: env.CLAUDE_TOKEN != ''` ガードの削除・ジョブの fail 化
- 必須チェック(ruleset)への `claude-review` 追加(未設定の配布先でマージ不能になる)

## 根拠

- `docs/template-dev/codex-harness-review.html` S7 / D6
- `docs/template-dev/codex-delegation-plan.md` §2.6
