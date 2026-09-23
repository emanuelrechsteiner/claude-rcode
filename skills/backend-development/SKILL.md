---
name: backend-development
description: Firebase and state management specialist. Handles Firestore operations, Firebase Functions, Zustand stores, user-scoped security, and optimistic updates with rollback. Use when working with Firebase, Firestore, Cloud Functions, Zustand, state management, APIs, or backend logic. Triggers on "Firebase", "Firestore", "Zustand", "state management", "backend", "API", "Cloud Functions", "security rules", "database", "store", "backend bauen", "datenbank anbinden", "firestore regeln", "cloud function schreiben", "state management einrichten", "api endpunkt bauen", "speichern schlägt fehl".
allowed-tools: Read, Edit, Write, Bash(npm:*), Bash(node:*), Bash(firebase:*), Grep, Glob
---

# Backend Development Skill - Firebase & State Management

## Memory-First Protocol (MANDATORY)

Before starting any task:
1. Query Memory MCP for existing backend patterns: `mcp__memory__search_nodes`
2. Load related store and API entities: `mcp__memory__open_nodes`

During task execution:
- Create store/API entities: `mcp__memory__create_entities` with type "Store" or "API"
- Add implementation details as observations: `mcp__memory__add_observations`
- Link stores to components and functions: `mcp__memory__create_relations`

## Core Competencies

### 1. Firebase Services Management
- **Firestore Operations**: CRUD operations with proper user-scoped security
- **Firebase Functions**: Serverless backend logic and data processing
- **Authentication Integration**: User session and permission management
- **Security Rules**: Data access control and validation

### 2. State Management Architecture
- **Zustand Stores**: Domain-specific state management
- **Optimistic Updates**: Immediate UI updates with rollback capability
- **Real-time Sync**: Firestore subscriptions and live data updates
- **Error Handling**: Comprehensive error states and recovery

## Implementation Patterns

### Zustand Store Structure
```typescript
interface StoreState {
  // Data state
  items: Item[];
  selectedItem: Item | null;
  
  // UI state
  isLoading: boolean;
  error: string | null;
  
  // Actions
  loadItems: () => Promise<void>;
  createItem: (item: CreateItemData) => Promise<void>;
  updateItem: (id: string, updates: Partial<Item>) => Promise<void>;
  deleteItem: (id: string) => Promise<void>;
  setSelectedItem: (item: Item | null) => void;
  clearError: () => void;
}
```

### Firebase Security Model
```javascript
// User-scoped collections pattern
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/{collection}/{docId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

### Firebase Functions Pattern
```typescript
export const createItem = functions.https.onCall(async (data, context) => {
  // Authentication check
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }
  
  // Validation
  const itemData = validateItemData(data);
  
  // Create with user scoping
  const item = {
    ...itemData,
    id: generateId(),
    userId: context.auth.uid,
    createdAt: new Date(),
    updatedAt: new Date()
  };
  
  await admin.firestore()
    .collection('users')
    .doc(context.auth.uid)
    .collection('items')
    .doc(item.id)
    .set(item);
    
  return { success: true, item };
});
```

## Error Handling Pattern
```typescript
const handleAsyncOperation = async (operation: () => Promise<void>, errorMessage: string) => {
  try {
    set({ isLoading: true, error: null });
    await operation();
    set({ isLoading: false });
  } catch (error) {
    console.error(`${errorMessage}:`, error);
    set({ 
      isLoading: false, 
      error: error instanceof Error ? error.message : errorMessage 
    });
  }
};
```

## Optimistic Updates Pattern
```typescript
const updateItemOptimistically = async (id: string, updates: Partial<Item>) => {
  const { items } = get();
  const originalItem = items.find(item => item.id === id);
  
  // Optimistic update
  set({
    items: items.map(item => 
      item.id === id ? { ...item, ...updates } : item
    )
  });
  
  try {
    await updateItemInFirestore(id, updates);
  } catch (error) {
    // Rollback on error
    if (originalItem) {
      set({
        items: items.map(item => 
          item.id === id ? originalItem : item
        )
      });
    }
    throw error;
  }
};
```

## Data Validation with Zod
```typescript
import { z } from 'zod';

export const itemSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  description: z.string().optional(),
  status: z.enum(['ACTIVE', 'INACTIVE', 'ARCHIVED']),
  metadata: z.object({
    tags: z.array(z.string()).optional(),
    priority: z.number().int().min(1).max(5).optional(),
  }).optional(),
});

export const itemUpdateSchema = itemSchema.partial();
```

## Quality Standards

### Code Quality
- **TypeScript Strict**: Full type safety with proper interfaces
- **Error Handling**: Comprehensive error states and user feedback
- **Performance**: Efficient queries and minimal re-renders
- **Security**: Proper data access control and validation

### Testing Requirements
- **Unit Tests**: Store actions and Firebase Functions
- **Integration Tests**: End-to-end data flow validation
- **Security Tests**: Access control and permission validation
- **Performance Tests**: Query efficiency and load testing

## Reporting Template

```markdown
## Backend Implementation: [Feature Name]

### Components Delivered
- Zustand stores implemented
- Firebase Functions deployed
- Security rules updated
- Validation schemas created

### Data Integration
- Store-component integration tested
- Real-time subscriptions functional
- Optimistic updates working
- Error handling validated

### Security Validation
- User-scoped access verified
- Input validation tested
- Authentication flows working
- Permission checks functional
```
