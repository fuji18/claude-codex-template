---
description: (econ の自動進行用)Codex が実装を終えたチケットをコミットして draft PR にする。検収はしない(CI に委ねる)
---

# 委託成果の出荷(econ)

モード B(econ)で `autopilot-loop.sh` が呼ぶコマンドです。計画(`/next-ticket N --plan-only`)→ 実装(ループがシェルから `delegate-codex.sh impl`)の後に、**最小のコンテキストで**コミット → push → draft PR だけを行う(`.claude/rules/mode/econ.md` の 4)。

**引数:** Issue 番号(例: `/ship-ticket 12`)

---

## 手順

1. 前提を確かめる。満たさなければ理由を 1 行報告して**何もせず終了する**:
   - `bash .claude/scripts/harness-mode.sh` が `econ`
   - 現在のブランチがこのチケットのもの(名前に `issue[番号]-` を含む)
   - `.steering/*-issue[番号]-*/tasklist.md` に未完了(`- [ ]`)が無い
2. **`/check` も `code-reviewer` も回さない**(econ.md の 2)。`git diff --stat` と `tasklist.md` だけを見て、PR の概要を書く材料にする。`package.json` のライフサイクル差分は**ループが事前に検査済み**(差分があればループは止まり、ここに来ない)
3. `Skill('commit')` で委託成果をコミットする(Codex は `.git` を書けないため、成果は未コミットで残っている)
4. `.harness/decisions.jsonl` に 1 行追記してコミットする(**PR より前**。delegation-policy.md「実測の記録」)。`implementer` は `"codex"`、往復・指摘数は委託の実績どおり、`review_rounds` は `0`。無人実行なので `/usage` は尋ねず `"usage": {"mode": "econ", "weekly_pct": null, "raw": "autopilot 無人実行のため未取得"}` とする
5. `git push` し、**draft で** PR を作る(`/add-feature` ステップ8 の形式。`--draft` 必須・ベースは `.claude/branch-policy.json` の `baseBranch`・ボディに `Closes #[番号]`)。「検証」節にはチェックを付けず「モード B のため検収未実施(CI に委ねる)」と書く
6. Issue にコメントする: `実装完了(draft)。PR: [URL] / steering: .steering/[dir]`
7. PR URL を 1 行で報告して終了する。**マージ・ready 化はしない**(枠が戻ったら人間が `gh pr ready` する)
