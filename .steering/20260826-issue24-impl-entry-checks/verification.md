# 検証: Issue #24 impl 入口検査の穴を塞ぐ

## 4.1 構文

```
bash -n .claude/scripts/delegate-codex.sh
```

結果: OK(エラーなし)。

## 4.2 5-1 の受け入れ条件

design §4.2 の等価スクリプト(`case` ブロックを 1 文字違わずコピー)で 7 ケースを実行。

```
.steering/20260826-x -> OK (.steering/20260826-x/)
.steering/20260826-x/ -> OK (.steering/20260826-x/)
./.steering/20260826-x/ -> OK (.steering/20260826-x/)
/tmp/foo/ -> NG(prefix)
docs/foo/ -> NG(prefix)
.steering/ -> NG(prefix)
.steering/../tmp/foo/ -> NG(..)
```

期待どおり(最初の3件がOK、残り4件がNG)。

実際の `delegate-codex.sh` でも1ケース実測した。この環境では入口検査4(codex認証)ではなく
入口検査1(機密ファイル検出: `./.claude/settings.local.json`)で先に止まるため、
`CODEX_DELEGATE_ACK_SECRETS=1` を付けて 5-1 まで到達させた:

```
$ CODEX_DELEGATE_ACK_SECRETS=1 bash .claude/scripts/delegate-codex.sh impl /tmp/.../scratchpad/outside
...
delegate-codex: impl の target は .steering/ 配下のディレクトリである必要があります: /tmp/.../scratchpad/outside/
exit=2
```

期待どおり `.steering/` 配下でない target が 5-1 で `exit 2` になることを実機で確認した。

## 4.3 5-5 の受け入れ条件

design §2.2 のループを1文字違わず抜き出した等価スクリプト(`rec_field` を含む)で、
`.harness/codex-runs/` を汚さないスタブディレクトリを使い、jq 経路 / sed フォールバック経路
(`PATH` から `jq` を除外)の両方で 4 ケースを実行した。pid は `kill -0` が生存判定できるよう、
各テスト内でバックグラウンドの `sleep 60 &` を起動しその pid を使用(テスト終了後に kill)。

| ケース | jq 経路 | sed フォールバック経路 |
| --- | --- | --- |
| 1. 別ステアリングへの並行(mode=impl, steering=other-dir) | 「別のステアリングへの委託が実行中です」+ exit 2 | 同左 |
| 2. 同一ステアリング(mode=impl, steering=STEERING と同値) | 「同じステアリングへの委託が実行中です」+ exit 2 | 同左 |
| 3. mode=explore の running record | 出力なし + exit 0 | 同左 |
| 4. jq 不在経路の確認 | — | 上記1・2・3 すべて jq 経路と同一結果(sed フォールバックが `mode` / `steering` / `pid` を正しく拾えることを確認) |

すべて期待どおり。スタブ record は各テスト後に削除し、`git status` で
`.harness/codex-runs/` に汚れがないことを確認した(同ディレクトリは `.gitignore` の
対象でもある)。

## 4.4 全体

`npm run typecheck` / `npm run format:check` / `npm run lint` / `npm test` をリポジトリ全体で実行。
`test-runner` による検収時の再実行を含め、すべてパス(test は 1 passed)。
`.claude/scripts/` 配下の全 `.sh` の `bash -n` も併せてパス。

## 検収指摘の反映

`code-reviewer` の指摘(0 Critical / 1 Major / 3 Minor)への対応:

| 指摘 | 対応 |
| --- | --- |
| [Major] `codex-delegation-plan.md` §3.2 の原則行が旧仕様(steering 一致で再入防止)のまま | 判定軸が mode=impl であることを反映して差し替えた |
| [Minor] `.steering/*/` がネストしたパス(`.steering/foo/bar/`)も通す | **仕様のまま。** 直後の `design.md` / `tasklist.md` 存在チェックが実質的な絞りとして働き、実害がない。単層に限定すると将来のサブディレクトリ運用を先に禁じることになる |
| [Minor] stale な running record の pid を OS が再利用していると誤検知しうる | 挙動は変えず、5-5 のコメントに「誤検知の条件」として明記した(既存の pid 生存判定に内在する性質。露出が全ステアリングへ広がったため記録する) |
| [Minor] 検証記録は問題なし(良い点の確認) | 対応不要 |
