# 検証: Issue #60 検収時のホスト実行

design.md §10 の手順を実際に実行した記録。**すべて実測**(推測での記載なし)。

## 1. 構文チェック

```
$ bash -n .claude/scripts/delegate-codex.sh && echo "OK: delegate-codex.sh syntax"
OK: delegate-codex.sh syntax

$ bash -n .claude/scripts/check-guard-integrity.sh && echo "OK: check-guard-integrity.sh syntax"
OK: check-guard-integrity.sh syntax
```

両方とも構文エラーなし。

## 2. 既存動作の非破壊(D4 の誤爆が無いこと)

現状のリポジトリ(`feature/issue60-host-exec-risk`、作業中の未コミット変更込み)で実行。

```
$ bash .claude/scripts/check-guard-integrity.sh
(出力なし)
EXIT=0

$ bash .claude/scripts/check-guard-integrity.sh degraded
(出力なし)
EXIT=0
```

D4 を含め、既存の D1/D2/D2.5/D3 いずれも誤爆していない。

## 3. D4 が鳴ること(実測)

手順:

1. 現在の未コミット変更(タスク 1〜14 の編集)を安全のため `git diff > /tmp/.../issue60-wip.patch` に退避
2. 一時ブランチ `tmp-issue60-d4-verify` を作成(`feature/issue60-host-exec-risk` から分岐、未コミット変更込み)
3. すべての変更を一時コミット `tmp: issue60 wip baseline for D4 verification`(`cae801a`)としてコミット(D4 実装済みの `check-guard-integrity.sh` を一時ブランチ上に確定させるため)
4. `package.json` の `scripts` に無害な差分(`"noop-issue60": "true"`)を `jq` で追加
5. `Codex-authored: test` トレーラーを含むコミットメッセージで一時コミット(`81d5e82`)

```
$ git add package.json && git commit -q -m "tmp: noop package.json change for D4 verification

Codex-authored: test"
(コミット成功)

$ git log -1 --format='%B'
tmp: noop package.json change for D4 verification

Codex-authored: test
```

6. `GUARD_DEGRADED_RANGE=HEAD~1..HEAD` で D4 検査を実行

```
$ GUARD_DEGRADED_RANGE=HEAD~1..HEAD bash .claude/scripts/check-guard-integrity.sh degraded
縮退中のコミット 81d5e82 が package.json を変更している。scripts / lint-staged / prepare に差分が無いか git diff で確認すること(検収でホスト上・ネットワーク有効で実行される。codex-delegation-plan.md §9)
EXIT=1
```

**D4 の行が実際に出力されることを確認した。**

### 後片付け(実施済み)

```
$ git checkout feature/issue60-host-exec-risk
$ git branch -D tmp-issue60-d4-verify
```

`git checkout` が一時ブランチ限定のコミット内容(`.steering/20260903-issue60-host-exec-risk/` を含む)を作業ツリーから落としたため、一時コミット `cae801a`(reflog 経由で到達可能)から
`git checkout cae801a -- .steering/20260903-issue60-host-exec-risk/` で復元し、`git restore --staged` で index からも外して元の未追跡状態に戻した。
最終的に `git diff --stat` は退避前と同一の 9 ファイル差分に一致し、`package.json` は差分なし(`git diff -- package.json` が空)であることを確認済み。一時ブランチは削除済みで `git branch -a` に残っていない。

## 4. 出口検査の警告(受け入れ条件 3)がブロックしないこと

`codex` CLI 自体は今回の実行環境に存在しないため実委託はしていない(design §10 手順 4 の「必須にはしない」に従う)。以下は実測。

### 4-1. `lifecycle_snapshot()` 相当の前後比較(書き換え検出)

一時コミット前後の `package.json` を対象に、`lifecycle_snapshot()` と同じ抽出クエリを実行して比較した。

```
$ git show HEAD~1:package.json | jq -S '{scripts: .scripts, "lint-staged": ."lint-staged"}' > /tmp/before.json
$ jq -S '{scripts: .scripts, "lint-staged": ."lint-staged"}' package.json > /tmp/after.json
$ diff /tmp/before.json /tmp/after.json
20a21
>     "noop-issue60": "true",
diff exit=1
```

`scripts` を書き換えた前後で `lifecycle_snapshot()` 相当の戻り値が変わることを確認した(diff exit=1 = 差分あり)。

### 4-2. 警告がブロックしないこと(コード上の裏取り)

`.claude/scripts/delegate-codex.sh` に追加した警告ブロックの実際のコード(該当行を引用):

```bash
# ---------- 出口検査(警告のみ): package.json のライフサイクル系差分 ----------
#
# 禁止領域の検査と違い **ブロックしない**(判断 D-3 / codex-delegation-plan.md §9)。
# 位置は禁止領域検査の直後・CODEX_EXIT の分岐より前で、上限や失敗で終わった委託でも
# 警告が出るようにしてある。rate-limited の経路は SUMMARY を捨てる(write_record に
# 空文字列を渡す)ので、stderr にも同じ内容を書く。
if [ "$MODE" = "impl" ]; then
  LIFECYCLE_AFTER="$(lifecycle_snapshot)"
  if [ "$LIFECYCLE_AFTER" != "$LIFECYCLE_BEFORE" ]; then
    SUMMARY="⚠️ package.json のライフサイクル系(scripts / lint-staged / prepare)に差分があります。
/check を回す前に \`git diff -- package.json\` で内容を確認してください
(検収は委託成果をホスト上・ネットワーク有効で実行します。codex-delegation-plan.md §9)。

$SUMMARY"
    cat >&2 <<'MSG'
delegate-codex: 警告 — package.json のライフサイクル系(scripts / lint-staged / prepare)に
差分があります。これらは検収(npm test / npm run lint / lint-staged)がサンドボックスの
外で実行する経路です。/check を回す前に内容を確認してください:

  git diff -- package.json

これは警告です。委託は失敗にしていません。
MSG
  fi
fi
```

このブロックには `exit` / `write_record "failed"` / `emit` のいずれも含まれていない。`SUMMARY` を書き換えるだけで、後続の `if [ "$CODEX_EXIT" -ne 0 ]; then` 以降の判定(`CODEX_EXIT` 分岐・VERDICT 判定・成果実在確認)へ制御がそのまま落ちる(禁止領域の出口検査ブロックが `exit "$EX_FAIL"` を含むのと対照的)。**ブロックしないことをコードで確認した。**

## 5. `/check`(プロジェクト標準チェック)

変更したファイル群(`.claude/`, `docs/`)に対して `npm run lint` と `npm run format:check` を実行(いずれも変更後の作業ツリーで、`package.json` 等スクリプト定義に手を加えていない状態)。

```
$ npm run lint
> claude-code-template@0.1.0 lint
> eslint .
(エラーなし)

$ npm run format:check
> claude-code-template@0.1.0 format:check
> prettier --check .

Checking formatting...
All matched files use Prettier code style!
```

両方とも成功。`.claude/scripts/*.sh` は shellcheck 等の lint 対象外(`eslint .` の対象は JS/TS 系)だが、`bash -n` による構文検査は上記 1. で実施済み。

## 6. 検収1巡目の指摘対応後の再検証

design §12(Minor 1 / Minor 3)対応で `codex-delegation-plan.md` §2.3 と `check-guard-integrity.sh` の D4 コメントを変更したため、構文と既存動作を再実測した。

### 6-1. 構文チェック(再実測)

```
$ bash -n .claude/scripts/delegate-codex.sh && echo "OK: delegate-codex.sh syntax"
OK: delegate-codex.sh syntax

$ bash -n .claude/scripts/check-guard-integrity.sh && echo "OK: check-guard-integrity.sh syntax"
OK: check-guard-integrity.sh syntax
```

両方とも構文エラーなし(D4 コメント追記のみで実行コードは変更していないため、想定どおり)。

### 6-2. 既存動作の非破壊(再実測)

現状のリポジトリ(`feature/issue60-host-exec-risk`、タスク 16〜19 の編集込みの未コミット変更込み)で実行。

```
$ bash .claude/scripts/check-guard-integrity.sh
(出力なし)
EXIT=0

$ bash .claude/scripts/check-guard-integrity.sh degraded
(出力なし)
EXIT=0
```

D4 を含め、既存の D1/D2/D2.5/D3 いずれも誤爆していない。コメントのみの変更であり、D3 側は無変更であることをこの結果と `git diff` で確認済み。
