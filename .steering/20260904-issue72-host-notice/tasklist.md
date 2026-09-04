# タスクリスト: #72 ホスト警告の分離(hostNotice)

設計は `design.md`。節番号はそこに対応する。

## 実装

- [x] `lib-record.sh`: `oneline()` を足し、`untrusted_oneline()` をその呼び出しにする(§2-1(a))
- [x] `lib-record.sh`: `HOST_NOTE` と `host_notice_block()` を `untrusted_block` の後ろに足す(§2-1(b))
- [x] `delegate-codex.sh`: `HOST_NOTICE` グローバルと `add_host_notice()` を `RUN_DIR` 直後に足す(§2-2)
- [x] `delegate-codex.sh`: `write_record` に `"hostNotice"` 行を足し、引数コメントを更新(§2-3)
- [x] `delegate-codex.sh`: 禁止領域違反の `SUMMARY` 連結を `add_host_notice` に置換(§2-4(1))
- [x] `delegate-codex.sh`: `package.json` 差分の連結を置換し、1448 行付近のコメントを差し替え(§2-4(2))
- [x] `delegate-codex.sh`: tasklist 未更新の連結を置換(§2-4(3))
- [x] `delegate-codex.sh`: `emit()` に `host_notice_block "$HOST_NOTICE"` を足す(§2-5)
- [x] `codex-run.sh`: `cmd_pending` に `_notice` を足し、サマリー行の前に出力(§2-6(a)(b)(c))
- [x] `codex-run.sh`: `cmd_show` の注記を差し替え(§2-6(d))

## ドキュメント

- [x] `docs/template-dev/codex-delegation-plan.md`: スキーマ例に `hostNotice` を足し、説明を 1 文追記(§2-7)
- [x] `docs/template-dev/CHANGELOG.md`: `## 2026-09-04` の先頭に `[auto]` で追記(§2-7)

## 検証(§5。すべて実測して結果を報告する)

- [x] (1) `bash -n` 3 ファイル + shellcheck(あれば)
- [x] (2) `host_notice_block` の単体確認(複数警告 / 空入力 / 制御文字除去)
- [x] (3) 旧形式 record を `pending` / `show` が従来どおり扱う(受け入れ条件 3)
- [x] (4) 新形式 record で `pending` がホスト検査行を summary 行の前に出す(受け入れ条件 2)
- [x] (5) `emit` → `untrusted_block` の順序確認。ホスト警告がブロックの外・前に出る(受け入れ条件 1)
- [x] (6) `git diff --stat` の確認 / `git diff -- package.json` が空
- [x] (7) `npm run lint` / `npm run typecheck` / `npm test`

## 検収の指摘(2026-09-04 / code-reviewer 1 巡目: Critical 0 / Major 0 / Minor 2)

- [x] Minor 1: `host_notice_block` の「偽造元が無い」という前提コメントを訂正する。
      禁止領域違反の警告本文に入る `$VIOL_LINE` は**委託先が作ったファイル名に由来する**ため、
      本文の一部は委託先が制御できる。行単位の終端マーカーは偽造できない(1 行内の部分文字列に留まる)が、
      コメントの言い切りが不正確。`lib-record.sh` の `host_notice_block` 直上コメントと
      `design.md` §1-3 の両方を直す
- [x] Minor 2: `cmd_pending` の 1 行化で複数警告の区切り(空行 1 つ)が二重スペースに潰れて
      境界が読めない。1 行化の前に空行を明示セパレータへ置き換える
- [x] 再検証: §5 (2)(4) を回し直す(複数警告の表示と制御文字除去が壊れていないこと)
