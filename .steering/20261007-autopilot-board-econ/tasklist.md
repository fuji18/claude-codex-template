<!-- main-edit-ok --> (テンプレート自体の改修。前回の autopilot の参照実装の拡張のため司令塔が書く)
# タスクリスト

- [x] `lib-github.sh`(リポジトリ解決の共通化)
- [x] `autopilot-next.sh`: 完了チケットのタイトル・モード別 WIP 上限
- [x] `autopilot-board.sh`(sync / paused / notify)
- [x] `autopilot-loop.sh`: 全体管理 Issue・一時停止・通知・`--background` / `--stop` / `--log`・econ の 3 段・自分の中断作業の再開
- [x] `/next-ticket --plan-only`・`/ship-ticket`(新規)
- [x] `/autopilot`・`econ.md`・README・CHANGELOG・`.gitignore`・`autopilot.json`
- [x] 検収(code-reviewer + test-runner)
  - code-reviewer: Critical 0 / Major 5 / Minor 7。Major は全件修正(別セッションの放置を約 1 時間で通知 /
    pid は自分のものだけ消し前面実行も排他 / --stop は子孫まで止め、本体を先に TERM して誤通知を防ぐ /
    一時停止の確認失敗は待つ(フェイルクローズ)/ Codex 委託も起動回数に数え exit 4 は 12 回で停止)。
    Minor は 6(タイトルのエスケープ)・7(ブランチ照合の厳格化と重複検出)・8(/ship-ticket 自身も package.json を確認)・
    10(--background の絶対パス)・11(CRLF)・12(econ の /fix-pr と draft 滞留の明記・通知)を修正
  - スタブ通し試験: econ 3 段 / ライフサイクル差分で停止 / 同一状態で停止 / --background の二重起動拒否 / --stop で孫まで停止

## 申し送り

- 9(ライフサイクル差分で止まった後の「目視済み」をループに伝える手段)は据え置き。目視後に人間が `/ship-ticket N` を実行すれば、次の周から PR ありとして進む
- 全体管理 Issue の書き込み(作成・更新・コメント)は実リポジトリでは未実行(このセッションで勝手に Issue を作らないため)。`render` で本文のみ確認済み。初回は `--dry-run` の後に前面で 1 周見ること

## 追加: 開始前の事前チェック(2026-10-07)

- [x] `autopilot-preflight.sh`(✅/⚠️/❌/ℹ️ と直し方。exit 0/1/2/3)
- [x] `autopilot-loop.sh` の起動時にチェックを通す。`--background` は `setsid` で切り離し、`CLAUDECODE` を子に渡さない
- [x] `/autopilot`: 引数なし = チェック → ✅ なら確認なしで開始 / ⚠️ なら AskUserQuestion / ❌ なら停止。`check` / `status` / `stop`
- [x] `settings.json` の allow に無人実行で要る操作を追加
- [x] 手順書・README・CHANGELOG
- [x] 検収(code-reviewer): Critical 0 / Major 4 / Minor 7。Major は全件修正(事前チェックの想定外終了コードで起動しない / delegate-codex.sh の allow を impl に限定 / fix-pr・next-ticket の gh api を allow 済みの gh issue view・gh pr checks・gh run view に置換 / claude のログイン確認)。Minor は 5(setsid の代替)・6(起動確認の待ち)・7(親セッションの変数)・10(econ.maxInFlight の検査)を修正。8・9・11 は据え置き(内部フラグ・保護ブランチ上でもループがブランチを切る・econ の説明は手順書にある)
