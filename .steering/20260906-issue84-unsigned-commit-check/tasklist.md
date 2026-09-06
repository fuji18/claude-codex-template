# タスクリスト: Issue #84 名乗らないコミットの逆向き検査(D0)

## 実装

- [x] 1. `.claude/scripts/check-guard-integrity.sh`: `$DEGRADED_RANGE` 解決ブロックを D3 の中から
      共通ブロックへ引き上げ、`DEGRADED_BASE_RESOLVED` を追加する(design.md「置換後」のとおり)
- [x] 2. 同ファイル: D0 ブロックを D2.5 の後・D3 の前に追加する(design.md「置換後」のとおり)
- [x] 3. 同ファイル: D3 のヘッダコメントから検査範囲の説明を落とし、`DELEGATE=` の代入だけ残す
- [x] 4. `bash -n .claude/scripts/check-guard-integrity.sh` で構文を確認する

## 検証(スクラッチリポジトリで行う。実リポジトリにテストコミットを作らない)

作業ディレクトリ: `$SCRATCH/d0-test`(`/tmp/claude-1000/.../scratchpad` 配下)

セットアップ:

```bash
SB="$SCRATCH/d0-test"; rm -rf "$SB"; mkdir -p "$SB"
tar -c --exclude=.git -C /workspaces/claude-codex-template . | tar -x -C "$SB"
cd "$SB" && git init -q -b degraded-test && git add -A \
  && git -c core.hooksPath=/dev/null commit -q -m "base: snapshot"
```

- [x] 5. **V1 誤検知しない**: 全コミットがトレーラー付きの状態で 1 行も出ないこと

  ```bash
  cd "$SB"
  echo x >> README.md && git add -A \
    && git -c core.hooksPath=/dev/null commit -q -m "codex: work" -m "Codex-authored: true"
  GUARD_DEGRADED_RANGE="$(git rev-list --max-parents=0 HEAD)..HEAD" \
    bash .claude/scripts/check-guard-integrity.sh degraded | grep -c 'トレーラーを持たないコミット'
  # 期待: 0
  ```

- [x] 6. **V2 検出する**: トレーラー無しコミットが報告されること

  ```bash
  cd "$SB"
  echo y >> README.md && git add -A \
    && git -c core.hooksPath=/dev/null commit -q -m "sneaky: no trailer"
  GUARD_DEGRADED_RANGE="$(git rev-list --max-parents=0 HEAD)..HEAD" \
    bash .claude/scripts/check-guard-integrity.sh degraded | grep 'トレーラーを持たないコミット'
  # 期待: "sneaky: no trailer" の 1 行だけが出る(codex: work は出ない)
  ```

- [x] 7. **V3 マージコミットを除く**: 取り込みマージが報告されないこと

  ```bash
  cd "$SB"
  git checkout -q -b side HEAD~1 && echo z >> LICENSE 2>/dev/null || echo z >> README.md
  git add -A && git -c core.hooksPath=/dev/null commit -q -m "side: work" -m "Codex-authored: true"
  git checkout -q degraded-test
  git -c core.hooksPath=/dev/null merge --no-ff -q side -m "Merge branch 'side'"
  GUARD_DEGRADED_RANGE="$(git rev-list --max-parents=0 HEAD)..HEAD" \
    bash .claude/scripts/check-guard-integrity.sh degraded | grep 'トレーラーを持たないコミット'
  # 期待: Merge branch 'side' が出ない(sneaky の 1 行だけ)
  ```

- [x] 8. **V4 フォールバック時はスキップ**: ベース(`main` / `origin/main`)が無い状態で
      スキップの理由行が出て、コミットの列挙が出ないこと

  ```bash
  cd "$SB"
  git rev-parse --verify --quiet main; git rev-parse --verify --quiet origin/main
  # 期待: どちらも出力なし(= 解決できない)
  bash .claude/scripts/check-guard-integrity.sh degraded | grep -E 'D0|トレーラーを持たないコミット'
  # 期待: スキップの理由行のみ。個別コミットの列挙は出ない
  ```

- [x] 9. **V5 exit の挙動が変わらない**: 実リポジトリで `degraded` を回し、D0 の追加によって
      新たな行が出ていないこと(現在のブランチのコミットは人間 / Claude が積んだものなので
      D0 が反応する。**反応した場合はそれが仕様どおりの挙動**であることを確認し、
      出力内容を報告に含める)

  ```bash
  bash .claude/scripts/check-guard-integrity.sh degraded; echo "exit=$?"
  ```

- [x] 10. **V6 既定サブコマンドが無影響**: `bash .claude/scripts/check-guard-integrity.sh; echo "exit=$?"`
      が変更前と同じ出力・同じ終了コードであること(D0 は `degraded` 経路にしか無い)
- [x] 11. スクラッチリポジトリを削除する(`rm -rf "$SB"`)

## ドキュメント

- [x] 12. `.claude/rules/mode/degraded.md` 手順 1 に 1 行追記(design.md (a))
- [x] 13. `docs/template-dev/codex-delegation-plan.md` §2.3 条件 2 の理由に追記(design.md (b))
- [x] 14. `docs/template-dev/CHANGELOG.md` の `## 2026-09-06` に `[auto]` 項目を追記(design.md (c))
