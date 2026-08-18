# serena MCP の再導入ガイド(目安と手順)

> **このファイルはプロジェクト開始後も残す**(プロジェクトが育った段階で参照するため、削除可能な `docs/template-dev/` ではなく `.claude/docs/` に置いている)。
> serena はテンプレートから一度削除済み(トークン最適化)。このドキュメントは「いつ・どう戻すか」の判断材料と手順を記録する。

## 背景(なぜ削除したか)

MCP サーバーのツールスキーマ(serena は 10〜20 個超)は、**使う・使わないに関わらず毎セッション無条件でコンテキストにロードされる**(固定費: 数千トークン/セッション)。テンプレート初期の小さいコードベースでは Grep / Explore subagent 委譲で十分であり、リターンがほぼゼロのまま固定費だけ払う状態だったため削除した。

## 損益分岐の構造

- **コスト**: ツールスキーマ+サーバー指示の毎セッション固定費
- **リターン**: 検索 1 回ごとの節約(LSP のシンボル参照解決により、Grep のノイズヒットや大きなファイルの全読みが減る)+ 大規模リファクタ時の参照漏れ防止(品質面)
- **判断**: 「セッション中の探索回数 × 1 回あたりの節約」が固定費を超えたら有効

このテンプレートは広範囲の探索を Explore subagent(安価なモデル)に委譲する設計のため、司令塔のコンテキスト節約は既に達成済み。serena の損益分岐点は一般的なプロジェクトより**高め**になることに注意。

## 再導入の目安(兆候ベースで判断する)

規模の数値より、次の**兆候**が出たら再導入を検討する:

1. Grep の結果にノイズが目立ち、絞り込みのための再検索が頻繁に発生するようになった(一般的な識別子名で数十件ヒットする等)
2. 「全呼び出し元の洗い出し」「シンボルのリネーム影響調査」系のタスクが週次で発生するようになった
3. 1 ファイルが数百行を超え、編集のための全読みが重くなった

規模の参考値(機械的な検知にも使える近似指標):

| 規模                                   | 判断                                                     |
| -------------------------------------- | -------------------------------------------------------- |
| 〜1 万行・数十ファイル                 | 不利(Grep がノイズなしで即答する規模)                    |
| 1〜5 万行                              | タスク次第(シンボル参照系の作業が頻繁なら有効になり始め) |
| 5 万行超・数百ファイル・モノレポ       | 明確に有利(精度・トークン両面で LSP が勝つ)              |

## 再導入手順

### 1. `.mcp.json` に serena エントリを追記する(context7 等の既存エントリと並記)

```json
"serena": {
  "command": "${HOME}/.local/bin/serena",
  "args": ["start-mcp-server", "--context", "ide-assistant", "--project", "."]
}
```

### 2. `post_create.sh` にインストール処理を戻す

GitHub 認証ステップの前に挿入する(削除時のコミットの git 履歴からも復元可):

```bash
# Install Serena tooling (registered as MCP server via .mcp.json)
echo "Installing Serena tooling..."
UV_BIN="$(command -v uv || true)"
if [ -z "$UV_BIN" ] && [ -x "$HOME/.local/bin/uv" ]; then
  UV_BIN="$HOME/.local/bin/uv"
fi
if [ -z "$UV_BIN" ]; then
  curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
  UV_BIN="$HOME/.local/bin/uv"
fi
export PATH="$HOME/.local/bin:$PATH"

# サードパーティ MCP サーバー(プロジェクト全体への読み書きを持つ)のため、
# プレリリース版は使わず安定版の最新のみを導入する(サプライチェーン面の配慮)
if ! command -v serena >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/serena" ]; then
  "$UV_BIN" tool install -p 3.13 serena-agent@latest
fi

# Persist ~/.local/bin on PATH for interactive shells (serena / uv)
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$rc" ] && ! grep -q '\.local/bin' "$rc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
  fi
done
```

### 3. CLAUDE.md に使い分けを明記する(必須)

指示なしで置くと司令塔が使いどころを判断できず固定費だけ払う。「実装前の確認」節の検索ルールに追記する:

```
- シンボルの参照解決・定義ジャンプ・リネーム影響調査は serena(mcp__serena__*)、
  文字列・設定値の検索は Grep、広範囲の概念的な探索は Explore subagent
```

### 4. 制約の再周知

- Claude Code on the web(リモート実行)には serena バイナリが無いため、起動失敗のログが出る(無視してよい)。README の補足節に一文戻す
- `.mcp.json` はセッション起動時に読まれるため、復元後は Claude Code の再起動が必要

## 自動再導入について(検知は自動・判断は人間を推奨)

**完全自動は推奨しない**。理由:

- 「処理の中の損益分岐」(Grep のノイズ率・再検索頻度)はフックから直接観測できず、規模の近似指標でしか代替できない
- サードパーティバイナリの無人インストールはサプライチェーン面で避けるべき(post_create の方針と整合)
- `.mcp.json` を復元してもセッション再起動が必要で、プロジェクトスコープの MCP サーバーは初回に承認プロンプトが出るため、完全無人にはならない

推奨は**半自動(検知だけ自動化)**: しきい値超過時に 1 行だけコンテキストに注入して司令塔からユーザーに提案させる。

この検知は **`.claude/hooks/session-start.sh` に導入済み**(startup 時のみ・`git ls-files` ベースで軽量。`.mcp.json` に serena が登録済みの間は何もしない)。

しきい値(TypeScript 3 万行 / 300 ファイル)は上の参考値表に基づく初期値であり、プロジェクトの言語構成に合わせて session-start.sh 側を調整する(TS 以外が主体のプロジェクトでは対象拡張子も変更する)。
