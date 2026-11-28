// Data types of the harness-workers mod and its `$.state` contract.
// The document it parses is `harness status --json --all`, version 1 (docs/reference.md).

/** `ko` is the Korean step name the brief gave (`[ko: …]`), else null. */
export type Step = { n: number; text: string; ko: string | null }

export type WorkerState = 'running' | 'exited' | 'dead'

/** One worker, reduced to the fields the display reads (hooks/fields.txt lists their source paths). */
export type Worker = {
  /** `<folder path>|<role>`: identifies a worker across polls */
  key: string
  role: string
  state: WorkerState
  /** `#<lane>`, `main`, the branch, or the folder's base name */
  folder: string
  askId: string | null
  startedAt: number | null
  elapsedS: number | null
  turns: number | null
  ctx: number | null
  now: string | null
  /** the brief's `Title-ko:` line, else null */
  titleKo: string | null
  steps: Step[]
  step: number | null
  verify: string | null
  rc: number | null
  verdict: string | null
  durationS: number | null
}

export type Snapshot = { ok: true; workers: Worker[]; generatedAt: number | null } | { ok: false; reason: string }

declare module 'claude-code' {
  interface PluginState {
    'harness-workers': {
      snapshot: Snapshot | null
      /** epoch seconds, moved once a second while a worker runs so elapsed times redraw */
      now: number
      expanded: boolean
      /** worker key -> epoch seconds at which the poll saw it stop (finish time the document lacks) */
      deadAt: Record<string, number>
    }
  }
}
