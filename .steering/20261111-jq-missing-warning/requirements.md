# requirements: jq が無い環境でガードが黙って消えるのを止める

## 背景

devcontainer の外(Windows ホストのデスクトップアプリ)でセッションを開くと、ホストに `jq` が無い。
ハーネスのガードは入力 JSON とポリシーファイルの読み取りを `jq` に頼っており、無ければ
**何も言わずに `exit 0`** する。実測(2026-11-11、ホスト):

```
echo '{"tool_input":{"command":"git push --force origin main"}}' | bash .claude/scripts/block-dangerous-cmds.sh
→ exit 0(ブロックされない)
```

同じ理由で次の層がすべて素通しになる:

| 層 | スクリプト |
| --- | --- |
| 危険コマンドの検査 | `block-dangerous-cmds.sh` |
| ブランチ戦略の検査 | `check-branch-policy.sh` |
| 司令塔の実装禁止 | `check-implementation-phase.sh` |
| 保護ブランチへの直接コミット(git hook) | `check-protected-branch.sh` |
| push 先の検査(git hook) | `check-push-policy.sh` |

SessionStart hook は実行ビットや `core.hooksPath` の欠落は警告するが、`jq` の欠落は見ていない。
「層が無いことより、無くなったのに気づけない方が悪い」という既存の原則に反している。

## 要求

1. `jq` が無いセッションでは、SessionStart が**どの層が効いていないか**と**入れ方**を注入する
2. 注入には、`jq` が入るまで司令塔が自分で守るべきこと(hook が代わりに止めていた操作)を含める
3. git hook 層(`check-protected-branch.sh` / `check-push-policy.sh`)は、`jq` が無くて検査を
   飛ばしたことを **stderr に 1 行出す**(Claude を起動しない作業でも気づけるように)
4. **フェイルオープン設計は変えない。** `jq` が無いだけで commit / push / 全ツール呼び出しを止めない

## 非対象

- `jq` 無しでも判定が動くようにする代替実装(node などでの JSON 読み取り)。判定の実体が
  2 系統になり、「経路によらず同じ結果」という要件を崩す
- フェイルクローズへの切り替え(設計の反転。必要ならユーザー判断で別作業にする)
- ホストの Node バージョン不一致(v22 / `engines: >=24`)と devcontainer 設定の見直し
