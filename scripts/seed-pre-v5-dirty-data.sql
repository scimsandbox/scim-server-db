-- scripts/seed-pre-v5-dirty-data.sql
-- Seeds representative pre-V5 legacy/dirty rows into a V4 schema so CI exercises
-- every V5 normalization, deduplication, and cleanup branch before constraints apply.

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO workspaces (id, name, description, created_by_username, created_at, updated_at)
VALUES (
    '77777777-7777-7777-7777-777777777777',
    'dirty-v5-migration-ws',
    'Pre-V5 dirty data migration test workspace',
    'ci-runner',
    NOW(),
    NOW()
);

-- 1. scim_users password variants:
--    0001: valid BCrypt ($2b$, 60 chars) -> preserved
--    0002: NULL                          -> preserved
--    0003: '' (empty string)             -> cleared_empty_passwords (#1)
--    0004: 'plaintext-secret'            -> nullified_passwords (#1)
--    0005: '$2a$hello' (bad prefix)      -> nullified_passwords (#2)
INSERT INTO scim_users (id, workspace_id, user_name, active, password, created_at, last_modified)
VALUES
    ('71000000-0000-0000-0000-000000000001', '77777777-7777-7777-7777-777777777777', 'valid-bcrypt@example.com', TRUE, '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', NOW(), NOW()),
    ('71000000-0000-0000-0000-000000000002', '77777777-7777-7777-7777-777777777777', 'null-pw@example.com', TRUE, NULL, NOW(), NOW()),
    ('71000000-0000-0000-0000-000000000003', '77777777-7777-7777-7777-777777777777', 'empty-pw@example.com', TRUE, '', NOW(), NOW()),
    ('71000000-0000-0000-0000-000000000004', '77777777-7777-7777-7777-777777777777', 'plain-pw@example.com', TRUE, 'plaintext-secret', NOW(), NOW()),
    ('71000000-0000-0000-0000-000000000005', '77777777-7777-7777-7777-777777777777', 'prefix-pw@example.com', TRUE, '$2a$hello', NOW(), NOW());

-- 2. workspace_tokens variants:
--    0001: valid lowercase 64-hex                         -> preserved
--    0002: valid uppercase 64-hex (unique)                -> lowercased (#1)
--    0003: lowercase 64-hex in collision pair #1          -> preserved
--    0004: uppercase 64-hex colliding w/ 0003             -> deleted (#1 colliding)
--    0005: malformed non-hex token_hash                   -> deleted (#1 malformed)
--    0006: mixed-case 64-hex in upper-only pair #2 (newer)-> survives & lowercased (#2)
--    0007: mixed-case 64-hex colliding w/ 0006 (older)    -> deleted (#2 colliding)
INSERT INTO workspace_tokens (id, workspace_id, token_hash, name, revoked, created_at, updated_at)
VALUES
    ('72000000-0000-0000-0000-000000000001', '77777777-7777-7777-7777-777777777777', '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef', 'valid-lower', FALSE, NOW(), NOW()),
    ('72000000-0000-0000-0000-000000000002', '77777777-7777-7777-7777-777777777777', 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', 'valid-upper', FALSE, NOW(), NOW()),
    ('72000000-0000-0000-0000-000000000003', '77777777-7777-7777-7777-777777777777', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'collide-lower', FALSE, NOW(), NOW()),
    ('72000000-0000-0000-0000-000000000004', '77777777-7777-7777-7777-777777777777', 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB', 'collide-upper', FALSE, NOW(), NOW()),
    ('72000000-0000-0000-0000-000000000005', '77777777-7777-7777-7777-777777777777', 'not-a-valid-sha256-token-hash', 'malformed', FALSE, NOW(), NOW()),
    ('72000000-0000-0000-0000-000000000006', '77777777-7777-7777-7777-777777777777', 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDd', 'collide-mixed-newer', FALSE, NOW() + INTERVAL '1 minute', NOW()),
    ('72000000-0000-0000-0000-000000000007', '77777777-7777-7777-7777-777777777777', 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddD', 'collide-mixed-older', FALSE, NOW() - INTERVAL '1 minute', NOW());

-- 3. scim_groups and scim_group_memberships variants:
INSERT INTO scim_groups (id, workspace_id, display_name, created_at, last_modified)
VALUES
    ('81000000-0000-0000-0000-000000000001', '77777777-7777-7777-7777-777777777777', 'Parent Group', NOW(), NOW()),
    ('81000000-0000-0000-0000-000000000002', '77777777-7777-7777-7777-777777777777', 'Dedup Group', NOW(), NOW()),
    ('81000000-0000-0000-0000-000000000003', '77777777-7777-7777-7777-777777777777', 'Nested Child Group', NOW(), NOW());

INSERT INTO scim_group_memberships (id, group_id, workspace_id, member_value, member_type, display)
VALUES
    -- Self-referential membership -> deleted (#1 self-ref)
    ('90000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', '77777777-7777-7777-7777-777777777777', '81000000-0000-0000-0000-000000000001', 'Group', 'Self Ref'),
    -- Case/whitespace variants of known member_type values -> normalized (#1..#3)
    ('90000000-0000-0000-0000-000000000002', '81000000-0000-0000-0000-000000000001', '77777777-7777-7777-7777-777777777777', '81000000-0000-0000-0000-000000000002', 'group', 'Lowercase Group'),
    ('90000000-0000-0000-0000-000000000003', '81000000-0000-0000-0000-000000000001', '77777777-7777-7777-7777-777777777777', '71000000-0000-0000-0000-000000000001', ' USER ', 'Padded Uppercase User'),
    ('90000000-0000-0000-0000-000000000004', '81000000-0000-0000-0000-000000000001', '77777777-7777-7777-7777-777777777777', '71000000-0000-0000-0000-000000000002', '   ', 'Whitespace Untyped'),
    -- Truly unknown member_type -> blanked (#1 unknown)
    ('90000000-0000-0000-0000-000000000005', '81000000-0000-0000-0000-000000000001', '77777777-7777-7777-7777-777777777777', '71000000-0000-0000-0000-000000000003', 'Robot', 'Unknown Type'),
    -- Duplicate pair #1 in Dedup Group: 0011 ('group' -> normalized #4 to 'Group') beats 0010 ('')
    ('90000000-0000-0000-0000-000000000010', '81000000-0000-0000-0000-000000000002', '77777777-7777-7777-7777-777777777777', '81000000-0000-0000-0000-000000000003', '', 'Untyped Subteam'),
    ('90000000-0000-0000-0000-000000000011', '81000000-0000-0000-0000-000000000002', '77777777-7777-7777-7777-777777777777', '81000000-0000-0000-0000-000000000003', 'group', NULL),
    -- Duplicate pair #2 in Dedup Group: 0021 (non-empty display) beats 0020 (blank display)
    ('90000000-0000-0000-0000-000000000020', '81000000-0000-0000-0000-000000000002', '77777777-7777-7777-7777-777777777777', '71000000-0000-0000-0000-000000000001', 'User', '   '),
    ('90000000-0000-0000-0000-000000000021', '81000000-0000-0000-0000-000000000002', '77777777-7777-7777-7777-777777777777', '71000000-0000-0000-0000-000000000001', 'User', 'Alice Canonical'),
    -- Duplicate pair #3 in Dedup Group: 0030 (smaller id) beats 0031 (larger id)
    ('90000000-0000-0000-0000-000000000030', '81000000-0000-0000-0000-000000000002', '77777777-7777-7777-7777-777777777777', '71000000-0000-0000-0000-000000000002', 'User', 'Bob First'),
    ('90000000-0000-0000-0000-000000000031', '81000000-0000-0000-0000-000000000002', '77777777-7777-7777-7777-777777777777', '71000000-0000-0000-0000-000000000002', 'User', 'Bob Second');

COMMIT;
