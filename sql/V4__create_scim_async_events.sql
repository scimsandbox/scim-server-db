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
--    If an error occurs, the worker updates status = 'FAILED' and completed_at = NOW().
-- 5. Clients poll GET /Events/<txn_id>, which returns 202 Accepted while PENDING, and 200 OK with SET JSON when COMPLETED.

CREATE TABLE IF NOT EXISTS scim_async_events (
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
    CONSTRAINT chk_scim_async_events_status CHECK (status IN ('PENDING', 'COMPLETED', 'FAILED'))
);

CREATE INDEX IF NOT EXISTS idx_scim_async_events_workspace_created_at
    ON scim_async_events (workspace_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_scim_async_events_workspace_status
    ON scim_async_events (workspace_id, status);
