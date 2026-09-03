# タスクリスト: Issue #62

- [x] T1 `delegate-codex.sh` に `RATE_EVENT_RE` を追加する(design.md §3.1)
- [x] T2 失敗時の上限判定を `RATE_EVENT_RE` と `RATE_ID_RE` を合成した **1 回の grep** に書き換える(§3.2。現状はパイプになっており SIGPIPE で本物を取り逃がす)
- [x] T3 「何を、どの範囲で見るか」コメントを差し替える(§3.3)
- [x] T4 V4: `bash -n .claude/scripts/delegate-codex.sh` が通ることを確認する
- [x] T5 V1: 識別子を含むファイルを読んだだけの失敗委託が `exit 2` / `failed` になることを実測する(§4)
- [x] T6 V2: 本物のレート上限イベント行で `exit 4` / `rate-limited` になることを再実測する(§4)
- [x] T7 V3: `429` の文言パターンで `exit 4` になることを実測する(§4)
- [x] T8 `docs/template-dev/CHANGELOG.md` の `## 2026-09-03` に 1 行追記する(§3.4)
- [x] T9 検証で生成された `.harness/codex-runs/*` が作業ツリーに残っていないか `git status` で確認する
- [x] T10 V5: 250KB 以上のログでも本物のレート上限が `exit 4` になることを実測する(§4 V5)
- [x] T11 検収 Major への対応: `RATE_EVENT_RE` の直下に「`item.*` を許可リストに入れない理由」「`RATE_TEXT_RE` に識別子を足さない理由」「`workspace_*` 変種は部分一致で既にカバー済み」の 3 点をコメントで残す(design.md §6)
