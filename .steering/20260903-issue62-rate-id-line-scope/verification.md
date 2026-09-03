# 実測記録: Issue #62

司令塔が最終差分に対して独立に再実行した結果(2026-09-03)。
すべて `codex` スタブ + `explore` モード(read-only)。
`CODEX_DELEGATE_ACK_SECRETS=1`(入口検査1 が `.claude/settings.local.json` を検出するため)。

| ケース | ログの内容 | 期待 | 実測 |
| --- | --- | --- | --- |
| V1 | `item.completed` の `aggregated_output` に `rate_limit_reached` を含む引用 + `turn.failed`(タスク起因) | `exit 2` / `failed` | ✅ `exit 2` / `failed` |
| V2 | `{"type":"error"}` と `{"type":"turn.failed"}` に本物の `rate_limit_reached` | `exit 4` / `rate-limited` | ✅ `exit 4` / `rate-limited` |
| V3 | `429` の文言のみ(構造化識別子なし) | `exit 4`(`RATE_TEXT_RE` の網) | ✅ `exit 4` / `rate-limited` |
| V5 | V2 と同じ本物の上限を **446KB / 3000 行超**のログで | `exit 4` | ✅ `exit 4` / `rate-limited` |
| V6 | `workspace_member_usage_limit_reached`(変種) | `exit 4`(部分一致で既にカバー) | ✅ `exit 4` / `rate-limited` |
| V4 | `bash -n .claude/scripts/delegate-codex.sh` | 構文 OK | ✅ OK |

## 修正前との差(V1)

同じスタブログを、`git stash` で修正前の `delegate-codex.sh` に戻して流した:

| | 修正前 | 修正後 |
| --- | --- | --- |
| V1(引用のみ・タスク起因の失敗) | `exit 4`(誤分類) | `exit 2` |

## V5 を追加した理由

当初の design §3.2 は `grep -E ... "$LOG" | grep -Eqi ...` の 2 段パイプだった。
`delegate-codex.sh:35` の `set -uo pipefail` と `grep -q` の早期終了が組み合わさると、
上流の `grep` が SIGPIPE で 141 → パイプ全体が 141 = 偽になり、
**本物のレート上限を取り逃がす**。

実測(独立スクリプトでの再現):

| ログサイズ | 本物の上限行がマッチした回数 |
| --- | --- |
| 277KB(実ログとほぼ同サイズ) | 0 / 10 |
| 2.8MB | 0 / 10 |
| 28MB | 0 / 10 |

3 行のスタブログでは発生しないため、V2 だけでは検出できなかった。
1 回の `grep` に合成して解消し、大ログの回帰ケースとして V5 を常設した。

## 後片付け

検証で生成された `.harness/codex-runs/*` は `.gitignore:54` の対象で作業ツリーに残らない
(`git check-ignore -v` で確認)。スタブとログはスクラッチパッドに置き、実行後に削除済み。
