---
name: ui-development
description: React component implementation specialist. Creates TypeScript components with Tailwind CSS, integrates Zustand stores, ensures accessibility, and maintains 90%+ test coverage. Use when building React components, implementing UI, working with Tailwind, or creating frontend interfaces. Triggers on "React", "component", "UI", "Tailwind", "frontend", "interface", "form", "button", "modal", "Storybook".
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(npm:*)
---

# UI Development Skill - React Component Implementation

## Memory-First Protocol (MANDATORY)

Before starting any task:
1. Query Memory MCP for component patterns and styles: `mcp__memory__search_nodes`
2. Load related component entities: `mcp__memory__open_nodes`

During task execution:
- Create component entities: `mcp__memory__create_entities` with type "Component"
- Add implementation details as observations: `mcp__memory__add_observations`
- Link components to stores and pages: `mcp__memory__create_relations`

## Core Competencies

### 1. React Component Development
- **TypeScript Components**: Create fully typed components with proper interfaces
- **Component Composition**: Use existing patterns (GlassCard, Layout, Header)
- **Hook Integration**: Implement custom hooks and Zustand store connections
- **Error Boundaries**: Add proper error handling for component failures

### 2. Styling & Design System
- **Tailwind CSS**: Apply utility classes following project conventions
- **Responsive Design**: Implement mobile-first layouts with proper breakpoints
- **Dark Mode**: Support light/dark theme switching
- **Animation**: Use Tailwind transitions and CSS animations appropriately

## Component Architecture

### Standard Component Structure
```typescript
interface ComponentProps {
  // Proper TypeScript interfaces
  data: DataType;
  onAction: (item: Item) => void;
  loading?: boolean;
}

export function ComponentName({ data, onAction, loading }: ComponentProps) {
  // Zustand store integration
  const { items, isLoading, error } = useStoreHook();
  
  // Error boundary and loading states
  if (isLoading || loading) return <LoadingSpinner />;
  if (error) return <ErrorMessage error={error} />;
  
  return (
    <Layout title="Page Title">
      <GlassCard>
        {/* Component content */}
      </GlassCard>
    </Layout>
  );
}
```

### Required Patterns
- **GlassCard Container**: Use for all major content sections
- **Layout Wrapper**: Implement proper header and navigation
- **Loading States**: Skeleton screens or spinners during data fetching
- **Error States**: User-friendly error messages with retry options
- **Empty States**: Helpful guidance when no data is available

## Form Implementation

### Standard Form Pattern
```typescript
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { itemSchema } from '../lib/validation';

function ItemForm({ item, onSubmit }: ItemFormProps) {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting }
  } = useForm<ItemFormData>({
    resolver: zodResolver(itemSchema),
    defaultValues: item
  });

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
      <div>
        <label htmlFor="name" className="block text-sm font-medium">
          Name
        </label>
        <input
          {...register('name')}
          className="mt-1 block w-full rounded-md border-gray-300"
        />
        {errors.name && (
          <p className="mt-1 text-sm text-red-600">{errors.name.message}</p>
        )}
      </div>
      <button
        type="submit"
        disabled={isSubmitting}
        className="btn-primary"
      >
        {isSubmitting ? 'Saving...' : 'Save'}
      </button>
    </form>
  );
}
```

## Styling Standards

### Consistent Spacing
Use Tailwind spacing scale: `4, 6, 8, 12, 16, 24`

### Color Palette
Follow existing blue/indigo/purple gradient theme

### Typography
Use established font sizes and weights

### Card Layouts
Apply consistent padding, borders, and shadows

## Component Structure
```
src/components/
├── [Feature]/
│   ├── [Feature]List.tsx     # List view with sorting/filtering
│   ├── [Feature]Form.tsx     # Add/edit form
│   ├── [Feature]Card.tsx     # Individual item display
│   └── index.ts              # Clean exports
```

## Testing Integration
- **Unit Tests**: Create `*.test.tsx` files for all components
- **Storybook Stories**: Implement `*.stories.tsx` for component documentation
- **Accessibility Testing**: Ensure proper ARIA labels and keyboard navigation
- **Visual Regression**: Maintain consistent visual appearance

## Quality Standards

### Component Quality
- **TypeScript Strict**: Zero type errors or warnings
- **Prop Validation**: All props properly typed and documented
- **Error Handling**: Graceful error states with user feedback
- **Performance**: Optimized rendering with proper memoization

### Visual Quality
- **Responsive Design**: Seamless experience across all devices
- **Accessibility**: Full keyboard navigation and screen reader support
- **Visual Consistency**: Matches existing design patterns
- **Loading States**: Smooth transitions and proper feedback

### Testing Coverage
- **Unit Tests**: >90% coverage for all components
- **Storybook Stories**: All components documented with use cases
- **Integration Tests**: Component interaction validation
- **Accessibility Tests**: Automated a11y compliance checking

## Reporting Template

```markdown
## UI Implementation: [Component/Page Name]

### Components Delivered
- List of components created
- TypeScript interfaces implemented
- Storybook stories completed
- Unit tests written

### Quality Validation
- TypeScript strict mode compliance
- ESLint/Prettier formatting
- Accessibility audit results
- Visual consistency verification

### Integration Status
- Store integration completed
- Navigation/routing updated
- Error handling implemented
- Loading states functional

### Testing Results
- Unit test coverage: [XX]%
- Storybook stories functional
- Manual testing completed
- Browser compatibility verified
```
