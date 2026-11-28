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

let poller: Timer | null = null
let clock: Timer | null = null
let isPolling = false // a slow run must not let two polls overlap
let epoch = 0 // a reload or a new session start retires the loop of the old one

// Starts the loop (or restarts it: a new `mine` retires the old one). Gate: not a worker, and the cwd
// is in a harness checkout; `harness status` runs in that root, so a subdirectory works too.
async function start($: Dollar): Promise<void> {
  poller?.cancel()
  clock?.cancel()
  poller = clock = null
  const mine = ++epoch
  const isWorker = (await $.env.get('HARNESS_ROLE')) === 'worker'
  const root = isWorker ? null : await findHarnessRoot(await $.session.cwd(), p => $.fs.exists(p))
  if (root === null) return // not a harness conductor: no polling, no row

  const schedule = (ms: number) => {
    if (mine !== epoch) return
    poller = $.clock.after(ms, () => void poll())
  }
  // A clock for the elapsed times, only while something runs.
  const syncClock = (isRunning: boolean) => {
    if (isRunning && clock === null) {
      clock = $.clock.every(1000, () => void update($, now, () => Date.now()).catch(() => {}))
    } else if (!isRunning && clock !== null) {
      clock.cancel()
      clock = null
    }
  }
  // One poll. Every stage that can throw is caught and shown as the dim `harness-workers: <reason>` row,
  // and the next poll is scheduled in `finally`, so the loop never dies silently.
  const poll = async (): Promise<void> => {
    if (mine !== epoch || isPolling) return
    isPolling = true
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
      if (mine !== epoch) return
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
      isPolling = false
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
    if (sessionEndAction(e.reason) === 'retire') {
      epoch++
      poller?.cancel()
      clock?.cancel()
      poller = clock = null
    } else if (poller === null && clock === null) {
      await start($)
    }
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
