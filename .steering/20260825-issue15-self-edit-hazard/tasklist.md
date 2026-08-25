# タスクリスト: delegate-codex.sh の自己編集ハザードを塞ぐ(#15)

design.md の該当節を読んでから着手する。番号順に 1 つずつ実施し、**1 タスク完了ごとにこのファイルを `- [x]` へ更新する**。

- [ ] 1. `.claude/scripts/delegate-codex.sh` の `set -uo pipefail` 直後に自己コピー & exec ブロックを挿入する(design.md §2 のコードをそのまま貼る)
- [ ] 2. 同ブロックの後半(`SELF_COPY_DIR` / `trap`)まで含めて `bash -n .claude/scripts/delegate-codex.sh` で構文を確認する
- [ ] 3. `.steering/20260825-issue15-self-edit-hazard/repro-self-edit.sh` を新規作成する(design.md §3。スタブ・フィクスチャ・安全策・S1〜S3・C1〜C6・後始末チェック・集計まで全部)
- [ ] 4. `bash .steering/20260825-issue15-self-edit-hazard/repro-self-edit.sh` を実行し、S1 が「旧挙動を再現(非 0 / status=running)」、S2・S3 が「exit 0 / status=completed」になることを確認する。落ちたら原因を直して全 PASS にする
- [ ] 5. 同スクリプトの契約チェック C1〜C6 がすべて期待値どおりになることを確認する
- [ ] 6. 実行後に `.claude/scripts/delegate-codex.sh` が元に戻っていること(`git diff` が §2 の追加分だけ)と、`tmp/repro-issue15*` が消えていることを確認する
- [ ] 7. `.steering/20260825-issue15-self-edit-hazard/test-procedure.md` を作成する(実行方法・各チェックの意味・期待出力・失敗時の見方。design.md §3 の表をそのまま載せてよい)
- [ ] 8. `AGENTS.md` §4 委託禁止領域の `delegate-codex.sh` の行を design.md §5 のとおり差し替える(**行自体は消さない**)
- [ ] 9. `CLAUDE.md`「Codex への委託禁止領域(パス)」の `delegate-codex.sh` の行を design.md §5 のとおり差し替える
- [ ] 10. `docs/template-dev/codex-delegation-plan.md` §9 に design.md §6 の追記を入れる
- [ ] 11. `npx prettier --write` を変更した Markdown に当て、`npx eslint .` と `npx tsc --noEmit` が通ることを確認する(シェルスクリプトは lint 対象外)
