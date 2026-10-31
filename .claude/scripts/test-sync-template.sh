#!/bin/bash
# sync-template.mjs の動作確認。一時ディレクトリに「テンプレート」と「プロジェクト」の
# 2 リポジトリを作り、テンプレートの旧版 → 新版への同期を流して結果を検査する。
#
#   bash .claude/scripts/test-sync-template.sh
#     → 失敗した検査を 1 行ずつ出し、1 件でもあれば exit 1
#
# テンプレート本体の CI(harness-integrity)から呼ぶ。ネットワークは使わない。
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sync-template.mjs"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset GITHUB_REPOSITORY

FAILS=0
check() { # 説明 条件コマンド...
  local desc="$1"; shift
  if ! "$@" >/dev/null 2>&1; then echo "NG: $desc"; FAILS=1; fi
}

T="$WORK/template"; P="$WORK/project"
mkdir -p "$T/.claude/scripts" "$T/.claude/rules" "$T/.github/workflows" "$T/docs/template-dev"
cd "$T" && git init -q -b main

cat > .claude/template-manifest.json <<JSON
{
  "templateRepo": "file://$T",
  "templateBranch": "main",
  "syncedAt": null,
  "syncedDate": null,
  "owned": [".claude/rules/", ".claude/scripts/", ".github/workflows/claude.yml"],
  "merge": [".claude/settings.json", ".claude/scripts/lint-on-edit.sh", ".gitignore", "AGENTS.md", ".claude/template-manifest.json"],
  "never": ["CLAUDE.md", "src/"]
}
JSON
printf 'rule v1\n' > .claude/rules/a.md
printf 'old rule\n' > .claude/rules/obsolete.md
printf '#!/bin/bash\necho v1\n' > .claude/scripts/run.sh && chmod +x .claude/scripts/run.sh
printf '#!/bin/bash\n# lint on edit\nset -u\n\nnpm run lint\n' > .claude/scripts/lint-on-edit.sh && chmod +x .claude/scripts/lint-on-edit.sh
printf 'on: push\n' > .github/workflows/claude.yml
printf '{\n  "permissions": { "allow": ["Bash(git status)"] },\n  "model": "opus"\n}\n' > .claude/settings.json
printf 'node_modules/\n' > .gitignore
printf '# AGENTS\n\n## 検証\nnpm test\n\n## 禁止\n- a\n' > AGENTS.md
printf 'template claude\n' > CLAUDE.md
printf '# CHANGELOG\n\n## 2000-01-01\n\n- **[auto]** 初版\n' > docs/template-dev/CHANGELOG.md
git add -A && git commit -q -m v1
V1="$(git rev-parse HEAD)"

# --- プロジェクトを v1 から作り、ローカルで手を入れる ---
git clone -q "$T" "$P"
cd "$P" && git remote remove origin && git remote add origin https://github.com/example/project.git
jq --arg s "$V1" '.syncedAt=$s | .syncedDate="2000-01-01" | .never += [".github/workflows/claude.yml"]' \
  .claude/template-manifest.json > m && mv m .claude/template-manifest.json
jq '.permissions.allow += ["Bash(flutter test:*)"] | .enabledPlugins = {"x": true}' .claude/settings.json > s && mv s .claude/settings.json
printf '#!/bin/bash\n# lint on edit\nset -u\n\nflutter analyze\n' > .claude/scripts/lint-on-edit.sh
printf 'node_modules/\n.dart_tool/\n' > .gitignore
printf '# AGENTS\n\n## 検証\nflutter test\n\n## 禁止\n- a\n' > AGENTS.md
printf 'project claude\n' > CLAUDE.md
printf 'rule v1 (local edit)\n' > .claude/rules/a.md
printf 'on: workflow_dispatch\n' > .github/workflows/claude.yml
git add -A && git commit -q -m "project setup"

# --- テンプレートを v2 に進める ---
cd "$T"
printf 'rule v2\n' > .claude/rules/a.md
printf 'new rule\n' > .claude/rules/b.md
git rm -q .claude/rules/obsolete.md
printf '#!/bin/bash\necho v2\n' > .claude/scripts/run.sh
printf '#!/bin/bash\n# lint on edit (flock)\nset -u\n\nnpm run lint\n' > .claude/scripts/lint-on-edit.sh
printf 'on: [push, pull_request]\n' > .github/workflows/claude.yml
printf '{\n  "permissions": { "allow": ["Bash(git status)", "Bash(git diff:*)"] },\n  "model": "opus",\n  "env": { "A": "1" }\n}\n' > .claude/settings.json
printf 'node_modules/\n.harness/mode\n' > .gitignore
printf '# AGENTS\n\n## 検証\nnpm test\n\n## 禁止\n- a\n- b\n' > AGENTS.md
printf 'template claude v2\n' > CLAUDE.md
jq '.merge += [".prettierignore"]' .claude/template-manifest.json > m && mv m .claude/template-manifest.json
printf 'dist/\n' > .prettierignore
printf '# CHANGELOG\n\n## 2000-01-02\n\n- **[manual]** AGENTS.md に b を足す\n\n## 2000-01-01\n\n- **[auto]** 初版\n' > docs/template-dev/CHANGELOG.md
git add -A && git commit -q -m v2
V2="$(git rev-parse HEAD)"

# --- dry-run は何も変えない ---
cd "$P"
node "$SCRIPT" --dry-run >/dev/null 2>&1
check "dry-run で作業ツリーが変わらない" test -z "$(git status --porcelain)"

# --- ドリフト検出 ---
node "$SCRIPT" --check-drift > "$WORK/drift.txt" 2>&1; RC=$?
check "--check-drift が exit 3" test "$RC" = 3
check "--check-drift が書き換えた owned を挙げる" grep -q '.claude/rules/a.md' "$WORK/drift.txt"

# --- 同期 ---
node "$SCRIPT" --json > "$WORK/out.json" 2> "$WORK/err.txt"; RC=$?
check "同期が exit 0(競合なし)" test "$RC" = 0
check "owned を上書き" grep -qx 'rule v2' .claude/rules/a.md
check "owned の追加" test -f .claude/rules/b.md
check "owned の削除(ローカル未変更)" test ! -e .claude/rules/obsolete.md
check "owned の実行権限を維持" test -x .claude/scripts/run.sh
check "ローカル書き換えを上書きしたことを報告" jq -e '.driftOverwritten | index(".claude/rules/a.md")' "$WORK/out.json"
check "プロジェクトの never 指定(claude.yml)は触らない" grep -qx 'on: workflow_dispatch' .github/workflows/claude.yml
check "never(CLAUDE.md)は触らない" grep -qx 'project claude' CLAUDE.md
check "owned ディレクトリ内の merge 指定はローカル変更を保持" grep -q 'flutter analyze' .claude/scripts/lint-on-edit.sh
check "同ファイルにテンプレート側の追記も入る" grep -q '(flock)' .claude/scripts/lint-on-edit.sh
check "settings.json: ローカルの許可を保持" jq -e '.permissions.allow | index("Bash(flutter test:*)")' .claude/settings.json
check "settings.json: テンプレートの許可を追加" jq -e '.permissions.allow | index("Bash(git diff:*)")' .claude/settings.json
check "settings.json: テンプレートの新キーを追加" jq -e '.env.A == "1"' .claude/settings.json
check "settings.json: ローカルの独自キーを保持" jq -e '.enabledPlugins.x == true' .claude/settings.json
check ".gitignore: 両側の追記が入る" bash -c 'grep -qx ".dart_tool/" .gitignore && grep -qx ".harness/mode" .gitignore'
check "AGENTS.md: 両側の変更が入る" bash -c 'grep -qx "flutter test" AGENTS.md && grep -qx -- "- b" AGENTS.md'
check "merge の新規ファイルを追加" test -f .prettierignore
check "manifest の syncedAt を進める" jq -e --arg s "$V2" '.syncedAt == $s' .claude/template-manifest.json
check "manifest: テンプレートの追加区分を取り込む" jq -e '.merge | index(".prettierignore")' .claude/template-manifest.json
check "manifest: プロジェクトの never 指定を保持" jq -e '.never | index(".github/workflows/claude.yml")' .claude/template-manifest.json
check "manifest: templateRepo はローカルの値" jq -e --arg t "file://$T" '.templateRepo == $t' .claude/template-manifest.json
check "[manual] 項目を出力" jq -e '.manual | length == 1' "$WORK/out.json"

# --- 競合: 同じ行を両側で変える ---
git add -A && git commit -q -m sync
printf '# AGENTS\n\n## 検証\nflutter test --coverage\n\n## 禁止\n- a\n- b\n' > AGENTS.md
git commit -qam "local change"
cd "$T"
printf '# AGENTS\n\n## 検証\nnpm test -- --run\n\n## 禁止\n- a\n- b\n' > AGENTS.md
git commit -qam v3
cd "$P"
node "$SCRIPT" --json > "$WORK/out3.json" 2>/dev/null; RC=$?
check "競合時は exit 2" test "$RC" = 2
check "競合ファイルを報告" jq -e '.conflicts[0].path == "AGENTS.md"' "$WORK/out3.json"
check "競合マーカーを残す" grep -q '^<<<<<<< project' AGENTS.md

# --- 未コミットの変更があれば止まる ---
git checkout -q -- . && git clean -qfd
printf 'x\n' >> CLAUDE.md
node "$SCRIPT" >/dev/null 2>&1; RC=$?
check "未コミットの変更があれば exit 1" test "$RC" = 1

if [ "$FAILS" -eq 0 ]; then echo "sync-template: all checks passed"; fi
exit "$FAILS"
