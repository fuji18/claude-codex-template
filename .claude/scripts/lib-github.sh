# shellcheck shell=bash
# GitHub REST を叩く autopilot 系スクリプトの共有ライブラリ(source 専用。実行ビットを付けない)。
#
# REST だけを使う理由: Claude Code on the web では GraphQL が 403 になり、
# gh issue list / gh pr list(GraphQL 経由)が使えないため。

# owner/repo を標準出力に返す。AUTOPILOT_REPO があればそれを使う。
# https://github.com/o/r(.git) / git@github.com:o/r.git / プロキシ経由の .../o/r のいずれも末尾 2 要素を取る
gh_resolve_repo() {
  local repo="${AUTOPILOT_REPO:-}" url
  if [ -z "$repo" ]; then
    url="$(git remote get-url origin 2>/dev/null)" || return 1
    repo="$(printf '%s' "$url" | sed -E 's#\.git$##; s#^.*[:/]([^/:]+/[^/]+)$#\1#')"
  fi
  case "$repo" in */*) printf '%s\n' "$repo" ;; *) return 1 ;; esac
}
