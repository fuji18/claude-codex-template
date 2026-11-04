# design: 信頼するボットを 2 キーの和集合で解決する

<!-- status: ready -->

## 方針

**どちらのスクリプトも `trustedBots` と `trustedReviewBots` の和集合(`unique`)を使う。**
キーは 2 つとも残し、既定値も変えない。「どちらに書いても両方で効く」ので、
`review-policy.md` の案内どおりに `trustedReviewBots` に足しただけでも `/fix-pr` が本文を読める。

和集合にするのは**設定の読み取りだけ**。信頼の判定条件(Bot 種別の確認・人間の
author_association)は一切変えない。

## 1. `.claude/scripts/pr-feedback.sh`

現状(37-40 行目付近):

```bash
CONF=.claude/autopilot.json
BOTS='["claude[bot]","github-actions[bot]"]'
if [ -f "$CONF" ] && jq -e '.trustedBots | type == "array"' "$CONF" >/dev/null 2>&1; then
  BOTS="$(jq -c '.trustedBots' "$CONF")"
fi
```

変更後:

```bash
CONF=.claude/autopilot.json
# 「信頼するボット」は trustedBots と trustedReviewBots の和集合。
# どちらのキーに書いても pr-feedback.sh / autopilot-next.sh の両方で効く
# (trustedReviewBots にだけ足すと変更要求は検出されるのに本文が返らず、/fix-pr が空振りする)
BOTS='["claude[bot]","github-actions[bot]"]'
if [ -f "$CONF" ]; then
  BOTS="$(jq -c '
    ((if (.trustedBots | type) == "array" then .trustedBots else ["claude[bot]", "github-actions[bot]"] end)
     + (if (.trustedReviewBots | type) == "array" then .trustedReviewBots else [] end)) | unique' "$CONF" 2>/dev/null)" ||
    die "$CONF の trustedBots / trustedReviewBots を読めない"
fi
```

- 型が配列でないキーは**既定値側に倒す**(現状の `pr-feedback.sh` と同じ寛容さ。型検査で die
  するのは `autopilot-next.sh` 側の役割で、そちらが先に止める)
- `jq` 自体が失敗したとき(`$CONF` が JSON でない等)は `die`。現状は黙って既定値のままになるが、
  **設定を読めていないのに「信頼するボットなし」で続けない**方が安全側
- `trusted` 関数の `.user.type == "Bot"` の確認はそのまま残す

## 2. `.claude/scripts/autopilot-next.sh`

現状(93-100 行目付近):

```bash
TRUSTED_BOTS='[]'
if [ -f "$CONF" ]; then
  TRUSTED_BOTS="$(jq -c 'if has("trustedReviewBots") then .trustedReviewBots else [] end' "$CONF" 2>/dev/null)" ||
    die "$CONF の trustedReviewBots を読めない"
  jq -e 'type == "array" and all(.[]; type == "string")' <<<"$TRUSTED_BOTS" >/dev/null 2>&1 ||
    die "trustedReviewBots は文字列の配列にする: $TRUSTED_BOTS"
fi
```

変更後(キーごとに型検査 → 和集合):

```bash
# 変更要求を信頼するボット(例: GitHub 上の Codex レビュー)。ログイン名の配列。
# trustedBots(pr-feedback.sh が本文を返す Bot)との和集合を使う。どちらのキーに書いても
# 両方のスクリプトで効く(片方だけだと要対応にはなるが本文が返らず /fix-pr が空振りする)
TRUSTED_BOTS='[]'
if [ -f "$CONF" ]; then
  for k in trustedBots trustedReviewBots; do
    v="$(jq -c --arg k "$k" 'if has($k) then .[$k] else null end' "$CONF" 2>/dev/null)" ||
      die "$CONF の $k を読めない"
    [ "$v" = null ] && continue
    jq -e 'type == "array" and all(.[]; type == "string")' <<<"$v" >/dev/null 2>&1 ||
      die "$k は文字列の配列にする: $v"
    TRUSTED_BOTS="$(jq -c --argjson a "$v" '. + $a | unique' <<<"$TRUSTED_BOTS")" ||
      die "$k を取り込めない"
  done
  # キーが 1 つも無いときは pr-feedback.sh と同じ既定値に倒す
  jq -e 'has("trustedBots") or has("trustedReviewBots")' "$CONF" >/dev/null 2>&1 ||
    TRUSTED_BOTS='["claude[bot]","github-actions[bot]"]'
fi
```

- 既定値の扱いを `pr-feedback.sh` と揃える: **`trustedBots` キーが無ければ**
  `["claude[bot]","github-actions[bot]"]` が既定。`trustedReviewBots` だけがあるときは
  「既定 + そのリスト」になる(`pr-feedback.sh` の和集合と同じ結果)
- `trustedBots` の型検査を `trustedReviewBots` と同じ強さにする(配列でなければ `exit 2`)
- 判定側の jq(`def trusted`)は変えない。`$bots` に和集合が入るだけ

既定値の一致を崩さないため、**キーが片方だけあるときの結果を両スクリプトで揃える**:

| `.claude/autopilot.json` | 両スクリプトの `$bots` |
| --- | --- |
| 両キーなし | `["claude[bot]","github-actions[bot]"]` |
| `trustedBots: [X]` のみ | `[X]` |
| `trustedReviewBots: [Y]` のみ | `["claude[bot]","github-actions[bot]", Y]` の unique |
| 両方 | 和集合 |

> `trustedReviewBots` だけがある構成では `trustedBots` が既定値に倒れる。これはテンプレート既定の
> `.claude/autopilot.json`(両キーを持つ)では起きないが、キーを削ったプロジェクトでも
> 両スクリプトの結果が一致することを保証するために揃える。

## 3. 文書(すべて「どちらに書いても両方で効く」に揃える)

| ファイル | 直す箇所 |
| --- | --- |
| `.claude/autopilot.json` | `$comment` の trustedBots / trustedReviewBots の説明 |
| `.claude/commands/autopilot.md` | 設定表の 2 行 |
| `.claude/docs/autopilot-guide.html` | 設定表(`trustedBots` の行を足す)と FAQ「コメントだけのレビュー指摘は拾われる?」 |
| `.claude/commands/fix-pr.md` | ステップ2-3(と 1-5 の `trustedBots` の記述) |
| `.claude/rules/lead/review-policy.md` | 「GitHub 上の Codex レビュー」の項 |

**既定値そのものは変えない。** `.claude/autopilot.json` の `trustedReviewBots` は `[]` のまま。

## 4. `docs/template-dev/CHANGELOG.md`

`## 2026-11-03` の見出しに `[auto]` で 1 項目を足す(キーの追加ではなく読み取りの統合なので
取り込む側の作業はゼロ)。

## 検証(スタブ・フィクスチャ)

`.claude/scripts/` は委託禁止領域なので Codex に委託せず、司令塔が直接書く。
検証は使い捨てのスタブ・フィクスチャをスクラッチパッドに置き、リポジトリにはコミットしない。

### `pr-feedback.sh`

`gh` をスタブに差し替え(`PATH` の先頭に置く)、`pulls/7/reviews` と `pulls/7/comments` に
`user.type: "Bot"` / login `chatgpt-codex-connector[bot]` / `author_association: "NONE"` の
本文を 1 件ずつ返させる。`issues/7/comments` は空配列。

| `.claude/autopilot.json` | 期待 |
| --- | --- |
| `trustedReviewBots` にだけ入れる | `reviews` 1 件・`reviewComments` 1 件に本文、`untrusted.count` = 0 |
| `trustedBots` にだけ入れる | 同じ |
| どちらにも入れない | 本文 0 件、`untrusted.count` = 2 |
| `user.type: "User"` で同じ login | 信頼しない(本文 0 件) |

### `autopilot-next.sh`

`--issues` / `--prs` / `--details` のフィクスチャを使う。`--details` の `reviews` に
`{"user":"chatgpt-codex-connector[bot]","state":"CHANGES_REQUESTED","commit_id":"<head sha>","author_association":"NONE"}`。

| `.claude/autopilot.json` | 期待 |
| --- | --- |
| `trustedBots` に入れる | `action: fix` |
| `trustedReviewBots` に入れる | `action: fix` |
| どちらにも入れない | `fix` にならない |
| `trustedBots` が文字列の配列でない | `exit 2` |

### 静的検査

- `bash -n` と `shellcheck -x`(変更前から警告を増やさない)
- `bash .claude/scripts/check-forbidden-paths-doc.sh`
- `npx prettier --check .`
- `bash .claude/scripts/autopilot-preflight.sh` の設定検査が ✅ のまま
