# tasklist: GitHub Projects を開発サイクルのダッシュボードにする

<!-- main-edit-ok -->
<!-- `.github/workflows/` `.claude/scripts/` `.claude/*.json` はいずれも委託禁止領域。
     司令塔が直接書く(Codex にも fork にも渡さない)。 -->

## 準備

- [x] Projects v2 の API 形(クエリ / 2 つのミューテーション / トークン要件)を docs で確認する
- [x] `autopilot-next.sh` の `Closes #N` 正規表現と fork 除外の境界を確認して合わせる

## 実装

- [x] `.claude/project-sync.json`(新規): ラベル名・Status / Priority の名前候補
- [x] `.claude/scripts/project-sync.sh`(新規): `sync-issue` / `sync-pr` / `backfill` / `--check` / `--resolve-status`
- [x] `.github/workflows/project-sync.yml`(新規): issues / pull_request イベント、未設定なら skip
- [x] `.claude/template-manifest.json`: workflow を `owned`、`project-sync.json` を `merge` に追加
- [x] `.claude/scripts/test-project-sync.sh`(新規)+ `ci.yml` に `Test project sync` ステップ
      (当初の計画に無かった。CI が `test-route.sh` / `test-sync-template.sh` を呼ぶ構造に合わせた)

## 文書

- [x] `README.md`: 自動化層の一覧に 1 行、スクリプト一覧に 1 行、2.5 節として導入手順
- [x] `README.html`: 同じ 3 箇所(ブランチ戦略の節番号を 2.5 → 2.6 に繰り下げ)
- [x] `docs/template-dev/CHANGELOG.md`: `[manual]` で取り込み手順(PAT・variable・board の用意)
- [x] `.claude/docs/project-sync-guide.html`(新規): 人間向けの手順書。`autopilot-guide.html` の
      CSS・テーマ切替・コピーボタンを流用し、本文だけ差し替えた(体裁を 1 つに保つため)
- [x] 同手順書にインライン SVG の図を 4 点入れた(サイクルと列の対応 / Status の判定フロー /
      情報の流れ / fork を止める 2 段の境界)。ブラウザで描画確認済み
- [x] `.claude/docs/project-sync-setup.html`(新規): 導入作業の**操作手順書**(画面とボタン、図 2 点)。
      手順書 2 枚は役割が違う —— `project-sync-guide.html` = しくみ / `project-sync-setup.html` = 操作
- [x] **進行中のプロジェクトへの後入れ**を 3 箇所に書いた(README 2.5 節 / README.html / CHANGELOG)+
      手順書の FAQ 先頭に `details open` で 1 項目。あわせて `backfill` の 100 件打ち切りを直した
      (`gh api --paginate`。当初の計画に無かった —— この問いで初めて露出した)

## 検証

- [x] `--resolve-status` のフィクスチャで Status 4 分岐 + fork 除外を確認する(20 件 all passed)
- [x] `bash .claude/scripts/check-shell.sh` が通る(36 ファイル / shellcheck 0.9.0 / 指摘ゼロ)
- [x] `bash .claude/scripts/check-manifest-coverage.sh` が通る
- [x] `/check`(lint・型・テスト・フォーマット)が通る
      (ホストは Node v22 / jq・shellcheck 無しのため、shell 検査と上の 2 件は Docker 側の結果を採用)
- [x] ~~実ボードでの動作確認~~ (理由: PAT の発行と Project の作成が要るため人間の担当。手順は CHANGELOG と README 2.5 節に記載)

## 申し送り

- **ホストに jq も shellcheck も無い。** 手元の `sc-local:1` イメージ(shellcheck 0.9.0 + jq 1.6)で
  `docker run --rm -e LC_ALL=C.UTF-8 -v "C:/Project/claude-codex-template:/w" -w /w sc-local:1 ...` と回せる。
  `LC_ALL=C.UTF-8` を付けないと日本語の指摘が `commitBuffer: invalid argument` で化ける
- **`done` を引数やリストに裸で書くと shellcheck が SC1010 を出す**(`for k in ... done` / `status_is ... done`)。
  クォートする。Status キーに `done` を使っている以上、今後も踏む
- **`PROJECT_URL` の判定は gh に触る前に置いた。** 後ろに置くと、リモートが無い一時ディレクトリでは
  「未設定なら何もしない」経路に入る前に repo 解決で落ちてテストできない
- **`addProjectV2ItemById` は冪等**(既にあれば既存の item ID が返る)なので、取りこぼし対策の
  再同期をそのまま何度でも流せる。この性質に Status 決定の冪等性を乗せてある
- **手順書 3 枚の体裁は `autopilot-guide.html` が正。** `project-sync-guide.html` はその head(テーマ変数・
  CSS)と末尾の script(コピーボタン・テーマ切替)を機械的に流用し、`project-sync-setup.html` はさらに
  `project-sync-guide.html` から同じやり方で流用した。**1 枚の CSS を直したら残り 2 枚にも写す**
  (生成スクリプトは残していない —— 以後は手で直す前提)。図の CSS は `figure.fig` / `.fig .nbox` /
  `.fig .ln` 系で、`autopilot-guide.html` 側には無い。localStorage のキーは 3 枚とも別
  (`autopilot-guide-theme` / `project-sync-guide-theme` / `project-sync-setup-theme`)
- **SVG に色を直書きしない。** `fill="#..."` を書くとダークテーマで読めなくなる。`.fig` 配下の
  クラス(`nbox` / `nbox.ok` / `ln.no` など)経由で既存のテーマ変数に乗せる。`done` を裸で書けない話と同じく、
  これも次に図を足すときに踏む
- **ユーザーが将来「board を判定の入力にしたい」と言った場合**、`autopilot-next.sh` の REST 限定の前提
  (Claude Code on the web で GraphQL が 403)を先に片付ける必要がある。今回は意図的に避けた
