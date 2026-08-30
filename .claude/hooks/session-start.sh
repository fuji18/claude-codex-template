#!/bin/bash
# SessionStart hook:
#   1) Claude Code on the web(リモート環境)では依存関係をインストールする
#   2) resume / clear 時は「現在地」(ブランチ・in-progress Issue・未完了タスク)を
#      コンテキストに自動注入する(チケット区切りの /clear 運用を支える)。
#      web リモートでは毎セッションが startup のため、startup でも注入する
#   3) startup 時にコード規模を検知し、serena MCP 再導入の目安超過を通知する
#   4) 司令塔専用ルール(.claude/rules/lead/*.md)を注入する
#   5) ハーネスモード(.harness/mode)が normal 以外なら .claude/rules/mode/*.md を注入する
#   6) 未検収の Codex 委託(.harness/codex-runs/)を注入する
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // "startup"' 2>/dev/null || echo "startup")"

cd "${CLAUDE_PROJECT_DIR:-.}"

# --- 1) 依存関係(リモート環境のみ。devcontainer では post_create.sh が担う) ---
# node_modules があればスキップし、resume / clear のたびの再インストールを避ける
if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && [ -f package.json ] && [ ! -d node_modules ]; then
  # stdout はセッションのコンテキストに注入されるため、ログは stderr へ逃がす
  if npm install --no-audit --no-fund 1>&2; then
    echo "依存関係: npm install 完了(リモート環境)"
  else
    echo "⚠️ npm install に失敗した。検証コマンドの実行前に原因を確認すること"
  fi
fi

# --- ハーネスの自壊検知: hook スクリプトの実行権限が落ちていないか ---
# PreToolUse hook は実行失敗時にフェイルオープン(素通り)になるため、ここで警告する。
# lib-*.sh は source 専用の共有ライブラリ(#45)なので要件が逆になる(非実行が正)。
for s in .claude/scripts/*.sh .claude/hooks/*.sh; do
  [ -f "$s" ] || continue
  case "$(basename "$s")" in
    lib-*.sh)
      if [ -x "$s" ]; then
        echo "⚠️ source 専用ライブラリに実行権限が付いている: $s(git update-index --chmod=-x で外すこと。CI の harness-integrity が落ちる)"
      fi
      ;;
    *)
      if [ ! -x "$s" ]; then
        echo "⚠️ hook スクリプトに実行権限がない: $s(chmod +x で復旧すること。PreToolUse はフェイルオープンになる)"
      fi
      ;;
  esac
done

# ディスクの権限と git 上の権限は食い違いうる。core.fileMode=false の環境(WSL や
# Windows マウント経由の devcontainer では珍しくない)では、ディスクが +x でも
# 新規スクリプトは 100644 で index に入る。ディスクだけを見る上の検査は素通しし、
# クリーンなクローンで動く CI の harness-integrity だけが PR で落ちる。
# = 「気づくのが最も遅い層」でしか検知できないので、ここでも見る。
if command -v git >/dev/null 2>&1; then
  # git ls-files -s の出力は "<mode> <sha> <stage>\tパス"。パスに空白が入っても
  # 切れないよう、フィールド分割ではなくタブ以降を丸ごと取る。
  # lib-*.sh は 100644 が正、それ以外の *.sh は 100755 が正(#45)。
  BADMODE="$(git ls-files -s .claude/scripts/ .claude/hooks/ 2>/dev/null |
    awk -F'\t' '
      $2 !~ /\.sh$/ { next }
      {
        n = split($2, p, "/")
        if (p[n] ~ /^lib-/) {
          if ($1 ~ /^100755 /) print $2 "  → 実行ビットを外す: git update-index --chmod=-x " $2
        } else {
          if ($1 !~ /^100755 /) print $2 "  → 実行ビットを付ける: git update-index --chmod=+x " $2
        }
      }')"
  if [ -n "$BADMODE" ]; then
    echo "⚠️ git 上の実行ビットが種別と合っていないスクリプトがある(CI の harness-integrity が落ちる):"
    printf '%s\n' "$BADMODE" | sed 's/^/   - /'
    echo "   chmod だけでは core.fileMode=false の環境で index に反映されない"
  fi
fi

# ベンダー非依存の防衛線(.husky/* → check-protected-branch.sh)が生きているか。
# .husky/ は template-manifest の merge 対象=手動統合のため、/sync-template の統合ミスで
# 呼び出しごと落ちても誰も気づかない。層が無いことより、無くなったのに気づけない方が悪い。
# 判定の実体は共有スクリプトに集約する(CI の harness-integrity と同じ結果になることが要件)。
if [ -f .claude/scripts/check-guard-integrity.sh ]; then
  GUARD_ISSUES="$(bash .claude/scripts/check-guard-integrity.sh 2>/dev/null || true)"
  [ -n "$GUARD_ISSUES" ] && printf '%s\n' "$GUARD_ISSUES" | sed 's/^/⚠️ /'
fi

# git hook 自体が有効化されているか。husky は prepare スクリプトが core.hooksPath を
# 設定して初めて効くため、依存未インストールのクローン直後は .husky/ が丸ごと無効。
if [ -d .husky ] && [ -z "$(git config --get core.hooksPath 2>/dev/null)" ]; then
  echo "⚠️ git hook が無効(core.hooksPath 未設定)。npm ci で husky が有効化されるまで .husky/ のフックは一切動かない"
fi

# --- 4) 司令塔専用ルールの注入(全 source: startup / resume / clear / compact) ---
# .claude/rules/lead/*.md は CLAUDE.md から @ インポートしない。CLAUDE.md 経由にすると
# 全サブエージェントにも毎回ロードされてしまうため(サブエージェント側では実行不能・無意味な指示)。
# SessionStart はメインセッションでのみ発火する(サブエージェント起動時は SubagentStart)ため、
# ここで注入すれば司令塔にだけ届く。判断の根拠は docs/template-dev/cost-model.md を参照。
if [ -d .claude/rules/lead ]; then
  LEAD_OUT=""
  for f in .claude/rules/lead/*.md; do
    [ -f "$f" ] || continue
    LEAD_OUT="${LEAD_OUT}$(cat "$f")"$'\n\n'
  done
  if [ -n "$LEAD_OUT" ]; then
    echo "# 司令塔専用ルール(SessionStart 注入 / サブエージェントには読み込まれません)"
    echo
    printf '%s' "$LEAD_OUT"
  fi
fi

# --- 5) ハーネスモードの注入(全 source: startup / resume / clear / compact) ---
# モードは推測させない(§2.2)。単一ソースは .harness/mode で、読み取りの実体は
# harness-mode.sh に集約してある(Codex 側 = delegate-codex.sh と同じ結果になることが要件)。
# normal のときは何も出さない: 既定モードのセッションで毎回数十行を注入するのは、
# モード B が節約しようとしているコンテキストそのものを食う。
HMODE="normal"
if [ -f .claude/scripts/harness-mode.sh ]; then
  # 不正値の警告は stderr に出る。stderr はコンテキストに載らないため、拾って stdout に回す。
  HMODE_WARN="$(bash .claude/scripts/harness-mode.sh 2>&1 >/dev/null || true)"
  HMODE="$(bash .claude/scripts/harness-mode.sh 2>/dev/null || echo normal)"
  [ -n "$HMODE_WARN" ] && printf '%s\n' "$HMODE_WARN"
fi
[ -n "$HMODE" ] || HMODE="normal"

if [ "$HMODE" != "normal" ] && [ -f ".claude/rules/mode/$HMODE.md" ]; then
  echo "# ハーネスモード(SessionStart 注入 / 切替を宣言するのは人間です)"
  echo
  cat ".claude/rules/mode/$HMODE.md"
  echo
fi

# --- 6) Codex 委託の未検収(§3.4) ---
# 判定の実体は codex-run.sh に集約する(list と同じ規則になることが要件)。
# 「現在地」ブロックが出る source ではその中に混ぜ、出ない source(通常の startup)では
# 単独の見出しで出す。モード B の実運用では「司令塔がセッションを閉じる → 人間が委託 →
# 新セッションを開く」が既定経路であり、再開が /clear とは限らない。
CODEX_PENDING=""
if [ -f .claude/scripts/codex-run.sh ]; then
  CODEX_PENDING="$(bash .claude/scripts/codex-run.sh pending 2>/dev/null || true)"
fi

# --- 2) serena MCP 再導入の規模検知(startup 時のみ・検知は自動、判断は人間) ---
# しきい値と判断材料・再導入手順は .claude/docs/serena-reintroduction.md を参照
# (.mcp.json には context7 等の他サーバーもあるため、serena エントリの有無で判定する)
if [ "$SOURCE" = "startup" ] && ! grep -qs '"serena"' .mcp.json; then
  TS_FILES="$(git ls-files '*.ts' '*.tsx' 2>/dev/null | wc -l)"
  TS_LOC="$(git ls-files '*.ts' '*.tsx' 2>/dev/null | xargs -r cat 2>/dev/null | wc -l)"
  if [ "${TS_LOC:-0}" -gt 30000 ] || [ "${TS_FILES:-0}" -gt 300 ]; then
    echo "コード規模が serena MCP 再導入の目安を超えた(TS: ${TS_LOC} 行 / ${TS_FILES} ファイル)。.claude/docs/serena-reintroduction.md を読み、再導入をユーザーに提案すること"
  fi
fi

# --- 3) resume / clear 時の現在地オリエンテーション ---
# web リモート(CLAUDE_CODE_REMOTE=true)は /clear せず新セッションを作る運用のため startup も対象
if [ "$SOURCE" = "resume" ] || [ "$SOURCE" = "clear" ] || { [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && [ "$SOURCE" = "startup" ]; }; then
  echo "## 現在地(SessionStart 自動オリエンテーション)"
  CUR_BRANCH="$(git branch --show-current 2>/dev/null || echo '不明')"
  echo "- ブランチ: $CUR_BRANCH"

  # --- ブランチ戦略の事実提示と乖離検知 ---
  # 推測させないことが目的。アプリ(リモートセッション)はプラットフォームが
  # 既定ブランチ(通常 main)起点で claude/* ブランチを先に作るため、
  # Git Flow(develop 起点)を採るプロジェクトでは base が乖離しやすい。
  POLICY=".claude/branch-policy.json"
  if [ -f "$POLICY" ] && command -v jq >/dev/null 2>&1; then
    BASE="$(jq -r '.baseBranch // "main"' "$POLICY" 2>/dev/null || echo main)"
    RELEASE_BASE="$(jq -r '.releaseBase // "main"' "$POLICY" 2>/dev/null || echo main)"

    EXPECTED="$BASE"
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      case "$CUR_BRANCH" in "$p"*) EXPECTED="$RELEASE_BASE" ;; esac
    done < <(jq -r '.releasePrefixes // [] | .[]' "$POLICY" 2>/dev/null)

    echo "- PR のベースブランチ(ポリシー): $EXPECTED(根拠: $POLICY。推測せずこの値を使うこと)"

    if git show-ref --verify -q "refs/remotes/origin/$EXPECTED" &&
      ! git merge-base --is-ancestor "origin/$EXPECTED" HEAD 2>/dev/null; then
      echo "  ⚠️ 現ブランチは origin/$EXPECTED を含まない(アプリ既定の $(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || echo main) 起点の可能性)。"
      echo "     PR 作成前に \`git merge origin/$EXPECTED\` で追従し、\`gh pr create --base $EXPECTED\` を明示すること"
    fi

    if jq -e --arg b "$CUR_BRANCH" '.protectedBranches // [] | index($b)' "$POLICY" >/dev/null 2>&1; then
      echo "  ⚠️ 保護ブランチ上にいる。実装を始める前に作業ブランチを切ること(直接コミットは hook がブロックする)"
    fi

    # リモートセッション生成ブランチはリネームしない(セッションとブランチの紐付けが壊れるため)
    REMOTE_PREFIX="$(jq -r '.remoteSessionPrefix // empty' "$POLICY" 2>/dev/null)"
    if [ -n "$REMOTE_PREFIX" ]; then
      case "$CUR_BRANCH" in
        "$REMOTE_PREFIX"*)
          echo "  ℹ️ プラットフォーム生成ブランチ($REMOTE_PREFIX*)。ポリシー上 feature/* と同格の正規ブランチであり、**リネームしないこと**(セッションとの紐付けが壊れる)。守るべきは base と PR 規約"
          ;;
      esac
    fi
  fi

  CHANGES="$(git status --short 2>/dev/null | head -10 || true)"
  if [ -n "$CHANGES" ]; then
    echo "- 未コミット変更:"
    printf '%s\n' "$CHANGES" | sed 's/^/  /'
  else
    echo "- 未コミット変更: なし"
  fi

  if command -v gh >/dev/null 2>&1; then
    ISSUES="$(gh issue list --label in-progress --state open --limit 5 2>/dev/null || true)"
    if [ -n "$ISSUES" ]; then
      echo "- in-progress チケット:"
      printf '%s\n' "$ISSUES" | sed 's/^/  /'
    fi
  else
    echo "- in-progress チケット: 未取得(gh CLI が無い環境。GitHub MCP ツールで確認する)"
  fi

  [ -n "$CODEX_PENDING" ] && printf '%s\n' "$CODEX_PENDING"

  # 選定規則は latest-steering.sh に集約する(hook・fork と同じ結果になることが要件)
  LATEST_STEERING="$(bash .claude/scripts/latest-steering.sh 2>/dev/null || true)"
  if [ -n "$LATEST_STEERING" ] && [ -f "${LATEST_STEERING}tasklist.md" ]; then
    UNDONE="$(grep -E '^[[:space:]]*- \[ \]' "${LATEST_STEERING}tasklist.md" 2>/dev/null | head -10 || true)"
    if [ -n "$UNDONE" ]; then
      echo "- 最新ステアリング(${LATEST_STEERING})の未完了タスク:"
      printf '%s\n' "$UNDONE" | sed 's/^/  /'
      echo "- 作業を再開する場合は /resume-work、次のチケットに進む場合は /next-ticket"
    fi
  fi
else
  # 現在地ブロックが出ない source(通常の startup)でも、未検収委託だけは出す。
  # 委託を挟んだ再開は /clear とは限らない(モード B ではセッションを閉じるのが既定)。
  if [ -n "$CODEX_PENDING" ]; then
    echo "## Codex 委託(未検収)"
    printf '%s\n' "$CODEX_PENDING"
  fi
fi

exit 0
