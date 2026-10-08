<!-- main-edit-ok --> (テンプレート自体の改修。委託禁止領域 .claude/scripts/ のため司令塔が直接書く)
# タスクリスト

- [x] `autopilot-next.sh` で fork / head 消失 PR を判定対象から外し `untrustedPrs` に出す
- [x] フィクスチャで確認(同一リポジトリ PR は inFlight、fork・head 消失 PR は untrustedPrs、repo 欄の無い旧フィクスチャは従来どおり)
- [x] `npm audit fix`(package-lock.json のみ。package.json 不変)
- [x] CHANGELOG を更新
- [x] 品質チェック(lint / typecheck / format / test / harness integrity)
