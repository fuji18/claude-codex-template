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

## 振り返り(司令塔 / 2026-08-27)

### 結果

実装は fork 1 回(往復 0 回)で完了。検収は `code-reviewer` 0 critical / 1 major / 4 minor、`test-runner` 全パス。**受け入れ条件 5 項目すべてを実 PR(#39)上で確認済み。**

| 受け入れ条件 | 確認方法 | 結果 |
| --- | --- | --- |
| `.claude/` 変更 + CHANGELOG 無しで検出 | run 33125409357 の annotation | ✅ |
| CHANGELOG 変更済みなら鳴らない | 最終 push 後の run | ✅ |
| 逃げ道ラベルが効く | 両ラベル付与 → run 33125453488 が緑・両検査が NOTICE | ✅ |
| decisions.jsonl の起動点が決まり根拠が記録されている | `design.md` §0 の決定事項表 | ✅ |
| 運用が `delegation-policy.md` に反映 | 「実測の記録」節 | ✅ |

### 学び

1. **受け入れ条件の「実際に PR を立てて確認する」が決定的だった。** 手元検証 11 ケースと code-reviewer 検収をすべて通した後、実 PR の初回実行(run 33125304790)で「**赤くはなるが annotation も Job Summary も出ない**」欠陥が出た。GitHub Actions の `run:` の既定シェルは `bash -e {0}` で、`set -uo pipefail` を書いても `-e` は残る。手元検証は `bash "$S"` を直接叩いており、`-e` 付きシェルから呼ぶ経路を再現できていなかった。**CI に検査を足すチケットでは「検査が落ちたときに理由が表示されるか」まで実環境で確認する。**
2. **検査を足すときは、検査自身の fail-open を必ず見る。** code-reviewer の Major(`gh api` 失敗時に `changed.txt` が空のまま緑になる)は、このチケットが塞ごうとしている「記録漏れが静かに見逃される」事象が別経路で再現する型だった。皮肉にも、その指摘への対応で書いた「判定ステップに `-e` を付けてはいけない」という文が、**既定で付いていることの見落とし**と同居していた。
3. **散文のルールと実運用がずれている場合、機械化は実運用の側に合わせてルール文を直す。** Issue は decisions.jsonl の記録を「マージ後に司令塔が書く」前提で「PR 時点では必ず落ちる」と懸念していたが、実運用では記録コミット(#29 の `1dc687d`)がマージ前のブランチ上にあり、値も PR 前の検収で確定していた。ルールを実態に合わせた結果、起動点は PR 時で成立した。

### 申し送り

- **CHANGELOG のトリガパスは 4 系統(`.claude/` / `.husky/` / `.codex/` / `AGENTS.md`)に限定してある。** `template-manifest.json` の owned / merge には `.github/workflows/*.yml` や `.gitignore` も含まれるが今回は広げていない(記録漏れの実績があるのはこの 4 系統)。拡大が要るなら別チケット
- 逃げ道ラベル `no-changelog` / `no-decision-record` は**このリポジトリには作成済み**。テンプレート利用側は自分で作る必要があり、CHANGELOG の `[manual]` に明記した
