---
name: data-migration
description: Create Rails data migrations using the data_migrate gem for one-time data changes, backfills, and normalization tasks.
---

# Rails Data Migration Guidelines

When a task involves modifying existing data rather than changing database structure, create a data migration in `db/data/` using the `data_migrate` gem.

## Use Data Migrations For

- Backfilling newly added columns
- Data normalization
- Data cleanup
- Recalculating cached values
- Correcting bad data
- Migrating values between columns
- One-time imports or transformations
- Repair scripts that should run once in each environment

Examples:

- Normalize part numbers to uppercase
- Populate a new search column
- Fix invalid status values
- Recalculate inventory totals
- Copy data from one model attribute to another

## Do NOT Use Data Migrations For

- add_column
- remove_column
- rename_column
- add_index
- remove_index
- foreign keys
- constraints
- table creation/removal

Those belong in standard ActiveRecord schema migrations (`db/migrate/`).

## Generator

Generate a data migration:

```bash
bin/rails g data_migration migration_name
```

Generated files belong in `db/data/`.

## Running

- Dev/test: `bin/rails data:migrate`
- Deploy (schema + data together): `bin/rails db:migrate:with_data`
- Status: `bin/rails data:migrate:status`
- Rollback: `bin/rails data:rollback`

The `data_migrations` table is created automatically on first run in the primary SQLite DB. Solid Queue/Cache/Cable use separate connections and are untouched.

## Implementation Rules

- Inherit from `ActiveRecord::Migration[CURRENT_RAILS_VERSION]` (e.g. `ActiveRecord::Migration[8.1]`)
- Implement `up`
- Use `raise ActiveRecord::IrreversibleMigration` in `down` unless rollback is explicitly requested
- Prefer `in_batches.update_all`
- Avoid model callbacks and validations
- Avoid loading records into memory
- Make operations idempotent when possible
- Use direct SQL expressions for bulk updates

## Stray-specific rules

- Do **not** convert already-committed schema migrations that happen to touch data (e.g. `SetFirstUserAdmin`, `SeedSettingsFromEnv`). The forward-going rule is: new data changes go in `db/data/`.
- Deploy runs `db:migrate:with_data` via the `migrate.cmd` hook in `config/deploy.yml`; `bin/setup` uses `db:prepare:with_data`.

## When Asked To Create A One-Off Script

If the request is:

- "update all existing records"
- "backfill data"
- "normalize values"
- "fix existing rows"
- "migrate data"
- "repair records"

Generate a `data_migrate` migration rather than a schema migration.
