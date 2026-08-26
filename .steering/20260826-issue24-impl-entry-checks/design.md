# 設計: Issue #24 impl 入口検査の穴を塞ぐ

<!-- status: ready -->

対象は `.claude/scripts/delegate-codex.sh` の入口検査5 区画(`if [ "$MODE" = "impl" ]; then` ブロック)と、その記述を持つドキュメント 2 本。

## 1. 5-1: `.steering/` prefix 検査を足す

### 1.1 現状

```bash
  # ---- 5-1: target がステアリングディレクトリであること ----
  STEERING="${TARGET#./}"
  STEERING="${STEERING%/}/"
  DESIGN="${STEERING}design.md"
  TASKLIST="${STEERING}tasklist.md"

  if [ ! -d "$STEERING" ] || [ ! -f "$DESIGN" ] || [ ! -f "$TASKLIST" ]; then
```

正規化(`./` を剥がし、末尾スラッシュを 1 つに揃える)はそのまま使う。**この正規化行は変更しない。**

### 1.2 変更内容

`STEERING="${STEERING%/}/"` の直後、`DESIGN=` の行の前に、以下のブロックを挿入する。

```bash

  # target は `.steering/` 配下に限定する。run record の steering フィールドと
  # SessionStart の現在地判定(latest-steering.sh)が `.steering/` 前提のため、
  # 外のディレクトリを通すと状態管理が静かにずれる。
  #
  # `..` を先に弾くのは prefix 検査を素通りさせないため — `.steering/../foo/` は
  # 文字列として `.steering/*/` に一致してしまう。
  case "$STEERING" in
    *..*)
      echo "delegate-codex: impl の target に .. を含めることはできません: $STEERING" >&2
      exit "$EX_FAIL"
      ;;
    .steering/*/) ;;
    *)
      echo "delegate-codex: impl の target は .steering/ 配下のディレクトリである必要があります: $STEERING" >&2
      exit "$EX_FAIL"
      ;;
  esac
```

**case の並び順を変えないこと。** `*..*` を後ろに置くと `.steering/../foo/` が先に `.steering/*/` へ一致して通る。

### 1.3 この形で受け入れ条件を満たす根拠(実装者は確認だけでよい)

| target 引数 | 正規化後の `$STEERING` | 判定 |
| --- | --- | --- |
| `.steering/20260826-x` | `.steering/20260826-x/` | 通る |
| `.steering/20260826-x/` | `.steering/20260826-x/` | 通る |
| `./.steering/20260826-x/` | `.steering/20260826-x/` | 通る |
| `/tmp/foo/` | `/tmp/foo/` | `*)` で `exit 2` |
| `docs/foo/` | `docs/foo/` | `*)` で `exit 2` |
| `.steering/` | `.steering/` | `*)` で `exit 2`(`*` が空でも末尾の `/` が足りない) |
| `.steering/../tmp/foo/` | 同左 | `*..*` で `exit 2` |

## 2. 5-5: 判定軸を「steering 一致」から「mode=impl」へ変える

### 2.1 現状

```bash
  # ---- 5-5: 再入防止(同じ steering への二重起動)----
  if [ -d "$RUN_DIR" ]; then
    for _f in "$RUN_DIR"/*.json; do
      [ -f "$_f" ] || continue
      [ "$(rec_field "$_f" steering)" = "$STEERING" ] || continue
      _st="$(rec_field "$_f" status)"
      ...
      if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
        echo "delegate-codex: 同じステアリングへの委託が実行中です(id=$_rid pid=$_pid)。二重起動しません。" >&2
        exit "$EX_FAIL"
      fi
```

### 2.2 変更後(ブロック全体を以下で置き換える)

```bash
  # ---- 5-5: 再入防止(impl の並行実行を 1 本に制限)----
  # delegation-policy.md の「並行数は 1 本まで(同一ワーキングツリーを共有するため)」を
  # 機械化する層。同じステアリングへの二重起動だけでなく、別ステアリングへの並行 impl も
  # 止める(ツリーを共有するため、片方の lint/format が他方の編集を巻き込む)。
  # 判定軸を steering 一致にしていたときはこの経路が素通りしていた。
  #
  # 空振り条件: explore / review は read-only でこの検査区画そのものを通らないため、
  # 従来どおり並行できる(意図した挙動)。
  if [ -d "$RUN_DIR" ]; then
    for _f in "$RUN_DIR"/*.json; do
      [ -f "$_f" ] || continue
      [ "$(rec_field "$_f" mode)" = "impl" ] || continue
      _st="$(rec_field "$_f" status)"
      [ "$_st" = "running" ] || continue
      _pid="$(rec_field "$_f" pid)"
      _rid="$(rec_field "$_f" id)"
      _rsteer="$(rec_field "$_f" steering)"
      # pid は数字でなければ「取れなかった」として扱う。kill -0 に非数字を渡すと
      # 引数エラーで必ず失敗し、実行中の委託を「プロセス不在」と誤認して素通しする。
      # rec_field 側でも直したが、この層でも明示的に落とす(検査が空振りする条件を減らす)。
      case "$_pid" in
        '' | *[!0-9]*) _pid="" ;;
      esac
      if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
        if [ "$_rsteer" = "$STEERING" ]; then
          echo "delegate-codex: 同じステアリングへの委託が実行中です(id=$_rid pid=$_pid)。二重起動しません。" >&2
        else
          echo "delegate-codex: 別のステアリングへの委託が実行中です(id=$_rid pid=$_pid steering=$_rsteer)。impl の並行数は 1 本までです。" >&2
        fi
        exit "$EX_FAIL"
      fi
      # プロセスが居ない running = 強制終了の疑い。止めはしないが必ず知らせる。
      echo "delegate-codex: 警告 — 過去の委託 $_rid が status=running のまま残っています(プロセス不在 = 強制終了の可能性)。" >&2
      echo "  回復手順は codex-delegation-plan.md §12.6。tasklist.md と git diff --stat を突き合わせてから続けてください。" >&2
    done
  fi
```

**注意点(設計判断は済んでいる。実装者は従うだけでよい)**

- `mode` は run record の必須フィールドで常にクォート付き文字列(`"mode": "impl",`)。`rec_field` の sed フォールバックはクォートされた値では末尾カンマを飲まないため、`pid` で起きた事故は再現しない
- `_rsteer` は**メッセージの出し分けにのみ使う**。判定条件には使わない
- プロセス不在の running に対する警告は**現状のまま**残す。判定軸が広がったぶん、他ステアリングの残骸に対しても出るようになるが、これは意図した挙動(止めはしない)

### 2.3 `RUN_ID` のコメント修正

`RUN_ID=` の直前にあるコメントが 5-5 の旧仕様に言及しているので差し替える。

現状:

```bash
# pid を足すのは衝突回避。秒までしか持たない ID だと、別ステアリングへの
# 委託を同じ秒に始めたとき log と record が無条件に上書きされる。再入防止は
# 同一ステアリングしか見ないのでこの経路は塞げない。
```

変更後:

```bash
# pid を足すのは衝突回避。秒までしか持たない ID だと、同じ秒に始まった 2 本の
# 委託で log と record が無条件に上書きされる。impl は 5-5 が 1 本に制限するが、
# explore / review は入口検査5 を通らず並行できるのでこの経路が残る。
```

## 3. ドキュメントの更新

### 3.1 `.claude/rules/lead/delegation-policy.md`

18 行目:

```markdown
- 並行数は **1 本まで**(同一ワーキングツリーを共有するため)
```

を次に差し替える(1 行のまま):

```markdown
- 並行数は **1 本まで**(同一ワーキングツリーを共有するため)。impl は入口検査5-5 が機械的に止める(別ステアリングへの並行委託も `exit 2`)。read-only の explore / review はこの検査を通らず並行できる
```

### 3.2 `docs/template-dev/codex-delegation-plan.md`

**(a) §12 の入口検査表・5-1 の行**(現在 946 行目付近)。「何が起きているか」列と「復旧手順」列だけを差し替える:

- 何が起きているか: `` `impl` の target がディレクトリでない、`.steering/` 配下でない、または `design.md` と `tasklist.md` の一方を欠いている``
- 復旧手順: `` 両ファイルを持つ `.steering/[dir]` を target に指定して再実行する``(変更なし)

「検査」列・終了コード列・「空振りする条件」列は変更しない。

**(b) 表の直後の 5-5 段落**(現在 951 行目)。全文を次に差し替える:

```markdown
再入防止(5-5)では、**mode=impl の委託が実行中なら steering を問わず** `exit 2` で止まる(`delegation-policy.md` の「並行数は 1 本まで」を機械化した層)。同じステアリングへの二重起動と別ステアリングへの並行委託でメッセージを出し分ける。`status=running` なのにプロセスが居ない record は強制終了の疑いとして警告を出して通すため、サマリーではなく `tasklist.md` と `git diff` を根拠に §12.6 の手順で回復する。record は `bash .claude/scripts/codex-run.sh set-status <id> <status>` で実態に合う状態へ更新する。read-only の `explore` / `review` は入口検査5 を通らないため、従来どおり並行できる。
```

## 4. 検証

`verification.md` に結果を書く。**Codex は起動しない**(`delegate-codex.sh` は委託禁止領域であり、検証は入口検査までで完結する)。

### 4.1 構文

```bash
bash -n .claude/scripts/delegate-codex.sh
```

### 4.2 5-1 の受け入れ条件

入口検査5-1 は入口検査1〜4 の後に走る。**検査1〜4 を通さずに 5-1 だけを確かめるため**、`delegate-codex.sh` を直接叩かず、5-1 の判定ロジックだけを抜き出した等価スクリプトで表 §1.3 の 7 ケースを回す。

```bash
cat > /tmp/claude-1000/-workspaces-claude-codex-template/5772dd5b-eebd-4626-b062-7c179c379e44/scratchpad/t51.sh <<'SH'
EX_FAIL=2
check() {
  TARGET="$1"
  STEERING="${TARGET#./}"
  STEERING="${STEERING%/}/"
  case "$STEERING" in
    *..*) echo "$1 -> NG(..)"; return "$EX_FAIL" ;;
    .steering/*/) ;;
    *) echo "$1 -> NG(prefix)"; return "$EX_FAIL" ;;
  esac
  echo "$1 -> OK ($STEERING)"
}
for t in ".steering/20260826-x" ".steering/20260826-x/" "./.steering/20260826-x/" "/tmp/foo/" "docs/foo/" ".steering/" ".steering/../tmp/foo/"; do
  check "$t" || true
done
SH
bash /tmp/claude-1000/-workspaces-claude-codex-template/5772dd5b-eebd-4626-b062-7c179c379e44/scratchpad/t51.sh
```

期待: 最初の 3 件が `OK`、残り 4 件が `NG`。**`case` ブロックは §1.2 と 1 文字も違わないものをコピーすること**(等価でなければ検証にならない)。

加えて、実際の `delegate-codex.sh` でも 1 ケースだけ実測する。`codex` 未認証環境では入口検査4 で `exit 3` になり 5-1 まで届かないため、**届いた場合のみ**結果を記録し、届かなければ `verification.md` にその旨を書く:

```bash
mkdir -p /tmp/claude-1000/-workspaces-claude-codex-template/5772dd5b-eebd-4626-b062-7c179c379e44/scratchpad/outside
touch /tmp/claude-1000/-workspaces-claude-codex-template/5772dd5b-eebd-4626-b062-7c179c379e44/scratchpad/outside/design.md \
      /tmp/claude-1000/-workspaces-claude-codex-template/5772dd5b-eebd-4626-b062-7c179c379e44/scratchpad/outside/tasklist.md
bash .claude/scripts/delegate-codex.sh impl /tmp/claude-1000/-workspaces-claude-codex-template/5772dd5b-eebd-4626-b062-7c179c379e44/scratchpad/outside "test"; echo "exit=$?"
```

### 4.3 5-5 の受け入れ条件

run record のスタブを `.harness/codex-runs/` に置いて判定部分だけを回す。**本物の `.harness/codex-runs/` を汚さないこと** — スタブは検証後に必ず消す。

1. **別ステアリングへの並行が止まること**: `mode=impl` / `status=running` / `pid=$$`(自分自身の pid = 必ず生存)/ `steering=".steering/other-dir/"` のスタブ record を書き、§2.2 のループを抜き出した等価スクリプトを `STEERING=".steering/20260826-issue24-impl-entry-checks/"` で回す。期待: 「別のステアリングへの委託が実行中です」+ `exit 2`
2. **同一ステアリングのメッセージが従来どおりであること**: スタブの `steering` を `STEERING` と同じ値にして回す。期待: 「同じステアリングへの委託が実行中です」+ `exit 2`
3. **mode=explore の running record では止まらないこと**: スタブの `mode` を `explore` にして回す。期待: 何も出力せず `exit 0`
4. **jq 不在経路**: 1 を `PATH` から `jq` を外した状態(`env PATH=/usr/bin:/bin` 等、`jq` が引けない PATH)でも同じ結果になることを確認する。`rec_field` の sed フォールバックが `mode` を正しく拾えることの確認

`jq` 経路と sed 経路の**両方**を回すこと。過去に sed フォールバックだけが壊れていた事故がある(§12 / `codex-delegation-plan.md` 822 行目)。

### 4.4 全体

```bash
npm run typecheck && npm run format:check && npm run lint && npm test
```

(`/check` で代替してよい)
