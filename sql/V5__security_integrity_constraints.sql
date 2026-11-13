-- Forward security & integrity constraints migration (V5).
--
-- Hardens credential hash storage and group membership invariants across existing
-- multi-tenant tables without breaking databases that contain pre-V5 legacy rows:
-- 1. Sanitizes any legacy non-BCrypt scim_users.password values to NULL before
--    enforcing modular crypt BCrypt ($2a$/$2b$/$2y$) format.
-- 2. Removes any malformed workspace_tokens rows and enforces 64-char hex SHA-256
--    token_hash format plus DEFAULT FALSE on revoked.
-- 3. Removes self-referential (member_value = group_id) and duplicate
--    (workspace_id, group_id, member_value) rows in scim_group_memberships,
--    normalizes unexpected member_type values to '', and enforces uniqueness,
--    allowed member_type domain ('User', 'Group', ''), and non-self-membership.

-- 1. Clean legacy scim_users password rows that are not valid 60-character BCrypt hashes
UPDATE scim_users
SET password = NULL
WHERE password IS NOT NULL
  AND password !~ '^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$';

ALTER TABLE scim_users
    ADD CONSTRAINT chk_scim_users_password_bcrypt
        CHECK (password IS NULL OR password ~ '^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$');

-- 2. Clean any malformed token hashes and enforce 64-hex SHA-256 format on workspace_tokens
DELETE FROM workspace_tokens
WHERE token_hash !~ '^[0-9a-fA-F]{64}$';

ALTER TABLE workspace_tokens
    ALTER COLUMN revoked SET DEFAULT FALSE,
    ADD CONSTRAINT chk_workspace_tokens_hash_format
        CHECK (token_hash ~ '^[0-9a-fA-F]{64}$');

-- 3. Clean legacy scim_group_memberships anomalies before adding constraints
DELETE FROM scim_group_memberships
WHERE member_value = group_id;

UPDATE scim_group_memberships
SET member_type = ''
WHERE member_type IS NOT NULL
  AND member_type NOT IN ('User', 'Group', '');

DELETE FROM scim_group_memberships m
USING (
    SELECT id,
           ROW_NUMBER() OVER (
               PARTITION BY workspace_id, group_id, member_value
               ORDER BY CASE WHEN member_type IN ('User', 'Group') THEN 0 ELSE 1 END,
                        id
           ) AS rn
    FROM scim_group_memberships
) dupes
WHERE m.id = dupes.id
  AND dupes.rn > 1;

ALTER TABLE scim_group_memberships
    ADD CONSTRAINT uk_scim_group_memberships_workspace_group_member
        UNIQUE (workspace_id, group_id, member_value),
    ADD CONSTRAINT chk_scim_group_memberships_member_type
        CHECK (member_type IS NULL OR member_type IN ('User', 'Group', '')),
    ADD CONSTRAINT chk_scim_group_memberships_no_self_ref
        CHECK (member_value <> group_id);
