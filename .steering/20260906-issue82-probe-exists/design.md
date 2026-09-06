# 設計: 検証プローブのホスト実行経路を閉じる(Issue #82)

<!-- status: ready -->

## 0. 採用方式の決定(司令塔の判断)

**Issue のスコープ 1(「プローブから exec を無くす」)を採用する。** スコープ 2(指紋を取る)は採らない。

| 観点 | 1. exec を無くす(採用) | 2. 指紋を取る(不採用) |
| --- | --- | --- |
| 経路 | **消える**(プロセスを 1 つも起動しない) | 残る。警告が出るだけで実行はされる |
| 検出タイミング | 事前(そもそも実行しない) | **実行の後**に「前回と違う」と分かる = 初回の差し替えは素通し |
| 初回委託 | 動く | **前回値が無いので必ず素通し**。初回に仕込まれたら検出できない |
| 追加状態 | なし | `.harness/` に指紋ファイルが増える。モード C ではそもそも `delegate-codex.sh` を通らないので更新されない |
| プローブの目的の充足 | 満たす(「依存が入っているか」は存在確認で十分) | 満たす |

決め手は「**指紋方式は初回と経路外(モード C)で必ず素通しする**」こと。#43 の教訓 1
(「許可リストは、許可した要素が安全であることを別途実測しないと成立しない」)と同じ形で、
指紋方式は「前回の値が信用できる」という**別の未検証の前提**を新たに導入する。
経路そのものを消せる以上、そちらを採る。

**#79 の判断理由(「依存が入っているか」を確かめたい)は満たされる。** `npx --no-install eslint --version`
が実質やっているのは `node_modules/.bin/eslint` の解決であり、その成否は存在確認で判定できる。
実行して版を出させる部分は導通確認に寄与していない。

## 1. 全体像

```
AGENTS.md の <!-- verify-probe: ... --> を抽出
  ↓
probe_format_reason()  ← P0 を追加(P1〜P3 は後方互換で維持)
  ↓
形式が P0 → [ -e "$path" ] だけで判定(プロセス起動なし)   ★新
形式が P1〜P3 → 従来どおり env -i ... bash -c(後方互換)
形式外・未設定 → 警告してスキップ(委託は続行。フェイルオープンは変えない)
```

## 2. 新形式 P0 の仕様

```
exists <相対パス>
```

- トークン数は必ず **2**。第 1 トークンは固定文字列 `exists`
- `<相対パス>` の制約:
  - `..` を含まない(`_probe_name_ok` の既存の独立検査が弾く)
  - **絶対パス不可**(先頭が `/` でない)
  - **`-` 始まり不可**(オプション類似を避ける)
  - 使える文字は既存の (b) 検査と同じ集合(英数 `.` `_` `/` `@` `=` `:` `+` `-`)
- テンプレート既定値: `exists node_modules/.bin/eslint`

### 判定の意味論

- 判定は `[ -e "$path" ]`。`delegate-codex.sh` は 112 行目で `cd "$ROOT"` 済みなので、
  パスは**リポジトリルート相対**として解決される
- `-e` はシンボリックリンクを辿る。**壊れたリンク = 依存が使えない**なので `-e` が正しい
  (`-L` を併用して「リンクがあれば OK」にはしない)
- ワークツリー内のシンボリックリンクがワークツリー外を指していても、**起きるのは stat だけ**で
  実行は無い。漏れるのは「そのパスが存在するか」という 1 bit のみで、受容する(コメントに明記)
- 失敗時は従来の P1〜P3 と同じく `exit "$EX_UNAVAIL"`(依存未インストールとして委託を止める)

## 3. 実装 A: `probe_format_reason()` への P0 追加

**挿入位置は `last="${parts[$((n - 1))]}"` の直後、`java -version` の完全一致特例より前。**

理由: `exists <path>` は n=2 だが末尾が `--version` ではないため、既存の
「末尾は必ず導通確認トークン」検査より**手前**で分岐しないと必ず落ちる。

現在(`.claude/scripts/delegate-codex.sh:561-565` 付近):

```bash
  IFS=' ' read -r -a parts <<<"$probe"
  n="${#parts[@]}"
  last="${parts[$((n - 1))]}"

  # java だけは従来形の `java -version` も通す(実測で版を出して終わる)。
```

変更後(`last=...` の行と `# java だけは...` の間に挿入):

```bash
  IFS=' ' read -r -a parts <<<"$probe"
  n="${#parts[@]}"
  last="${parts[$((n - 1))]}"

  # P0: exists <相対パス> — **ホスト上でプロセスを 1 つも起動しない**存在確認。
  #     テンプレート既定はこの形。P1〜P3(exec を伴う形)は他スタック向けの
  #     後方互換として残すが、上の「残るリスク」をそのまま引き受けることになる。
  #     末尾が導通確認トークンではないため、下のトークン検査より手前で分岐する。
  if [ "${parts[0]}" = "exists" ]; then
    if [ "$n" != 2 ]; then
      echo "exists 形式は exists <相対パス> の 2 トークンである必要があります"
      return 1
    fi
    # 先頭 1 文字の文字クラスで絶対パス(/)と - 始まりを弾き、
    # .. は _probe_name_ok の独立検査が弾く(P2 / P3 と同じ多重防御)。
    if _probe_name_ok "${parts[1]}" '^[A-Za-z0-9._@+][A-Za-z0-9._/@=:+-]*$'; then
      return 0
    fi
    echo "exists のパスが不正です(リポジトリ相対のみ。.. と絶対パスは不可): ${parts[1]}"
    return 1
  fi

  # java だけは従来形の `java -version` も通す(実測で版を出して終わる)。
```

**`PROBE_ALLOWED_CMDS` に `exists` を足さないこと。** P0 は上の専用分岐だけで完結し、
P1 の `<cmd> <verify>` 経路には乗らない(乗せると `exists --version` が通ってしまう)。

### (c) のコメント表の更新

`probe_format_reason()` 内の `# (c) 全体が導通確認の固定形に一致すること。` ブロックにある
形式一覧(現在 P1 / P2 / P3 の 3 行)の**先頭**に P0 を追加する:

```
#       P0  exists <相対パス>                          exists node_modules/.bin/eslint(exec しない)
#       P1  <cmd> <verify>                          node --version / java -version
```

末尾の「許可された形に一致しません」のメッセージにも P0 を足す:

```bash
  echo "許可された形に一致しません(exists <相対パス> / <cmd> <verify> / npx --no-install <pkg> <verify> / python -I -m <module> <verify> のいずれか)"
```

## 4. 実装 B: ホスト側の分岐(exec しない経路)

現在(`.claude/scripts/delegate-codex.sh:663` 付近、`else` ブロック):

```bash
else
  # 何が実行されるかを毎回目に見える形にする。ここを黙らせない。
  echo "delegate-codex: 検証プローブを実行します: $PROBE" >&2
  if ! env -i "${PROBE_ENV[@]}" bash -c "$PROBE" >/dev/null 2>&1; then
    cat >&2 <<MSG
delegate-codex: 検証プローブが失敗しました: $PROBE
...
MSG
    exit "$EX_UNAVAIL"
  fi
fi
unset _probe_reason
```

変更後:

```bash
elif [ "${PROBE%% *}" = "exists" ]; then
  # P0: プロセスを 1 つも起動しない。cd "$ROOT" 済みなのでリポジトリルート相対で解決する。
  # -e はシンボリックリンクを辿るが、ここで起きるのは stat だけで実行は無い
  # (ワークツリー内のリンクがワークツリー外を指していても、漏れるのは存在の有無だけ)。
  _probe_path="${PROBE#exists }"
  echo "delegate-codex: 検証プローブ(存在確認・プロセス起動なし): $_probe_path" >&2
  if [ ! -e "$_probe_path" ]; then
    cat >&2 <<MSG
delegate-codex: 検証プローブの対象が存在しません: $_probe_path

依存が未インストールの可能性があります。Codex の sandbox はネットワーク
無効のため、この状態で委託すると何も完遂できないまま枠だけを消費します。
先に依存をインストールしてから再実行してください。

(このプローブはリポジトリルート相対の存在確認で、ホスト上でプロセスを起動しません。)
MSG
    exit "$EX_UNAVAIL"
  fi
else
  # 何が実行されるかを毎回目に見える形にする。ここを黙らせない。
  echo "delegate-codex: 検証プローブを実行します: $PROBE" >&2
  if ! env -i "${PROBE_ENV[@]}" bash -c "$PROBE" >/dev/null 2>&1; then
    cat >&2 <<MSG
delegate-codex: 検証プローブが失敗しました: $PROBE

依存が未インストールの可能性があります。Codex の sandbox はネットワーク
無効のため、この状態で委託すると何も完遂できないまま枠だけを消費します。
先に依存をインストールしてから再実行してください。

(プローブは env -i + 最小の環境変数で実行されます。親の環境変数に依存する
 プローブはここで失敗します。)
MSG
    exit "$EX_UNAVAIL"
  fi
fi
unset _probe_reason _probe_path
```

**分岐の順序に注意。** `elif` は既存の `elif ! _probe_reason=...`(形式検査)の**後ろ**に置く。
形式検査を通ったものだけが `exists` 分岐に入る = 形式外の `exists ...` は stat すらしない。

## 5. 実装 C: 実在しない代償措置の記述を直す(受け入れ条件)

`.claude/scripts/delegate-codex.sh:497-503` の以下のコメントブロックを差し替える。

現在:

```
# **形式検査で閉じられない残りのリスク**: プローブは cd "$ROOT" した状態で実行される。
# npx --no-install <pkg> は node_modules/.bin/<pkg> を解決するため、ワークツリーに
# 実行ファイルを置ける相手には、AGENTS.md を 1 文字も変えなくてもホスト実行の経路が
# 残る。これはプローブの正当な仕事(このプロジェクトのローカル依存の導通確認)と
# 表裏一体で、形式検査では原理的に閉じられない。空ディレクトリでの実行は
# npx --no-install が常に失敗するため採れない(実測)。ワークツリーの完全性は
# 出口ハッシュ検査・check-guard-integrity.sh degraded が受け持つ別の層。
```

変更後:

```
# **P1〜P3(exec を伴う形)に残るリスク**: プローブは cd "$ROOT" した状態で実行される。
# npx --no-install <pkg> は node_modules/.bin/<pkg> を解決するため、ワークツリーに
# 実行ファイルを置ける相手には、AGENTS.md を 1 文字も変えなくてもホスト実行の経路が
# 残る(sandbox 内で書く → 次回委託の入口検査でサンドボックス外実行)。これは
# プローブの正当な仕事(このプロジェクトのローカル依存の導通確認)と表裏一体で、
# 形式検査では原理的に閉じられない。空ディレクトリでの実行は npx --no-install が
# 常に失敗するため採れない(実測)。
#
# **この経路を受け持つ層は存在しない(#82)。** かつてここには「ワークツリーの完全性は
# 出口ハッシュ検査・check-guard-integrity.sh degraded が受け持つ別の層」と書いてあったが、
# 出口ハッシュ検査は FORBIDDEN_PATHS に列挙したパスだけを走査して node_modules/ を見ず
# (数万ファイルのハッシュは現実的でない)、degraded 検査は git log 起点で node_modules/ は
# gitignore 済み。**前提だけが書かれていて、その層は実在しなかった。**
#
# そのため既定形式を P0(exists <相対パス>)に移した。P0 はプロセスを 1 つも起動しない
# ので、この経路そのものが無い。P1〜P3 は他スタックのプロジェクト向けの後方互換として
# 残すが、選んだ場合は上のリスクを受容することになる(#60 の「受容するなら明文化する」)。
```

## 6. 実装 D: `AGENTS.md` の更新

### D-1. マーカー(86 行目)

```diff
-<!-- verify-probe: npx --no-install eslint --version -->
+<!-- verify-probe: exists node_modules/.bin/eslint -->
```

### D-2. §2 の形式制約の説明

引用ブロックの本文を次に差し替える(表「用途 / コマンド」より上、マーカー直下のブロック)。
**既存の文体・引用符号(`>`)を維持すること。**

```markdown
> 上の行は `delegate-codex.sh` が読む機械可読マーカーです。**依存が入っているかどうかだけ**を確かめる 1 行を書いてください。
>
> **既定は「実行しない」形式(`exists`)です。** この行はかつてホスト上で実行されていましたが、`node_modules/` をワークツリーの相手が書き換えられる以上、実行経路を守る層が存在しませんでした(Issue #82)。現在の既定はプロセスを 1 つも起動しない存在確認です。
>
> **形式制約(`delegate-codex.sh` の入口検査3 が機械検査します)。** 次の形に限って処理され、外れた場合は**何もされず警告が出ます**(委託は続行します)。
>
> - **推奨(既定)** — `exists <リポジトリ相対パス>` — 例: `exists node_modules/.bin/eslint` / `exists .venv/bin/pytest`
>   - リポジトリルートからの相対パスのみ。**絶対パス(`/` 始まり)と `..` は使えません**。`-` 始まりも不可
>   - 判定は存在確認だけで、**ホスト上でプロセスは起動しません**
> - **後方互換(ホスト上で実行されます)** — 他スタックで存在確認では足りない場合のみ:
>   - `<コマンド> <確認フラグ>` — 例: `node --version` / `java -version` / `rake --version`
>   - `npx --no-install <パッケージ> <確認フラグ>` — 例: `npx --no-install eslint --version`
>   - `python3 -I -m <モジュール> <確認フラグ>` — 例: `python3 -I -m pytest --version`(**`-I` は必須**。付けないとカレントディレクトリのファイルが読まれます)
>   - `<確認フラグ>` は **`--version` のみ**で、**必ず末尾**に置くこと。`version`(ダッシュなし)・`-v`・`--help` は使えません(ダッシュなしの `version` は多くの処理系で『カレントディレクトリの `version` というファイルを実行する』意味になるため)。**`java -version` だけは従来形として通ります**
>   - `<コマンド>` は **`node` `npm` `npx` `python3` `ruby` `java` `rake` `gradle` のみ**です。`yarn` / `pnpm` / `mvn` は使えません(`--version` でもワークツリーの設定ファイルに従って別のコードを実行するため)
>   - `install` / `add` / `run` / `exec` のようなサブコマンドは書けません(依存の取得やライフサイクルスクリプトがホスト上で走るため。`npx` の `--no-install` が必須なのも同じ理由)
>   - **これらを選ぶと残存リスクを引き受けることになります。** `npx --no-install <パッケージ>` はワークツリーの `node_modules/.bin/` を解決するため、そこに実行ファイルを置ける相手にはホスト実行の経路が残ります。**この経路を守る層はありません**(だから既定を `exists` にしています)
> - 共通: 使える文字は英数と `.` `_` `/` `@` `=` `:` `+` `-`、区切りは半角スペース 1 個のみ(`;` `|` `&` `$` `` ` `` 引用符・リダイレクト・改行はすべて不可)、全体 200 文字以内
> - **形式が合っていても安全になるわけではありません。** プローブの形式検査は「文字列が任意コマンドに化けること」を防ぐものです。このファイルも `node_modules/` も書き換えないでください
```

### D-3. 155 行目(禁止領域の説明)

現在:

```
- `AGENTS.md` — このファイル自身。冒頭の `<!-- verify-probe: ... -->` は次回の委託時にホスト側で実行されるため、あなたが書き換えるとサンドボックスの外へ影響が出ます。形式検査が入っていますが、**検査を通る範囲でも書き換えないでください**
```

変更後:

```
- `AGENTS.md` — このファイル自身。冒頭の `<!-- verify-probe: ... -->` は次回の委託時にホスト側で読まれます。既定の `exists` 形式はプロセスを起動しませんが、**後方互換の形式(`npx` / `python3` 等)に書き換えられるとホスト上でコマンドが実行されます**。形式検査が入っていますが、**検査を通る範囲でも書き換えないでください**
```

## 7. `CLAUDE.md` の記述との整合

`CLAUDE.md` の委託禁止領域節にある `AGENTS.md` の説明:

> 入口検査3 の `<!-- verify-probe: ... -->` は次回委託時にホスト上の `bash -c` へそのまま渡されるため、書き換えを許すとサンドボックス外でのコマンド実行経路になる(入口検査3 に許可リスト形式の機械検査と `env -i` 実行を入れてあるが、**多層防御であって置き換えではない**。禁止領域からは外さない)

**この記述は変更しない。** 既定は `exists` に移るが、後方互換形式に書き換えられれば
`bash -c` 経路は依然として開く。禁止領域に置く理由は変わらない。

## 8. CHANGELOG

`docs/template-dev/CHANGELOG.md` の `## 2026-09-05` の**上**に `## 2026-09-06` の見出しを
新設して追記する(日付を遡って過去の見出しに追記しない)。区分は **`[manual]`**
(既定マーカーの形式が変わり、取り込む側の `AGENTS.md` は merge 区分なので手当てが要る)。

書く内容:

- 検証プローブに `exists <リポジトリ相対パス>` 形式を追加し、テンプレート既定のマーカーを
  `npx --no-install eslint --version` から `exists node_modules/.bin/eslint` に変更したこと
- 理由:従来の既定は `node_modules/.bin/eslint` をホスト上で実行しており、その `node_modules/`
  はワークツリーの委託先が書き換えられた。守る層(出口ハッシュ検査 / degraded 検査)は
  実在しなかった(#82)
- 既存の 3 形式(`<cmd> --version` / `npx --no-install <pkg> --version` /
  `python3 -I -m <module> --version`)は**後方互換として動作を変えていない**
- 取り込む側の作業(`[manual]` に必須):**自分の `AGENTS.md` の `<!-- verify-probe: ... -->`
  を `exists <相対パス>` 形式に書き換える**。Node 系なら `exists node_modules/.bin/<ツール名>`、
  Python 系なら `exists .venv/bin/<ツール名>`。書き換えなくても従来形式は動くが、
  ホスト実行の経路が残る

## 9. 変更しないもの(スコープガード)

- `PROBE_ALLOWED_CMDS` / `PROBE_VERIFY_TOKENS` / `PROBE_ENV` の値
- `_probe_name_ok()` の実装
- (a) 長さ上限 / (a2) 改行 / (b) 文字集合の各検査
- P1 / P2 / P3 の判定ロジックと `java -version` 特例
- 形式外・未設定時のフェイルオープン(警告 + スキップ)
- 入口検査の順序(検査1 の denylist が検査3 より先)
- `FORBIDDEN_PATHS`(`node_modules/` は追加しない)
- `CLAUDE.md`(§7 のとおり)

## 10. 検証(V1〜V12)

手順は #43 と同じ(`.steering/20260829-issue43-verify-probe-hardening/verification.md`):

1. `AGENTS.md` の 86 行目のマーカーだけを line-targeted `sed` で差し替える
2. `CODEX_DELEGATE_ACK_SECRETS=1 bash .claude/scripts/delegate-codex.sh impl /tmp/not-steering`
   を実行する(入口検査5-1 で `exit 2` になるので **codex を起動せずに**入口検査3 の出力だけを観測できる)
3. バックアップから `AGENTS.md` を復元する

**必ずバックアップを取ってから始め、全 V の実行後に `git diff -- AGENTS.md` で
最終形(D-1 / D-2 / D-3 の変更のみ)になっていることを確認すること。**

| ID | プローブ | 期待 |
| --- | --- | --- |
| V1 | `exists node_modules/.bin/eslint` | 通る。`検証プローブ(存在確認・プロセス起動なし)` が出て `exit 2`(検査5-1)まで進む |
| V2 | `exists node_modules/.bin/does-not-exist` | `検証プローブの対象が存在しません` で `exit 3`(`EX_UNAVAIL`) |
| V3 | `exists ../../etc/passwd` | **形式検査で落ちる**(`exists のパスが不正です`)。stat もされない |
| V4 | `exists /etc/passwd` | 同上(絶対パス) |
| V5 | `exists node_modules/../../../etc/passwd` | 同上(`..` を含む) |
| V6 | `exists -rf` | 同上(`-` 始まり) |
| V7 | `exists`(1 トークン) | 形式検査で落ちる(`許可された形に一致しません`。n=1 は (c) の分岐に落ちる) |
| V8 | `exists a b` (3 トークン) | 形式検査で落ちる(`exists 形式は ... 2 トークン`) |
| V9 | `exists --version` | 形式検査で落ちる(`-` 始まり)。**P1 として通ってはならない** |
| V10 | `npx --no-install eslint --version` | **従来どおり通る**(後方互換。`検証プローブを実行します` が出る) |
| V11 | `node --version` / `java -version` | **従来どおり通る**(後方互換) |
| V12 | `python3 -I -m pytest --version` | **形式検査は通る**(実行自体は pytest 未インストールで失敗しうる。`検証プローブを実行します` が出れば合格) |

さらに:

- V13 `npm run lint` / `npm run format:check` が通る(shell は対象外だが Markdown が prettier に掛かる)
- V14 `bash -n .claude/scripts/delegate-codex.sh` が通る(構文チェック)
- V15 `bash .claude/scripts/check-guard-integrity.sh` が通る
- V16 `bash .claude/scripts/check-record-hygiene.sh` 相当(CHANGELOG 更新の検査)が通る

## 11. 実装順序

§11 の順で進める(tasklist.md 参照)。**A → B を先に入れてから C / D を書く**
(コメントと文書が実装より先に「新しい形」を主張する状態を作らない)。
