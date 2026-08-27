# タスクリスト: チケット記録の機械的検査(Issue #37)

対象: `.steering/20260827-issue37-record-hygiene-ci/design.md`

## 実装フェーズ(implement-ticket / Sonnet fork)

- [x] 1. `.claude/scripts/check-record-hygiene.sh` を design.md §1 の全文どおり新規作成する
- [x] 2. 同スクリプトに実行権限を付ける(`chmod +x` に加えて `git update-index --chmod=+x` を実行する。`core.fileMode=false` の環境では index に反映されないため)
- [x] 3. `.github/workflows/record-hygiene.yml` を design.md §2 の全文どおり新規作成する
- [x] 4. `.claude/template-manifest.json` の `owned` に `.github/workflows/record-hygiene.yml` を追加する(design.md §3)
- [x] 5. `.claude/rules/lead/delegation-policy.md` の「### 実測の記録」節を design.md §4 の内容で置き換える
- [x] 6. design.md §6 の検証 1〜11 を実行し、各コマンドの出力と rc を `verification.md` に記録する
- [x] 7. design.md §6 の yaml 構文検証を実行する(PyYAML が無ければスキップし、その旨を `verification.md` に明記する)
- [x] 8. `npm run format:check` を通す(整形が要求されたら `npm run format` を実行してから再確認する)
- [x] 9. `verification.md` に「触っていないこと」の確認を書く: `docs/template-dev/CHANGELOG.md` / `.harness/decisions.jsonl` / `.github/workflows/ci.yml` を変更していない(`git status --short` の出力を貼る)

**重要**: `docs/template-dev/CHANGELOG.md` と `.harness/decisions.jsonl` は**実装フェーズで絶対に触らない**(design.md §5)。触ると受け入れ条件1(実 PR で検出されること)が確認できなくなる。

**設計判断が必要になったら停止して報告する。** design.md に書かれていない判断を推測で下さない。

## 後続(司令塔が実装フェーズ完了後に行う。実装者は着手しない)

- 検収: `code-reviewer` + `test-runner`(`/check`)
- ラベル作成: `gh label create no-changelog` / `gh label create no-decision-record`
- コミット → push → **draft PR**(`Closes #37`)を作成し、`record-hygiene` が **赤**になることを確認する
  - 受け入れ条件1(CHANGELOG 未更新の検出)と decisions.jsonl 未記録の検出が同時に確認できる
- `no-changelog` ラベルを付けて再実行 → CHANGELOG 検査が NOTICE になることを確認 → ラベルを外す(受け入れ条件3)
- `docs/template-dev/CHANGELOG.md` に記法の追記と `## 2026-08-27` 節を書く
- `.harness/decisions.jsonl` に #37 の 1 行を追記する
- push → `record-hygiene` が **緑**になることを確認する(受け入れ条件2)
- 振り返りを `tasklist.md` に追記 → `gh pr ready`
