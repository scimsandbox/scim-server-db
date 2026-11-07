-- scripts/verify-schema.sql
-- Comprehensive schema and constraint verification for scim-server-db against PostgreSQL 17.

\set ON_ERROR_STOP on

BEGIN;

-- 1. Verify existence of table, columns, and constraints
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'scim_async_events'
    ) THEN
        RAISE EXCEPTION 'Table scim_async_events does not exist';
    END IF;

    -- Verify dropped index does NOT exist
    IF EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE tablename = 'scim_async_events'
          AND indexname = 'idx_scim_async_events_workspace_status'
    ) THEN
        RAISE EXCEPTION 'Index idx_scim_async_events_workspace_status should have been dropped';
    END IF;

    -- Verify partial index idx_scim_async_events_pending_created_at exists
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE tablename = 'scim_async_events'
          AND indexname = 'idx_scim_async_events_pending_created_at'
    ) THEN
        RAISE EXCEPTION 'Partial index idx_scim_async_events_pending_created_at is missing';
    END IF;

    -- Verify workspace ordering index exists
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE tablename = 'scim_async_events'
          AND indexname = 'idx_scim_async_events_workspace_created_at'
    ) THEN
        RAISE EXCEPTION 'Index idx_scim_async_events_workspace_created_at is missing';
    END IF;
END $$;

-- 2. Setup Test Workspace
INSERT INTO workspaces (id, name, created_at, updated_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'CI Test Workspace', NOW(), NOW());

-- 3. Positive Cases: Allowed operations and lifecycle transitions
-- 3a. Insert PENDING for all allowed operations
INSERT INTO scim_async_events (txn_id, workspace_id, operation, resource_type, status)
VALUES ('a0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'POST', 'User', 'PENDING');

INSERT INTO scim_async_events (txn_id, workspace_id, operation, resource_type, status)
VALUES ('a0000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'PUT', 'User', 'PENDING');

INSERT INTO scim_async_events (txn_id, workspace_id, operation, resource_type, status)
VALUES ('a0000000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'PATCH', 'Group', 'PENDING');

INSERT INTO scim_async_events (txn_id, workspace_id, operation, resource_type, status)
VALUES ('a0000000-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'DELETE', 'User', 'PENDING');

-- 3b. Transition PENDING -> COMPLETED
UPDATE scim_async_events
SET status = 'COMPLETED', completed_at = NOW(), set_payload = '{"event":"prov:create:full"}'
WHERE txn_id = 'a0000000-0000-0000-0000-000000000001';

-- 3c. Transition PENDING -> FAILED
UPDATE scim_async_events
SET status = 'FAILED', completed_at = NOW(), set_payload = '{"event":"misc:asyncresp","status":500}'
WHERE txn_id = 'a0000000-0000-0000-0000-000000000002';

-- 4. Negative Cases: chk_scim_async_events_operation
-- Rejects lowercase 'create'
DO $$
BEGIN
    INSERT INTO scim_async_events (txn_id, workspace_id, operation, resource_type, status)
    VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'create', 'User', 'PENDING');
    RAISE EXCEPTION 'Expected rejection for operation create';
EXCEPTION WHEN check_violation THEN
    -- Expected
END $$;

-- Rejects invalid verb 'GET'
DO $$
BEGIN
    INSERT INTO scim_async_events (txn_id, workspace_id, operation, resource_type, status)
    VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'GET', 'User', 'PENDING');
    RAISE EXCEPTION 'Expected rejection for operation GET';
EXCEPTION WHEN check_violation THEN
    -- Expected
END $$;

-- 5. Negative Cases: chk_scim_async_events_lifecycle
-- 5a. Rejects PENDING with completed_at NOT NULL
DO $$
BEGIN
    INSERT INTO scim_async_events (txn_id, workspace_id, operation, resource_type, status, completed_at)
    VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'POST', 'User', 'PENDING', NOW());
    RAISE EXCEPTION 'Expected rejection for PENDING with completed_at';
EXCEPTION WHEN check_violation THEN
    -- Expected
END $$;

-- 5b. Rejects PENDING with set_payload NOT NULL
DO $$
BEGIN
    INSERT INTO scim_async_events (txn_id, workspace_id, operation, resource_type, status, set_payload)
    VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'POST', 'User', 'PENDING', '{"payload":true}');
    RAISE EXCEPTION 'Expected rejection for PENDING with set_payload';
EXCEPTION WHEN check_violation THEN
    -- Expected
END $$;

-- 5c. Rejects COMPLETED with completed_at NULL
DO $$
BEGIN
    INSERT INTO scim_async_events (txn_id, workspace_id, operation, resource_type, status, set_payload)
    VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'POST', 'User', 'COMPLETED', '{"payload":true}');
    RAISE EXCEPTION 'Expected rejection for COMPLETED with NULL completed_at';
EXCEPTION WHEN check_violation THEN
    -- Expected
END $$;

-- 5d. Rejects COMPLETED with set_payload NULL
DO $$
BEGIN
    INSERT INTO scim_async_events (txn_id, workspace_id, operation, resource_type, status, completed_at)
    VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'POST', 'User', 'COMPLETED', NOW());
    RAISE EXCEPTION 'Expected rejection for COMPLETED with NULL set_payload';
EXCEPTION WHEN check_violation THEN
    -- Expected
END $$;

-- 5e. Rejects FAILED with completed_at NULL
DO $$
BEGIN
    INSERT INTO scim_async_events (txn_id, workspace_id, operation, resource_type, status, set_payload)
    VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'POST', 'User', 'FAILED', '{"payload":true}');
    RAISE EXCEPTION 'Expected rejection for FAILED with NULL completed_at';
EXCEPTION WHEN check_violation THEN
    -- Expected
END $$;

-- 5f. Rejects FAILED with set_payload NULL
DO $$
BEGIN
    INSERT INTO scim_async_events (txn_id, workspace_id, operation, resource_type, status, completed_at)
    VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'POST', 'User', 'FAILED', NOW());
    RAISE EXCEPTION 'Expected rejection for FAILED with NULL set_payload';
EXCEPTION WHEN check_violation THEN
    -- Expected
END $$;

-- 6. Verify Foreign Key Cascade on Workspace Deletion
DELETE FROM workspaces WHERE id = '11111111-1111-1111-1111-111111111111';

DO $$
DECLARE
    cnt INTEGER;
BEGIN
    SELECT COUNT(*) INTO cnt FROM scim_async_events WHERE workspace_id = '11111111-1111-1111-1111-111111111111';
    IF cnt <> 0 THEN
        RAISE EXCEPTION 'Foreign key ON DELETE CASCADE failed; % rows still exist', cnt;
    END IF;
END $$;

COMMIT;
