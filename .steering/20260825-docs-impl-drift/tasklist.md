# タスクリスト: 実装とドキュメントの乖離解消

<!-- main-edit-ok -->
> テンプレート自体の改修(ドキュメント整合)であり、司令塔が直接編集する作業。
> 実装フェーズの委譲強制(`check-implementation-phase.sh`)を解除する。

- [x] D1: 「強制層 4 段」→「強制 3 層 + 情報提供 1 層」(rules/lead・README・development-guidelines スキル・解説 HTML)
- [x] D2: `check-implementation-phase.sh` の通過パスに `.github/` `.husky/` を追記(README・解説 HTML)
- [x] D3: AGENTS.md §1-3 の git hook 検査を実装(空 or 実在しないディレクトリ)に合わせる
- [x] D4: `docs/template-dev/README.md` の Codex 委託「不採用」記述を実態に更新 + HTML 3 本を表に追加
- [x] D5: `codex-harness.html` の masthead・§01 段落・段階06 を現状に更新
- [x] D6: CHANGELOG に 2026-08-23 / 08-24 / 08-25 を追加(段階3〜6 + #15)
- [x] D7: `codex-run.sh` ヘッダに `pending` を追記
- [x] D8: `delegate-codex.sh` の `--background` 文言を実態に(処理は変えない)
- [x] D9: `session-start.sh` 冒頭コメントに 5) 6) を追記
- [x] D10: 計画書 §3.1 に `fix-ci` / `--background` の実装状況を明記
- [x] 品質チェック(lint / 型 / フォーマット / テスト)を通す

---

## 振り返り(2026-08-25)

- **実装は 1 行も変えていない。** 変えたのはドキュメントと、実態と食い違っていた
  スクリプト内コメント・メッセージ文言のみ(`--background` の案内 / `codex-run.sh` の使い方 /
  SessionStart の項目一覧)。挙動の差分は無い(`bash -n` + 引数スモークで確認)。
- **乖離が生まれた場所には偏りがある。** 10 件中 6 件が「段階が進んだのに、段階2 時点の記述が
  残っていた」もの(解説 HTML・`docs/template-dev/README.md`・CHANGELOG・スクリプトの未来形コメント)。
  実装 PR が触るのは計画書(`codex-delegation-plan.md`)までで、**その外側にある派生ドキュメントが
  取り残される**。とくに CHANGELOG は「取り込む側が読む唯一の面」なので、欠けると
  `/sync-template` 利用者が段階3〜6 を知らないまま同期することになる。
- **改善提案**: チケット完了時のチェックに「CHANGELOG に当日分の項目があるか」を
  機械的に見る層を置く(例: `.github/workflows` で、`.claude/` `.husky/` `AGENTS.md` を触った PR に
  `docs/template-dev/CHANGELOG.md` の変更が無ければ警告)。散文の「必ず追記する」だけでは 4 回連続で守られなかった。
- **「強制層は 4 段」の書き直しは、Codex の第二意見が 2026-08-23 に指摘してから 2 日間放置されていた。**
  計画書に「次に §8 を触るときに直す」と書いた宿題は、その §8 を触る機会が来ないと消化されない。
  宿題は Issue にするか、その場で直すかの二択にした方がよい。
