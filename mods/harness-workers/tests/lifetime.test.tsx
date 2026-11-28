// Lifetime tests of the poll loop (hooks/register.tsx) through the engine's test kit: a mocked clock,
// a `process.run` that answers after a delay, and `session.start` / `session.end` raised by hand.
// Pure-model tests cannot see this class of bug: how many loops are alive after a restart.
// Run through tests/mod.test.sh (it writes ./golden.ts).
import { expect, mock, test } from 'claude-code/testing'

import { golden } from './golden'

if (golden === '') throw new Error('tests/golden.ts is the empty placeholder: run these tests through bash tests/mod.test.sh')

type Opts = { failOnce?: 'fs' | 'env' | 'cwd'; slowStateMs?: number; slowSetMs?: number; env?: Record<string, string>; cwd?: string; dirs?: string[]; delayMs?: number; mode?: 'ok' | 'reject' | 'hang' }
const SLOW = 30_000

// `on` and `$` are the test kit's; a hook here stands for the engine beneath the plugin.
// biome-ignore lint: the kit's types are structural
function rig($: any, on: any, o: Opts = {}) {
  // every state write counts: a live 1 s clock writes the `now` atom each second
  const everys = { writes: 0 }
  const clock = mock.clock(on)
  // a slow store write (slowSetMs): the poll is inside its last `update` while a retire lands
  on('state.set', async (_: unknown, e: unknown, next: (e: unknown) => unknown) => {
    if (o.slowSetMs) await clock.sleep(o.slowSetMs)
    everys.writes++
    return next(e)
  })
  const vars: Record<string, string> = { HOME: '/home/u', ...(o.env ?? {}) }
  let failed = false // the one failure of `failOnce`
  const failNow = (what: string) => (o.failOnce === what && !failed ? ((failed = true), true) : false)
  if (o.failOnce === 'env') {
    on('env.get', (_: unknown, e: { name: string }) => (failNow('env') ? { deny: 'env down' } : { value: vars[e.name] }))
  } else {
    mock.env(on, vars)
  }
  // a slow store read: a poll is inside its read/update awaits for that long
  if (o.slowStateMs) {
    on('state.get', async (_: unknown, e: unknown, next: (e: unknown) => unknown) => {
      await clock.sleep(o.slowStateMs!)
      return next(e)
    })
  }
  const dirs = new Set(o.dirs ?? ['/w/repo/.harness/asks', '/w/repo/.git'])
  const st = { runs: 0, active: 0, maxActive: 0, cwds: [] as string[], toasts: 0, mode: o.mode ?? 'ok', delayMs: o.delayMs ?? 0 }
  on('session.cwd', () => (failNow('cwd') ? { deny: 'cwd down' } : { value: o.cwd ?? '/w/repo' }))
  on('fs.exists', (_: unknown, e: { path: string }) => (failNow('fs') ? { deny: 'fs down' } : { value: dirs.has(e.path) }))
  on('ui.toast', () => (st.toasts++, { value: undefined }))
  on('ui.notify', () => ({ value: { isShown: true } }))
  on('session.start', (_: unknown, e: { cwd: string }) => ({ cwd: e.cwd }))
  on('session.end', () => ({ sessionId: 's' }))
  on('process.run', async (_: unknown, e: { init?: { timeoutMs?: number; cwd?: string } }) => {
    st.runs++
    st.cwds.push(e.init?.cwd ?? '')
    st.active++
    st.maxActive = Math.max(st.maxActive, st.active)
    try {
      if (st.mode === 'reject') return { deny: 'no harness' }
      if (st.mode === 'hang') {
        // a run that never answers is cut at its own timeout, as the engine does
        await clock.sleep(e.init?.timeoutMs ?? 3_600_000)
        return { deny: 'timed out' }
      }
      await clock.sleep(st.delayMs)
      return { value: { exitCode: 0, stdout: golden, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    } finally {
      st.active--
    }
  })
  const start = () => $.session.start({ cwd: o.cwd ?? '/w/repo', surface: 'terminal', isInteractive: true })
  const end = (reason: string) => $.session.end({ reason, sessionId: 's', resume: { id: 's' } })
  return { clock, st, start, end, everys }
}

const BAND = { plugin: 'harness-workers', surface: 'terminal', component: 'AbovePrompt', props: { hasSurvey: false, isCollapsed: false, isWorking: false, maxRows: 5, bodyColumns: 80, scroll: { offset: 0, bodyRows: 5 }, view: {} } } as const

test('/clear during the first poll: polling continues, never two runs at once', async ($, on) => {
  const r = rig($, on, { delayMs: 500 })
  await r.start()
  await r.clock.advance(100) // the first poll is in flight
  expect(r.st.runs).toBe(1)
  await r.end('clear')
  await r.clock.advance(60_000)
  expect(r.st.runs).toBeGreaterThanOrEqual(5)
  expect(r.st.maxActive).toBe(1)
})

test('a second session.start during a poll leaves exactly one loop', async ($, on) => {
  const r = rig($, on, { delayMs: 500 })
  await r.start()
  await r.clock.advance(100)
  await r.start()
  await r.clock.advance(60_000)
  expect(r.st.runs).toBeGreaterThanOrEqual(5)
  expect(r.st.maxActive).toBe(1)
  // one loop: about one run per 3 s while a worker runs, not two
  expect(r.st.runs).toBeLessThanOrEqual(25)
})

test('/clear and resume between polls: continues with one loop', async ($, on) => {
  const r = rig($, on)
  await r.start()
  await r.clock.advance(1_000)
  const before = r.st.runs
  await r.end('clear')
  await r.end('resume')
  await r.clock.advance(60_000)
  expect(r.st.runs - before).toBeGreaterThanOrEqual(10)
  expect(r.st.runs - before).toBeLessThanOrEqual(25)
  expect(r.st.maxActive).toBe(1)
})

for (const reason of ['prompt_input_exit', 'logout', 'other']) {
  test(`${reason}: no further runs and no timer left, even from a poll in flight`, async ($, on) => {
    const r = rig($, on, { delayMs: 500 })
    await r.start()
    await r.clock.advance(100) // retire while a poll is in flight: its finally must not start a loop or a clock
    await r.end(reason)
    await r.clock.advance(600)
    const after = r.st.runs
    await r.clock.advance(120_000)
    expect(r.st.runs).toBe(after)
    // (the 1 s clock race is pinned by the store-read tests below: here the retire lands before the
    // poll can see a snapshot, so no clock could have started either way)
  })
}

test('a process.run that rejects: the loop goes on at the slow interval and the band shows the reason', async ($, on) => {
  const r = rig($, on, { mode: 'reject' })
  await r.start()
  await r.clock.advance(100)
  expect(r.st.runs).toBeGreaterThanOrEqual(1) // the bin on PATH, then ~/.local/bin
  const first = r.st.runs
  await r.clock.advance(SLOW * 3)
  expect(r.st.runs).toBeGreaterThanOrEqual(first * 3)
  expect(r.st.runs).toBeLessThanOrEqual(first * 5)
  const ui = await $.ui.mount(BAND)
  expect((await ui.find({ type: 'Text', text: /harness-workers: harness status did not run/ }))?.text).toMatch(/did not run/)
  await ui.unmount()
})

test('a process.run that never answers: it times out, the loop goes on slowly and the band shows it', async ($, on) => {
  const r = rig($, on, { mode: 'hang' })
  await r.start()
  await r.clock.advance(100)
  expect(r.st.runs).toBe(1)
  await r.clock.advance(10_000) // the 10 s timeout
  await r.clock.advance(SLOW * 3 + 10_000)
  expect(r.st.runs).toBeGreaterThanOrEqual(3)
  expect(r.st.runs).toBeLessThanOrEqual(6)
  expect(r.st.maxActive).toBe(1)
  const ui = await $.ui.mount(BAND)
  expect((await ui.find({ type: 'Text', text: /harness-workers: harness status timed out/ }))?.text).toMatch(/timed out/)
  await ui.unmount()
})

test('HARNESS_ROLE=worker: zero runs', async ($, on) => {
  const r = rig($, on, { env: { HARNESS_ROLE: 'worker' } })
  await r.start()
  await r.clock.advance(120_000)
  expect(r.st.runs).toBe(0)
})

test('a cwd outside any checkout: zero runs', async ($, on) => {
  const r = rig($, on, { cwd: '/elsewhere/dir' })
  await r.start()
  await r.clock.advance(120_000)
  expect(r.st.runs).toBe(0)
})

test('a harness subdirectory: runs `harness status` in the root', async ($, on) => {
  const r = rig($, on, { cwd: '/w/repo/src/deep' })
  await r.start()
  await r.clock.advance(100)
  expect(r.st.runs).toBeGreaterThanOrEqual(1)
  expect(r.st.cwds[0]).toBe('/w/repo')
})

// A gate call that fails once must not leave a claimed loop that never polls (review round 3, probe P8).
for (const what of ['fs', 'env', 'cwd'] as const) {
  test(`${what} rejects once in the start gate: dim row, then polling starts by itself, one loop`, async ($, on) => {
    const r = rig($, on, { failOnce: what, delayMs: 500 })
    await r.start()
    await r.clock.advance(100)
    expect(r.st.runs).toBe(0)
    const ui = await $.ui.mount(BAND)
    expect((await ui.find({ type: 'Text', text: /harness-workers: start gate failed/ }))?.text).toMatch(/start gate failed/)
    await ui.unmount()
    await r.clock.advance(SLOW + 1_000) // the retry, with no /clear
    expect(r.st.runs).toBeGreaterThanOrEqual(1)
    await r.clock.advance(60_000)
    expect(r.st.runs).toBeGreaterThanOrEqual(10)
    expect(r.st.runs).toBeLessThanOrEqual(25)
    expect(r.st.maxActive).toBe(1)
  })
}

test('a failed gate with HARNESS_ROLE=worker stays silent: no row, no runs', async ($, on) => {
  const r = rig($, on, { env: { HARNESS_ROLE: 'worker' }, failOnce: 'fs' })
  await r.start()
  await r.clock.advance(120_000)
  expect(r.st.runs).toBe(0)
  const ui = await $.ui.mount(BAND)
  expect(await ui.find({ type: 'Text', text: /harness-workers/ })).toBeFalsy()
  await ui.unmount()
})

// A retire that lands while the poll is inside its read/update awaits: nothing late is shown (review round 3, P5).
test('retire during the store reads: no toast, no write, no clock afterwards', async ($, on) => {
  const r = rig($, on, { slowStateMs: 400 })
  await r.start()
  await r.clock.advance(100) // process.run answered; the poll waits in `read(snapshot)`
  expect(r.st.runs).toBe(1)
  await r.end('prompt_input_exit')
  const toasts = r.st.toasts
  const writes = r.everys.writes
  await r.clock.advance(30_000)
  expect(r.st.toasts).toBe(toasts)
  expect(r.everys.writes).toBe(writes)
  expect(r.st.runs).toBe(1)
})

// The retire-time clock race (review round 3, P7): the poll sees a running worker, is retired while it
// still reads the store, and must not start the 1 s clock that nothing would cancel.
test('retire during the store reads with a running worker: no 1 s clock starts', async ($, on) => {
  const r = rig($, on, { slowStateMs: 400 })
  await r.start()
  await r.clock.advance(100)
  await r.end('prompt_input_exit')
  await r.clock.advance(1_000) // the in-flight reads finish
  const writes = r.everys.writes
  await r.clock.advance(20_000)
  expect(r.everys.writes).toBe(writes)
})

// Retire, then start again in the same process (an in-process resume): the new loop must not be blocked
// by the retired loop's poll still in flight (review round 3, P3: a module-global in-flight guard).
test('retire during a poll, then session.start: exactly one loop resumes', async ($, on) => {
  const r = rig($, on, { delayMs: 500 })
  await r.start()
  await r.clock.advance(100) // first poll in flight
  await r.end('logout')
  await r.start()
  await r.clock.advance(60_000)
  expect(r.st.runs).toBeGreaterThanOrEqual(5)
  expect(r.st.runs).toBeLessThanOrEqual(25)
  // the retired poll's run cannot be cancelled, so one overlap with the new loop's first run is allowed
  expect(r.st.maxActive).toBeLessThanOrEqual(2)
})

// The last await of a poll is the `now` write; a retire landing there leaves `running` true in the
// finally, whose syncClock must not start the 1 s clock (review round 3, P7; mutant: no dead check there).
test('retire during the last store write with a running worker: no 1 s clock starts', async ($, on) => {
  const r = rig($, on, { slowSetMs: 400 })
  await r.start()
  await r.clock.advance(1_000) // deadAt (400) and snapshot (400) written; the `now` write is in flight
  await r.end('prompt_input_exit')
  await r.clock.advance(2_000) // the write settles
  const writes = r.everys.writes
  await r.clock.advance(20_000)
  expect(r.everys.writes).toBe(writes)
})
