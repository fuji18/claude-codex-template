---
description: チケット消化を自動進行する。レビュー待ちの PR は待ち、その間に依存が解決済みの独立チケットを並行で進める。全体管理 Issue で状態表示・一時停止、econ モードにも対応
---

# チケットの自動進行

`/next-ticket` → `/clear` を人手で繰り返す代わりに使う司令塔コマンドです。人間向けの手順書は `.claude/docs/autopilot-guide.html`(ブラウザで開く。使い方を聞かれたらこのパスを案内する)。**次に何をするかは毎回 `autopilot-next.sh` が決める**(選定規則を散文で持たない)。マージ・approve は人間が行い、ここでは**しない**。

**引数:** なし

---

## ステップ0: 前提検査

1. `bash .claude/scripts/harness-mode.sh` を確認する。`degraded`(モード C)なら**止まる**(Claude が動かない前提のモード)。`econ`(モード B)は**ローカルのみ**可(ステップ2。計画と PR だけ Claude、実装はシェルから Codex)。クラウドの子セッション起動は枠を使うので econ では行わない
2. `bash .claude/scripts/autopilot-next.sh --summary` で現在地を出し、1〜3 行でユーザーに示す。終了コード 2 なら原因(gh の認証等)を報告して止まる
3. 実行環境で分岐する:
   - **ローカル**(既定)→ ステップ2
   - **クラウド**(`CLAUDE_CODE_REMOTE=true` かつ `mcp__claude-code-remote__create_session` が使える、かつ normal)→ ステップ1

## ステップ1: クラウド(司令塔 = 振り分け役、チケットは子セッション)

この司令塔セッションは**実装も計画もしない**。チケット 1 枚につき子セッションを 1 つ起動し(コンテナ・ブランチ・コンテキストが別 = `/clear` 不要)、自分は判定と起動だけを繰り返す。

1. 自分のセッション ID を `mcp__claude-code-remote__get_session`(`session_id` 省略)で取得しておく(子からの通知先)
2. `bash .claude/scripts/autopilot-next.sh` の `action` で分岐する(判定のたびに `bash .claude/scripts/autopilot-next.sh | bash .claude/scripts/autopilot-board.sh sync --status "[いまの動き]"` で全体管理 Issue を更新し、`autopilot-board.sh paused` が exit 0 なら起動をせず 3 の予約だけして終える):

| action | 動き |
| --- | --- |
| `fix` | 対象 PR を担当している子セッションがこのセッションで起動済みなら、`send_message` で `/fix-pr [PR番号]` を送る。いなければ子を起動して `/fix-pr [PR番号]` を渡す(下の子プロンプトの「PR 作成後」以降を付ける) |
| `start` | `targets` の各 Issue について、**先に** `in-progress` ラベルを付ける(次の判定で空き枠に数えないため。`mcp__github__issue_write`)→ 子セッションを起動する → Issue に `autopilot: 子セッション [子のセッションID] が着手` とコメントする(コンテキストが圧縮されても、どの stalled が自分の子かを Issue から辿れるようにする) |
| `wait` | 3 へ |
| `blocked` | 依存待ちの一覧を報告して終了する(依存が閉じないのは計画の問題。人間の判断が要る) |
| `done` | 全チケット完了を報告し、`/sync-docs` と次フェーズ(P1)の計画を提案して終了する |

   `stalled`(PR 未作成の in-progress)は、Issue の最新の `autopilot: 子セッション …` コメントの子が生きていれば(`mcp__claude-code-remote__get_session` で `status_bucket` が `working` / `blocked`)正常。コメントが無い・子が `failed` / `completed` なら中断した作業なので、子を起動して `/next-ticket [番号]`(再開経路に入る)を渡す。

3. `fix` / `start` を処理したら判定をもう一度回し、`wait` になるまで繰り返す(**同じ PR への `fix` は 1 ターンに 1 回まで**。送った後も残るなら子の報告を待つ)。`wait` になったら `mcp__claude-code-remote__send_later` で **60 分後**の再判定を予約し、**ターンを終える**。子からの通知(PR 作成・マージ・行き詰まり)でも起きるので、待機中に `sleep` やポーリングをしない
   - 予約メッセージは `/autopilot (wait [回数])` とし、回数は**判定結果が前回の予約時から変わらなかった連続回数**にする(変われば 1 に戻す)。**6 回(約 6 時間)続いたら再予約せず**、待っている PR の一覧を報告して終了する(次の子の通知かユーザーの `/autopilot` で再開する)

**子セッションの起動**(`mcp__claude-code-remote__create_session`、`source_url` はこのリポジトリ、`title` は `ticket #[番号] [タイトル]`)。`prompt` は次の形にする:

```
/next-ticket [番号]

autopilot の子セッションとして動く。親セッション: [親のセッションID]
- 他のチケットに着手しない。/next-ticket の WIP 判定は親が済ませている
- PR を作ったら mcp__claude-code-remote__subscribe_pr_activity でその PR を購読し、
  親に send_message で「PR #[PR番号] 作成(Issue #[番号])」と送る
- PR イベント(CI 失敗・レビュー指摘・コンフリクト)は /fix-pr [PR番号] の手順で対応する。マージはしない
- PR がマージ / クローズされたら親に send_message で「PR #[PR番号] マージ済み」と送って終了する
- 設計判断が要る・同じ失敗が 2 回続いた等で進めないときは、親に send_message で理由を送って止まる
```

**子からのメッセージを受けたら**、内容をユーザーに 1 行で伝えてからステップ1-2 の判定に戻る(マージで枠が空けば次のチケットが起動される)。

## ステップ2: ローカル(ターミナルのループに任せる)

このセッションの中でチケットを回し続けない。1 セッションで複数チケットを回すと、前のチケットの調査・実装ログが毎ターン再送され続ける。

ユーザーに次をターミナルで実行するよう案内して終わる(**起動は 1 回だけ。あとは GitHub の全体管理 Issue を見ればよい**):

```bash
bash .claude/scripts/autopilot-loop.sh --dry-run      # まず判定と起動予定だけ確認
bash .claude/scripts/autopilot-loop.sh --background   # 裏で起動(ターミナルを閉じてもよい)
bash .claude/scripts/autopilot-loop.sh --log          # 進行を見る / --stop で止める
```

- 1 周ごとに `claude -p` を新しいプロセスで起動する(= チケットごとの `/clear` 相当)
- レビュー・CI 待ちの間はシェルが `pollSeconds` 眠るだけで、Claude の枠を消費しない
- 作業ツリーは 1 つなので**実装は直列**。ただし WIP 上限まで PR を開いたままにできるので、PR 1 本のレビュー待ちの間に次のチケットを進められる
- **全体管理 Issue**(`autopilot` ラベル、初回の判定で自動作成): 全チケットの状態(🔧 要対応 / 👀 レビュー待ち / 🚧 実装中 / ▶️ 着手可能 / ⏳ 依存待ち / 🙋 手動 / ✅ 完了)を判定のたびに書き出す。本文の「一時停止」にチェックを入れると次の周から止まり、外すと再開する(スマホの GitHub アプリからでも操作できる)。人手が要る停止は理由がコメントされる。**状態の正は各チケットのラベルと PR のまま**で、この Issue は表示と操作だけ(手で書き換えた内容は次の更新で上書きされる)
- 停止の通知: 全体管理 Issue へのコメントに加え、`AUTOPILOT_NOTIFY_CMD`(例: `notify-send autopilot`、ntfy / Slack への `curl` を包んだスクリプト)があれば理由を引数に実行する。**自分の gh アカウントで投稿したコメントは自分には通知されない**ので、手元で気づきたいなら `AUTOPILOT_NOTIFY_CMD` を設定する
- **econ(モード B)**: 1 チケットを 計画(`claude -p "/next-ticket N --plan-only"`)→ 実装(ループがシェルから `delegate-codex.sh impl` を直接実行。Claude を起動しない)→ draft PR(`claude -p "/ship-ticket N"`)の 3 段で進める。検収はせず CI に委ねる。`package.json` の `scripts` / `lint-staged` / `prepare` が変わっていたら止まって人間に返す。Codex が使えない(exit 3)ときは Sonnet fork に自動で落とさず止まる。draft はマージされず枠を埋め続けるので、上限は `econ.maxInFlight`(既定 4)を使う
- 自動進行に向かないチケット(委託禁止領域・新規依存)は `autopilot:manual` ラベルが付いて候補から外れる。人間が通常モードで `/next-ticket [番号]` を回す
- `claude -p` は対話できないため、許可が要るコマンドで止まらないよう `AUTOPILOT_CLAUDE_ARGS`(既定 `--permission-mode acceptEdits`)と `.claude/settings.json` の allow を確認しておく

## 設定(`.claude/autopilot.json`)

| キー | 既定 | 意味 |
| --- | --- | --- |
| `maxInFlight` | 2 | 同時に進める作業の上限(in-progress のチケット + チケットに紐づく open PR)。レビュー待ちの PR もここに数える |
| `pollSeconds` | 300 | ローカルループの再判定間隔 |
| `maxRuns` | 20 | ローカルループが `claude -p` を起動する回数の上限 |
| `board` | true | 全体管理 Issue を作成・更新するか |
| `econ.maxInFlight` | 4 | econ(モード B)での同時進行の上限(draft PR を積む) |

**チケットの完了は Issue の closed で判定する。** PR の `Closes #N` で Issue が自動クローズされるのは**デフォルトブランチへのマージ時だけ**なので、`baseBranch` が `develop` のプロジェクトでは、マージ後に Issue を手で閉じないと依存が解けず `blocked` / `stalled` が残る。

**独立性の判定は `depends:` 行の `#N` だけを見る。** 依存先が未マージ(PR がレビュー待ち)のチケットは着手しない(ブランチを積み重ねない)。依存を書いていないのに同じファイルを触るチケット同士はコンフリクトしうる —— 起きたら `/fix-pr` が base を取り込んで解消する。頻発するなら `/setup-tickets` で `depends:` を足す。
