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

-- 6. V3 & V5 Security Integrity Constraints: scim_users
-- 6a. Accepts NULL password and valid 60-char BCrypt ($2a$/$2b$/$2y$) hashes
INSERT INTO scim_users (id, workspace_id, user_name, active, password, created_at, last_modified)
VALUES (
    '20000000-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    'Alice@example.com',
    TRUE,
    NULL,
    NOW(),
    NOW()
);

INSERT INTO scim_users (id, workspace_id, user_name, active, password, created_at, last_modified)
VALUES (
    '20000000-0000-0000-0000-000000000002',
    '11111111-1111-1111-1111-111111111111',
    'bob@example.com',
    TRUE,
    '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy',
    NOW(),
    NOW()
);

-- 6b. Rejects case-variant duplicate user_name (V3)
DO $$
BEGIN
    INSERT INTO scim_users (id, workspace_id, user_name, active, created_at, last_modified)
    VALUES (
        gen_random_uuid(),
        '11111111-1111-1111-1111-111111111111',
        'alice@example.com',
        TRUE,
        NOW(),
        NOW()
    );
    RAISE EXCEPTION 'Expected unique_violation for case-insensitive duplicate user_name';
EXCEPTION WHEN unique_violation THEN
    -- Expected
END $$;

-- 6c. Rejects plaintext password in scim_users (V5)
DO $$
BEGIN
    INSERT INTO scim_users (id, workspace_id, user_name, active, password, created_at, last_modified)
    VALUES (
        gen_random_uuid(),
        '11111111-1111-1111-1111-111111111111',
        'plaintext-user@example.com',
        TRUE,
        'PlaintextSecret123!',
        NOW(),
        NOW()
    );
    RAISE EXCEPTION 'Expected check_violation for plaintext password';
EXCEPTION WHEN check_violation THEN
    -- Expected
END $$;

-- 6d. Rejects empty-string or truncated BCrypt prefix in scim_users (V5)
DO $$
BEGIN
    INSERT INTO scim_users (id, workspace_id, user_name, active, password, created_at, last_modified)
    VALUES (
        gen_random_uuid(),
        '11111111-1111-1111-1111-111111111111',
        'empty-pw@example.com',
        TRUE,
        '',
        NOW(),
        NOW()
    );
    RAISE EXCEPTION 'Expected check_violation for empty password';
EXCEPTION WHEN check_violation THEN
    -- Expected
END $$;

-- 7. V5 Security Integrity Constraints: workspace_tokens
-- 7a. Accepts valid 64-hex SHA-256 token_hash and defaults revoked to FALSE
INSERT INTO workspace_tokens (id, workspace_id, token_hash, name, created_at, updated_at)
VALUES (
    '30000000-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    'CI Valid Token',
    NOW(),
    NOW()
);

DO $$
DECLARE
    is_revoked BOOLEAN;
BEGIN
    SELECT revoked INTO is_revoked
    FROM workspace_tokens
    WHERE id = '30000000-0000-0000-0000-000000000001';

    IF is_revoked IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'Expected workspace_tokens.revoked DEFAULT FALSE, got %', is_revoked;
    END IF;
END $$;

-- 7b. Rejects non-SHA-256 / plaintext token_hash (V5)
DO $$
BEGIN
    INSERT INTO workspace_tokens (id, workspace_id, token_hash, name, revoked, created_at, updated_at)
    VALUES (
        gen_random_uuid(),
        '11111111-1111-1111-1111-111111111111',
        'not-a-sha256-hex-digest',
        'Bad Token',
        FALSE,
        NOW(),
        NOW()
    );
    RAISE EXCEPTION 'Expected check_violation for invalid token_hash';
EXCEPTION WHEN check_violation THEN
    -- Expected
END $$;

-- 8. V5 Security Integrity Constraints: scim_group_memberships
INSERT INTO scim_groups (id, workspace_id, display_name, created_at, last_modified)
VALUES (
    '40000000-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    'Engineering',
    NOW(),
    NOW()
);

INSERT INTO scim_groups (id, workspace_id, display_name, created_at, last_modified)
VALUES (
    '40000000-0000-0000-0000-000000000002',
    '11111111-1111-1111-1111-111111111111',
    'Backend',
    NOW(),
    NOW()
);

-- 8a. Accepts allowed member_type values ('User', 'Group', '')
INSERT INTO scim_group_memberships (id, group_id, workspace_id, member_value, member_type, display)
VALUES (
    '50000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    '20000000-0000-0000-0000-000000000001',
    'User',
    'Alice'
);

INSERT INTO scim_group_memberships (id, group_id, workspace_id, member_value, member_type, display)
VALUES (
    '50000000-0000-0000-0000-000000000002',
    '40000000-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    '40000000-0000-0000-0000-000000000002',
    'Group',
    'Backend'
);

INSERT INTO scim_group_memberships (id, group_id, workspace_id, member_value, member_type, display)
VALUES (
    '50000000-0000-0000-0000-000000000003',
    '40000000-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    '20000000-0000-0000-0000-000000000002',
    '',
    'Bob'
);

-- 8b. Rejects duplicate (workspace_id, group_id, member_value)
DO $$
BEGIN
    INSERT INTO scim_group_memberships (id, group_id, workspace_id, member_value, member_type, display)
    VALUES (
        gen_random_uuid(),
        '40000000-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        '20000000-0000-0000-0000-000000000001',
        'User',
        'Alice Duplicate'
    );
    RAISE EXCEPTION 'Expected unique_violation for duplicate group membership';
EXCEPTION WHEN unique_violation THEN
    -- Expected
END $$;

-- 8c. Rejects invalid member_type
DO $$
BEGIN
    INSERT INTO scim_group_memberships (id, group_id, workspace_id, member_value, member_type, display)
    VALUES (
        gen_random_uuid(),
        '40000000-0000-0000-0000-000000000002',
        '11111111-1111-1111-1111-111111111111',
        '20000000-0000-0000-0000-000000000001',
        'InvalidType',
        'Alice'
    );
    RAISE EXCEPTION 'Expected check_violation for invalid member_type';
EXCEPTION WHEN check_violation THEN
    -- Expected
END $$;

-- 8d. Rejects self-referential group membership (member_value = group_id)
DO $$
BEGIN
    INSERT INTO scim_group_memberships (id, group_id, workspace_id, member_value, member_type, display)
    VALUES (
        gen_random_uuid(),
        '40000000-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        '40000000-0000-0000-0000-000000000001',
        'Group',
        'Self'
    );
    RAISE EXCEPTION 'Expected check_violation for self-referential group membership';
EXCEPTION WHEN check_violation THEN
    -- Expected
END $$;

-- 9. Verify Foreign Key Cascade on Workspace Deletion
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
