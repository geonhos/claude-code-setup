---
title: Use Direct Imports Instead of Barrel Exports
impact: CRITICAL
section: bundle
tags: [bundle, imports, tree-shaking, module]
improvement: "50-90% bundle reduction for libraries"
---

# Use Direct Imports Instead of Barrel Exports

**Impact:** CRITICAL
**Improvement:** 50-90% bundle size reduction for affected libraries

## Description

Import directly from library subpaths instead of the main entry point. Barrel exports (index files that re-export everything) can prevent tree-shaking and include unnecessary code in your bundle.

## Problem

Importing from the main entry point often pulls in the entire library, even if you only use one function. This is especially problematic with large utility libraries like lodash, date-fns, or Material UI.

### Bad Example

```typescript
// Imports entire library (200KB+)
import { format } from 'date-fns';
import { debounce } from 'lodash';
import { Button } from '@mui/material';

function MyComponent() {
  return <Button>{format(new Date(), 'yyyy-MM-dd')}</Button>;
}
```

## Solution

Import directly from the specific module path. Most modern libraries support this pattern.

### Good Example

```typescript
// Only imports what you need (~5KB each)
import format from 'date-fns/format';
import debounce from 'lodash/debounce';
import Button from '@mui/material/Button';

function MyComponent() {
  return <Button>{format(new Date(), 'yyyy-MM-dd')}</Button>;
}
```

## Library-Specific Patterns

### date-fns
```typescript
// Bad
import { format, parseISO, addDays } from 'date-fns';

// Good
import format from 'date-fns/format';
import parseISO from 'date-fns/parseISO';
import addDays from 'date-fns/addDays';
```

### lodash
```typescript
// Bad
import { debounce, throttle, cloneDeep } from 'lodash';

// Good - individual imports
import debounce from 'lodash/debounce';
import throttle from 'lodash/throttle';
import cloneDeep from 'lodash/cloneDeep';

// Good - use lodash-es for ESM tree-shaking
import { debounce } from 'lodash-es';
```

### Material UI
```typescript
// Bad
import { Button, TextField, Dialog } from '@mui/material';

// Good
import Button from '@mui/material/Button';
import TextField from '@mui/material/TextField';
import Dialog from '@mui/material/Dialog';
```

### Icons
```typescript
// Bad - imports all icons
import { Home, Settings, User } from 'lucide-react';

// Good - direct imports
import Home from 'lucide-react/dist/esm/icons/home';

// Better - use library's recommended pattern
import { Home } from 'lucide-react'; // if tree-shaking works
```

## Verifying Bundle Impact

Use bundle analyzer to verify the impact:

```bash
# Next.js
npm install @next/bundle-analyzer
ANALYZE=true npm run build

# Vite
npm install rollup-plugin-visualizer
```

## Why It Matters

- **Initial load time**: Smaller bundles = faster page loads
- **Parse time**: Less JavaScript to parse = faster TTI
- **Memory usage**: Less code in memory
- **Mobile users**: Especially important on slow networks

## Related Rules

- `bundle-dynamic-import.md` - Dynamic imports for code splitting
- `bundle-third-party.md` - Defer non-critical third-party scripts

## References

- [Webpack Tree Shaking](https://webpack.js.org/guides/tree-shaking/)
- [web.dev: Reduce JavaScript payloads](https://web.dev/articles/reduce-javascript-payloads-with-code-splitting)
