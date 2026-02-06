# Performance Optimization Sections

Rules are organized into 8 sections, ranked by performance impact.

---

## 1. Eliminating Waterfalls

**Prefix:** `async-`
**Impact:** CRITICAL
**Description:** Waterfalls are the #1 performance killer. Sequential awaits compound network latency, turning three 100ms requests into 300ms+ total time.

**Key Patterns:**
- `Promise.all()` for independent operations
- Suspense boundaries for parallel data loading
- Preloading critical resources

---

## 2. Bundle Size Optimization

**Prefix:** `bundle-`
**Impact:** CRITICAL
**Description:** Reducing initial payload directly improves Time to Interactive (TTI) and Largest Contentful Paint (LCP). Every kilobyte counts on mobile networks.

**Key Patterns:**
- Direct imports instead of barrel exports
- Dynamic imports for route-based splitting
- Deferred loading for third-party scripts

---

## 3. Server-Side Performance

**Prefix:** `server-`
**Impact:** HIGH
**Description:** Server rendering bottlenecks affect Time to First Byte (TTFB) and overall page load experience.

**Key Patterns:**
- React `cache()` for request deduplication
- LRU caching for expensive computations
- Data minimization (only fetch what you need)

---

## 4. Client-Side Data Fetching

**Prefix:** `client-`
**Impact:** MEDIUM-HIGH
**Description:** Efficient client-side data management reduces redundant network requests and improves perceived performance.

**Key Patterns:**
- SWR/TanStack Query for automatic caching
- Stale-while-revalidate strategies
- Event listener deduplication

---

## 5. Re-render Optimization

**Prefix:** `rerender-`
**Impact:** MEDIUM
**Description:** Unnecessary re-renders waste CPU cycles and can cause visible jank, especially on lower-end devices.

**Key Patterns:**
- State splitting by update frequency
- `useMemo` for expensive calculations
- `useTransition` for non-urgent updates

---

## 6. Rendering Performance

**Prefix:** `rendering-`
**Impact:** MEDIUM
**Description:** Browser rendering optimizations reduce layout thrashing and improve paint performance.

**Key Patterns:**
- CSS containment (`contain: layout paint`)
- `content-visibility: auto` for off-screen content
- SVG sprites over inline SVGs

---

## 7. JavaScript Performance

**Prefix:** `js-`
**Impact:** LOW-MEDIUM
**Description:** Micro-optimizations for hot code paths that execute frequently.

**Key Patterns:**
- DOM update batching
- Map/Set for O(1) lookups
- Efficient iteration patterns

---

## 8. Advanced Patterns

**Prefix:** `advanced-`
**Impact:** LOW
**Description:** Specialized techniques for edge cases and complex scenarios.

**Key Patterns:**
- Refs for non-rendering values
- Callback refs for DOM measurements
- Custom hook optimization patterns
