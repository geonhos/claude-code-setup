---
name: react_setup
description: Sets up React/TypeScript project with Vite, Feature-Sliced Design structure, TanStack Query, and essential tooling.
model: haiku
---

# React Project Setup Skill

Sets up a React/TypeScript project with FSD structure and working state.

## Prerequisites

- Node.js 18+ installed
- npm or pnpm
- Git initialized

## Workflow

### 1. Create Project

```bash
# Create React + TypeScript project with Vite
npm create vite@latest ${PROJECT_NAME} -- --template react-ts

cd ${PROJECT_NAME}

# Install dependencies
npm install
```

### 2. Install Core Dependencies

```bash
# State Management & Data Fetching
npm install @tanstack/react-query zustand

# Routing
npm install react-router-dom

# Forms & Validation
npm install react-hook-form @hookform/resolvers zod

# UI & Styling
npm install tailwindcss postcss autoprefixer
npm install clsx tailwind-merge

# HTTP Client
npm install axios

# Dev Dependencies
npm install -D @types/node
npm install -D @testing-library/react @testing-library/jest-dom @testing-library/user-event
npm install -D vitest jsdom @vitest/coverage-v8
npm install -D eslint-plugin-react-hooks eslint-plugin-react-refresh
npm install -D prettier eslint-config-prettier
```

### 3. Create Feature-Sliced Design Structure

```bash
# FSD directory structure
mkdir -p src/{app,pages,widgets,features,entities,shared}

# App layer
mkdir -p src/app/{providers,styles}

# Pages layer
mkdir -p src/pages/{home,not-found}

# Shared layer
mkdir -p src/shared/{ui,lib,api,config,types}
mkdir -p src/shared/ui/{button,input,modal}

# Create initial files
touch src/shared/lib/cn.ts
touch src/shared/api/client.ts
touch src/shared/config/env.ts
```

### 4. Configure Tailwind CSS

```bash
npx tailwindcss init -p
```

**tailwind.config.js:**
```javascript
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
```

**src/app/styles/index.css:**
```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

### 5. Configure TypeScript

**tsconfig.json:**
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"],
      "@app/*": ["./src/app/*"],
      "@pages/*": ["./src/pages/*"],
      "@widgets/*": ["./src/widgets/*"],
      "@features/*": ["./src/features/*"],
      "@entities/*": ["./src/entities/*"],
      "@shared/*": ["./src/shared/*"]
    }
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

**vite.config.ts:**
```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      '@app': path.resolve(__dirname, './src/app'),
      '@pages': path.resolve(__dirname, './src/pages'),
      '@widgets': path.resolve(__dirname, './src/widgets'),
      '@features': path.resolve(__dirname, './src/features'),
      '@entities': path.resolve(__dirname, './src/entities'),
      '@shared': path.resolve(__dirname, './src/shared'),
    },
  },
})
```

### 6. Utility Functions

**src/shared/lib/cn.ts:**
```typescript
import { type ClassValue, clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

**src/shared/api/client.ts:**
```typescript
import axios from 'axios';

export const apiClient = axios.create({
  baseURL: import.meta.env.VITE_API_URL || '/api',
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json',
  },
});

apiClient.interceptors.response.use(
  (response) => response,
  (error) => {
    console.error('API Error:', error);
    return Promise.reject(error);
  }
);
```

### 7. App Providers

**src/app/providers/index.tsx:**
```typescript
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter } from 'react-router-dom';
import { ReactNode } from 'react';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5,
      retry: 1,
    },
  },
});

interface ProvidersProps {
  children: ReactNode;
}

export function Providers({ children }: ProvidersProps) {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        {children}
      </BrowserRouter>
    </QueryClientProvider>
  );
}
```

### 8. App Entry Point

**src/app/index.tsx:**
```typescript
import { Providers } from './providers';
import { AppRouter } from './router';
import './styles/index.css';

export function App() {
  return (
    <Providers>
      <AppRouter />
    </Providers>
  );
}
```

**src/app/router.tsx:**
```typescript
import { Routes, Route } from 'react-router-dom';
import { HomePage } from '@pages/home';
import { NotFoundPage } from '@pages/not-found';

export function AppRouter() {
  return (
    <Routes>
      <Route path="/" element={<HomePage />} />
      <Route path="*" element={<NotFoundPage />} />
    </Routes>
  );
}
```

### 9. Sample Pages

**src/pages/home/index.tsx:**
```typescript
export function HomePage() {
  return (
    <div className="min-h-screen flex items-center justify-center">
      <h1 className="text-4xl font-bold text-gray-900">
        Welcome to {import.meta.env.VITE_APP_NAME || 'React App'}
      </h1>
    </div>
  );
}
```

**src/pages/not-found/index.tsx:**
```typescript
import { Link } from 'react-router-dom';

export function NotFoundPage() {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center">
      <h1 className="text-6xl font-bold text-gray-900">404</h1>
      <p className="text-xl text-gray-600 mt-4">Page not found</p>
      <Link to="/" className="mt-8 text-blue-600 hover:underline">
        Go home
      </Link>
    </div>
  );
}
```

### 10. Vitest Configuration

**vitest.config.ts:**
```typescript
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './src/test/setup.ts',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html'],
    },
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      '@shared': path.resolve(__dirname, './src/shared'),
    },
  },
});
```

**src/test/setup.ts:**
```typescript
import '@testing-library/jest-dom';
```

### 11. Package.json Scripts

```json
{
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview",
    "test": "vitest",
    "test:coverage": "vitest run --coverage",
    "lint": "eslint . --ext ts,tsx --report-unused-disable-directives --max-warnings 0",
    "format": "prettier --write \"src/**/*.{ts,tsx}\""
  }
}
```

### 12. Verify Setup

```bash
# Run development server
npm run dev

# Run tests
npm test

# Build
npm run build
```

## Generated Structure

```
${PROJECT_NAME}/
├── public/
├── src/
│   ├── app/
│   │   ├── providers/
│   │   │   └── index.tsx
│   │   ├── styles/
│   │   │   └── index.css
│   │   ├── index.tsx
│   │   └── router.tsx
│   ├── pages/
│   │   ├── home/
│   │   │   └── index.tsx
│   │   └── not-found/
│   │       └── index.tsx
│   ├── widgets/
│   ├── features/
│   ├── entities/
│   ├── shared/
│   │   ├── ui/
│   │   ├── lib/
│   │   │   └── cn.ts
│   │   ├── api/
│   │   │   └── client.ts
│   │   ├── config/
│   │   └── types/
│   ├── test/
│   │   └── setup.ts
│   └── main.tsx
├── index.html
├── package.json
├── tsconfig.json
├── vite.config.ts
├── vitest.config.ts
└── tailwind.config.js
```

## Verification Checklist

- [ ] `npm run dev` displays page
- [ ] `npm test` passes
- [ ] `npm run build` succeeds
- [ ] Path aliases work correctly
- [ ] Tailwind CSS applied

## Summary Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
React Project Setup Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Project: ${PROJECT_NAME}
React: 18+
TypeScript: 5+
Vite: 5+

- FSD structure created
- TanStack Query configured
- Tailwind CSS configured
- Vitest configured
- Path aliases configured

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Next Steps:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Add features in src/features/
2. Create shared UI components
3. Implement pages with routing
4. Add API integration

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
