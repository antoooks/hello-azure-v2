#!/usr/bin/env node
// Mirror the images listed in a mirroring list into an Azure Container Registry, using qcli (@unique-ag/cli, the
// tool the GitHub mirroring workflows use) or plain `az acr import`. Run with --help for usage.
//
// Plain Node.js (18+), no dependencies: runs the same on macOS, Linux and Windows, on amd64 and arm64.
// External commands are started with an argument list, never through a shell (except Windows .cmd shims, whose
// arguments are escaped for cmd.exe), so passwords and paths need no quoting.

import { spawn, spawnSync } from 'node:child_process';
import { accessSync, constants, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import readline from 'node:readline/promises';

const QCLI_PACKAGE = '@unique-ag/cli';
const QCLI_VERSION = process.env.QCLI_VERSION || '0.5.1'; // same version as .github/workflows/test.mirror-*.yaml
const IS_WIN = process.platform === 'win32';
const ME = 'mirror-registry';
const ENGINES = ['auto', 'qcli-import', 'qcli-mirror', 'az'];
const PACKAGE_MANAGERS = ['pnpm', 'yarn', 'npm'];

const HELP = `Usage: ${ME} [options] <list.yaml> [target-registry]

  macOS/Linux:  ./mirroring/mirror-registry.sh [options] <list.yaml>
  Windows:      mirroring\\mirror-registry.cmd [options] <list.yaml>
  Anywhere:     node mirroring/mirror-registry.mjs [options] <list.yaml>

Copies every image in <list.yaml> from its sourceRegistry into an Azure Container Registry.
Images that already exist in the target are skipped, so it is safe to re-run.

Arguments:
  <list.yaml>          Mirroring list, e.g. mirroring/test/io.docker.yaml, with 'sourceRegistry:' and
                       '- name: <image>:<tag>' entries.
  [target-registry]    Target ACR as a name (uqhacranto) or login server (uqhacranto.azurecr.io).
                       Defaults to the list's 'targetRegistryName:' or 'targetRegistry:'.

Options:
  -e, --engine <name>  How to copy (default: auto):
                         qcli-import  'qcli az acr import'. Server-side in Azure, keeps every architecture.
                                      Needs SRC_USER/SRC_PASS (qcli requires source credentials).
                         qcli-mirror  'qcli mirror images'. docker pull/tag/push through local Docker.
                                      qcli ${QCLI_VERSION} always pulls linux/amd64, so only for amd64 clusters.
                         az           'az acr import' directly. Server-side, keeps every architecture,
                                      works without credentials for public sources.
                         auto         qcli-import if credentials are set; else qcli-mirror if Docker is
                                      running and all target platforms are linux/amd64; else az.
  --install-qcli       Install ${QCLI_PACKAGE}@${QCLI_VERSION} if qcli is missing (also: QCLI_AUTO_INSTALL=true).
                       Without it, an interactive terminal is asked; otherwise auto falls back to az and
                       the qcli-* engines stop.
  --package-manager <pnpm|yarn|npm>
                       Package manager for installing qcli. Default: the one that launched this script, else
                       pnpm, then yarn 1, then npm.
  -p, --platform <list>
                       Platforms the images must support, comma-separated, e.g. linux/amd64,linux/arm64.
                       Default: the OS/architecture of the nodes in the current kubectl context, or
                       linux/amd64 if the cluster cannot be reached.
  -c, --concurrency <n>
                       Parallel imports for the az engine (1-8, default 4).
  --no-verify          Skip the check that the mirrored images contain every required platform.
  -n, --dry-run        Show the plan (engine, platforms, missing images) without copying anything.
  -h, --help           Show this help and exit.

Environment:
  SRC_USER, SRC_PASS   Source registry credentials. Required for private sources such as
                       uniquecr.azurecr.io (app.unique.yaml); optional for Docker Hub (rate limits).
  QCLI_VERSION         qcli version to install (default ${QCLI_VERSION}).
  QCLI_AUTO_INSTALL    "true" behaves like --install-qcli.

Architectures:
  Import engines (qcli-import, az) copy the full multi-platform image index, so every architecture the source
  publishes ends up in the target. qcli-mirror copies only linux/amd64 (fixed in qcli ${QCLI_VERSION}; pulling amd64
  on an arm64 machine is fine, nothing is run). After copying, each image is checked for the required platforms;
  the exit code is 2 if one is missing.

Prerequisites:
  Node.js 18+, Azure CLI with 'az login' and permission to import into the target registry (e.g. Contributor).
  qcli engines: qcli (see --install-qcli). qcli-mirror: a running Docker daemon.

Examples:
  # Public lists into the registry named in each list (bash/zsh)
  for f in mirroring/test/io.*.yaml; do ./mirroring/mirror-registry.sh "$f"; done

  # Force qcli, installing it first if needed
  ./mirroring/mirror-registry.sh --engine qcli-mirror --install-qcli mirroring/test/io.quay.yaml

  # Unique images (private source); read -s keeps the password out of shell history
  read -r -p "uniquecr username: " SRC_USER; read -r -s -p "uniquecr password: " SRC_PASS; echo
  SRC_USER="$SRC_USER" SRC_PASS="$SRC_PASS" ./mirroring/mirror-registry.sh mirroring/test/app.unique.yaml

  # PowerShell
  $env:SRC_USER = "..."; $env:SRC_PASS = Read-Host -MaskInput "uniquecr password"
  node mirroring/mirror-registry.mjs mirroring/test/app.unique.yaml

  # What would happen for an arm64 + amd64 cluster
  ./mirroring/mirror-registry.sh --dry-run --platform linux/amd64,linux/arm64 mirroring/test/io.ghcr.yaml
`;

// --- output helpers ----------------------------------------------------------------------------------------------

function die(message, { usageHint = true, code = 1 } = {}) {
  console.error(`Error: ${message}`);
  if (usageHint) console.error(`Run '${ME} --help' for usage.`);
  process.exit(code);
}
const warn = (message) => console.error(`warning: ${message}`);
const info = (message) => console.log(message);

const nodeMajor = Number(process.versions.node.split('.')[0]);
if (nodeMajor < 18) die(`Node.js 18 or newer is required (found ${process.versions.node})`, { usageHint: false });

// --- running external commands -----------------------------------------------------------------------------------

/** Finds an executable on PATH (with PATHEXT on Windows). Returns its full path or null. */
function which(command) {
  const extensions = IS_WIN ? (process.env.PATHEXT || '.EXE;.CMD;.BAT;.COM').split(';').filter(Boolean) : [''];
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    for (const ext of extensions) {
      const candidate = path.join(dir, IS_WIN && !path.extname(command) ? command + ext : command);
      try {
        if (!statSync(candidate).isFile()) continue;
        if (!IS_WIN) accessSync(candidate, constants.X_OK);
        return candidate;
      } catch {
        // not here
      }
    }
  }
  return null;
}

// Windows .cmd/.bat files (az.cmd, qcli.cmd, pnpm.cmd, ...) can only run through cmd.exe. Arguments are escaped the
// same way cross-spawn does it; Node-based shims re-parse their arguments, so their metacharacters are escaped twice.
const CMD_META = /([()\][%!^"`<>&|;, *?])/g;
function escapeCmdArgument(argument, doubleEscape) {
  let escaped = `${argument}`.replace(/(?=(\\+?)?)\1"/g, '$1$1\\"').replace(/(?=(\\+?)?)\1$/, '$1$1');
  escaped = `"${escaped}"`.replace(CMD_META, '^$1');
  return doubleEscape ? escaped.replace(CMD_META, '^$1') : escaped;
}

function prepare(command, args) {
  const resolved = which(command);
  if (!resolved) return null;
  if (IS_WIN && /\.(cmd|bat)$/i.test(resolved)) {
    let isNodeShim = false;
    try {
      isNodeShim = /node(\.exe)?["\s]/i.test(readFileSync(resolved, 'utf8'));
    } catch {
      // unreadable: treat as a plain batch file
    }
    const line = [resolved.replace(CMD_META, '^$1'), ...args.map((a) => escapeCmdArgument(a, isNodeShim))].join(' ');
    return {
      file: process.env.ComSpec || 'cmd.exe',
      args: ['/d', '/s', '/c', `"${line}"`],
      options: { windowsVerbatimArguments: true },
    };
  }
  return { file: resolved, args, options: {} };
}

/** Runs a command and captures its output. Never throws; code 127 means "not found". */
function run(command, args, { input, timeout } = {}) {
  const prepared = prepare(command, args);
  if (!prepared) return { code: 127, stdout: '', stderr: `${command}: command not found` };
  const result = spawnSync(prepared.file, prepared.args, {
    ...prepared.options,
    input,
    timeout,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    stdio: [input === undefined ? 'ignore' : 'pipe', 'pipe', 'pipe'],
  });
  return { code: result.status ?? 1, stdout: result.stdout || '', stderr: result.stderr || String(result.error || '') };
}

/** Runs a command with its output going straight to the terminal. Returns the exit code. */
function runInteractive(command, args) {
  const prepared = prepare(command, args);
  if (!prepared) die(`${command} not found on PATH`, { usageHint: false });
  const result = spawnSync(prepared.file, prepared.args, { ...prepared.options, stdio: 'inherit' });
  return result.status ?? 1;
}

/** Async variant of run(), for parallel imports. */
function runAsync(command, args) {
  const prepared = prepare(command, args);
  if (!prepared) return Promise.resolve({ code: 127, stdout: '', stderr: `${command}: command not found` });
  return new Promise((resolve) => {
    const child = spawn(prepared.file, prepared.args, { ...prepared.options, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => (stdout += chunk));
    child.stderr.on('data', (chunk) => (stderr += chunk));
    child.on('error', (error) => resolve({ code: 1, stdout, stderr: stderr + String(error) }));
    child.on('close', (code) => resolve({ code: code ?? 1, stdout, stderr }));
  });
}

function runJson(command, args) {
  const result = run(command, args);
  if (result.code !== 0) return null;
  try {
    return JSON.parse(result.stdout);
  } catch {
    return null;
  }
}

// --- arguments ---------------------------------------------------------------------------------------------------

function parseArgs(argv) {
  const opts = {
    engine: 'auto',
    installQcli: /^(true|1|yes)$/i.test(process.env.QCLI_AUTO_INSTALL || ''),
    pm: '',
    platforms: '',
    concurrency: 4,
    verify: true,
    dryRun: false,
    positional: [],
  };
  const takeValue = (flag, inline, rest) => {
    if (inline !== undefined) return inline;
    const value = rest.shift();
    if (value === undefined || value.startsWith('-')) die(`${flag} needs a value`);
    return value;
  };
  const rest = [...argv];
  while (rest.length > 0) {
    const arg = rest.shift();
    if (arg === '--') {
      opts.positional.push(...rest.splice(0));
      break;
    }
    const [flag, inline] = arg.startsWith('--') && arg.includes('=') ? [arg.slice(0, arg.indexOf('=')), arg.slice(arg.indexOf('=') + 1)] : [arg, undefined];
    switch (flag) {
      case '-h':
      case '--help':
        process.stdout.write(HELP);
        process.exit(0);
        break;
      case '-e':
      case '--engine':
        opts.engine = takeValue(flag, inline, rest);
        break;
      case '--install-qcli':
        opts.installQcli = true;
        break;
      case '--pm':
      case '--package-manager':
        opts.pm = takeValue(flag, inline, rest);
        break;
      case '-p':
      case '--platform':
        opts.platforms = takeValue(flag, inline, rest);
        break;
      case '-c':
      case '--concurrency':
        opts.concurrency = Number(takeValue(flag, inline, rest));
        break;
      case '--no-verify':
        opts.verify = false;
        break;
      case '-n':
      case '--dry-run':
        opts.dryRun = true;
        break;
      default:
        if (arg.startsWith('-')) die(`unknown option: ${arg}`);
        opts.positional.push(arg);
    }
  }
  if (!ENGINES.includes(opts.engine)) die(`unknown engine: ${opts.engine} (use ${ENGINES.join(', ')})`);
  if (opts.pm && !PACKAGE_MANAGERS.includes(opts.pm)) die(`unknown package manager: ${opts.pm} (use ${PACKAGE_MANAGERS.join(', ')})`);
  if (!Number.isInteger(opts.concurrency) || opts.concurrency < 1 || opts.concurrency > 8) die('--concurrency must be 1-8');
  if (opts.positional.length === 0) {
    process.stderr.write(HELP);
    process.exit(1);
  }
  if (opts.positional.length > 2) die('too many arguments');
  return opts;
}

// --- mirroring list ------------------------------------------------------------------------------------------------

const unquote = (value) => value.trim().replace(/^(['"])(.*)\1$/, '$2').trim();

/**
 * Reads the simple YAML shape the mirroring lists use: top-level 'key: value' pairs and an 'images:' sequence of
 * '- name: <image>' items. Other keys inside the items are ignored.
 */
function parseList(file) {
  let text;
  try {
    text = readFileSync(file, 'utf8');
  } catch {
    die(`list file not found: ${file}`);
  }
  const top = {};
  const images = [];
  let inImages = false;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.replace(/(^|\s)#.*$/, '');
    if (!line.trim()) continue;
    const topLevel = /^([A-Za-z_][\w-]*):\s*(.*)$/.exec(line);
    if (topLevel) {
      const [, key, value] = topLevel;
      inImages = key === 'images' && value.trim() === '';
      if (value.trim() !== '') top[key] = unquote(value);
      continue;
    }
    const item = inImages && /^\s*-\s+name:\s*(.+)$/.exec(line);
    if (item) images.push(unquote(item[1]));
  }
  return { top, images };
}

/** Splits 'repo:tag' (tag defaults to latest; a ':' in a registry port is not a tag separator). */
function splitImage(image) {
  const lastColon = image.lastIndexOf(':');
  if (lastColon > image.lastIndexOf('/')) return { repo: image.slice(0, lastColon), tag: image.slice(lastColon + 1) };
  return { repo: image, tag: 'latest' };
}

// --- main --------------------------------------------------------------------------------------------------------

const opts = parseArgs(process.argv.slice(2));
const [listFile, targetArg] = opts.positional;

const srcUser = process.env.SRC_USER || '';
const srcPass = process.env.SRC_PASS || '';
if (srcUser && !srcPass) die('SRC_USER is set but SRC_PASS is empty');
const haveCreds = Boolean(srcUser);

if (!which('az')) die('Azure CLI (az) not found on PATH', { usageHint: false });

const { top, images } = parseList(listFile);
const source = top.sourceRegistry;
if (!source) die(`no 'sourceRegistry:' in ${listFile}`);
let target = targetArg || top.targetRegistryName || top.targetRegistry;
if (!target) die(`no target registry given and none found in ${listFile}`);
target = target.replace(/\.azurecr\.io$/i, ''); // registry name; the login server is <name>.azurecr.io
if (images.length === 0) die(`no '- name:' entries in ${listFile}`);

// Docker Hub official images live under library/ for az acr import (docker pull adds it on its own).
const needsLibraryPrefix = (image) => source === 'docker.io' && !image.includes('/');

// --- target platforms ----------------------------------------------------------------------------------------------

function detectPlatforms() {
  if (opts.platforms) return { list: opts.platforms, from: '--platform' };
  if (which('kubectl')) {
    const result = run('kubectl', ['get', 'nodes', '-o', 'json', '--request-timeout=5s'], { timeout: 20000 });
    if (result.code === 0) {
      try {
        const nodes = JSON.parse(result.stdout).items || [];
        const found = [...new Set(nodes.map((n) => `${n.status.nodeInfo.operatingSystem}/${n.status.nodeInfo.architecture}`))].sort();
        if (found.length > 0) {
          const context = run('kubectl', ['config', 'current-context']).stdout.trim() || '?';
          return { list: found.join(','), from: `nodes of kubectl context '${context}'` };
        }
      } catch {
        // fall through to the default
      }
    }
  }
  return { list: 'linux/amd64', from: 'default (cluster not reachable)' };
}

const detected = detectPlatforms();
const platforms = detected.list.split(',').map((p) => p.trim()).filter(Boolean);
for (const p of platforms) {
  if (!/^[a-z0-9]+\/[a-z0-9]+(\/v[0-9]+)?$/.test(p)) die(`invalid platform '${p}' (expected os/arch, e.g. linux/amd64)`);
}
const amd64Only = platforms.length === 1 && platforms[0] === 'linux/amd64';

// --- qcli: find or install -----------------------------------------------------------------------------------------

const qcliVersion = () => /\/(\d+\.\d+\.\d+)/.exec(run('qcli', ['--version']).stdout)?.[1] || '';
const isYarn1 = () => run('yarn', ['--version']).stdout.trim().startsWith('1.');

function detectPackageManager() {
  if (opts.pm) return opts.pm;
  // The package manager that launched this script (e.g. "pnpm dlx", "yarn node") reports itself here.
  const launcher = /^(pnpm|yarn|npm)\//.exec(process.env.npm_config_user_agent || '')?.[1];
  if (launcher && which(launcher) && (launcher !== 'yarn' || isYarn1())) return launcher;
  // pnpm first: when Node itself is managed by pnpm (pnpm env), npm -g installs into pnpm's store.
  if (which('pnpm')) return 'pnpm';
  if (which('yarn') && isYarn1()) return 'yarn'; // yarn 2+ (berry) has no global installs
  if (which('npm')) return 'npm';
  return '';
}

function checkPackageManager(pm) {
  if (!pm) die('qcli not found and no package manager to install it (need pnpm, yarn 1 or npm)', { usageHint: false });
  if (!which(pm)) die(`qcli not found and package manager '${pm}' is not installed`, { usageHint: false });
  if (pm === 'yarn' && !isYarn1()) die('yarn 2+ has no global installs; use --package-manager pnpm or npm', { usageHint: false });
}

function globalBinDir(pm) {
  if (pm === 'pnpm') return run('pnpm', ['bin', '-g']).stdout.trim();
  if (pm === 'yarn') return run('yarn', ['global', 'bin']).stdout.trim();
  const prefix = run('npm', ['prefix', '-g']).stdout.trim();
  return prefix && (IS_WIN ? prefix : path.join(prefix, 'bin'));
}

function installQcli() {
  const pm = detectPackageManager();
  checkPackageManager(pm);
  const spec = `${QCLI_PACKAGE}@${QCLI_VERSION}`;
  const args = { pnpm: ['add', '-g', spec], yarn: ['global', 'add', spec], npm: ['install', '-g', spec] }[pm];
  info(`Installing ${spec} with ${pm} ...`);
  if (runInteractive(pm, args) !== 0) {
    const hints = {
      pnpm: "if pnpm reports no global bin directory, run 'pnpm setup' and open a new terminal",
      yarn: 'check the yarn output above',
      npm: 'on EACCES, use a user prefix: npm config set prefix ~/.npm-global',
    };
    die(`${pm} could not install qcli (${hints[pm]})`, { usageHint: false });
  }
  if (!which('qcli')) {
    const dir = globalBinDir(pm);
    if (dir) {
      process.env.PATH = `${dir}${path.delimiter}${process.env.PATH || ''}`;
      if (which('qcli')) warn(`qcli was installed to ${dir}, which is not on your PATH. Add it to your shell profile.`);
    }
  }
  if (!which('qcli')) die('qcli was installed but cannot be found on PATH', { usageHint: false });
  info(`Installed qcli ${qcliVersion()}`);
}

async function askYesNo(question) {
  if (!process.stdin.isTTY || !process.stdout.isTTY) return false;
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  try {
    return /^y/i.test((await rl.question(`${question} [y/N] `)).trim());
  } finally {
    rl.close();
  }
}

/** Makes sure qcli is available. Returns false (without exiting) when it is missing and not required. */
async function ensureQcli(required) {
  if (which('qcli')) {
    const version = qcliVersion();
    if (version && version !== QCLI_VERSION) warn(`qcli ${version} is installed; the workflows use ${QCLI_VERSION}`);
    return true;
  }
  if (opts.dryRun) {
    if (opts.installQcli) {
      const pm = detectPackageManager();
      checkPackageManager(pm);
      info(`(dry run) would install ${QCLI_PACKAGE}@${QCLI_VERSION} with ${pm}`);
      return true;
    }
    if (required) die('qcli not found (add --install-qcli to install it)');
    return false;
  }
  if (opts.installQcli) {
    installQcli();
    return true;
  }
  if (required && (await askYesNo(`qcli is not installed. Install ${QCLI_PACKAGE}@${QCLI_VERSION} with ${detectPackageManager() || '?'}?`))) {
    installQcli();
    return true;
  }
  if (required) die('qcli not found (add --install-qcli, or use --engine az)');
  return false;
}

const dockerReady = () => which('docker') !== null && run('docker', ['info'], { timeout: 20000 }).code === 0;

// qcli az acr import splices the credentials into a shell command line, so they must not contain shell syntax.
const credsShellSafe = () => /^[A-Za-z0-9._@+/=~-]+$/.test(srcUser) && /^[A-Za-z0-9._@+/=~-]+$/.test(srcPass);

// --- choose the engine ---------------------------------------------------------------------------------------------

let engine = opts.engine;
let engineReason = 'requested';
if (engine === 'auto') {
  if (haveCreds && credsShellSafe() && (await ensureQcli(false))) {
    engine = 'qcli-import';
    engineReason = 'source credentials set';
  } else if (!haveCreds && amd64Only && dockerReady() && (await ensureQcli(false))) {
    engine = 'qcli-mirror';
    engineReason = 'Docker is running and all target platforms are linux/amd64';
  } else {
    engine = 'az';
    if (haveCreds && !credsShellSafe()) engineReason = 'credentials contain characters qcli cannot pass safely';
    else if (!which('qcli')) engineReason = 'qcli not installed (add --install-qcli to use it)';
    else if (!haveCreds && !amd64Only) engineReason = `qcli-mirror copies only linux/amd64, but ${platforms.join(',')} is needed`;
    else if (!haveCreds) engineReason = 'no source credentials for qcli-import and Docker is not running for qcli-mirror';
    else engineReason = 'fallback';
  }
} else if (engine === 'qcli-import') {
  if (!haveCreds) die('qcli-import needs SRC_USER and SRC_PASS (qcli requires source credentials); use --engine az for public sources');
  if (!credsShellSafe()) die('SRC_USER/SRC_PASS contain characters that qcli would pass unquoted to a shell; use --engine az');
  await ensureQcli(true);
} else if (engine === 'qcli-mirror') {
  if (!amd64Only) die(`qcli-mirror copies only linux/amd64 (qcli ${QCLI_VERSION}), but the target needs ${platforms.join(',')}; use --engine qcli-import or az`);
  if (!opts.dryRun && !dockerReady()) die('qcli-mirror needs a running Docker daemon');
  await ensureQcli(true);
}

info(`Mirroring ${listFile}: ${source} => ${target}.azurecr.io`);
info(`Engine:    ${engine} (${engineReason})`);
info(`Platforms: ${platforms.join(',')} (${detected.from})`);

// --- skip images that already exist ------------------------------------------------------------------------------

const repositories = runJson('az', ['acr', 'repository', 'list', '--name', target, '-o', 'json']);
if (!Array.isArray(repositories)) {
  die(`cannot list repositories in ${target} (check 'az login' and that you have access to the registry)`, { usageHint: false });
}
const repositorySet = new Set(repositories);
const tagCache = new Map();
function imageExists(image) {
  const { repo, tag } = splitImage(image);
  if (!repositorySet.has(repo)) return false;
  if (!tagCache.has(repo)) {
    const tags = runJson('az', ['acr', 'repository', 'show-tags', '--name', target, '--repository', repo, '-o', 'json']);
    tagCache.set(repo, new Set(Array.isArray(tags) ? tags : []));
  }
  return tagCache.get(repo).has(tag);
}

const missing = [];
for (const image of images) {
  if (imageExists(image)) {
    info(`   exists:  ${image}`);
  } else {
    missing.push(image);
    info(`   missing: ${image}`);
  }
}
info(`${missing.length} of ${images.length} image(s) to copy`);

if (opts.dryRun) {
  info('(dry run) nothing copied');
  process.exit(0);
}

// --- copy --------------------------------------------------------------------------------------------------------

const workDir = mkdtempSync(path.join(tmpdir(), 'mirror-registry-'));
process.on('exit', () => rmSync(workDir, { recursive: true, force: true }));

async function azImport(image) {
  const sourceImage = needsLibraryPrefix(image) ? `library/${image}` : image;
  const args = ['acr', 'import', '--name', target, '--source', `${source}/${sourceImage}`, '--image', image];
  if (haveCreds) args.push('--username', srcUser, '--password', srcPass);
  const result = await runAsync('az', args);
  const output = `${result.stdout}${result.stderr}`;
  if (result.code === 0) return { image, ok: true, note: 'copied' };
  if (/already exists/i.test(output)) return { image, ok: true, note: 'already there, skipped' };
  return { image, ok: false, note: output.trim() };
}

async function azImportAll(list) {
  const queue = [...list];
  const failures = [];
  const worker = async () => {
    while (queue.length > 0) {
      const image = queue.shift();
      info(`-> ${source}/${needsLibraryPrefix(image) ? `library/${image}` : image}  =>  ${target}/${image}`);
      const result = await azImport(image);
      info(`   ${result.ok ? result.note : 'FAILED'}: ${image}`);
      if (!result.ok) failures.push(result);
    }
  };
  await Promise.all(Array.from({ length: Math.min(opts.concurrency, list.length) }, worker));
  if (failures.length > 0) {
    for (const f of failures) console.error(`\n${f.image}:\n${f.note}`);
    die(`${failures.length} image(s) failed to import`, { usageHint: false });
  }
}

function writeList(file, targetKey, targetValue, list) {
  const lines = [`sourceRegistry: "${source}"`, `${targetKey}: "${targetValue}"`, 'images:', ...list.map((i) => `  - name: "${i}"`)];
  writeFileSync(file, `${lines.join('\n')}\n`);
}

if (missing.length > 0) {
  if (engine === 'az') {
    await azImportAll(missing);
  } else if (engine === 'qcli-import') {
    // qcli uses the same name for source and target, so Docker Hub official images (library/...) go through az.
    const viaAz = missing.filter(needsLibraryPrefix);
    const viaQcli = missing.filter((i) => !needsLibraryPrefix(i));
    if (viaAz.length > 0) await azImportAll(viaAz);
    if (viaQcli.length > 0) {
      const file = path.join(workDir, 'list.yaml');
      writeList(file, 'targetRegistryName', target, viaQcli);
      warn('qcli passes the source password on the az command line; it can show up in process listings');
      if (runInteractive('qcli', ['az', 'acr', 'import', '-f', file, '-u', srcUser, '-p', srcPass]) !== 0) {
        die('qcli az acr import failed', { usageHint: false });
      }
    }
  } else if (engine === 'qcli-mirror') {
    if (run('az', ['acr', 'login', '--name', target]).code !== 0) die(`az acr login --name ${target} failed`, { usageHint: false });
    if (haveCreds) {
      const login = run('docker', ['login', source, '--username', srcUser, '--password-stdin'], { input: srcPass });
      if (login.code !== 0) die(`docker login ${source} failed: ${login.stderr.trim()}`, { usageHint: false });
    }
    const file = path.join(workDir, 'list.yaml');
    writeList(file, 'targetRegistry', `${target}.azurecr.io`, missing);
    if (runInteractive('qcli', ['mirror', 'images', '-f', file]) !== 0) die('qcli mirror images failed', { usageHint: false });
  }
}

// --- verify architectures --------------------------------------------------------------------------------------------

if (!opts.verify) {
  info('Done (verification skipped)');
  process.exit(0);
}

/** Returns the platforms (os/arch[/variant]) of an image in the target, [] if unknown, or null if it is missing. */
function imagePlatforms(image) {
  const manifest = runJson('az', ['acr', 'manifest', 'show', '--registry', target, '--name', image, '-o', 'json']);
  if (!manifest) return null;
  if (Array.isArray(manifest.manifests)) {
    // Multi-platform index / manifest list
    const found = manifest.manifests
      .map((m) => m.platform)
      .filter((p) => p && p.architecture && p.architecture !== 'unknown')
      .map((p) => `${p.os}/${p.architecture}${p.variant ? `/${p.variant}` : ''}`);
    return [...new Set(found)].sort();
  }
  // Single-platform image: ACR keeps the architecture in the manifest metadata.
  const metadata = runJson('az', ['acr', 'manifest', 'show-metadata', '--registry', target, '--name', image, '-o', 'json']);
  return metadata && metadata.os && metadata.architecture ? [`${metadata.os}/${metadata.architecture}`] : [];
}

const supports = (have, wanted) => have.some((h) => h === wanted || h.startsWith(`${wanted}/`)); // linux/arm64 ~ linux/arm64/v8

info(`Checking platforms (${platforms.join(',')}):`);
let failed = 0;
let unknown = 0;
for (const image of images) {
  const have = imagePlatforms(image);
  if (have === null) {
    info(`   MISSING  ${image} (not in ${target})`);
    failed += 1;
  } else if (have.length === 0) {
    info(`   ?        ${image} (single-platform image; architecture not reported)`);
    unknown += 1;
  } else {
    const lacking = platforms.filter((p) => !supports(have, p));
    if (lacking.length > 0) {
      info(`   LACKS    ${image}: has ${have.join(',')}, missing ${lacking.join(',')}`);
      failed += 1;
    } else {
      info(`   ok       ${image} (${have.join(',')})`);
    }
  }
}

if (failed > 0) {
  console.error(
    `Error: ${failed} image(s) are missing or lack a required platform. Pods on those nodes will fail with\n` +
      "'exec format error' or 'no matching manifest'. Use an import engine (az or qcli-import) to copy every\n" +
      'architecture, or pick image tags that publish the needed platforms.',
  );
  process.exit(2);
}
if (unknown > 0) warn(`${unknown} image(s) could not be checked; make sure they match ${platforms.join(',')}`);
info('Done');
