# タスクリスト: 検証プローブのホスト実行経路を閉じる(Issue #82)

> 設計は `design.md`。**設計判断は済んでいる**(方式 1「exec を無くす」を採用)。
> 判断が必要になったら停止して報告すること。

## 実装

- [x] T1 `probe_format_reason()` に P0 分岐を追加する(design §3)。挿入位置は `last="${parts[$((n - 1))]}"` の直後・`java -version` 特例より前
- [x] T2 `# (c)` ブロックの形式一覧に P0 行を追加し、末尾の「許可された形に一致しません」メッセージに `exists <相対パス>` を足す(design §3 後半)
- [x] T3 ホスト側に `elif [ "${PROBE%% *}" = "exists" ]` 分岐を追加する(design §4)。`unset` に `_probe_path` を足す
- [x] T4 `delegate-codex.sh:497-503` の「実在しない代償措置」コメントを差し替える(design §5)
- [x] T5 `bash -n .claude/scripts/delegate-codex.sh` で構文を確認する

## ドキュメント

- [x] T6 `AGENTS.md` 86 行目のマーカーを `exists node_modules/.bin/eslint` に変更する(design §6 D-1)
- [x] T7 `AGENTS.md` §2 の形式制約ブロックを差し替える(design §6 D-2)
- [x] T8 `AGENTS.md` 155 行目の禁止領域の説明を更新する(design §6 D-3)
- [x] T9 `docs/template-dev/CHANGELOG.md` に `## 2026-09-06` 見出しを新設し `[manual]` で追記する(design §8)

## 検証(design §10。V1〜V16 をすべて実行し結果を記録する)

**開始前に `cp AGENTS.md /tmp/AGENTS.md.bak` でバックアップを取ること。**

- [x] V1 `exists node_modules/.bin/eslint` が通る(`検証プローブ(存在確認・プロセス起動なし)` が出る)
- [x] V2 `exists node_modules/.bin/does-not-exist` が `検証プローブの対象が存在しません` で `exit 3`
- [x] V3 `exists ../../etc/passwd` が形式検査で落ちる
- [x] V4 `exists /etc/passwd` が形式検査で落ちる
- [x] V5 `exists node_modules/../../../etc/passwd` が形式検査で落ちる
- [x] V6 `exists -rf` が形式検査で落ちる
- [x] V7 `exists`(1 トークン)が形式検査で落ちる
- [x] V8 `exists a b`(3 トークン)が形式検査で落ちる
- [x] V9 `exists --version` が形式検査で落ちる(P1 として通らないこと)
- [x] V10 `npx --no-install eslint --version` が従来どおり通る(後方互換)
- [x] V11 `node --version` と `java -version` が従来どおり通る(後方互換)
- [x] V12 `python3 -I -m pytest --version` が形式検査を通る(後方互換)
- [x] V13 検証後に `AGENTS.md` を復元し、`git diff -- AGENTS.md` が D-1 / D-2 / D-3 の変更だけになっている
- [x] V14 `npm run lint` が通る
- [x] V15 `npm run format:check` が通る(落ちたら `npx prettier --write` で変更ファイルのみ整形)
- [x] V16 `bash .claude/scripts/check-guard-integrity.sh` が通る

## 記録

- [x] T10 検証結果を `.steering/20260906-issue82-probe-exists/verification.md` に記録する(V1〜V16 の実測出力の要点)
