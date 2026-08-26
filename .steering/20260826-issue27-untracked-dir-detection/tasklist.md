# タスクリスト: Issue #27

- [x] 1. 修正前の挙動を実測する(design.md §4-1〜4-4 のスタブとプローブを用意し、シナリオ B → A の順に実行。**シナリオ A が `exit 2` になること**を確認して控える)
- [x] 2. `tree_snapshot()` を `--untracked-files=all` 付きに変更する(design.md §1 のコメント込みでそのまま適用)
- [x] 3. `bash -n .claude/scripts/delegate-codex.sh` を通す
- [x] 4. 修正後の挙動を実測する(シナリオ B = `exit 2` のまま / シナリオ A = `exit 0` に変わること)
- [x] 5. 走査量を再計測する(design.md §5)
- [x] 6. `grep -rn 'tree_snapshot\|porcelain' --include='*.md' .` を実行し、ドキュメント側に実装詳細の記述が無いことを確認する
- [x] 7. `verification.md` を design.md §6 の項目立てで作成する
- [x] 8. 後片付け(design.md §4-5)を行い、`git status --short` が意図した差分のみであることを確認する
