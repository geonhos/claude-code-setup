---
title: Use React cache() for Request Deduplication
impact: HIGH
section: server
tags: [server, cache, deduplication, rsc]
improvement: "Eliminates duplicate database/API calls"
---

# Use React cache() for Request Deduplication

**Impact:** HIGH
**Improvement:** Eliminates duplicate database/API calls per request

## Description

Use React's `cache()` function to deduplicate expensive operations within a single request. This prevents the same data from being fetched multiple times when multiple components need it.

## Problem

In React Server Components, multiple components might need the same data. Without caching, each component triggers a separate database query or API call.

### Bad Example

```typescript
// lib/data.ts
export async function getUser(id: string) {
  console.log('Fetching user...'); // Called multiple times!
  return await db.user.findUnique({ where: { id } });
}

// components/Header.tsx
async function Header() {
  const user = await getUser('123'); // DB call #1
  return <h1>Welcome, {user.name}</h1>;
}

// components/Sidebar.tsx
async function Sidebar() {
  const user = await getUser('123'); // DB call #2 (duplicate!)
  return <nav>Settings for {user.email}</nav>;
}

// components/Profile.tsx
async function Profile() {
  const user = await getUser('123'); // DB call #3 (duplicate!)
  return <div>{user.bio}</div>;
}
```

## Solution

Wrap the data fetching function with React's `cache()`. Calls with the same arguments are deduplicated within the request lifecycle.

### Good Example

```typescript
// lib/data.ts
import { cache } from 'react';

export const getUser = cache(async (id: string) => {
  console.log('Fetching user...'); // Called only once!
  return await db.user.findUnique({ where: { id } });
});

// All components can call getUser('123')
// Only one database query is made per request

async function Header() {
  const user = await getUser('123'); // DB call (first call)
  return <h1>Welcome, {user.name}</h1>;
}

async function Sidebar() {
  const user = await getUser('123'); // Cached (no DB call)
  return <nav>Settings for {user.email}</nav>;
}

async function Profile() {
  const user = await getUser('123'); // Cached (no DB call)
  return <div>{user.bio}</div>;
}
```

## Important: Request Scope

`cache()` deduplication is scoped to a single server request. Each new page request gets a fresh cache.

```typescript
// Request 1: User visits /profile
// - getUser('123') called → DB query executed
// - getUser('123') called → cached result returned

// Request 2: Different user visits /profile
// - getUser('456') called → new DB query executed (different args)
// - getUser('123') called → new DB query executed (fresh request)
```

## Combining with Other Caching

```typescript
import { cache } from 'react';
import { unstable_cache } from 'next/cache';

// Request-level deduplication
export const getUser = cache(async (id: string) => {
  return await db.user.findUnique({ where: { id } });
});

// Cross-request caching (Data Cache)
export const getPopularPosts = unstable_cache(
  async () => {
    return await db.post.findMany({
      orderBy: { views: 'desc' },
      take: 10,
    });
  },
  ['popular-posts'],
  { revalidate: 3600 } // Cache for 1 hour
);

// Both together: deduplicated within request + cached across requests
export const getCachedUser = cache(
  unstable_cache(
    async (id: string) => db.user.findUnique({ where: { id } }),
    ['user'],
    { revalidate: 60 }
  )
);
```

## Common Patterns

### Preloading Pattern

```typescript
// Preload data at the top of the tree
export const preload = (userId: string) => {
  void getUser(userId);
  void getUserPosts(userId);
};

// app/dashboard/page.tsx
export default function DashboardPage({ params }) {
  preload(params.userId); // Start fetching immediately

  return (
    <Suspense fallback={<Loading />}>
      <Dashboard userId={params.userId} />
    </Suspense>
  );
}
```

### Current User Pattern

```typescript
// lib/auth.ts
import { cache } from 'react';
import { cookies } from 'next/headers';

export const getCurrentUser = cache(async () => {
  const session = cookies().get('session');
  if (!session) return null;

  return await db.user.findUnique({
    where: { sessionId: session.value }
  });
});

// Use anywhere - only one auth check per request
```

## Why It Matters

- **Database load**: Fewer queries = less database strain
- **Response time**: Eliminate redundant network round trips
- **Cost**: Fewer API calls = lower bills for external services
- **Simplicity**: Components can fetch their own data without coordination

## Related Rules

- `server-lru-cache.md` - LRU caching for expensive computations
- `async-parallel.md` - Parallel data fetching

## References

- [React cache() Reference](https://react.dev/reference/react/cache)
- [Next.js Data Fetching](https://nextjs.org/docs/app/building-your-application/data-fetching)
