<!-- status: ready -->
# 設計: autopilot

## 0. 方針

判定(次に何をするか)は**決定的なシェルスクリプト 1 本**に寄せ、クラウド・ローカル・
`/next-ticket` の 3 経路が同じ結果を使う(`check-protected-branch.sh` と同じ「判定の一本化」)。
GitHub へは **REST(`gh api`)だけ**でアクセスする。クラウドセッションでは GraphQL が 403 になる
(`gh issue list` / `gh pr list` は GraphQL 経由)ため。

## 1. 設定 `.claude/autopilot.json`(template-manifest: merge)

```json
{ "maxInFlight": 2, "pollSeconds": 300, "maxRuns": 20 }
```

- `maxInFlight`: 同時に進める作業の上限(in-progress の open チケット + チケットに紐づく open PR の和集合)
- `pollSeconds`: ローカルループの待機間隔(待機中は Claude を起動しない = 枠を消費しない)
- `maxRuns`: ローカルループが `claude -p` を起動する回数の上限(暴走防止)
- 環境変数 `AUTOPILOT_MAX_IN_FLIGHT` / `AUTOPILOT_POLL_SECONDS` / `AUTOPILOT_MAX_RUNS` が優先

## 2. 判定 `.claude/scripts/autopilot-next.sh`

入力: GitHub REST(または `--issues FILE --prs FILE` のフィクスチャ。テスト用)
出力: 標準出力に JSON 1 個(`--summary` で人間向け 1〜数行)

- `open`: open の ticket Issue。`closed`: closed の ticket Issue 番号
- PR ↔ Issue: open PR のボディの `Closes|Fixes|Resolves #N`(大小無視)
- `inFlight`: open チケットのうち `in-progress` ラベル付き ∪ open PR に紐づくもの
- `stalled`: `in-progress` だが open PR が無い(中断 or 子セッションが実装中)
- `ready`: open・inFlight でない・`depends: #N` が全部 closed。P0>P1>P2>無印、同順位は番号順
  - depends 先が ticket 一覧に無い番号は `gh api issues/N` で個別に state を引く
- `attention`: inFlight の PR のうち、`conflict`(mergeable_state=dirty)/ `ci_failed`
  (head の check-runs に failure・timed_out・cancelled・action_required)/
  `changes_requested`(レビュアーごとの最新レビューに CHANGES_REQUESTED がある)
- `slots = maxInFlight - |inFlight|`
- `action`(上から最初に当たったもの):
  1. `fix` — attention がある(先頭の PR 番号を `target`)
  2. `start` — slots>0 かつ ready がある(`target` = ready の先頭、`targets` = slots 本ぶん)
  3. `wait` — inFlight がある(レビュー・CI 待ち)
  4. `blocked` — open チケットが残るが ready が無い(依存が閉じない)
  5. `done` — open チケットが無い
- `stalled` は action を変えない(クラウドでは子が実装中の正常状態)。ローカルループが別途扱う
- 終了コード: 0 = 判定成功 / 2 = 取得・解析の失敗(gh 不在・認証・JSON 不正)

## 3. `/next-ticket` の変更

- ステップ1: `gh issue list` を `autopilot-next.sh` に置き換える
- 「in-progress があれば止まる」を、**`slots == 0` のときだけ止まる**に変更。
  attention があれば先に `/fix-pr` を案内。stalled は `/resume-work` を案内(従来どおり)
- ステップ3 冒頭: **別チケットの PR ブランチ上にいるなら、`origin/[baseBranch]` から新ブランチを切る**
  (チケットのブランチを積み重ねない)。`claude/*` の再利用は「その PR のブランチではない」ときだけ

## 4. `/fix-pr [PR番号]`(新規)

既存 PR を緑・マージ可能にする。順序: コンフリクト(base を merge、rebase しない)→ CI 赤(根本原因を直す。
テスト無効化禁止)→ CHANGES_REQUESTED / 未解決スレッド(小さい指摘は直す、大きいものは返信で提案)。
直したら push、各スレッドに返信。マージはしない。

## 5. `/autopilot`(新規、司令塔用)

前提検査: モードが normal でなければ止まる。

- **クラウド**(`CLAUDE_CODE_REMOTE=true` かつ `mcp__claude-code-remote__create_session` が使える):
  1. `autopilot-next.sh` を回す
  2. `start` → targets ごとに `in-progress` を付け、`create_session` で子を起動
     (`/next-ticket N` + 子の作法: PR 作成後 `subscribe_pr_activity`、作成・マージ時に親へ `send_message`)
  3. `fix` → 該当 PR を持つ子が無ければ子を起動して `/fix-pr N`
  4. `wait` → `send_later` で 60 分後に再判定を予約し、ターンを終える(子の通知でも起きる)
  5. `blocked` / `done` → 報告して終了
- **ローカル**: 司令塔セッション内でループしない(コンテキストが膨らむ)。
  `bash .claude/scripts/autopilot-loop.sh` をターミナルで叩くよう案内して終わる

## 6. ローカルループ `.claude/scripts/autopilot-loop.sh`

1 周 = 判定 1 回 + 必要なら `claude -p` 1 回(新プロセス = `/clear` 済みのコンテキスト)。

- モード != normal → 停止
- stalled がある → `claude -p "/resume-work"`。同じ stalled が 2 周続いたら停止(人間に返す)
- `fix` → `claude -p "/fix-pr N"`。直後の判定で同じ PR が同じ理由で残ったら停止
- `start` → `claude -p "/next-ticket N"`。直後に N が stalled なら停止
- `wait` → `pollSeconds` 眠る(Claude を起動しない)
- `blocked` / `done` → 終了
- 作業ツリーが汚れていたら起動前に停止
- `claude` の引数は `AUTOPILOT_CLAUDE_ARGS`(既定 `--permission-mode acceptEdits`)
- `--dry-run` で判定と起動予定コマンドだけ表示

## 7. その他

- `settings.json` の allow に `Bash(bash .claude/scripts/autopilot-next.sh:*)` を追加
- `template-manifest.json` の merge に `.claude/autopilot.json`
- `status.md` の「次の一手」に attention → `/fix-pr` と、slots>0 なら並行着手可を反映
- `branch-and-tickets.md` に WIP 上限の 1 行
- README コマンド早見表、CHANGELOG([manual]: `.claude/autopilot.json` の取り込みと、クラウドは子セッション起動のツール許可)
