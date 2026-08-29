# タスクリスト: CHANGELOG 検査のトリガに `.github/workflows/` を追加する(Issue #41)

design.md の §番号に対応する。上から順に消化する。

## 実装

- [x] §1 `check-record-hygiene.sh` の 31〜33 行目をコメント込みで置き換える(配列に `.github/workflows/` を追加)
- [x] §2 `delegation-policy.md` 52 行目の検査表を実態に合わせる
- [x] §3 `CHANGELOG.md` 13 行目「記法」節のトリガ列挙を実態に合わせる
- [x] §4 `CHANGELOG.md` の `## 2026-08-29` 節末尾に #41 の項目を追記する
- [x] 4 箇所の列挙(スクリプト配列 / delegation-policy 表 / CHANGELOG 記法 / CHANGELOG 追記)が一致していることを突き合わせる

## 検証

- [x] §5 V0〜V6 の 7 ケースを実行する
- [x] §5 実測結果を `verification.md` に表で記録する
- [x] §6 品質チェック(`bash -n` / eslint / tsc)を通す
