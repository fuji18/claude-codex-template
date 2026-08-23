# 設計: 段階0 の残件

> **実装者への注意**: 判断はすべてここで下してある。迷ったら推測せず停止して報告すること。
> Codex CLI は導入済み・認証済みだが、**このタスクで `delegate-codex.sh` に実際の委託をさせてはいけない**(枠を消費する)。回帰確認は入口検査1 で止まるところまでで行う(§D7)。

---

## D1. データガバナンス判断(§10.2)

**判断: このリポジトリでは Codex 委託を使う。**

根拠: 本リポジトリは OSS のテンプレート本体であり、顧客コード・個人情報・本番シークレットを含まない。委託で送られるのはテンプレート自身の構成ファイルと開発記録に限られる。

**送信してよい範囲**: リポジトリ配下のトラッキング対象ファイルすべて(`docs/` / `.claude/` / `.codex/` / `.husky/` / `.github/` / `src/` / ルートの設定ファイル)。

**送信してはいけないもの**(= 委託前に検出して止める):

| 対象 | 理由 |
| --- | --- |
| `.env` / `.env.*` | 実行時シークレットの標準的な置き場所 |
| `*.pem` / `*.key` / `id_rsa*` / `id_ed25519*` | 秘密鍵 |
| `credentials*` / `*.p12` / `*.pfx` | 資格情報 |
| `.claude/settings.local.json` | ローカル設定。トークンが入りうる(manifest の `never` にある = 個人環境固有) |
| `.harness/` 配下 | 過去の委託ログ。再送は無意味かつ巨大(1 回で 115 KB) |

`.example` / `.sample` / `.template` で終わるものは**中身がプレースホルダなので対象外**(現行実装の除外を維持する)。

`.harness/` は denylist ではなく **prune(走査除外)** で扱う(検出して人間に確認させる対象ではなく、単に読ませたくないだけのため)。

---

## D2. 送信禁止パスの単一ソース: `.claude/codex-denylist.txt`

### D2-1. ファイルを新規作成する

パス: `.claude/codex-denylist.txt`

```
# Codex 委託の送信禁止パターン(単一ソース)。
#
# .claude/scripts/delegate-codex.sh の入口検査1 がこのファイルを読む。
# Codex の sandbox には読み取りの除外機能が無い(計画 §13 #7 で確定)ため、
# ワークツリーにある機密はそのまま委託先へ送られうる。ここが唯一の層。
#
# 書式:
#   - 1 行 1 パターン。空行と # 始まりの行は無視される
#   - パターンに / を含む   → リポジトリルートからのパス一致(find -path "./PATTERN")
#   - パターンに / を含まない → ファイル名一致(find -name "PATTERN")
#   - シェルの glob がそのまま使える(* ? [])
#
# 末尾が .example / .sample / .template のファイルは常に対象外(プレースホルダ)。
# node_modules / .git / .harness は走査自体をしない。
#
# このファイルが無い、または有効パターンが 0 件のときは委託を止める(フェイルクローズ)。
# 根拠: docs/template-dev/codex-delegation-plan.md §10.2

# --- 実行時シークレット ---
.env
.env.*

# --- 鍵・資格情報 ---
*.pem
*.key
id_rsa*
id_ed25519*
credentials*
*.p12
*.pfx

# --- ローカル固有設定(トークンが入りうる) ---
.claude/settings.local.json
```

### D2-2. `delegate-codex.sh` の入口検査1 を差し替える

**差し替える範囲**: `# ---------- 入口検査1: 機密ファイル ----------` のコメントブロック直後から、`SENSITIVE` を組み立てて `if [ -n "$SENSITIVE" ]; then ... fi` が閉じるまで。**その前の入口検査0 と、後の入口検査2・3 は触らない。**

冒頭のコメントブロックは、denylist を単一ソースにしたことが分かる形に書き換える:

```bash
# ---------- 入口検査1: 機密ファイル ----------
#
# Codex の sandbox は「書き込み」の制限であり、読み取りの deny-list は
# 存在しない(§13 #7 で確定)。.gitignore されていてもディスク上にあれば
# 読めるため、委託は機密を委託先へ送りうる。入口の人間確認が唯一の層。
#
# 何を機密とみなすかはプロジェクト固有(§10.2)なので、パターンは
# .claude/codex-denylist.txt に外出しし、ここでは読むだけにする。
```

置き換える本体:

```bash
DENYLIST=".claude/codex-denylist.txt"

if [ ! -f "$DENYLIST" ]; then
  echo "delegate-codex: $DENYLIST がありません。機密チェックが成立しないため委託しません。" >&2
  exit "$EX_UNAVAIL"
fi

# find の式を denylist から組み立てる。
# / を含むパターンはパス一致、含まないパターンはファイル名一致。
FIND_EXPR=()
while IFS= read -r _line || [ -n "$_line" ]; do
  _line="${_line%%#*}"
  _line="$(printf '%s' "$_line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -z "$_line" ] && continue
  [ ${#FIND_EXPR[@]} -gt 0 ] && FIND_EXPR+=(-o)
  case "$_line" in
    */*) FIND_EXPR+=(-path "./$_line") ;;
    *) FIND_EXPR+=(-name "$_line") ;;
  esac
done <"$DENYLIST"

if [ ${#FIND_EXPR[@]} -eq 0 ]; then
  echo "delegate-codex: $DENYLIST に有効なパターンがありません。委託しません。" >&2
  exit "$EX_UNAVAIL"
fi

# -maxdepth は付けない。深い階層の .env を見逃すため。
# 代わりに node_modules / .git / .harness を prune して走査量を抑える。
SENSITIVE="$(
  find . \
    \( -name node_modules -o -name .git -o -name .harness \) -prune -o \
    \( "${FIND_EXPR[@]}" \) -type f -print 2>/dev/null |
    grep -Ev '\.(example|sample|template)$' |
    head -20
)"

if [ -n "$SENSITIVE" ]; then
  cat >&2 <<'MSG'
delegate-codex: ワークツリーに機密の可能性があるファイルがあります。

Codex の sandbox には読み取りの除外機能が無いため、これらは委託先へ
送られうる。内容を確認し、問題なければ承認して再実行してください:

  CODEX_DELEGATE_ACK_SECRETS=1 .claude/scripts/delegate-codex.sh ...

該当:
MSG
  echo "$SENSITIVE" | sed 's/^/  /' >&2
  if [ "${CODEX_DELEGATE_ACK_SECRETS:-}" != "1" ]; then
    exit "$EX_FAIL"
  fi
fi
```

**注意点(逸脱しないこと)**:

- 変数名は `_line` にする(このスクリプトは `set -u` なのでローカル変数の衝突を避ける)
- `FIND_EXPR` は **bash 配列**。shebang は `#!/bin/bash` なので使ってよい
- フェイルクローズの終了コードは **`EX_UNAVAIL`(3)**。`EX_FAIL`(2)ではない。「委託の環境が整っていない」であって「タスクが失敗した」ではないため。入口検査0(`find` 不在)と同じ扱いに揃える
- **機密が見つかったときの終了コードは `EX_FAIL`(2)のまま**変えない(現行どおり)
- `head -20` と `.example` 除外は現行の挙動を維持する
- 入口検査0 のコマンド一覧(`find grep sed head tail tr`)は変更不要

### D2-3. `.claude/template-manifest.json` を更新する

- `owned` から **`".codex/prompts/"` を削除**する(D4 の結論: そのディレクトリは Codex CLI に存在しない)
- `merge` に **`".claude/codex-denylist.txt"` を追加**する。`owned` ではない理由: 何を機密とみなすかはプロジェクト固有(§10.2)で、テンプレート側の一覧で上書きするとプロジェクトが足した行が消える。`branch-policy.json` と同じ扱い
- 追加位置は `merge` 配列の `".claude/branch-policy.json"` の直後

---

## D3. 認証キャッシュ(`~/.codex/auth.json`)の永続化

**判断: devcontainer の `mounts` は張らない。リビルド後は `codex login` で入り直す運用にする。**

根拠:

1. **既存の一貫性**: Claude Code の認証(`~/.claude`)も同じくコンテナ内にしか無く、リビルド後に入り直す運用で通っている(`README.md` の初回セットアップ)。Codex だけ named volume を張ると、認証の寿命がツールごとに違うという分かりにくさが増える
2. **消し忘れのリスク**: OAuth 資格情報を named volume に置くと、コンテナを捨てても資格情報だけが残る。devcontainer を作り直す動機の一つが「環境を綺麗にする」ことなので、逆行する
3. **回復コストが小さい**: リビルドは稀で、回復は `codex login` 1 コマンド。`post_create.sh` が未認証を検出して案内する実装は `c5331c8` で入っている

**実装**: `README.md` の初回セットアップ手順に Codex の認証を追記する。追記先は `post_create.sh` に触れている箇所(現行 25 行目付近の「`post_create.sh` が Claude Code のインストールと GitHub 認証を自動で行う」の項目)。その直後に子項目として次を足す:

```markdown
   - Codex CLI も同時に入る(Codex 併用ハーネス用)。**認証は初回と devcontainer リビルドのたびに手動**で `codex login` を実行する(通らなければ `codex login --device-auth`)。`~/.codex` はコンテナ内にしか無く、永続化していない(判断の根拠: `docs/template-dev/codex-delegation-plan.md` §11)
   - `--with-api-key` は使わないこと(ChatGPT Plus 枠ではなく API 従量課金になる)
```

既存の箇条書きのインデント・記法に合わせること。**README の他の節は触らない。**

---

## D4. §13 #4 の結論: `.codex/prompts/` は存在しない

**実機調査の結果(Codex CLI v0.149.0、2026-08-23)**:

- `codex --help` のサブコマンド一覧に `prompts` は無い。あるのは `plugin` / `skills`(内部)
- `~/.codex/` の実体に `prompts/` は無く、**`skills/` と `plugins/` がある**
- ネイティブバイナリの文字列走査で、プロンプト置き場を示す `.codex/prompts` / `CODEX_HOME/prompts` は **1 件も出ない**
- 一方 **`CODEX_HOME/skills` と `/.codex/skills` の両方が出る**。project スコープのレイヤ自体は存在する

**結論: カスタムプロンプトの仕組みは skills に置き換わっている。** `.codex/prompts/` を前提にした記述はすべて誤り。project スコープ(`.codex/skills/`)は**存在するが実機で動作確認していない**。

**帰結(このタスクでやること)**:

- `template-manifest.json` の `owned` から `.codex/prompts/` を削除する(D2-3)
- 計画文書の §13 #4 行を下記 D6 のとおり書き換える
- **`.codex/skills/` の実機確認は段階5(#7)に送る。**このタスクでは作らない

---

## D5. §13 #6 の結論: `resetAt` は `codex exec --json` から取れない

**実機ログでの判定(2026-08-23、成功した委託 1 回、`.harness/codex-runs/20260823-024419.log` = 114,919 B)**:

- ログに出たイベント型は **5 種のみ**: `thread.started` / `turn.started` / `item.started` / `item.completed` / `turn.completed`
- `turn.completed` が持つのは `usage` だけ:
  `{"type":"turn.completed","usage":{"input_tokens":109096,"cached_input_tokens":79872,"cache_write_input_tokens":0,"output_tokens":1119,"reasoning_output_tokens":139}}`
- **`resets_at` / `rate_limit` を含む文字列は 1 件も無い**(`grep` で確認)
- バイナリには `AccountRateLimitsUpdated` というイベント名があるが、これは **app-server プロトコル**(`codex app-server`)側の通知で、`codex exec` の JSON ストリームには流れない

**結論: 成功時のストリームには上限情報が一切乗らない。** `resetAt` が埋まりうるのは上限に当たったときのエラー出力だけで、それは上限に到達しないと確かめられない(意図的に到達させるのは枠を捨てることになるのでやらない)。

**帰結: `delegate-codex.sh` は変更しない。** 現行実装(ログ中の `"resets_at"` を拾えれば埋め、拾えなければ `null`)は、この結論のもとで**そのまま正しい挙動**である。既定は §12.6 のフォールバック(「待つ」判断を人間に委ねる)に確定する。

---

## D6. 文書の更新(文言を確定させてある)

### D6-1. `docs/template-dev/codex-delegation-plan.md`

**(a) §10.2 の末尾**(「送信は取り返しがつかない。他のリスクと違い**事後の検収で回収できない**唯一の項目」の箇条書きの直後)に、次の小節を追加する:

```markdown
**このリポジトリの判断(2026-08-23)**: テンプレート本体は OSS で顧客コード・個人情報・本番シークレットを含まないため、**Codex 委託を使う**。送信してよいのはトラッキング対象ファイルすべて。送信禁止の一覧は **`.claude/codex-denylist.txt`** を単一ソースとし、`delegate-codex.sh` の入口検査1 がそれを読む(ファイルが無い / 有効パターンが 0 件なら委託を止める = フェイルクローズ)。`.harness/` 配下(過去の委託ログ)は検出対象ではなく走査除外で扱う。
```

**(b) §11 の箇条書き**のうち、末尾にある「**リビルドの副作用と恒久化(2026-08-23)**」の項目の最後の一文
「**認証キャッシュの永続化は未決**(mounts を張るか毎回 `--device-auth` で入り直すか)」
を、次に**置き換える**:

```markdown
**認証キャッシュは永続化しない(決定)**。`mounts` を張らず、リビルド後は `codex login` で入り直す。理由は (1) Claude Code の認証も同じくコンテナ内にしか無く運用が通っている、(2) OAuth 資格情報が named volume に残り続けるのは devcontainer を作り直す動機に逆行する、(3) 回復が 1 コマンドで済む。手順は `README.md` に明記した
```

**(c) §11 の箇条書きの末尾**に、段階0 の完了を記録する項目を追加する(「本ドキュメントは調査時点の〜」の**直前**):

```markdown
- **段階0 完了(2026-08-23)**: 契約・CLI 導入・認証・sandbox・データガバナンス判断(§10.2)・§13 の実機検証がすべて片付いた。判定は**続行**(下記の価値判定)。次は段階3([#5](https://github.com/fuji18/claude-codex-template/issues/5))
```

**(d) §13 の表**の #4 行と #6 行を差し替える:

| 列 | #4 の新しい内容 |
| --- | --- |
| 確かめること | `.codex/prompts/` の project スコープ対応 |
| 結果 | ❌ **そもそも存在しない(2026-08-23 実機)**。v0.149.0 に `prompts` サブコマンドは無く、`~/.codex/` にも `prompts/` は無い。ネイティブバイナリの文字列走査でも `.codex/prompts` / `CODEX_HOME/prompts` は 0 件。**カスタムプロンプトの仕組みは skills に置き換わっている**(`CODEX_HOME/skills` と `/.codex/skills` の両方が出る)。project スコープのレイヤ自体は存在するが**実機の動作確認は未実施** |
| 崩れた場合の代替 | 段階5(#7)で `.codex/skills/` を実機確認し、動かなければ `docs/playbook/codex-standalone.md` に降格(§7.3) |

| 列 | #6 の新しい内容 |
| --- | --- |
| 確かめること | レート上限のリセット単位(5 時間枠 / 週次)と `resetAt` の取得可否 |
| 結果 | ✅ **単位は確定**(5 時間枠 + 週次)。**`resetAt` は `codex exec --json` からは取れないと確定(2026-08-23 実機)**。成功した委託 1 回(114,919 B)のイベント型は `thread.started` / `turn.started` / `item.started` / `item.completed` / `turn.completed` の 5 種のみで、`turn.completed` が持つのは `usage` だけ。`resets_at` / `rate_limit` は 0 件。バイナリにある `AccountRateLimitsUpdated` は app-server プロトコル側の通知で exec には流れない |
| 崩れた場合の代替 | **これを採用**: 「待つ」判断を人間に委ねる(§12.6)。スクリプトの `resets_at` 抽出はそのまま残す(上限時のエラー出力に出れば埋まる。出なければ `null`) |

**(e) §13 の表の直後の「現状」段落**を次に差し替える:

```markdown
**現状(2026-08-23 更新): #1〜#3・#5〜#7 が確定し、#4 は「対象が存在しない」という形で決着した。** 未確認として残るのは `.codex/skills/` の project スコープが実際に効くか(段階5 / [#7](https://github.com/fuji18/claude-codex-template/issues/7))だけである。
```

**(f) §7.3** に `.codex/prompts/` への言及があれば、`.codex/skills/`(段階5 で実機確認)に読み替えた注記を足す。**言及が無ければ何もしない**(勝手に節を作らない)。

### D6-2. `docs/template-dev/codex-harness.html`

同じ内容を HTML 側にも反映する。**新しい節は作らず、既存の該当箇所だけを直す**:

1. 段階0 のカード(§10 相当): 「残るのはデータガバナンス判断と環境の恒久化」といった未了の記述を**完了**に更新し、判定「続行 → 段階3(#5)へ」を明記する
2. §13 相当の表があれば #4 / #6 の行を D6-1(d) と同じ結論に更新する
3. §12.4(発見の記録)に、認証永続化の決定(D3)を 1 項目として追加する
4. データガバナンス判断(D1)と `.claude/codex-denylist.txt` への参照を、§10.2 に対応する箇所に追加する

**HTML の既存のマークアップ・クラス名・見出し階層に合わせること。** 独自のスタイルを持ち込まない。該当箇所が見つからない項目は**でっち上げず、その旨を報告に書く**。

### D6-3. `README.md`

D3 のとおり。**追記のみで、他は触らない。**

---

## D7. 回帰確認(Codex を呼ばずに行う)

`.claude/scripts/delegate-codex.sh` は入口検査1 で止まれば Codex に到達しない。以下はすべてスクラッチ領域で行い、**リポジトリを汚さない**(作った一時ファイルは必ず消す)。

`explore` の target は何でもよい(検査1 より後には進まない)。

| # | 手順 | 期待 |
| --- | --- | --- |
| 1 | `.claude/codex-denylist.txt` を一時退避して `explore x` | exit **3**、「codex-denylist.txt がありません」 |
| 2 | denylist をコメント行だけの内容に一時差し替えて `explore x` | exit **3**、「有効なパターンがありません」 |
| 3 | `touch .env` して `explore x` | exit **2**、該当に `./.env` が出る |
| 4 | 3 の状態で `CODEX_DELEGATE_ACK_SECRETS=1 ... explore x` | 検査1 を**通過**して先へ進む(検査2・3 or CLI 段階の出力になる。**Codex への実委託まで行かせないよう、確認できたら Ctrl-C 相当で止めるのではなく、AGENTS.md を一時退避して検査2 で落とす**) |
| 5 | `touch .env.example` だけ置いて `explore x` | 検出**されない** |
| 6 | `mkdir -p a/b/c/d && touch a/b/c/d/.env` して `explore x` | exit **2**、該当に `./a/b/c/d/.env` が出る(`-maxdepth 3` 撤廃の確認) |
| 7 | `.claude/settings.local.json` が存在する環境で `explore x` | exit **2**、該当に出る(パス一致パターンの確認) |

**#7 は `.claude/settings.local.json` が実在する場合のみ確認する。** 無ければ一時的に作って確認し、必ず消す(manifest の `never` = 個人環境固有のファイルなので、無かった環境に残さない)。

終わったら **`git status` がクリーン**(意図した変更以外が無い)ことを確認する。

## D8. 品質チェック

- `npm run lint`
- `npm run format:check`(失敗したら `npm run format`)
- `npm run test`(既存テストがあれば)
- shellcheck はこの環境に無いので実行しない

## D9. コミット

変更をまとめて 1 コミットにする。メッセージ:

```
feat: Codex 委託の送信禁止パスを単一ソース化し段階0 を完了する
```

本文に D1 / D3 / D4 / D5 の決定を要約する。**PR の作成・push は司令塔が行うので、実装者はコミットまでで止める。**
