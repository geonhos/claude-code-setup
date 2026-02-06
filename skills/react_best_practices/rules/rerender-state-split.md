---
title: Split State by Update Frequency
impact: MEDIUM
section: rerender
tags: [state, rerender, performance, hooks]
improvement: "Reduces unnecessary re-renders by 50-80%"
---

# Split State by Update Frequency

**Impact:** MEDIUM
**Improvement:** 50-80% reduction in unnecessary re-renders

## Description

Group state variables by how often they change. When unrelated state values are combined, updating one forces re-renders for components that only depend on the others.

## Problem

Large state objects cause every subscribed component to re-render on any property change, even when they only care about specific properties.

### Bad Example

```typescript
// One large state object
const [state, setState] = useState({
  user: null,           // Changes rarely (on login)
  theme: 'light',       // Changes rarely (user preference)
  searchQuery: '',      // Changes frequently (every keystroke)
  isModalOpen: false,   // Changes frequently (user interaction)
  cartItems: [],        // Changes moderately (add to cart)
});

function Header() {
  // Re-renders on EVERY state change, even searchQuery
  return <div>Welcome, {state.user?.name}</div>;
}

function SearchInput() {
  // This is fine, but triggers re-renders everywhere else
  return (
    <input
      value={state.searchQuery}
      onChange={(e) => setState(s => ({ ...s, searchQuery: e.target.value }))}
    />
  );
}
```

## Solution

Split state by update frequency. Fast-changing values should be separate from stable ones.

### Good Example

```typescript
// Separate state by update frequency
const [user, setUser] = useState<User | null>(null);         // Stable
const [theme, setTheme] = useState('light');                  // Stable
const [searchQuery, setSearchQuery] = useState('');           // Fast
const [isModalOpen, setIsModalOpen] = useState(false);        // Fast
const [cartItems, setCartItems] = useState<CartItem[]>([]);   // Moderate

function Header() {
  // Only re-renders when user changes
  return <div>Welcome, {user?.name}</div>;
}

function SearchInput() {
  // Only affects this component
  return (
    <input
      value={searchQuery}
      onChange={(e) => setSearchQuery(e.target.value)}
    />
  );
}
```

## Using Zustand for Global State

```typescript
import { create } from 'zustand';

// Bad: Monolithic store
const useStore = create((set) => ({
  user: null,
  searchQuery: '',
  setSearchQuery: (q) => set({ searchQuery: q }),
}));

// Good: Split stores or use selectors
const useUserStore = create((set) => ({
  user: null,
  setUser: (user) => set({ user }),
}));

const useSearchStore = create((set) => ({
  query: '',
  setQuery: (query) => set({ query }),
}));

// Or use shallow comparison with selectors
import { shallow } from 'zustand/shallow';

function Header() {
  // Only subscribes to user
  const user = useStore((state) => state.user);
  return <div>Welcome, {user?.name}</div>;
}
```

## Context Splitting Pattern

```typescript
// Bad: One large context
const AppContext = createContext({
  user: null,
  theme: 'light',
  searchQuery: '',
});

// Good: Split contexts
const UserContext = createContext<User | null>(null);
const ThemeContext = createContext<'light' | 'dark'>('light');
const SearchContext = createContext({ query: '', setQuery: () => {} });

// Components only subscribe to what they need
function Header() {
  const user = useContext(UserContext);
  return <div>Welcome, {user?.name}</div>;
}
```

## State Frequency Classification

| Frequency | Examples | Strategy |
|-----------|----------|----------|
| Stable | User, settings, permissions | Separate state/context |
| Moderate | Cart, notifications | Separate state |
| Fast | Search input, form fields, hover | Local state, debounce |
| Very Fast | Mouse position, scroll | Refs, no state |

## Why It Matters

- **React re-renders**: Any state change re-renders the component and children
- **Cascading updates**: Combined state causes unnecessary cascading re-renders
- **Virtual DOM work**: More re-renders = more reconciliation work
- **User experience**: Sluggish UI from excessive re-renders

## Related Rules

- `rerender-memo.md` - Using useMemo for expensive calculations
- `rerender-callback.md` - Stable callback references with useCallback

## References

- [React Docs: Choosing State Structure](https://react.dev/learn/choosing-the-state-structure)
- [Zustand: Prevent Re-renders](https://docs.pmnd.rs/zustand/guides/prevent-rerenders-with-useShallow)
