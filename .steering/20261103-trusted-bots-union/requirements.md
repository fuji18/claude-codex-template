# requirements: 信頼するボットの設定を 1 つの概念にまとめる

## 背景(確認済みの事実)

`.claude/autopilot.json` には「信頼するボット」の設定が 2 つある。

| キー | 読む側 | 用途 |
| --- | --- | --- |
| `trustedReviewBots` | `.claude/scripts/autopilot-next.sh` | 変更要求(CHANGES_REQUESTED)を「要対応」として数えるか |
| `trustedBots` | `.claude/scripts/pr-feedback.sh` | レビュー・コメントの**本文**を返すか(既定 `["claude[bot]","github-actions[bot]"]`) |

Codex ボット(例: `chatgpt-codex-connector[bot]`)を `trustedReviewBots` にだけ入れると、次の順で失敗する。

1. `autopilot-next.sh` が `changes_requested` と判定し、`/fix-pr` を起動する
2. `pr-feedback.sh` はそのボットの本文を `untrusted` に回し、件数と名前しか返さない
3. `/fix-pr` は直す対象を受け取れず、何も push しない。ループは「前回の実行後も状態が変わっていない」で止まる

`.claude/rules/lead/review-policy.md` は `trustedReviewBots` に足すようにだけ案内しているため、
**案内どおりに設定すると必ずこの状態になる**。

## 要求

1. 「信頼するボット」を 1 つの概念として扱う。**どちらのキーに書いても両方のスクリプトで効く**
2. 互換のためキーは 2 つとも残す(既存プロジェクトの設定を壊さない)
3. 既定値は変えない。`trustedBots` の既定は `["claude[bot]","github-actions[bot]"]`、`trustedReviewBots` は `[]` のまま
4. Bot であることの確認(`.user.type == "Bot"`)は外さない。名前だけで信頼しない
5. 設定を案内している文書すべてを「どちらに書いても両方で効く」に揃える

## 非対象

- `.claude/autopilot.json` の既定値の変更(`trustedReviewBots` は `[]` のまま)
- 人間の判定基準(OWNER / MEMBER / COLLABORATOR)の変更
- キーの統合・廃止(互換のため 2 つとも残す)

## 受け入れ条件

- `pr-feedback.sh`: ボットを `trustedBots` / `trustedReviewBots` の**どちらに入れても**本文が返る。どちらにも入れなければ `untrusted` に回る。`user.type` が `"User"` なら名前が一致しても信頼しない
- `autopilot-next.sh`: そのボットの現在 head に対する CHANGES_REQUESTED が、**どちらに入れても** `action: fix` になる。どちらにも入れなければならない
- `autopilot-next.sh`: `trustedBots` が文字列の配列でなければ `exit 2`(`trustedReviewBots` と同じ扱い)
- `bash -n` / `shellcheck -x` / `check-forbidden-paths-doc.sh` / `npx prettier --check .` / `autopilot-preflight.sh` の設定検査が通る
