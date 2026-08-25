<!-- status: ready -->

# 設計: delegate-codex.sh の自己編集ハザードを塞ぐ

## 1. 採る方式

`docs/template-dev/codex-delegation-plan.md` §9 で **(b) 起動時に自身を一時ディレクトリへコピーして `exec` する** が判断済み。これをそのまま実装する。(a)(本体を関数で包む)は採らない。

**なぜ (b) で塞がるか**: `exec` はプロセスを置き換えるが、置き換え後の bash が読むのは**コピー側のファイル**。元ファイルがどれだけ書き換わっても、実行中の読み取り対象は誰も触らない一時ファイルなので、オフセットがずれない。

**exec で変わらないもの**(既存挙動を壊さない根拠):

| 事項 | exec 後 | 影響 |
| --- | --- | --- |
| PID(`$$`) | 変わらない | `RUN_ID` の衝突回避と run record の `"pid"`、再入防止(5-5)の `kill -0` がそのまま成立する |
| カレントディレクトリ | 変わらない | `git rev-parse --show-toplevel` が同じ結果を返し、以降の相対パス参照(`.claude/codex-denylist.txt` / `AGENTS.md` / `.claude/scripts/*.sh` / `.harness/codex-runs`)はすべて `cd "$ROOT"` 後の解決なので影響なし |
| 終了コード | そのまま伝播 | 契約(0〜5)が変わらない |
| 標準入出力・環境変数 | 引き継がれる | ログ・サマリーの出方が変わらない |

**コピーは無条件に行う**(`impl` に限定しない)。ハザードは `workspace-write` でしか起きないが、モード判定は引数パース後であり、分岐を増やすほど「どの経路でコピーされるか」が読みにくくなる。コストは `mktemp` + `cp` + `exec` 1 回で無視できる。

## 2. 挿入位置とコード(そのまま貼る)

`.claude/scripts/delegate-codex.sh` の `set -uo pipefail` の**直後**、`EX_FAIL=2` の**直前**に以下を挿入する。**引数パースより前に置くこと** — `"$@"` が `shift` される前でなければ元の引数を渡せない。

```bash
# ---------- 自己編集ハザード対策: 自身をコピーして exec ----------
#
# bash はスクリプトを逐次読み込みする。実行中に自分自身のファイルが書き換わると
# 次に読むオフセットがずれ、無関係な行で構文エラーになって死ぬ。委託先がハーネス層を
# 触るのはテンプレート開発では常態なので、起動直後に自身を一時ディレクトリへコピーし、
# そちらを exec して走る。以降どれだけ元ファイルが書き換わっても、読んでいるのは
# コピーなので影響がない(根拠: docs/template-dev/codex-delegation-plan.md §9)。
#
# exec は PID もカレントディレクトリも変えないため、$$ を使う RUN_ID / run record の
# pid、および git rev-parse --show-toplevel 以下の相対パス参照は従来どおり成立する。
#
# 環境変数:
#   CODEX_DELEGATE_SELF_COPY    内部用。コピー先ディレクトリ(= 再入マーカー)。外から設定しない
#   CODEX_DELEGATE_NO_SELF_COPY =1 でコピーを行わない(再現テストが旧挙動を再現するための逃げ道)
#
# ここはフェイルオープンにする。機密送信やガードレールと違い、これは堅牢化の層であって
# 安全検査ではない。コピーに失敗しただけで委託を丸ごと止めるのは、通したコストより
# 止めたコストの方が大きい(入口検査群とは非対称の判断)。
if [ -z "${CODEX_DELEGATE_SELF_COPY:-}" ] && [ "${CODEX_DELEGATE_NO_SELF_COPY:-}" != "1" ]; then
  _self="${BASH_SOURCE[0]:-$0}"
  _copy_dir="$(mktemp -d 2>/dev/null || true)"
  if [ -n "$_copy_dir" ] && [ -d "$_copy_dir" ] &&
    cp "$_self" "$_copy_dir/delegate-codex.sh" 2>/dev/null; then
    export CODEX_DELEGATE_SELF_COPY="$_copy_dir"
    exec bash "$_copy_dir/delegate-codex.sh" "$@"
  fi
  [ -n "$_copy_dir" ] && rm -rf "$_copy_dir"
  echo "delegate-codex: 警告 — 自身の一時コピーを作れませんでした。委託中にこのスクリプトが書き換わると異常終了します。" >&2
fi

if [ -n "${CODEX_DELEGATE_SELF_COPY:-}" ]; then
  SELF_COPY_DIR="$CODEX_DELEGATE_SELF_COPY"
  # 子プロセス(codex exec とその sandbox)の環境に漏らさない。
  unset CODEX_DELEGATE_SELF_COPY
  cleanup_self_copy() { [ -n "${SELF_COPY_DIR:-}" ] && rm -rf "$SELF_COPY_DIR"; }
  trap cleanup_self_copy EXIT
  # 既定では SIGINT / SIGTERM で EXIT トラップを通らずに死ぬ = 一時ディレクトリが残る。
  # exit を明示して EXIT トラップへ落とす(終了コードはシグナル既定の 128+n に揃える)。
  trap 'exit 130' INT
  trap 'exit 143' TERM
fi
```

**注意点(実装者向け)**

- `exec bash "$_copy_dir/delegate-codex.sh"` と**明示的に bash で起動する**。`cp` がモードを保つとは限らない環境があるため、実行ビットに依存しない
- `_self` は相対パスでも構わない。このブロックは `cd "$ROOT"` より前にあるので、呼び出し時のカレントディレクトリで正しく解決される
- `usage()` に `CODEX_DELEGATE_NO_SELF_COPY` を**足さない**。テスト用の逃げ道であり、利用者向けの機能ではない(usage に出すと「使ってよいもの」に見える)

## 3. 再現テスト

`.steering/20260825-issue15-self-edit-hazard/repro-self-edit.sh` を新規作成する。**実物の `delegate-codex.sh` を実行中に書き換える**ことで事象を再現し、対策の有無で結果が変わることを確認する。

### 3.1 スタブ方針

本物の Codex は呼ばない。ハザードは bash の挙動であって Codex の挙動ではないため、`codex` を PATH 上のスタブに差し替えれば忠実かつ再現可能に再現できる(枠も消費しない)。スタブは以下を行う:

1. `codex login status`(第 1 引数が `login`)なら何もせず `exit 0`
2. `codex exec ...` なら:
   - 引数から `--output-last-message` の値を取り出す
   - **親スクリプト(`.claude/scripts/delegate-codex.sh`)を書き換える** — これが再現したい事象
   - フィクスチャの `tasklist.md` に `- [x]` を 1 行足す(delegate 側の「成果の実在確認」を通すため)
   - last-message ファイルに `完了: ...` の判定行を書いて `exit 0`

書き換えの 2 種類を `REPRO_EDIT` で切り替える:

| 値 | 書き換え方 | 意図 |
| --- | --- | --- |
| `overwrite` | ファイル全体を `fi` だけの 20000 行で上書き | **決定論的**。bash が保存済みオフセットから読み直すと必ず `fi` から始まり `syntax error near unexpected token 'fi'` になる |
| `insert` | 先頭(shebang の直後)に `# pad` を 400 行挿入 | 実際に起きた事象に近い形(Codex による編集 = 前方へのバイト挿入でオフセットがずれる) |

`overwrite` を主シナリオにする理由: 末尾への追記では**再現しない**。bash のオフセットより後ろにバイトを足しても、既に読んだ位置は動かないため。「書き換えれば必ず落ちる」わけではない点を取り違えると、空振りするテストになる。

### 3.2 フィクスチャ

委託対象のステアリングディレクトリは `tmp/repro-issue15/`(gitignore 済み)に毎回作り直す。入口検査5-1 は「`design.md` と `tasklist.md` を持つディレクトリ」しか見ないので `.steering/` 配下である必要はない。実物のステアリングを対象にすると tasklist が汚れるため使わない。

- `design.md`: 先頭に `<!-- status: ready -->` の 1 行(検査5-2 を通すため)
- `tasklist.md`: `- [ ] ダミータスク` の 1 行

### 3.3 安全策(実物を壊さない)

- 開始時に `.claude/scripts/delegate-codex.sh` を作業用一時ディレクトリへ退避し、`trap ... EXIT` で**必ず書き戻す**
- 書き戻しに失敗した場合の最後の砦として、trap の中で `git checkout -- .claude/scripts/delegate-codex.sh` も試みる
- 各シナリオの直後にも書き戻す(次のシナリオが壊れたスクリプトを実行しないため)
- 生成した run record は steering フィールドがフィクスチャのものだけを削除する
- 終了時に `tmp/repro-issue15/` を削除する

### 3.4 シナリオと期待値

| # | 対策 | 書き換え | 期待 exit | 期待 run record status |
| --- | --- | --- | --- | --- |
| S1 | 無効(`CODEX_DELEGATE_NO_SELF_COPY=1`) | overwrite | **非 0** | `running`(孤児化 = 旧挙動の再現) |
| S2 | 有効 | overwrite | **0** | `completed` |
| S3 | 有効 | insert | **0** | `completed` |

**S1 が「失敗」しなければテスト自体が無効**。S1 が通ってしまう場合は再現方法が誤っているので、対策の検証にならない旨を明示して落とす。

### 3.5 終了コード契約の非回帰チェック

同じスクリプトの後半で、対策を入れても契約(0〜5)が変わらないことを確認する。

| # | 実行 | 期待 exit |
| --- | --- | --- |
| C1 | 引数なし | 2(usage) |
| C2 | `fix-ci x` | 2(未実装) |
| C3 | `impl tmp/repro-issue15-missing` | 2(ステアリングでない) |
| C4 | `impl <draft の design.md を持つディレクトリ>` | 5 |
| C5 | `explore x --unknown-opt` | 2(未知のオプション) |
| C6 | `PATH=/usr/bin:/bin` で `explore x` | 3(Codex 利用不可) |

- C1〜C5 は `codex` スタブを PATH に入れた状態で走らせる(スタブは呼ばれない — いずれも入口検査で落ちるため)
- C4 用に `tmp/repro-issue15-draft/` を別途作る(`design.md` の先頭が `<!-- status: draft -->`)
- C6 は PATH を絞るため `codex` も `npx` も見えなくなる。**どちらの理由でも `EX_UNAVAIL=3`** なので期待値は 3 で正しい(理由の区別まではこのテストの対象外)

### 3.6 一時ディレクトリの後始末チェック

S2 の実行前後で `mktemp -d` の親(`${TMPDIR:-/tmp}`)直下のエントリ数を数え、実行後に**増えていない**ことを確認する。増えていれば `trap` が効いていない。

### 3.7 出力

各チェックを `PASS` / `FAIL` の 1 行で出し、末尾に集計を出す。1 つでも FAIL があれば `exit 1`。

## 4. 実装しないこと

- `codex-run.sh` は変更しない(delegate-codex.sh から呼ばれていない。孤児検出は既存のまま使える)
- `check-guard-integrity.sh` は `delegate-codex.sh` をハッシュしていないので変更不要
- `package.json` の scripts に再現テストを足さない(実物のガードレールファイルを一時的に書き換えるテストであり、CI やコミットフックの流れに乗せない。手動実行に限る)

## 5. 委託禁止領域をどうするか(判断)

**`delegate-codex.sh` は委託禁止領域に残す。** 対策後も外さない。

理由: 本チケットが塞ぐのは「実行中の親プロセスが死ぬ」という**機構上のハザード**だけ。委託の唯一の入口を、その委託自身に書き換えさせるリスク(壊れた入口がコミットされれば以後すべての委託が不能になり、しかもその委託自身は自分の変更を検証できない)は変わらない。

ただし `AGENTS.md` §4 と `CLAUDE.md` の**理由の記述は事実でなくなる**ため更新する:

- `AGENTS.md` の該当行を次に差し替える:
  - 変更前: ``- `.claude/scripts/delegate-codex.sh` — 実行中のあなた自身の起動元。書き換えると親プロセスが構文エラーで死にます``
  - 変更後: ``- `.claude/scripts/delegate-codex.sh` — 実行中のあなた自身の起動元。委託の唯一の入口であり、壊れたものがコミットされると以後すべての委託が不能になります(実行中のプロセス自体は自己コピーで保護済み)``
- `CLAUDE.md`「Codex への委託禁止領域(パス)」の該当行を次に差し替える:
  - 変更前: ``- `.claude/scripts/delegate-codex.sh` — 委託の実行中に自分自身が書き換わると、bash の逐次読み込みで親プロセスが死ぬ(2026-08-23 に実測。`docs/template-dev/codex-delegation-plan.md` §9)``
  - 変更後: ``- `.claude/scripts/delegate-codex.sh` — 委託の唯一の入口。壊れたものがコミットされると以後すべての委託が不能になり、その委託自身は自分の変更を検証できない(実行中プロセスの保護は #15 の自己コピー exec で別途実装済み。`docs/template-dev/codex-delegation-plan.md` §9)``

## 6. 計画文書の更新

`docs/template-dev/codex-delegation-plan.md` §9 の該当項目の末尾(「当座の防波堤として〜明記した。」の後)に追記する:

> **実装済み(2026-08-25 / #15)**: 起動直後に自身を `mktemp -d` 配下へコピーし `exec` する方式で実装した。`exec` は PID とカレントディレクトリを変えないため、`RUN_ID` / run record の `pid` / 相対パス参照はいずれも従来どおり。再現テストは `.steering/20260825-issue15-self-edit-hazard/repro-self-edit.sh`(対策を切った状態で旧挙動が再現することまで確認する)。**委託禁止領域からは外していない** — 塞いだのは実行中プロセスの死であって、「壊れた入口がコミットされると以後の委託が全滅する」というリスクは残るため。
