// Pure part of the harness-workers mod: parse `harness status --json --all`, pick and order the
// workers to show, format collapsed/expanded lines, decide notifications from two snapshots.
// No `$` access here, so it is unit-testable (tests/model.test.ts).
import type { Snapshot, Step, Worker, WorkerState } from '../types'

export const SUPPORTED_VERSION = 1
export const LINGER_S = 60 // a finished worker stays in the band this long

export type Color = 'green' | 'red' | 'yellow'
export type Line = { text: string; color?: Color; dim?: boolean }
export type Layout = { lines: Line[]; hidden: number }
export type ExitEvent = { key: string; text: string; notify: boolean }

// ---------- text helpers ----------

/**
 * One line of plain text: whole escape sequences (CSI `ESC [ … final`, OSC `ESC ] … BEL|ESC \`, and
 * two-byte `ESC x`) are dropped, then any other control character (newline, tab) becomes a space.
 */
export function clean(s: string): string {
  return s
    .replace(/\u001b\[[0-?]*[ -/]*[@-~]/g, '')
    .replace(/\u001b\][^\u0007\u001b]*(?:\u0007|\u001b\\)?/g, '')
    .replace(/\u001b[@-Z\\-_]/g, '')
    .replace(/[\u0000-\u001f\u007f-\u009f]+/g, ' ')
    .trim()
}

function cellWidth(cp: number): number {
  if (cp === 0 || (cp >= 0x200b && cp <= 0x200f) || (cp >= 0x300 && cp <= 0x36f) || (cp >= 0xfe00 && cp <= 0xfe0f)) return 0
  if (
    (cp >= 0x1100 && cp <= 0x115f) ||
    (cp >= 0x2e80 && cp <= 0xa4cf) ||
    (cp >= 0xac00 && cp <= 0xd7a3) ||
    (cp >= 0xf900 && cp <= 0xfaff) ||
    (cp >= 0xfe30 && cp <= 0xfe6f) ||
    (cp >= 0xff00 && cp <= 0xff60) ||
    (cp >= 0xffe0 && cp <= 0xffe6) ||
    (cp >= 0x1f300 && cp <= 0x1faff) ||
    (cp >= 0x20000 && cp <= 0x3fffd)
  )
    return 2
  return 1
}

/** Terminal cells the text takes (wide Korean/CJK characters count 2). */
export function width(s: string): number {
  let w = 0
  for (const ch of s) w += cellWidth(ch.codePointAt(0) as number)
  return w
}

/** Cut to at most `cols` cells, ending in `…` when something was cut. */
export function truncate(s: string, cols: number): string {
  if (cols <= 0) return ''
  if (width(s) <= cols) return s
  let out = ''
  let w = 0
  for (const ch of s) {
    const cw = cellWidth(ch.codePointAt(0) as number)
    if (w + cw > cols - 1) break
    out += ch
    w += cw
  }
  return out + '…'
}

export function formatDuration(s: number): string {
  const t = Math.max(0, Math.floor(s))
  const pad = (n: number) => String(n).padStart(2, '0')
  if (t < 60) return `${t}s`
  if (t < 3600) return `${Math.floor(t / 60)}m${pad(t % 60)}s`
  return `${Math.floor(t / 3600)}h${pad(Math.floor((t % 3600) / 60))}m`
}

function formatCtx(n: number): string {
  return n >= 1000 ? `${Math.round(n / 1000)}k` : String(n)
}

// ---------- parsing ----------

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null)
const str = (v: unknown): string | null => (typeof v === 'string' ? v : null)

function baseName(p: string): string {
  const parts = p.split('/').filter(Boolean)
  return parts[parts.length - 1] ?? p
}

/** A string field made one clean line; null when it is absent, not a string, or empty after cleaning. */
function cleanOrNull(v: unknown): string | null {
  const t = str(v)
  const c = t === null ? '' : clean(t)
  return c === '' ? null : c
}

function parseWorker(raw: unknown, folder: string, path: string): Worker | null {
  if (!isObj(raw)) return null
  const role = str(raw.role)
  const state = str(raw.state)
  if (role === null || (state !== 'running' && state !== 'exited' && state !== 'dead')) return null
  const steps: Step[] = []
  if (Array.isArray(raw.steps)) {
    for (const s of raw.steps) {
      if (isObj(s) && num(s.n) !== null && str(s.text) !== null) steps.push({ n: s.n as number, text: clean(s.text as string), ko: cleanOrNull(s.ko) })
    }
  }
  const step = num(raw.step)
  const exit = isObj(raw.exit) ? raw.exit : null
  const now = str(raw.now)
  return {
    key: `${path}|${role}`,
    role,
    state: state as WorkerState,
    folder,
    askId: str(raw.ask_id),
    startedAt: num(raw.started_at),
    elapsedS: num(raw.elapsed_s),
    turns: num(raw.turns),
    ctx: num(raw.ctx),
    now: now === null || clean(now) === '' ? null : clean(now),
    titleKo: cleanOrNull(raw.title_ko),
    steps,
    step: step !== null && steps.some(s => s.n === step) ? step : null, // a step the list lacks is unknown, not certain
    verify: str(raw.verify),
    rc: exit ? num(exit.rc) : null,
    verdict: exit ? str(exit.verdict) : null,
    durationS: exit ? num(exit.duration_s) : null,
  }
}

/** Parse the output of `harness status --json --all`; a reason when it cannot be shown. */
export function parseStatus(raw: string): Snapshot {
  let doc: unknown
  try {
    doc = JSON.parse(raw)
  } catch {
    return { ok: false, reason: 'harness status printed unparsable output' }
  }
  if (!isObj(doc)) return { ok: false, reason: 'harness status printed unparsable output' }
  if (doc.version !== SUPPORTED_VERSION) {
    const v = typeof doc.version === 'number' || typeof doc.version === 'string' ? String(doc.version) : '?'
    return { ok: false, reason: `status format v${clean(v).slice(0, 12)} is not supported` }
  }
  if (!Array.isArray(doc.folders)) return { ok: false, reason: 'harness status printed no folders list' }
  const workers: Worker[] = []
  for (const f of doc.folders) {
    if (!isObj(f) || !Array.isArray(f.workers)) continue
    const path = str(f.path) ?? '?'
    const lane = num(f.lane)
    const branch = str(f.branch)
    const folder = lane !== null ? `#${lane}` : f.primary === true ? 'main' : clean(branch ?? baseName(path))
    for (const w of f.workers) {
      const one = parseWorker(w, folder, path)
      if (one) workers.push(one)
    }
  }
  return { ok: true, workers, generatedAt: num(doc.generated_at) }
}

export function anyRunning(s: Snapshot | null): boolean {
  return s !== null && s.ok && s.workers.some(w => w.state === 'running')
}

// ---------- which workers, in which order ----------

/** Epoch second at which a stopped worker finished: the document's own, else when a poll saw it stop. */
export function finishedAt(w: Worker, deadAt: Record<string, number>): number | null {
  if (w.state === 'exited' && w.startedAt !== null && w.durationS !== null) return w.startedAt + w.durationS
  return deadAt[w.key] ?? null
}

/** Running workers (oldest first), then workers that finished within LINGER_S (latest first). */
export function selectWorkers(s: { workers: Worker[] }, nowS: number, deadAt: Record<string, number>): Worker[] {
  const running = s.workers.filter(w => w.state === 'running').sort((a, b) => (a.startedAt ?? 0) - (b.startedAt ?? 0) || a.key.localeCompare(b.key))
  const done: { w: Worker; at: number }[] = []
  for (const w of s.workers) {
    if (w.state === 'running') continue
    const at = finishedAt(w, deadAt)
    if (at !== null && nowS - at <= LINGER_S) done.push({ w, at })
  }
  done.sort((a, b) => b.at - a.at || a.w.key.localeCompare(b.w.key))
  return [...running, ...done.map(d => d.w)]
}

// ---------- notifications ----------

function elapsedOf(w: Worker, nowS: number): number | null {
  if (w.state === 'running') return w.startedAt !== null ? nowS - w.startedAt : w.elapsedS
  return w.durationS ?? w.elapsedS
}

function exitText(w: Worker): string {
  if (w.state === 'dead') return 'dead'
  return w.rc === null ? 'exited' : `exit ${w.rc}`
}

/**
 * Compare two consecutive snapshots. An event is a worker that was running in `prev` and has
 * stopped in `next` (same ask). A worker that vanished, or whose ask was replaced, gives none.
 * `deadAt` gets the stop time of each such worker so its row can linger.
 */
export function diffSnapshots(prev: Snapshot | null, next: Snapshot, nowS: number): { events: ExitEvent[]; deadAt: Record<string, number> } {
  const events: ExitEvent[] = []
  const deadAt: Record<string, number> = {}
  if (prev === null || !prev.ok || !next.ok) return { events, deadAt }
  const before = new Map<string, Worker>()
  for (const w of prev.workers) before.set(w.key, w)
  for (const w of next.workers) {
    const p = before.get(w.key)
    if (!p || p.state !== 'running' || w.state === 'running' || p.askId !== w.askId) continue
    deadAt[w.key] = nowS
    const parts = [`harness: ${w.role} ${w.folder} ${exitText(w)}`]
    if (w.verify === 'pass' || w.verify === 'fail') parts.push(`verify ${w.verify}`)
    if (w.verdict) parts.push(w.verdict)
    const dur = w.durationS ?? (p.startedAt !== null ? nowS - p.startedAt : null)
    if (dur !== null) parts.push(formatDuration(dur))
    const failed = w.state === 'dead' || (w.rc !== null && w.rc !== 0) || w.verify === 'fail'
    events.push({ key: w.key, text: parts.join(' · '), notify: failed })
  }
  return { events, deadAt }
}

// ---------- lines ----------

// One worker's lines. `head`: the header. `top`: the 지시 line. `cur`: the current step line (or the lone
// `→ now` line when no step is known). `act`: the action line under the current step. `steps`: every step in
// order with its distance from the current one. Tier order when rows are short: head, cur, top, act, other steps.
type Block = { head: Line; top: Line[]; cur: Line | null; act: Line | null; steps: { n: number; line: Line; dist: number; cur: boolean }[] }

const stepName = (s: Step): string => s.ko ?? s.text

function glyphOf(w: Worker): { g: string; color: Color } {
  if (w.state === 'running') return { g: '●', color: 'yellow' }
  const ok = w.state === 'exited' && w.rc === 0
  return ok ? { g: '✓', color: 'green' } : { g: '✗', color: 'red' }
}

function finishedParts(w: Worker): string[] {
  const parts = [exitText(w)]
  if (w.verify) parts.push(`verify ${w.verify}`)
  if (w.verdict) parts.push(w.verdict)
  return parts
}

/** Middle part of a collapsed row: `<step>/<n> <text>`, else `→ <now>`, else nothing. */
function middle(w: Worker): string {
  if (w.step !== null) {
    const s = w.steps.find(x => x.n === w.step)
    if (s) return `${w.step}/${w.steps.length} ${stepName(s)}`
  }
  return w.now ? `→ ${w.now}` : ''
}

// Narrow-terminal rules. A head line is built in the fixed order symbol, role, folder tag, elapsed, then the
// step (or action), or the finished parts; expanded: then turns, then ctx. When a line does not fit,
// the least important part goes first: compact form (short role, one space between fields), then
// ctx, turns, the folder tag (a `#N` tag stays), and last the end of the line is cut with `…`.
export const SHORT_ROLE: Record<string, string> = { implementer: 'impl', analyst: 'anl', reviewer: 'rev' }
export const NARROW_COLS = 60 // below this the action line under a step is indented 2, else ACTION_INDENT
export const ACTION_INDENT = 6
export const NARROW_ACTION_INDENT = 2

type Pad = { role: number; folder: number; compact: boolean }

type Fields = { g: string; role: string; folder: string; elapsed: string | null; mid: string[]; turns: string | null; ctx: string | null }

function fieldsOf(w: Worker, nowS: number, expanded: boolean): Fields {
  const dur = elapsedOf(w, nowS)
  const f: Fields = { g: glyphOf(w).g, role: w.role, folder: w.folder, elapsed: dur === null ? null : formatDuration(dur), mid: [], turns: null, ctx: null }
  if (w.state !== 'running') f.mid = finishedParts(w)
  else if (!expanded) f.mid = middle(w) ? [middle(w)] : []
  if (expanded) {
    if (w.turns !== null) f.turns = `${w.turns} turns`
    if (w.ctx !== null) f.ctx = `ctx ${formatCtx(w.ctx)}`
  }
  return f
}

function joinFields(f: Fields, pad: Pad, o: { ctx: boolean; turns: boolean; folder: boolean }): string {
  const parts = [f.elapsed, ...f.mid, o.turns ? f.turns : null, o.ctx ? f.ctx : null].filter((x): x is string => x !== null)
  if (pad.compact) return [f.g, SHORT_ROLE[f.role] ?? f.role, o.folder ? f.folder : null, ...parts].filter(x => x !== null && x !== '').join(' ')
  return `${f.g} ${f.role.padEnd(pad.role)} ${f.folder.padEnd(pad.folder)}  ${parts.join(' · ')}`.trimEnd()
}

/** The head line of one worker: the first of the shrinking forms that fits `cols`, else the last cut with `…`. */
function headText(w: Worker, nowS: number, expanded: boolean, pad: Pad, cols: number): string {
  const f = fieldsOf(w, nowS, expanded)
  const keepFolder = /^#\d+$/.test(f.folder) // `main` and any other tag go before elapsed is cut
  const forms = [{ ctx: true, turns: true, folder: true }]
  if (pad.compact) forms.push({ ctx: false, turns: true, folder: true }, { ctx: false, turns: false, folder: true }, { ctx: false, turns: false, folder: keepFolder })
  let line = ''
  for (const o of forms) {
    line = joinFields(f, pad, o)
    if (width(line) <= cols) return line
  }
  return truncate(line, cols)
}

function buildBlock(w: Worker, nowS: number, expanded: boolean, pad: Pad, cols: number): Block {
  const { color } = glyphOf(w)
  const head: Line = { text: headText(w, nowS, expanded, pad, cols), color: w.state === 'running' ? undefined : color }
  const block: Block = { head, top: [], cur: null, act: null, steps: [] }
  if (!expanded || w.state !== 'running') return block
  if (w.titleKo) block.top.push({ text: truncate(`  지시: ${w.titleKo}`, cols) })
  const cur = w.step !== null ? w.steps.find(s => s.n === w.step) : undefined
  if (!cur) {
    if (w.now) block.cur = { text: truncate(`  → ${w.now}`, cols), dim: true }
    return block
  }
  for (const s of w.steps) {
    const sym = s.n < cur.n ? '✓' : s.n === cur.n ? '▸' : '·'
    const line: Line = { text: truncate(`  ${sym} ${s.n} ${stepName(s)}`, cols), color: s.n < cur.n ? 'green' : undefined, dim: s.n > cur.n }
    if (s.n === cur.n) {
      block.cur = line
      if (w.now) block.act = { text: truncate(`${' '.repeat(cols < NARROW_COLS ? NARROW_ACTION_INDENT : ACTION_INDENT)}→ ${w.now}`, cols), dim: true }
    }
    block.steps.push({ n: s.n, line, dist: Math.abs(s.n - cur.n), cur: s.n === cur.n })
  }
  return block
}

/** Every line of a block in display order. */
function allLines(b: Block): Line[] {
  if (b.steps.length === 0) return [b.head, ...b.top, ...(b.cur ? [b.cur] : [])]
  return [b.head, ...b.top, ...b.steps.flatMap(s => (s.cur && b.act ? [s.line, b.act] : [s.line]))]
}

/**
 * The lines to draw for `workers` (already ordered by selectWorkers) in at most `maxRows` rows.
 * When rows are short they go by priority, each tier round-robin over the workers: header, current step
 * (or the lone action line), 지시, action line, then the other steps nearest the current one first.
 * If the headers do not all fit, the last row is `+N more`. Exception: with maxRows 1 only the first header
 * is drawn and there is no `+N more` row.
 */
export function layout(workers: Worker[], o: { expanded: boolean; maxRows: number; columns: number; nowS: number }): Layout {
  const cols = Math.max(10, o.columns)
  const wide: Pad = { role: Math.max(0, ...workers.map(w => w.role.length)), folder: Math.max(0, ...workers.map(w => width(w.folder))), compact: false }
  // the aligned form only when every head fits whole; else all heads use the compact form
  const fits = workers.every(w => width(headText(w, o.nowS, o.expanded, wide, Infinity)) <= cols)
  const pad: Pad = fits ? wide : { ...wide, compact: true }
  const blocks = workers.map(w => buildBlock(w, o.nowS, o.expanded, pad, cols))
  if (o.maxRows <= 0 || blocks.length === 0) return { lines: [], hidden: blocks.length }
  if (blocks.reduce((n, b) => n + allLines(b).length, 0) <= o.maxRows) return { lines: blocks.flatMap(allLines), hidden: 0 }
  // Which workers: all when every header fits, else as many headers as fit beside the `+N more` row (at least one).
  const k = blocks.length <= o.maxRows ? blocks.length : Math.max(1, o.maxRows - 1)
  const shown = blocks.slice(0, k)
  const hidden = blocks.length - k
  let budget = o.maxRows - k - (hidden > 0 && o.maxRows >= 2 ? 1 : 0)
  // Tiers 2-4, then the other steps: a Set of kept lines per worker.
  const keep = shown.map(() => new Set<Line>())
  const take = (i: number, l: Line | null | undefined) => {
    if (l && budget > 0) {
      keep[i]?.add(l)
      budget--
    }
  }
  shown.forEach((b, i) => take(i, b.cur))
  shown.forEach((b, i) => b.top.forEach(l => take(i, l)))
  shown.forEach((b, i) => take(i, b.act))
  const rest = shown.map(b => b.steps.filter(s => !s.cur).sort((a, c) => a.dist - c.dist || a.n - c.n))
  for (let round = 0; budget > 0; round++) {
    const before = budget
    shown.forEach((_, i) => take(i, rest[i]?.[round]?.line))
    if (budget === before) break
  }
  const lines: Line[] = shown.flatMap((b, i) => allLines(b).filter(l => l === b.head || keep[i]?.has(l)))
  // With a worker hidden and maxRows >= 2 the last row is `+N more`; with maxRows 1 only the first header.
  if (hidden > 0 && o.maxRows >= 2) lines.push({ text: truncate(`  +${hidden} more`, cols), dim: true })
  if (lines.length > o.maxRows) lines.length = o.maxRows
  return { lines, hidden }
}

export function failureLine(reason: string, columns: number): Line {
  return { text: truncate(`harness-workers: ${clean(reason)}`, Math.max(10, columns)), dim: true }
}

// ---------- the poll loop's decisions (kept pure: register.tsx only calls these) ----------

export const KEEP_DEAD_S = 300 // how long a dead worker's stop time is remembered

/**
 * What the loop does when `session.end` fires, by `SessionEndReason` (types of Claude Code 2.1.332:
 * `'clear' | 'resume' | 'logout' | 'prompt_input_exit' | 'other'`):
 * - `retire`: the process ends (`prompt_input_exit` /exit, ctrl+c; `logout`; `other` -p finish or a signal).
 * - `continue`: the process goes on under a new session id and no `session.start` fires (`clear`, `resume`),
 *   so the loop keeps running and its state stays: `expanded` survives, and the snapshot and `deadAt`
 *   survive so an old exit is not toasted again.
 * An unknown future reason continues: a timer of a process that is ending dies with it anyway.
 */
export function sessionEndAction(reason: string): 'retire' | 'continue' {
  return reason === 'prompt_input_exit' || reason === 'logout' || reason === 'other' ? 'retire' : 'continue'
}

/** The snapshot of one finished `harness status` run: the process result, or a reason string. */
export function snapshotOf(out: { exitCode: number; stdout: string } | string): Snapshot {
  if (typeof out === 'string') return { ok: false, reason: out }
  if (out.exitCode !== 0) return { ok: false, reason: `harness status failed (rc ${out.exitCode})` }
  return parseStatus(out.stdout)
}

/** The snapshot for a stage of the poll that threw: shown as the dim `harness-workers: <reason>` row. */
export function failureSnapshot(stage: string, err: unknown): Snapshot {
  const msg = err instanceof Error ? err.message : String(err)
  return { ok: false, reason: `${stage} failed${msg ? `: ${msg}` : ''}` }
}

/** `deadAt` after a poll: the old times, the new ones, minus those older than KEEP_DEAD_S. */
export function mergeDeadAt(old: Record<string, number>, fresh: Record<string, number>, nowS: number): Record<string, number> {
  const merged = { ...old, ...fresh }
  for (const k of Object.keys(merged)) if (nowS - merged[k]! > KEEP_DEAD_S) delete merged[k]
  return merged
}

/**
 * The harness root for a session cwd: the nearest dir at or above `cwd` with `.harness/asks`, searched
 * up to the dir holding `.git` inclusive; outside git only `cwd` counts. Same search as lib/harness-root.sh
 * with two differences: it walks the logical cwd (the shell version resolves `pwd -P` first, so a symlinked
 * cwd can find a different root) and `exists` only checks existence (the shell version tests `-d`).
 * `$.fs.stat(path, { resolve: true })` could close both, but costs a call per level; not used.
 * `exists` is the host's `$.fs.exists`. The walk is bounded and stops at the filesystem root.
 */
export async function findHarnessRoot(cwd: string, exists: (path: string) => Promise<boolean>, maxDepth = 64): Promise<string | null> {
  if (!cwd.startsWith('/')) return null
  const parts = cwd.split('/').filter(Boolean)
  let hit: string | null = null
  for (let i = 0; i <= Math.min(parts.length, maxDepth); i++) {
    const d = '/' + parts.slice(0, parts.length - i).join('/')
    const dir = d === '//' ? '/' : d
    const base = dir === '/' ? '' : dir
    if (hit === null && (await exists(`${base}/.harness/asks`))) hit = dir
    if (await exists(`${base}/.git`)) return hit
  }
  return (await exists(`${cwd.replace(/\/+$/, '')}/.harness/asks`)) ? cwd : null
}
