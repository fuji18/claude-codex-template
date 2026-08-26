# 検証結果: Issue #23 委託先へ渡る環境変数のサニタイズ

## 4.1 環境変数が渡っていないことの確認(受け入れ条件2)

実行コマンド(`.claude/settings.local.json` は権限設定のみで機密を含まないため
`CODEX_DELEGATE_ACK_SECRETS=1` で承認して実行した):

```bash
CODEX_DELEGATE_ACK_SECRETS=1 .claude/scripts/delegate-codex.sh explore \
  "シェルで \`env | cut -d= -f1 | sort\` を実行し、出力をそのまま報告してください。他のファイルは読まないでください。"
```

run id: `20260826-092507-53699`(`.harness/codex-runs/20260826-092507-53699.log`)

- 委託先が報告した `env` の変数名一覧: `CODEX_CI` / `CODEX_MANAGED_BY_NPM` /
  `CODEX_MANAGED_PACKAGE_ROOT` / `CODEX_SANDBOX_NETWORK_DISABLED` /
  `CODEX_SESSION_ID` / `CODEX_THREAD_ID` / `COLORTERM` / `GH_PAGER` / `GIT_PAGER` /
  `HOME` / `LANG` / `LC_ALL` / `LC_CTYPE` / `NO_COLOR` / `PAGER` / `PATH` / `PWD` /
  `SHELL` / `SHLVL` / `TERM` / `USER` / `_`
- `LOCAL_GH_TOKEN` / `CLAUDE_CODE_MESSAGING_TOKEN` / `CLAUDE_CODE_SESSION_ID` /
  `GITHUB_TOKEN` / `GH_TOKEN` は**含まれない**(生ログを
  `grep -iE "LOCAL_GH_TOKEN|CLAUDE_CODE_MESSAGING_TOKEN|CLAUDE_CODE_SESSION_ID|GITHUB_TOKEN|GH_TOKEN"`
  で確認 → 0 件)
- `PATH` / `HOME` は**ある**

**受け入れ条件2 は満たされた。** なお `CODEX_*` の一部(`CODEX_CI` 等)は Codex CLI 自身が
sandbox 内で設定するものであり、`delegate-codex.sh` が親から渡した変数ではない
(design §2.2 の許可リストには含まれておらず、`env -i` 起動後に codex 本体が付与する)。

## 4.2 3 モードの完走(受け入れ条件1)

- **explore**: 上記 4.1 の実行で完走を確認(exit 0 / `status=completed`)
- **review**: `CODEX_DELEGATE_ACK_SECRETS=1 .claude/scripts/delegate-codex.sh review main`
  を実行し完走(exit 0 / `status=completed` / run id `20260826-092548-55359`)。
  差分が実質空だったため指摘は「指摘なし」。
- **impl**: 司令塔が実測済み。使い捨てステアリング `.steering/20260826-env-probe/`
  (tasklist 3 項目)を用意し、`.claude/scripts/delegate-codex.sh impl` で委託した
  (run id `20260826-111132-77303` / `.harness/codex-runs/20260826-111132-77303.log` /
  exit 0 / `status=completed` / tasklist 3/3)。

  確認できた点:
  - sandbox(`workspace-write`)内で `node --version`(`v24.18.0`)/
    `npx --no-install prettier --version`(`3.9.6`)/ `git status --short` が
    いずれも成功し、env サニタイズ後も開発ツールチェーン(Node / npx / git)が
    壊れていないことを確認した
  - 委託先の `env | cut -d= -f1 | sort` の出力に `LOCAL_GH_TOKEN` /
    `CLAUDE_CODE_*` / `GITHUB_TOKEN` / `GH_TOKEN` は含まれない
    (実際の出力: `CODEX_CI CODEX_MANAGED_BY_NPM CODEX_MANAGED_PACKAGE_ROOT
    CODEX_SANDBOX_NETWORK_DISABLED CODEX_SESSION_ID CODEX_THREAD_ID COLORTERM
    GH_PAGER GIT_PAGER HOME LANG LC_ALL LC_CTYPE NO_COLOR PAGER PATH PWD SHELL
    SHLVL TERM USER _`)
  - 結果は `.steering/20260826-env-probe/probe-result.md` に記録されている。
    検証用の使い捨てステアリング `.steering/20260826-env-probe/` は検証後に削除する

  これにより受け入れ条件1(3 モード完走)は explore / review に加え impl も
  実測で確認できた。

## 4.3 静的検査

```bash
bash -n .claude/scripts/delegate-codex.sh   # → 構文エラーなし(SYNTAX OK)
```

`npx --no-install prettier --check .steering/20260826-issue23-env-sanitize/` は
`/check` の一部として司令塔側で実施予定(design §4.3 の記載どおり)。

## まとめ

受け入れ条件1(explore / review / impl の3モード完走)・受け入れ条件2(機密変数の非到達)
とも実測で確認できた。`.claude/scripts/delegate-codex.sh` の `codex exec` 起動が
`env -i` + 許可リスト方式に置き換わり、親環境の機密変数(`LOCAL_GH_TOKEN` 等)は
委託先へ渡らないこと、かつ env サニタイズ後も sandbox 内の開発ツールチェーンが
正常に動作することを確認した。
