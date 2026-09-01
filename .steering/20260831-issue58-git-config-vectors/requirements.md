# 要件: モード C 復帰検査に `.git/config` の実行ベクタ検査(D2.5)を追加する(Issue #58)

## 背景

モード C(縮退)は `codex --sandbox workspace-write -c 'sandbox_workspace_write.writable_roots=[".git"]'` で起動する。
これは **Codex が `.git/config` を丸ごと書ける唯一の経路**である。

`check-guard-integrity.sh degraded` は既に 3 つの検査を持つ:

| 検査 | 見ているもの | 実装位置 |
| --- | --- | --- |
| D1 | `core.hooksPath` が `.husky` 配下を指しているか | `check-guard-integrity.sh:104-117` |
| D2 | `.git/hooks/` への直書きフック | `:124-138` |
| D3 | `Codex-authored` コミットが委託禁止領域に触れていないか | `:140-208` |

D1 は `.git/config` の**特定の 1 キー**だけを見ている。しかし同じファイルには
「次に人間や Claude が git を叩いた瞬間にホストコマンドを実行する」キーが他にも複数ある。

| キー | 発火タイミング |
| --- | --- |
| `core.fsmonitor` | `git status` を叩いた瞬間。**復帰検収(D1〜D3)より先に発火し得る** |
| `core.sshCommand` / `credential.helper` | 人間が push した瞬間(§12.3 手順 7 は人間の push を前提にしている) |
| `alias.*` の `!` 形式 / `filter.*.clean|smudge` / `core.pager` / `include.path` | 各コマンド実行時 |

これは「ローカルのガードレールをセキュリティ境界として扱わない」という割り切りの範囲内ではある。
しかし **D1/D2 を設けた以上、同じ経路のより実害の大きい亜種が漏れているのは検査の非対称**であり、
D1/D2 が「守られている」という誤った安心を与える。

さらに順序の問題がある。現行 §12.3 は手順 7 で人間が push し、手順 8 で Claude 復帰時に検収する。
`core.sshCommand` / `credential.helper` は **push の瞬間に発火する**ため、検査が発火に間に合わない。

## スコープ(やること)

1. `check-guard-integrity.sh degraded` に **D2.5** を追加する(`git config --local --list` を読み、危険キーを値ごと報告する)
2. 平常の devcontainer で誤爆しないことを実測で確かめる
3. `docs/template-dev/codex-delegation-plan.md` §12.3 に「push の前に degraded 検査を回す」順序を入れる
4. `.claude/rules/mode/degraded.md` の復帰手順にも同じ順序を反映する

## スコープ外(やらないこと)

- `.git/config` の書き込み自体を止めること(モード C は `.git` が書ける前提で成立している設計)
- グローバル/システム設定(`--global` / `--system`)の検査。縮退中の Codex が書けるのはローカルのみ
- 検査を「セキュリティ境界」として位置づけること。**あくまで検出と報告**
- D1/D2/D3 の既存挙動の変更
- 検査を CI(`harness-integrity` ジョブ)や SessionStart hook の既定経路に載せること(`degraded` サブコマンド限定)

## 受け入れ条件

- [ ] `git config --local core.fsmonitor 'echo pwned'` を仕込んだ状態で `bash .claude/scripts/check-guard-integrity.sh degraded` が反応する(exit 1 + 該当行の出力)
- [ ] 平常の devcontainer(縮退なし)で誤爆しない(D2.5 由来の出力が 0 行)
- [ ] `§12.3` と `degraded.md` に push 前検査の順序が入っている
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み

## 委託方針

**Codex に委託しない。** 対象が `.claude/scripts/`(委託禁止領域・1 系統目「実行される実体」)。
Issue にも `delegate:codex` は付けない旨が明記されている。`implement-ticket` の Sonnet fork が実装する。

## 並行制約

**#59(hooksPath 判定の一本化)と同じ `check-guard-integrity.sh` を触る。** 並行させない。
本チケット(#58)を先に入れる。
