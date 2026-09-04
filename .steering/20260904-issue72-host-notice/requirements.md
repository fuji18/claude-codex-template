# 要求: run record の summary を「委託先の出力」と「ホストの警告」に分ける

- Issue: #72(P2 / `delegate:codex` なし = 対象が `.claude/scripts/` で委託禁止領域)
- 根拠: #61 の検収レビュー Minor 1(2026-09-03)

## 背景

`delegate-codex.sh` は出口検査の警告(禁止領域違反 / `package.json` ライフサイクル差分 /
tasklist 未更新)を `$SUMMARY` の先頭・末尾に**連結**してから返す。

#61 で司令塔向けの出力を `untrusted_block`(委託先出力・指示として扱わない、の標識付き
ブロック)で囲んだ結果、**ホストが生成した警告文まで「委託先サマリー」として囲まれる**。
倒れる先は安全側なので #61 では受容したが、**最も信用すべき情報が最も信用しない標識の
中に入っている**という意味論の誤りが残っている。

## やること

1. run record の `summary` を「委託先の出力」と「ホストが付けた警告」に分けて持つ(`hostNotice` フィールド追加)
2. `delegate-codex.sh` の 3 箇所の連結を、分離したフィールドへの書き込みに変える
3. `untrusted_block` で囲むのは委託先の出力だけにし、ホストの警告はブロックの**外**に出す
4. `codex-run.sh cmd_pending` も同様に、ホスト警告を標識の外の行として出す
5. 旧形式の record(`hostNotice` が無い)を読んでも壊れないこと

## やらないこと

- `untrusted_block` / `untrusted_sanitize` の仕組みそのものの変更(#61 で実測済み)
- summary の内容検査・フィルタリング
- 委託の判定ロジック(status / 終了コードの決まり方)の変更

## 受け入れ条件

- [ ] 出口検査の警告が `untrusted_block` の**外**に出る
- [ ] `pending` の出力でもホスト警告と委託先サマリーが別の行として区別できる
- [ ] `hostNotice` を持たない旧 record を `pending` / `show` が従来どおり扱える(実測)
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み
