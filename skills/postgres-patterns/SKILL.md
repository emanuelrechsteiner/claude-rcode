---
name: postgres-patterns
description: PostgreSQL quick reference for indexes, data types, query patterns, RLS policies, and slow-query diagnosis, based on Supabase guidance. Use when designing schemas, writing SQL, or fixing slow queries. Triggers on "postgres", "slow query", "add an index", "RLS policy".
---

<!--
Adapted from affaan-m/ECC skills/postgres-patterns @ c70874f (MIT, Copyright (c) 2026 Affaan Mustafa); reviewed and rewritten 2026-10-01 for this framework.
-->

# PostgreSQL Patterns

Quick reference for PostgreSQL schema, index, and query decisions. For schema changes on a live database, also load `database-migrations`.

## When to Use

- Writing SQL queries or migrations
- Designing or reviewing a schema
- Diagnosing a slow query
- Writing Row Level Security (RLS) policies
- Sizing connection limits and timeouts

## Safety first

- Read-only diagnostics (`EXPLAIN`, `pg_stat_*` views, catalog queries) are safe to run freely.
- DDL, `ALTER SYSTEM`, `REVOKE`, and anything on production are not: they follow `agency-bands`. Against a Supabase project, `execute_sql` with a write or DDL statement, and `apply_migration`, are ESCALATE-band; ask for an explicit y/n first.
- Measure before you index: run `EXPLAIN (ANALYZE, BUFFERS)` on the real query, ideally on production-sized data. A guessed index is a cost with no proven benefit.
- `EXPLAIN ANALYZE` executes the statement: never run it on a write outside a transaction you roll back.

## Index cheat sheet

| Query pattern | Index type | Example |
|---|---|---|
| `WHERE col = value` | B-tree (default) | `CREATE INDEX idx ON t (col)` |
| `WHERE col > value` | B-tree | `CREATE INDEX idx ON t (col)` |
| `WHERE a = x AND b > y` | Composite | `CREATE INDEX idx ON t (a, b)` |
| `WHERE jsonb @> '{}'` | GIN | `CREATE INDEX idx ON t USING gin (col)` |
| `WHERE tsv @@ query` | GIN | `CREATE INDEX idx ON t USING gin (col)` |
| Time-series ranges on append-ordered data | BRIN | `CREATE INDEX idx ON t USING brin (col)` |

On a large live table create indexes with `CREATE INDEX CONCURRENTLY` (see `database-migrations`).

## Data types

| Use case | Use | Avoid |
|---|---|---|
| IDs | `bigint` identity, or an ordered UUID (v7) where distributed ids are needed | `int`, random UUIDv4 as a hot key |
| Strings | `text` | `varchar(255)` without a real limit |
| Timestamps | `timestamptz` | `timestamp` |
| Money | `numeric(10,2)` | `float` |
| Flags | `boolean` | `varchar`, `int` |

## Common patterns

**Composite index order**: equality columns first, range columns last.
```sql
CREATE INDEX idx ON orders (status, created_at);
-- serves: WHERE status = 'pending' AND created_at > '2024-01-01'
```

**Covering index**
```sql
CREATE INDEX idx ON users (email) INCLUDE (name, created_at);
-- SELECT email, name, created_at can skip the table lookup
```

**Partial index**
```sql
CREATE INDEX idx ON users (email) WHERE deleted_at IS NULL;
-- smaller; only active users
```

**RLS policy (optimized)**: wrap the auth call in a `SELECT` so Postgres evaluates it once per query, not once per row. Index the column the policy filters on.
```sql
CREATE POLICY policy ON orders
  USING ((SELECT auth.uid()) = user_id);
```
Every table exposed through the API needs RLS enabled and tested with a non-owner role. A policy you never exercised as another user is not verified.

**Upsert**
```sql
INSERT INTO settings (user_id, key, value)
VALUES (123, 'theme', 'dark')
ON CONFLICT (user_id, key)
DO UPDATE SET value = EXCLUDED.value;
```

**Cursor pagination** (constant cost, unlike `OFFSET`)
```sql
SELECT * FROM products WHERE id > $last_id ORDER BY id LIMIT 20;
```
Select the columns you need rather than `*` in production code.

**Queue processing**
```sql
UPDATE jobs SET status = 'processing'
WHERE id = (
  SELECT id FROM jobs WHERE status = 'pending'
  ORDER BY created_at LIMIT 1
  FOR UPDATE SKIP LOCKED
) RETURNING *;
```

## Anti-pattern detection

All read-only.

```sql
-- Foreign keys without a supporting index
SELECT conrelid::regclass, a.attname
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
WHERE c.contype = 'f'
  AND NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indrelid = c.conrelid AND a.attnum = ANY(i.indkey)
  );

-- Slow queries (needs the pg_stat_statements extension)
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
WHERE mean_exec_time > 100
ORDER BY mean_exec_time DESC;

-- Dead tuples / bloat candidates
SELECT relname, n_dead_tup, last_vacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```

## Configuration template (self-hosted Postgres)

A starting point, not a paste-and-run script. Adjust to RAM, review each line, and apply it only with the owner's approval. On a managed service such as Supabase most of these are set through the dashboard or are not changeable; do not run `ALTER SYSTEM` there.

```sql
-- Connection limits (adjust for RAM)
ALTER SYSTEM SET max_connections = 100;
ALTER SYSTEM SET work_mem = '8MB';

-- Timeouts
ALTER SYSTEM SET idle_in_transaction_session_timeout = '30s';
ALTER SYSTEM SET statement_timeout = '30s';

-- Monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Security default: only if no role relies on implicit access to schema public.
-- It can break existing grants; test on a copy first.
REVOKE ALL ON SCHEMA public FROM public;

SELECT pg_reload_conf();
```

`max_connections` needs a restart, not just a reload. With many clients prefer a pooler over a bigger `max_connections`. A global `statement_timeout` of 30 s will also cut off legitimate long jobs and migrations; set it per role instead when those exist.

## Related skills

- `database-migrations`: how to change a live schema safely.
- `backend-development`: application-side data access and security rules.
- `cloud-cli-discipline`: inspect the target project and environment before running anything against it.

---
*Based on Supabase Agent Skills (credit: Supabase team, MIT License).*
