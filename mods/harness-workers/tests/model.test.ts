import { expect, test } from 'claude-code/testing'

import type { Snapshot, Worker } from '../types'
import { anyRunning, diffSnapshots, failureLine, layout, parseStatus, selectWorkers, truncate, width } from '../hooks/model'

const NOW = 10_000

function w(over: Partial<Worker> = {}): Worker {
  return {
    key: '/p|implementer',
    role: 'implementer',
    state: 'running',
    folder: '#305',
    askId: 'a1',
    startedAt: NOW - 252,
    elapsedS: 252,
    turns: 23,
    ctx: 61000,
    now: null,
    steps: [],
    step: null,
    verify: null,
    rc: null,
    verdict: null,
    durationS: null,
    ...over,
  }
}
const STEPS = ['Read AGENTS.md', 'Add failing tests', 'Implement', 'Run the full tests'].map((text, i) => ({ n: i + 1, text }))
const snap = (...workers: Worker[]): Snapshot => ({ ok: true, workers, generatedAt: NOW })
const okSnap = (...workers: Worker[]) => snap(...workers) as Extract<Snapshot, { ok: true }>
const texts = (workers: Worker[], o: { expanded: boolean; maxRows: number; columns?: number }) => layout(workers, { columns: 100, nowS: NOW, ...o }).lines.map(l => l.text)

function doc(workers: unknown[], extra: Record<string, unknown> = {}): string {
  return JSON.stringify({ version: 1, generated_at: NOW, folders: [{ path: '/p', primary: true, lane: null, branch: 'main', workers }], ...extra })
}

test('parse: lane, main and other folder labels', () => {
  const one = { role: 'analyst', state: 'running' }
  const s = parseStatus(
    JSON.stringify({
      version: 1,
      folders: [
        { path: '/r', primary: true, lane: null, branch: 'main', workers: [one] },
        { path: '/r-305', primary: false, lane: 305, branch: 'feat/x', workers: [one] },
        { path: '/r-other', primary: false, lane: null, branch: 'topic', workers: [one] },
        { path: '/r-nobranch', primary: false, lane: null, branch: null, workers: [one] },
      ],
    }),
  )
  expect(s.ok && s.workers.map(x => x.folder)).toEqual(['main', '#305', 'topic', 'r-nobranch'])
})

test('parse: unsupported version, bad json, failures keep a reason', () => {
  expect(parseStatus(doc([], { version: 2 }))).toEqual({ ok: false, reason: 'status format v2 is not supported' })
  expect(parseStatus('not json')).toEqual({ ok: false, reason: 'harness status printed unparsable output' })
  expect(parseStatus('[]').ok).toBe(false)
  expect(parseStatus('{"version":1}').ok).toBe(false)
})

test('parse: unknown fields ignored, missing optional fields are null', () => {
  const s = parseStatus(doc([{ role: 'analyst', state: 'running', future_field: { a: 1 } }]))
  expect(s.ok && s.workers[0]).toMatchObject({ role: 'analyst', now: null, step: null, steps: [], turns: null, rc: null, verify: null })
  // a worker with an unknown state or no role is skipped, not a crash
  const t = parseStatus(doc([{ role: 'x', state: 'paused' }, { state: 'running' }, 5]))
  expect(t.ok && t.workers).toEqual([])
})

test('parse: a step number the list lacks is treated as unknown', () => {
  const s = parseStatus(doc([{ role: 'a', state: 'running', step: 9, steps: [{ n: 1, text: 'x' }] }]))
  expect(s.ok && s.workers[0]?.step).toBeNull()
})

test('select: running first (oldest first), finished within 60 s only, latest first', () => {
  const run1 = w({ key: 'r1', role: 'analyst', startedAt: NOW - 10 })
  const run2 = w({ key: 'r2', role: 'reviewer', startedAt: NOW - 100 })
  const fresh = w({ key: 'f1', state: 'exited', rc: 0, startedAt: NOW - 130, durationS: 100 }) // finished 30 s ago
  const fresher = w({ key: 'f2', state: 'exited', rc: 0, startedAt: NOW - 40, durationS: 30 }) // 10 s ago
  const old = w({ key: 'o', state: 'exited', rc: 0, startedAt: NOW - 400, durationS: 100 }) // 300 s ago
  const deadSeen = w({ key: 'd', state: 'dead' })
  const deadUnseen = w({ key: 'd2', state: 'dead' })
  const rows = selectWorkers(okSnap(old, fresh, run1, deadUnseen, fresher, run2, deadSeen), NOW, { d: NOW - 5 })
  expect(rows.map(r => r.key)).toEqual(['r2', 'r1', 'd', 'f2', 'f1'])
  const none = selectWorkers(okSnap(old, deadUnseen), NOW, {})
  expect(none).toEqual([])
})

test('collapsed rows: step, now, neither', () => {
  const a = w({ step: 2, steps: STEPS, now: 'ignored while a step is known' })
  const b = w({ role: 'analyst', folder: 'main', startedAt: NOW - 63, now: 'Read lib/harness-dash.sh' })
  const c = w({ role: 'reviewer', folder: 'main', startedAt: NOW - 5 })
  expect(texts([a, b, c], { expanded: false, maxRows: 10 })).toEqual([
    '● implementer #305  2/4 Add failing tests · 4m12s',
    '● analyst     main  → Read lib/harness-dash.sh · 1m03s',
    '● reviewer    main · 5s',
  ])
})

test('collapsed rows: finished ✓ ✗, exit, verify, verdict, duration', () => {
  const ok = w({ role: 'reviewer', folder: '#301', state: 'exited', rc: 0, verdict: 'PASS', durationS: 220, startedAt: NOW - 230 })
  const bad = w({ role: 'implementer', folder: '#301', state: 'exited', rc: 5, verify: 'fail', durationS: 61, startedAt: NOW - 70 })
  const dead = w({ role: 'analyst', folder: '#301', state: 'dead', startedAt: null, elapsedS: null })
  const out = texts([ok, bad, dead], { expanded: false, maxRows: 10 })
  expect(out[0]).toBe('✓ reviewer    #301  exit 0 · PASS · 3m40s')
  expect(out[1]).toBe('✗ implementer #301  exit 5 · verify fail · 1m01s')
  expect(out[2]).toBe('✗ analyst     #301  dead')
  const lines = layout([ok, bad], { expanded: false, maxRows: 10, columns: 100, nowS: NOW }).lines
  expect(lines.map(l => l.color)).toEqual(['green', 'red'])
})

test('expanded: step list marks done, current with now, pending', () => {
  const a = w({ step: 2, steps: STEPS, now: 'Run the dash suite' })
  expect(texts([a], { expanded: true, maxRows: 10 })).toEqual([
    '● implementer #305  4m12s · 23 turns · ctx 61k',
    '  ✓ 1 Read AGENTS.md',
    '  ▸ 2 Add failing tests   → Run the dash suite',
    '  · 3 Implement',
    '  · 4 Run the full tests',
  ])
})

test('expanded: no step shows only the now line; a stale step is shown as is', () => {
  const a = w({ role: 'analyst', folder: 'main', startedAt: NOW - 63, turns: 6, ctx: 40000, now: 'Read lib/harness-dash.sh' })
  expect(texts([a], { expanded: true, maxRows: 10 })).toEqual(['● analyst main  1m03s · 6 turns · ctx 40k', '  → Read lib/harness-dash.sh'])
  const none = w({ turns: null, ctx: null })
  expect(texts([none], { expanded: true, maxRows: 10 })).toEqual(['● implementer #305  4m12s'])
  const stale = w({ step: 1, steps: STEPS, startedAt: NOW - 3000, turns: 300 })
  expect(texts([stale], { expanded: true, maxRows: 10 })[1]).toBe('  ▸ 1 Read AGENTS.md')
})

test('maxRows overflow, collapsed: as many as fit then +N more', () => {
  const ws = [1, 2, 3, 4, 5].map(i => w({ key: `k${i}`, role: `r${i}`, step: 1, steps: STEPS }))
  const out = texts(ws, { expanded: false, maxRows: 3 })
  expect(out.length).toBe(3)
  expect(out[2]?.trim()).toBe('+3 more')
  expect(texts(ws, { expanded: false, maxRows: 5 }).length).toBe(5)
  expect(texts(ws, { expanded: false, maxRows: 4 }).slice(-1)[0]?.trim()).toBe('+2 more')
  expect(texts(ws, { expanded: false, maxRows: 0 })).toEqual([])
  expect(texts(ws, { expanded: false, maxRows: 1 }).length).toBe(1)
})

test('maxRows overflow, expanded: current step of each worker beats done and pending steps', () => {
  const a = w({ key: 'a', role: 'implementer', step: 3, steps: STEPS, now: 'X' })
  const b = w({ key: 'b', role: 'analyst', step: 2, steps: STEPS, now: 'Y' })
  // 2 workers x (header + current) = 4 rows: nothing else fits
  const four = texts([a, b], { expanded: true, maxRows: 4 })
  expect(four.length).toBe(4)
  expect(four.filter(t => t.includes('▸')).length).toBe(2)
  expect(four.some(t => t.includes('✓') || t.includes('·  '))).toBe(false)
  // a fifth and sixth row go to the steps nearest the current one, one per worker
  const six = texts([a, b], { expanded: true, maxRows: 6 })
  expect(six.length).toBe(6)
  expect(six.filter(t => t.includes('▸')).length).toBe(2)
  // a third worker that does not fit becomes +1 more
  const c = w({ key: 'c', role: 'reviewer', step: 1, steps: STEPS })
  const three = texts([a, b, c], { expanded: true, maxRows: 5 })
  expect(three.length).toBe(5)
  expect(three[4]?.trim()).toBe('+1 more')
  // order of lines stays the order of steps
  const ordered = texts([a], { expanded: true, maxRows: 4 })
  expect(ordered.slice(1).map(t => t.trim().slice(0, 3))).toEqual(['✓ 2', '▸ 3', '· 4'])
})

test('truncation counts wide Korean characters as two cells', () => {
  expect(width('가나다')).toBe(6)
  expect(truncate('가나다라마', 6)).toBe('가나…')
  expect(truncate('가나다라마', 10)).toBe('가나다라마')
  expect(truncate('abcdef', 4)).toBe('abc…')
  const a = w({ step: 1, steps: [{ n: 1, text: '한국어로 된 아주 긴 단계 이름입니다 정말로 깁니다' }] })
  const line = texts([a], { expanded: false, maxRows: 5, columns: 40 })[0]
  expect(width(line ?? "")).toBeLessThanOrEqual(40)
  expect(line?.endsWith(' · 4m12s')).toBe(true) // the duration survives the cut
  const fail = failureLine('매우 긴 사유 '.repeat(20), 30)
  expect(width(fail.text)).toBeLessThanOrEqual(30)
})

test('failure line text', () => {
  expect(failureLine('harness status failed (rc 1)', 80)).toEqual({ text: 'harness-workers: harness status failed (rc 1)', dim: true })
})

test('notifications: running to exited rc 0 is a toast only', () => {
  const prev = snap(w({ askId: 'a1' }))
  const next = snap(w({ askId: 'a1', state: 'exited', rc: 0, verify: 'pass', durationS: 422, startedAt: NOW - 422 }))
  const { events, deadAt } = diffSnapshots(prev, next, NOW)
  expect(events).toEqual([{ key: '/p|implementer', text: 'harness: implementer #305 exit 0 · verify pass · 7m02s', notify: false }])
  expect(deadAt).toEqual({ '/p|implementer': NOW })
})

test('notifications: rc 5, dead and verify fail also notify', () => {
  const prev = snap(w(), w({ key: '/p|analyst', role: 'analyst' }), w({ key: '/p|reviewer', role: 'reviewer' }))
  const next = snap(
    w({ state: 'exited', rc: 5, durationS: 10 }),
    w({ key: '/p|analyst', role: 'analyst', state: 'dead' }),
    w({ key: '/p|reviewer', role: 'reviewer', state: 'exited', rc: 0, verify: 'fail', verdict: 'FAIL', durationS: 5 }),
  )
  const { events } = diffSnapshots(prev, next, NOW)
  expect(events.map(e => e.notify)).toEqual([true, true, true])
  expect(events[0]?.text).toBe('harness: implementer #305 exit 5 · 10s')
  expect(events[1]?.text.startsWith('harness: analyst #305 dead')).toBe(true)
  expect(events[2]?.text).toBe('harness: reviewer #305 exit 0 · verify fail · FAIL · 5s')
})

test('notifications: a vanished worker, a replaced ask, the next poll and a first snapshot give none', () => {
  const run = snap(w({ askId: 'a1' }))
  expect(diffSnapshots(run, snap(), NOW).events).toEqual([])
  expect(diffSnapshots(run, snap(w({ askId: 'a2' })), NOW).events).toEqual([])
  const exited = snap(w({ askId: 'a1', state: 'exited', rc: 0, durationS: 5 }))
  expect(diffSnapshots(exited, exited, NOW + 3).events).toEqual([]) // no duplicate on the next poll
  expect(diffSnapshots(null, exited, NOW).events).toEqual([])
  expect(diffSnapshots(run, { ok: false, reason: 'x' }, NOW).events).toEqual([])
  expect(diffSnapshots({ ok: false, reason: 'x' }, exited, NOW).events).toEqual([])
})

test('anyRunning', () => {
  expect(anyRunning(null)).toBe(false)
  expect(anyRunning({ ok: false, reason: 'x' })).toBe(false)
  expect(anyRunning(snap(w({ state: 'exited' })))).toBe(false)
  expect(anyRunning(snap(w()))).toBe(true)
})
