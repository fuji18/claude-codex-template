# タスクリスト: 委託経路で jq を必須化する(#63)

設計は `design.md`。**節番号を必ず参照してから着手すること。**

## 1. `lib-record.sh`(§2)

- [x] 1-1. `require_jq` を追加する(`rec_field` の直前 / §2-1 のコード・コメントをそのまま使う)
- [x] 1-2. `rec_field` の sed 分岐を削除し、jq 一本にする(§2-2)
- [x] 1-3. sed 経路を説明していた 2 段落のコメントを削除し、§2-2 のコメントに差し替える(冒頭の source 専用 / 命名規約 / 委託禁止領域 / 自己コピーの各コメントは**残す**)
- [x] 1-4. `bash -n .claude/scripts/lib-record.sh` が通る

## 2. `delegate-codex.sh`(§3)

- [x] 2-1. 入口検査0-2 を `--print-forbidden` ブロックの**直後**・入口検査1 の**直前**に追加する(§3-1)。**入口検査0 の配列に jq を足さない**
- [x] 2-2. `json_str` の `command -v jq` 分岐を外す(空出力フォールバックは残す / §3-2)
- [x] 2-3. `lifecycle_snapshot` の `command -v jq` 分岐を外し、「必須化は Issue #63 の担当」というコメントを事実に合わせて書き換える(§3-3)
- [x] 2-4. `bash -n .claude/scripts/delegate-codex.sh` が通る

## 3. `codex-run.sh`(§4)

- [x] 3-1. ヘッダーの終了コード表と層の宣言を更新する(§4-1)
- [x] 3-2. `write_field` から sed 経路・独自 JSON 検査・第 4 引数を削除する(§4-2)
- [x] 3-3. `cmd_accept` の呼び出しを 3 引数に直し、sed 経路の説明コメントを削除する(§4-3)
- [x] 3-4. `cmd_list` / `cmd_accept` / `cmd_set_status` / `cmd_prune` の先頭に `require_jq "codex-run" 2` を入れる(§4-4)
- [x] 3-5. `cmd_pending` の先頭に `command -v jq >/dev/null 2>&1 || exit 0` を入れる(**`require_jq` を呼ばない** / §4-4)
- [x] 3-6. `cmd_show` には**何も入れない**ことを確認する(§4-4)
- [x] 3-7. `bash -n .claude/scripts/codex-run.sh` が通る

## 4. 検証(§6)

- [x] 4-1. §6-1 の手順で jq 抜き PATH(`$NOJQ`)を作り、`PATH="$NOJQ" command -v jq` が何も返さないことを確認する
- [x] 4-2. V1〜V6(jq 不在時の挙動)を実測する
- [x] 4-3. V7〜V9(jq あり・既存 record と使い捨て record)を実測する。**使い捨て record は検証後に必ず削除する**
- [x] 4-4. V10〜V12(自己コピー経路 / 構文チェック / shellcheck)を実測する
- [x] 4-5. `bash .claude/scripts/check-guard-integrity.sh` を 1 回通す(§6-3)
- [x] 4-6. 実測結果を `verification.md` に表で残す(コマンド・期待・実際)

## 5. ドキュメント

- [x] 5-1. `docs/template-dev/CHANGELOG.md` の `## 2026-09-03` 配下**先頭**に §7 の `[manual]` 項目を追記する(**新しい日付見出しを作らない**)
- [x] 5-2. `git status` に `.harness/codex-runs/` の意図しない差分が無いことを確認する
