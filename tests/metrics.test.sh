#!/bin/bash
# Tests for `harness metrics` (JSON/text output, windows, wiki block) against bin/harness.
# Run: /bin/bash tests/metrics.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"
GUARD="perl -e alarm(40);exec(@ARGV)"
msetup() { setup; unset HARNESS_LOG_KEEP HARNESS_LOG_DAYS HARNESS_NOW; }

# --- harness metrics ---
# fixed clock: NOW = 2026-10-29T00:00:00Z -> current window 2026-10-01..2026-10-29, previous 2026-09-03..2026-10-01
NOW=$(perl -MTime::Local -e 'print timegm(0,0,0,29,9,2026)')
msetup
mkdir -p .harness
cat > .harness/progress.jsonl <<'EOF'
{"ts":"2026-10-02T10:00:00Z","agent":"analyst","exit":0,"dur_s":100,"status":"done"}
{"ts":"2026-10-03T10:00:00Z","agent":"analyst","exit":4,"dur_s":600}
{"ts":"2026-10-04T10:00:00Z","agent":"implementer","exit":0,"dur_s":300,"verify":"pass","verify_attempts":1}
{"ts":"2026-10-05T10:00:00Z","agent":"implementer","exit":5,"dur_s":900,"verify":"fail","verify_attempts":3}
{"ts":"2026-10-06T10:00:00Z","agent":"implementer","exit":0,"dur_s":500,"verify":"pass","verify_attempts":2}
{"ts":"2026-10-07T10:00:00Z","agent":"implementer","exit":0,"dur_s":100}
{"ts":"2026-10-08T10:00:00Z","agent":"reviewer","exit":0,"dur_s":50}
{"ts":"2026-10-09T10:00:00Z","agent":"reviewer","exit":5,"dur_s":150}
{"ts":"2026-10-09T10:30:00Z","agent":"reviewer","exit":3,"dur_s":200}
{"ts":"2026-10-10T10:00:00Z","event":"close","role":"implementer","reason":"after_ask"}
this is not json
{"ts":"2026-09-10T10:00:00Z","agent":"analyst","exit":0,"dur_s":40}
{"ts":"2026-09-11T10:00:00Z","agent":"reviewer","exit":5,"dur_s":60}
{"ts":"2026-09-12T10:00:00Z","agent":"reviewer","exit":5,"dur_s":80}
{"ts":"2026-08-01T10:00:00Z","agent":"analyst","exit":0,"dur_s":1}
{"agent":"analyst","exit":0,"dur_s":1}
EOF
export HARNESS_NOW=$NOW
run metrics --json
check "metrics json: rc 0" [ "$RC" -eq 0 ]
J=$OUT
jv() { printf '%s' "$J" | jq -r "$1"; }
check "json: valid" jq -e . <<<"$J" >/dev/null
check "json: window" [ "$(jv '.window.start + " " + .window.end + " " + (.window.days|tostring)')" = "2026-10-01 2026-10-29 28" ]
check "json: previous window" [ "$(jv '.previous.start + " " + .previous.end')" = "2026-09-03 2026-10-01" ]
check "json: asks total" [ "$(jv .current.total.asks)" -eq 9 ]
check "json: asks per role" [ "$(jv '[.current.roles.analyst.asks,.current.roles.implementer.asks,.current.roles.reviewer.asks]|join(",")')" = "2,4,3" ]
check "json: exit distribution" [ "$(jv '.current.total.exit|to_entries|map("\(.key)=\(.value)")|join(",")')" = "0=5,3=1,4=1,5=2" ]
check "json: abnormal total" [ "$(jv .current.total.abnormal)" -eq 2 ]
check "json: abnormal rate total (2/9)" [ "$(jv .current.total.abnormal_rate)" = 22.2 ]
check "json: abnormal rate analyst (1/2)" [ "$(jv .current.roles.analyst.abnormal_rate)" = 50 ]
check "json: abnormal rate implementer" [ "$(jv .current.roles.implementer.abnormal_rate)" = 0 ]
check "json: abnormal rate reviewer (1/3)" [ "$(jv .current.roles.reviewer.abnormal_rate)" = 33.3 ]
check "json: implementer verify-failure rate (1/4)" [ "$(jv .current.roles.implementer.verify_failure_rate)" = 25 ]
check "json: mean verify attempts (old lines skipped)" [ "$(jv .current.roles.implementer.mean_verify_attempts)" = 2 ]
check "json: reviewer FAIL rate (1/3)" [ "$(jv .current.roles.reviewer.fail_rate)" = 33.3 ]
check "json: implementer median/p95" [ "$(jv '"\(.current.roles.implementer.duration_median_s)/\(.current.roles.implementer.duration_p95_s)"')" = "400/900" ]
check "json: analyst median/p95 (600,100)" [ "$(jv '"\(.current.roles.analyst.duration_median_s)/\(.current.roles.analyst.duration_p95_s)"')" = "350/600" ]
check "json: reviewer median/p95" [ "$(jv '"\(.current.roles.reviewer.duration_median_s)/\(.current.roles.reviewer.duration_p95_s)"')" = "150/200" ]
check "json: previous asks" [ "$(jv .prev.total.asks)" -eq 3 ]
check "json: previous reviewer FAIL rate (2/2)" [ "$(jv .prev.roles.reviewer.fail_rate)" = 100 ]
check "json: previous empty role is null" [ "$(jv .prev.roles.implementer.verify_failure_rate)" = null ]
check "json: no retro key" [ "$(jv 'has("retro")')" = false ]
check "json: no wiki -> null" [ "$(jv .wiki)" = null ]

run metrics
check "text: rc 0" [ "$RC" -eq 0 ]
check "text: header" grep -q '^harness metrics  2026-10-01 .. 2026-10-29 (28d)  vs  2026-09-03 .. 2026-10-01' <<<"$OUT"
check "text: asks row" grep -Eq '^  asks +9 +3$' <<<"$OUT"
check "text: abnormal row" grep -Eq 'abnormal rate .* +22.2% +' <<<"$OUT"
check "text: exits line" grep -q 'exits current:  0:5 3:1 4:1 5:2' <<<"$OUT"
check "text: no retro line" bash -c '! grep -q "^retro:" <<<"$1"' _ "$OUT"
check "text: no wiki" grep -q '^wiki: none' <<<"$OUT"

run metrics --since 2026-10-05
check "since: window start" grep -q '2026-10-05 .. 2026-10-29 (24d)  vs  2026-09-11 .. 2026-10-05' <<<"$OUT"
run metrics --since 2099-01-01
check "since: future rc 1" [ "$RC" -eq 1 ]
check "since: future message" grep -q 'in the future' <<<"$OUT"
run metrics --since 2026-02-31
check "since: impossible date rc 1" [ "$RC" -eq 1 ]
run metrics --since nope
check "since: bad date rc 1" [ "$RC" -eq 1 ]
run metrics --bogus
check "metrics: bad flag rc 1" [ "$RC" -eq 1 ]

# empty / missing progress.jsonl
msetup
run metrics --json
check "metrics: no progress file rc 0" [ "$RC" -eq 0 ]
check "metrics: no progress file zero asks" [ "$(printf '%s' "$OUT" | jq -r .current.total.asks)" -eq 0 ]
run metrics
check "metrics: no data text rc 0" [ "$RC" -eq 0 ]

# wiki block
msetup
unset HARNESS_NOW
mkdir -p docs/wiki/troubleshooting
printf -- '---\nstatus: active\n---\n# a\n' > docs/wiki/troubleshooting/a.md
printf -- '---\nstatus: active\n---\n# b\n' > docs/wiki/troubleshooting/b.md
printf -- '---\nstatus: stale\n---\n# c\n' > docs/wiki/troubleshooting/c.md
printf -- '---\nstatus: draft\n---\n# d\n' > docs/wiki/troubleshooting/d.md
printf '# Wiki index\n\n- [a](troubleshooting/a.md) — h (active, 2026-10-21)\n- [b](troubleshooting/b.md) — h (active, 2026-10-21)\n- [c](troubleshooting/c.md) — h (stale, 2026-10-21)\n' > docs/wiki/index.md
printf 'x\n' > docs/wiki/log.md
run metrics --json
J=$OUT
check "wiki: pages" [ "$(jv '.wiki.pages|"\(.active)/\(.stale)/\(.draft)/\(.superseded)/\(.other)"')" = "2/1/1/0/0" ]
check "wiki: index lines" [ "$(jv .wiki.index_lines)" -eq 5 ]
check "wiki: SessionStart bytes = active lines only" [ "$(jv .wiki.session_start_bytes)" -eq "$(grep -F '(active,' docs/wiki/index.md | LC_ALL=C wc -c | tr -d ' ')" ]
run metrics
check "text: wiki pages line" grep -q '^wiki: pages active 2 · stale 1 · draft 1' <<<"$OUT"
check "text: wiki index line" grep -q '^wiki: index 5 lines' <<<"$OUT"

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
