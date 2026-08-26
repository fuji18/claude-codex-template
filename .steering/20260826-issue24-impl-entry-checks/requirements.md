# 要求: Issue #24 impl 入口検査の穴を塞ぐ

## 背景

`delegate-codex.sh` の入口検査5(impl 専用)に、運用ルールと実装が一致していない箇所が 2 つある。どちらも同じ区画への小さな修正。

### (a) 5-1: target が `.steering/` 配下に限定されていない

検査は「`design.md` と `tasklist.md` を持つディレクトリ」しか見ないため、`.steering/` 外の任意ディレクトリでも通る。run record の `steering` フィールドと SessionStart の現在地判定(`latest-steering.sh`)は `.steering/` 前提なので、通ってしまうと状態管理が静かにずれる。

### (b) 5-5: 再入防止が「同一ステアリング」しか見ていない

`.claude/rules/lead/delegation-policy.md` は「並行数は 1 本まで(同一ワーキングツリーを共有するため)」と定めているが、検査は同じ steering への二重起動しか止めない。別 steering への並行 impl 委託は素通りし、ツリー競合(片方の lint が他方の編集を巻き込む等)が防がれない。

## 根拠

- `docs/template-dev/codex-harness-review-20260825.html` 指摘8・指摘9 / 推奨アクション P2
- Issue #24

## スコープ

1. 5-1 に `.steering/` prefix 検査を足す
2. 5-5 の判定軸を「steering 一致」から「mode=impl」へ変える(status=running かつプロセス実在なら steering を問わず止める)
3. 「並行 1 本」が機械化されたことを `delegation-policy.md` に反映する
4. 上記に伴い実態と食い違う `codex-delegation-plan.md` の記述(§12 の入口検査表 5-1 行・5-5 段落)を直す

## スコープ外

- 並行実行そのものの許可(worktree 分離等)。運用ルールは「1 本」のまま
- `AGENTS.md` の更新(委託禁止領域。今回の変更は委託先の規約に影響しない)
- 5-5 の「プロセス不在の running」警告の挙動変更(現状のまま残す)

## 受け入れ条件

- [ ] `.steering/` 外に `design.md` + `tasklist.md` を置いたディレクトリを target にすると `exit 2` で止まる
- [ ] 正規の `.steering/YYYYMMDD-*/` はこれまで通り通る(`./` 付き・末尾スラッシュ有無の両方)
- [ ] 別 steering への impl 委託が実行中のとき、2 本目が `exit 2` で止まる
- [ ] explore / review は入口検査5 を通らない(従来通り並行可)ことが変わっていない

## 振り返り(申し送り)

- **入口検査の「判定軸」は検査の目的から引き直す。** 5-5 は「二重起動を防ぐ」という表現から steering 一致で書かれていたが、運用ルールの本文は「同一ワーキングツリーを共有するため 1 本まで」であり、軸は steering ではなく mode だった。検査を足すときは**ルール文の理由節**を判定条件に写す
- **prefix 検査には `..` の除外が要る。** `.steering/../foo/` は文字列として `.steering/*/` に一致する。`case` の並び順が仕様の一部になるので、コメントで順序の理由を残した
- **同じ仕様が 3 箇所に散る構造が残っている。** 今回も `delegate-codex.sh` / `delegation-policy.md` / `codex-delegation-plan.md`(§3.2 の原則・§12 の表・§12 の段落)を手で揃えた。code-reviewer が拾った Major は §3.2 の取りこぼしで、design のスコープ側の見落としだった。**スクリプトの挙動を変えるチケットでは、着手時に `grep` で当該検査への言及を全ドキュメントから洗い出してから design を書く**とこの取りこぼしが減る
- **`.harness/codex-runs/` の record が増え続ける前提は未解決。** 5-5 の判定軸が全ステアリングに広がったことで、stale な running record の影響範囲も広がった(警告の出方・pid 再利用の誤検知)。ローテーション整備は Issue #29 の担当
