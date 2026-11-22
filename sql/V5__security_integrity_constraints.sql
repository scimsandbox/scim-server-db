-- Forward security & integrity constraints migration (V5).
--
-- 1. scim_users.password is a writeOnly SCIM attribute ("returned": "never", RFC 7643 §7).
--    Any pre-BCrypt plaintext or empty-string values written before BCrypt enforcement are
--    cleared to NULL before adding chk_scim_users_password_bcrypt.
--
-- 2. workspace_tokens and scim_group_memberships are deliberately NOT auto-mutated: if an
--    environment contains non-compliant rows, Flyway aborts the migration transaction so an
--    operator can inspect and reconcile them rather than losing data silently:
--
--      -- Non-lowercase-64-hex token hashes:
--      SELECT id, workspace_id, name FROM workspace_tokens WHERE token_hash !~ '^[0-9a-f]{64}$';
--
--      -- Self-referential, invalid member_type, or duplicate group memberships:
--      SELECT id, workspace_id, group_id, member_value, member_type
--        FROM scim_group_memberships
--       WHERE member_value = group_id OR member_type NOT IN ('User', 'Group', '');
--
--      SELECT workspace_id, group_id, member_value, COUNT(*)
--        FROM scim_group_memberships
--       GROUP BY workspace_id, group_id, member_value
--      HAVING COUNT(*) > 1;

DO $$
DECLARE
    cleared_passwords BIGINT := 0;
BEGIN
    UPDATE scim_users
    SET password = NULL
    WHERE password IS NOT NULL
      AND password !~ '^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$';
    GET DIAGNOSTICS cleared_passwords = ROW_COUNT;
    IF cleared_passwords > 0 THEN
        RAISE NOTICE 'V5: cleared % legacy non-BCrypt scim_users.password value(s) to NULL', cleared_passwords;
    END IF;
END $$;

ALTER TABLE scim_users
    ADD CONSTRAINT chk_scim_users_password_bcrypt
        CHECK (password IS NULL OR password ~ '^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$');

ALTER TABLE workspace_tokens
    ALTER COLUMN revoked SET DEFAULT FALSE,
    ADD CONSTRAINT chk_workspace_tokens_hash_format
        CHECK (token_hash ~ '^[0-9a-f]{64}$');

ALTER TABLE scim_group_memberships
    ADD CONSTRAINT uk_scim_group_memberships_workspace_group_member
        UNIQUE (workspace_id, group_id, member_value),
    ADD CONSTRAINT chk_scim_group_memberships_member_type
        CHECK (member_type IN ('User', 'Group', '')),
    ADD CONSTRAINT chk_scim_group_memberships_no_self_ref
        CHECK (member_value <> group_id);

-- Covered by leading columns of uk_scim_group_memberships_workspace_group_member (workspace_id, group_id, member_value)
DROP INDEX IF EXISTS idx_group_memberships_workspace_group_id;
