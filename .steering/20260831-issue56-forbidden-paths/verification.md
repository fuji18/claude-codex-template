# 検証記録: 委託禁止領域の適用漏れを塞ぐ(Issue #56)

## 1. 構文チェック / 一覧確認

```bash
bash -n .claude/scripts/delegate-codex.sh   # exit 0
bash .claude/scripts/delegate-codex.sh --print-forbidden
```

`FORBIDDEN_PATHS` 15 項目が出力されることを確認した(想定どおり)。残置 running record は無かった。

## 2. design.md との相違点(実装時に補正したもの)

design.md §4 は `FAKE_CODEX_TOUCH` / `FAKE_CODEX_WORK` をそのまま環境変数として渡す手順だが、
現行の `delegate-codex.sh` は `env -i "${CODEX_ENV[@]}" codex exec ...` という許可リスト方式で
子プロセスを起動するため、この 2 変数はそのままではスタブ Codex に伝播しない(#40 の
verification.md が既に記録している既知の補正)。`CODEX_DELEGATE_ENV_ALLOW="FAKE_CODEX_TOUCH,FAKE_CODEX_WORK"`
(S7・S8 は `FAKE_CODEX_WORK` のみ)を追加で渡すことで解消した。手順(テストの book-keeping)の
補正であり、`delegate-codex.sh` 本体・`AGENTS.md` / `CLAUDE.md` の記述には影響しない。

ワークツリーに `.claude/settings.local.json`(gitignore 対象・機密検査の対象)が存在するため、
全シナリオで `CODEX_DELEGATE_ACK_SECRETS=1` を追加した(このリポジトリの既存ローカル設定であり、
今回の変更とは無関係)。

## 3. シナリオ表(8 本)

| # | `FAKE_CODEX_TOUCH` | exit | status | error(run record) |
| --- | --- | --- | --- | --- |
| S1 | `.claude/branch-policy.json` | 2 | `failed` | `委託禁止領域が変更されました: .claude/branch-policy.json` |
| S2 | `.claude/rules/lead/model-strategy.md` | 2 | `failed` | `委託禁止領域が変更されました: .claude/rules/lead/model-strategy.md` |
| S3 | `.claude/rules/spec-driven.md` | 2 | `failed` | `委託禁止領域が変更されました: .claude/rules/spec-driven.md` |
| S4 | `CLAUDE.md` | 2 | `failed` | `委託禁止領域が変更されました: CLAUDE.md` |
| S5 | `.mcp.json` | 2 | `failed` | `委託禁止領域が変更されました: .mcp.json` |
| S6 | `.codex/config.toml` | 2 | `failed` | `委託禁止領域が変更されました: .codex/config.toml` |
| S7 | (なし) | 0 | `completed` | `null`(禁止領域に触れない通常委託は従来どおり成功。誤爆なし) |
| S8 | (なし。`.mcp.json` を退避した状態) | 0 | `completed` | `null`(不在パスでも `--print-forbidden` rc=0・通常委託 exit 0。回帰なし) |

いずれも期待どおりの結果。判断1(`.claude/rules/` をディレクトリ単位で入れる)の裏取りとして、
S3 で `lead/` `mode/` の個別列挙では拾えない `spec-driven.md` の改ざんも検出できることを確認した。

改ざんしたファイルのうち、本チケットで未コミットの変更が乗っている 4 ファイル
(`.claude/branch-policy.json` / `CLAUDE.md` / `.mcp.json` / `.codex/config.toml`)は
各シナリオ直後に `cp` によるバックアップ/リストアで復元した(`git checkout --` を使うと
本チケットの実装変更ごと消えるため。#20 の実測を踏襲)。`.claude/rules/lead/model-strategy.md`
と `spec-driven.md`(本チケットでの変更対象外)は S2・S3 実行直後の復元を失念しており、
§6 後始末の `git diff --stat` 確認時に汚染(`# tampered by fake codex` の追記)が残っていることに
気づいたため、この 2 ファイルは未コミット変更が無いことを確認したうえで `git checkout --` で
復元した。

## 4. 受け入れ条件3(不在パスで壊れないこと)の実測(S8)

```
print-forbidden rc=0
S8 exit=0 status=completed error=null
```

`.mcp.json` を一時退避した状態でも `--print-forbidden` と通常委託がどちらも正常終了することを
確認した。`.mcp.json` は検証直後に復元した。

## 5. コスト計測

S7 相当(禁止領域に触れない通常委託 1 本)の全体所要時間:

```
real    0m7.682s
user    0m1.831s
sys     0m0.358s
```

`FORBIDDEN_PATHS` を 10 項目→15 項目に増やしても、`forbidden_files()` の探索対象(各エントリの
`git diff` / `git ls-files` 呼び出し)が線形に増えるだけで、#40 検証時(7.856s)と有意差はない。
閾値判定はしない(design.md の要件どおり、数値を残すのみ。バッチ化は Issue #65 の担当)。

## 6. 後始末

`git reset` で使い捨てステアリング(`.steering/20260831-issue56-verify-scratch`)の追跡を外し、
`rm -rf` でディレクトリ・バックアップ(`/tmp/bk-*`)・スタブ Codex ディレクトリを削除した。
`git status --porcelain` で使い捨てステアリングと scratch ファイルが残っていないこと、
`.mcp.json` / `.claude/branch-policy.json` が退避前の内容に戻っていることを確認した。
`git diff --stat` は §1〜§3・§5 の 4 ファイル(`delegate-codex.sh` / `AGENTS.md` / `CLAUDE.md` /
`CHANGELOG.md`)のみであることを確認した。検証で生成された run record
(`.harness/codex-runs/20260831-*.json` / `*.log`)は実測の証跡として削除していない。
