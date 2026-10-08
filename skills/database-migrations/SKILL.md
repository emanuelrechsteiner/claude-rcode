---
name: database-migrations
description: Safe schema and data migrations — forward-only, expand-contract renames, concurrent indexes, batched backfills, per-tool workflows. Use when changing a live schema. Triggers on "database migration", "schema migration", "zero-downtime migration", "expand contract", "backfill a column".
---

<!--
Adapted from affaan-m/ECC skills/database-migrations @ c70874f (MIT, Copyright (c) 2026 Affaan Mustafa); reviewed and rewritten 2026-10-01 for this framework.
-->

# Database Migration Patterns

Safe, reviewable schema changes for production systems.

## When to Use

- Creating or altering tables; adding or removing columns or indexes
- Running a data migration (backfill, transform)
- Planning a zero-downtime change or a rollback
- Setting up migration tooling in a new project

## Authority first

A migration against a production or shared database is an ESCALATE-band operation (`agency-bands`): prod migrations, `DROP TABLE`, `TRUNCATE`, `apply_migration`, and `execute_sql` with writes need an explicit y/n, shown with the exact SQL and the target project. Preview or branch databases are SOFT-ACK. Before running anything, confirm which project and environment the CLI or MCP server points at (`cloud-cli-discipline`): a correct migration on the wrong database is still an incident. Writing and reviewing the migration file is AUTO; applying it is the gated step.

## Core principles

1. **Every change is a migration.** Never alter a production database by hand.
2. **Forward-only in production.** A rollback is a new forward migration, not a reverse run.
3. **Schema and data migrations are separate.** Never mix DDL and DML in one migration.
4. **Test against production-sized data.** A migration that takes ms on 100 rows can lock on 10M.
5. **Migrations are immutable once deployed.** Never edit one that has run in production.

## Safety checklist

- [ ] Has an UP and a DOWN, or is marked irreversible with a recovery plan
- [ ] No long full-table lock on a large table
- [ ] New columns are nullable or have a default; never `NOT NULL` without a default on an existing table
- [ ] Indexes on existing tables are created concurrently
- [ ] Backfill is its own migration, separate from the schema change
- [ ] Tested on a copy of production-shaped data
- [ ] Rollback or restore plan written down (a backup or point-in-time restore point exists before destructive steps)
- [ ] The target database is confirmed

## PostgreSQL patterns

### Add a column safely

```sql
-- GOOD: nullable, no rewrite
ALTER TABLE users ADD COLUMN avatar_url TEXT;

-- GOOD: constant default (Postgres 11+ stores it as metadata, no rewrite)
ALTER TABLE users ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT true;

-- BAD: NOT NULL without a default on an existing table fails or rewrites
ALTER TABLE users ADD COLUMN role TEXT NOT NULL;
```

### Add an index without blocking writes

```sql
-- BAD on a large table: blocks writes while it builds
CREATE INDEX idx_users_email ON users (email);

-- GOOD: allows concurrent writes
CREATE INDEX CONCURRENTLY idx_users_email ON users (email);
```

`CONCURRENTLY` cannot run inside a transaction block, so the tool must run that file without a wrapping transaction. A failed concurrent build leaves an `INVALID` index; drop it and retry.

### Rename a column (zero downtime)

Never rename in place in production. Use expand-contract; the order matters, because a backfill that runs before the app dual-writes misses rows written in between.

```sql
-- 1. Add the new column (migration 001)
ALTER TABLE users ADD COLUMN display_name TEXT;
-- 2. Deploy application code that writes BOTH columns (dual-write)
-- 3. Backfill existing rows in batches (migration 002, data migration; use the batched
--    pattern under "Large data migrations", not one big UPDATE)
-- 4. Once the new code is the only reader, drop the old column (migration 003)
ALTER TABLE users DROP COLUMN username;
```

### Remove a column safely

Remove every application reference, deploy, then drop the column in the next migration (`ALTER TABLE orders DROP COLUMN legacy_status;`). In Django, use `SeparateDatabaseAndState` to drop the field from model state first, deploy, then drop the column later.

### Large data migrations

```sql
-- BAD: one transaction over every row
UPDATE users SET normalized_email = LOWER(email);

-- GOOD: batches with a commit between them
DO $$
DECLARE
  batch_size INT := 10000;
  rows_updated INT;
BEGIN
  LOOP
    UPDATE users SET normalized_email = LOWER(email)
    WHERE id IN (
      SELECT id FROM users
      WHERE normalized_email IS NULL AND email IS NOT NULL
      LIMIT batch_size FOR UPDATE SKIP LOCKED
    );
    GET DIAGNOSTICS rows_updated = ROW_COUNT;
    RAISE NOTICE 'Updated % rows', rows_updated;
    EXIT WHEN rows_updated = 0;
    COMMIT;
  END LOOP;
END $$;
```

The `email IS NOT NULL` filter is required: a row whose source value is NULL would keep `normalized_email` NULL after the update, stay in the selected set, and the loop would never reach zero. `COMMIT` inside `DO` needs Postgres 11+ and the block must not already be inside a transaction. Keep the backfill resumable (the `IS NULL` filter does that) and idempotent, and verify the row count afterwards.

## Tool workflows

(ESCALATE against production: applying any command below to a production database needs the y/n described under "Authority first".)

Generate the migration from the schema change, read the generated SQL, then apply. A generated migration is unverified code until you have read it.

**Prisma**
```bash
npx prisma migrate dev --name add_user_avatar   # create + apply in dev
npx prisma migrate deploy                       # apply pending in production
npx prisma migrate reset                        # DEV ONLY: wipes the database
npx prisma migrate dev --create-only --name add_email_index   # empty migration to hand-write SQL
```
Prisma cannot express `CONCURRENTLY` or a backfill; write them into the `--create-only` migration (`CREATE INDEX CONCURRENTLY IF NOT EXISTS ...`).

**Drizzle**
```bash
npx drizzle-kit generate   # SQL migration from schema changes
npx drizzle-kit migrate    # apply
npx drizzle-kit push       # DEV ONLY: pushes the schema directly, no migration file
```

**Kysely (kysely-ctl)**
```bash
kysely migrate make add_user_avatar   # new migration file
kysely migrate latest                 # apply pending
kysely migrate down                   # dev only; production is forward-only
kysely migrate list                   # status
```
Type migration functions as `Kysely<any>`, never the typed DB interface: a migration is frozen in time and must not depend on today's schema types. When running the `Migrator` programmatically, keep timestamp-order validation on (`allowUnorderedMigrations` is development only because it permits drift between environments) and fail the process on the returned `error`.

**Django**
```bash
python manage.py makemigrations
python manage.py migrate
python manage.py showmigrations
python manage.py makemigrations --empty app_name -n description   # custom SQL or data
```
For a backfill in `RunPython`, make the loop terminate on rows that still need work (exclude values that can never be filled), pass a real reverse function or `migrations.RunPython.noop`, and use `bulk_update` in batches.

**golang-migrate**
```bash
migrate create -ext sql -dir migrations -seq add_user_avatar
migrate -path migrations -database "$DATABASE_URL" up
migrate -path migrations -database "$DATABASE_URL" down 1
migrate -path migrations -database "$DATABASE_URL" force VERSION   # repair a dirty state; find out what failed first
```
Each `.up.sql` has a matching `.down.sql`. `CREATE INDEX CONCURRENTLY` must live in its own migration if the driver wraps files in a transaction. Read `DATABASE_URL` from the environment; never paste a real one into chat, commits, or logs.

## Zero-downtime strategy: expand, migrate, contract

```
Phase 1 EXPAND    Add the new column/table (nullable or defaulted).
                  Deploy: the app writes to BOTH old and new. Backfill existing rows.
Phase 2 MIGRATE   Deploy: the app reads NEW, still writes BOTH. Verify the data matches.
Phase 3 CONTRACT  Deploy: the app uses only NEW. Drop the old column/table in a separate migration.
```

Typical pacing: day 1 add the column and dual-write, day 2 backfill, day 3 read from the new column, about day 7 drop the old one.

## Anti-patterns

| Anti-pattern | Why it fails | Better |
|---|---|---|
| Manual SQL in production | No audit trail, not repeatable | Migration files |
| Editing a deployed migration | Environments drift | A new migration |
| `NOT NULL` without a default | Locks or rewrites the table | Add nullable, backfill, then add the constraint |
| Inline index on a large table | Blocks writes during the build | `CREATE INDEX CONCURRENTLY` |
| Schema + data in one migration | Hard to roll back, long transactions | Separate migrations |
| Dropping a column before removing the code | Application errors on the missing column | Remove code first, drop in the next deploy |
| `push` / `reset` tooling on a shared database | Wipes or diverges data | Dev databases only |

## Related skills

- `postgres-patterns`: index and query decisions behind a migration.
- `cloud-cli-discipline`: confirm the project and environment before applying.
- `incident-response`: when a migration goes wrong in production.
