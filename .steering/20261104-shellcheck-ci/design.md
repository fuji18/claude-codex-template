# design: ci.yml の harness-integrity に ShellCheck ステップを足す

<!-- status: ready -->

## 置き場所

`harness-integrity` ジョブの末尾に足す。理由:

- 依存のインストールが要らない(`ubuntu-latest` に shellcheck が同梱されている)。`quality` ジョブに置くと
  `npm ci` を待つことになる
- 同じジョブに既に `bash -n` があり、**シェルの機械的検査がそこに集まる**
- `quality` の lint / テスト失敗で飛ばされない(ジョブが独立しているので fail-fast の影響を受けない)

## コマンド

```bash
shellcheck -x -P SCRIPTDIR --severity=warning "${FILES[@]}"
```

| 指定 | 理由 |
| --- | --- |
| `-x` | source された共有ライブラリ(`lib-*.sh`)も追う |
| `-P SCRIPTDIR` | `# shellcheck source=lib-github.sh` をスクリプト自身のディレクトリ基準で解決する。呼び出しはリポジトリルート相対(`. .claude/scripts/lib-github.sh`)で書かれているため、これが無いと 9 件すべてが「追えない(SC1091)」で埋まる |
| `--severity=warning` | note には**意図して使っている書き方**が多い(`A && B || C` = SC2015 が 5 件、SC1091 が 9 件、SC2016 / SC2001 / SC2317 = 誤検知寄り)。全部拾うと鳴りっぱなしになり「赤いのが普通」のゲートは誰も読まなくなる |

**深刻度の線は下げない。** 個別に抑止したいものは、その場に `# shellcheck disable=SCxxxx` と理由を書く
(どこで何を許したかがコード側に残る)。

## 対象ファイルの選定

```bash
mapfile -t FILES < <(git ls-files | grep -E '\.sh$|^\.husky/[a-z-]+$' | grep -v '^\.steering/')
```

- **git 追跡下だけ**を見る。`.husky/_/` は husky の生成物で追跡外、未追跡の作業ディレクトリも拾わない
- `.husky/pre-commit` / `.husky/prepare-commit-msg` は**拡張子が無い**ので別に拾う
- `.steering/` は過去の作業記録(再現用スクリプト)なので修正対象にしない
- 空になったら `exit 1`(`git ls-files` が壊れた状態で「指摘なし」に倒さない)

## ツールが無いときの扱い

`command -v shellcheck` が無ければ `::error` を出して `exit 1`。
**フェイルオープンにしない** —— ハーネスの他の層(hook・preflight)は「止めない方が害が小さい」ので
フェイルオープンだが、**CI のゲートは止めるのが仕事**で、黙って通ると層が消えたことに誰も気づかない。

## 既存の指摘 11 件の直し方

`--severity=warning` で出るのは 11 件。**ガードレールの挙動は変えない**ことを最優先にする。

| 件数 | コード | ファイル | 直し方と理由 |
| --- | --- | --- | --- |
| 2 | SC2164 | `.claude/hooks/session-start.sh` / `.codex/hooks/session-start.sh` | `cd "${CLAUDE_PROJECT_DIR:-.}" \|\| exit 0`。**フェイルオープン**(何も注入せず終わる)。違う場所で動いて見当違いの現在地を注入する方が害が大きい。`check-implementation-phase.sh` が既にこの形 |
| 2 | SC2164 | `harness-mode.sh` / `check-guard-integrity.sh` | `if [ -n "$ROOT" ]; then cd "$ROOT" 2>/dev/null \|\| true; fi`。**現在地のまま続ける**既存の挙動を変えずに明示するだけ。`A && B` のままだと SC2015 に化けるので `if` にする |
| 4 | SC2164 | `test-sync-template.sh` | `cd "$T" \|\| exit 1` / `cd "$P" \|\| exit 1`。テストは**違う場所で検査すると結果が無意味**になるので止める |
| 1 | SC2034 | `autopilot-preflight.sh` | 未使用の `OPEN=` を削除。値は同じブロックの `SUM` に入っている(`grep -n OPEN` で他に参照が無いことを確認) |
| 2 | SC2148 | `.husky/pre-commit` / `.husky/prepare-commit-msg` | 先頭に `# shellcheck shell=sh` を足す。husky はこの 2 つを **shebang 無しの `sh -e`** で実行するので、方言を明示するのが正しい。コメント 1 行なので実行時の挙動は変わらない(`bash -n` と `check-guard-integrity.sh` で確認) |

## 検証

ホストに shellcheck が無いため、手元のビルド済み devcontainer イメージに
`apt-get install shellcheck`(0.9.0)したものをイメージとして固め、その中で回す。

- `ci.yml` の ShellCheck ステップと**同じコマンド**を実行して `exit 0` を確認する
- 修正前のベースラインも同じコマンドで測る(11 件 → 0 件)
- 修正がガードレールを壊していないことを、既存の検査の再実行で確認する:
  `bash -n`(CI と同じ範囲)/ `check-guard-integrity.sh` / `check-forbidden-paths-doc.sh` /
  `check-manifest-coverage.sh` / `test-sync-template.sh` / `test-route.sh` / `harness-mode.sh` /
  SessionStart hook の実行 / `20261103-trusted-bots-union` の検証スイート
- `ci.yml` は prettier で検査する(YAML として壊れていればここで落ちる)

---

## 第2ラウンド: devcontainer にも入れ、判定を 1 箇所に寄せる

第1ラウンドでは `ci.yml` に検査をインラインで書いた。**ローカルに shellcheck が無いまま**だったので、
申し送りに「devcontainer に入れるかは別途判断」と残した —— ユーザーの判断は「入れる」。

ただし **「ローカルに入れる」だけでは足りない。** CI だけが対象の選定と引数を知っている状態で
手元にツールを入れると、「手元では緑なのに CI で落ちる(逆もある)」が起きる。手元で先に見ることの
意味が消え、このリポジトリで繰り返し起きている事故(判定が 2 箇所にある)と同じ形になる。
そこで **検査の実体をスクリプトに一本化し、CI と手元の両方がそれを呼ぶ**形にする。

### 1) `.claude/scripts/check-shell.sh`(新規)= 唯一の実行経路

対象の選定(git 追跡下の `*.sh` + `.husky/pre-commit` / `.husky/prepare-commit-msg`、
`.husky/_/` と `.steering/` を除外)と引数(`-x -P SCRIPTDIR --severity=warning`)をここに集約する。

| 終了コード | 意味 |
| --- | --- |
| 0 | 指摘なし |
| 1 | 指摘あり |
| 2 | **検査を実行できない**(shellcheck が無い / 対象 0 件 / 不明な引数) |

`--list` で対象一覧だけを出せる(shellcheck が無くても動く)。

**0 件を「指摘なし」に倒さない。** テンプレートの `.claude/scripts/*.sh` は必ず追跡下にあるので、
空になるのは `git ls-files` が働いていないか除外条件が壊れたとき。シェルを一切使わない構成の
プロジェクトでは CI のステップごと落とす(CHANGELOG の `[manual]` に明記した)。

### 2) `ci.yml` は `bash .claude/scripts/check-shell.sh` を呼ぶだけにする

**非ゼロはすべて失敗。** 指摘(1)だけでなく「shellcheck が無い」(2)でも落とす。
他のハーネス層はフェイルオープンだが、**CI のゲートは止めるのが仕事**で、黙って通ると
層が消えたことに誰も気づかない。

### 3) devcontainer に入れる(`.devcontainer/post_create.sh`)

ステップを 4 → 5 に増やし、`[2/5] Installing shellcheck...` を足す。
`post_create.sh` は `set -e` なので、**インストールは `if` の条件で受ける**
(失敗しても警告 1 行でセットアップは続行。ツールが無いことと環境が壊れることは別の話)。

### 4) `/check`(`test-runner`)が同じコマンドを回す

`test-runner.md` のステップ1 に検出項目として足す。**テンプレートはスタック非依存**なので、
`check-shell.sh` があるときだけ回し、`exit 2`(未インストール)は**スキップとして報告する**
(失敗にしない)。**指摘の自動修正はしない** —— ガードレールのシェルを機械的に書き換えると
挙動が変わるため、要約だけ司令塔に返す。

### やり残し

`.claude/settings.json` の allow に `Bash(bash .claude/scripts/check-shell.sh:*)` を足せなかった
(auto モードの分類器が自己改変として拒否した)。足さなくても動くが、`/check` のたびに許可を聞かれる。
**人間が 1 行足す**(`harness-mode.sh` の行の次が自然)。
