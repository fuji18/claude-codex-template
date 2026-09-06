# タスクリスト: #83 委託禁止領域節のポインタ化

> 設計は `design.md`。**設計判断は済んでいる**(検査は「残して双方向化」= design.md §4)。
> 迷ったら停止して報告すること。

## 計測(前)

- [x] 1. `wc -c CLAUDE.md` と当該節のバイト数を記録する(design.md §9 のコマンド。着手時点: 11,368 B / 7,845 B)。実測: `CLAUDE.md` = 11,368 B / 当該節 = 6,001 B(design.md 記載値と当該節の数値が一致しないが、実測をそのまま記録する。全体バイト数は一致)

## 移設(順序を守る。3 → 2 → 1 の順で、原文が消える前に写す)

- [x] 2. `docs/template-dev/codex-delegation-plan.md` §9 の末尾に `### 9.1 委託禁止領域の設計(なぜこのパスなのか)` を新設し、現行 `CLAUDE.md` L27〜L52 の記述を**そのまま**移す(design.md §3)
- [x] 3. `.claude/rules/lead/delegation-policy.md` に `### 委託禁止領域(パス一覧)` 節を挿入し、L14 の参照を差し替える(design.md §2)
- [x] 4. `CLAUDE.md` の当該節をポインタに置換する(design.md §1)

## 検査の双方向化

- [x] 5. `delegate-codex.sh` に `--print-forbidden generic` を足す(design.md §5。4 箇所)
- [x] 6. `check-forbidden-paths-doc.sh` を書き直す(design.md §6)
- [x] 7. `.github/workflows/ci.yml` の該当コメントを更新する(design.md §7)

## 参照の張り替え

- [x] 8. `README.md` / `.claude/commands/kickoff.md`(2 箇所)/ `next-ticket.md` / `setup-tickets.md` を design.md §8 の表のとおり直す

## 検証と記録

- [x] 9. design.md §6「検証」の 6 項目をすべて実行し、結果(rc と警告件数)をこの行の下に追記する
  - 1) 乖離なし: rc=0・出力なし
  - 2) 順方向(表から `.husky/` の行を削除): 警告1件・rc=1(「委託禁止領域 '.husky/' が...書かれていない」)。復元後 rc=0 に戻ることを確認
  - 3) 逆方向(表に `.claude/nonexistent-guard.json` の行を追加): 警告1件・rc=1(「...一覧にある '.claude/nonexistent-guard.json' が...FORBIDDEN_PATHS に無い」)。復元後 rc=0 に戻ることを確認
  - 4) 部分一致バグの回帰(表の `.husky/` を `.husky/pre-commit` に変更): **両方向**で警告2件・rc=1(順方向: `.husky/` が無い / 逆方向: `.husky/pre-commit` が無い)。旧実装は素通ししていたが新実装は検知した。復元後 rc=0 に戻ることを確認
  - 5) generic の分離: `--print-forbidden generic` の出力は配列と同じ 15 件
  - 6) 引数検査: `--print-forbidden bogus` は rc=2(EX_FAIL)
- [x] 10. `bash .claude/scripts/check-guard-integrity.sh` が新規の指摘を出さないことを確認する。実行結果: 出力なし・rc=0
- [x] 11. 計測(後)を実行し、削減幅(前 → 後、削減バイト数と割合)をこの行の下に追記する
  - `CLAUDE.md` 全体: 11,368 B → 6,707 B(削減 4,661 B / 41.0%)
  - 当該節: 実測ベース(タスク1で記録した着手時点の実測 6,001 B)→ 1,340 B(削減 4,661 B / 77.7%)
- [x] 12. `docs/template-dev/CHANGELOG.md` に追記する(design.md §10)
