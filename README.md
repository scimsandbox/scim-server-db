# SCIM Sandbox - Server DB

This repository is the standalone database migration bundle for the SCIM Sandbox server database.

## What Is In This Repo

- `sql/` contains the Flyway migration scripts (`V1` through `V5`).
- `scripts/verify-schema.sql` verifies all tables, indexes, foreign-key cascades, and `UNIQUE`/`CHECK` constraints against PostgreSQL.
- `Dockerfile` packages those migrations into a hardened non-root Flyway image (`65532:65532`) that runs `flyway migrate` against a target PostgreSQL database.
- `CONTRIBUTING.md` and `SECURITY.md` describe the workflow and reporting process.

## Schema Overview

- **`V1` (Initial schema)**:
  - `workspaces` for tenant and workspace metadata.
  - `mgmt_users` for management users.
  - `scim_users` for SCIM user records and profile attributes.
  - `scim_groups` for SCIM groups.
  - `scim_group_memberships` for group membership links.
  - `workspace_tokens` for workspace-scoped API tokens.
  - `scim_request_logs` for request and response auditing.
- **`V2` (Request path enlargement)**:
  - Alters `scim_request_logs.request_path` to `TEXT` to accommodate extended query parameters and long request URIs.
- **`V3` (Case-insensitive unique username)**:
  - Adds unique index `uk_scim_users_workspace_user_name_ci` on `(workspace_id, LOWER(user_name))` per RFC 7643 §7.
- **`V4` (Asynchronous events & SET polling)**:
  - Creates `scim_async_events` table for RFC 9967 asynchronous operation tracking.
  - Enforces uppercase HTTP methods (`POST`, `PUT`, `PATCH`, `DELETE`) via `chk_scim_async_events_operation`.
  - Enforces strict lifecycle state invariants via `chk_scim_async_events_lifecycle` (`PENDING` requires null `completed_at` and null `set_payload`; `COMPLETED` and `FAILED` require non-null values for both).
  - Configures indexes for per-workspace reverse-chronological ordering (`idx_scim_async_events_workspace_created_at`) and partial index on active operations for the stale-`PENDING` reaper (`idx_scim_async_events_pending_created_at`).
- **`V5` (Security & integrity constraints)**:
  - **`scim_users.password`**: Clears legacy non-BCrypt values to `NULL` (logging `NOTICE: V5: cleared N legacy non-BCrypt scim_users.password value(s) to NULL` when `N > 0`) and enforces 60-character modular crypt BCrypt (`$2a$`/`$2b$`/`$2y$`) hash format (`chk_scim_users_password_bcrypt`).
  - **`workspace_tokens`**: Enforces lowercase 64-character hex SHA-256 format (`chk_workspace_tokens_hash_format`, `token_hash ~ '^[0-9a-f]{64}$'`) and `DEFAULT FALSE` on `revoked` without auto-mutating existing rows.
  - **`scim_group_memberships`**: Enforces `uk_scim_group_memberships_workspace_group_member` (`UNIQUE (workspace_id, group_id, member_value)`), `chk_scim_group_memberships_member_type` (`member_type IN ('User', 'Group', '')`), and `chk_scim_group_memberships_no_self_ref` (`member_value <> group_id`) without auto-mutating existing rows, and drops the redundant `idx_group_memberships_workspace_group_id` index.

## Upgrade & Deployment Order (`V5`)

Deploy `V5`-compatible application releases **before** applying the `V5` database migration (or run `V5` during a maintenance rollout where no pre-`V5` application pods remain serving traffic):

1. Roll out updated application services first:
   - `scim-server-impl-spring` ([PR #16](https://github.com/scimsandbox/scim-server-impl-spring/pull/16))
   - `scim-server-impl-go` ([PR #16](https://github.com/scimsandbox/scim-server-impl-go/pull/16))
   - `scim-server-ui-spring` ([PR #15](https://github.com/scimsandbox/scim-server-ui-spring/pull/15))
2. Run `scim-server-db` (`V5`) once pre-`V5` application pods are drained.

**Why order matters**: Pre-`V5` application pods could write `password = ''`, unhashed `$2a$`-prefixed strings, self-referential group memberships (`member_value = group_id`), or clear-and-reinsert `ScimGroupMembership` collections without flushing deletes before inserts. Running those older pods against a `V5` schema will trigger PostgreSQL `CHECK` / `UNIQUE` violations and return `500` responses, whereas the updated application versions remain fully compatible with `V4` during rollout and return `400 invalidValue` for invalid inputs.

## Working With Migrations

Add new migrations under `sql/` using Flyway versioned filenames such as `V2__add_new_index.sql`. Keep migrations forward-only and avoid editing scripts that may already have been applied in another environment.

When you build or run the bundle, supply the Flyway connection settings at runtime with `FLYWAY_URL`, `FLYWAY_USER`, and `FLYWAY_PASSWORD`.

## Versioning

The release version is stored in [`VERSION`](./VERSION). The GitHub release workflow bumps that file with a patch, minor, or major increment, then tags and publishes the resulting commit. Publishing that GitHub release triggers the Docker publish workflow, which builds and pushes `edipal/scim-server-db`.

## Published Image

Published releases build and push a multi-arch Flyway image to `edipal/scim-server-db` with `latest`, `vX.Y.Z`, `X.Y.Z`, and `X.Y` tags.

## Validation

Before merging a migration change, build the image and run both clean-database (`V1 -> V5`) and `V4 -> V5` upgrade verification against PostgreSQL 17 (automated in [`.github/workflows/build-test.yml`](./.github/workflows/build-test.yml)), using [`scripts/verify-schema.sql`](./scripts/verify-schema.sql) to verify tables, indexes, cascades, and constraints.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## Security

See [SECURITY.md](./SECURITY.md).
