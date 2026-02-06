---
name: component_generator
description: Generates React components following MVVM pattern with ViewModel hooks, TypeScript interfaces, and tests.
model: haiku
---

# React Component Generator Skill

Generates React components following the MVVM pattern.

## Prerequisites

- React/TypeScript project setup complete
- FSD structure applied

## Workflow

### 1. Gather Component Information

Confirm with user:
- Component name
- Component type (feature/entity/shared)
- Props definition
- State management needs
- API integration needs

### 2. Create File Structure

**Feature Component:**
```
src/features/{feature-name}/
├── components/
│   ├── {ComponentName}.tsx
│   └── {ComponentName}.test.tsx
├── hooks/
│   └── use{Feature}ViewModel.ts
├── api/
│   └── {feature}Api.ts
├── model/
│   ├── types.ts
│   └── schemas.ts
└── index.ts
```

**Shared UI Component:**
```
src/shared/ui/{component-name}/
├── index.tsx
├── {ComponentName}.test.tsx
└── types.ts
```

### 3. Types Definition

**model/types.ts:**
```typescript
export interface {Feature}Data {
  id: string;
  name: string;
  // ... fields
}

export interface {Feature}FormData {
  name: string;
  // ... form fields
}

export interface Use{Feature}ViewModelReturn {
  data: {Feature}Data | null;
  isLoading: boolean;
  error: Error | null;
  handleSubmit: (data: {Feature}FormData) => Promise<void>;
  handleDelete: (id: string) => Promise<void>;
}
```

### 4. Schema Definition (Zod)

**model/schemas.ts:**
```typescript
import { z } from 'zod';

export const {feature}Schema = z.object({
  id: z.string(),
  name: z.string().min(1, 'Name is required'),
  email: z.string().email('Invalid email'),
  // ... validation rules
});

export const {feature}FormSchema = {feature}Schema.omit({ id: true });

export type {Feature}FormData = z.infer<typeof {feature}FormSchema>;
```

### 5. API Layer

**api/{feature}Api.ts:**
```typescript
import { apiClient } from '@shared/api/client';
import type { {Feature}Data, {Feature}FormData } from '../model/types';

const BASE_URL = '/{features}';

export const {feature}Api = {
  getAll: async (): Promise<{Feature}Data[]> => {
    const { data } = await apiClient.get(BASE_URL);
    return data;
  },

  getById: async (id: string): Promise<{Feature}Data> => {
    const { data } = await apiClient.get(`${BASE_URL}/${id}`);
    return data;
  },

  create: async (payload: {Feature}FormData): Promise<{Feature}Data> => {
    const { data } = await apiClient.post(BASE_URL, payload);
    return data;
  },

  update: async (id: string, payload: Partial<{Feature}FormData>): Promise<{Feature}Data> => {
    const { data } = await apiClient.patch(`${BASE_URL}/${id}`, payload);
    return data;
  },

  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`${BASE_URL}/${id}`);
  },
};
```

### 6. ViewModel Hook

**hooks/use{Feature}ViewModel.ts:**
```typescript
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { {feature}Api } from '../api/{feature}Api';
import type { {Feature}FormData, Use{Feature}ViewModelReturn } from '../model/types';

const QUERY_KEY = ['{features}'];

export function use{Feature}ViewModel(id?: string): Use{Feature}ViewModelReturn {
  const queryClient = useQueryClient();

  const { data, isLoading, error } = useQuery({
    queryKey: [...QUERY_KEY, id],
    queryFn: () => id ? {feature}Api.getById(id) : null,
    enabled: !!id,
  });

  const createMutation = useMutation({
    mutationFn: {feature}Api.create,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: QUERY_KEY });
    },
  });

  const deleteMutation = useMutation({
    mutationFn: {feature}Api.delete,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: QUERY_KEY });
    },
  });

  const handleSubmit = async (formData: {Feature}FormData) => {
    await createMutation.mutateAsync(formData);
  };

  const handleDelete = async (targetId: string) => {
    await deleteMutation.mutateAsync(targetId);
  };

  return {
    data: data ?? null,
    isLoading,
    error: error as Error | null,
    handleSubmit,
    handleDelete,
  };
}
```

### 7. Component

**components/{ComponentName}.tsx:**
```typescript
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { use{Feature}ViewModel } from '../hooks/use{Feature}ViewModel';
import { {feature}FormSchema, type {Feature}FormData } from '../model/schemas';
import { Button } from '@shared/ui/button';
import { Input } from '@shared/ui/input';

interface {ComponentName}Props {
  id?: string;
  onSuccess?: () => void;
}

export function {ComponentName}({ id, onSuccess }: {ComponentName}Props) {
  const { data, isLoading, error, handleSubmit: submit } = use{Feature}ViewModel(id);

  const form = useForm<{Feature}FormData>({
    resolver: zodResolver({feature}FormSchema),
    defaultValues: {
      name: '',
    },
  });

  const onSubmit = async (formData: {Feature}FormData) => {
    try {
      await submit(formData);
      form.reset();
      onSuccess?.();
    } catch (e) {
      console.error('Submit failed:', e);
    }
  };

  if (isLoading) {
    return <div className="animate-pulse">Loading...</div>;
  }

  if (error) {
    return <div className="text-red-600">Error: {error.message}</div>;
  }

  return (
    <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
      <div>
        <label htmlFor="name" className="block text-sm font-medium">
          Name
        </label>
        <Input
          id="name"
          {...form.register('name')}
          aria-invalid={!!form.formState.errors.name}
        />
        {form.formState.errors.name && (
          <p className="mt-1 text-sm text-red-600" role="alert">
            {form.formState.errors.name.message}
          </p>
        )}
      </div>

      <Button type="submit" disabled={form.formState.isSubmitting}>
        {form.formState.isSubmitting ? 'Submitting...' : 'Submit'}
      </Button>
    </form>
  );
}
```

### 8. Test

**components/{ComponentName}.test.tsx:**
```typescript
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { {ComponentName} } from './{ComponentName}';
import { {feature}Api } from '../api/{feature}Api';

jest.mock('../api/{feature}Api');

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { retry: false },
  },
});

const wrapper = ({ children }: { children: React.ReactNode }) => (
  <QueryClientProvider client={queryClient}>
    {children}
  </QueryClientProvider>
);

describe('{ComponentName}', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    queryClient.clear();
  });

  it('renders form correctly', () => {
    render(<{ComponentName} />, { wrapper });

    expect(screen.getByLabelText(/name/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /submit/i })).toBeInTheDocument();
  });

  it('validates required fields', async () => {
    const user = userEvent.setup();
    render(<{ComponentName} />, { wrapper });

    await user.click(screen.getByRole('button', { name: /submit/i }));

    await waitFor(() => {
      expect(screen.getByRole('alert')).toHaveTextContent(/required/i);
    });
  });

  it('submits valid form', async () => {
    const user = userEvent.setup();
    const onSuccess = jest.fn();
    ({feature}Api.create as jest.Mock).mockResolvedValue({ id: '1', name: 'Test' });

    render(<{ComponentName} onSuccess={onSuccess} />, { wrapper });

    await user.type(screen.getByLabelText(/name/i), 'Test Name');
    await user.click(screen.getByRole('button', { name: /submit/i }));

    await waitFor(() => {
      expect({feature}Api.create).toHaveBeenCalledWith({ name: 'Test Name' });
      expect(onSuccess).toHaveBeenCalled();
    });
  });
});
```

### 9. Index Export

**index.ts:**
```typescript
export { {ComponentName} } from './components/{ComponentName}';
export { use{Feature}ViewModel } from './hooks/use{Feature}ViewModel';
export type { {Feature}Data, {Feature}FormData } from './model/types';
```

## Component Patterns

### Compound Component
```typescript
// Parent
function Tabs({ children, defaultValue }) {
  const [value, setValue] = useState(defaultValue);
  return (
    <TabsContext.Provider value={{ value, setValue }}>
      {children}
    </TabsContext.Provider>
  );
}

// Attach children
Tabs.List = TabsList;
Tabs.Tab = Tab;
Tabs.Panel = TabPanel;
```

### Headless Component
```typescript
// Hook only
function useDropdown() {
  const [isOpen, setIsOpen] = useState(false);
  return {
    isOpen,
    toggle: () => setIsOpen(!isOpen),
    close: () => setIsOpen(false),
  };
}

// Consumer creates UI
function MyDropdown() {
  const { isOpen, toggle } = useDropdown();
  return <div>...</div>;
}
```

## Verification Checklist

- [ ] Types defined
- [ ] ViewModel hook separated
- [ ] Component handles rendering only
- [ ] Tests written
- [ ] Accessibility attributes applied

## Summary Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Component Generated
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Component: {ComponentName}
Location: src/features/{feature}/
Tests: Included

Files Created:
- components/{ComponentName}.tsx
- components/{ComponentName}.test.tsx
- hooks/use{Feature}ViewModel.ts
- api/{feature}Api.ts
- model/types.ts
- model/schemas.ts
- index.ts

- MVVM pattern applied
- TanStack Query integration
- Form validation with Zod
- Tests with mocking

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
