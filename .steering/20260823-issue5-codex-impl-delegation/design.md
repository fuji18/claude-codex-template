# 設計書: 段階3 — 実装委託と終了コード契約

<!-- status: ready -->

## 0. 実装対象ファイル(これ以外を触らない)

| ファイル | 区分 | 変更 |
| --- | --- | --- |
| `.claude/scripts/delegate-codex.sh` | 改修 | `impl` モード・exit 1/5・run record 完全化・再入防止・成果実在確認 |
| `.claude/scripts/codex-run.sh` | **新規** | run record の一覧・`accepted` 付与・`status` 更新(§12.6 の回復手段) |
| `.claude/commands/add-feature.md` | 改修 | ステップ5 を「Codex 委託 → 終了コード分岐 → fork フォールバック」に置換 |
| `.claude/commands/next-ticket.md` | 改修 | 担当表の実装行を委託経路に更新 |
| `.claude/commands/fix-issue.md` | 改修 | ステップ4 を add-feature ステップ5 参照に更新 |
| `.claude/template-manifest.json` | 改修 | `codex-run.sh` を `owned` に登録 |
| `README.md` | 改修 | `scripts/` の 1 行説明に `codex-run.sh` を足す |
| `docs/template-dev/codex-delegation-plan.md` | 改修 | §11 の段階表と進捗メモを段階3 完了に更新 |
| `docs/template-dev/codex-harness.html` | 改修 | 「impl は未実装」と書いてある箇所を実態に合わせる |

`AGENTS.md` は**変更しない**。impl に必要な規約(モード判定・逐次更新・報告フォーマット・完成マーカー)は段階2 で既に書かれている。

---

## 1. `delegate-codex.sh` の改修

### 1.1 全体方針

既存の構造(引数 → 入口検査0〜4 → ハーネスモード → run record → プロンプト → 実行 → 出口判定)を**維持したまま差し込む**。既存の `explore` / `review` の挙動を変えない。

追加する定数(ファイル冒頭の `EX_FAIL=2` の近くに置く):

```bash
EX_BLOCKED=1    # 判断待ち
EX_NOTREADY=5   # design.md が ready でない
```

### 1.2 引数まわり

- `case "$MODE"` の許可リストに `impl` を足す。`fix-ci` は現状どおり「段階外」として `exit 2`(メッセージは「`fix-ci` は本テンプレートでは未実装です」に変える。「段階3 で実装します」は嘘になる)
- `--background` のメッセージを **「段階4 で実装します(未検収委託が SessionStart に出るようになるまで非同期にしない)」** に変える。挙動(`exit 2`)は変えない
- `usage()` に `impl <.steering/[dir]>   実装フェーズの委託(workspace-write)` の行を足す

### 1.3 入口検査5(impl 専用)

**置き場所**: 既存の「入口検査4: Codex CLI」ブロックの**直後**、「ハーネスモード」節の直前。

`RUN_DIR=".harness/codex-runs"` の代入だけをこのブロックより前(入口検査5 の直前)に移動する。再入判定が run record を読むため。`mkdir -p` は現状の位置(run record 節)のまま。

`STEERING` はグローバル変数として**常に定義する**(impl 以外では空文字列)。run record の `steering` フィールドがこれを使う。

```bash
STEERING=""

if [ "$MODE" = "impl" ]; then
  # ---- 5-1: target がステアリングディレクトリであること ----
  STEERING="${TARGET#./}"
  STEERING="${STEERING%/}/"
  DESIGN="${STEERING}design.md"
  TASKLIST="${STEERING}tasklist.md"

  if [ ! -d "$STEERING" ] || [ ! -f "$DESIGN" ] || [ ! -f "$TASKLIST" ]; then
    echo "delegate-codex: impl の target は design.md と tasklist.md を持つステアリングディレクトリである必要があります: $STEERING" >&2
    exit "$EX_FAIL"
  fi

  # ---- 5-2: design.md の完成マーカー(§2.5)----
  # draft = 拒否(exit 5)/ ready = 通す / 印なし = 通す(マーカー導入以前のものを止めない)
  # 空振り条件: 印が無い design.md は書きかけでも通る。implement-ticket スキルと
  # AGENTS.md §4 が同じ規則なので、経路によらず結果が一致することを優先している。
  if grep -q '<!-- status: draft -->' "$DESIGN"; then
    cat >&2 <<MSG
delegate-codex: $DESIGN が <!-- status: draft --> です(計画が未完成)。

書きかけの設計で Codex の枠を溶かさないため委託しません。司令塔が design.md を
書き切り、印を <!-- status: ready --> に変えてから再委託してください。
MSG
    exit "$EX_NOTREADY"
  fi
  if ! grep -q '<!-- status: ready -->' "$DESIGN"; then
    echo "delegate-codex: 警告 — $DESIGN に完成マーカーがありません。検査対象外として通します。" >&2
  fi

  # ---- 5-3: git hook が有効か ----
  # .husky/ があるのに core.hooksPath が未設定 = husky が丸ごと無効。
  # 保護ブランチへのコミットを止めるベンダー非依存の層が存在しない状態で
  # workspace-write の委託をしない。
  # 空振り条件: .husky/ を持たないプロジェクト(Python/Go 等)ではこの検査は
  # 何も見ない。そこでは git hook 層そのものが存在しないので、判定できない。
  if [ -d .husky ] && [ -z "$(git config --get core.hooksPath 2>/dev/null)" ]; then
    cat >&2 <<'MSG'
delegate-codex: git hook が無効です(core.hooksPath 未設定 / Codex 利用不可)。

husky が有効化されていないため、保護ブランチへのコミットを止めるベンダー非依存の
層が存在しません。sandbox はネットワーク無効なので Codex 自身では復旧できません。

  npm ci        (または npx husky)

を実行してから再委託してください。当面は Sonnet fork にフォールバック。
MSG
    exit "$EX_UNAVAIL"
  fi

  # ---- 5-4: 保護ブランチ上で実装委託しない ----
  # 判定の実体は共有スクリプトに委ねる(hook・CI と同じ結果になることが要件)。
  # 空振り条件: check-protected-branch.sh は jq / ポリシーファイルが無いとき
  # フェイルオープン(exit 0)する。そこでは保護ブランチでも通る。
  if [ -f .claude/scripts/check-protected-branch.sh ] &&
    ! bash .claude/scripts/check-protected-branch.sh 2>/dev/null; then
    echo "delegate-codex: 保護ブランチ上では実装を委託しません。作業ブランチを切ってください。" >&2
    exit "$EX_FAIL"
  fi

  # ---- 5-5: 再入防止(同じ steering への二重起動)----
  if [ -d "$RUN_DIR" ]; then
    for _f in "$RUN_DIR"/*.json; do
      [ -f "$_f" ] || continue
      [ "$(rec_field "$_f" steering)" = "$STEERING" ] || continue
      _st="$(rec_field "$_f" status)"
      [ "$_st" = "running" ] || continue
      _pid="$(rec_field "$_f" pid)"
      _rid="$(rec_field "$_f" id)"
      if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
        echo "delegate-codex: 同じステアリングへの委託が実行中です(id=$_rid pid=$_pid)。二重起動しません。" >&2
        exit "$EX_FAIL"
      fi
      # プロセスが居ない running = 強制終了の疑い。止めはしないが必ず知らせる。
      echo "delegate-codex: 警告 — 過去の委託 $_rid が status=running のまま残っています(プロセス不在 = 強制終了の可能性)。" >&2
      echo "  回復手順は codex-delegation-plan.md §12.6。tasklist.md と git diff --stat を突き合わせてから続けてください。" >&2
    done
  fi
fi
```

`rec_field` は 1.4 で定義する。**定義位置は入口検査5 より前**(ファイル冒頭の関数群、`json_str` の近く)に置くこと。

### 1.4 run record の完全化

`json_str` / `json_or_null` はそのまま。次を足す。

**読み出しヘルパー**(再入判定と `codex-run.sh` で同じ規則を使う。`codex-run.sh` 側にも同じ関数を書く。共有ファイルは作らない — 2 箇所・十数行のために依存を増やす方が高くつく):

```bash
# $1=json ファイル $2=キー名。無い/null は空文字列を返す。
rec_field() {
  local _out=""
  if command -v jq >/dev/null 2>&1; then
    _out="$(jq -r --arg k "$2" '.[$k] // empty' "$1" 2>/dev/null)"
  else
    _out="$(sed -n "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\},\{0,1\}[[:space:]]*$/\1/p" "$1" | head -1)"
  fi
  [ "$_out" = "null" ] && _out=""
  printf '%s' "$_out"
}
```

**時刻とセッション ID のグローバル**(run record 節、`RUN_ID` の近くで初期化する):

```bash
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ENDED_AT=""
CODEX_SESSION_ID=""
```

**`write_record` の本体を差し替える**(引数の並びは現状維持: `$1=status $2=summary $3=error $4=resetAt`):

```json
{
  "id": ..., "mode": ..., "target": ...,
  "steering": <json_or_null "$STEERING">,
  "branch": ..., "harnessMode": ...,
  "codexSessionId": <json_or_null "$CODEX_SESSION_ID">,
  "pid": $$,
  "status": ...,
  "startedAt": <json_str "$STARTED_AT">,
  "endedAt": <json_or_null "$ENDED_AT">,
  "resetAt": ..., "summary": ..., "error": ...,
  "log": ...,
  "accepted": false
}
```

- `accepted` は常にリテラル `false` を書く。`true` にするのは `codex-run.sh accept` だけで、`delegate-codex.sh` が record を上書きするのは同一 run の中だけなので競合しない
- `pid` は `$$`(このスクリプトのプロセス ID)。§3.4 の `kill -0` による生存確認がこれを見る
- **`status` の語彙**: `running` / `completed` / `blocked` / `failed` / `rate-limited` / `unavailable`。`blocked` が今回の追加(判断待ち)

### 1.5 事前スナップショット(exit 0 の裏取りに使う)

`write_record "running" ...` を書く**直前**に取る。impl 以外では取らない。

```bash
tree_snapshot() { git status --porcelain 2>/dev/null | LC_ALL=C sort; }
count_done() {
  local _n
  _n="$(grep -cE '^[[:space:]]*- \[[xX]\]' "$TASKLIST" 2>/dev/null)"
  printf '%s' "${_n:-0}"
}

if [ "$MODE" = "impl" ]; then
  TREE_BEFORE="$(tree_snapshot)"
  HEAD_BEFORE="$(git rev-parse HEAD 2>/dev/null || echo none)"
  DONE_BEFORE="$(count_done)"
fi
```

`grep -c` はマッチ 0 件のとき標準出力に `0` を出して exit 1 を返す。`set -uo pipefail` 下でも `$(...)` の非ゼロは変数代入では致命的にならない(`set -e` を使っていない)が、**`|| echo 0` を足さないこと** — 足すと `0` が 2 行出る。

`.harness/codex-runs/` は `.gitignore` 済みなので、ログや record 自身が `git status --porcelain` に混ざることはない。

### 1.6 impl のプロンプト

`PREAMBLE` は explore/review 用の文言(「読み取り専用」)を含むため、**impl では別の前文を使う**。既存の `PREAMBLE` 定義を次の形に変える:

```bash
if [ "$MODE" = "impl" ]; then
  PREAMBLE="あなたは実装フェーズ(--sandbox workspace-write)で起動されています。

まず $AGENTS を読み、そこに書かれた規約に従ってください。
現在のハーネスモード: $HMODE"
else
  PREAMBLE="あなたは読み取り専用(--sandbox read-only)で起動されています。ファイルの変更・コミットは行わないでください。

まず $AGENTS を読み、そこに書かれた規約に従ってください。
現在のハーネスモード: $HMODE"
fi
```

`case "$MODE"` に `impl` を足す:

```bash
  impl)
    PROMPT="$PREAMBLE

対象のステアリングディレクトリ: $STEERING

${STEERING}design.md と ${STEERING}tasklist.md を読み、tasklist の未完了タスクを
先頭から 1 つずつ実装してください。内容はこの指示に貼っていません。自分で読んでください。

守ること:
- **1 タスク完了ごとに tasklist.md を - [x] へ更新する**(まとめ更新は禁止)。途中で
  停止しても別の実装者が続きから引き継げることが要件です
- design.md に書かれていない設計判断が必要になったら、推測せず停止して「判断待ち」で報告する
- 変更したファイルだけを対象に lint・型チェック・関連テストを回す(全体フォーマットは禁止)
- ネットワークは無効。新規依存の追加が必要になったら実装せず「判断待ち」で報告する
- コミットの可否は AGENTS.md のモード表に従う

**最後に、次のどれか 1 行を単独の行として出力してください。司令塔はこの行だけで分岐します:**
完了: tasklist N/M / 変更 K ファイル / lint・型・関連テスト pass
判断待ち: [何が決まっていないか] / [考えられる選択肢]
失敗: [何が起きたか] / [試したこと]"
    ;;
```

### 1.7 sandbox の切り替え

```bash
SANDBOX="read-only"
[ "$MODE" = "impl" ] && SANDBOX="workspace-write"
```

`codex exec` 呼び出しの `--sandbox read-only` を `--sandbox "$SANDBOX"` に変える。他のフラグは変えない(段階0 で実機確認済みの並び)。

### 1.8 出口判定

既存の「上限 → 認証 → その他」の判定は**そのまま**(exit 非ゼロのときだけ当てる方針も維持)。次を足す。

**(a) セッション ID の抽出** — `codex exec` 直後、最初の `write_record` より前:

```bash
CODEX_SESSION_ID="$(grep -Eo '"(thread_id|session_id|conversation_id)"[[:space:]]*:[[:space:]]*"[^"]+"' "$LOG" 2>/dev/null |
  head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
ENDED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

段階0 の実機ログでは `thread.started` イベントが流れることまで確認済みだが、**キー名は未確認**。3 つの候補を試して取れなければ `null` のままにする(取れないことは回復手段を壊さない — 回復の根拠は `tasklist.md` と `git diff`)。

**(b) 判定行の抽出と分岐** — 既存の `if [ "$CODEX_EXIT" -ne 0 ]` ブロック 2 つの**後**、最後の `write_record "completed"` の**前**に挿入する。impl のときだけ効かせる:

```bash
if [ "$MODE" = "impl" ]; then
  # 報告フォーマット(AGENTS.md §7)の判定行。複数あれば最後のものを採る。
  VERDICT="$(grep -hE '^[[:space:]]*(\*\*)?(完了|判断待ち|失敗)[::]' "$LAST" 2>/dev/null | tail -1)"

  case "$VERDICT" in
    *判断待ち*)
      write_record "blocked" "$SUMMARY" "" ""
      emit "blocked" "$EX_BLOCKED"
      printf -- '--- 判断待ち ---\n%s\n' "$SUMMARY"
      exit "$EX_BLOCKED"
      ;;
    *失敗*)
      write_record "failed" "$SUMMARY" "" ""
      emit "failed" "$EX_FAIL"
      printf -- '--- 失敗 ---\n%s\n' "$SUMMARY"
      exit "$EX_FAIL"
      ;;
  esac

  # ---- 成果の実在確認 ----
  # codex exec の exit 0 は「ターンが完了した」であってタスクの成否ではない
  # (段階0 の実測)。何も動いていない委託を検収に回さない。
  # 空振り条件: Codex が判定行を書かずに何かを 1 バイトでも変更した場合、
  # ここは通る。そのときの防衛線は司令塔の検収(code-reviewer + test-runner)。
  TREE_AFTER="$(tree_snapshot)"
  HEAD_AFTER="$(git rev-parse HEAD 2>/dev/null || echo none)"
  DONE_AFTER="$(count_done)"

  if [ "$TREE_AFTER" = "$TREE_BEFORE" ] &&
    [ "$HEAD_AFTER" = "$HEAD_BEFORE" ] &&
    [ "$DONE_AFTER" -le "$DONE_BEFORE" ]; then
    write_record "failed" "$SUMMARY" "exit 0 だが成果物が確認できない(作業ツリー・HEAD・tasklist のいずれも変化なし)" ""
    emit "failed" "$EX_FAIL"
    cat >&2 <<'MSG'
delegate-codex: Codex は正常終了しましたが、成果物が確認できません。
作業ツリー・HEAD・tasklist の進捗がいずれも変化していないため、失敗として扱います。
生ログで原因(sandbox の起動失敗など)を確認してください。
MSG
    exit "$EX_FAIL"
  fi

  if [ "$DONE_AFTER" -le "$DONE_BEFORE" ]; then
    SUMMARY="$SUMMARY

⚠️ tasklist.md の [x] が増えていません(変更はあります)。逐次更新がされていない
可能性があるため、進捗の判断は tasklist ではなく git diff --stat を根拠にしてください。"
  fi
fi
```

**分岐の順序が要点**: 「判定行 = 失敗/判断待ち」を先に見て、そのあとに成果実在確認をする。逆順にすると、判断待ちで正しく停止した委託(= 差分が無いのが正常)が `exit 2` に化ける。

**(c) ヘッダーコメントの更新**: 冒頭の「段階2 で実装するのは読み取り専用の 2 モードだけ」を実態(`impl` 実装済み・`fix-ci` と `--background` は未実装)に書き換える。終了コード表の `1` と `5` から「段階3 で」の但し書きを外す。

---

## 2. `.claude/scripts/codex-run.sh`(新規)

### 2.1 目的

§12.6 の回復手順の最後(「run record の `status` を実態に合わせて更新し、`accepted` の判定に進む」)を成立させる。

**なぜスクリプトにするか**: 司令塔が `.harness/codex-runs/*.json` を Edit/Write で直そうとすると、`check-implementation-phase.sh` のパス許可リスト(`.steering/` `docs/` `.claude/` `.github/` `.husky/`)に `.harness/` が無いため、**未完了タスクが残っている状況 = まさに §12.6 の状況でブロックされる**。Bash 経由なら通る。許可リストに `.harness/` を足す案は採らない — record は機械が書く状態ファイルであり、手編集を正規の経路にすると JSON の破損経路が増える。

### 2.2 インターフェース

```
.claude/scripts/codex-run.sh list [--all]
.claude/scripts/codex-run.sh show <id>
.claude/scripts/codex-run.sh accept <id>
.claude/scripts/codex-run.sh set-status <id> <status>
```

| サブコマンド | 動作 |
| --- | --- |
| `list` | `accepted != true` の record を 1 件 1 行で出す。`--all` で全件 |
| `show` | その record を丸ごと出す(`cat`) |
| `accept` | `accepted` を `true` にする |
| `set-status` | `status` を差し替える。語彙は `running` / `completed` / `blocked` / `failed` / `rate-limited` / `unavailable` / `interrupted` / `discarded` に限定し、それ以外は拒否する |

`interrupted`(強制終了と判明したもの)と `discarded`(部分成果を破棄したもの)は §12.6 の処理後に人が付ける値で、`delegate-codex.sh` は書かない。

終了コード: `0` 成功 / `1` 対象が無い・値が不正 / `2` 使い方の誤り。**`delegate-codex.sh` の契約とは別系統**である旨をヘッダーコメントに明記する(司令塔が取り違えないため)。

### 2.3 実装の要点

- 冒頭で `git rev-parse --show-toplevel` に `cd`(`delegate-codex.sh` と同じ)
- `rec_field` は 1.4 と**同一の実装**をコピーする
- `list` の 1 行フォーマット:
  `<id>  mode=<mode>  status=<status>  branch=<branch>  accepted=<accepted>  <steering|target>`
  - `status=running` かつ pid が生きていなければ `status=running(プロセス不在)` と出す
  - 現在のブランチと record の `branch` が違うものは行末に ` [別ブランチ]` を付ける
  - 該当が無ければ `未検収の Codex 委託はありません` と出して exit 0
- 書き換え(`accept` / `set-status`)は **jq があれば jq、無ければ sed** の 2 経路:

```bash
write_field() { # $1=file $2=key $3=raw-json-value
  local _tmp="$1.tmp.$$"
  if command -v jq >/dev/null 2>&1; then
    jq --argjson v "$3" --arg k "$2" '.[$k] = $v' "$1" >"$_tmp" 2>/dev/null || { rm -f "$_tmp"; return 1; }
  else
    sed "s|^\([[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*\).*\$|\1$3,|" "$1" >"$_tmp" || { rm -f "$_tmp"; return 1; }
  fi
  mv "$_tmp" "$1"
}
```

  - `accept` は `write_field "$f" accepted true`
  - `set-status` は `write_field "$f" status "\"$NEW\""`
  - **sed 経路の既知の弱点**: 末尾のカンマを常に付けるため、対象キーが JSON の**最後のフィールド**だと壊れる。`write_record` が書く順序では `accepted` が最後・`status` は中間なので、`accepted` の sed 経路だけカンマ無しにする。判断を残さないため、`write_field` に第 4 引数 `trailing_comma`(既定 `,`)を持たせ、`accept` は空文字列を渡す
  - 書き換え後に `jq -e . "$f" >/dev/null`(jq がある場合のみ)で妥当性を確認し、壊れていたらバックアップから戻して exit 1。バックアップは `mv` の前に `cp "$1" "$1.bak"` で取り、成功したら消す
- 実行権限 `chmod +x` を付け、**`git update-index --chmod=+x` も必ず実行する**(`core.fileMode=false` の環境ではディスクの +x が index に入らず、CI の harness-integrity だけが落ちる)

---

## 3. コマンド 3 本の分岐改訂

### 3.1 `/add-feature` ステップ5(正の記述はここ 1 箇所)

見出しを `## ステップ5: 実装 (Codex 委託 → Sonnet fork フォールバック)` に変える。既存の「司令塔は実装コードを書かない」の段落は残し、次の内容に差し替える。

```markdown
**司令塔は実装コードを書かない。** 実装フェーズは委託する。**既定は Codex**(`delegate-codex.sh impl`)、使えなければ `implement-ticket` スキル(`context: fork` / Sonnet)。委託先が変わっても**司令塔の分岐ロジックは同じ**(完了 / 判断待ち / 失敗)であることが設計要件。司令塔は Opus のまま維持され、モデルの切り替えは不要。

1. **委譲前に作業ツリーをクリーンにする**(`git status` で確認)。fork の編集はチェックポイント(`/rewind`)で戻せない可能性があり、Codex の編集は原理的に戻せない。git を退避手段として確保しておく。
2. **このセッションで既に `exit 3` を受け取っている場合は 3 を飛ばし、4(Sonnet fork)へ直行する**(恒久フォールバック。同じ環境欠落を毎回試さない)。
3. `bash .claude/scripts/delegate-codex.sh impl .steering/[dir]` を実行し、**終了コードだけを見て分岐する**(サマリー本文から成否を推測しない):

| exit | 意味 | 司令塔の動き |
| --- | --- | --- |
| `0` | 完了 | ステップ6(検証)へ進む |
| `1` | 判断待ち | 判断を下し、**`design.md` に追記してから**再委託する(tasklist の途中から再開される) |
| `2` | 失敗(タスク起因) | 原因を分析する。設計起因なら `design.md` を修正して再委託。**2 回連続で失敗したら委託を打ち切り**、`Skill('implement-ticket')` に引き継ぐ |
| `3` | Codex 利用不可 | **このセッションは以降ずっと `Skill('implement-ticket')` を使う**(恒久フォールバック)。`delegate-codex.sh` を呼び直さない |
| `4` | Codex 側のレート上限 | 一時フォールバック。`tasklist.md` と `git diff --stat` を根拠に**ユーザーへ 3 択を提示する**: (a) 待つ(残タスクが多いとき) (b) `Skill('implement-ticket')` に引き継ぐ(残り 1〜2 タスク) (c) 部分成果を破棄(ビルドが壊れていて進捗が 1 タスク以下)。**司令塔が自分で引き取るのを既定にしない** |
| `5` | 計画が未完成 | `design.md` を書き切り、冒頭の印を `<!-- status: ready -->` に変えてから再委託する。**追記だけでは同じところで止まる** |

4. **Sonnet fork 経路**(`exit 3` を受けた場合、または Codex を使わない判断をした場合): `Skill('implement-ticket')` にステアリングディレクトリのパスを渡して実行し、戻り値の `判定` で分岐する:

| 判定 | 司令塔の対応 |
| --- | --- |
| `完了` | ステップ6(検証)へ進む |
| `判断待ち` | 判断を下し、**`design.md` に追記してから**再実行する。**差し戻しの理由が「計画未完成(`<!-- status: draft -->`)」の場合は、`design.md` を書き切ったうえで印を `<!-- status: ready -->` に変えてから再実行すること** |
| `失敗` | 原因を分析する。設計起因なら `design.md` を修正して再実行、根本原因が不明なら `/model fable` への一時切替をユーザーに提案する |

5. `判断待ち` の往復が 2 回を超えた場合、`design.md` の粒度が不足している。判断を個別に足し続けるのをやめ、`design.md` を書き直してから再開する。

6. **委託が中断したとき**(exit 4、または `bash .claude/scripts/codex-run.sh list` に `status=running(プロセス不在)` が出るとき)は、サマリーが存在しない。`tasklist.md` → `git diff --stat` → 型チェック の順に実態を確かめ、上の 3 択に進む。処理後に `bash .claude/scripts/codex-run.sh set-status [id] [interrupted|discarded|failed]` で record を実態に合わせる。

- **❌ 絶対禁止の行為:**
  - 司令塔が自分で `tasklist.md` を消化すること(委譲を迂回すること)。
  - 未完了タスクを「後でやる」などの理由で意図的にスキップすること。
  - `判断待ち` に対して `design.md` を更新せずに再委託・再実行すること(同じところで再び止まる)。
  - **終了コードを見ずにサマリーの文面で成否を判断すること**(`codex exec` の `exit 0` はタスクの成否を表さない)。
```

ステップ6(検証)の末尾に 1 項目足す:

```markdown
6. Codex に委託した場合、検収が通った時点で `bash .claude/scripts/codex-run.sh accept [run-id]` を実行し、run record の `accepted` を立てる(run-id は委託時の出力に出ている)。立て忘れると未検収の記録が残り続ける。
```

### 3.2 `/next-ticket`

ステップ3 の担当表の実装行を差し替える:

```markdown
| **実装(tasklist の消化)** | **委託(既定 = `delegate-codex.sh impl` / フォールバック = `Skill('implement-ticket')` の Sonnet fork)** |
```

その下の箇条書きの 1 行目「司令塔は実装コードを書かない。モデルの手動切替も不要」に続けて、**分岐の詳細は `/add-feature` ステップ5 の終了コード表に従う**旨を 1 行足す。

### 3.3 `/fix-issue`

ステップ4 の見出しを `### ステップ4: 実装(委託)` に変え、本文を次に差し替える:

```markdown
**司令塔は実装コードを書かない。** 委譲前に `git status` で作業ツリーがクリーンであることを確認したうえで、**既定は `bash .claude/scripts/delegate-codex.sh impl .steering/[dir]`**、`exit 3` なら `Skill('implement-ticket')`(`context: fork` / Sonnet)に切り替える。**終了コードによる分岐の詳細は `/add-feature` ステップ5 の表に従う**(3 コマンドで同一)。
```

以降の行(戻り値の扱いなど)が add-feature の表と重複する場合は、重複を削って参照に寄せる。

---

## 4. マニフェストとドキュメント

### 4.1 `.claude/template-manifest.json`

`.claude/scripts/codex-run.sh` を、既存の `.claude/scripts/*` と同じ配列(`owned`)に足す。`.claude/codex-denylist.txt` が載っている配列と同じ場所。**配列内の並びは既存の並び順の規則(アルファベット順であればそれに従う)に合わせる。**

### 4.2 `README.md`

297 行目付近の `scripts/` の説明に `Codex 委託の run record 操作(codex-run.sh)` を足す。1 行の追記に留める。

### 4.3 `docs/template-dev/codex-delegation-plan.md`

- §11 の段階表の「3. 実装委託」行に ✅ **完了(2026-08-23)** を付ける(段階1・2 と同じ書式)
- §11 の箇条書きに段階3 の結果を 1 項目足す。含める内容: 実装した終了コード、`exit 0` の裏取りをどう入れたか、`exit 4` を実機で再現できなかったこと(要求定義の「既知の逸脱」と同じ内容)、検収の往復回数
- §3.2 の `exit 0` に関する ⚠️ callout に「**段階3 で対処済み**」を追記する(「段階3 で対処する」のままにしない)

### 4.4 `docs/template-dev/codex-harness.html`

**大幅な改稿はしない。** 「impl は未実装」と読める記述だけを実態に合わせる:

- 779 行目付近: 「`impl` モードと `.harness/mode` は**未実装**」→ `impl` は実装済み(段階3)、`.harness/mode` の司令塔側運用が段階4 で残っている、という記述に変える
- 1390〜1400 行目付近の段階カードで、段階3 のカードを段階1・2 と同じ「完了」表現に揃える
- 1427 行目付近「`delegate-codex.sh` が実際に Codex を正しく駆動できるかは段階3 で初めて分かる」→ 段階3 の実機結果を 1 文で追記する

HTML は既存のクラス名・マークアップ様式(`chip ok` など)をそのまま使う。**新しいスタイルやセクションを作らない。**

---

## 5. 検証(実装者が行うところ)

`.claude/scripts/` に自動テストの枠組みは無い。**スクラッチパッドに使い捨ての検証スクリプトを書いて実行し、結果表を報告に含める**(リポジトリにはコミットしない)。

スタブは `PATH` の先頭に置いた `codex` 実行ファイルで作る(段階2 と同じ手法)。`codex login status` に対して常に `exit 0` を返し、`codex exec` の挙動をシナリオごとに変える。

| # | シナリオ | 作り方 | 期待 |
| --- | --- | --- | --- |
| V1 | 引数不正(target が steering でない) | `impl /tmp/nowhere` | exit 2 |
| V2 | design.md が draft | draft マーカーの一時 steering | **exit 5** |
| V3 | design.md にマーカー無し | マーカーを消した一時 steering | 警告を出して先へ進む |
| V4 | 判断待ち | スタブが `--output-last-message` の先へ `判断待ち: ...` を書き exit 0 | **exit 1** / `status=blocked` |
| V5 | 報告が失敗 | スタブが `失敗: ...` を書き exit 0 | exit 2 / `status=failed` |
| V6 | **exit 0 だが何もしない** | スタブが `完了: ...` だけ書いて何も変更しない | **exit 2** / error に「成果物が確認できない」 |
| V7 | 正常完了 | スタブがファイルを 1 つ変更し tasklist を 1 つ `[x]` にして `完了: ...` | exit 0 / `status=completed` |
| V8 | 逐次更新なしの完了 | スタブがファイルだけ変更し tasklist は据え置き | exit 0 + summary に ⚠️ 警告 |
| V9 | レート上限 | スタブがログに `rate_limit_reached` を出し exit 1 | exit 4 / `status=rate-limited` / 生エラー保存 |
| V10 | 二重起動 | `status=running` かつ生存 pid(`$$` を使う)の record を置く | exit 2「二重起動しません」 |
| V11 | 強制終了の残骸 | `status=running` かつ不在 pid(`999999`)の record | 警告を出して先へ進む |
| V12 | hooksPath 未設定 | `git config --unset core.hooksPath` を張った一時クローンか、`git -c` では再現できないため `core.hooksPath` を一時的に外して復元する | exit 3 |
| V13 | `codex-run.sh accept` | V7 の record に対して実行 | `accepted: true` / JSON が壊れない |
| V14 | `codex-run.sh set-status` | 不正な値 → 拒否、`interrupted` → 反映 | exit 1 / 反映 |
| V15 | jq 不在時 | `PATH` から jq を外して V13・V14 | 同じ結果になる |

**V12 は元の設定を必ず復元すること**(`git config core.hooksPath .husky/` 等。実行前に `git config --get core.hooksPath` で控える)。

`explore` / `review` の非回帰も 1 回ずつ確認する(スタブで exit 0 を返させ、record が従来どおり書けること)。

**実機の Codex を使った検証は司令塔が行う**(実装者はスタブまで)。理由: このチケットは `delegate-codex.sh` 自体を書き換えるので、fork の中から実機委託を走らせると自己参照になり切り分けが立たない。

---

## 6. 設計判断の記録(実装者が迷わないための明示)

| 論点 | 決定 | 理由 |
| --- | --- | --- |
| `--background` を今回入れるか | **入れない** | 未検収委託が SessionStart に出る(段階4)まで、非同期にすると委託を忘れる経路ができる。同期なら司令塔が必ず結果を見る |
| `exit 5` の検査で「マーカー無し」をどう扱うか | **通す** | `implement-ticket` スキルと AGENTS.md が同じ規則。経路によらず結果が一致することを優先 |
| `hooksPath` 未設定を `2` でなく `3` にする | **`3`(利用不可)** | 回復手段が「タスクの原因分析」ではなく「環境の修復」。`3` の定義(環境の欠落)に一致する。恒久ではないが、`4`(枠切れ)よりは `3` が近い |
| 保護ブランチ上の委託を `2` にする | **`2`** | 環境ではなく使い方の誤り。ブランチを切れば同じ委託がそのまま通る |
| `.harness/` を `check-implementation-phase.sh` の許可リストに足すか | **足さない** | record は機械が書く状態ファイル。手編集を正規経路にすると JSON 破損の経路が増える。代わりに `codex-run.sh` を置く |
| `rec_field` を共有ファイルに切り出すか | **切り出さない** | 2 箇所・十数行。共有ファイルを増やすと `/sync-template` のマニフェスト管理対象と自壊検知の対象が増える |
| `codex-run.sh` の終了コードを `delegate-codex.sh` に揃えるか | **揃えない** | 別系統(`0`/`1`/`2`)にし、ヘッダーコメントに明記する。委託の契約コードと同じ形にすると司令塔が取り違える |
