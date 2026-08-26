# 要求: explore / review の run record を auto-accept する(Issue #22)

## 背景

`delegate-codex.sh` の `write_record` は全モードで `"accepted": false` を書く。しかし
「検収して accept する」という概念は **impl にしかない**(検収対象の成果物 = 作業ツリーの
差分が存在するのは impl だけ)。

explore / review の成果はサマリーの標準出力として司令塔にその場で渡り切っており、
あとから検収する対象が残らない。にもかかわらず record が `accepted: false` のまま残るため、
`codex-run.sh pending` が SessionStart のたびにそれを注入し続ける。7 日経っても
「古い記録」に降格するだけで消えない。

結果として、**コンテキストを削るための read-only 委託が、毎セッションの固定コンテキストを
単調増加させる**。

## スコープ

1. read-only モード(`explore` / `review`)が `completed` で終わったときの record を
   `accepted: true` で書く
2. `write_record` に accepted の値を引数で渡せるようにする(現状はリテラル `false` 固定)
3. 異常終了(`failed` / `rate-limited` / `unavailable` / `blocked` / `running`)は
   モードによらず `accepted: false` のままにする

## スコープ外

- 未検収レコードの自動削除・件数上限(発生源を止めるだけ)
- `codex-run.sh` 側のロジック変更(`pending` / `list` は `accepted != true` を見るだけで
  正しく動く)
- record の JSON フィールドの並び順の変更

## 受け入れ条件

- [ ] explore / review の正常完了後、`codex-run.sh pending` に当該レコードが出ない
- [ ] `codex-run.sh list --all` には従来どおり出る(記録は消さない)
- [ ] impl の completed は従来どおり `accepted: false` で pending に出る
- [ ] explore / review が failed / unavailable で終わった場合は pending に出る
- [ ] `accepted` は JSON の最終フィールドのまま(`codex-run.sh` の `write_field` の
      sed 経路が末尾フィールド前提でカンマ無しを書くため)

## 根拠

- Issue #22
- `docs/template-dev/codex-harness-review-20260825.html` 指摘7 / 推奨アクション P1
