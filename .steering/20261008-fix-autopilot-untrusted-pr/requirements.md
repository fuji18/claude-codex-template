# 要求: autopilot が fork の PR を「チケットの PR」として扱わない

## 背景

`autopilot-next.sh` は open PR の本文に `Closes #N`(N は open のチケット)があれば、作成者・head リポジトリを問わず
チケットの PR とみなしていた。公開リポジトリでは第三者が fork から `Closes #N` 付きの PR を出し CI を落とすだけで
`action: fix` になり、`autopilot-loop.sh` が手元で `claude -p "/fix-pr N" --permission-mode acceptEdits` を起動する。
`/fix-pr` は検証で `npm ci` / `npm test` を回すため、外部コードがホスト上で実行される(+ プロンプトインジェクションの入口、
`maxInFlight` の枠埋めによる停止)。

## 要求

- head リポジトリが base と異なる PR(fork)、head リポジトリが消えた PR は判定対象から外す
- 外した PR は判定 JSON(`untrustedPrs`)と要約に出し、人間が気づけるようにする
- フィクスチャ(repo フィールドを持たない)の既存の挙動は変えない

## 付随

- `npm audit` の high 2 件(brace-expansion / source-map-js。いずれも devDependencies の DoS)を `npm audit fix` で解消する(lockfile のみ)

## 追加の要求(2 回目)

- 外部の作成者の `ticket` Issue・書き込み権限の無いレビュアーの変更要求で autopilot が動かない
- `/fix-pr` に信頼できない書き手のコメント本文を渡さない(散文の指示ではなく、読み取り経路で機械的に落とす)
- 委託先が書けばサンドボックス外で実行されるパス(`.devcontainer/` / `.vscode/` / `.npmrc`)を委託禁止領域にする
- セッション開始時に `npx -y` で取得・実行する MCP サーバのバージョンを固定する
