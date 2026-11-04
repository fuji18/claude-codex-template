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
