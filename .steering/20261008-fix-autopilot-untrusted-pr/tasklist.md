<!-- main-edit-ok --> (テンプレート自体の改修。委託禁止領域 .claude/scripts/ のため司令塔が直接書く)
# タスクリスト

- [x] `autopilot-next.sh` で fork / head 消失 PR を判定対象から外し `untrustedPrs` に出す
- [x] フィクスチャで確認(同一リポジトリ PR は inFlight、fork・head 消失 PR は untrustedPrs、repo 欄の無い旧フィクスチャは従来どおり)
- [x] `npm audit fix`(package-lock.json のみ。package.json 不変)
- [x] CHANGELOG を更新
- [x] 品質チェック(lint / typecheck / format / test / harness integrity)

## 追加(2 回目)

- [x] `autopilot-next.sh`: 書き込み権限の無い作成者のチケットを対象外にし `untrustedTickets` に出す
- [x] `autopilot-next.sh`: 書き込み権限の無いレビュアーの CHANGES_REQUESTED を数えない
- [x] `pr-feedback.sh` を新規作成(信頼できる書き手の本文だけを返す。取得失敗は exit 2)し、`/fix-pr`・settings.json の allow・preflight・autopilot.json(`trustedBots`)に配線
- [x] 委託禁止領域に `.devcontainer/` / `.vscode/` / `.npmrc` を追加(`lib-forbidden.sh` / `delegation-policy.md` / 計画書 §9.1)
- [x] `.mcp.json` の context7 を 4.1.1 に固定(起動を確認)、`mcp-introduction-guide.md` に固定の理由を追記
- [x] CHANGELOG を更新
- [x] 品質チェック

## 申し送り(受容・据え置き)

- devcontainer の `seccomp=unconfined` は Codex sandbox(bubblewrap)のための受容済みリスク(#60)
- `containerEnv` の `LOCAL_GH_TOKEN` はコンテナ内の全プロセス(`npm test` 等)から読める。Codex には env 許可リストで渡らない
- Actions はタグ固定(SHA 固定ではない)。dependabot(github-actions)が更新を担う
