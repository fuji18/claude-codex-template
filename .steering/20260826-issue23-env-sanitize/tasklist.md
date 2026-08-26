# タスクリスト: Issue #23 委託先へ渡る機密の境界を明確にする

## 実装

- [x] `.claude/scripts/delegate-codex.sh` に許可リスト組み立てブロックを追加する(design §2.2〜2.5)
- [x] `codex exec` の呼び出しを `env -i "${CODEX_ENV[@]}" codex exec \` に書き換える(design §2.6)
- [x] usage の環境変数一覧に `CODEX_DELEGATE_ENV_ALLOW` を追記し、`CODEX_DELEGATE_ACK_SECRETS` の説明を訂正する(design §3.2)
- [x] 入口検査1 のコメントを差し替える(design §3.1)
- [x] `.claude/codex-denylist.txt` の冒頭コメントを差し替える(design §3.3)
- [x] `docs/template-dev/codex-delegation-plan.md` §10.2 に限界の段落を追記し、§13 #7 表の「唯一の層」を「ワークツリー内の唯一の層」に直す(design §3.4)

## 検証

- [x] `bash -n .claude/scripts/delegate-codex.sh` が通る
- [x] `explore` モードで委託先に `env` を出力させ、`LOCAL_GH_TOKEN` / `CLAUDE_CODE_MESSAGING_TOKEN` / `GITHUB_TOKEN` が無いことを確認する(design §4.1)
- [x] `review main` が完走する(design §4.2)
- [x] `verification.md` に上記の結果を書く(impl は検収指摘を受けて後から実測した。下記参照)
- [x] `/check` を通す

## 検収指摘の反映(code-reviewer P1 / P2)

- [x] impl モードを実測し `verification.md` §4.2 を「実測済み」に書き換える(司令塔が実行済み。結果は下記)
- [x] 許可リストのコメントに「pnpm / corepack 系が必要になったら `CODEX_DELEGATE_ENV_ALLOW` で追加する」旨を 1 行足す
- [x] `/check` を通す(司令塔実施済み: typecheck / format / lint / test すべてパス)
