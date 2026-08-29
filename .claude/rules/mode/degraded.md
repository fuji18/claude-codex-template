<!-- テンプレート所有ファイル: /sync-template で上書きされます。 -->
<!-- SessionStart hook が .harness/mode = degraded のときにのみ注入します。サブエージェントには載りません。 -->

## 現在のハーネスモード: C(縮退 / `.harness/mode` = `degraded`)

**このモードは「Claude が動かない期間」のために宣言されたもの。** あなた(Claude)が起動しているということは、次のどちらかが起きている:

1. **枠が回復した** → 縮退中に Codex が積んだ成果を検収し、PR に合流させる(下記)
2. **モードの戻し忘れ** → 同じ手順で未検収の成果が無いことを確かめる

どちらの場合も、合流後に**人間へ `.harness/mode` を `normal` か `econ` に戻すよう促す**。**`.harness/mode` は Claude が書き換えない**(切替の宣言は人間の担当)。

### 復帰時の検収(§2.3)

1. **ガードレールの健全性を機械検査する(最初にこれを回す)**

   ```bash
   bash .claude/scripts/check-guard-integrity.sh degraded && echo "ガードレール健全"
   ```

   縮退モードは `.git` が書き込み可能な唯一の経路で、`core.hooksPath` の書き換え・
   `.git/hooks/` への直書き・禁止領域を触った `Codex-authored` コミットを検出する。
   **1 行でも出力されたら、その内容を人間に報告してから検収を続ける。**
2. `git log --grep 'Codex-authored' --oneline` で縮退中のコミットを特定する
3. `.steering/[dir]/codex-log.md` を読む。**「設計判断」欄は必ず回収する**(`design.md` に無い判断が下されている可能性がある)
4. 通常フローの検収(`/check` + `code-reviewer`)を回す
5. PR を作る(縮退中は Codex が PR を作らない設計 = キューとして設計されている)

根拠: `docs/template-dev/codex-delegation-plan.md` §2.3 / §12.3
