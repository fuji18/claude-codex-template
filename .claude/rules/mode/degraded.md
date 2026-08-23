<!-- テンプレート所有ファイル: /sync-template で上書きされます。 -->
<!-- SessionStart hook が .harness/mode = degraded のときにのみ注入します。サブエージェントには載りません。 -->

## 現在のハーネスモード: C(縮退 / `.harness/mode` = `degraded`)

**このモードは「Claude が動かない期間」のために宣言されたもの。** あなた(Claude)が起動しているということは、次のどちらかが起きている:

1. **枠が回復した** → 縮退中に Codex が積んだ成果を検収し、PR に合流させる(下記)
2. **モードの戻し忘れ** → 同じ手順で未検収の成果が無いことを確かめる

どちらの場合も、合流後に**人間へ `.harness/mode` を `normal` か `econ` に戻すよう促す**。**`.harness/mode` は Claude が書き換えない**(切替の宣言は人間の担当)。

### 復帰時の検収(§2.3)

1. `git log --grep 'Codex-authored' --oneline` で縮退中のコミットを特定する
2. `.steering/[dir]/codex-log.md` を読む。**「設計判断」欄は必ず回収する**(`design.md` に無い判断が下されている可能性がある)
3. 通常フローの検収(`/check` + `code-reviewer`)を回す
4. PR を作る(縮退中は Codex が PR を作らない設計 = キューとして設計されている)

根拠: `docs/template-dev/codex-delegation-plan.md` §2.3 / §12.3
