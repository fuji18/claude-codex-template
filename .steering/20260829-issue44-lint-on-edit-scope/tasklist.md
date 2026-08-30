# タスクリスト: lint-on-edit.sh を編集ファイル単位に絞る

design.md の §5 / §6 をそのまま適用する。設計判断は残っていない。

## 実装

- [x] `.claude/scripts/lint-on-edit.sh` を design.md §5 の内容で全面置換する(実行ビットは維持する)
- [x] `docs/template-dev/CHANGELOG.md` の既存見出し `## 2026-08-29` の直下(既存本文の後ろ)に
      design.md §6 の 2 項目を追記する。**新しい日付見出しは作らない**

## 検証(すべて実際に走らせて結果を控える)

hook は標準入力から JSON を読む。以下の形で直接叩ける:

```bash
run() { printf '{"tool_input":{"file_path":"%s"}}' "$1" | .claude/scripts/lint-on-edit.sh; }
```

- [x] **対象外の拡張子で何も出ない**: `run "$PWD/README.md"` → 出力なし・exit 0
- [x] **クリーンな TS ファイルで何も出ない**: `run "$PWD/src/index.ts"` → 出力なし
- [x] **編集ファイルの lint エラーが出る**: `src/index.ts` の末尾に一時的に
      `const _unusedForCheck = 1; unusedForCheckTypo;` のような eslint エラーを入れて `run` し、
      **そのファイルの指摘だけ**が出ることを確認する → **確認後に必ず元へ戻す**
- [x] **他ファイルの型エラーが件数 1 行に畳まれる**: `src/index.test.ts` に一時的に型エラーを入れ、
      `run "$PWD/src/index.ts"` を実行 → `src/index.ts` の行は出ず、
      `(このファイル以外に型エラー N 件。…)` の 1 行だけが出ることを確認する → **確認後に必ず元へ戻す**
- [x] **連続編集でも取りこぼさない(スキップ穴が塞がったこと)**:
      `run "$PWD/src/index.ts" &` を実行した直後(先行が走っている間)に
      `run "$PWD/src/index.test.ts"` を実行し、**後者が黙って捨てられず**、
      先行プロセス側の出力として拾われる(= キューが処理される)ことを確認する。
      終了後に `.claude/.lint-on-edit.lock` が残っていないことも確認する
- [x] **ロック解放が漏れない**: 上記の実行後 `ls -d .claude/.lint-on-edit.lock` が「無い」ことを確認する

## 後始末

- [x] 検証で入れた一時的なエラーがすべて元に戻っていることを `git diff -- src/` で確認する
      (`src/` に差分が残っていてはいけない)
- [x] 変更したファイルを対象に品質チェックを回す(`npm run format:check` / 対象ファイルの lint)

---

## 改訂(検収指摘の反映 / design.md §8)

**§5 のスクリプトは §8 で置き換えられている。§8 の内容を正とすること。**

- [x] `.claude/scripts/lint-on-edit.sh` を design.md §8 のスクリプトで全面置換する
- [x] `.gitignore` の `.claude/.lint-on-edit.lock` の行を `.claude/.lint-on-edit.*` に**書き換える**(追加ではなく置換。`*.tsbuildinfo` の行は残す)
- [x] `docs/template-dev/CHANGELOG.md` の #44 項目のうち **2 項目め(coalescing の項)を design.md §8 末尾の文面に差し替える**(1 項目めはそのまま)

### 改訂ぶんの検証

前回の検証項目(対象外拡張子 / クリーンファイル / 単体 lint エラー / 型エラーの畳み込み / 連続編集 / ロック解放)を**もう一度**通したうえで、以下を追加する。

- [x] **孤立ロックが奪取される**: `mkdir -p .claude/.lint-on-edit.lock` を手で作り、`touch -d '10 minutes ago' .claude/.lint-on-edit.lock` で古くしてから hook を実行 → **検査が走る**(黙って終わらない)ことと、終了後にロックが残っていないことを確認する
- [x] **新しいロックは奪取されない**: 上と同じ手順でロックを作り、mtime を現在のままにして hook を実行 → 検査は走らず、`.claude/.lint-on-edit.queue` に編集パスが 1 行積まれることを確認する。**確認後にロックとキューを手で消す**
- [x] **シンボリックリンク経由でも検査される**: プロジェクト外に `ln -s` でリンクを作るなどして `realpath` 正規化が効いていることを確認する(環境的に難しければ、`realpath` が入っていることの確認 + `run_checks` に相対パスを渡して動くことの確認で代替してよい。代替した場合はその旨を報告に書く)
- [x] 検証で作ったロック・キュー・シンボリックリンク等の一時物がすべて消えていることを `git status --short` で確認する

---

## 再改訂(再レビュー指摘の反映 / design.md §9)

**§8 のスクリプトは §9 で置き換えられている。§9 の内容を正とすること。`.gitignore` と CHANGELOG は変更不要。**

- [x] `.claude/scripts/lint-on-edit.sh` を design.md §9 のスクリプトで全面置換する

### 再改訂ぶんの検証

これまでの検証項目を**もう一度**通したうえで、以下を追加する。

- [x] **奪取が二重取得しない**: 古いロック(`mkdir` して `touch -d '10 minutes ago'`)を用意し、`acquire_lock` 相当を 2 プロセスほぼ同時に走らせて、**取得成功が 1 本だけ**になることを確認する(スクリプトを `source` せず、hook を 2 本同時にバックグラウンド起動する形でよい)
- [x] **`stat` に依存していない**: `find -mmin` 版の stale 判定が、古いロックで真・新しいロックで偽になることを確認する
- [x] **キューは 1 件ずつ減る**: キューに 3 行積んだ状態でドレインを走らせ、処理のたびに `.claude/.lint-on-edit.queue` の行数が減っていくこと、終了時に空になることを確認する
- [x] **同一パスの重複が畳まれる**: キューに同じパスを 3 行積んで、検査が 1 回だけ走ることを確認する
- [x] 検証で作った一時物(ロック・キュー・`*.reclaim.*`・`*.queue.tmp`)が残っていないことを `ls -a .claude/` と `git status --short` で確認する

---

## 再々改訂(`flock` への置き換え / design.md §10)

**§9 のスクリプトは §10 で置き換えられている。§10 の内容を正とすること。**
これまでの改訂で入れた仕掛け(奪取・ドレイン・キュー)は**消す**。足すのではなく減らす作業。

- [x] `.claude/scripts/lint-on-edit.sh` を design.md §10 のスクリプトで全面置換する
- [x] `.gitignore` の `.claude/.lint-on-edit.*` を `.claude/.lint-on-edit.lock` に**戻す**(これで `.gitignore` はこの PR で無変更になる。`git diff -- .gitignore` が空になることを確認する)
- [x] `docs/template-dev/CHANGELOG.md` の #44 の 2 項目を design.md §10 末尾の文面に**差し替える**(1 項目めも変わっている点に注意。`--incremental` と buildinfo の記述が消える)
- [x] `.claude/.lint-on-edit.tsbuildinfo` を作業ツリーから削除する(`rm -f`)

### 検証

- [x] **相互排他が守られる**: hook を 5 本以上ほぼ同時に起動し、eslint/tsc が直列に実行されることを確認する(`flock` 待ちで後続が待たされること)
- [x] **連続編集を取りこぼさない**: 先行が走っている間に別ファイルの hook を起動し、**黙って終わらず順番が来たら検査される**ことを確認する
- [x] **これまでの検証項目を通す**: 対象外拡張子で無出力 / クリーンな TS で無出力 / 編集ファイルの lint エラーが出る / 他ファイルの型エラーが件数 1 行に畳まれる
- [x] **ロックが孤立しない**: ロック保持中のプロセスを `kill -9` した後、後続の hook が待たされずに実行されることを確認する
- [x] 一時物が残っていないことを `ls -a .claude/` と `git status --short` で確認する(`.lint-on-edit.queue` / `.tsbuildinfo` / `*.reclaim.*` が残っていないこと)
