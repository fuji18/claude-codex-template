# requirements: GitHub Projects を開発サイクルのダッシュボードにする

## 背景

チケットは GitHub Issues(`ticket` + 優先度ラベル)で管理し、自動進行は
`autopilot-next.sh` の判定 + `autopilot-board.sh` の全体管理 Issue で回っている。
ただし**人間が「いま全体がどこにいるか」を見る面が Issue の表の 1 枚しかない**。
README の開発サイクル(着手 → 実装 → レビュー → マージ)を GitHub Projects の
ボードで追えるようにしたい。

## 決めたこと(ユーザー判断)

1. **Project の役割は「表示のみ」**。判定の入力にはしない
2. **同期の実行者は GitHub Actions**(ローカルスクリプトからは呼ばない)

この 2 つが前提にあるのは次の理由:

- **Projects v2 は GraphQL 専用。** `autopilot-next.sh` は「Claude Code on the web で
  GraphQL が 403 になる」ため REST 限定で書かれている(同ファイル冒頭)。Project を
  判定経路に入れるとこの前提が壊れる
- Actions 側に置けば、**ローカル autopilot でも手作業でも Codex 直叩きでも**
  誰が動かしてもボードが揃う

## 要求

1. `ticket` ラベルの Issue を Project に自動追加し、**Status を開発サイクルに沿って動かす**
   (Todo → In Progress → In Review → Done)
2. 優先度ラベル(`P0` / `P1` / `P2`)を Project の Priority フィールドに反映する
3. **判定の正はラベルと PR のまま。** Project は状態を二重に持たない
   (`autopilot-board.sh` と同じ方針 —— 表示専用)
4. **Status の決め方は冪等。** イベント種別ではなく **Issue の現在の状態**
   (open/closed・ラベル・紐づく open PR の有無)から毎回決め直す。取りこぼしや
   順序の入れ替わりで板がずれない
5. **未設定なら黙ってスキップする**(テンプレートから作った直後のリポジトリで
   赤くならない)。設定済みで失敗したときは**ログに出して落とす**
   (板が黙って古くなる方が悪い。`ci.yml` の shellcheck ステップと同じ判断)
6. ボードのフィールド名・オプション名は**プロジェクトごとに違う**ので設定で持つ
   (日本語のボードでも動く)
7. **信頼の境界を既存の判定と揃える**: fork の PR は対象外にする
   (`autopilot-next.sh` の untrustedPrs と同じ理由)

## 非対象

- Project の Status を autopilot の**入力**にすること(「Ready 列に置いたものだけ着手」等)
- Actions でサイクル自体を無人進行させること(Claude Code Action の schedule 実行)
- Project 自体の作成(ボードとフィールドは人間が GitHub の UI で作る)
- `autopilot-next.sh` / `autopilot-loop.sh` / `autopilot-board.sh` への変更

## 受け入れ条件

- [ ] `PROJECT_URL`(variable)と `PROJECT_SYNC_TOKEN`(secret)が未設定のリポジトリで
      ワークフローが skip され、赤くならない
- [ ] `--check` で設定・権限・Status / Priority 名の照合結果が人間に読める形で出る
- [ ] フィクスチャで Status 決定ロジックを検証できる(GitHub に触らず)
- [ ] `bash .claude/scripts/check-shell.sh` が通る
- [ ] `check-manifest-coverage.sh` が通る(新規ファイルが manifest に載っている)
- [ ] `docs/template-dev/CHANGELOG.md` に `[manual]` で取り込み手順が書かれている
