<!-- テンプレート所有ファイル: /sync-template で上書きされます。 -->
<!-- SessionStart hook が .harness/mode = econ のときにのみ注入します。サブエージェントには載りません。 -->

## 現在のハーネスモード: B(節約 / `.harness/mode` = `econ`)

Claude の週枠を温存する運用。**モードの切替を宣言するのは人間**(`/usage` の残枠を見て判断する)。Claude は自動で降格も復帰もしないし、`.harness/mode` を自分で書き換えない。

### 司令塔の作法

1. **`design.md` を書き切り、完成マーカーを `<!-- status: ready -->` にしたらセッションを閉じる。** 検収まで待たない
2. **`/check` も `code-reviewer` も回さない。** 機械的検証は CI に、スペック整合は枠が戻ってからの一括レビューに委ねる
3. 実装委託(`delegate-codex.sh impl`)は**人間がターミナルから叩く**。Claude セッションを開けたまま待たない
4. 委託後の `/commit` → `push` → **draft PR** は、最小コンテキストの新セッションで行う

検収を飛ばした分の担保は、ベンダー中立ガードレール(`.husky/*`)と CI(`ci.yml`)。

### PR は draft で積み、マージしない

- **draft は作法ではなく節約の実体。** `claude-code-review.yml` は `draft == false` のときだけ走るため、draft のままなら Claude レビューが起動しない。非 draft で開くと、このモードが温存しようとしているまさにその枠を PR ごとに消費する
- `ci.yml` の `pull_request` トリガは draft でも発火する。**機械的検証は受けたままレビューだけを止められる**
- PR を作るときは **`--draft` を必ず付ける**。PR ボディの「検証」節には `/check` 済みのチェックを付けず、**「モード B のため検収未実施(CI に委ねる)」と明記する**
- 積んだ PR は**マージしない**。枠が戻ったら人間が `gh pr ready [番号]` で切り替える → `types: [opened, ready_for_review]` により**レビューが自動起動する**(手動で呼び直す必要はない)
- 急ぐ場合の例外は**ユーザーが明示的に判断する**。司令塔の裁量で非 draft を既定にしない

### 手順の順序を逆にしない

`ci.yml` のトリガは `push: [main, develop]` と `pull_request` だけで、**作業ブランチへの push だけでは CI は走らない**。「CI が緑なら PR を作る」は因果が逆で、**draft PR を作って初めて CI が動く**。このモードは検収を CI に預ける設計なので、取り違えると検収が丸ごと空振りする。

根拠: `docs/template-dev/codex-delegation-plan.md` §2.1 / §2.6 / §12.2
