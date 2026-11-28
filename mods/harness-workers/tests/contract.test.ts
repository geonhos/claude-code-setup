// Contract test: the mod's parser against the golden file that tests/dash.test.sh compares the
// real `harness status --json` output with. If the harness changes a field the mod reads, one of
// the two tests fails before the change is committed.
//
// A test module cannot read files, so tests/mod.test.sh copies the mod to a temp dir and writes
// ./golden.ts there from the two real files (tests/fixtures/status-v1.json, hooks/fields.txt).
// Run this test through that suite, not by pointing `claude plugin test` at the repo folder.
import { expect, test } from 'claude-code/testing'

import { layout, parseStatus, selectWorkers } from '../hooks/model'
import { fields, golden } from './golden'

if (golden === '') throw new Error('tests/golden.ts is the empty placeholder: run these tests through bash tests/mod.test.sh')

test('every field path the mod reads exists in the golden', () => {
  const doc = JSON.parse(golden)
  const has = (v: unknown, parts: string[]): boolean => {
    if (parts.length === 0) return true
    const [head = "", ...rest] = parts
    const isArr = head.endsWith('[]')
    const key = isArr ? head.slice(0, -2) : head
    if (typeof v !== 'object' || v === null || !(key in v)) return false
    const child = (v as Record<string, unknown>)[key]
    if (!isArr) return has(child, rest)
    return Array.isArray(child) && child.some(c => has(c, rest))
  }
  const missing = fields.filter(f => !has(doc, f.split('.')))
  expect(missing).toEqual([])
  expect(fields.length).toBeGreaterThan(15)
})

test('the golden parses into the expected rows', () => {
  const s = parseStatus(golden)
  expect(s.ok).toBe(true)
  if (!s.ok) return
  const now = 1795867512 // the golden's generated_at
  expect(s.workers.map(w => [w.role, w.state, w.folder, w.step, w.steps.length, w.rc, w.verify, w.verdict, w.durationS])).toEqual([
    ['analyst', 'running', 'main', null, 0, null, null, null, null],
    ['implementer', 'exited', 'main', 2, 2, 0, 'pass', null, 220],
    ['reviewer', 'exited', 'main', null, 0, 0, null, 'PASS', 220],
  ])
  expect(s.workers[0]).toMatchObject({ askId: 'a-1', startedAt: 1795867260, turns: 2, ctx: 61000, now: 'Run the "dash" suite' })
  // the golden is synthetic: the reviewer's start + duration lies after generated_at, so it counts as just finished
  const rows = selectWorkers(s, now, {})
  expect(rows.map(r => r.role)).toEqual(['analyst', 'reviewer'])
  const lines = layout(rows, { expanded: false, maxRows: 5, columns: 100, nowS: now }).lines.map(l => l.text)
  expect(lines[0]).toBe('● analyst  main  → Run the "dash" suite · 4m12s')
  expect(lines[1]).toContain('exit 0 · PASS')
  // the implementer finished at 1795867432, long before: never shown; the reviewer lingers 60 s from 1795867632
  expect(selectWorkers(s, 1795867632 + 61, {}).map(r => r.role)).toEqual(['analyst'])
})
