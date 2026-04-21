# SCIM Sandbox - Server DB

This repository is the standalone database migration bundle for the SCIM Sandbox server database.
## What Is In This Repo

- `sql/` contains the Flyway migration scripts.
- `sql/V1__init_common_schema.sql` creates the initial SCIM Sandbox server schema.
- `Dockerfile` packages those migrations into a Flyway image that runs `flyway migrate` against a target PostgreSQL database.
- `CONTRIBUTING.md` and `SECURITY.md` describe the workflow and reporting process.

## Schema Overview

The initial migration creates:

- `workspaces` for tenant and workspace metadata.
- `mgmt_users` for management users.
- `scim_users` for SCIM user records and profile attributes.
- `scim_groups` for SCIM groups.
- `scim_group_memberships` for group membership links.
- `workspace_tokens` for workspace-scoped API tokens.
- `scim_request_logs` for request and response auditing.

The migration also adds unique constraints and indexes for workspace lookup, external IDs, membership lookups, token lookup, and request-log ordering.

## Working With Migrations

Add new migrations under `sql/` using Flyway versioned filenames such as `V2__add_new_index.sql`. Keep migrations forward-only and avoid editing scripts that may already have been applied in another environment.

When you build or run the bundle, supply the Flyway connection settings at runtime with `FLYWAY_URL`, `FLYWAY_USER`, and `FLYWAY_PASSWORD`.

## Versioning

The release version is stored in [`VERSION`](./VERSION). The GitHub release workflow bumps that file with a patch, minor, or major increment, then tags and publishes the resulting commit. Publishing that GitHub release triggers the Docker publish workflow, which builds and pushes `edipal/scim-flyway-api`.

## Published Image

Published releases build and push a multi-arch Flyway image to `edipal/scim-flyway-api` with `latest`, `vX.Y.Z`, `X.Y.Z`, and `X.Y` tags.

## Validation

Before merging a migration change, apply it to a fresh PostgreSQL database and verify that the resulting schema matches the intended design. A typical check is to build the image and run it against an empty database, then inspect the resulting schema with `psql` or your preferred tooling.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## Security

See [SECURITY.md](./SECURITY.md).
