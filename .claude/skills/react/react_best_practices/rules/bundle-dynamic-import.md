---
title: Use Dynamic Imports for Heavy Components
impact: CRITICAL
section: bundle
tags: [bundle, dynamic-import, code-splitting, lazy-loading]
improvement: "30-70% initial bundle reduction"
---

# Use Dynamic Imports for Heavy Components

**Impact:** CRITICAL
**Improvement:** 30-70% initial bundle size reduction

## Description

Use dynamic imports to split heavy components into separate chunks that load on demand. This reduces initial bundle size and improves Time to Interactive (TTI).

## Problem

Static imports include all code in the main bundle, even components that users may never see. Charts, rich text editors, and modals often add 100KB+ to your initial bundle.

### Bad Example

```typescript
// All components loaded immediately
import HeavyChart from './HeavyChart';      // 150KB
import RichTextEditor from './RichTextEditor'; // 200KB
import AdminPanel from './AdminPanel';       // 100KB

function Dashboard() {
  const [showChart, setShowChart] = useState(false);

  return (
    <div>
      <button onClick={() => setShowChart(true)}>Show Chart</button>
      {showChart && <HeavyChart />}
    </div>
  );
}
```

## Solution

Use `React.lazy()` with `Suspense` or Next.js `dynamic()` for components that aren't needed immediately.

### Good Example (React)

```typescript
import { lazy, Suspense, useState } from 'react';

// Loaded only when needed
const HeavyChart = lazy(() => import('./HeavyChart'));
const RichTextEditor = lazy(() => import('./RichTextEditor'));

function Dashboard() {
  const [showChart, setShowChart] = useState(false);

  return (
    <div>
      <button onClick={() => setShowChart(true)}>Show Chart</button>
      {showChart && (
        <Suspense fallback={<ChartSkeleton />}>
          <HeavyChart />
        </Suspense>
      )}
    </div>
  );
}
```

### Good Example (Next.js)

```typescript
import dynamic from 'next/dynamic';

// Client-only component with loading state
const HeavyChart = dynamic(() => import('./HeavyChart'), {
  loading: () => <ChartSkeleton />,
  ssr: false, // Disable SSR for client-only components
});

// Preload on hover for better UX
const AdminPanel = dynamic(() => import('./AdminPanel'), {
  loading: () => <AdminSkeleton />,
});

function Dashboard() {
  return (
    <div>
      <button
        onMouseEnter={() => {
          // Preload when user hovers
          import('./AdminPanel');
        }}
      >
        Open Admin
      </button>
      <HeavyChart />
    </div>
  );
}
```

## When to Use Dynamic Imports

| Component Type | Example | Recommend Dynamic? |
|---------------|---------|-------------------|
| Route pages | `/admin`, `/settings` | Yes |
| Heavy visualizations | Charts, maps, 3D | Yes |
| Rich text editors | Draft.js, TipTap | Yes |
| Modals/Dialogs | Confirmation dialogs | Maybe |
| Below-the-fold content | Footer, comments | Yes |
| Core UI | Button, Input | No |

## Preloading Strategies

```typescript
// Preload on route hover (Next.js)
import Link from 'next/link';

<Link href="/admin" prefetch={true}>
  Admin Panel
</Link>

// Preload on visibility (Intersection Observer)
function LazySection() {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const observer = new IntersectionObserver((entries) => {
      if (entries[0].isIntersecting) {
        import('./HeavyComponent');
      }
    });
    if (ref.current) observer.observe(ref.current);
    return () => observer.disconnect();
  }, []);

  return <div ref={ref} />;
}
```

## Why It Matters

- **Faster initial load**: Main bundle loads faster
- **Better Core Web Vitals**: Improved LCP and TTI
- **Bandwidth savings**: Users only download what they use
- **Caching**: Smaller chunks = better cache utilization

## Related Rules

- `bundle-direct-imports.md` - Direct imports for tree-shaking
- `bundle-third-party.md` - Defer third-party scripts

## References

- [React Lazy Loading](https://react.dev/reference/react/lazy)
- [Next.js Dynamic Imports](https://nextjs.org/docs/pages/building-your-application/optimizing/lazy-loading)
