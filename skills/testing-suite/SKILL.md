---
name: testing-suite
description: "QA specialist for tests: unit tests with Vitest, E2E tests with Playwright, Storybook visual tests and accessibility checks (WCAG 2.1 AA), targeting 80%+ line coverage (branch 75%+, function 80%+). Use when writing tests, checking coverage or validating code quality or accessibility."
allowed-tools: Read, Glob, Grep, Bash(npm test:*), Bash(npm run test:*), Bash(npx vitest:*), Bash(npx playwright:*)
---

# Testing Suite Skill - Quality Assurance Specialist

## Memory-First Protocol (MANDATORY)

Before starting any task:
1. Query Memory MCP for testing patterns and history: `mcp__memory__search_nodes`
2. Load related test entities and coverage data: `mcp__memory__open_nodes`

During task execution:
- Create test entities: `mcp__memory__create_entities` with type "Test Suite" or "Test Results"
- Add coverage metrics as observations: `mcp__memory__add_observations`
- Link tests to components and features: `mcp__memory__create_relations`

## Core Responsibilities

### 1. Test Implementation
- **Unit tests** with Vitest and React Testing Library
- **Integration tests** for complex workflows
- **E2E tests** with Playwright for user scenarios
- **Visual tests** with Storybook for components
- **Performance tests** for critical paths

### 2. Quality Assurance Standards
- **Meet the coverage targets in `rules/testing-quality.md`** (line ≥80%, branch ≥75%, function ≥80%) across all modules
- **Test edge cases** and error scenarios thoroughly
- **Verify accessibility compliance** (WCAG 2.1 AA)
- **Check responsive behavior** across devices
- **Validate security measures** in authentication flows

### 3. Framework Detection
Automatically identify and configure testing frameworks:
- Detect existing test frameworks (Jest, Vitest, Cypress, Playwright)
- Analyze package.json dependencies
- Configure testing environment based on project setup

## Testing Technology Stack

### Unit Testing with Vitest
```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

describe('ComponentName', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders correctly with props', () => {
    render(<ComponentName prop="value" />);
    expect(screen.getByRole('button')).toBeInTheDocument();
  });

  it('handles user interactions', async () => {
    const mockHandler = vi.fn();
    render(<ComponentName onClick={mockHandler} />);
    
    await userEvent.click(screen.getByRole('button'));
    expect(mockHandler).toHaveBeenCalledTimes(1);
  });
});
```

### E2E Testing with Playwright
```typescript
import { test, expect, Page } from '@playwright/test';

test.describe('Feature Flow', () => {
  test('complete user journey', async ({ page }) => {
    await page.goto('/app');
    await page.fill('[data-testid="email"]', 'test@example.com');
    await page.click('[data-testid="login-button"]');
    await expect(page).toHaveURL('/dashboard');
  });
});
```

### Visual Testing with Storybook
```typescript
import type { Meta, StoryObj } from '@storybook/react';
import { within, userEvent, expect } from '@storybook/test';

const meta: Meta<typeof Component> = {
  title: 'Components/ComponentName',
  component: Component,
  parameters: { layout: 'centered' },
  tags: ['autodocs'],
};

export default meta;
```

## Coverage Requirements

```typescript
// vitest.config.ts - Enforce the coverage floors of rules/testing-quality.md
export default defineConfig({
  test: {
    coverage: {
      thresholds: {
        global: {
          branches: 75,
          functions: 80,
          lines: 80,
          statements: 80
        }
      }
    }
  }
});
```

## Quality Gates Checklist

- [ ] Coverage floors met (line 80%+, branch 75%+, function 80%+): All code paths tested
- [ ] Zero Flaky Tests: Consistent test execution
- [ ] Performance Benchmarks: Tests complete in <60s
- [ ] Accessibility Tests: WCAG 2.1 AA compliance
- [ ] Security Tests: Authentication and authorization
- [ ] Error Scenarios: Failure modes covered

## Test Commands

```bash
# Unit tests
npm test                   # Uses detected primary framework
npm run test:watch         # Watch mode
npm run test:coverage      # Coverage report

# E2E tests
npm run test:e2e           # Headless
npm run test:e2e:headed    # With browser UI
npm run test:e2e:ui        # Playwright test UI

# Visual tests
npm run storybook          # Development
npm run test:storybook     # Run visual tests
```

## Error Reporting Template

```markdown
## Test Failure Report

**Test**: ComponentName > User Interactions > handles click events
**File**: src/components/ComponentName.test.tsx
**Status**: FAILING

**Error Details**:
Expected: onClick handler to be called
Received: onClick handler was not called

**Analysis**:
The onClick prop is not properly bound to the button element.

**Suggested Fix**:
Verify onClick={onClick} prop is passed to <button> in ComponentName.tsx:42
```

## Best Practices

1. **Descriptive Names**: Clear test intent and expectations
2. **Arrange-Act-Assert**: Consistent test structure
3. **Single Responsibility**: One concept per test
4. **Independent Tests**: No shared state or dependencies
5. **Fast Execution**: Optimize for quick feedback
