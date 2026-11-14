-- Forward security & integrity constraints migration (V5).
--
-- Hardens credential hash storage and group membership invariants across existing
-- multi-tenant tables while auditing and normalizing pre-V5 legacy rows:
-- 1. Sanitizes legacy non-BCrypt (including empty-string) scim_users.password values
--    to NULL before enforcing modular crypt BCrypt ($2a$/$2b$/$2y$) format.
-- 2. Removes malformed workspace_tokens rows, resolves any hex-case collisions,
--    normalizes valid 64-hex digests to lowercase, and enforces lowercase 64-hex
--    SHA-256 token_hash format plus DEFAULT FALSE on revoked.
-- 3. Removes self-referential (member_value = group_id) rows in scim_group_memberships,
--    normalizes case/whitespace variants of member_type ('User', 'Group', '') before
--    blanking unrecognized values, deduplicates (workspace_id, group_id, member_value)
--    deterministically, enforces uniqueness, allowed member_type domain, and
--    non-self-membership, and drops the redundant (workspace_id, group_id) index.

DO $$
DECLARE
    cleared_empty_passwords       BIGINT := 0;
    nullified_passwords           BIGINT := 0;
    deleted_malformed_tokens      BIGINT := 0;
    deleted_colliding_tokens      BIGINT := 0;
    lowercased_tokens             BIGINT := 0;
    deleted_self_memberships      BIGINT := 0;
    normalized_member_types       BIGINT := 0;
    blanked_unknown_member_types  BIGINT := 0;
    deleted_duplicate_memberships BIGINT := 0;
BEGIN
    -- 1a. Normalize benign legacy empty-string scim_users.password values ('') to NULL
    UPDATE scim_users
    SET password = NULL
    WHERE password = '';
    GET DIAGNOSTICS cleared_empty_passwords = ROW_COUNT;
    IF cleared_empty_passwords > 0 THEN
        RAISE NOTICE 'V5 cleanup: normalized % empty scim_users.password value(s) to NULL', cleared_empty_passwords;
    END IF;

    -- 1b. Nullify remaining non-BCrypt scim_users.password values (plaintext or malformed hashes)
    UPDATE scim_users
    SET password = NULL
    WHERE password IS NOT NULL
      AND password !~ '^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$';
    GET DIAGNOSTICS nullified_passwords = ROW_COUNT;
    IF nullified_passwords > 0 THEN
        RAISE WARNING 'V5 cleanup: nullified % non-BCrypt scim_users.password value(s)', nullified_passwords;
    END IF;

    -- 2a. Delete workspace_tokens rows whose token_hash is not a 64-character hex SHA-256 digest
    DELETE FROM workspace_tokens
    WHERE token_hash !~ '^[0-9a-fA-F]{64}$';
    GET DIAGNOSTICS deleted_malformed_tokens = ROW_COUNT;
    IF deleted_malformed_tokens > 0 THEN
        RAISE WARNING 'V5 cleanup: deleted % malformed workspace_tokens row(s)', deleted_malformed_tokens;
    END IF;

    -- 2b. Resolve case-only 64-hex collisions before lowercasing (workspace_tokens.token_hash is UNIQUE)
    DELETE FROM workspace_tokens t
    USING (
        SELECT id,
               ROW_NUMBER() OVER (
                   PARTITION BY LOWER(token_hash)
                   ORDER BY CASE WHEN token_hash = LOWER(token_hash) THEN 0 ELSE 1 END,
                            CASE WHEN revoked = FALSE THEN 0 ELSE 1 END,
                            created_at DESC,
                            id ASC
               ) AS rn
        FROM workspace_tokens
    ) dupes
    WHERE t.id = dupes.id
      AND dupes.rn > 1;
    GET DIAGNOSTICS deleted_colliding_tokens = ROW_COUNT;
    IF deleted_colliding_tokens > 0 THEN
        RAISE WARNING 'V5 cleanup: deleted % case-colliding workspace_tokens row(s)', deleted_colliding_tokens;
    END IF;

    -- 2c. Normalize any uppercase/mixed-case 64-hex token_hash digests to lowercase
    UPDATE workspace_tokens
    SET token_hash = LOWER(token_hash)
    WHERE token_hash <> LOWER(token_hash);
    GET DIAGNOSTICS lowercased_tokens = ROW_COUNT;
    IF lowercased_tokens > 0 THEN
        RAISE WARNING 'V5 cleanup: normalized % uppercase workspace_tokens.token_hash row(s) to lowercase', lowercased_tokens;
    END IF;

    -- 3a. Delete self-referential group memberships
    DELETE FROM scim_group_memberships
    WHERE member_value = group_id;
    GET DIAGNOSTICS deleted_self_memberships = ROW_COUNT;
    IF deleted_self_memberships > 0 THEN
        RAISE WARNING 'V5 cleanup: deleted % self-referential scim_group_memberships row(s)', deleted_self_memberships;
    END IF;

    -- 3b. Normalize case/whitespace variants of known member_type values ('User', 'Group', '') first
    UPDATE scim_group_memberships
    SET member_type = CASE
        WHEN LOWER(BTRIM(member_type)) = 'user' THEN 'User'
        WHEN LOWER(BTRIM(member_type)) = 'group' THEN 'Group'
        ELSE ''
    END
    WHERE member_type IS NOT NULL
      AND member_type NOT IN ('User', 'Group', '')
      AND LOWER(BTRIM(member_type)) IN ('user', 'group', '');
    GET DIAGNOSTICS normalized_member_types = ROW_COUNT;
    IF normalized_member_types > 0 THEN
        RAISE WARNING 'V5 cleanup: normalized % non-canonical scim_group_memberships.member_type row(s)', normalized_member_types;
    END IF;

    -- 3c. Blank only genuinely unrecognized member_type values
    UPDATE scim_group_memberships
    SET member_type = ''
    WHERE member_type IS NOT NULL
      AND member_type NOT IN ('User', 'Group', '');
    GET DIAGNOSTICS blanked_unknown_member_types = ROW_COUNT;
    IF blanked_unknown_member_types > 0 THEN
        RAISE WARNING 'V5 cleanup: blanked % unrecognized scim_group_memberships.member_type row(s)', blanked_unknown_member_types;
    END IF;

    -- 3d. Deduplicate (workspace_id, group_id, member_value), preferring canonical member_type,
    --     then non-empty display, then deterministic id ASC
    DELETE FROM scim_group_memberships m
    USING (
        SELECT id,
               ROW_NUMBER() OVER (
                   PARTITION BY workspace_id, group_id, member_value
                   ORDER BY CASE WHEN member_type IN ('User', 'Group') THEN 0 ELSE 1 END,
                            CASE WHEN display IS NOT NULL AND BTRIM(display) <> '' THEN 0 ELSE 1 END,
                            id ASC
               ) AS rn
        FROM scim_group_memberships
    ) dupes
    WHERE m.id = dupes.id
      AND dupes.rn > 1;
    GET DIAGNOSTICS deleted_duplicate_memberships = ROW_COUNT;
    IF deleted_duplicate_memberships > 0 THEN
        RAISE WARNING 'V5 cleanup: deleted % duplicate scim_group_memberships row(s)', deleted_duplicate_memberships;
    END IF;

    RAISE NOTICE 'V5 security integrity summary: cleared_empty_passwords=%, nullified_passwords=%, deleted_malformed_tokens=%, deleted_colliding_tokens=%, lowercased_tokens=%, deleted_self_memberships=%, normalized_member_types=%, blanked_unknown_member_types=%, deleted_duplicate_memberships=%',
        cleared_empty_passwords,
        nullified_passwords,
        deleted_malformed_tokens,
        deleted_colliding_tokens,
        lowercased_tokens,
        deleted_self_memberships,
        normalized_member_types,
        blanked_unknown_member_types,
        deleted_duplicate_memberships;
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

-- Redundant with leading columns of uk_scim_group_memberships_workspace_group_member (workspace_id, group_id, member_value)
DROP INDEX IF EXISTS idx_group_memberships_workspace_group_id;
