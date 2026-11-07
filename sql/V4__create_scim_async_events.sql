-- RFC 9967: SCIM Profile for Security Event Tokens (SETs)
-- Asynchronous request processing and polling event table.
--
-- Tracks long-running or asynchronously accepted mutating operations (POST, PUT, PATCH, DELETE)
-- initiated with the HTTP request header 'Prefer: respond-async' (RFC 7240 / RFC 9967 §2.5.1.1).
--
-- Lifecycle:
-- 1. On request receipt, a row is inserted with status = 'PENDING' and a freshly generated txn_id (UUID).
-- 2. The server responds immediately with HTTP 202 Accepted, Set-Txn: <txn_id>, and Location: <baseUrl>/Events/<txn_id>.
-- 3. A background worker executes the SCIM operation and compiles the Security Event Token (SET) JSON payload (RFC 8417).
-- 4. Upon success, the worker updates status = 'COMPLETED', set_payload = <SET JSON>, and completed_at = NOW().
--    If an error occurs or the worker times out, the worker or reaper updates status = 'FAILED',
--    set_payload = <RFC 9967 §2.5.1.3 error SET JSON>, and completed_at = NOW().
-- 5. Clients poll GET /Events/<txn_id>, which returns 202 Accepted while PENDING, and 200 OK with SET JSON
--    when terminal (both COMPLETED and FAILED return 200 OK per RFC 9967 §2.5.1.3, delivering either the
--    provisioning event or the misc:asyncresp error event).
--
-- Design Notes:
-- - operation: Enforced by chk_scim_async_events_operation to uppercase HTTP methods ('POST', 'PUT', 'PATCH', 'DELETE')
--   matching scim_request_logs.http_method from V1.
-- - resource_type: Expected values include 'User' and 'Group'; left unconstrained to allow future custom resources.
-- - jti: Security Event Token identifier is embedded inside the serialized set_payload JSON. Polling keys solely
--   on txn_id (PK), so a dedicated column and index for jti are unnecessary.
-- - Stale PENDING recovery: In-flight operations execute in-process without durable request body persistence.
--   Orphaned PENDING events older than a stale cutoff (e.g. 5 minutes) are swept to FAILED with an error SET
--   by a background reaper using idx_scim_async_events_pending_created_at.
-- - Retention: Terminal rows (COMPLETED, FAILED) are pruned per workspace according to retention policy
--   using idx_scim_async_events_workspace_created_at.

CREATE TABLE scim_async_events (
    txn_id UUID PRIMARY KEY,
    workspace_id UUID NOT NULL,
    operation VARCHAR(32) NOT NULL,
    resource_type VARCHAR(32) NOT NULL,
    resource_id UUID,
    status VARCHAR(32) NOT NULL,
    set_payload TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT fk_scim_async_events_workspace FOREIGN KEY (workspace_id) REFERENCES workspaces (id) ON DELETE CASCADE,
    CONSTRAINT chk_scim_async_events_operation CHECK (operation IN ('POST', 'PUT', 'PATCH', 'DELETE')),
    CONSTRAINT chk_scim_async_events_status CHECK (status IN ('PENDING', 'COMPLETED', 'FAILED')),
    CONSTRAINT chk_scim_async_events_lifecycle CHECK (
        (status = 'PENDING' AND completed_at IS NULL AND set_payload IS NULL)
        OR (status IN ('COMPLETED', 'FAILED') AND completed_at IS NOT NULL AND set_payload IS NOT NULL)
    )
);

CREATE INDEX idx_scim_async_events_workspace_created_at
    ON scim_async_events (workspace_id, created_at DESC);

CREATE INDEX idx_scim_async_events_pending_created_at
    ON scim_async_events (created_at)
    WHERE status = 'PENDING';
