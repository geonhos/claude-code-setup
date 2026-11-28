import { expect, test } from 'claude-code/testing'

import type { Snapshot, Worker } from '../types'
import {
  anyRunning,
  clean,
  diffSnapshots,
  failureLine,
  failureSnapshot,
  findHarnessRoot,
  layout,
  mergeDeadAt,
  NARROW_COLS,
  parseStatus,
  selectWorkers,
  sessionEndAction,
  snapshotOf,
  truncate,
  width,
} from '../hooks/model'

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
    titleKo: null,
    steps: [],
    step: null,
    verify: null,
    rc: null,
    verdict: null,
    durationS: null,
    ...over,
  }
}
const STEPS = ['Read AGENTS.md', 'Add failing tests', 'Implement', 'Run the full tests'].map((text, i) => ({ n: i + 1, text, ko: null }))
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
    '● implementer #305  4m12s · 2/4 Add failing tests',
    '● analyst     main  1m03s · → Read lib/harness-dash.sh',
    '● reviewer    main  5s',
  ])
})

test('collapsed rows: finished ✓ ✗, exit, verify, verdict, duration', () => {
  const ok = w({ role: 'reviewer', folder: '#301', state: 'exited', rc: 0, verdict: 'PASS', durationS: 220, startedAt: NOW - 230 })
  const bad = w({ role: 'implementer', folder: '#301', state: 'exited', rc: 5, verify: 'fail', durationS: 61, startedAt: NOW - 70 })
  const dead = w({ role: 'analyst', folder: '#301', state: 'dead', startedAt: null, elapsedS: null })
  const out = texts([ok, bad, dead], { expanded: false, maxRows: 10 })
  expect(out[0]).toBe('✓ reviewer    #301  3m40s · exit 0 · PASS')
  expect(out[1]).toBe('✗ implementer #301  1m01s · exit 5 · verify fail')
  expect(out[2]).toBe('✗ analyst     #301  dead')
  const lines = layout([ok, bad], { expanded: false, maxRows: 10, columns: 100, nowS: NOW }).lines
  expect(lines.map(l => l.color)).toEqual(['green', 'red'])
})

test('expanded: step list marks done, current with now, pending', () => {
  const a = w({ step: 2, steps: STEPS, now: 'Run the dash suite' })
  expect(texts([a], { expanded: true, maxRows: 10 })).toEqual([
    '● implementer #305  4m12s · 23 turns · ctx 61k',
    '  ✓ 1 Read AGENTS.md',
    '  ▸ 2 Add failing tests',
    '      → Run the dash suite',
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

test('maxRows overflow, expanded: current step and its action line of each worker beat done and pending steps', () => {
  const a = w({ key: 'a', role: 'implementer', step: 3, steps: STEPS, now: 'X' })
  const b = w({ key: 'b', role: 'analyst', step: 2, steps: STEPS, now: 'Y' })
  // 2 workers x (header + current step + action line) = 6 rows: nothing else fits
  const six = texts([a, b], { expanded: true, maxRows: 6 })
  expect(six.length).toBe(6)
  expect(six.filter(t => t.includes('▸')).length).toBe(2)
  expect(six.filter(t => t.includes('→')).length).toBe(2)
  expect(six.some(t => t.includes('✓') || t.includes('·  '))).toBe(false)
  // a seventh and eighth row go to the steps nearest the current one, one per worker
  const eight = texts([a, b], { expanded: true, maxRows: 8 })
  expect(eight.length).toBe(8)
  expect(eight.filter(t => t.includes('▸')).length).toBe(2)
  // a third worker that does not fit becomes +1 more
  const c = w({ key: 'c', role: 'reviewer', step: 1, steps: STEPS })
  const seven = texts([a, b, c], { expanded: true, maxRows: 7 })
  expect(seven.length).toBe(7)
  expect(seven[6]?.trim()).toBe('+1 more')
  // order of lines stays the order of steps, the action line stays under its step
  const ordered = texts([a], { expanded: true, maxRows: 5 })
  expect(ordered.slice(1).map(t => t.trim().slice(0, 3))).toEqual(['✓ 2', '▸ 3', '→ X', '· 4'])
})

const KO_STEPS = [
  { n: 1, text: 'Read the mod code', ko: 'mod 코드와 계약 읽기' },
  { n: 2, text: 'Add failing tests', ko: '실패하는 테스트 추가' },
  { n: 3, text: 'No Korean name', ko: null },
  { n: 4, text: 'Run all tests', ko: '전체 테스트 실행' },
]

test('Korean: collapsed row uses the step ko, else the English text', () => {
  const a = w({ step: 2, steps: KO_STEPS, titleKo: 'band에 한글 지시' })
  expect(texts([a], { expanded: false, maxRows: 5 })).toEqual(['● implementer #305  4m12s · 2/4 실패하는 테스트 추가'])
  const b = w({ step: 3, steps: KO_STEPS })
  expect(texts([b], { expanded: false, maxRows: 5 })).toEqual(['● implementer #305  4m12s · 3/4 No Korean name'])
})

test('Korean: expanded shows 지시 first, ko names, the action line under the current step', () => {
  const a = w({ step: 2, steps: KO_STEPS, titleKo: 'band에 한글 지시와 단계 표시', now: 'Run the dash suite' })
  expect(texts([a], { expanded: true, maxRows: 10 })).toEqual([
    '● implementer #305  4m12s · 23 turns · ctx 61k',
    '  지시: band에 한글 지시와 단계 표시',
    '  ✓ 1 mod 코드와 계약 읽기',
    '  ▸ 2 실패하는 테스트 추가',
    '      → Run the dash suite',
    '  · 3 No Korean name',
    '  · 4 전체 테스트 실행',
  ])
  // no step known: 지시 line, then the action line
  const n = w({ titleKo: '한글 지시', now: 'Read it' })
  expect(texts([n], { expanded: true, maxRows: 10 })).toEqual(['● implementer #305  4m12s · 23 turns · ctx 61k', '  지시: 한글 지시', '  → Read it'])
  // without a title or ko the layout is the old one
  const plain = w({ step: 1, steps: STEPS })
  expect(texts([plain], { expanded: true, maxRows: 10 }).some(t => t.includes('지시'))).toBe(false)
})

test('Korean: the 지시 line counts toward maxRows and is cut by cells', () => {
  const a = w({ key: 'a', step: 2, steps: KO_STEPS, titleKo: '아주 긴 한글 지시 문장입니다 정말로 매우 깁니다', now: 'X' })
  const b = w({ key: 'b', role: 'analyst', step: 1, steps: KO_STEPS, titleKo: '두 번째' })
  // a costs header + 지시 + step + action = 4; b does not fit with +1 more
  const out = texts([a, b], { expanded: true, maxRows: 5 })
  expect(out.length).toBe(5)
  expect(out[1]).toContain('지시:')
  expect(out[4]?.trim()).toBe('+1 more')
  for (const cols of [12, 20, 30]) {
    const lines = layout([a], { expanded: true, maxRows: 10, columns: cols, nowS: NOW }).lines
    for (const l of lines) expect(width(l.text)).toBeLessThanOrEqual(cols)
  }
  const cut = layout([a], { expanded: true, maxRows: 10, columns: 20, nowS: NOW }).lines[1]?.text ?? ''
  expect(cut.endsWith('…')).toBe(true)
  // a block that cannot fit its 지시 line keeps header and current step first
  const tight = texts([a], { expanded: true, maxRows: 3 })
  expect(tight.length).toBe(3)
})

test('parseStatus reads title_ko and steps[].ko; absent or empty is null', () => {
  const s = parseStatus(doc([
    { role: 'a', state: 'running', title_ko: '지시 문장', steps: [{ n: 1, text: 'x', ko: '하나' }, { n: 2, text: 'y', ko: null }, { n: 3, text: 'z' }, { n: 4, text: 'q', ko: '  ' }] },
    { role: 'b', state: 'running', title_ko: null, steps: [] },
    { role: 'c', state: 'running' },
  ]))
  expect(s.ok).toBe(true)
  if (!s.ok) return
  expect(s.workers[0]?.titleKo).toBe('지시 문장')
  expect(s.workers[0]?.steps.map(x => x.ko)).toEqual(['하나', null, null, null])
  expect(s.workers[1]?.titleKo).toBeNull()
  expect(s.workers[2]?.titleKo).toBeNull()
})

test('truncation counts wide Korean characters as two cells', () => {
  expect(width('가나다')).toBe(6)
  expect(truncate('가나다라마', 6)).toBe('가나…')
  expect(truncate('가나다라마', 10)).toBe('가나다라마')
  expect(truncate('abcdef', 4)).toBe('abc…')
  const a = w({ step: 1, steps: [{ n: 1, text: '한국어로 된 아주 긴 단계 이름입니다 정말로 깁니다', ko: null }] })
  const line = texts([a], { expanded: false, maxRows: 5, columns: 40 })[0]
  expect(width(line ?? "")).toBeLessThanOrEqual(40)
  expect(line?.includes('4m12s')).toBe(true) // the duration survives the cut
  expect(line?.endsWith('…')).toBe(true)
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

test('layout never returns more rows than maxRows', () => {
  const many = Array.from({ length: 6 }, (_, i) => w({ key: `/p|r${i}`, role: `r${i}`, step: 2, steps: STEPS, now: 'editing' }))
  for (const workers of [[many[0]!], many]) {
    for (const maxRows of [1, 2]) {
      for (const expanded of [false, true]) {
        const out = layout(workers, { expanded, maxRows, columns: 80, nowS: NOW })
        expect(out.lines.length <= maxRows).toBe(true)
        expect(out.lines.length >= 1).toBe(true)
      }
    }
  }
  // a hidden worker with maxRows >= 2: the last row says how many
  for (const expanded of [false, true]) {
    for (const maxRows of [2, 3]) {
      const out = layout(many, { expanded, maxRows, columns: 80, nowS: NOW })
      expect(out.lines.length).toBe(maxRows)
      expect(out.lines[maxRows - 1]!.text.trim()).toBe(`+${out.hidden} more`)
      expect(out.hidden >= 1).toBe(true)
    }
  }
  const two = layout(many, { expanded: true, maxRows: 2, columns: 80, nowS: NOW })
  expect(two.lines.map(l => l.text.trim()).slice(1)).toEqual(['+5 more'])
  const one = layout([many[0]!], { expanded: true, maxRows: 1, columns: 80, nowS: NOW })
  expect(one.lines.length).toBe(1)
})

test('clean strips whole escape sequences and control characters', () => {
  expect(clean('a\x1b[31mred\x1b[0m')).toBe('ared')
  expect(clean('x\x1b]0;title\x07y')).toBe('xy')
  expect(clean('x\x1b]8;;http://a\x1b\\link\x1b]8;;\x1b\\')).toBe('xlink')
  expect(clean('a\nb\tc')).toBe('a b c')
})

test('session.end: only the reasons that end the process retire the loop', () => {
  for (const r of ['prompt_input_exit', 'logout', 'other']) expect(sessionEndAction(r)).toBe('retire')
  for (const r of ['clear', 'resume']) expect(sessionEndAction(r)).toBe('continue')
  expect(sessionEndAction('something_new')).toBe('continue')
})

test('poll stages: a result becomes a snapshot, a throw becomes a failure row', () => {
  expect(snapshotOf('harness status timed out')).toEqual({ ok: false, reason: 'harness status timed out' })
  expect(snapshotOf({ exitCode: 2, stdout: '' })).toEqual({ ok: false, reason: 'harness status failed (rc 2)' })
  expect(snapshotOf({ exitCode: 0, stdout: 'not json' }).ok).toBe(false)
  const f = failureSnapshot('update', new Error('boom'))
  expect(f).toEqual({ ok: false, reason: 'update failed: boom' })
  expect(failureLine((f as { reason: string }).reason, 80).text).toBe('harness-workers: update failed: boom')
  expect(failureSnapshot('toast', 'x')).toEqual({ ok: false, reason: 'toast failed: x' })
})

test('deadAt merge keeps new times and drops old ones', () => {
  expect(mergeDeadAt({ a: NOW - 400, b: NOW - 10 }, { c: NOW }, NOW)).toEqual({ b: NOW - 10, c: NOW })
})

test('harness root: nearest ancestor with .harness/asks, up to .git inclusive', async () => {
  const fs = (paths: string[]) => async (p: string) => paths.includes(p)
  // a subdirectory of a checkout
  expect(await findHarnessRoot('/w/repo/src/deep', fs(['/w/repo/.harness/asks', '/w/repo/.git']))).toBe('/w/repo')
  // the nearest one wins
  expect(await findHarnessRoot('/w/repo/sub', fs(['/w/repo/.harness/asks', '/w/repo/sub/.harness/asks', '/w/repo/.git']))).toBe('/w/repo/sub')
  // the search stops at the dir holding .git: an ancestor above it does not count
  expect(await findHarnessRoot('/w/repo/src', fs(['/w/.harness/asks', '/w/repo/.git']))).toBe(null)
  // outside git only the start dir counts
  expect(await findHarnessRoot('/w/plain/src', fs(['/w/plain/.harness/asks']))).toBe(null)
  expect(await findHarnessRoot('/w/plain', fs(['/w/plain/.harness/asks']))).toBe('/w/plain')
  // the filesystem root, a relative path and the depth bound end the walk
  expect(await findHarnessRoot('/', fs([]))).toBe(null)
  expect(await findHarnessRoot('relative/dir', fs(['relative/dir/.harness/asks']))).toBe(null)
  let calls = 0
  const counting = async () => (calls++, false)
  expect(await findHarnessRoot('/' + Array.from({ length: 200 }, () => 'd').join('/'), counting, 5)).toBe(null)
  expect(calls <= 2 * 6 + 1).toBe(true)
})

// ---------- narrow terminals ----------

const hasWide = (t: string) => /[\u1100-\u115f\u2e80-\ua4cf\uac00-\ud7a3]/.test(t)

test('narrow: the wide form keeps full role names, aligned, at 80 columns', () => {
  const a = w({ step: 2, steps: KO_STEPS })
  const b = w({ key: 'b', role: 'analyst', folder: 'main', now: 'Read lib/harness-dash.sh', startedAt: NOW - 63 })
  expect(texts([a, b], { expanded: false, maxRows: 5, columns: 80 })).toEqual([
    '● implementer #305  4m12s · 2/4 실패하는 테스트 추가',
    '● analyst     main  1m03s · → Read lib/harness-dash.sh',
  ])
})

test('narrow: short roles, single spaces; the end of the step name goes first', () => {
  const a = w({ step: 2, steps: KO_STEPS, folder: '#331', now: 'Run the dash suite' })
  expect(texts([a], { expanded: false, maxRows: 5, columns: 30 })).toEqual(['● impl #331 4m12s 2/4 실패하…'])
  expect(texts([a], { expanded: false, maxRows: 5, columns: 40 })).toEqual(['● impl #331 4m12s 2/4 실패하는 테스트 …'])
  const long = w({ step: 1, folder: '#331', steps: [{ n: 1, text: 'A very long English step name that cannot fit', ko: null }] })
  expect(texts([long], { expanded: false, maxRows: 5, columns: 40 })).toEqual(['● impl #331 4m12s 1/1 A very long Engli…'])
})

test('narrow: main tag is dropped before the step name is cut, #N stays', () => {
  const a = w({ role: 'analyst', folder: 'main', step: 1, steps: [{ n: 1, text: 'Read the code', ko: null }] })
  expect(texts([a], { expanded: false, maxRows: 5, columns: 24 })).toEqual(['● anl 4m12s 1/1 Read th…'])
  const b = w({ role: 'reviewer', folder: '#7', step: 1, steps: [{ n: 1, text: 'Read the code', ko: null }] })
  expect(texts([b], { expanded: false, maxRows: 5, columns: 24 })[0]).toBe('● rev #7 4m12s 1/1 Read…')
})

test('narrow: expanded header drops ctx, then turns', () => {
  const a = w({ folder: '#331' })
  expect(texts([a], { expanded: true, maxRows: 5, columns: 80 })).toEqual(['● implementer #331  4m12s · 23 turns · ctx 61k'])
  expect(texts([a], { expanded: true, maxRows: 5, columns: 40 })).toEqual(['● impl #331 4m12s 23 turns ctx 61k'])
  expect(texts([a], { expanded: true, maxRows: 5, columns: 30 })).toEqual(['● impl #331 4m12s 23 turns'])
  expect(texts([a], { expanded: true, maxRows: 5, columns: 22 })).toEqual(['● impl #331 4m12s'])
})

test('narrow: action line is indented 6 when wide, 2 below NARROW_COLS', () => {
  const a = w({ step: 2, steps: KO_STEPS, folder: '#331', now: 'Run the dash suite' })
  expect(texts([a], { expanded: true, maxRows: 10, columns: 80 })[3]).toBe('      → Run the dash suite')
  expect(texts([a], { expanded: true, maxRows: 10, columns: NARROW_COLS })[3]).toBe('      → Run the dash suite')
  expect(texts([a], { expanded: true, maxRows: 10, columns: NARROW_COLS - 1 })[3]).toBe('  → Run the dash suite')
})

test('narrow: at 80, 60, 40 and 30 columns no line is wider than the width and elapsed stays', () => {
  const korean = w({ step: 2, steps: KO_STEPS, titleKo: '아주 긴 한글 지시 문장입니다 정말로 매우 깁니다', folder: '#331', now: '한글이 섞인 아주 긴 동작 Run the whole dash suite now' })
  const english = w({ key: 'e', role: 'reviewer', folder: 'main', step: 3, steps: [{ n: 1, text: 'a', ko: null }, { n: 2, text: 'b', ko: null }, { n: 3, text: 'A long English step name for the width test', ko: null }], now: 'Reading a long file path lib/harness-dash.sh', startedAt: NOW - 3700 })
  const done = w({ key: 'd', role: 'analyst', folder: '#12', state: 'exited', rc: 1, verify: 'fail', verdict: 'FAIL', durationS: 75, startedAt: NOW - 90 })
  const samples: Record<string, string[]> = {}
  for (const cols of [80, 60, 40, 30]) {
    for (const expanded of [false, true]) {
      const lines = layout([korean, english, done], { expanded, maxRows: 30, columns: cols, nowS: NOW }).lines.map(l => l.text)
      samples[`${cols}${expanded ? 'x' : 'c'}`] = lines
      for (const t of lines) expect(width(t)).toBeLessThanOrEqual(cols)
      for (const h of lines.filter(t => /^[●✓✗]/.test(t))) expect(/\d+(s|m\d\d s|m\d\ds|h\d\dm)/.test(h) || /\d(s|m)/.test(h)).toBe(true)
    }
  }
  // elapsed text of each worker is visible in every head at 30 columns, Korean step names are cut with …
  const heads30 = samples['30c']!
  expect(heads30[0]).toContain('4m12s')
  expect(heads30[1]).toContain('1h01m')
  expect(heads30[2]).toContain('1m15s')
  expect(heads30[0]?.endsWith('…') || hasWide(heads30[0] ?? '')).toBe(true)
  expect(samples['30x']!.some(t => t.endsWith('…'))).toBe(true)
  expect(samples['80c']![0]).toBe('● implementer #331  4m12s · 2/4 실패하는 테스트 추가')
})
