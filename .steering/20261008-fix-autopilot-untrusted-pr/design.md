<!-- status: ready -->
# 設計

- `prs.json` の整形で `trusted: ((.head.repo.full_name? // null) == (.base.repo.full_name? // null))` を持たせる
  - fork: 不一致 → false / fork 削除(head.repo = null): 不一致 → false / フィクスチャ(両方欠落): null == null → true
- 1 段目で `Closes` がチケットに紐づく PR を `$linked` とし、`trusted` のものだけを従来の `$tprs`(inFlight・詳細取得・fix 判定の対象)にする
- 信頼しない PR は `untrusted: [{pr, issues}]` として BASE に載せ、最終 JSON の `untrustedPrs` と要約の ⚠️ 行に出す
- 紐づくチケットは in-flight 扱いにしない(外部 PR で枠が埋まらない。チケットは通常どおり着手候補に残る)
- author_association での絞り込みはしない(同一リポジトリへの push = 書き込み権限があるため head リポジトリの一致で足りる)
