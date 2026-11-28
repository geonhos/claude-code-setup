// harness-workers: worker progress above the prompt, read from `harness status --json --all`.
// Wiring only: parsing, row selection, layout and notification decisions live in ./model.ts.
// Draws only: nothing here writes a file or puts text into the conversation.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { Snapshot } from '../types'
import { anyRunning, diffSnapshots, failureLine, layout, parseStatus, selectWorkers } from './model'

const FAST_MS = 3_000 // while a worker runs
const SLOW_MS = 30_000 // otherwise, and after a failed poll
const RUN_TIMEOUT_MS = 10_000
const MAX_BAND_ROWS = 12
const KEEP_DEAD_S = 300 // how long a dead worker's stop time is remembered

// Held by the host, so the state survives a hot reload of this file.
const snapshot = atom({ plugin: 'harness-workers', key: 'snapshot' } as const, null as Snapshot | null)
const now = atom({ plugin: 'harness-workers', key: 'now' } as const, 0)
const expanded = atom({ plugin: 'harness-workers', key: 'expanded' } as const, false)
const deadAt = atom({ plugin: 'harness-workers', key: 'deadAt' } as const, {} as Record<string, number>)

const nowS = () => Math.floor(Date.now() / 1000)

type Dollar = EngineInterface

/** `harness` from PATH, else the install location of install.sh. */
async function runStatus($: Dollar): Promise<{ exitCode: number; stdout: string } | string> {
  const argv = ['status', '--json', '--all']
  const home = await $.env.get('HOME')
  const bins = ['harness', ...(home ? [`${home}/.local/bin/harness`] : [])]
  let last = 'harness status did not run'
  for (const bin of bins) {
    try {
      const r = await $.process.run([bin, ...argv], { timeoutMs: RUN_TIMEOUT_MS })
      return { exitCode: r.exitCode, stdout: r.stdout }
    } catch (err) {
      last = /still running|timed? ?out/i.test(String(err)) ? 'harness status timed out' : 'harness status did not run'
      if (last === 'harness status timed out') break
    }
  }
  return last
}

export const register: Register = on => {
  let poller: Timer | null = null
  let clock: Timer | null = null
  let isPolling = false // a slow run must not let two polls overlap
  let epoch = 0 // a reload or a new session start retires the loop of the old one

  on('session.start', async ($, e, next) => {
    const r = await next(e)
    poller?.cancel()
    clock?.cancel()
    poller = clock = null
    const mine = ++epoch
    const isWorker = (await $.env.get('HARNESS_ROLE')) === 'worker'
    const cwd = await $.session.cwd()
    if (isWorker || !(await $.fs.exists(`${cwd}/.harness/asks`))) return r // not a harness conductor: no polling, no row

    const schedule = (ms: number) => {
      if (mine !== epoch) return
      poller = $.clock.after(ms, () => void poll().catch(() => {}))
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
    const poll = async (): Promise<void> => {
      if (mine !== epoch || isPolling) return
      isPolling = true
      let fresh: Snapshot
      try {
        const out = await runStatus($)
        if (typeof out === 'string') fresh = { ok: false, reason: out }
        else if (out.exitCode !== 0) fresh = { ok: false, reason: `harness status failed (rc ${out.exitCode})` }
        else fresh = parseStatus(out.stdout)
      } catch (err) {
        fresh = { ok: false, reason: 'harness status failed' }
      } finally {
        isPolling = false
      }
      if (mine !== epoch) return
      const t = nowS()
      if (fresh.ok) {
        const prev = await read($, snapshot)
        const d = diffSnapshots(prev, fresh, t)
        await update($, deadAt, old => {
          const merged = { ...old, ...d.deadAt }
          for (const k of Object.keys(merged)) if (t - merged[k]! > KEEP_DEAD_S) delete merged[k]
          return merged
        })
        for (const ev of d.events) {
          $.ui.toast(ev.text)
          if (ev.notify) void $.ui.notify(ev.text, { title: 'harness-workers', key: `harness-workers:${ev.key}` }).catch(() => {})
        }
      }
      await update($, snapshot, () => fresh)
      await update($, now, () => Date.now())
      const running = fresh.ok && anyRunning(fresh)
      syncClock(running)
      schedule(running ? FAST_MS : SLOW_MS)
    }
    void poll().catch(() => {})
    return r
  })

  on('session.end', async (_$, e, next) => {
    epoch++
    poller?.cancel()
    clock?.cancel()
    poller = clock = null
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
