<!-- status: ready -->

# 設計: 委託禁止領域に CI/hook の判定実体を含める(Issue #40)

実装者へ: このファイルに書かれた内容だけで完結する。設計判断は残していない。
迷ったら**停止して報告**すること(推測で進めない)。

---

## §0. 変更対象ファイル(4 つ)

| ファイル | 変更内容 |
| --- | --- |
| `.claude/scripts/delegate-codex.sh` | `FORBIDDEN_PATHS` 配列 + 直上のコメント |
| `AGENTS.md` | §4「委託禁止領域(パス)」のマーカー内 |
| `CLAUDE.md` | 「Codex への委託禁止領域(パス)」節の箇条書き |
| `docs/template-dev/CHANGELOG.md` | 先頭に `## 2026-08-29` 見出しを新設して追記 |

**これ以外のファイルを変更しない。**

---

## §1. `.claude/scripts/delegate-codex.sh`

### 1-1. 配列(現在 692〜702 行)

変更前:

```bash
FORBIDDEN_PATHS=(
  ".claude/scripts/delegate-codex.sh"
  ".claude/scripts/check-protected-branch.sh"
  ".husky/pre-commit"
  ".husky/prepare-commit-msg"
  ".claude/codex-denylist.txt"
  "AGENTS.md"
  ".github/workflows/"
  ".harness/mode"
  ".harness/codex-runs/"
)
```

変更後(**この 10 行に完全に置き換える。順序もこのとおり**):

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

注記(実装時に確認するだけ。コードは変えない):

- `.claude/scripts/` は末尾 `/` = ディレクトリ配下すべて。`forbidden_files()` の
  `*/) [ -d "${_p%/}" ] && find ... -type f` の分岐が受ける。既存の
  `delegate-codex.sh` / `check-protected-branch.sh` はこれに包含されるため個別行は消す
- `.claude/settings.json` は**完全一致**で列挙する。`.claude/settings.local.json` は
  gitignore 対象で対象外のまま(意図どおり)
- `.claude/skills/` / `.claude/commands/` / `.claude/agents/` / `.claude/rules/` /
  `.claude/docs/` は**足さない**(スコープ外)

### 1-2. 配列直上のコメント

680 行の

```
#   - .husky/* / .claude/scripts/* はホストの git・Claude セッションが実行する
```

を、次の 2 行に置き換える:

```
#   - .husky/* / .claude/scripts/* / .claude/hooks/* はホストの git・Claude セッションが実行する
#   - .claude/settings.json は PreToolUse hook の定義そのもの(どのコマンドを止めるかの宣言)
```

さらに、`# 末尾が / のものはディレクトリ配下すべてが対象。` の**直前**に次の段落を挿入する
(その行はそのまま残す):

```
# .claude/scripts/ と .claude/hooks/ を個別ファイルではなくディレクトリで指定しているのは、
# 「.github/workflows/ を守るなら、workflows が bash で呼ぶ判定の実体も同等に守る」線を
# 一貫させるため(Issue #40)。個別列挙にすると、判定スクリプトが 1 本増えるたびに同じ
# 漏れを繰り返す。実際 #37 で足した check-record-hygiene.sh は、冒頭に exit 0 を 1 行
# 書くだけで全 PR の記録漏れ検査を無効化できる状態のまま守られていなかった。
# .claude/ 全体をディレクトリごと禁止にはしない。skills/ commands/ agents/ rules/ の
# 定型追記まで止めると委託の余地が過剰に狭まるため、対象は**実行される実体**
# (scripts / hooks / settings.json)に限る。
```

---

## §2. `AGENTS.md` §4

`<!-- kickoff:delegation-forbidden-paths -->` と `<!-- /kickoff:delegation-forbidden-paths -->`
の**間だけ**を、次の内容に完全に置き換える。**マーカー行そのものは消さない・動かさない。**

```markdown
- `.claude/scripts/` — 委託の入口(`delegate-codex.sh`)・保護ブランチ判定・CI が呼ぶ判定スクリプトの実体が置かれる場所です。実行中のあなた自身の起動元も含みます(プロセス自体は自己コピーで保護済み)。ここが 1 行書き換わるだけで、CI の検査やガードレールの自壊検知が静かに無効化されます
- `.claude/hooks/` / `.claude/settings.json` — Claude 側のフック定義とその実体です。司令塔のコンテキストへ注入される内容の出所でもあります
- `.husky/pre-commit` / `.husky/prepare-commit-msg` — ベンダー非依存のガードレール本体
- `.claude/codex-denylist.txt` — 委託先が自分の送信禁止リストを書き換えることはできません
- `AGENTS.md` — このファイル自身。冒頭の `<!-- verify-probe: ... -->` は次回の委託時にホスト側で実行されるため、あなたが書き換えるとサンドボックスの外へ影響が出ます
- `.github/workflows/` — CI 定義そのもの。ここを書き換えると認証済みトークンに触れられます
- `.harness/mode` / `.harness/codex-runs/` — ハーネスモードと委託の実行記録。自分の結果を承認済みにすることはできません
```

**重要**: マーカー内のバックティック囲み文字列は `delegate-codex.sh` が委託開始時に抽出して
配列とマージする。上のとおり書けば `.claude/scripts/` `.claude/hooks/`
`.claude/settings.json` が抽出され、配列側と重複するが `forbidden_snapshot()` が
`sort -u` で畳むため問題ない。`delegate-codex.sh` のような**配下の個別ファイル名**を
バックティックで書くと、それも抽出されて重複するだけで害はない(上の文面はその形になっている)。

マーカー下の説明文(`> 上の項目はテンプレート由来の…`)は**変更しない**。

---

## §3. `CLAUDE.md`

「### Codex への委託禁止領域(パス)」節の箇条書き(`.claude/scripts/delegate-codex.sh` から
`.harness/mode` までの 7 項目)を、次に置き換える。**節タイトルと前後の段落は変更しない。**

```markdown
- `.claude/scripts/` — 委託の唯一の入口(`delegate-codex.sh`)、保護ブランチ判定、CI が `bash` で呼ぶ判定の実体(`check-record-hygiene.sh` / `check-guard-integrity.sh`)、検収状態を書き換える `codex-run.sh` がすべてここにある。`.github/workflows/` を守っても、そのワークフローが実行する実体が書き換え可能なら防御は成立しない。個別列挙はスクリプトが増えるたびに漏れるのでディレクトリ単位で禁止する(実行中プロセスの保護は #15 の自己コピー exec で別途実装済み。`docs/template-dev/codex-delegation-plan.md` §9)
- `.claude/hooks/` / `.claude/settings.json` — PreToolUse hook の定義そのものと、司令塔コンテキストへの注入元(プロンプトインジェクションの経路になり得る)
- `.husky/pre-commit` / `.husky/prepare-commit-msg` — ベンダー中立ガードレールの本体
- `.claude/codex-denylist.txt` — 委託先が自分の送信禁止リストを編集できてはならない
- `AGENTS.md` — 委託先の憲法。入口検査3 の `<!-- verify-probe: ... -->` は次回委託時にホスト上の `bash -c` へそのまま渡されるため、書き換えを許すとサンドボックス外でのコマンド実行経路になる
- `.github/workflows/` — 非 fork PR で `CLAUDE_CODE_OAUTH_TOKEN` にアクセスできるワークフロー定義そのもの
- `.harness/mode` / `.harness/codex-runs/` — ハーネスモードと run record。委託先が自分の結果を `accepted` に書き換えたりモードを詐称したりできてはならない
```

さらに、この箇条書きの**直後**(`**機密の送信禁止…` の段落の直前)に次の 1 行を挿入する:

```markdown
`.claude/` 配下でも `skills/` / `commands/` / `agents/` / `rules/` / `docs/` は禁止領域に含めない。対象は**実行される実体**(scripts / hooks / settings.json)に限る。
```

---

## §4. 検証(`verification.md` に記録する)

`.steering/20260829-issue40-forbidden-paths-expand/verification.md` を新規作成し、
下の 4 シナリオの実測結果(exit code / run record の `status` / `error`)を表で残す。
手順は Issue #20 の検証(`.steering/20260825-issue20-codex-exit-check/verification.md`)を踏襲する。

### 4-0. 準備

```bash
bash -n .claude/scripts/delegate-codex.sh   # 構文チェック(必須。先に通す)
```

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
S=".steering/20260829-issue40-verify-scratch"
mkdir -p "$S"
printf '<!-- status: ready -->\n# scratch\n' > "$S/design.md"
printf -- '- [ ] scratch task\n' > "$S/tasklist.md"
```

- `FAKE_CODEX_TOUCH` に禁止領域のパスを渡すと、そのファイルへ 1 行追記される(= 改ざん)
- `FAKE_CODEX_WORK` には**シナリオごとに別名**の scratch ファイルを渡し、
  **作成直後に `git add` する**(未追跡ディレクトリの畳み込みで成果実在確認が空振りするため。
  #20 の verification.md §3 の実測)

### 4-1. シナリオ表(4 本)

| # | `FAKE_CODEX_TOUCH` | 期待 exit | 期待 status | 期待 error |
| --- | --- | --- | --- | --- |
| S1 | `.claude/scripts/check-record-hygiene.sh` | 2 | `failed` | `委託禁止領域が変更されました: .claude/scripts/check-record-hygiene.sh` |
| S2 | `.claude/hooks/session-start.sh` | 2 | `failed` | 同上(パス差し替え) |
| S3 | `.claude/settings.json` | 2 | `failed` | 同上(パス差し替え) |
| S4 | (なし。`FAKE_CODEX_WORK` のみ) | 0 | `completed` 系(`failed` でないこと) | なし |

実行の形(S1 の例):

```bash
cp .claude/scripts/check-record-hygiene.sh /tmp/bk-crh.sh    # 改ざんの巻き戻し用バックアップ
: > "$S/scratch1.txt"; git add "$S/scratch1.txt"
FAKE_CODEX_TOUCH=".claude/scripts/check-record-hygiene.sh" \
FAKE_CODEX_WORK="$S/scratch1.txt" \
  bash .claude/scripts/delegate-codex.sh impl "$S" ; echo "exit=$?"
cp /tmp/bk-crh.sh .claude/scripts/check-record-hygiene.sh    # 復元
```

**巻き戻しは `git checkout --` ではなく `cp` のバックアップ/リストアで行う**
(このブランチには同じファイル群に未コミットの変更が乗るため、`git checkout` すると
設計変更ごと消える。#20 の実測)。

`status` / `error` は最新の run record から読む:

```bash
ls -t .harness/codex-runs/*.json | head -1 | xargs -I{} sh -c 'jq "{status,error}" {}'
```

### 4-2. コスト計測(受け入れ条件)

`.claude/scripts/`(11 ファイル)追加後のスナップショット 1 回あたりの所要時間を測る:

```bash
time (for i in 1 2 3 4 5; do
  bash -c 'source /dev/stdin <<< "$(sed -n "/^FORBIDDEN_PATHS=(/,/^)/p" .claude/scripts/delegate-codex.sh)"' >/dev/null
done)
```

上が扱いづらい場合は、**委託 1 本の全体所要時間(S4 の `time`)を before/after で 1 回ずつ測る**
形でよい。要件は「一度測って `verification.md` に数値を残す」ことだけで、閾値判定はしない。

### 4-3. 後始末(必須)

```bash
rm -rf "$S" /tmp/bk-*.sh "$STUB"
git status --porcelain    # 使い捨てステアリングと scratch が残っていないこと
```

検証で作られた run record(`.harness/codex-runs/`)は**消さない**(実測の証跡)。
ただし件数が閾値を超えた警告が出た場合は `bash .claude/scripts/codex-run.sh prune --dry-run`
の結果を `verification.md` に記録するだけにとどめ、削除はしない。

---

## §5. `docs/template-dev/CHANGELOG.md`

先頭の `---` 直後(既存の `## 2026-08-27` の**上**)に新しい日付見出しを作る。
**既存の見出しへ追記しない**(`/sync-template` が日付で読むため)。

```markdown
## 2026-08-29

**委託禁止領域に CI/hook の判定実体を含めた(Issue #40)。** `.github/workflows/` は守られていたのに、**そのワークフローが `bash` で呼ぶ判定スクリプトの本体は守られていませんでした**。定義を守っても、定義が実行する実体が書き換え可能なら防御は成立しません。

- **[manual]** ⚠️ **`FORBIDDEN_PATHS` に `.claude/scripts/` / `.claude/hooks/` / `.claude/settings.json` を追加した**(#40)。個別ファイル列挙(`delegate-codex.sh` / `check-protected-branch.sh`)は**ディレクトリ単位**に置き換え。#37 で足した `check-record-hygiene.sh` は冒頭に `exit 0` を 1 行書くだけで全 PR の記録漏れ検査を無効化できる状態でしたし、`check-guard-integrity.sh` を骨抜きにすると「husky 層が消えたことに気づけない」状態になります。`.claude/` 全体は禁止にせず、対象は**実行される実体**(scripts / hooks / settings.json)に限っています(`skills/` / `commands/` / `agents/` / `rules/` は従来どおり委託可)。**取り込む側の作業**: `AGENTS.md`(`merge` 区分)§4 のマーカー内に `.claude/scripts/` と `.claude/hooks/` / `.claude/settings.json` の 2 項目を足し、既存の `.claude/scripts/delegate-codex.sh` / `.claude/scripts/check-protected-branch.sh` の行を整理する。`CLAUDE.md`(`never` 区分)の禁止領域リストにも同じ変更を反映する
- **[auto]** ハーネス改修を Codex に委託していたプロジェクトでは、`.claude/scripts/` 配下を触る impl 委託が今後 `status=failed` / `exit 2` で止まります。ハーネス改修はもともと委託しない方針(`.claude/rules/lead/delegation-policy.md`)なので、通常の運用で失うものはありません
```

---

## §6. 品質チェック

```bash
bash -n .claude/scripts/delegate-codex.sh
npm run lint && npm run typecheck && npm test    # package.json のスクリプト名に合わせる
```

`.md` / `.sh` のみの変更なのでテストへの影響は無い見込みだが、**通してから完了報告する**。
