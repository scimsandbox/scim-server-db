-- scripts/verify-v5-cleanup.sql
-- Verifies every post-V5 state transition on the pre-V5 dirty dataset seeded by
-- scripts/seed-pre-v5-dirty-data.sql, then cleans up the test workspace.

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    pw_val TEXT;
    tok_hash TEXT;
    cnt INTEGER;
    m_type TEXT;
    m_disp TEXT;
BEGIN
    -- 1. Verify scim_users password sanitization
    SELECT password INTO pw_val FROM scim_users WHERE id = '71000000-0000-0000-0000-000000000001';
    IF pw_val IS DISTINCT FROM '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy' THEN
        RAISE EXCEPTION 'Expected valid BCrypt password to remain intact, got %', pw_val;
    END IF;

    SELECT COUNT(*) INTO cnt
    FROM scim_users
    WHERE id IN (
        '71000000-0000-0000-0000-000000000002',
        '71000000-0000-0000-0000-000000000003',
        '71000000-0000-0000-0000-000000000004',
        '71000000-0000-0000-0000-000000000005'
    )
      AND password IS NULL;
    IF cnt <> 4 THEN
        RAISE EXCEPTION 'Expected all 4 NULL/empty/plaintext/malformed-prefix passwords to be NULL, got %', cnt;
    END IF;

    -- 2. Verify workspace_tokens cleanup, collision resolution, and lowercase normalization
    SELECT COUNT(*) INTO cnt
    FROM workspace_tokens
    WHERE workspace_id = '77777777-7777-7777-7777-777777777777';
    IF cnt <> 4 THEN
        RAISE EXCEPTION 'Expected 4 surviving workspace_tokens rows, got %', cnt;
    END IF;

    SELECT token_hash INTO tok_hash
    FROM workspace_tokens
    WHERE id = '72000000-0000-0000-0000-000000000002';
    IF tok_hash IS DISTINCT FROM 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' THEN
        RAISE EXCEPTION 'Expected uppercase token_hash to be normalized to lowercase, got %', tok_hash;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM workspace_tokens WHERE id = '72000000-0000-0000-0000-000000000003') THEN
        RAISE EXCEPTION 'Expected lowercase survivor 72000000-0000-0000-0000-000000000003 to remain';
    END IF;

    SELECT token_hash INTO tok_hash
    FROM workspace_tokens
    WHERE id = '72000000-0000-0000-0000-000000000006';
    IF tok_hash IS DISTINCT FROM 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd' THEN
        RAISE EXCEPTION 'Expected mixed-case collision survivor 72000000-0000-0000-0000-000000000006 to be lowercased, got %', tok_hash;
    END IF;

    IF EXISTS (SELECT 1 FROM workspace_tokens WHERE id IN (
        '72000000-0000-0000-0000-000000000004',
        '72000000-0000-0000-0000-000000000005',
        '72000000-0000-0000-0000-000000000007'
    )) THEN
        RAISE EXCEPTION 'Expected colliding uppercase/mixed-case and malformed workspace_tokens rows to be deleted';
    END IF;

    -- 3. Verify scim_group_memberships self-ref deletion, member_type normalization, and deterministic deduplication
    IF EXISTS (SELECT 1 FROM scim_group_memberships WHERE id = '90000000-0000-0000-0000-000000000001') THEN
        RAISE EXCEPTION 'Expected self-referential membership row to be deleted';
    END IF;

    SELECT member_type INTO m_type FROM scim_group_memberships WHERE id = '90000000-0000-0000-0000-000000000002';
    IF m_type IS DISTINCT FROM 'Group' THEN
        RAISE EXCEPTION 'Expected lowercase group member_type to normalize to Group, got %', m_type;
    END IF;

    SELECT member_type INTO m_type FROM scim_group_memberships WHERE id = '90000000-0000-0000-0000-000000000003';
    IF m_type IS DISTINCT FROM 'User' THEN
        RAISE EXCEPTION 'Expected padded uppercase USER member_type to normalize to User, got %', m_type;
    END IF;

    SELECT member_type INTO m_type FROM scim_group_memberships WHERE id = '90000000-0000-0000-0000-000000000004';
    IF m_type IS DISTINCT FROM '' THEN
        RAISE EXCEPTION 'Expected whitespace-only member_type to normalize to empty string, got %', m_type;
    END IF;

    SELECT member_type INTO m_type FROM scim_group_memberships WHERE id = '90000000-0000-0000-0000-000000000005';
    IF m_type IS DISTINCT FROM '' THEN
        RAISE EXCEPTION 'Expected unrecognized member_type to be blanked to empty string, got %', m_type;
    END IF;

    -- Duplicate pair #1: 0011 ('group' -> 'Group') must survive over 0010 ('')
    IF NOT EXISTS (SELECT 1 FROM scim_group_memberships WHERE id = '90000000-0000-0000-0000-000000000011' AND member_type = 'Group')
       OR EXISTS (SELECT 1 FROM scim_group_memberships WHERE id = '90000000-0000-0000-0000-000000000010') THEN
        RAISE EXCEPTION 'Duplicate pair #1 failed: expected normalized Group row 0011 to survive over untyped row 0010';
    END IF;

    -- Duplicate pair #2: 0021 (non-empty display) must survive over 0020 (blank display)
    SELECT display INTO m_disp FROM scim_group_memberships WHERE id = '90000000-0000-0000-0000-000000000021';
    IF m_disp IS DISTINCT FROM 'Alice Canonical'
       OR EXISTS (SELECT 1 FROM scim_group_memberships WHERE id = '90000000-0000-0000-0000-000000000020') THEN
        RAISE EXCEPTION 'Duplicate pair #2 failed: expected non-empty display row 0021 to survive over blank-display row 0020';
    END IF;

    -- Duplicate pair #3: 0030 (smaller id) must survive over 0031 (larger id)
    IF NOT EXISTS (SELECT 1 FROM scim_group_memberships WHERE id = '90000000-0000-0000-0000-000000000030')
       OR EXISTS (SELECT 1 FROM scim_group_memberships WHERE id = '90000000-0000-0000-0000-000000000031') THEN
        RAISE EXCEPTION 'Duplicate pair #3 failed: expected deterministic smaller UUID 0030 to survive over 0031';
    END IF;
END $$;

-- Clean up dirty-test workspace so verify-schema.sql can also run cleanly on the migrated DB
DELETE FROM workspaces WHERE id = '77777777-7777-7777-7777-777777777777';

COMMIT;
