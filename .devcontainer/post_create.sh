#!/bin/bash
set -e

echo "=== Post-create setup ==="

# Install Playwright deps (only when the project actually uses Playwright)
echo "[1/5] Installing Playwright dependencies..."
if grep -qE '"(@playwright/test|playwright)"' package.json 2>/dev/null; then
  npx --yes playwright install-deps chromium
else
  echo "  Playwright not found in package.json. Skipping (E2E 導入時に再実行される)."
fi

# Install shellcheck
# シェルスクリプトの静的検査。CI(harness-integrity)が同じ検査を回すので、
# 手元に無いと「CI で初めて指摘に気づく」= ゲートが遅くなる。
# 判定の実体(対象の選定と引数)は .claude/scripts/check-shell.sh に一本化してある。
# set -e 下でも落ちないよう、インストールは if の条件で受ける(失敗しても警告だけ)。
echo "[2/5] Installing shellcheck..."
if command -v shellcheck &>/dev/null; then
  echo "  Already installed ($(shellcheck --version | sed -n 2p))."
elif sudo apt-get update -qq && sudo apt-get install -y -qq shellcheck; then
  echo "  Installed ($(shellcheck --version | sed -n 2p))."
else
  echo "  ⚠️  Failed to install shellcheck. 検査は CI だけで走ります"
  echo "      (手元で見たいなら 'sudo apt-get install -y shellcheck' を実行してください)。"
fi

# Install Claude Code
echo "[3/5] Installing Claude Code..."
npm install -g @anthropic-ai/claude-code

# Install Codex CLI (Codex 併用ハーネスの前提。docs/template-dev/codex-harness.html §12.4)
# 認証(codex login)はリビルドのたびに人間の手動操作が要る。~/.codex は
# コンテナ内にしか無いため、ここで入れられるのは CLI 本体だけ。
#
# 本体パッケージはランチャー(bin/codex.js)だけを含み、実体はプラットフォーム別の
# optionalDependencies(エイリアス指定)で降ってくる。optional なので取得に失敗しても
# npm install は成功扱いで終わり、実行時に初めて
#   Error: Missing optional dependency @openai/codex-linux-x64
# で落ちる。インストール成否は npm ではなく codex --version で判定する。
echo "[4/5] Installing Codex CLI..."
npm install -g @openai/codex || true
if ! codex --version &>/dev/null; then
  echo "  ⚠️  プラットフォーム別バイナリの取得に失敗。再試行します..."
  npm install -g @openai/codex@latest || true
fi
if codex --version &>/dev/null; then
  if codex login status &>/dev/null; then
    echo "  Already authenticated with Codex."
  else
    echo "  ⚠️  Not authenticated. Run 'codex login'(通らなければ 'codex login --device-auth')."
    echo "      '--with-api-key' は使わないこと(ChatGPT Plus 枠ではなく API 従量課金になる)。"
  fi
else
  echo "  ⚠️  Codex CLI のインストールに失敗しました。手動で 'npm install -g @openai/codex@latest' を実行してください。"
fi

# GitHub authentication
# Codespaces が注入する GITHUB_TOKEN を尊重し、ローカル devcontainer では
# LOCAL_GH_TOKEN(ホストの GH_TOKEN)をフォールバックとして使う
echo "[5/5] Setting up GitHub authentication..."
GITHUB_TOKEN="${GITHUB_TOKEN:-${LOCAL_GH_TOKEN:-}}"
if gh auth status &>/dev/null; then
  echo "  Already authenticated with GitHub."
elif [ -n "$GITHUB_TOKEN" ]; then
  echo "$GITHUB_TOKEN" | gh auth login --with-token
  gh auth setup-git
  echo "  GitHub authentication complete (via GITHUB_TOKEN)."
else
  echo "  ⚠️  Not authenticated. Run 'gh auth login' to authenticate manually."
fi

echo "=== Setup complete ==="
