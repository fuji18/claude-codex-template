# 設計: Issue #29 run record のローテーション(prune)

<!-- status: ready -->

変更対象は 3 ファイル。**新規ファイルは作らない。**

| ファイル | 変更 |
| --- | --- |
| `.claude/scripts/codex-run.sh` | `prune` サブコマンド追加(ヘッダ・usage・dispatch も) |
| `.claude/scripts/delegate-codex.sh` | 起動時の件数警告(削除はしない)を 1 ブロック挿入 |
| `docs/template-dev/codex-delegation-plan.md` | §12.8 を新設。`forbidden_snapshot()` のコメント更新は codex-run 側ではなく delegate 側 |

## 0. 設計判断(実装者は判断しない。ここに書いた通りに書く)

- **既定の残し方は「accepted かつ、直近 N 本より古いもの」だけを消す**。日数(M 日より古い)は採らない。record の時刻源が `startedAt` 文字列と ID しか無く、`date -d` が GNU 依存(`cmd_pending` のコメント参照)で非 GNU 環境では静かに空振りするため。件数基準なら jq の有無にも `date` の実装にも依存しない
- **新旧の判定は record のファイル名(= `RUN_ID` = `YYYYMMDD-HHMMSS-PID`)の辞書順**。`startedAt` を読むより安く、`rec_field` の 2 経路(jq / sed)に依存しない
- **`--keep` の既定は 20**
- **未検収も消せる逃げ道は用意する**(`--include-unaccepted`)。Issue の「未検収は**既定では**消さない」に対応する。ただし実行中(pid 生存)はこのフラグでも消さない
- **自動削除はしない。** `delegate-codex.sh` 側は警告のみ(Issue の案B)

## 1. `codex-run.sh`: ヘッダと usage

### 1.1 ヘッダのコマンド一覧(冒頭コメント)

`#   .claude/scripts/codex-run.sh set-status <id> <status>` の**次の行**に 1 行足す:

```bash
#   .claude/scripts/codex-run.sh prune [--dry-run] [--keep N] [--include-unaccepted]
```

### 1.2 `usage()` のヒアドキュメント

`set-status` の説明ブロック(`(running / completed / ... / discarded)` の行)の**後ろ**に足す:

```
  prune [options]       検収済みの古い run record を 3 点セットで削除する
                          --dry-run              消さずに対象を表示する
                          --keep N               新しい順に N 本は残す(既定 20)
                          --include-unaccepted   未検収(accepted != true)も対象にする
                        実行中(status=running かつ pid 生存)は常に残す
```

## 2. `codex-run.sh`: `cmd_prune()`

`cmd_set_status()` の**閉じ括弧の直後**、`SUBCOMMAND="${1:-}"` の行の**前**に挿入する。

```bash
# run record の 3 点セット(<id>.json / <id>.log / <id>.last.txt)をまとめて削除する。
# 自動実行はしない(人間が明示的に叩く)。run record は「会話に依存しない状態の正」で、
# 勝手に消えると検収漏れが静かに発生するため。
#
# 既定で残すもの:
#   - 新しい順に --keep N 本(既定 20)
#   - accepted != true の record(未検収 = 検収キュー。--include-unaccepted で対象に入る)
#   - status=running かつ pid 生存(実行中。--include-unaccepted でも消さない)
#
# 新旧はファイル名(RUN_ID = YYYYMMDD-HHMMSS-PID)の辞書順で判定する。delegate-codex.sh が
# 必ずこの形で採番するため、startedAt を読むより安く、jq の有無にも date の実装にも依存しない。
cmd_prune() {
  local _dry=0 _keep=20 _unaccepted=0
  local _files=() _f _id _status _accepted _pid _skip
  local _rank=0 _cand=0 _removed=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) _dry=1 ;;
      --include-unaccepted) _unaccepted=1 ;;
      --keep)
        shift
        _keep="${1:-}"
        ;;
      --keep=*) _keep="${1#--keep=}" ;;
      *)
        echo "codex-run: prune の不明なオプションです: $1" >&2
        usage
        exit 2
        ;;
    esac
    shift
  done

  case "$_keep" in
    '' | *[!0-9]*)
      echo "codex-run: --keep には 0 以上の整数を指定してください: $_keep" >&2
      exit 1
      ;;
  esac

  [ -d "$RUN_DIR" ] || {
    echo "削除対象の record はありません"
    exit 0
  }

  # 逆順に並べて「新しい順」にする。glob の並びはロケール依存なので sort に任せる。
  # マッチが 0 件のときは glob 文字列がそのまま来るため [ -f ] で落とす。
  while IFS= read -r _f; do
    [ -f "$_f" ] || continue
    _files+=("$_f")
  done < <(printf '%s\n' "$RUN_DIR"/*.json | LC_ALL=C sort -r)

  for _f in "${_files[@]+"${_files[@]}"}"; do
    _rank=$((_rank + 1))
    _id="${_f##*/}"
    _id="${_id%.json}"

    # find_record と同じ理由の防御。id はこの後 rm のパスになる。
    case "$_id" in
      '' | */* | *..*)
        echo "スキップ: $_id(不正な id)" >&2
        continue
        ;;
    esac

    _status="$(rec_field "$_f" status)"
    _accepted="$(rec_field "$_f" accepted)"
    _skip=""

    if [ "$_rank" -le "$_keep" ]; then
      _skip="直近 ${_keep} 本"
    elif [ "$_accepted" != "true" ] && [ "$_unaccepted" -eq 0 ]; then
      _skip="未検収"
    elif [ "$_status" = "running" ]; then
      _pid="$(rec_field "$_f" pid)"
      if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
        _skip="実行中(pid=$_pid)"
      fi
    fi

    if [ -n "$_skip" ]; then
      [ "$_dry" -eq 1 ] && echo "残す: $_id  ($_skip)"
      continue
    fi

    _cand=$((_cand + 1))
    if [ "$_dry" -eq 1 ]; then
      echo "削除候補: $_id  (status=${_status:-不明} accepted=${_accepted:-不明})"
      continue
    fi

    # 3 点セット単位。片方だけ残さない(log だけ残ると出口検査のハッシュ対象に残り続ける)。
    rm -f -- "$RUN_DIR/$_id.json" "$RUN_DIR/$_id.log" "$RUN_DIR/$_id.last.txt"
    _removed=$((_removed + 1))
  done

  if [ "$_dry" -eq 1 ]; then
    if [ "$_cand" -eq 0 ]; then
      echo "削除対象の record はありません"
    else
      echo "削除候補: ${_cand} 件(--dry-run のため削除していません)"
    fi
  else
    if [ "$_removed" -eq 0 ]; then
      echo "削除対象の record はありません"
    else
      echo "削除: ${_removed} 件"
    fi
  fi
  exit 0
}
```

**注意点(実装者向け)**

- このスクリプトは `set -uo pipefail`(`-e` なし)。`_files=()` を `"${_files[@]+"${_files[@]}"}"` の形で展開しているのは `-u` の下で空配列展開が落ちる bash 3.2 系を避けるため。**この書き方を変えない**
- `while ... done < <(...)` はプロセス置換。パイプにすると `_files` がサブシェルに閉じて空になる
- `rec_field` は既存関数。新しく作らない

## 3. `codex-run.sh`: dispatch

`case "$SUBCOMMAND" in` の `set-status)` 行の**次**に 1 行足す:

```bash
  prune) cmd_prune "$@" ;;
```

他のサブコマンドが `"${1:-}"` 形式で渡しているのに対し、`prune` は可変長オプションを取るため `"$@"` をそのまま渡す(`SUBCOMMAND` を取り出した直後の `shift` で、残りの引数が `"$@"` に入っている)。

## 4. `delegate-codex.sh`: 件数の警告(削除はしない)

### 4.1 挿入位置

`mkdir -p "$RUN_DIR" || exit "$EX_FAIL"` の行の**直後**(`LOG=` の行の前)。

```bash

# run record は自動削除しない(§12.8)。溜まるほど出口検査の forbidden_snapshot() が
# .harness/codex-runs/ 配下を前後 2 回ハッシュするコストが線形に増えるため、閾値を
# 超えたら警告だけ出す。削除の判断は人間が行う(未検収の record は検収キューであり、
# 勝手に消えると検収漏れが静かに発生する)。
RUN_WARN_THRESHOLD=50
REC_COUNT="$(find "$RUN_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
if [ "${REC_COUNT:-0}" -gt "$RUN_WARN_THRESHOLD" ]; then
  echo "delegate-codex: run record が ${REC_COUNT} 件あります(閾値 ${RUN_WARN_THRESHOLD})。\`bash .claude/scripts/codex-run.sh prune --dry-run\` で整理を検討してください(委託は続行します)。" >&2
fi
```

**委託は止めない。** 警告は stderr の 1 行のみで、終了コードにも出力契約にも影響させない。

### 4.2 `forbidden_snapshot()` のコメント更新

「空振り条件」リストの最後の項目を差し替える。現在:

```
#   - .harness/codex-runs/ はローテーションされないため、run record が溜まるほど前後 2 回の
#     ハッシュ計算コストが線形に増える。委託 1 本の所要時間に対しては十分小さいので、
#     ローテーションの整備は別チケットに送っている
```

差し替え後:

```
#   - .harness/codex-runs/ が溜まるほど前後 2 回のハッシュ計算コストが線形に増える。委託 1 本の
#     所要時間に対しては十分小さいため検査対象は絞り込まず、元を断つ側(手動の
#     `codex-run.sh prune`)で抑える。自動削除はしない(Issue #29 / §12.8)
```

## 5. `docs/template-dev/codex-delegation-plan.md`

`### 12.7 委託が入口で止まったとき(exit 2 / 3 / 5)` の節の**末尾**(次の `## 13.` の前)に §12.8 を新設する。

```markdown
### 12.8 run record が溜まってきたとき(prune)

`.harness/codex-runs/` は委託 1 本につき 3 ファイル(`<id>.json` / `<id>.log` / `<id>.last.txt`)を積む。出口検査の `forbidden_snapshot()` はこのディレクトリ配下を**委託の前後 2 回**ハッシュするため、record 数に比例して委託ごとのコストが増える。**自動削除はしない**(run record は会話に依存しない状態の正であり、勝手に消えると検収漏れが静かに発生する)。代わりに 2 層で抑える。

1. **警告(自動)**: `delegate-codex.sh` は起動時に record 数が 50 件を超えていたら stderr に 1 行警告する。**委託は止めない**
2. **削除(手動)**: 人間が `codex-run.sh prune` を叩く

```bash
bash .claude/scripts/codex-run.sh prune --dry-run   # 何が消えるか先に見る
bash .claude/scripts/codex-run.sh prune             # 実行
```

既定で残るもの:

| 条件 | 理由 |
| --- | --- |
| 新しい順に 20 本(`--keep N` で変更) | 直近の委託は検収済みでも手元に残す |
| `accepted != true`(未検収) | 検収キューとして機能している。`--include-unaccepted` で対象に含められる |
| `status=running` かつ pid 生存 | 実行中。フラグでも消さない |

削除は 3 点セット単位で行うため、`.log` だけが残って検査対象に居座ることはない。`.harness/codex-runs/` は `.gitignore` 済みなので、削除がコミット履歴に影響することもない。

**`.harness/decisions.jsonl` は prune の対象外**。あちらは追記のみの永続ログで、性質が違う(§10.7)。
```

## 6. 検証手順

**実リポジトリの `.harness/codex-runs/` を汚さない。** 検証は scratchpad に使い捨ての git リポジトリを作って行う。

```bash
T=/tmp/claude-1000/-workspaces-claude-codex-template/705cc885-21fb-4d81-abc3-3a695db14e4d/scratchpad/prune-test
rm -rf "$T" && mkdir -p "$T/.harness/codex-runs" "$T/.claude/scripts"
cd "$T" && git init -q .
cp /workspaces/claude-codex-template/.claude/scripts/codex-run.sh .claude/scripts/
```

fixture は 3 点セットで作る(`<id>.json` の中身は `write_record` と同じキー構成にする。最低限 `id` / `status` / `pid` / `accepted` / `startedAt` / `mode` / `branch` / `log` があればよい)。

| id | status | accepted | 期待 |
| --- | --- | --- | --- |
| `20260101-000001-1` | completed | true | `--keep 0` で削除される |
| `20260101-000002-1` | completed | false | 既定で残る / `--include-unaccepted` で削除される |
| `20260101-000003-1` | running | true | pid を自分自身($$)にして**常に残る** |
| `20260101-000004-1` | completed | true | `--keep 1` では残る(最新 1 本) |

確認項目:

1. `bash -n .claude/scripts/codex-run.sh` が通る
2. `prune --dry-run --keep 0` が候補を列挙し、**ファイルが 1 つも減らない**(前後で `ls | wc -l` が同じ)
3. `prune --keep 0` で 3 点セットが揃って消える(`<id>.log` / `<id>.last.txt` が残らない)
4. `accepted: false` の record が既定で残る / `--include-unaccepted --keep 0` で消える
5. `status=running` かつ pid 生存の record が `--include-unaccepted --keep 0` でも残る
6. 削除後に `list` / `list --all` / `pending` / `show <残った id>` が正常終了する
7. `--keep abc` が exit 1、`--bogus` が exit 2
8. **jq を外した経路**も確認する: `PATH=/usr/bin:/bin` ではなく、`jq` を見つけられない PATH(例: 一時ディレクトリに `jq` を持たない最小 PATH)で 2〜6 のうち最低 1 ケースを再実行し、`rec_field` の sed 経路でも同じ判定になることを見る
9. `bash -n .claude/scripts/delegate-codex.sh` が通る
10. 検証後 `rm -rf "$T"`。**実リポジトリの `git status` が汚れていないこと**を確認する

結果は `.steering/20260826-issue29-run-record-prune/verification.md` に記録する(コマンドと出力の要点のみ。全ログは貼らない)。

## 7. 検収指摘の反映(code-reviewer)

### 7.1 採用: 非数値 pid のガード(Minor)

`cmd_prune()` の `elif [ "$_status" = "running" ]; then` ブロックの中身を、以下に**丸ごと差し替える**:

```bash
      _pid="$(rec_field "$_f" pid)"
      # 非数値は「pid 不明」に正規化する(kill -0 はエラーで失敗するため)。
      # 判定不能な running は「実行中かもしれない」側に倒して残す — record が壊れている・
      # 強制終了で running のまま残った、という状況こそ #29 の背景であり、ここを削除に
      # 倒すと検収前の record が静かに消える。保護の向きを delegate-codex.sh 5-5
      # (再入防止)と揃える。
      case "$_pid" in '' | *[!0-9]*) _pid="" ;; esac
      if [ -z "$_pid" ] || kill -0 "$_pid" 2>/dev/null; then
        _skip="実行中(pid=${_pid:-不明})"
      fi
```

`status=running` かつ pid 不明の record が残るだけで、`accept` してから prune する / `set-status` で実態に合わせる、という既存の回復経路(§12.6)は塞がない。

### 7.2 不採用(記録のみ)

- **Minor 2(`rec_field` の sed 経路が 1 行 1 キー形式に依存)**: `write_record` 以外が record を書かない前提は既存 5 サブコマンドと共通で、今回持ち込んだものではない。かつ食い違ったときは「未検収として保護」= 安全側に倒れる。`verification.md` に判断だけ残す
- **Minor 3(`find | wc -l` が pipefail で非ゼロを拾いうる)**: `-e` 無しで代入の右辺、終了ステータスを見る分岐も無く無害。`verification.md` に判断だけ残す
