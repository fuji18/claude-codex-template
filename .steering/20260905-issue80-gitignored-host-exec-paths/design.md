<!-- status: ready -->

# 設計: gitignore 済みのホスト実行経路を禁止領域に入れる(#80)

## 0. 前提の確認(実装前に読む)

- **この作業は Codex に委託しない。** 対象が `.claude/scripts/` / `CLAUDE.md` / `AGENTS.md`
  = 委託禁止領域そのもの。`implement-ticket` の fork(Sonnet)が直接書く
- 変更するのは 4 ファイル + CHANGELOG のみ。**新しいスクリプトもリストファイルも作らない**
  (3 箇所目のリストを作らない方針は `delegate-codex.sh` 冒頭のコメントに明記されている)
- `check-guard-integrity.sh` は `set -uo pipefail`。新しい変数は最初の参照より前で必ず初期化する
- シェルの自動テスト基盤は無い。検証は §5 の手動再現コマンドで行う
- 既存のコメントは**消さずに実態へ合わせる**。このリポジトリのスクリプトは
  「なぜそうなっているか」をコメントで持つ設計になっている

## 1. 中心の判断

### 1-1. `.husky/` はディレクトリ単位で禁止する(個別ファイル列挙をやめる)

`FORBIDDEN_PATHS` の `.husky/pre-commit` / `.husky/prepare-commit-msg` の 2 行を
**`.husky/` の 1 行に置き換える**。#40 が `.claude/scripts/` に適用した原則をそのまま当てる。

これで足りる理由は `forbidden_files()` の実装にある(`delegate-codex.sh` 1137 行付近):

```sh
*/) [ -d "${_p%/}" ] && find "${_p%/}" -type f -print 2>/dev/null ;;
```

`find` は gitignore を見ないので `.husky/_/` 配下も列挙され、`git hash-object` は
追跡外ファイルにもそのまま効く。**列挙の仕組みは変えなくてよい。配列の 1 行だけの問題。**

`check-guard-integrity.sh` の `is_forbidden()`(302 行付近)も `*/)` を前方一致で扱うため、
モード C の `Codex-authored` コミット検査も同じ 1 行で `.husky/_/` まで広がる。
**こちらも変更不要**(判定が厳密に広がるだけで、従来検出していたものは全て検出し続ける)。

### 1-2. `.claude/settings.local.json` は完全一致の 1 行を足す

ディレクトリ(`.claude/`)ごと禁止にはしない。`skills/` `commands/` `agents/` `docs/` への
定型追記まで止まり、委託の余地が過剰に狭まる(#56 の 3 系統の線引きをそのまま維持する)。
`settings.json` の隣に `settings.local.json` を 1 行足すだけにする。

**実在しなくても配列に入れてよい。** `forbidden_files()` の `*)` 分岐は `[ -e "$_p" ]` で
実在検査をするため、無い間は列挙されず前後スナップショットに現れない。
委託先が**新規作成した瞬間に AFTER 側にだけ現れて差分になる** = 期待どおりの検出。

### 1-3. `check-guard-integrity.sh` の新検査は「ラッパが `h` を source しているか」だけを見る

検査 3・4 が見る `.husky/pre-commit` はチェーンの末端。git が起動する入口は
`core.hooksPath` 配下の同名ファイル。ここが `exit 0` に潰されると検査 3・4 は緑のまま通る。

**`h` の内容は検証しない**(Issue のスコープ外。husky のバージョン更新で毎回落ちる)。
見るのは「ラッパが存在し、コメントでない行から `h` を source していること」だけ。

### 1-4. 新検査は既定サブコマンドに置く。`hooks-path` には混ぜない

`hooks-path` は `delegate-codex.sh` 入口検査 5-3 専用で、標準出力をそのまま
エラーメッセージに載せる。ラッパの指摘が混ざると「git hook が無効」という説明と食い違い、
5-3 が本来の理由と違う理由で `exit 3` を返す(Issue の技術メモの指示どおり)。
`hooks-path` は 2.5 で早期 return するので、**検査 4 の直後に置けば自動的に対象外**になる。

### 1-5. `.husky/_` が無いときは検査しない(CI を恒常的に赤くしないため)

CI の `harness-integrity` ジョブは **checkout だけで `npm ci` を回さない**(実測:
`.github/workflows/ci.yml`)。そのジョブでは `.husky/_/` が存在せず `core.hooksPath` も
未設定なのが正常。存在を必須にすると CI が永久に赤くなる。

判定は `core.hooksPath` の実値から取る:

- 未設定 / 実在しない → 検査しない(その状態自体は degraded の D1 が見る担当)
- 値が `.husky` そのもの → 検査しない。husky v8 以前の構成ではラッパが無く
  `.husky/<name>` が直接の入口 = 検査 3・4 がすでに入口を見ている。二重に見ない
- それ以外(husky v9 の `.husky/_` 等)で、かつディレクトリが実在 → ラッパを検査する

## 2. 変更内容(ファイルごと)

### 2-1. `.claude/scripts/delegate-codex.sh`

**(a) `FORBIDDEN_PATHS` 配列(264 行付近)**

```diff
   ".claude/settings.json"
+  ".claude/settings.local.json"
   ".claude/branch-policy.json"
   ".claude/rules/"
-  ".husky/pre-commit"
-  ".husky/prepare-commit-msg"
+  ".husky/"
```

並び順の意図: `.claude/settings.local.json` は `settings.json` の直後(隣接させて、
片方だけ直す事故を減らす)。`.husky/` は元の 2 行があった位置に置く。

**(b) 配列直前のコメント「3 系統」の 1 行(255 行付近)**

```diff
-#   1. 実行される実体      … scripts/ hooks/ settings.json .husky/* .github/workflows/
+#   1. 実行される実体      … scripts/ hooks/ settings.json settings.local.json .husky/ .github/workflows/
```

**(c) 同コメントブロックへ 1 段落を追記**(`.claude/scripts/` をディレクトリにした理由の
説明の直後、`.claude/` 全体を禁止にしない理由の段落の前)。文面:

```
# .husky/ をディレクトリ単位にしたのも同じ理由(Issue #80)。core.hooksPath が指すのは
# .husky/_ で、git が実際に起動するのは .husky/_/pre-commit → .husky/_/h → sh -e
# ".husky/pre-commit" の順。守られていた .husky/pre-commit はチェーンの末端でしかなく、
# 入口側の .husky/_/ は .husky/_/.gitignore = "*" で git 追跡外のため、内容ハッシュ方式の
# この検査以外に見る層が無かった。.husky/_/h は人間や Claude が git commit を叩くたびに
# ホスト上・サンドボックス外で走るので、性質は package.json のライフサイクルと同じ。
# .claude/settings.local.json も同系統(gitignore 済み・hooks を定義できる・次のセッション
# 開始時にホストで走る)なので、settings.json と対で持つ。
```

**(d) 変更しない箇所を確認する(読むだけ)**: `forbidden_files()` / `forbidden_snapshot()` /
`--print-forbidden` は一切触らない。`.husky/` の +20 ファイルは #65 の
`git hash-object --stdin-paths` バッチに乗るため固定費の増加は誤差。

### 2-2. `CLAUDE.md`(委託禁止領域の節)

3 箇所。**配列と食い違いが残らないこと**が受け入れ条件。

**(a) 32 行目**

```diff
-- `.claude/hooks/` / `.claude/settings.json` — PreToolUse hook の定義そのものと、司令塔コンテキストへの注入元(プロンプトインジェクションの経路になり得る)
+- `.claude/hooks/` / `.claude/settings.json` / `.claude/settings.local.json` — PreToolUse hook の定義そのものと、司令塔コンテキストへの注入元(プロンプトインジェクションの経路になり得る)。`settings.local.json` は `.gitignore` 済みで `git diff` に出ないが、hooks を定義できる点は同じで、**次に人間が Claude セッションを開いた瞬間に SessionStart hook としてホストコマンドが走る**。denylist は「次の委託」を止めるが、時間順ではセッション開始のほうが先に来る(#80 / S3)
```

**(b) 35 行目**

```diff
-- `.husky/pre-commit` / `.husky/prepare-commit-msg` — ベンダー中立ガードレールの本体
+- `.husky/` — ベンダー中立ガードレールの本体(`pre-commit` / `prepare-commit-msg`)と、**git が実際に起動する入口**である `.husky/_/`。`core.hooksPath` は `.husky/_` を指し、`.husky/_/pre-commit` → `.husky/_/h` → `sh -e ".husky/pre-commit"` の順で呼ばれる。守られていた 2 ファイルはチェーンの末端でしかなく、入口側は `.husky/_/.gitignore` = `*` で git 追跡外のため全層が同時に素通ししていた。`.husky/_/h` は `git commit` のたびにホスト上・サンドボックス外で走る(#80 / S1)
```

**(c) 46 行目(3 系統の 1)**

```diff
-1. **実行される実体** — `.claude/scripts/` / `.claude/hooks/` / `.claude/settings.json` / `.husky/*` / `.github/workflows/`
+1. **実行される実体** — `.claude/scripts/` / `.claude/hooks/` / `.claude/settings.json` / `.claude/settings.local.json` / `.husky/` / `.github/workflows/`
```

### 2-3. `AGENTS.md` §4(`kickoff:delegation-forbidden-paths` マーカー内)

マーカー内のバックティック囲みは `delegate-codex.sh` が起動時に抽出してマージするため、
**ここの表記もそのまま検査対象になる**。委託先向けの文体(です・ます)を保つ。

**(a) `.claude/hooks/` の行(150 行目)**

```diff
-- `.claude/hooks/` / `.claude/settings.json` — Claude 側のフック定義とその実体です。司令塔のコンテキストへ注入される内容の出所でもあります
+- `.claude/hooks/` / `.claude/settings.json` / `.claude/settings.local.json` — Claude 側のフック定義とその実体です。司令塔のコンテキストへ注入される内容の出所でもあります。`settings.local.json` は git 追跡外ですが、新規作成すると次に人間が Claude を起動した時点でホスト側のコマンドが走ります
```

**(b) `.husky/` の行(153 行目)**

```diff
-- `.husky/pre-commit` / `.husky/prepare-commit-msg` — ベンダー非依存のガードレール本体
+- `.husky/` — ベンダー非依存のガードレール本体です。git が実際に起動するのは `.husky/_/` 配下のラッパで、そこから `.husky/pre-commit` が呼ばれます。`.husky/_/` は git 追跡外ですが、内容ハッシュで照合されるため書き換えれば検出されます
```

### 2-4. `.claude/scripts/check-guard-integrity.sh`(新しい検査 5)

`if [ "$USES_HUSKY" = yes ]` ブロックの中、**検査 4 の `for h in ...` ループの直後**、
ブロックを閉じる `fi` の直前に挿入する。挿入するコードは次のとおり(そのまま使う):

```sh
  # --- 5) git が実際に起動するラッパが生きているか ---
  # 検査 3・4 が見る .husky/<name> はチェーンの**末端**。git が起動するのは core.hooksPath
  # (husky v9 では .husky/_)配下の同名ファイルで、それが h を source し、h が最後に
  # sh -e ".husky/<name>" を呼ぶ。.husky/_/ は .husky/_/.gitignore = "*" で git 追跡外の
  # ため、ここを exit 0 の 2 行に潰しても検査 3・4 は緑のまま通っていた(#80 / S1)。
  #
  # h の中身は検証しない。husky のバージョン更新で毎回落ちるため(#80 スコープ外)。
  # 見るのは「ラッパが存在し、コメントでない行から h を source しているか」だけ。
  #
  # 検査しない構成が 2 つある:
  #   - core.hooksPath が未設定 / 実在しない … CI の harness-integrity は checkout だけで
  #     npm ci を回さないため .husky/_ が無いのが正常。必須にすると恒常的に赤くなる
  #     (この状態自体を見るのは degraded の D1 の担当)
  #   - core.hooksPath が .husky そのもの … husky v8 以前はラッパが無く .husky/<name> が
  #     直接の入口 = 検査 3・4 がすでに入口を見ている。二重に見ない
  #
  # hooks-path サブコマンドはここへ来ない(2.5 で早期 return する)。5-3 は標準出力を
  # そのままエラーメッセージに載せるため、ラッパの指摘が混ざると本来の理由と食い違う。
  WRAPPER_DIR="$(git config --get core.hooksPath 2>/dev/null || true)"
  if [ -n "$WRAPPER_DIR" ] && [ "$WRAPPER_DIR" != ".husky" ] && [ -d "$WRAPPER_DIR" ]; then
    # 呼び出しとみなすのは「コメントでない行」からの source(`.` または `source`)で、
    # 対象が /h で終わるもの。単なる文字列一致だと、source 行をコメントアウトしても
    # 通ってしまう(検査 4 の INVOKE_RE と同じ考え方)。
    WRAPPER_RE='^[^#]*(source|\.)[[:space:]]+[^#]*/h"?[[:space:]]*$'
    for _wh in pre-commit prepare-commit-msg; do
      case "$_wh" in
        pre-commit) covers="git commit / git commit --amend" ;;
        *)          covers="git revert / git cherry-pick" ;;
      esac
      if [ ! -f "$WRAPPER_DIR/$_wh" ]; then
        note "$WRAPPER_DIR/$_wh が存在しない。git が起動する入口が無いため .husky/$_wh は一度も呼ばれず、保護ブランチ上の $covers が素通しになる"
      elif ! grep -qE "$WRAPPER_RE" "$WRAPPER_DIR/$_wh"; then
        note "$WRAPPER_DIR/$_wh が husky のディスパッチャ(h)を source していない。.husky/$_wh が呼ばれないまま保護ブランチ上の $covers が通る($WRAPPER_DIR は git 追跡外なので git diff にも出ない)"
      fi
    done
  fi
```

さらに**ファイル冒頭のサブコマンド説明(20〜31 行目付近)は変更しない**。検査の一覧を
持っているコメントではないため、追記すると別の場所と二重管理になる。

### 2-5. `docs/template-dev/CHANGELOG.md`

既存の書式に合わせて 1 エントリ追記する(最新が上か下かは**必ず既存ファイルを見て合わせる**)。
内容は「委託禁止領域に `.husky/`(ディレクトリ単位)と `.claude/settings.local.json` を追加。
`check-guard-integrity.sh` に `core.hooksPath` 配下のラッパ検査を追加(#80)」の主旨。

## 3. やらないこと(スコープガード)

- `forbidden_files()` / `forbidden_snapshot()` / `--print-forbidden` の実装変更
- `check-forbidden-paths-doc.sh` の双方向化(C1/D1 の別チケット)
- `.husky/_/h` の内容検証、`node_modules/` の禁止領域化(#82)、`.harness/codex-runs/` の扱い
- `hooks-path` サブコマンドの挙動変更

## 4. 既知の落とし穴

- **`check-forbidden-paths-doc.sh` はこの変更の記述漏れを検出できない。** 検査は
  「配列 → CLAUDE.md」の片方向で、`grep -qF -- ".husky/"` は `.husky/pre-commit` という
  古い記述にも部分一致する。**手順 2-2 を忘れても CI は緑のまま**なので目視で確認する
- `.claude/settings.local.json` は実在しないため、同スクリプトの `[ -e "$_p" ] || continue` で
  照合対象から外れる。CLAUDE.md への追記は機械検査では担保されない
- `.husky/_` は `npm ci` が再生成する。生成内容は決定的だが、**impl 委託の実行中に人間が
  `npm ci` を叩くと出口検査が誤爆しうる**(B1 と同系統。運用上の注意として残す)

## 5. 検証(実装後に必ず回す)

### V1: 配列と出力

```bash
bash .claude/scripts/delegate-codex.sh --print-forbidden | grep -E '^(\.husky/|\.claude/settings\.local\.json)$'
# → 2 行とも出ること
bash .claude/scripts/delegate-codex.sh --print-forbidden | grep -E '^\.husky/(pre-commit|prepare-commit-msg)$'
# → 1 行も出ないこと(配列からは消えている。AGENTS.md 由来の抽出にも残っていないこと)
```

### V2: ラッパが列挙対象に入ったか(`forbidden_files()` の `*/)` 分岐と同じコマンド)

```bash
find .husky -type f -print | grep -E '_/(pre-commit|prepare-commit-msg|h)$'
# → 3 行出ること
```

### V3: `check-guard-integrity.sh` が無音化を検出するか

```bash
cp .husky/_/pre-commit /tmp/_pc.bak
printf '#!/usr/bin/env sh\nexit 0\n' > .husky/_/pre-commit
bash .claude/scripts/check-guard-integrity.sh; echo "exit=$?"   # → 指摘 1 行 + exit=1
cp /tmp/_pc.bak .husky/_/pre-commit && rm /tmp/_pc.bak
bash .claude/scripts/check-guard-integrity.sh; echo "exit=$?"   # → 無出力 + exit=0
```

`prepare-commit-msg` でも同じことを 1 回やる(ファイル名だけ差し替え)。
**復元を忘れないこと。** 忘れると以降のコミットが素通しになる。

### V4: 静的検査と既存 CI 相当

```bash
bash -n .claude/scripts/delegate-codex.sh
bash -n .claude/scripts/check-guard-integrity.sh
bash .claude/scripts/check-forbidden-paths-doc.sh; echo "exit=$?"   # → 無出力 + exit=0
npx prettier --check CLAUDE.md AGENTS.md docs/template-dev/CHANGELOG.md
```

### V5: 出口検査の再現テスト(受け入れ条件 2・3)

`codex` CLI がこの環境に無い場合、`delegate-codex.sh` は入口検査で `exit 3` を返して
出口検査まで到達しない。**その場合はスタブで代替する**(本物の委託は行わない):

```bash
STUB="$(mktemp -d)"
cat > "$STUB/codex" <<'EOS'
#!/usr/bin/env bash
# 委託先が禁止領域を書き換えたことにする
printf '#!/usr/bin/env sh\nexit 0\n' > .husky/_/pre-commit
echo '{"type":"item.completed"}'
exit 0
EOS
chmod +x "$STUB/codex"
PATH="$STUB:$PATH" bash .claude/scripts/delegate-codex.sh impl .steering/20260905-issue80-gitignored-host-exec-paths
echo "exit=$?"   # → 出口検査が .husky/_/pre-commit の差分を報告し exit=2
```

終了後に `.husky/_/pre-commit` を `npm ci` か手元のバックアップで**必ず復元する**
(`git checkout` では戻らない。追跡外のファイル)。
`.claude/settings.local.json` 版はスタブの 1 行を
`printf '{}' > .claude/settings.local.json` に差し替えて同じ手順を踏み、
**確認後にそのファイルを削除する**。

**スタブでも到達しない場合**(入口検査が別の理由で止まる等)は、**深追いせず
V1 / V2 の列挙レベルの確認をもって代替とし、その事実と実際の終了コード・停止理由を
`verification.md` に記録して報告する**。ここで新しい設計判断はしない。
