# タスクリスト: rec_field() の二重実装を共有ファイルに集約する

design.md をそのまま適用する。設計判断は残っていない。

## 実装

- [x] `.claude/scripts/lib-record.sh` を design.md §2 の全文で新規作成する
      (**実行ビットは付けない**。`chmod +x` しない)
- [x] `.claude/scripts/delegate-codex.sh` の自己コピーブロックに design.md §3-1 の
      2 行(`_self_dir=` と `cp`)を挿入し、ブロック冒頭の説明に 1 文足す
- [x] `.claude/scripts/delegate-codex.sh` の `cd "$ROOT" || exit "$EX_FAIL"` の直後に
      design.md §3-2 の source ブロックを挿入する(**位置が重要。入口検査より前**)
- [x] `.claude/scripts/delegate-codex.sh` の旧 `rec_field`(642〜661 行)を削除する(§3-3)
- [x] `.claude/scripts/codex-run.sh` の旧 `rec_field`(50〜68 行)を design.md §4 の
      source ブロックで置換する
- [x] `docs/template-dev/CHANGELOG.md` に design.md §8 の `## 2026-08-30` 節を
      **既存の `## 2026-08-29` より上**に追加する

## 検証(design.md §7。すべて実際に走らせて結果を控える)

jq を外す `nojq` ヘルパーは design.md §7-1 にある。

- [x] `bash -n` が 3 ファイルすべてで通る
- [x] `lib-record.sh` に実行ビットが付いていない
- [x] `rec_field` 単体 / jq あり(`id` `mode` `status` `accepted` `pid`)
- [x] `rec_field` 単体 / jq なし(**pid に末尾カンマが付かない** = 過去の Critical の回帰点)
- [x] 存在しないキーが jq あり / なし どちらも空文字列
- [x] `accepted: false` が空にならない(jq あり / なし。一時 record を使ったら消す)
- [x] `codex-run.sh` の等価性 4 通り(`list --all` / `pending` × jq あり / なし)が
      design.md §7-0 の基準ファイルと `diff` で完全一致
- [x] `delegate-codex.sh --print-forbidden` が 10 行を出し、
      **「lib-record.sh の一時コピーを使えていません」警告が出ない**
      (実測: `FORBIDDEN_PATHS` 自体は 10 行、`PROJECT_FORBIDDEN_PATHS` を含む総出力は 22 行。
      これは既存仕様で今回の変更とは無関係。警告なしは確認済み)
- [x] `CODEX_DELEGATE_NO_SELF_COPY=1` でも同じ 22 行が出る(自己コピー無効の警告 1 行のみ)
- [x] フェイルクローズ: `lib-record.sh` を退避した状態で `delegate-codex.sh --print-forbidden` と
      `codex-run.sh list` が exit 2 で止まる → **確認後に必ず戻す**(戻した)
- [x] 退避状態で `check-guard-integrity.sh degraded` が「`--print-forbidden` が委託禁止領域を返さない」を出し、
      戻した後は無出力に戻る
- [ ] 任意: 入口検査5-5 の実経路(§7-3)。**未実施**(機密承認 `CODEX_DELEGATE_ACK_SECRETS=1` が要り、
      実際に委託を走らせないという制約と両立できないため見送った)

## 後始末

- [x] `git status --short` に想定外の差分・一時ファイルが残っていない
- [x] 変更したファイルを対象に品質チェックを回す(`npm run format:check`)

---

## 改訂: CI の実行ビット検査との衝突を直す(design.md §10)

CI `harness-integrity` が `lib-record.sh` に実行権限が無いことで落ちた。
**実行ビットを付けて黙らせるのではなく、検査側に「実行される実体 / source 専用ライブラリ」の
区別を入れる**(design.md §10)。

### 実装

- [x] `.github/workflows/ci.yml` の実行ビット検査ループ(85〜93 行)を design.md §10-1 で置換する。
      **既存のエラー文面は 1 文字も変えない**
- [x] `.claude/hooks/session-start.sh` のディスク権限ループ(31〜35 行)を §10-2(a) で置換する
- [x] `.claude/hooks/session-start.sh` の git index mode 検査(45〜52 行)を §10-2(b) で置換する
- [x] `.claude/scripts/lib-record.sh` のヘッダに §10-3 の 3 行を足す
- [x] `docs/template-dev/CHANGELOG.md` の `## 2026-08-30` 節末尾に §10-4 の項目を足す

### 検証(design.md §10-5)

- [x] `lib-record.sh` の git index mode が `100644` のまま
- [x] 他の `.claude/scripts/*.sh` / `.claude/hooks/*.sh` はすべて `100755` のまま
- [x] ci.yml のループをローカルで `bash -e` 再現し、無出力・exit 0
- [x] **抜け道が塞がっている**: `lib-record.sh` に実行ビットを付けると落ちる /
      shebang を足すと落ちる(**どちらも確認後に元へ戻す**)
- [x] **既存の検査が生きている**: `harness-mode.sh` の実行ビットを外すと従来の文面で落ちる
      (**確認後に戻す**)
- [x] `bash -n .claude/hooks/session-start.sh` が通る
- [x] `.claude/hooks/session-start.sh` を直接実行し、実行ビット関連の警告が出ない
- [x] `git status --short` に一時ファイル・想定外の差分が残っていない
