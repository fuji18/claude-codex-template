# 検証記録: 委託禁止領域に CI/hook の判定実体を含める(Issue #40)

## 1. 構文チェック

```bash
bash -n .claude/scripts/delegate-codex.sh
```

結果: エラーなし(exit 0)。

## 2. design.md との相違点(実装時に補正したもの)

design.md §4-0 は `FAKE_CODEX_TOUCH` / `FAKE_CODEX_WORK` をそのまま `bash .claude/scripts/delegate-codex.sh` に環境変数として渡す手順だが、**この前提は実機で成立しなかった**。

- 現行の `delegate-codex.sh` は `env -i "${CODEX_ENV[@]}" codex exec ...` という許可リスト方式で子プロセスを起動する(Issue #20 の検証当時にはまだ存在しなかった仕組み)。許可されるのは `PATH` / `HOME` などの固定リストと `CODEX_*` 接頭辞の変数のみで、`FAKE_CODEX_TOUCH` / `FAKE_CODEX_WORK` はどちらにも該当しないため、素の `bash ... delegate-codex.sh` 呼び出しではスタブ Codex に渡らず、改ざん・成果物書き込みのどちらも発生しなかった(1 回目の S1 試行で確認。exit 2 にはなったが `error` が `委託禁止領域が変更されました` ではなく `exit 0 だが成果物が確認できない` になっていた)
- `CODEX_DELEGATE_ENV_ALLOW="FAKE_CODEX_TOUCH,FAKE_CODEX_WORK"`(S4 は `FAKE_CODEX_WORK` のみ)を追加で渡すことで、スタブへ正しく伝播することを確認した
- これは検証手順(テストの book-keeping)の補正であり、`delegate-codex.sh` 本体・`AGENTS.md` / `CLAUDE.md` の記述には影響しない
- 併せて、Issue #20 の verification.md が既に記録している 2 点も踏襲した: (1) `FAKE_CODEX_WORK` の scratch ファイルは作成直後に `git add` する、(2) シナリオごとに別名の scratch ファイルを使う(`scratch1a.txt` 〜 `scratch1d.txt`)
- ワークツリーに `.claude/settings.local.json`(gitignore 対象・機密検査の対象)が存在するため、全シナリオで `CODEX_DELEGATE_ACK_SECRETS=1` を追加した(このリポジトリの既存ローカル設定であり、今回の変更とは無関係)

## 3. シナリオ表(4 本)

| # | `FAKE_CODEX_TOUCH` | exit | status | error(run record) |
| --- | --- | --- | --- | --- |
| S1 | `.claude/scripts/check-record-hygiene.sh` | 2 | `failed` | `委託禁止領域が変更されました: .claude/scripts/check-record-hygiene.sh` |
| S2 | `.claude/hooks/session-start.sh` | 2 | `failed` | `委託禁止領域が変更されました: .claude/hooks/session-start.sh` |
| S3 | `.claude/settings.json` | 2 | `failed` | `委託禁止領域が変更されました: .claude/settings.json` |
| S4 | (なし) | 0 | `completed` | `null`(禁止領域に触れない通常委託は従来どおり成功。回帰なし) |

いずれも期待どおりの結果。改ざんしたファイルは各シナリオ直後に `cp` によるバックアップ/リストアで復元した(`git checkout --` は使わない。同じファイル群に未コミットの設計変更が乗っているため。#20 の実測を踏襲)。

## 4. コスト計測

S4(禁止領域に触れない通常委託 1 本)の全体所要時間:

```
real    0m7.856s
user    0m1.495s
sys     0m0.526s
```

`FORBIDDEN_PATHS` を 9 項目→10 項目(実質 2 個の完全ファイル名エントリをディレクトリエントリへ置換)にしても、`forbidden_files()` の探索対象ファイル数は大きく変わらない(`.claude/scripts/` 配下は数本、`.claude/hooks/` 配下は 1 本)。閾値判定は行わない(design.md の要件どおり、数値を残すのみ)。

## 5. 後始末

`rm -rf` で使い捨てステアリング(`.steering/20260829-issue40-verify-scratch`)・バックアップ(`/tmp/bk-*.sh` / `/tmp/bk-settings.json`)・スタブ Codex ディレクトリを削除し、`git status --porcelain` で残留が無いことを確認した。検証で生成された run record(`.harness/codex-runs/*.json` / `*.log`)は実測の証跡として削除していない。

## 6. 検収(code-reviewer + test-runner)

- **test-runner**: lint / typecheck / test / format:check / `bash -n`(`.claude/scripts/*.sh` 11 本)すべてパス。自動修正なし
- **code-reviewer**: `0 critical / 0 major / 4 minor`(うち 2 件は info 寄り)

| # | 指摘 | 判断 |
| --- | --- | --- |
| Minor 1 | `AGENTS.md` の新バレットで、`delegate-codex.sh` を壊すと以後すべての委託が不能になる(fail-closed)というリスク説明が旧文言から脱落。`CLAUDE.md` 側は保持しており、Codex 向けと司令塔向けで伝える危険性の種類が食い違う | **採用**。当該バレットに fail-closed の帰結を復活させた |
| Minor 2 | `CHANGELOG.md` の「2 項目を足し」が、実際に追加する 3 エントリと読み違えられうる | **採用**。「3 項目を足し」に修正 |
| Info 3 | `docs/template-dev/codex-delegation-plan.md` に旧・個別ファイル列挙時代の記述が残る | **不採用**。design.md §0 が変更対象を 4 ファイルに限定しており明示的スコープ外。単一ソースは `FORBIDDEN_PATHS` 配列で、この文書は物語調の計画記録であり正ではない |
| Info 4 | `.harness/decisions.jsonl` に #40 のエントリが未記載 | **対応**(指摘ではなくタイミングの確認)。`delegation-policy.md` の定めどおり PR 作成前に追記する |

指摘を反映した 2 ファイルについて、`npx prettier --check` と `bash -n` を再実行して回帰が無いことを確認した。
