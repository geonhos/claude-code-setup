#!/bin/bash
#
# Agent Progress Hook
# Records SubagentStart/SubagentStop events to track agent activity.
# On SubagentStop, parses the agent transcript to extract actions taken.
#
# Output files (in project cwd):
#   logs/agent-progress.jsonl         — raw event log (machine-parseable)
#   logs/agent-progress-summary.md    — session summary (Claude context)

set -euo pipefail

# Read stdin JSON
INPUT=$(cat)

# Extract fields — use jq if available, otherwise fallback to sed
if command -v jq &>/dev/null; then
  EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
  AGENT=$(echo "$INPUT" | jq -r '.agent_type // "unknown"')
  AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // "unknown"')
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
  CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.agent_transcript_path // empty')
else
  extract() {
    echo "$INPUT" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
  }
  EVENT=$(extract hook_event_name)
  AGENT=$(extract agent_type)
  AGENT_ID=$(extract agent_id)
  SESSION_ID=$(extract session_id)
  CWD=$(extract cwd)
  TRANSCRIPT_PATH=$(extract agent_transcript_path)
  [ -z "$AGENT" ] && AGENT="unknown"
  [ -z "$AGENT_ID" ] && AGENT_ID="unknown"
  [ -z "$SESSION_ID" ] && SESSION_ID="unknown"
  [ -z "$CWD" ] && CWD="."
fi

# Validate event
if [ -z "$EVENT" ]; then
  exit 0
fi

LOGDIR="${CWD}/logs"
JSONL="${LOGDIR}/agent-progress.jsonl"
SUMMARY="${LOGDIR}/agent-progress-summary.md"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S")

mkdir -p "$LOGDIR"

# DEBUG: dump raw hook input (opt-in via AGENT_DEBUG=1)
if [ "${AGENT_DEBUG:-0}" = "1" ]; then
  echo "$INPUT" >> "${LOGDIR}/agent-hook-debug.jsonl"
fi

# Map hook event to log event
case "$EVENT" in
  SubagentStart) LOG_EVENT="start" ;;
  SubagentStop)  LOG_EVENT="stop" ;;
  *)             exit 0 ;;
esac

# ── Filter orphan stop events (no matching start) ──
if [ "$LOG_EVENT" = "stop" ] && [ -z "$AGENT" -o "$AGENT" = "unknown" ]; then
  exit 0
fi

# ── Extract agent actions from transcript on SubagentStop ──
DESCRIPTION=""
TOOLS_USED=""
TOOL_COUNT="0"

if [ "$EVENT" = "SubagentStop" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  if command -v jq &>/dev/null; then
    # Task description: first user message content (string type only)
    DESCRIPTION=$(jq -r 'select(.type == "user" and (.message.content | type) == "string") | .message.content' "$TRANSCRIPT_PATH" 2>/dev/null | head -1 | cut -c1-80 || true)

    # Unique tool names used
    TOOLS_USED=$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .name' "$TRANSCRIPT_PATH" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//' || true)

    # Total tool invocation count
    TOOL_COUNT=$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .name' "$TRANSCRIPT_PATH" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  fi
fi

# ── Append event to JSONL ──
if command -v jq &>/dev/null; then
  if [ "$LOG_EVENT" = "stop" ]; then
    jq -n -c \
      --arg event "$LOG_EVENT" \
      --arg agent "$AGENT" \
      --arg id "$AGENT_ID" \
      --arg session "$SESSION_ID" \
      --arg time "$TIMESTAMP" \
      --arg desc "$DESCRIPTION" \
      --arg tools "$TOOLS_USED" \
      --argjson tool_count "${TOOL_COUNT:-0}" \
      '{event: $event, agent: $agent, id: $id, session: $session, time: $time, description: $desc, tools: $tools, tool_count: $tool_count}' >> "$JSONL"
  else
    jq -n -c \
      --arg event "$LOG_EVENT" \
      --arg agent "$AGENT" \
      --arg id "$AGENT_ID" \
      --arg session "$SESSION_ID" \
      --arg time "$TIMESTAMP" \
      '{event: $event, agent: $agent, id: $id, session: $session, time: $time}' >> "$JSONL"
  fi
else
  if [ "$LOG_EVENT" = "stop" ]; then
    SAFE_DESC=$(printf '%s' "$DESCRIPTION" | sed 's/"/\\"/g' | tr -d '\n')
    echo "{\"event\":\"${LOG_EVENT}\",\"agent\":\"${AGENT}\",\"id\":\"${AGENT_ID}\",\"session\":\"${SESSION_ID}\",\"time\":\"${TIMESTAMP}\",\"description\":\"${SAFE_DESC}\",\"tools\":\"${TOOLS_USED}\",\"tool_count\":${TOOL_COUNT:-0}}" >> "$JSONL"
  else
    echo "{\"event\":\"${LOG_EVENT}\",\"agent\":\"${AGENT}\",\"id\":\"${AGENT_ID}\",\"session\":\"${SESSION_ID}\",\"time\":\"${TIMESTAMP}\"}" >> "$JSONL"
  fi
fi

# ── Regenerate summary on SubagentStop ──
if [ "$EVENT" = "SubagentStop" ]; then

  awk '
  function parse_field(line, field,    pat, val) {
    pat = "\"" field "\":\"([^\"]*)\""
    if (match(line, pat)) {
      val = substr(line, RSTART, RLENGTH)
      gsub("\"" field "\":\"", "", val)
      gsub("\"$", "", val)
      return val
    }
    return ""
  }
  function parse_num(line, field,    pat, val) {
    pat = "\"" field "\":[0-9]+"
    if (match(line, pat)) {
      val = substr(line, RSTART, RLENGTH)
      gsub("\"" field "\":", "", val)
      return val + 0
    }
    return 0
  }
  function to_epoch(ts,    cmd, epoch) {
    cmd = "date -j -f \"%Y-%m-%dT%H:%M:%S\" \"" ts "\" +%s 2>/dev/null"
    if ((cmd | getline epoch) > 0) {
      close(cmd)
      return epoch + 0
    }
    close(cmd)
    cmd = "date -d \"" ts "\" +%s 2>/dev/null"
    if ((cmd | getline epoch) > 0) {
      close(cmd)
      return epoch + 0
    }
    close(cmd)
    return 0
  }
  function truncate(s, maxlen) {
    if (length(s) > maxlen) return substr(s, 1, maxlen) "..."
    return s
  }
  BEGIN {
    total = 0; completed = 0; running = 0
  }
  {
    evt = parse_field($0, "event")
    agent = parse_field($0, "agent")
    id = parse_field($0, "id")
    ts = parse_field($0, "time")

    if (evt == "start") {
      total++
      order[total] = id
      agents[id] = agent
      status[id] = "running"
      start_time[id] = ts
      running++
    } else if (evt == "stop") {
      if (status[id] == "") next
      status[id] = "completed"
      desc[id] = parse_field($0, "description")
      tools[id] = parse_field($0, "tools")
      tool_cnt[id] = parse_num($0, "tool_count")
      s = to_epoch(start_time[id])
      e = to_epoch(ts)
      if (s > 0 && e > 0) {
        dur = e - s
        if (dur >= 60)
          duration[id] = int(dur / 60) "m" (dur % 60) "s"
        else
          duration[id] = dur "s"
      } else {
        duration[id] = "-"
      }
      completed++
      running--
    }
  }
  END {
    print "# Agent Progress (Current Session)"
    print ""
    print "| # | Agent | Status | Duration | Tools | Task |"
    print "|---|-------|--------|----------|-------|------|"
    for (i = 1; i <= total; i++) {
      id = order[i]
      d = (status[id] == "completed") ? duration[id] : "-"
      t = (tool_cnt[id] > 0) ? tools[id] " (" tool_cnt[id] ")" : "-"
      task = (desc[id] != "") ? truncate(desc[id], 50) : "-"
      printf "| %d | %s | %s | %s | %s | %s |\n", i, agents[id], status[id], d, t, task
    }
    print ""
    printf "Total: %d | Completed: %d | Running: %d\n", total, completed, running
  }
  ' "$JSONL" > "$SUMMARY"

  echo "Agent '${AGENT}' completed." >&2
fi
