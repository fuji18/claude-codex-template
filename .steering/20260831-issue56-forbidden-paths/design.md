# 設計: 委託禁止領域の適用漏れを塞ぐ(Issue #56)

<!-- status: ready -->

実装者は設計判断をしない。本ファイルに書かれた内容を、指定のファイルに指定の形で反映するだけでよい。

---

## §0. 設計判断(確定済み。実装者は判断しない)

### 判断1: `.claude/rules/` は**ディレクトリ単位**で入れる(`lead/` `mode/` の個別列挙にしない)

Issue のスコープには「`spec-driven.md` を含めるかは設計判断」とあるが、**含める**。理由は
`.claude/scripts/` を丸ごと入れたとき(#40)と同じで、個別列挙はファイルが増えるたびに漏れる。
`spec-driven.md` は `CLAUDE.md` 経由で司令塔と**全サブエージェント**に毎回ロードされるので、
注入元としての性質は `lead/*.md` と同じ。`lead/` と `mode/` だけを列挙すると、まさにその
一番広く読まれるファイルが漏れる。

委託の余地は狭まらない。`rules/` への追記はもともと司令塔の仕事と定めてある
(`context-management.md`「ルールを追記するときの置き場所」)。

### 判断2: 追加する 5 項目(これで確定。増減しない)

`.claude/branch-policy.json` / `.claude/rules/` / `CLAUDE.md` / `.mcp.json` / `.codex/`

### 判断3: 原則の言い換えは「3 系統」にする

現行の「対象は**実行される実体**(scripts / hooks / settings.json)に限る」は、
`rules/` と `branch-policy.json` を入れた時点で成り立たない。次の 3 系統に書き換える:

1. **実行される実体** — `scripts/` / `hooks/` / `settings.json` / `.husky/*` / `.github/workflows/`
2. **コンテキストへ注入される実体** — `rules/` / `CLAUDE.md` / `AGENTS.md` / `.mcp.json`
3. **全層が読む判定データ** — `branch-policy.json`

除外は据え置き: `.claude/` 配下の `skills/` / `commands/` / `agents/` / `docs/`。

### 判断4: 不在パスの扱いは**現状のままでよい**(コード変更なし)

受け入れ条件3(`.mcp.json` が未追跡・不在でも壊れない)は既存実装で満たされている。
司令塔が実測で確認済み:

- `forbidden_files()` の catch-all は `*) [ -e "$_p" ] && printf ...` なので、不在パスは列挙されない
- 入口検査5-5b の pathspec は `GIT_LITERAL_PATHSPECS=1 git diff HEAD --name-only -- <不在パス>` と
  `git ls-files --others --exclude-standard -- <不在パス>` の形で、`--error-unmatch` を付けていないため
  不在パスでも rc=0(実測済み)
- ディレクトリ指定 `.codex/` も `*/) [ -d ... ] && find ...` で不在なら何も出さない

したがって**コードは変更せず、§4 の検証で回帰確認だけを行う**。

---

## §1. `.claude/scripts/delegate-codex.sh`

### 1-1. 配列(現在 241〜252 行)

現行:

```bash
FORBIDDEN_PATHS=(
  ".claude/scripts/"
  ".claude/hooks/"
  ".claude/settings.json"
  ".husky/pre-commit"
  ".husky/prepare-commit-msg"
  ".claude/codex-denylist.txt"
  "AGENTS.md"
  ".github/workflows/"
  ".harness/mode"
  ".harness/codex-runs/"
)
```

これを**この 15 行にそっくり置き換える**(並び順もこのとおり。既存 10 項目は 1 つも消さない):

```bash
FORBIDDEN_PATHS=(
  ".claude/scripts/"
  ".claude/hooks/"
  ".claude/settings.json"
  ".claude/branch-policy.json"
  ".claude/rules/"
  ".husky/pre-commit"
  ".husky/prepare-commit-msg"
  ".claude/codex-denylist.txt"
  "AGENTS.md"
  "CLAUDE.md"
  ".mcp.json"
  ".github/workflows/"
  ".codex/"
  ".harness/mode"
  ".harness/codex-runs/"
)
```

### 1-2. 配列直上のコメント(2 箇所)

**(a) 「後でサンドボックスの外で実行される」の箇条書き**(現在 219〜221 行の 3 行)。
現行の 3 行:

```
#   - .husky/* / .claude/scripts/* / .claude/hooks/* はホストの git・Claude セッションが実行する
#   - .claude/settings.json は PreToolUse hook の定義そのもの(どのコマンドを止めるかの宣言)
#   - .github/workflows/* は非 fork PR で CLAUDE_CODE_OAUTH_TOKEN に触れる定義そのもの
```

の**直後に**、次の 10 行を挿入する(既存 3 行は変更しない):

```
#   - .claude/branch-policy.json は保護ブランチ検査の全 3 層(PreToolUse hook / .husky/* /
#     CI の branch-policy ジョブ)が読む**判定データ**。判定ロジックは一本化して守ってあるが、
#     データが書き換われば全層が「正常に動作したうえで素通し」する。層の数では防げない
#     (Issue #56 / S1)
#   - .claude/rules/* は SessionStart hook と CLAUDE.md 経由で、司令塔と全サブエージェントの
#     コンテキストへ本文がそのまま注入される。1 段落足すだけで恒久的な指示注入の足場になる
#   - CLAUDE.md も同じ性質(全エージェントに毎回ロードされる)
#   - .mcp.json は MCP サーバ定義 = セッション開始時のローカルプロセス起動指示
#   - .codex/ は Codex 側の設定(network_access 等)とモード C の手順書。「Codex 自身は
#     .codex/ に書けない」は codex-cli v0.149.0 の実測に依存した前提で、CLI 更新で崩れうる
```

**(b) 末尾の原則の段落**(現在 238〜240 行)。現行:

```
# .claude/ 全体をディレクトリごと禁止にはしない。skills/ commands/ agents/ rules/ の
# 定型追記まで止めると委託の余地が過剰に狭まるため、対象は**実行される実体**
# (scripts / hooks / settings.json)に限る。
```

を、次の 9 行に置き換える:

```
# .claude/ 全体をディレクトリごと禁止にはしない。skills/ commands/ agents/ docs/ の
# 定型追記まで止めると委託の余地が過剰に狭まる。対象は次の 3 系統に限る(Issue #56):
#   1. 実行される実体      … scripts/ hooks/ settings.json .husky/* .github/workflows/
#   2. 注入される実体      … rules/ CLAUDE.md AGENTS.md .mcp.json
#   3. 全層が読む判定データ … branch-policy.json
# rules/ をディレクトリ単位にしたのは scripts/ と同じ理由。lead/ と mode/ だけを個別列挙すると
# CLAUDE.md 経由で全サブエージェントに載る spec-driven.md が漏れ、ファイルが増えるたびに
# 同じ漏れを繰り返す。rules/ への正当な追記はもともと司令塔の仕事(context-management.md
# 「ルールを追記するときの置き場所」)なので、委託の余地はほぼ狭まらない。
```

`# 末尾が / のものはディレクトリ配下すべてが対象。` の 1 行はそのまま残す。

---

## §2. `AGENTS.md` §4(マーカー内。148〜156 行)

**マーカー行(`<!-- kickoff:delegation-forbidden-paths -->` / 閉じタグ)は動かさない。**
マーカー内の箇条書きに 5 行を挿入する。既存 7 行の文面は変更しない。

挿入位置と文面:

1. `- \`.claude/hooks/\` / \`.claude/settings.json\` — …` の**次の行**に 2 行:

```
- `.claude/branch-policy.json` — 保護ブランチ判定の単一ソースです。ここを書き換えると、判定の全層が正常に動いたまま保護を素通しします
- `.claude/rules/` — 司令塔とすべてのサブエージェントのコンテキストへ本文がそのまま注入される場所です。1 段落の追記が恒久的な指示になります
```

2. `- \`AGENTS.md\` — このファイル自身。…` の**次の行**に 2 行:

```
- `CLAUDE.md` — プロジェクトメモリ。全エージェントに毎回読み込まれます
- `.mcp.json` — MCP サーバ定義。セッション開始時にローカルでプロセスを起動する指示です
```

3. `- \`.github/workflows/\` — CI 定義そのもの。…` の**次の行**に 1 行:

```
- `.codex/` — あなた自身の設定(ネットワーク許可など)とモード C の手順書です
```

> **バッククォートの制約(重要)。** `delegate-codex.sh` はマーカー内の**バッククォート囲みの文字列をすべて**
> 禁止領域として抽出する。上の 5 行では、禁止領域にしたいパスだけをバッククォートで囲んである。
> **説明文の中に他の実在パスをバッククォートで書き足さないこと**(意図しないパスが禁止領域に化ける)。

---

## §3. `CLAUDE.md`「Codex への委託禁止領域(パス)」節(27〜39 行)

### 3-1. 箇条書きへの追加(配列と同じ並び)

1. `- \`.claude/hooks/\` / \`.claude/settings.json\` — …` の次に 2 行:

```
- `.claude/branch-policy.json` — 保護ブランチ検査の全 3 層(PreToolUse hook / `.husky/*` / CI の `branch-policy` ジョブ)が読む**判定データ**。判定ロジックは `check-protected-branch.sh` に一本化して守ってあるが、データが書き換われば全層が「正常に動作したうえで素通し」する。`check-guard-integrity.sh` の検査1 も `protectedBranches` が空かどうかしか見ないため、`["develop"]` への差し替えは緑のまま通る(#56 / S1)
- `.claude/rules/` — SessionStart hook(`lead/` / `mode/`)と `CLAUDE.md` 経由(`spec-driven.md`)で、司令塔と全サブエージェントのコンテキストへ**本文がそのまま注入される**。1 段落の追記が恒久的な指示注入の足場になる。`lead/` と `mode/` だけの個別列挙にしないのは、最も広く読まれる `spec-driven.md` が漏れるため
```

2. `- \`AGENTS.md\` — 委託先の憲法。…` の次に 2 行:

```
- `CLAUDE.md` — プロジェクトメモリ。司令塔と全サブエージェントに毎回ロードされるため、`rules/` と同じ注入経路になる
- `.mcp.json` — MCP サーバ定義 = セッション開始時のローカルプロセス起動指示(新規サーバは承認プロンプトが挟まるぶん緩和されるが、経路としては同種)
```

3. `- \`.github/workflows/\` — …` の次に 1 行:

```
- `.codex/` — Codex 側の設定(`network_access` 等)とモード C の手順書(`degraded-mode-ticket`)。「Codex 自身は `.codex/` に書けない」は codex-cli v0.149.0 の実測に依存した前提で、CLI 更新で崩れうる。多層防御として入れる(#56 / S6)
```

### 3-2. 原則の 1 行(現在 39 行)を置き換える

現行:

```
`.claude/` 配下でも `skills/` / `commands/` / `agents/` / `rules/` / `docs/` は禁止領域に含めない。対象は**実行される実体**(scripts / hooks / settings.json)に限る。
```

置き換え後(3 行):

```
`.claude/` 配下でも `skills/` / `commands/` / `agents/` / `docs/` は禁止領域に含めない。対象は次の 3 系統に限る(#56):

1. **実行される実体** — `.claude/scripts/` / `.claude/hooks/` / `.claude/settings.json` / `.husky/*` / `.github/workflows/`
2. **コンテキストへ注入される実体** — `.claude/rules/` / `CLAUDE.md` / `AGENTS.md` / `.mcp.json`
3. **全層が読む判定データ** — `.claude/branch-policy.json`
```

> `rules/` を除外リストから**外す**のを忘れないこと(3-1 で禁止領域に入れたため、
> 同じ節の中で矛盾する)。

---

## §4. 検証(`verification.md` に記録する)

`.steering/20260831-issue56-forbidden-paths/verification.md` を新規作成し、
下の 7 シナリオの実測結果(exit code / run record の `status` / `error`)を表で残す。
手順は #40 の検証(`.steering/20260829-issue40-forbidden-paths-expand/design.md` §4)を踏襲する。

### 4-0. 準備

```bash
bash -n .claude/scripts/delegate-codex.sh   # 構文チェック(必須。先に通す)
bash .claude/scripts/delegate-codex.sh --print-forbidden   # 15 項目が出ること
```

残置 record の確認(あると入口検査5-5 で止まる):

```bash
grep -l '"status": *"running"' .harness/codex-runs/*.json 2>/dev/null || echo "残置なし"
```

残置があれば `bash .claude/scripts/codex-run.sh set-status <id> failed` で実態に合わせてから進む。

スタブ Codex を作る(**実 Codex は呼ばない**):

```bash
STUB="$(mktemp -d)"
cat > "$STUB/codex" <<'STUB_EOF'
#!/bin/bash
[ "${1:-}" = "login" ] && exit 0
LASTPATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --output-last-message) LASTPATH="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "${FAKE_CODEX_TOUCH:-}" ] && printf '\n# tampered by fake codex\n' >> "$FAKE_CODEX_TOUCH"
[ -n "${FAKE_CODEX_WORK:-}" ] && printf 'fake work\n' >> "$FAKE_CODEX_WORK"
[ -n "$LASTPATH" ] && printf '完了: tasklist 1/1 / 変更 1 ファイル / lint・型・関連テスト pass\n' > "$LASTPATH"
exit 0
STUB_EOF
chmod +x "$STUB/codex"
export PATH="$STUB:$PATH"
```

使い捨てステアリング(`.steering/` 配下でないと入口検査5-1 に落ちる):

```bash
S=".steering/20260831-issue56-verify-scratch"
mkdir -p "$S"
printf '<!-- status: ready -->\n# scratch\n' > "$S/design.md"
printf -- '- [ ] scratch task\n' > "$S/tasklist.md"
```

- `FAKE_CODEX_TOUCH` に禁止領域のパスを渡すと、そのファイルへ 1 行追記される(= 改ざん)
- `FAKE_CODEX_WORK` には**シナリオごとに別名**の scratch ファイルを渡し、
  **作成直後に `git add` する**(未追跡ディレクトリの畳み込みで成果実在確認が空振りするため。
  #20 の verification.md §3 の実測)

### 4-1. シナリオ表(7 本)

| # | `FAKE_CODEX_TOUCH` | 期待 exit | 期待 status | 期待 error |
| --- | --- | --- | --- | --- |
| S1 | `.claude/branch-policy.json` | 2 | `failed` | `委託禁止領域が変更されました: .claude/branch-policy.json` |
| S2 | `.claude/rules/lead/model-strategy.md` | 2 | `failed` | 同上(パス差し替え) |
| S3 | `.claude/rules/spec-driven.md` | 2 | `failed` | 同上(判断1 の裏取り。`lead/` 個別列挙では漏れるパス) |
| S4 | `CLAUDE.md` | 2 | `failed` | 同上 |
| S5 | `.mcp.json` | 2 | `failed` | 同上 |
| S6 | `.codex/config.toml` | 2 | `failed` | 同上 |
| S7 | (なし。`FAKE_CODEX_WORK` のみ) | 0 | `failed` でないこと | なし |

実行の形(S1 の例):

```bash
cp .claude/branch-policy.json /tmp/bk-branch-policy.json   # 改ざんの巻き戻し用バックアップ
: > "$S/scratch1.txt"; git add "$S/scratch1.txt"
FAKE_CODEX_TOUCH=".claude/branch-policy.json" \
FAKE_CODEX_WORK="$S/scratch1.txt" \
  bash .claude/scripts/delegate-codex.sh impl "$S" ; echo "exit=$?"
cp /tmp/bk-branch-policy.json .claude/branch-policy.json   # 復元
```

**巻き戻しは `git checkout --` ではなく `cp` のバックアップ/リストアで行う**
(このブランチには `CLAUDE.md` / `AGENTS.md` / `delegate-codex.sh` に未コミットの変更が
乗っているため、`git checkout` すると本チケットの実装ごと消える。#20 の実測)。

`status` / `error` は最新の run record から読む:

```bash
ls -t .harness/codex-runs/*.json | head -1 | xargs -I{} sh -c 'jq "{status,error}" {}'
```

### 4-2. 受け入れ条件3(不在パスで壊れないこと)の実測

S7 と同じ通常委託を、`.mcp.json` を一時退避した状態でもう 1 本流す(**S8** とする):

```bash
mv .mcp.json /tmp/bk-mcp.json
bash .claude/scripts/delegate-codex.sh --print-forbidden >/dev/null; echo "print rc=$?"
: > "$S/scratch8.txt"; git add "$S/scratch8.txt"
FAKE_CODEX_WORK="$S/scratch8.txt" bash .claude/scripts/delegate-codex.sh impl "$S"; echo "exit=$?"
mv /tmp/bk-mcp.json .mcp.json
```

期待: `--print-forbidden` が rc=0、委託が exit 0(`failed` でない)。
**`.mcp.json` の復元を忘れないこと。**

### 4-3. コスト計測

S7(通常委託)の全体所要時間を `time` で 1 回だけ測り、数値を `verification.md` に残す。
閾値判定はしない(バッチ化は Issue #65 の担当)。

### 4-4. 後始末(必須)

```bash
git reset -- "$S" 2>/dev/null
rm -rf "$S" /tmp/bk-* "$STUB"
git status --porcelain    # 使い捨てステアリングと scratch が残っていないこと
ls -l .mcp.json .claude/branch-policy.json   # 退避したファイルが戻っていること
git diff --stat            # 変更が §1〜§3 と §5 の 4 ファイルだけであること
```

検証で作られた run record(`.harness/codex-runs/`)は**消さない**(実測の証跡)。

---

## §5. `docs/template-dev/CHANGELOG.md`

先頭の `---` の直後(`## 2026-08-30` の**上**)に `## 2026-08-31` の見出しを新設して追記する。
**過去の日付見出しには追記しない。**

```markdown
## 2026-08-31

**委託禁止領域を「実行される実体」から 3 系統に広げ、適用漏れ 3 系統を塞いだ(Issue #56)。** 保護ブランチ検査は判定ロジックを 1 本化して守ってありましたが、**その判定が読むデータ**(`.claude/branch-policy.json`)は禁止領域に無く、委託先が `protectedBranches` を差し替えても出口検査に掛かりませんでした。全層が正常に動作したうえで素通しする形になるため、層を増やしても防げない経路です。同じ理屈で、司令塔のコンテキストへ本文が注入される `.claude/rules/` と `CLAUDE.md` も保護されていませんでした。

- **[auto]** `FORBIDDEN_PATHS` に 5 項目を追加: `.claude/branch-policy.json` / `.claude/rules/` / `CLAUDE.md` / `.mcp.json` / `.codex/`。`AGENTS.md` §4 のマーカー内と `CLAUDE.md` の説明も同時に更新済みです
- **[auto]** 原則を 3 系統に整理しました。**実行される実体**(scripts / hooks / settings.json / `.husky/*` / workflows)、**コンテキストへ注入される実体**(rules / CLAUDE.md / AGENTS.md / .mcp.json)、**全層が読む判定データ**(branch-policy.json)。`skills/` / `commands/` / `agents/` / `docs/` の除外は据え置きです
- **[auto]** `.claude/rules/` はディレクトリ単位です。`lead/` と `mode/` だけを個別列挙すると、`CLAUDE.md` 経由で全サブエージェントに載る `spec-driven.md` が漏れます
- **[manual]** ⚠️ **委託先が `CLAUDE.md` / `.claude/rules/` を編集する運用をしていた場合、その委託は `failed` / `exit 2` になります。** ルールへの追記はもともと司令塔の仕事(`context-management.md`)なので実害は無いはずですが、**取り込む側の作業**: `/kickoff` 以外で Codex に `CLAUDE.md` を書かせる手順を作っていないか確認してください
```

---

## §6. 品質チェック

```bash
bash -n .claude/scripts/delegate-codex.sh
npx eslint .
npx tsc --noEmit
npx prettier --check .claude/scripts/delegate-codex.sh AGENTS.md CLAUDE.md docs/template-dev/CHANGELOG.md
```

`.sh` / `.md` のみの変更なので `vitest` 対象コードへの影響は無い。`prettier --check` が
落ちた場合は**変更したファイルだけ** `npx prettier --write <file>` を回す(全体フォーマットは禁止)。

---

## §7. 変更対象ファイル(4 つ。これ以外を触らない)

| ファイル | 変更 |
| --- | --- |
| `.claude/scripts/delegate-codex.sh` | §1(配列 + コメント 2 箇所) |
| `AGENTS.md` | §2(マーカー内に 5 行挿入) |
| `CLAUDE.md` | §3(5 行挿入 + 原則 1 行の置き換え) |
| `docs/template-dev/CHANGELOG.md` | §5(`## 2026-08-31` を新設) |

加えて `.steering/20260831-issue56-forbidden-paths/verification.md` を新規作成する(§4)。
