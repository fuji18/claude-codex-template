# タスクリスト: delegate-codex.sh の自己編集ハザードを塞ぐ(#15)

design.md の該当節を読んでから着手する。番号順に 1 つずつ実施し、**1 タスク完了ごとにこのファイルを `- [x]` へ更新する**。

- [x] 1. `.claude/scripts/delegate-codex.sh` の `set -uo pipefail` 直後に自己コピー & exec ブロックを挿入する(design.md §2 のコードをそのまま貼る)
- [x] 2. 同ブロックの後半(`SELF_COPY_DIR` / `trap`)まで含めて `bash -n .claude/scripts/delegate-codex.sh` で構文を確認する
- [x] 3. `.steering/20260825-issue15-self-edit-hazard/repro-self-edit.sh` を新規作成する(design.md §3。スタブ・フィクスチャ・安全策・S1〜S3・C1〜C6・後始末チェック・集計まで全部)
- [x] 4. `bash .steering/20260825-issue15-self-edit-hazard/repro-self-edit.sh` を実行し、S1 が「旧挙動を再現(非 0 / status=running)」、S2・S3 が「exit 0 / status=completed」になることを確認する。落ちたら原因を直して全 PASS にする
- [x] 5. 同スクリプトの契約チェック C1〜C6 がすべて期待値どおりになることを確認する
- [x] 6. 実行後に `.claude/scripts/delegate-codex.sh` が元に戻っていること(`git diff` が §2 の追加分だけ)と、`tmp/repro-issue15*` が消えていることを確認する
- [x] 7. `.steering/20260825-issue15-self-edit-hazard/test-procedure.md` を作成する(実行方法・各チェックの意味・期待出力・失敗時の見方。design.md §3 の表をそのまま載せてよい)
- [x] 8. `AGENTS.md` §4 委託禁止領域の `delegate-codex.sh` の行を design.md §5 のとおり差し替える(**行自体は消さない**)
- [x] 9. `CLAUDE.md`「Codex への委託禁止領域(パス)」の `delegate-codex.sh` の行を design.md §5 のとおり差し替える
- [x] 10. `docs/template-dev/codex-delegation-plan.md` §9 に design.md §6 の追記を入れる
- [x] 11. `npx prettier --write` を変更した Markdown に当て、`npx eslint .` と `npx tsc --noEmit` が通ることを確認する(シェルスクリプトは lint 対象外)

## 申し送り

- **`exec` 失敗後のフォールバック経路は存在しない。** 非対話 bash は `exec` に失敗した時点で終了する(`execfail` 未設定。実測 exit 127)。`exec` の直後にコードを足しても到達しないので、そこに回復処理を書かないこと
- **末尾への追記では自己編集ハザードは再現しない。** bash が保存しているのはバイトオフセットなので、既読位置より後ろにバイトを足しても読み取りはずれない。再現には既読位置より**手前**を変えるか(insert)、ファイル全体を置き換える(overwrite)必要がある。ここを取り違えると「書き換えたのに落ちない」= 空振りするテストになる
- **`repro-self-edit.sh` は実物のガードレールファイルを一時的に書き換える。** `package.json` の scripts にも CI にも載せていない(手動実行専用)。実行が中断されたときは `git diff -- .claude/scripts/delegate-codex.sh` を確認すること
- **この環境では `.claude/settings.local.json` が denylist に一致する**ため、`delegate-codex.sh` の入口検査1 が毎回止まる。再現テストは `CODEX_DELEGATE_ACK_SECRETS=1` を付けて回避している。実運用で毎回承認を求められるのが煩わしければ denylist 側の見直しが要る(本チケットのスコープ外)
- **委託禁止領域から `delegate-codex.sh` は外していない。** 塞いだのは「実行中プロセスが死ぬ」ハザードだけで、「壊れた入口がコミットされると以後の委託が全滅する」リスクは残る(design.md §5)
