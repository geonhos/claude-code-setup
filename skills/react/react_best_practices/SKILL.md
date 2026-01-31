---
name: react_best_practices
description: React/Next.js performance optimization guide with 45+ rules across 8 categories
model: haiku
---

# React Best Practices

Comprehensive performance optimization guide for React and Next.js applications.

## When to Reference

- Writing new React components or Next.js pages
- Implementing data fetching patterns
- Reviewing code for performance issues
- Refactoring existing React/Next.js code
- Optimizing bundle size or load times

## Priority Categories

| Priority | Section | Description |
|----------|---------|-------------|
| CRITICAL | Eliminating Waterfalls | Sequential awaits compound network latency |
| CRITICAL | Bundle Size | Reduces Time to Interactive and LCP |
| HIGH | Server Performance | Server rendering and data fetching |
| MEDIUM-HIGH | Client Data Fetching | Request deduplication and caching |
| MEDIUM | Re-render Optimization | Unnecessary component updates |
| MEDIUM | Rendering Performance | Browser rendering workflows |
| LOW-MEDIUM | JavaScript Performance | Hot code path optimization |
| LOW | Advanced Patterns | Specialized edge case techniques |

## Quick Reference

### 1. Eliminating Waterfalls (CRITICAL)

```typescript
// Bad: Sequential requests
const user = await fetchUser();
const posts = await fetchPosts();
const comments = await fetchComments();

// Good: Parallel requests
const [user, posts, comments] = await Promise.all([
  fetchUser(),
  fetchPosts(),
  fetchComments()
]);
```

### 2. Bundle Size (CRITICAL)

```typescript
// Bad: Full library import
import { format } from 'date-fns';

// Good: Direct import
import format from 'date-fns/format';
```

```typescript
// Bad: Static import for large components
import HeavyChart from './HeavyChart';

// Good: Dynamic import
const HeavyChart = dynamic(() => import('./HeavyChart'), {
  loading: () => <ChartSkeleton />
});
```

### 3. Server Performance (HIGH)

```typescript
// Use React cache for expensive operations
import { cache } from 'react';

export const getUser = cache(async (id: string) => {
  const user = await db.user.findUnique({ where: { id } });
  return user;
});
```

### 4. Client Data Fetching (MEDIUM-HIGH)

```typescript
// Use SWR or TanStack Query for caching
import useSWR from 'swr';

function Profile() {
  const { data, error, isLoading } = useSWR('/api/user', fetcher, {
    revalidateOnFocus: false,
    dedupingInterval: 60000
  });
}
```

### 5. Re-render Optimization (MEDIUM)

```typescript
// Split state to prevent unnecessary re-renders
// Bad: One large state object
const [state, setState] = useState({ user, posts, comments });

// Good: Separate state slices
const [user, setUser] = useState(initialUser);
const [posts, setPosts] = useState(initialPosts);
```

```typescript
// Use useMemo for expensive calculations
const sortedItems = useMemo(
  () => items.sort((a, b) => a.price - b.price),
  [items]
);
```

### 6. Rendering Performance (MEDIUM)

```typescript
// Use CSS containment for independent sections
<div style={{ contain: 'layout paint' }}>
  <ExpensiveComponent />
</div>
```

```typescript
// Prefer CSS over inline styles
// Bad
<div style={{ marginTop: '16px', padding: '8px' }} />

// Good
<div className="mt-4 p-2" />
```

### 7. JavaScript Performance (LOW-MEDIUM)

```typescript
// Batch DOM updates
const updates = items.map(item => updateItem(item));
await Promise.all(updates);

// Use Map/Set for O(1) lookups
const itemMap = new Map(items.map(item => [item.id, item]));
const found = itemMap.get(targetId); // O(1) instead of O(n)
```

### 8. Advanced Patterns (LOW)

```typescript
// Use refs for values that don't need re-renders
const renderCount = useRef(0);
renderCount.current += 1;

// Use callback refs for DOM measurements
const measureRef = useCallback((node: HTMLDivElement | null) => {
  if (node) {
    const { height } = node.getBoundingClientRect();
    setHeight(height);
  }
}, []);
```

## Rules Directory

Individual rules are located in `rules/` directory with detailed explanations and examples.

File naming convention:
- `async-*.md` - Waterfall elimination rules
- `bundle-*.md` - Bundle optimization rules
- `server-*.md` - Server performance rules
- `client-*.md` - Client data fetching rules
- `rerender-*.md` - Re-render optimization rules
- `rendering-*.md` - Rendering performance rules
- `js-*.md` - JavaScript performance rules
- `advanced-*.md` - Advanced pattern rules

Files starting with `_` are metadata files (not rules).

## Verification Checklist

```
[ ] No sequential awaits for independent operations
[ ] Direct imports from libraries (not barrel exports)
[ ] Dynamic imports for heavy components
[ ] React cache for repeated expensive operations
[ ] SWR/TanStack Query for client data fetching
[ ] State split by update frequency
[ ] useMemo for expensive calculations
[ ] CSS containment where appropriate
[ ] No unnecessary inline styles
```

## Summary

```
Priority Guide for Performance Optimization:

1. Fix waterfalls first (biggest wins)
2. Reduce bundle size (improves load time)
3. Optimize server rendering (faster TTFB)
4. Improve client data fetching (better UX)
5. Reduce re-renders (smoother interactions)
6. Fine-tune rendering (polish)
7. Optimize JS (micro-optimizations)
```
