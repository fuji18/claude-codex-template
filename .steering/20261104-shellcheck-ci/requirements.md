# requirements: shellcheck を CI の機械的ゲートに加える

## 背景

`.steering/20261103-trusted-bots-union/` の作業で `shellcheck -x` を回そうとしたが、
**この環境のどこにも shellcheck が無く(ホスト・手元の docker イメージ全て)、取得も拒否された**。
さらに調べると **CI にも shellcheck のジョブが無い**ことが分かった。

ハーネスの判定の実体 —— 委託の入口(`delegate-codex.sh`)・保護ブランチ判定
(`check-protected-branch.sh`)・autopilot の選定(`autopilot-next.sh`)—— はほぼ全部シェルなのに、
機械的な検査は `ci.yml` の `bash -n`(構文エラーだけ)しかない。クォート漏れ・`cd` 失敗の
取りこぼしのような**意味的な欠陥は通ってしまう**。

## 要求

1. `ci.yml` に `shellcheck` のステップを足し、**git 追跡下のシェルスクリプト全量**に当てる
2. **ジョブが緑で始まること。** 既存の指摘は同じ変更の中で潰す(赤いまま入れたゲートは無効化される)
3. 深刻度は「鳴りっぱなしにならない」線で切る。このリポジトリが意図して使っている書き方
   (`set -e` を避ける `A && B || C` = SC2015、共有ライブラリの source = SC1091 など)で落とさない
4. `shellcheck` が見つからないときに**黙って通さない**(ゲートが消えたことに気づけない方が悪い)
5. 既存の指摘を直すとき、**ガードレールの挙動(フェイルオープン設計)を変えない**

## 非対象

- `.husky/_/`(husky の生成物。git 追跡外)と `.steering/`(過去の作業記録)の検査
- note 相当の指摘の解消(深刻度の線を下げない。個別に抑止するなら `# shellcheck disable` をその場に書く)
- shellcheck をローカル(devcontainer / pre-commit)にも入れること

## 受け入れ条件

- `shellcheck -x -P SCRIPTDIR --severity=warning` が追跡下の 30 ファイルで `exit 0`
- `bash -n`・`check-guard-integrity.sh`・`check-forbidden-paths-doc.sh`・`check-manifest-coverage.sh`・
  `test-sync-template.sh`・`test-route.sh`・`harness-mode.sh`・SessionStart hook が修正後も通る
- `ci.yml` が prettier を通り、YAML として壊れていない
- `docs/template-dev/CHANGELOG.md` に `[manual]`(`ci.yml` / `.husky/*` は `merge` 区分 = 手動統合)
