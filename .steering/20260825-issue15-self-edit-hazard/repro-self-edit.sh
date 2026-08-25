#!/bin/bash
# 再現テスト: delegate-codex.sh の自己編集ハザード対策の検証
#
# design.md §3 の手順どおり、実物の .claude/scripts/delegate-codex.sh を
# 実行中に書き換えることで事象を再現し、対策の有無で結果が変わることを確認する。
# codex は本物を呼ばず、PATH 上のスタブに差し替える(枠を消費しない)。
#
# 実行方法:
#   bash .steering/20260825-issue15-self-edit-hazard/repro-self-edit.sh
#
# 各チェックを PASS / FAIL の 1 行で出力し、末尾に集計を出す。
# 1 つでも FAIL があれば exit 1。
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$ROOT" ]; then
  echo "repro-self-edit: git リポジトリの外では実行できません" >&2
  exit 1
fi
cd "$ROOT" || exit 1

REAL_SCRIPT="$ROOT/.claude/scripts/delegate-codex.sh"
RUN_DIR_ABS="$ROOT/.harness/codex-runs"

WORK_DIR="$(mktemp -d)"
BACKUP_SCRIPT="$WORK_DIR/delegate-codex.sh.orig"
STUB_DIR="$WORK_DIR/stub"
OUT_DIR="$WORK_DIR/out"
mkdir -p "$STUB_DIR" "$OUT_DIR"
cp "$REAL_SCRIPT" "$BACKUP_SCRIPT"

FIXTURE_DIR="$ROOT/tmp/repro-issue15"
FIXTURE_DRAFT_DIR="$ROOT/tmp/repro-issue15-draft"
FIXTURE_MISSING_DIR="$ROOT/tmp/repro-issue15-missing" # 意図的に作らない(C3 用)

PASS=0
FAIL=0

record() {
  # $1=name $2=PASS|FAIL $3=detail
  if [ "$2" = "PASS" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
  printf '%s %s %s\n' "$2" "$1" "$3"
}

restore_script() {
  cp "$BACKUP_SCRIPT" "$REAL_SCRIPT" 2>/dev/null && return 0

  # ここに来るのは cp が失敗したときだけ。最後の砦の git checkout は HEAD へ巻き戻すため、
  # **検証中の未コミットパッチを道連れにする**。黙って実行してはいけないので、先に
  # 退避コピーを作業ツリー外(gitignore 済みの tmp/)へ置き、何が起きたかを必ず知らせる。
  local rescue="$ROOT/tmp/delegate-codex.sh.rescue"
  mkdir -p "$ROOT/tmp" 2>/dev/null
  cp "$BACKUP_SCRIPT" "$rescue" 2>/dev/null
  cat >&2 <<MSG
repro-self-edit: 警告 — delegate-codex.sh の復元(cp)に失敗しました。
  退避コピー: $rescue
  最後の手段として git checkout で HEAD の内容へ戻します。
  **未コミットの変更(検証中のパッチを含む)が失われます。** 上の退避コピーから復旧してください。
MSG
  git -C "$ROOT" checkout -- .claude/scripts/delegate-codex.sh 2>/dev/null
}

cleanup() {
  restore_script
  rm -rf "$WORK_DIR" "$FIXTURE_DIR" "$FIXTURE_DRAFT_DIR" "$FIXTURE_MISSING_DIR" 2>/dev/null
  # 生成した run record のうち、フィクスチャの steering を指すものだけを消す。
  if [ -d "$RUN_DIR_ABS" ]; then
    for _f in "$RUN_DIR_ABS"/*.json; do
      [ -f "$_f" ] || continue
      if grep -q '"steering":[[:space:]]*"tmp/repro-issue15' "$_f" 2>/dev/null; then
        _base="${_f%.json}"
        rm -f "$_f" "$_base.log" "$_base.last.txt"
      fi
    done
  fi
}
trap cleanup EXIT

# ---------- スタブ codex ----------
#
# REPRO_TARGET_SCRIPT / REPRO_EDIT / REPRO_TASKLIST は呼び出し側(このスクリプト)が
# 環境変数として渡す。delegate-codex.sh は素通しするので codex exec の子プロセスにも
# 伝わる。
cat >"$STUB_DIR/codex" <<'STUB'
#!/bin/bash
set -uo pipefail

if [ "${1:-}" = "login" ]; then
  exit 0
fi

if [ "${1:-}" = "exec" ]; then
  last=""
  prev=""
  for a in "$@"; do
    if [ "$prev" = "--output-last-message" ]; then
      last="$a"
    fi
    prev="$a"
  done

  target="${REPRO_TARGET_SCRIPT:?REPRO_TARGET_SCRIPT が未設定です}"
  case "${REPRO_EDIT:-overwrite}" in
    overwrite)
      # ファイル全体を fi だけの 20000 行で上書きする(決定論的に構文エラーを起こす)。
      yes fi | head -20000 >"$target"
      ;;
    insert)
      # shebang の直後に 400 行のパディングを挿入する(前方へのバイト挿入でオフセットがずれる)。
      _tmp="$(mktemp)"
      head -1 "$target" >"$_tmp"
      yes '# pad' | head -400 >>"$_tmp"
      tail -n +2 "$target" >>"$_tmp"
      mv "$_tmp" "$target"
      ;;
  esac

  if [ -n "${REPRO_TASKLIST:-}" ] && [ -f "$REPRO_TASKLIST" ]; then
    echo "- [x] スタブによる完了印" >>"$REPRO_TASKLIST"
  fi

  if [ -n "$last" ]; then
    echo "完了: tasklist 1/1 / 変更 1 ファイル / lint・型・関連テスト pass" >"$last"
  fi
  exit 0
fi

exit 0
STUB
chmod +x "$STUB_DIR/codex"

# ---------- フィクスチャ ----------

reset_fixture() {
  rm -rf "$FIXTURE_DIR"
  mkdir -p "$FIXTURE_DIR"
  printf '%s\n' '<!-- status: ready -->' >"$FIXTURE_DIR/design.md"
  printf '%s\n' '- [ ] ダミータスク' >"$FIXTURE_DIR/tasklist.md"
}

reset_draft_fixture() {
  rm -rf "$FIXTURE_DRAFT_DIR"
  mkdir -p "$FIXTURE_DRAFT_DIR"
  printf '%s\n' '<!-- status: draft -->' >"$FIXTURE_DRAFT_DIR/design.md"
  printf '%s\n' '- [ ] ダミータスク' >"$FIXTURE_DRAFT_DIR/tasklist.md"
}

# ---------- ヘルパー ----------

rec_status() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.status // empty' "$1" 2>/dev/null
  else
    sed -n 's/^[[:space:]]*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -1
  fi
}

list_records() { find "$RUN_DIR_ABS" -maxdepth 1 -name '*.json' 2>/dev/null | sort; }

# $1=id $2=no-copy(1 or "") $3=edit-mode
# 標準出力: "exit_code|status|record_path"
run_scenario() {
  local id="$1" no_copy="$2" edit="$3"
  local before after new_file exit_code status
  reset_fixture
  restore_script

  before="$(list_records)"

  if [ "$no_copy" = "1" ]; then
    REPRO_EDIT="$edit" REPRO_TARGET_SCRIPT="$REAL_SCRIPT" REPRO_TASKLIST="$FIXTURE_DIR/tasklist.md" \
      CODEX_DELEGATE_NO_SELF_COPY=1 CODEX_DELEGATE_ACK_SECRETS=1 \
      PATH="$STUB_DIR:$PATH" \
      timeout 60 bash "$REAL_SCRIPT" impl tmp/repro-issue15 >"$OUT_DIR/$id.out" 2>&1
  else
    REPRO_EDIT="$edit" REPRO_TARGET_SCRIPT="$REAL_SCRIPT" REPRO_TASKLIST="$FIXTURE_DIR/tasklist.md" \
      CODEX_DELEGATE_ACK_SECRETS=1 \
      PATH="$STUB_DIR:$PATH" \
      timeout 60 bash "$REAL_SCRIPT" impl tmp/repro-issue15 >"$OUT_DIR/$id.out" 2>&1
  fi
  exit_code=$?

  restore_script

  after="$(list_records)"
  new_file="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -1)"
  status=""
  [ -n "$new_file" ] && status="$(rec_status "$new_file")"

  printf '%s|%s|%s\n' "$exit_code" "$status" "$new_file"
}

# ---------- S1〜S3 ----------

echo "== S1〜S3: 自己編集ハザードの再現 =="

# S1: 対策を切った状態(CODEX_DELEGATE_NO_SELF_COPY=1)で overwrite。
# 旧挙動の再現 = 非 0 で終了し、run record が running のまま孤児化する。
s1_out="$(run_scenario S1 1 overwrite)"
s1_exit="${s1_out%%|*}"
s1_rest="${s1_out#*|}"
s1_status="${s1_rest%%|*}"

if [ "$s1_exit" = "0" ]; then
  record S1 FAIL "exit=0(旧挙動が再現しませんでした。再現方法が無効なため、S2/S3 の PASS は対策の検証になっていません)"
elif [ "$s1_status" = "running" ]; then
  record S1 PASS "exit=$s1_exit status=running(孤児化を確認)"
else
  record S1 FAIL "exit=$s1_exit だが status=$s1_status(running を期待)"
fi

# S2: 対策を有効にした状態で overwrite。exit 0 / completed を期待する。
# あわせて一時ディレクトリの後始末(§3.6)もこの実行の前後で測る。
TMP_PARENT="${TMPDIR:-/tmp}"
count_tmp_entries() { find "$TMP_PARENT" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' '; }

leak_before="$(count_tmp_entries)"
s2_out="$(run_scenario S2 "" overwrite)"
leak_after="$(count_tmp_entries)"

s2_exit="${s2_out%%|*}"
s2_rest="${s2_out#*|}"
s2_status="${s2_rest%%|*}"

if [ "$s2_exit" = "0" ] && [ "$s2_status" = "completed" ]; then
  record S2 PASS "exit=0 status=completed"
else
  record S2 FAIL "exit=$s2_exit status=$s2_status(exit=0 / status=completed を期待)。出力: $(tail -5 "$OUT_DIR/S2.out" 2>/dev/null | tr '\n' ' ')"
fi

if [ "$leak_after" -le "$leak_before" ]; then
  record S2-leak PASS "$TMP_PARENT 直下のエントリ数: 前=$leak_before 後=$leak_after"
else
  record S2-leak FAIL "$TMP_PARENT 直下のエントリ数が増えました: 前=$leak_before 後=$leak_after(自己コピーの trap が効いていない可能性)"
fi

# S3: 対策を有効にした状態で insert。exit 0 / completed を期待する。
s3_out="$(run_scenario S3 "" insert)"
s3_exit="${s3_out%%|*}"
s3_rest="${s3_out#*|}"
s3_status="${s3_rest%%|*}"

if [ "$s3_exit" = "0" ] && [ "$s3_status" = "completed" ]; then
  record S3 PASS "exit=0 status=completed"
else
  record S3 FAIL "exit=$s3_exit status=$s3_status(exit=0 / status=completed を期待)。出力: $(tail -5 "$OUT_DIR/S3.out" 2>/dev/null | tr '\n' ' ')"
fi

# ---------- C1〜C6: 終了コード契約の非回帰チェック ----------

echo "== C1〜C6: 終了コード契約の非回帰チェック =="

run_contract() {
  local name="$1" expect="$2" path_override="$3"
  shift 3
  local exit_code
  CODEX_DELEGATE_ACK_SECRETS=1 PATH="${path_override:-$STUB_DIR:$PATH}" \
    timeout 30 bash "$REAL_SCRIPT" "$@" >"$OUT_DIR/$name.out" 2>&1
  exit_code=$?
  if [ "$exit_code" = "$expect" ]; then
    record "$name" PASS "exit=$exit_code(期待 $expect)"
  else
    record "$name" FAIL "exit=$exit_code(期待 $expect)。出力: $(tail -3 "$OUT_DIR/$name.out" 2>/dev/null | tr '\n' ' ')"
  fi
}

# C1: 引数なし
run_contract C1 2 "" </dev/null

# C2: 未実装モード
run_contract C2 2 "" fix-ci x

# C3: ステアリングでない target(存在しないディレクトリ)
run_contract C3 2 "" impl tmp/repro-issue15-missing

# C4: draft の design.md を持つディレクトリ
reset_draft_fixture
run_contract C4 5 "" impl tmp/repro-issue15-draft

# C5: 未知のオプション
run_contract C5 2 "" explore x --unknown-opt

# C6: codex も npx も見えない PATH → EX_UNAVAIL=3(理由の区別はしない)
run_contract C6 3 "/usr/bin:/bin" explore x

# ---------- 後始末の確認 ----------

echo "== 後始末 =="

if cmp -s "$BACKUP_SCRIPT" "$REAL_SCRIPT"; then
  record restore PASS "delegate-codex.sh は元の内容に戻っています"
else
  record restore FAIL "delegate-codex.sh が元の内容と一致しません(実物が壊れている可能性)"
fi

# ---------- 集計 ----------

echo "== 集計 =="
echo "PASS=$PASS FAIL=$FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
