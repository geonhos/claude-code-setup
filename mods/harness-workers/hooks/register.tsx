// harness-workers: worker progress above the prompt, read from `harness status --json --all`.
// Wiring only: parsing, row selection, layout and notification decisions live in ./model.ts.
// Draws only: nothing here writes a file or puts text into the conversation.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { Snapshot } from '../types'
import { anyRunning, diffSnapshots, failureLine, failureSnapshot, findHarnessRoot, layout, mergeDeadAt, selectWorkers, sessionEndAction, snapshotOf } from './model'

const FAST_MS = 3_000 // while a worker runs
const SLOW_MS = 30_000 // otherwise, and after a failed poll
const RUN_TIMEOUT_MS = 10_000
const MAX_BAND_ROWS = 12

// Held by the host, so the state survives a hot reload of this file.
const snapshot = atom({ plugin: 'harness-workers', key: 'snapshot' } as const, null as Snapshot | null)
const now = atom({ plugin: 'harness-workers', key: 'now' } as const, 0)
const expanded = atom({ plugin: 'harness-workers', key: 'expanded' } as const, false)
const deadAt = atom({ plugin: 'harness-workers', key: 'deadAt' } as const, {} as Record<string, number>)

const nowS = () => Math.floor(Date.now() / 1000)

type Dollar = EngineInterface

/** `harness` from PATH, else the install location of install.sh. */
async function runStatus($: Dollar, cwd: string): Promise<{ exitCode: number; stdout: string } | string> {
  const argv = ['status', '--json', '--all']
  const home = await $.env.get('HOME')
  const bins = ['harness', ...(home ? [`${home}/.local/bin/harness`] : [])]
  let last = 'harness status did not run'
  for (const bin of bins) {
    try {
      const r = await $.process.run([bin, ...argv], { timeoutMs: RUN_TIMEOUT_MS, cwd })
      return { exitCode: r.exitCode, stdout: r.stdout }
    } catch (err) {
      last = /still running|timed? ?out/i.test(String(err)) ? 'harness status timed out' : 'harness status did not run'
      if (last === 'harness status timed out') break
    }
  }
  return last
}

// One loop instance owns everything with a lifetime: its timers, its in-flight guard and its `dead`
// flag. `current` is the one live instance (or null), so after any sequence of session.start and
// session.end exactly one loop is alive, and a retired loop's late poll can neither reschedule nor
// start a clock. start() is idempotent: while a loop is alive it does nothing (each poll re-resolves
// the harness root, so a changed cwd needs no restart).
type Loop = { dead: boolean; isPolling: boolean; poller: Timer | null; clock: Timer | null }
let current: Loop | null = null

function retire(): void {
  const l = current
  current = null
  if (l === null) return
  l.dead = true
  l.poller?.cancel()
  l.clock?.cancel()
  l.poller = l.clock = null
}

// Gate: not a worker, and the cwd is in a harness checkout; `harness status` runs in that root.
async function start($: Dollar): Promise<void> {
  if (current !== null) return
  const me: Loop = { dead: false, isPolling: false, poller: null, clock: null }
  current = me // claimed before the first await: a second start() during the gate sees it
  const isWorker = (await $.env.get('HARNESS_ROLE')) === 'worker'
  const root = isWorker ? null : await findHarnessRoot(await $.session.cwd(), p => $.fs.exists(p))
  if (me.dead) return // retired while the gate ran
  if (root === null) {
    current = null // not a harness conductor: no polling, no row; a later session.end may try again
    return
  }

  const schedule = (ms: number) => {
    if (me.dead) return
    me.poller = $.clock.after(ms, () => void poll())
  }
  // A clock for the elapsed times, only while something runs.
  const syncClock = (isRunning: boolean) => {
    if (me.dead) return
    if (isRunning && me.clock === null) {
      me.clock = $.clock.every(1000, () => void update($, now, () => Date.now()).catch(() => {}))
    } else if (!isRunning && me.clock !== null) {
      me.clock.cancel()
      me.clock = null
    }
  }
  // One poll. Every stage that can throw is caught and shown as the dim `harness-workers: <reason>` row,
  // and the next poll is scheduled in `finally`, so the loop never dies silently.
  const poll = async (): Promise<void> => {
    if (me.dead || me.isPolling) return
    me.isPolling = true
    let running = false
    try {
      let fresh: Snapshot | null // null: not in a harness checkout (no band)
      try {
        // The gate again: the cwd can change with a new session id (/clear, resume); no root, no band.
        const dir = await findHarnessRoot(await $.session.cwd(), p => $.fs.exists(p))
        fresh = dir === null ? null : snapshotOf(await runStatus($, dir))
      } catch (err) {
        fresh = failureSnapshot('harness status', err)
      }
      if (me.dead) return
      const t = nowS()
      try {
        if (fresh?.ok) {
          const prev = await read($, snapshot)
          const d = diffSnapshots(prev, fresh, t)
          await update($, deadAt, old => mergeDeadAt(old, d.deadAt, t))
          for (const ev of d.events) {
            try {
              $.ui.toast(ev.text)
              if (ev.notify) void $.ui.notify(ev.text, { title: 'harness-workers', key: `harness-workers:${ev.key}` }).catch(() => {})
            } catch (err) {
              fresh = failureSnapshot('toast', err)
              break
            }
          }
        }
      } catch (err) {
        fresh = failureSnapshot('read', err)
      }
      try {
        await update($, snapshot, () => fresh)
        await update($, now, () => Date.now())
      } catch (err) {
        // the failure row cannot be stored either: nothing left to show it with
      }
      running = fresh !== null && fresh.ok && anyRunning(fresh)
    } catch (err) {
      // unreachable by design; the finally below still reschedules
    } finally {
      me.isPolling = false
      try {
        syncClock(running)
      } catch (err) {
        // a clock that cannot start must not stop the poll
      }
      schedule(running ? FAST_MS : SLOW_MS)
    }
  }
  void poll()
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const r = await next(e)
    await start($)
    return r
  })

  // The process ends: retire the loop. /clear and resume go on under a new session id and fire no
  // session.start, so the loop keeps running (or starts, if the gate failed before); see sessionEndAction.
  on('session.end', async ($, e, next) => {
    if (sessionEndAction(e.reason) === 'retire') retire()
    else await start($) // no-op while a loop is alive; starts one if the gate failed before
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const snap = await read($, snapshot)
    if (snap === null || e.props.hasSurvey || e.props.maxRows <= 0) return next(e)
    const { Box, Button, Text } = $.ui.resolve(e)
    const columns = Math.max(20, e.props.bodyColumns)

    if (!snap.ok) {
      const f = failureLine(snap.reason, columns)
      return (
        <Box>
          <Text dimColor>{f.text}</Text>
        </Box>
      )
    }
    const isOpen = await read($, expanded)
    await read($, now) // redraw on the clock tick
    const t = nowS()
    const rows = selectWorkers(snap, t, await read($, deadAt))
    if (rows.length === 0) return next(e)
    const out = layout(rows, { expanded: isOpen, maxRows: Math.min(e.props.maxRows, MAX_BAND_ROWS), columns: columns - 2, nowS: t })
    if (out.lines.length === 0) return next(e)

    return (
      <Box flexDirection="column">
        {out.lines.map((l, i) => (
          <Box key={`row${i}`}>
            {i === 0 ? (
              <Button key="toggle" label={isOpen ? '▾ ' : '▸ '} onPress={() => update($, expanded, v => !v)} />
            ) : (
              <Text>{'  '}</Text>
            )}
            <Text color={l.color} dimColor={l.dim}>
              {l.text}
            </Text>
          </Box>
        ))}
      </Box>
    )
  })
}
