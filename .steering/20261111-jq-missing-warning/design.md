# design: jq が無い環境でガードが黙って消えるのを止める

## 判断

**フェイルオープンのまま、黙らせない。** 選ばなかった案:

| 案 | 選ばなかった理由 |
| --- | --- |
| `jq` が無ければ PreToolUse hook を `exit 2` にする | 全 Bash / Edit が止まり、`jq` を入れる操作すらセッションからできない。`check-protected-branch.sh` 冒頭に明記された「`jq` が無い環境で commit 不能にしない」を反転させる |
| node で JSON を読む代替経路 | 入力の取り出しは代替できても、ポリシーファイルを読む `jq` フィルタ(10 種以上)は残る。部分的にしか塞がらないのに、判定の実体が 2 系統になる |

## 変更

### 1. `.claude/hooks/session-start.sh`

「ハーネスの自壊検知」ブロックの直前に、`command -v jq` が失敗したときだけ出す警告を足す。
全 source(startup / resume / clear / compact)で出す。内容:

- 見出し(`# ⚠️ jq が無い: ガード hook が効いていない`)
- 効いていない層の一覧(requirements の表と同じ 5 つ)
- `jq` が入るまで司令塔が守ること: 保護ブランチへの直接コミット・force push・
  `--base` 無しの `gh pr create`・実装フェーズ中の実装コード直接編集をしない
- 入れ方(Windows: `winget install jqlang.jq` / macOS: `brew install jq` /
  Debian 系: `sudo apt-get install -y jq`)と、devcontainer の中で開けば不要である旨
- ユーザーに最初の応答で伝えるよう指示する 1 行

`jq` があるときは何も出さない(既定のセッションのコンテキストを増やさない)。

### 2. `.claude/scripts/check-protected-branch.sh` / `check-push-policy.sh`

`command -v jq >/dev/null 2>&1 || exit 0` を、stderr に 1 行出してから `exit 0` に変える。
終了コードは変えない(呼び出し元の `.husky/*` と `check-branch-policy.sh` は終了コードだけを見る)。

`check-branch-policy.sh` からは `jq` がある場合しか呼ばれないので、Claude 経由では出ない。
出るのは git hook 経由(手動 git・Codex・他ツール)だけ。

### 3. PreToolUse hook 3 本は変えない

`exit 0` の stderr はモデルにもユーザーにも見えないため、警告を足しても届かない。
Claude 経由の気づきは 1. の SessionStart が担う。

### 4. Windows 版 jq の CRLF(追記: ホストに jq を入れて判明)

`winget install jqlang.jq` で入る `jq.exe` は、Git Bash から呼ぶと出力の改行が CRLF になる
(`jq -r '.baseBranch'` → `main\r\n`)。`jq -e` の終了コードだけを見る検査は動くが、値を文字列比較する
検査はエラーを出さずに外れる(`check-manifest-coverage.sh` が 381 件中 380 件を誤判定)。

- **対処はスクリプト側ではなく環境側**: `jq.exe -b` を呼ぶラッパーを `~/bin/jq` に置く。
  22 本・約 220 箇所の `jq` 呼び出しに `-b` や `tr -d '\r'` を足す案は、足し忘れが次の素通しになるので採らない
- **SessionStart で検知する**: `jq -rn '"a"'` の出力に `\r` が含まれたら警告する(`jq` 欠落の警告と排他)
- 手順は CHANGELOG の 2026-11-11 に書く

## 検証

- ホスト(`jq` 無し): `session-start.sh` の出力に警告が出る / `exit 0`
- `jq` あり(PATH にダミーの `jq` を置く): 警告が出ない
- `check-protected-branch.sh` / `check-push-policy.sh`: `jq` 無しで stderr 1 行 + `exit 0`
- `bash -n`(変更した 3 本)
- `shellcheck` はホストに無いため未実施 → CI の `harness-integrity` で確認する
