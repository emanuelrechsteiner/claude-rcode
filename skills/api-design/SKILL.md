---
name: api-design
description: REST API conventions — resource naming, methods and status codes, response and error envelopes, pagination, filtering, auth, rate limits, versioning. Use when designing or reviewing endpoints. Triggers on "API design", "REST endpoint", "HTTP status codes", "API pagination", "API versioning".
---

<!--
Adapted from affaan-m/ECC skills/api-design @ c70874f (MIT, Copyright (c) 2026 Affaan Mustafa); reviewed and rewritten 2026-10-01 for this framework.
-->

# API Design Patterns

Conventions for consistent, predictable REST APIs. Match an existing API's conventions first; this skill is the default for new surfaces and the checklist for reviews. Stack-specific implementation lives in `backend-development`.

## When to Use

- Designing new endpoints or a new API; reviewing an existing contract
- Adding pagination, filtering, or sorting
- Standardizing error handling
- Planning versioning or deprecation
- Building a public or partner-facing API

## Resource design

Resources are plural lowercase nouns in kebab-case. Nest for ownership; use a verb only for actions that do not map to CRUD.

```
GET    /api/v1/users            GET    /api/v1/users/:id
POST   /api/v1/users            PUT    /api/v1/users/:id
PATCH  /api/v1/users/:id        DELETE /api/v1/users/:id
GET    /api/v1/users/:id/orders              # sub-resource
POST   /api/v1/orders/:id/cancel             # action, verb used sparingly
POST   /api/v1/auth/login                    # action

GOOD  /api/v1/team-members   /api/v1/orders?status=active
BAD   /api/v1/getUsers (verb)   /api/v1/user (singular)   /api/v1/team_members (snake_case)
```

## HTTP methods and status codes

| Method | Idempotent | Safe | Use for |
|---|---|---|---|
| GET | yes | yes | Read |
| POST | no | no | Create, trigger an action |
| PUT | yes | no | Full replacement |
| PATCH | not guaranteed | no | Partial update |
| DELETE | yes | no | Remove |

A POST that clients may retry (payments, orders) needs an idempotency key.

```
200 OK            GET, PUT, PATCH with a body       400 Bad Request   malformed JSON, basic validation
201 Created       POST (add a Location header)      401 Unauthorized  missing or invalid authentication
204 No Content    DELETE, PUT without a body        403 Forbidden     authenticated, not allowed
404 Not Found     resource does not exist           409 Conflict      duplicate, state conflict
422 Unprocessable valid JSON, semantically invalid  429 Too Many      rate limit exceeded
500 Internal      unexpected; never expose details  502 Bad Gateway   upstream failed
503 Unavailable   temporary overload; Retry-After
```

Pick either 400 or 422 for validation failures and use it everywhere. Use the status code honestly: `HTTP 200 { "success": false }` is wrong, so is `500` for a validation error, so is `200` for a created resource.

## Response format

```json
{ "data": { "id": "abc-123", "email": "alice@example.com", "created_at": "2025-01-15T10:30:00Z" } }
```

Collections add `meta` and `links`:

```json
{
  "data": [ { "id": "abc-123" }, { "id": "def-456" } ],
  "meta":  { "total": 142, "page": 1, "per_page": 20, "total_pages": 8 },
  "links": { "self": "/api/v1/users?page=1", "next": "/api/v1/users?page=2", "last": "/api/v1/users?page=8" }
}
```

Errors carry a stable machine code, a human message, and field-level details:

```json
{
  "error": {
    "code": "validation_error",
    "message": "Request validation failed",
    "details": [
      { "field": "email", "message": "Must be a valid email address", "code": "invalid_format" }
    ]
  }
}
```

Envelope choice: a `data` wrapper with `meta`/`links` suits public APIs; a flat body (resource on success, error object on failure, distinguished by status code) is simpler for internal APIs. Choose one per API and keep it.

## Pagination

| Use case | Type |
|---|---|
| Admin dashboards, small sets (under about 10K rows) | Offset |
| Infinite scroll, feeds, large sets | Cursor |
| Public APIs | Cursor by default, offset optional |
| Search results (users expect page numbers) | Offset |

**Offset:** `?page=2&per_page=20` becomes `LIMIT 20 OFFSET 20`. Simple, allows "jump to page N", but slow at large offsets and inconsistent under concurrent inserts.

**Cursor:** `?cursor=eyJpZCI6MTIzfQ&limit=20` becomes `WHERE id > :cursor_id ORDER BY id LIMIT 21` (fetch one extra row to know `has_next`). Stable, constant cost, no random page access; the cursor is opaque to clients. Response meta: `{ "has_next": true, "next_cursor": "..." }`.

Always paginate list endpoints and cap `limit` server-side.

## Filtering, sorting, search

```
GET /api/v1/orders?status=active&customer_id=abc-123        # equality
GET /api/v1/products?price[gte]=10&price[lte]=100           # operators in brackets
GET /api/v1/products?category=electronics,clothing          # multiple values
GET /api/v1/products?sort=-featured,price                   # "-" prefix = descending
GET /api/v1/products?q=wireless+headphones                  # free-text search
GET /api/v1/users?fields=id,name,email                      # sparse fieldsets
```

Whitelist filter and sort fields server-side; an open `sort=` or filter parameter is an injection and denial-of-service surface.

## Authentication and authorization

`Authorization: Bearer <token>` for user sessions, `X-API-Key: <key>` for server-to-server. Authenticate every endpoint or mark it explicitly public. Authorize per resource, server-side, on every request: load the resource, check that `order.userId === req.user.id` (or the role), return 404 or 403 as a deliberate choice about leaking existence, and check roles in middleware for admin routes. Never trust client-side auth state. Keys and tokens in examples are placeholders; real ones come from the environment.

## Rate limiting

Return `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset` on every response, and on excess `429 Too Many Requests` with `Retry-After: 60` and the standard error body (`rate_limit_exceeded`). Starting tiers: anonymous 30/min per IP, authenticated 100/min per user, premium 1000/min per API key, internal 10000/min per service. Derive real limits from measured traffic.

## Versioning

**URL path (recommended):** `/api/v1/users`, `/api/v2/users`: explicit, easy to route and cache. **Header:** `Accept: application/vnd.myapp.v2+json`: clean URLs, but harder to test and easy to forget.

1. Start at `/api/v1/`; do not add a version until you need one.
2. Keep at most two active versions.
3. Deprecate with notice (about six months for public APIs), a `Sunset` header, then `410 Gone` after the date.
4. Non-breaking, no new version: new response fields, new optional query parameters, new endpoints.
5. Breaking, new version: removing or renaming fields, changing a type, changing URL structure, changing the auth method.

## Implementation example (Next.js route)

```typescript
const createUserSchema = z.object({ email: z.string().email(), name: z.string().min(1).max(100) });

export async function POST(req: NextRequest) {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json(
      { error: { code: "invalid_json", message: "Request body is not valid JSON" } },
      { status: 400 },
    );
  }
  const parsed = createUserSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: {
      code: "validation_error", message: "Request validation failed",
      details: parsed.error.issues.map((i) => ({ field: i.path.join("."), message: i.message, code: i.code })),
    } }, { status: 422 });
  }
  const user = await createUser(parsed.data);
  return NextResponse.json({ data: user }, { status: 201, headers: { Location: `/api/v1/users/${user.id}` } });
}
```

The shape carries to any framework: validate input at the boundary with a schema (Zod, Pydantic, Bean Validation), map known domain errors to specific codes (`409` for a duplicate email), and map unknown errors to a generic `500` that logs details server-side and shows none to the client. Malformed JSON returns `400`, as above, never an unhandled exception.

## API design checklist

- [ ] URL follows the naming conventions (plural, kebab-case, no verbs)
- [ ] Correct method; retried POSTs are idempotent
- [ ] Semantic status codes, never 200 for everything
- [ ] Input validated with a schema at the boundary
- [ ] Errors use the standard format with codes and messages
- [ ] List endpoints are paginated with a capped limit
- [ ] Authentication required, or explicitly public; authorization checked per resource
- [ ] Rate limiting configured
- [ ] No stack traces, SQL errors, or internal ids in responses
- [ ] Field naming matches the existing endpoints (camelCase vs snake_case)
- [ ] The OpenAPI/Swagger spec is updated

## Related skills

- `backend-development`: Firebase/Firestore and state-management specifics for this stack.
- `postgres-patterns`: the query and index side of pagination and filtering.
- `testing-suite`: endpoint and contract tests for the checklist above.
