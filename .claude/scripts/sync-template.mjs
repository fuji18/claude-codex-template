#!/usr/bin/env node
/* global process, console, Buffer */
// テンプレートの更新をこのプロジェクトへ取り込む(/sync-template と月次の
// template-update-check が呼ぶ機械処理の実体)。
//
//   node .claude/scripts/sync-template.mjs [--dry-run] [--json] [--ref <ref>]
//   node .claude/scripts/sync-template.mjs --check-drift
//
// やること(判断の要らない部分だけ):
//   - owned  : テンプレートの内容で上書きする。テンプレートで消えたファイルは、
//              ローカルで手を入れていなければ消す(入れていれば残して報告)
//   - merge  : 前回同期した版(syncedAt)を共通の祖先にした 3-way マージ。
//              テキストは git merge-file、JSON はキー単位の構造マージ。
//              両側が同じ箇所を変えたときだけ「競合」として報告し、
//              テキストには競合マーカーを残す(JSON はローカル側の値を残す)
//   - never  : 触らない
//   - manifest の syncedAt / syncedDate を取り込み先の commit に進める
//
// やらないこと: 競合の解消と CHANGELOG の [manual] 項目の対応。それは
// /sync-template(Claude)か人間が行う。--json の出力に材料をすべて載せる。
//
// 区分の判定: パスが複数のエントリに当たるときは、最も具体的な(長い)エントリが勝つ。
// 同じ長さなら owned > merge > never。ただし**プロジェクトの manifest にだけある
// never のエントリ**(テンプレートから更新されたくないものとしてプロジェクトが
// 足したもの)は、長さに関係なく最優先する。
//
// 終了コード: 0 = 完了(または変更なし) / 1 = 実行できない(前提条件の不足)/
//             2 = 完了したが競合あり(解消してからコミットする)
//
// --check-drift: owned のファイルのうち、前回同期した版から**ローカルで書き換え
// られているもの**を列挙するだけ(何も変更しない)。次の同期で上書きされて
// 失われる変更の早期発見に使う。該当があれば終了コード 3。

import { spawnSync } from 'node:child_process';
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';

const MANIFEST = '.claude/template-manifest.json';
const REMOTE = 'template';

const args = process.argv.slice(2);
const opt = {
  dryRun: args.includes('--dry-run'),
  json: args.includes('--json'),
  checkDrift: args.includes('--check-drift'),
  ref: args.includes('--ref') ? args[args.indexOf('--ref') + 1] : null,
};

function git(argv, { input, allowFail = false, binary = false } = {}) {
  const r = spawnSync('git', argv, {
    input,
    encoding: binary ? 'buffer' : 'utf8',
    maxBuffer: 256 * 1024 * 1024,
  });
  if (r.status !== 0 && !allowFail) {
    const err = binary ? r.stderr.toString() : r.stderr;
    throw new Error(`git ${argv.join(' ')}: ${err.trim()}`);
  }
  return r;
}

function fail(msg) {
  if (opt.json) console.log(JSON.stringify({ ok: false, error: msg }));
  else console.error(`❌ ${msg}`);
  process.exit(1);
}

function normalizeRepo(url) {
  return String(url || '')
    .trim()
    .replace(/^(https:\/\/|git@)github\.com[/:]/, '')
    .replace(/\.git$/, '')
    .toLowerCase();
}

// ---------- 区分の判定 ----------

function buildClassifier(templateManifest, localManifest) {
  const entries = [];
  for (const kind of ['owned', 'merge', 'never']) {
    for (const p of templateManifest[kind] || []) entries.push({ kind, p });
  }
  const templateNever = new Set(templateManifest.never || []);
  const overrides = (localManifest.never || []).filter(
    (p) => !templateNever.has(p)
  );
  const rank = { owned: 0, merge: 1, never: 2 };
  const hit = (path, p) =>
    path === p || (p.endsWith('/') && path.startsWith(p));
  return (path) => {
    if (overrides.some((p) => hit(path, p))) return 'never';
    let best = null;
    for (const e of entries) {
      if (!hit(path, e.p)) continue;
      if (
        !best ||
        e.p.length > best.p.length ||
        (e.p.length === best.p.length && rank[e.kind] < rank[best.kind])
      ) {
        best = e;
      }
    }
    return best ? best.kind : null;
  };
}

// ---------- 内容の取得 ----------

function blobAt(ref, path) {
  const r = git(['show', `${ref}:${path}`], { allowFail: true, binary: true });
  return r.status === 0 ? r.stdout : null;
}

function modeAt(ref, path) {
  const r = git(['ls-tree', ref, '--', path], { allowFail: true });
  return r.status === 0 && r.stdout ? r.stdout.split(' ')[0] : null;
}

function localBlob(path) {
  return existsSync(path) ? readFileSync(path) : null;
}

function same(a, b) {
  if (a === null || b === null) return a === b;
  return Buffer.compare(a, b) === 0;
}

// ---------- JSON の 3-way マージ ----------

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const isScalarArray = (v) =>
  Array.isArray(v) && v.every((x) => x === null || typeof x !== 'object');
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

function merge3(base, local, theirs, path, conflicts) {
  if (eq(local, theirs)) return local;
  if (eq(base, local)) return theirs;
  if (eq(base, theirs)) return local;
  if (isObj(local) && isObj(theirs)) {
    const b = isObj(base) ? base : {};
    const out = {};
    const keys = [...new Set([...Object.keys(local), ...Object.keys(theirs)])];
    for (const k of keys) {
      const inL = k in local;
      const inT = k in theirs;
      const inB = k in b;
      if (inL && inT) {
        out[k] = merge3(b[k], local[k], theirs[k], `${path}.${k}`, conflicts);
      } else if (inL && !inT) {
        // テンプレートが消した: ローカルが手を入れていなければ消す
        if (inB && eq(b[k], local[k])) continue;
        if (inB)
          conflicts.push(`${path}.${k}(テンプレートで削除・ローカルで変更)`);
        out[k] = local[k];
      } else if (!inL && inT) {
        // ローカルが消した: テンプレートが変えていなければ消したまま
        if (inB && eq(b[k], theirs[k])) continue;
        if (inB)
          conflicts.push(`${path}.${k}(ローカルで削除・テンプレートで変更)`);
        else out[k] = theirs[k];
      }
    }
    return out;
  }
  if (isScalarArray(local) && isScalarArray(theirs)) {
    // 集合として 3-way: ローカルの追加・削除とテンプレートの追加・削除を両方反映
    const b = isScalarArray(base) ? base : [];
    const key = (x) => JSON.stringify(x);
    const bS = new Set(b.map(key));
    const tS = new Set(theirs.map(key));
    const removedByTemplate = new Set([...bS].filter((x) => !tS.has(x)));
    const out = local.filter((x) => !removedByTemplate.has(key(x)));
    const outS = new Set(out.map(key));
    const lS = new Set(local.map(key));
    for (const x of theirs) {
      const k = key(x);
      // テンプレートの追加分だけ足す(ローカルが消したものは戻さない)
      if (!bS.has(k) && !outS.has(k) && !lS.has(k)) {
        out.push(x);
        outS.add(k);
      }
    }
    return out;
  }
  conflicts.push(`${path}(両側で変更。ローカルの値を残した)`);
  return local;
}

function mergeJson(baseBuf, localBuf, theirsBuf) {
  const parse = (b) => (b === null ? undefined : JSON.parse(b.toString()));
  const conflicts = [];
  const merged = merge3(
    parse(baseBuf),
    parse(localBuf),
    parse(theirsBuf),
    '$',
    conflicts
  );
  return {
    content: Buffer.from(JSON.stringify(merged, null, 2) + '\n'),
    conflicts,
  };
}

// ---------- テキストの 3-way マージ ----------

// 1 行 1 エントリのリスト(ignore 系)は、行の追加どうしを競合にしない(和集合で取り込む)
const UNION_FILES =
  /(^|\/)\.(gitignore|prettierignore|secretlintignore|gitattributes)$|codex-denylist\.txt$/;

function mergeText(baseBuf, localBuf, theirsBuf, union = false) {
  const dir = mkdtempSync(join(tmpdir(), 'sync-template-'));
  try {
    const f = (n, b) => {
      const p = join(dir, n);
      writeFileSync(p, b ?? Buffer.alloc(0));
      return p;
    };
    const cur = f('local', localBuf);
    const base = f('base', baseBuf);
    const other = f('template', theirsBuf);
    const r = spawnSync('git', [
      'merge-file',
      ...(union ? ['--union'] : []),
      '-L',
      'project',
      '-L',
      'last-sync',
      '-L',
      'template',
      cur,
      base,
      other,
    ]);
    if (r.status < 0 || r.status === null)
      throw new Error('git merge-file failed');
    return { content: readFileSync(cur), conflicts: r.status };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// ---------- 本体 ----------

function main() {
  const top = git(['rev-parse', '--show-toplevel'], { allowFail: true });
  if (top.status !== 0) fail('git リポジトリの中で実行してください');
  process.chdir(top.stdout.trim());

  if (!existsSync(MANIFEST)) {
    fail(`${MANIFEST} がありません(テンプレート同期に未対応のプロジェクト)`);
  }
  const localManifest = JSON.parse(readFileSync(MANIFEST, 'utf8'));
  const templateRepo = localManifest.templateRepo;
  const branch = localManifest.templateBranch || 'main';
  const base = localManifest.syncedAt;

  const origin = git(['remote', 'get-url', 'origin'], { allowFail: true });
  const self = process.env.GITHUB_REPOSITORY || origin.stdout;
  if (normalizeRepo(self) === normalizeRepo(templateRepo)) {
    fail('ここはテンプレート本体です。同期はプロジェクト側で実行します');
  }
  if (!base) {
    fail(
      'syncedAt が未設定です。プロジェクトを始めた時点のテンプレートの commit SHA を ' +
        `${MANIFEST} の syncedAt に書いてから実行してください(README「初回ブートストラップ」)`
    );
  }

  // テンプレートを取得する
  if (git(['remote', 'get-url', REMOTE], { allowFail: true }).status !== 0) {
    git(['remote', 'add', REMOTE, templateRepo]);
  }
  git(['fetch', '--quiet', '--tags', REMOTE, branch]);
  const target = git([
    'rev-parse',
    opt.ref || `${REMOTE}/${branch}`,
  ]).stdout.trim();
  if (git(['cat-file', '-e', `${base}^{commit}`], { allowFail: true }).status) {
    // 浅いクローン等で祖先が無い場合は深く取り直す
    git(['fetch', '--quiet', '--unshallow', REMOTE], { allowFail: true });
    git(['fetch', '--quiet', REMOTE, base], { allowFail: true });
    if (
      git(['cat-file', '-e', `${base}^{commit}`], { allowFail: true }).status
    ) {
      fail(`syncedAt の commit ${base} がテンプレートに見つかりません`);
    }
  }

  const templateManifest = JSON.parse(blobAt(target, MANIFEST).toString());
  const classify = buildClassifier(templateManifest, localManifest);

  // --- ドリフト検出(読み取りのみ) ---
  const ownedAtBase = git(['ls-tree', '-r', '--name-only', base])
    .stdout.split('\n')
    .filter((p) => p && classify(p) === 'owned');
  const drift = ownedAtBase.filter((p) => {
    const l = localBlob(p);
    return l !== null && !same(l, blobAt(base, p));
  });
  if (opt.checkDrift) {
    if (opt.json) console.log(JSON.stringify({ ok: true, base, drift }));
    else if (drift.length === 0)
      console.log('owned のファイルにローカルの書き換えはありません');
    else {
      console.log(
        '次の owned ファイルはローカルで書き換えられています(次の同期で上書きされます):'
      );
      for (const p of drift) console.log(`  ${p}`);
    }
    process.exit(drift.length ? 3 : 0);
  }

  if (!opt.dryRun) {
    const dirty = git(['status', '--porcelain', '--untracked-files=no']).stdout;
    if (dirty.trim())
      fail(
        '未コミットの変更があります。コミットか stash をしてから実行してください'
      );
  }

  const result = {
    ok: true,
    dryRun: opt.dryRun,
    from: base,
    to: target,
    overwritten: [],
    added: [],
    deleted: [],
    keptLocallyModified: [],
    merged: [],
    conflicts: [],
    skipped: [],
    driftOverwritten: [],
  };

  if (target === base) {
    if (opt.json) console.log(JSON.stringify({ ...result, upToDate: true }));
    else console.log('テンプレートは最新です');
    return 0;
  }

  const write = (path, buf, mode) => {
    if (opt.dryRun) return;
    mkdirSync(dirname(path) || '.', { recursive: true });
    writeFileSync(path, buf);
    if (mode) chmodSync(path, mode === '100755' ? 0o755 : 0o644);
  };
  const remove = (path) => {
    if (!opt.dryRun && existsSync(path)) unlinkSync(path);
  };

  const diff = git(['diff', '--name-status', '--no-renames', base, target])
    .stdout.split('\n')
    .filter(Boolean)
    .map((l) => l.split('\t'));

  let manifestTouched = false;
  for (const [status, path] of diff) {
    const kind = classify(path);
    if (kind !== 'owned' && kind !== 'merge') continue;
    if (path === MANIFEST) {
      manifestTouched = true;
      continue;
    }
    const baseBuf = blobAt(base, path);
    const theirs = blobAt(target, path);
    const mode = modeAt(target, path);
    const local = localBlob(path);

    if (status === 'D') {
      if (local === null) continue;
      if (same(local, baseBuf)) {
        remove(path);
        result.deleted.push(path);
      } else {
        result.keptLocallyModified.push(path);
      }
      continue;
    }

    if (kind === 'owned') {
      if (same(local, theirs)) continue;
      if (local !== null && !same(local, baseBuf))
        result.driftOverwritten.push(path);
      write(path, theirs, mode);
      (local === null ? result.added : result.overwritten).push(path);
      continue;
    }

    // merge
    if (local === null) {
      if (baseBuf !== null) {
        // ローカルで消してある。テンプレートが変えても戻さない
        result.skipped.push(`${path}(ローカルで削除済み)`);
        continue;
      }
      write(path, theirs, mode);
      result.added.push(path);
      continue;
    }
    if (same(local, theirs)) continue;
    if (same(local, baseBuf)) {
      write(path, theirs, mode);
      result.overwritten.push(path);
      continue;
    }
    if (path.endsWith('.json')) {
      let m;
      try {
        m = mergeJson(baseBuf, local, theirs);
      } catch {
        m = null;
      }
      if (m) {
        write(path, m.content);
        result.merged.push(path);
        if (m.conflicts.length)
          result.conflicts.push({ path, detail: m.conflicts });
        continue;
      }
    }
    const m = mergeText(baseBuf, local, theirs, UNION_FILES.test(path));
    write(path, m.content);
    result.merged.push(path);
    if (m.conflicts > 0) {
      result.conflicts.push({
        path,
        detail: [`競合マーカー ${m.conflicts} 箇所`],
      });
    }
  }

  // manifest は最後に: 構造マージしてから同期位置を進める
  const theirsManifest = blobAt(target, MANIFEST);
  const m = manifestTouched
    ? mergeJson(
        blobAt(base, MANIFEST),
        Buffer.from(readFileSync(MANIFEST)),
        theirsManifest
      )
    : { content: readFileSync(MANIFEST), conflicts: [] };
  const nextManifest = JSON.parse(m.content.toString());
  nextManifest.syncedAt = target;
  nextManifest.syncedDate = new Date().toISOString().slice(0, 10);
  // テンプレート本体の識別子はローカルの値を正とする(フォーク運用の余地を残す)
  nextManifest.templateRepo = localManifest.templateRepo;
  nextManifest.templateBranch = localManifest.templateBranch;
  write(MANIFEST, Buffer.from(JSON.stringify(nextManifest, null, 2) + '\n'));
  if (m.conflicts.length)
    result.conflicts.push({ path: MANIFEST, detail: m.conflicts });

  // CHANGELOG のうち前回同期より後の日付の節(取り込み側の [manual] 作業の材料)
  const baseDate =
    localManifest.syncedDate ||
    git(['show', '-s', '--format=%cs', base]).stdout.trim();
  const log = blobAt(target, 'docs/template-dev/CHANGELOG.md');
  result.changelog = [];
  if (log) {
    const sections = log.toString().split(/^(?=## \d{4}-\d{2}-\d{2})/m);
    for (const s of sections) {
      const d = s.match(/^## (\d{4}-\d{2}-\d{2})/);
      if (d && d[1] >= baseDate) result.changelog.push(s.trim());
    }
  }
  result.manual =
    result.changelog.join('\n').match(/^- \*\*\[manual\]\*\*.*$/gm) || [];

  if (opt.json) {
    console.log(JSON.stringify(result));
  } else {
    const line = (label, xs) =>
      xs.length &&
      console.log(`${label} (${xs.length}):\n  ${xs.join('\n  ')}`);
    console.log(
      `テンプレート ${base.slice(0, 7)} → ${target.slice(0, 7)}${opt.dryRun ? '(dry-run: 変更していません)' : ''}`
    );
    line('上書き', result.overwritten);
    line('追加', result.added);
    line('削除', result.deleted);
    line('3-way マージ', result.merged);
    line(
      'テンプレートで削除されたがローカルで変更済みのため残した',
      result.keptLocallyModified
    );
    line(
      'ローカルの書き換えを上書きした owned ファイル',
      result.driftOverwritten
    );
    line('スキップ', result.skipped);
    if (result.conflicts.length) {
      console.log(`⚠️ 競合 (${result.conflicts.length}):`);
      for (const c of result.conflicts)
        console.log(`  ${c.path}: ${c.detail.join(' / ')}`);
    }
    if (result.manual.length) {
      console.log(`📝 CHANGELOG の [manual] 項目 (${result.manual.length}):`);
      for (const l of result.manual) console.log(`  ${l.slice(0, 160)}`);
    }
  }
  return result.conflicts.length ? 2 : 0;
}

try {
  process.exit(main());
} catch (e) {
  fail(e.message);
}
