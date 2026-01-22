---
title: Use Promise.all() for Independent Operations
impact: CRITICAL
section: async
tags: [async, promises, parallel, waterfall]
improvement: "2-10x improvement"
---

# Use Promise.all() for Independent Operations

**Impact:** CRITICAL
**Improvement:** 2-10x faster execution

## Description

When async operations have no interdependencies, execute them concurrently using `Promise.all()`. Sequential awaiting of independent operations creates unnecessary waterfalls that compound network latency.

## Problem

Three independent 100ms API calls executed sequentially take 300ms+ total. Each request waits for the previous one to complete, even though they don't depend on each other.

### Bad Example

```typescript
// Three separate round trips - each waits for the previous
async function loadDashboard(userId: string) {
  const user = await fetchUser(userId);        // 100ms
  const posts = await fetchPosts(userId);      // 100ms (starts after user)
  const comments = await fetchComments(userId); // 100ms (starts after posts)

  // Total: ~300ms minimum
  return { user, posts, comments };
}
```

## Solution

Use `Promise.all()` to execute independent operations in parallel. All requests start immediately and resolve when the slowest one completes.

### Good Example

```typescript
// Single round trip - all requests start simultaneously
async function loadDashboard(userId: string) {
  const [user, posts, comments] = await Promise.all([
    fetchUser(userId),      // 100ms
    fetchPosts(userId),     // 100ms (concurrent)
    fetchComments(userId),  // 100ms (concurrent)
  ]);

  // Total: ~100ms (slowest request time)
  return { user, posts, comments };
}
```

## When to Use Sequential Awaits

Only use sequential awaits when operations have dependencies:

```typescript
// Correct: Token needed for subsequent requests
async function loadUserWithAuth() {
  const token = await getAuthToken();           // Must complete first
  const user = await fetchUser(token);          // Needs token

  // These two can be parallel after getting user
  const [posts, settings] = await Promise.all([
    fetchPosts(user.id),
    fetchSettings(user.id),
  ]);

  return { user, posts, settings };
}
```

## Why It Matters

- **Network latency compounds**: 3 sequential 100ms requests = 300ms+
- **Server capacity**: Parallel requests can be processed by different servers
- **User experience**: Faster page loads, less time staring at spinners
- **Mobile networks**: High latency makes this optimization even more critical

## Related Rules

- `async-suspense.md` - React Suspense for parallel data loading
- `async-preload.md` - Preloading critical resources

## References

- [MDN: Promise.all()](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/all)
- [web.dev: Optimize long tasks](https://web.dev/articles/optimize-long-tasks)
