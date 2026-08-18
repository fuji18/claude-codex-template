#!/bin/bash
set -e

echo "=== Post-create setup ==="

# Install Playwright deps (only when the project actually uses Playwright)
echo "[1/3] Installing Playwright dependencies..."
if grep -qE '"(@playwright/test|playwright)"' package.json 2>/dev/null; then
  npx --yes playwright install-deps chromium
else
  echo "  Playwright not found in package.json. Skipping (E2E 導入時に再実行される)."
fi

# Install Claude Code
echo "[2/3] Installing Claude Code..."
npm install -g @anthropic-ai/claude-code

# GitHub authentication
# Codespaces が注入する GITHUB_TOKEN を尊重し、ローカル devcontainer では
# LOCAL_GH_TOKEN(ホストの GH_TOKEN)をフォールバックとして使う
echo "[3/3] Setting up GitHub authentication..."
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
