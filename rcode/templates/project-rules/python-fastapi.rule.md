# Python/FastAPI Patterns

> Project-level rule: Install in `.claude/rules/` for Python/FastAPI projects.

## Python Standards

- Python 3.11+ with full type hints (PEP 484)
- mypy strict mode — No `Any` without written justification
- Use dataclasses or Pydantic for structured data
- pathlib for all file operations (not os.path)
- Google-style docstrings
- async/await for all I/O operations

## FastAPI Standards

- Dependency injection for auth, database sessions, config
- Pydantic models for ALL request/response validation
- Proper error handlers with appropriate HTTP status codes
- WebSocket support with proper connection lifecycle
- Use `BackgroundTasks` for non-blocking operations

```python
# Route pattern
from fastapi import FastAPI, Depends, HTTPException
from pydantic import BaseModel

class ItemCreate(BaseModel):
    name: str
    description: str | None = None

@app.post("/items/", response_model=ItemResponse)
async def create_item(item: ItemCreate, user: User = Depends(get_current_user)):
    if not user:
        raise HTTPException(status_code=401, detail="Unauthorized")
    return await item_service.create(item, user.id)
```

## Testing

- pytest for all tests
- `@pytest.mark.asyncio` for async tests
- Use httpx AsyncClient for API testing
- Fixtures in `conftest.py` for shared setup
- Mock external services (never call real APIs in tests)

## Quality Tools

```bash
pytest                  # Run tests
ruff check .           # Linting
black --check .        # Formatting
mypy .                 # Type checking
```

## File Handling

- Use temporary files securely with `tempfile`
- Always clean up temp files (use context managers)
- Prevent path traversal (validate all file paths)
- Validate MIME types for uploads
- Set size limits for file uploads

## Async Patterns

- Use `asyncio.gather()` for parallel I/O
- Use `asyncio.Semaphore` for concurrency limits
- Context managers for resource cleanup
- Retry logic with exponential backoff (tenacity library)
