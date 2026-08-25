# 再現テストの実行手順(`repro-self-edit.sh`)

対象: `.claude/scripts/delegate-codex.sh` の自己編集ハザード対策(#15)。

## 実行方法

```bash
bash .steering/20260825-issue15-self-edit-hazard/repro-self-edit.sh
```

- 本物の Codex は呼ばない(`codex` を PATH 上のスタブに差し替える)。枠は消費しない
- 実物の `.claude/scripts/delegate-codex.sh` を実行中に一時的に書き換えるが、各シナリオの直後と終了時(`trap ... EXIT`)に必ず元へ書き戻す
- 書き戻し(`cp`)が失敗した場合だけ、退避コピーを `tmp/delegate-codex.sh.rescue` に残したうえで警告を出し、最後の手段として `git checkout` へ落ちる。**この経路は未コミットの変更を失う**ので、警告が出たら退避コピーから復旧すること
- フィクスチャは `tmp/repro-issue15*`(`.gitignore` 済み)に作り、終了時に削除する
- 生成した run record(`.harness/codex-runs/*.json` 等)のうち、フィクスチャの steering を指すものだけを削除する

## チェック内容と期待値

### S1〜S3: 自己編集ハザードの再現(design.md §3.4)

コピー先の `codex` スタブが、`codex exec` 呼び出しの中で実物の `delegate-codex.sh` を書き換える(= Codex が委託中にハーネス層を触る事象を模す)。書き換え方法は `REPRO_EDIT` で切り替える:

| 値 | 書き換え方 | 意図 |
| --- | --- | --- |
| `overwrite` | ファイル全体を `fi` だけの 20000 行で上書き | 決定論的に構文エラーを起こす |
| `insert` | shebang の直後に `# pad` を 400 行挿入 | 実際に近い形(前方へのバイト挿入でオフセットがずれる) |

| # | 対策 | 書き換え | 期待 exit | 期待 run record status | 意味 |
| --- | --- | --- | --- | --- | --- |
| S1 | 無効(`CODEX_DELEGATE_NO_SELF_COPY=1`) | overwrite | 非 0 | `running`(孤児化) | 旧挙動の再現。**これが失敗しなければテスト自体が無効** |
| S2 | 有効 | overwrite | 0 | `completed` | 対策が overwrite 型の書き換えを防ぐ |
| S3 | 有効 | insert | 0 | `completed` | 対策が insert 型の書き換えを防ぐ |

S2 の実行前後では、追加で `${TMPDIR:-/tmp}` 直下のエントリ数を数え、増えていないことも確認する(`trap` によるコピー先の後始末が効いているかの検証。design.md §3.6)。

### C1〜C6: 終了コード契約の非回帰チェック(design.md §3.5)

対策を入れても既存の終了コード契約(0〜5)が変わらないことを確認する。C1〜C5 はいずれも入口検査で落ちるため、`codex` スタブは呼ばれない。

| # | 実行 | 期待 exit | 理由 |
| --- | --- | --- | --- |
| C1 | 引数なし | 2 | usage 表示 |
| C2 | `fix-ci x` | 2 | 未実装モード |
| C3 | `impl tmp/repro-issue15-missing` | 2 | ステアリングディレクトリでない(存在しない) |
| C4 | `impl <draft の design.md を持つディレクトリ>` | 5 | 計画未完成(`<!-- status: draft -->`) |
| C5 | `explore x --unknown-opt` | 2 | 未知のオプション |
| C6 | `PATH=/usr/bin:/bin` で `explore x` | 3 | `codex` も `npx` も見えず Codex 利用不可(理由の区別はしない) |

### 後始末の確認

`.claude/scripts/delegate-codex.sh` が実行開始前のバックアップと一致すること(`cmp`)を確認する。

## 出力の見方

各行は `PASS <名前> <詳細>` または `FAIL <名前> <詳細>` の形式。末尾に `PASS=N FAIL=N` の集計が出て、1 つでも FAIL があればスクリプト全体が `exit 1` になる。

## 失敗時の見方

- **S1 が FAIL(exit=0)**: 再現方法自体が成立していない。bash のバージョンやスクリプト長の前提が環境で崩れている可能性がある。`overwrite` の行数(20000)を増やすなど、書き換えが読み取り位置より確実に手前で構文を壊すように調整する
- **S2 / S3 が FAIL**: 対策(自己コピー & exec ブロック)が効いていない。`.claude/scripts/delegate-codex.sh` の該当ブロックが `set -uo pipefail` の直後・引数パースより前にあるか確認する
- **S2-leak が FAIL**: 自己コピー先の一時ディレクトリが残っている。`trap cleanup_self_copy EXIT` および `INT` / `TERM` のトラップが正しく設定されているか確認する
- **C1〜C6 のいずれかが FAIL**: 対策の挿入によって既存の入口検査の分岐(引数パース・denylist・AGENTS.md プローブ・Codex CLI 検査・impl 専用検査)の順序や条件が壊れていないか確認する
- **restore が FAIL**: `.claude/scripts/delegate-codex.sh` の内容が実行前と一致しない。**最優先で `git diff -- .claude/scripts/delegate-codex.sh` を確認し、意図しない変更が残っていないか確かめること**。復元失敗の警告が出ていた場合は `tmp/delegate-codex.sh.rescue` に実行前の内容が残っている
