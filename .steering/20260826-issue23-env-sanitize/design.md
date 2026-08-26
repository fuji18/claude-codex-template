<!-- status: ready -->

# 設計: 委託先へ渡る環境変数のサニタイズと保護範囲の記述訂正(Issue #23)

## 0. 実装方針の要約

`codex exec` の呼び出しを `env -i` + 許可リストに置き換える。許可リストは
「固定名の列挙 + 接頭辞マッチ(`LC_*` / `CODEX_*`)+ 環境変数による追加」の 3 系統。
併せて 3 箇所の記述を実態に合わせる。

---

## 1. 実測で確定した前提(推測禁止・再測不要)

devcontainer(codex-cli 0.149.0)で以下を実測済み。**この結果を前提に実装してよい。**

- `env -i PATH=… HOME=… TERM=… LANG=… codex exec --sandbox read-only …` は**完走する**
  (認証は `$HOME/.codex/auth.json` を読むため `HOME` が要る)
- 同じ最小環境で sandbox 内のシェル実行も成立する。`node --version` / `git rev-parse` /
  `npx --no-install eslint --version` がいずれも解決した(`PATH` に nvm の bin が含まれるため、
  `NVM_DIR` / `NVM_BIN` は不要)
- 親の環境には `LOCAL_GH_TOKEN` / `CLAUDE_CODE_MESSAGING_TOKEN` 等が乗っている

---

## 2. 許可リストの実装(`.claude/scripts/delegate-codex.sh`)

### 2.1 置き場所

`codex exec \` の呼び出し(現行 734 行目付近)の**直前**にブロックを追加し、呼び出し自体を
`env -i "${CODEX_ENV[@]}" codex exec \` に書き換える。

事前スナップショット(`TREE_BEFORE` 等)より後、`write_record "running" …` の前後どちらでもよいが、
**`write_record "running"` の直前**に置くこと(組み立てに失敗しても run record を汚さない)。

### 2.2 許可する固定名

```
PATH HOME USER LOGNAME SHELL TERM LANG TZ TMPDIR
HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy
SSL_CERT_FILE SSL_CERT_DIR NODE_EXTRA_CA_CERTS
```

**未設定の変数は渡さない**(`env -i` に空値で渡すと「空文字が設定済み」になり挙動が変わるため)。
判定は `[ -n "${VAR+x}" ]`(空文字でも設定済みなら渡す)を使う。`-n "$VAR"` にしないこと。

各変数を残す理由をコメントに残す(Issue のスコープ1「削れなかった変数と理由をコメントに残す」):

| 変数 | 理由 |
| --- | --- |
| `PATH` | `codex` 自身と sandbox 内のシェルが `node` / `git` / `npx` を解決するのに要る |
| `HOME` | Codex の認証(`~/.codex/auth.json`)と設定(`~/.codex/config.toml`)の探索元 |
| `USER` / `LOGNAME` / `SHELL` | sandbox 内でシェルを起こすツール群が参照する。無くても動くが削る利得が無い |
| `TERM` | Codex の出力制御。`--color never` を渡しているので実害は無いが未設定だと警告が出る環境がある |
| `LANG` / `LC_*` / `TZ` | 文字コード・日付整形。委託先が生成するログの再現性に効く |
| `TMPDIR` | sandbox が一時ファイルを書く先。既定から外している環境で必要 |
| proxy 系 / `SSL_CERT_*` / `NODE_EXTRA_CA_CERTS` | プロキシ配下・社内 CA 環境で API 到達に必須。このリポジトリでは未設定 |

### 2.3 接頭辞マッチ

`compgen -e`(**エクスポート済み変数名のみ**を列挙する。`compgen -v` はスクリプト内部の
シェル変数まで拾うので使わない)を回して以下を追加する:

- `LC_*` — すべて許可
- `CODEX_*` — 許可。ただし **`CODEX_DELEGATE_*` と `CODEX_HARNESS_MODE` は除外する**
  (このスクリプト自身の制御変数であり、委託先に見せる意味が無い。特に
  `CODEX_DELEGATE_ACK_SECRETS` が子に渡ると「承認済み」の事実が委託先から観測できてしまう)

`case` の並び順に注意。除外パターンを先に書くこと:

```bash
case "$_name" in
  CODEX_DELEGATE_* | CODEX_HARNESS_MODE) continue ;;
  LC_* | CODEX_*) _codex_env_add "$_name" ;;
esac
```

### 2.4 追加の逃げ道: `CODEX_DELEGATE_ENV_ALLOW`

**全バイパスは用意しない**(サニタイズを 1 変数で無効化できると層として意味を失う)。
代わりに**加算のみ**の逃げ道を置く:

- `CODEX_DELEGATE_ENV_ALLOW` … カンマ区切りの変数名。許可リストへ**追加**する
- 未知の環境で必要な変数が出たときに、スクリプトを編集せずに通せる
- 使用時は `>&2` に 1 行警告を出す(自己コピー無効化と同じ作法。明示的な緩和は必ずログに残す)
- 名前の妥当性検査: `[A-Za-z_][A-Za-z0-9_]*` に一致しないトークンは無視して警告する

`CODEX_DELEGATE_ENV_ALLOW` 自身は `CODEX_DELEGATE_*` なので子には渡らない(2.3 の除外に含まれる)。

### 2.5 実装スケッチ

```bash
# ---------- codex exec に渡す環境の組み立て(許可リスト方式) ----------
#
# (ここに「なぜ」を書く。§3 の文言を参照)

CODEX_ENV=()
_codex_env_add() {
  # 未設定は渡さない。空文字は「設定済みの空」として渡す。
  [ -n "${!1+x}" ] || return 0
  CODEX_ENV+=("$1=${!1}")
}

for _name in PATH HOME USER LOGNAME SHELL TERM LANG TZ TMPDIR \
  HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy \
  SSL_CERT_FILE SSL_CERT_DIR NODE_EXTRA_CA_CERTS; do
  _codex_env_add "$_name"
done

for _name in $(compgen -e); do
  case "$_name" in
    CODEX_DELEGATE_* | CODEX_HARNESS_MODE) continue ;;
    LC_* | CODEX_*) _codex_env_add "$_name" ;;
  esac
done

if [ -n "${CODEX_DELEGATE_ENV_ALLOW:-}" ]; then
  echo "delegate-codex: 警告 — CODEX_DELEGATE_ENV_ALLOW により追加の環境変数を委託先へ渡します: $CODEX_DELEGATE_ENV_ALLOW" >&2
  _saved_ifs="$IFS"; IFS=','
  for _name in $CODEX_DELEGATE_ENV_ALLOW; do
    _name="$(printf '%s' "$_name" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$_name" ] && continue
    case "$_name" in
      [A-Za-z_]*) ;;
      *) echo "delegate-codex: 警告 — 変数名として不正なため無視します: $_name" >&2; continue ;;
    esac
    _codex_env_add "$_name"
  done
  IFS="$_saved_ifs"; unset _saved_ifs
fi
unset _name
```

`[A-Za-z_]*` の case グロブは 2 文字目以降を検査しない。厳密にやるなら
`printf '%s' "$_name" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$'` を使う。**こちらを採用する**
(不正な名前が `env` に渡ると `env` 自体がエラーで死に、委託が謎の失敗になるため)。

### 2.6 呼び出しの書き換え

```bash
env -i "${CODEX_ENV[@]}" codex exec \
  --cd "$ROOT" \
  ...
```

`set -u` 下で `"${CODEX_ENV[@]}"` は要素 0 でも安全(bash 4.4 以降。devcontainer は bash 5)。
ただし `PATH` は必ず設定されているため 0 件にはならない。

---

## 3. コメント・ドキュメントの訂正

### 3.1 `.claude/scripts/delegate-codex.sh` 168 行目付近(入口検査1 のコメント)

現行:
```
# 読めるため、委託は機密を委託先へ送りうる。入口の人間確認が唯一の層。
```

**2 点を直す。**

1. 「唯一の層」→ 保護範囲が**ワークツリー内**に限られることを明記する。ホーム配下
   (`~/.config/gh/hosts.yml` / `~/.claude/`)は `find .` の走査対象外であり、この層では守れない
2. 「人間確認」→ 実態は**承認付き再実行**。`CODEX_DELEGATE_ACK_SECRETS=1` を付けた再実行は
   司令塔も Bash から実行でき、人間が見た保証にはならない(permission prompt 頼み)

書き換え後の文面(そのまま採用してよい):

```bash
# ---------- 入口検査1: 機密ファイル ----------
#
# Codex の sandbox は「書き込み」の制限であり、読み取りの deny-list は
# 存在しない(§13 #7 で確定)。.gitignore されていてもディスク上にあれば
# 読めるため、委託は機密を委託先へ送りうる。
#
# この検査が守るのは **ワークツリー内だけ**(find . の走査範囲)。ホーム配下の
# 資格情報(~/.config/gh/hosts.yml・~/.claude/ など)は走査対象外で、sandbox 設定でも
# 読み取りを止められない。環境変数経由の漏れは codex exec の許可リスト(§2)で塞いだが、
# ファイルとして置かれた資格情報は依然として委託先から読める。ここは限界として受け入れ、
# 物理的な隔離(別コンテナ・別ユーザー実行)が要るなら別途判断する。
#
# 検出時の CODEX_DELEGATE_ACK_SECRETS=1 は「人間が確認した」ことの保証ではなく、
# **承認付き再実行**にすぎない。司令塔も Bash から付けて再実行できるため、
# 人間の目が入るかどうかは permission prompt の設定に依存する。
#
# 何を機密とみなすかはプロジェクト固有(§10.2)なので、パターンは
# .claude/codex-denylist.txt に外出しし、ここでは読むだけにする。
```

### 3.2 `.claude/scripts/delegate-codex.sh` 115 行目(usage の環境変数一覧)

`CODEX_DELEGATE_ENV_ALLOW` を追記する:

```
  CODEX_DELEGATE_ACK_SECRETS  機密ファイル検出時の承認(=1 で続行。承認付き再実行であって人間確認の保証ではない)
  CODEX_DELEGATE_ENV_ALLOW    委託先へ追加で渡す環境変数名(カンマ区切り。既定は許可リストのみ)
```

冒頭 49 行目付近の「環境変数:」ブロック(自己コピーの説明)には追記しない。あちらは自己コピー専用の説明。

### 3.3 `.claude/codex-denylist.txt` の冒頭コメント

5 行目「ここが唯一の層。」を差し替える。差し替え後:

```
# .claude/scripts/delegate-codex.sh の入口検査1 がこのファイルを読む。
# Codex の sandbox には読み取りの除外機能が無い(計画 §13 #7 で確定)ため、
# ワークツリーにある機密はそのまま委託先へ送られうる。
#
# ここが守るのは **ワークツリー内だけ**。走査は find . = リポジトリルート配下に限られる。
# ホーム配下の資格情報(~/.config/gh/hosts.yml・~/.claude/ など)は検査対象にすらならず、
# sandbox 設定でも読み取りを止められない。環境変数経由の漏れは delegate-codex.sh の
# 許可リスト(env -i + 明示した変数だけを渡す)で別途塞いである。
```

22 行目・55 行目の `CODEX_DELEGATE_ACK_SECRETS` の説明はそのままでよい(こちらは
「唯一の層」とは書いていない)。

### 3.4 `docs/template-dev/codex-delegation-plan.md` §10.2

節末に段落を 1 つ追加する。既存の本文は書き換えない(判断の記録なので残す)。

追記する内容:

- **保護範囲はワークツリー内に限られる**(2026-08-26 / Issue #23 で明確化)
- `delegate-codex.sh` の入口検査1 は `find .` でリポジトリルート配下だけを走査する。
  ホーム配下の資格情報は検査対象外であり、sandbox にも読み取り除外が無いため守れない
- **環境変数**は別枠で塞いだ。`codex exec` は `env -i` + 許可リストで起動し、
  `LOCAL_GH_TOKEN` / `CLAUDE_CODE_MESSAGING_TOKEN` 等は子プロセスへ渡らない
  (実測: 委託先に `env` を出力させて確認。verification.md 参照)
- 残る限界は「ホーム配下にファイルとして置かれた資格情報」。物理的な隔離が必要なら別チケット

§13 #7 の表(963 行目)にある「**唯一の層**として確定した」も、
「**ワークツリー内の**唯一の層」に直す。

---

## 4. 検証(verification.md に結果を書く)

### 4.1 環境変数が渡っていないことの確認(受け入れ条件2)

read-only モードで 1 本委託し、委託先に `env` を出力させて確認する:

```bash
.claude/scripts/delegate-codex.sh explore "シェルで \`env | cut -d= -f1 | sort\` を実行し、出力をそのまま報告してください。他のファイルは読まないでください。"
```

**確認する項目**(`.harness/codex-runs/[id].log` を見る):
- `LOCAL_GH_TOKEN` / `CLAUDE_CODE_MESSAGING_TOKEN` / `CLAUDE_CODE_SESSION_ID` が**無い**
- `GITHUB_TOKEN` / `GH_TOKEN` が**無い**
- `PATH` / `HOME` が**ある**

### 4.2 3 モードの完走(受け入れ条件1)

- `explore` … 4.1 の実行で兼ねる
- `review` … `.claude/scripts/delegate-codex.sh review main`
- `impl` … 新規に捨てチケット用の steering を作るのは重いので、**既存の完了済み steering を
  再委託しない**。代わりに `.steering/20260826-issue23-env-sanitize/` 自身の tasklist の
  末尾に**検証専用のダミー項目**を置いて 1 本流す…のは委託禁止領域の編集になるため**行わない**。

  **impl の確認方法**: impl 経路で追加されるのは入口検査 4〜6 と出口検査だけで、
  `codex exec` の起動部分は 3 モード共通(同じ 1 箇所)。したがって
  **`env -i` 化の影響は explore / review の完走で確認できる**。
  加えて `bash -n .claude/scripts/delegate-codex.sh` と、impl 経路の入口検査が
  `exit 5`(design.md が draft)で正しく止まることを確認して代替とする:

  ```bash
  # ダミーの draft steering を /tmp 配下ではなくリポジトリ内に作ると入口検査に引っかかるため、
  # 既存の完了済み steering を指定して「design.md は ready なので入口検査を通過し、
  # codex exec の起動直前まで到達する」ことをログで確認する方法は取らない(枠を消費するため)。
  ```

  **上記の判断でよい。実装者は impl の実行を試みず、explore / review の完走をもって
  受け入れ条件1 を満たしたものとし、その旨を verification.md に明記すること。**
  枠の消費を避ける判断であり、司令塔が下した設計判断として記録する。

### 4.3 静的検査

```bash
bash -n .claude/scripts/delegate-codex.sh
npx --no-install prettier --check .steering/20260826-issue23-env-sanitize/ 2>/dev/null || true
```

`/check` は最後に司令塔が回す。

---

## 5. やらないこと(明示)

- `codex exec` 以外の場所(`git` 呼び出し等)の環境サニタイズ — 対象外
- 全バイパス用の環境変数 — §2.4 の通り置かない
- ACK 値のハッシュ化 — Issue のスコープ外
