<!-- status: ready -->

# 設計: Claude レビューの skip を可視化する(Issue #12)

## 設計方針

skip の判定は変えず、**skip したという事実を run に残す**。手段は 2 つ:

| 手段 | 出る場所 | ジョブの結論 |
| --- | --- | --- |
| `::warning` ワークフローコマンド | run のヘッダの annotation | 変わらない(緑のまま) |
| `$GITHUB_STEP_SUMMARY` への追記 | run の Summary ページ | 変わらない |

`::error` は使わない(annotation は赤くなるがジョブは緑のままで、**見た目と結論が食い違う**方が紛らわしい)。
`exit 1` も使わない(方針「ガードは外さない」に反する)。

## 決定事項(実装者は判断しない)

1. **共通化しない。** 2 ワークフローに同じ形のステップをインラインで複製する。
   composite action を切ると `.claude/template-manifest.json` の同期対象が 1 つ増え、
   10 行の重複を消すために配布面が増える。割に合わない。
2. **`$GITHUB_STEP_SUMMARY` への書き込みはクォート付きヒアドキュメント(`<<'EOF'`)を使う。**
   本文にバッククォートが多数出るため、`echo "..."` だとバックスラッシュ退避が必要になり壊れやすい。
   `<<'EOF'` は変数展開もコマンド置換も起きないので退避が一切要らない。
3. **ヒアドキュメントの終端 `EOF` は本文と同じインデントに置く。**
   YAML のリテラルブロック(`run: |`)は共通インデントを除去してから bash に渡すため、
   ステップ内で揃えてあれば bash からは列 0 に見える。`<<-` は使わない(タブが要るため)。
4. **ステップ名は `Notify review skipped`(`claude-code-review.yml`)/ `Notify mention skipped`(`claude.yml`)。**
5. **配置は本体ステップの直後**(最終ステップ)。
6. **`if: env.CLAUDE_TOKEN == ''`** を使う。`env` コンテキストはステップの `if` で参照でき、
   既存の `if: env.CLAUDE_TOKEN != ''` が同じ参照で動いている実績がある。
7. **prettier の検査対象である点に注意する。** `.prettierignore` は `.github/` を除外していないため、
   `npm run format:check` が両ファイルを見る。編集後に `npm run format` を通してから差分を確認すること。

## 変更 1: `.github/workflows/claude-code-review.yml`

既存の `Run Claude Code Review` ステップ(ファイル末尾)の**直後**に以下を追加する。
既存部分は一切変更しない。

```yaml
      - name: Notify review skipped
        if: env.CLAUDE_TOKEN == ''
        run: |
          echo "::warning title=Claude レビュー未実行::CLAUDE_CODE_OAUTH_TOKEN が未設定のため Claude Code Review は実行されていません。このジョブの success はレビュー通過を意味しません。"
          cat >> "$GITHUB_STEP_SUMMARY" <<'EOF'
          ## ⚠️ Claude レビューは実行されていません

          `CLAUDE_CODE_OAUTH_TOKEN` が Actions シークレットに未設定のため、`Run Claude Code Review` は skip されました。

          **このジョブの `success` はレビュー通過を意味しません。**

          Settings → Secrets and variables → Actions で登録するまで、
          モード B(節約)の「draft で積んで枠の回復後にまとめてレビューする」は出口がありません
          (`docs/template-dev/codex-delegation-plan.md` §2.6)。
          EOF
```

## 変更 2: `.github/workflows/claude.yml`

既存の `Run Claude Code` ステップ(ファイル末尾。末尾はコメント行)の**直後**に以下を追加する。
文面は `@claude` メンション経路に読み替えてある。

```yaml
      - name: Notify mention skipped
        if: env.CLAUDE_TOKEN == ''
        run: |
          echo "::warning title=@claude 応答なし::CLAUDE_CODE_OAUTH_TOKEN が未設定のため @claude メンションに応答できません。このジョブの success は応答したことを意味しません。"
          cat >> "$GITHUB_STEP_SUMMARY" <<'EOF'
          ## ⚠️ @claude メンションに応答していません

          `CLAUDE_CODE_OAUTH_TOKEN` が Actions シークレットに未設定のため、`Run Claude Code` は skip されました。

          **このジョブの `success` は応答したことを意味しません。** メンションは無言で捨てられています。

          Settings → Secrets and variables → Actions で登録してください。
          EOF
```

## 変更 3: `README.md`

Step 0 の項番 2(`CLAUDE_CODE_OAUTH_TOKEN` の設定)に、**サブ項目を 1 つ追加する**。
既存の 2 つのサブ項目は変更しない。挿入位置は既存サブ項目の 1 つ目の直後
(「未設定の間、PR 自動レビュー・`@claude` メンションの Actions はスキップされる(失敗はしない)」の次の行)。

追加する行(インデントは既存サブ項目と同じ 3 スペース):

```markdown
   - **スキップしてもジョブは `success` を返す。** 緑のチェックはレビュー通過を意味しない
     (未設定時は run の annotation と Summary に「未実行」が出る)
```

## 変更 4: `docs/template-dev/codex-delegation-plan.md` §2.6

§2.6 末尾の「前提: リポジトリの Actions シークレットに〜」段落(現状の最終文が
「緑を根拠にマージしない。」)の**直後**に、次の段落を追加する。既存の記述は変更しない。

```markdown
**可視化を入れた(Issue #12 / 2026-08-24)。** 上の取り違えは運用の注意書きだけでは防げないため、
`claude-code-review.yml` / `claude.yml` にシークレット未設定時だけ走る通知ステップを追加した。
skip すると run の annotation(`::warning`)と job summary に「レビュー未実行 / 応答なし」が残る。
**ガードも `success` という結論も変えていない** — 未設定の配布先で無関係な PR まで赤くしないため。
変えたのは沈黙だけで、「緑 = レビュー済み」の誤読を run 上で否定できるようにした。
```

## 検証

自動テストは無い(ワークフローの実行結果を検査する仕組みはこのリポジトリに無い)。

1. `npm run format:check` が通ること(prettier が両 YAML を検査する)
2. YAML として妥当であること(`python3 -c "import yaml,sys; yaml.safe_load(open(...))"` で確認可)
3. **実機確認**: この PR を非 draft で開くと `claude-code-review.yml` が起動する。
   シークレットは未登録なので `Notify review skipped` が走り、
   - run の annotation に「Claude レビュー未実行」が出る
   - Summary に「⚠️ Claude レビューは実行されていません」が出る
   - ジョブの結論は `success`

   の 3 点を確認する(司令塔が PR 作成後に `gh run view` で行う。実装者の担当外)。

## やらないこと

- 既存の `if: env.CLAUDE_TOKEN != ''` の変更
- ジョブを fail させること
- composite action / 再利用ワークフローへの切り出し
- ruleset(必須チェック)への追加
