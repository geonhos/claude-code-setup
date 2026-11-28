// Lifetime tests of the poll loop (hooks/register.tsx) through the engine's test kit: a mocked clock,
// a `process.run` that answers after a delay, and `session.start` / `session.end` raised by hand.
// Pure-model tests cannot see this class of bug: how many loops are alive after a restart.
// Run through tests/mod.test.sh (it writes ./golden.ts).
import { expect, mock, test } from 'claude-code/testing'

import { golden } from './golden'

if (golden === '') throw new Error('tests/golden.ts is the empty placeholder: run these tests through bash tests/mod.test.sh')

type Opts = { env?: Record<string, string>; cwd?: string; dirs?: string[]; delayMs?: number; mode?: 'ok' | 'reject' | 'hang' }
const SLOW = 30_000

// `on` and `$` are the test kit's; a hook here stands for the engine beneath the plugin.
// biome-ignore lint: the kit's types are structural
function rig($: any, on: any, o: Opts = {}) {
  // every state write counts: a live 1 s clock writes the `now` atom each second
  const everys = { writes: 0 }
  on('state.set', (_: unknown, e: unknown, next: (e: unknown) => unknown) => (everys.writes++, next(e)))
  const clock = mock.clock(on)
  mock.env(on, { HOME: '/home/u', ...(o.env ?? {}) })
  const dirs = new Set(o.dirs ?? ['/w/repo/.harness/asks', '/w/repo/.git'])
  const st = { runs: 0, active: 0, maxActive: 0, cwds: [] as string[], mode: o.mode ?? 'ok', delayMs: o.delayMs ?? 0 }
  on('session.cwd', () => ({ value: o.cwd ?? '/w/repo' }))
  on('fs.exists', (_: unknown, e: { path: string }) => ({ value: dirs.has(e.path) }))
  on('ui.toast', () => ({ value: undefined }))
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
    const writes = r.everys.writes
    await r.clock.advance(10_000)
    expect(r.everys.writes).toBe(writes) // the in-flight poll must not start the 1 s clock after the retire
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
