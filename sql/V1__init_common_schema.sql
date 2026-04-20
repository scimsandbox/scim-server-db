CREATE TABLE IF NOT EXISTS workspaces (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description VARCHAR(255),
    created_by_username VARCHAR(500),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL
);

ALTER TABLE workspaces
    ADD CONSTRAINT uk_workspaces_created_by_username_name UNIQUE (created_by_username, name);

CREATE INDEX IF NOT EXISTS idx_workspaces_updated_at ON workspaces (updated_at);
CREATE INDEX IF NOT EXISTS idx_workspaces_created_at ON workspaces (created_at DESC);

CREATE TABLE IF NOT EXISTS mgmt_users (
    email VARCHAR(500) PRIMARY KEY,
    last_login_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE IF NOT EXISTS scim_users (
    id UUID PRIMARY KEY,
    workspace_id UUID NOT NULL,
    user_name VARCHAR(255) NOT NULL,
    external_id VARCHAR(255),
    name_formatted VARCHAR(255),
    name_family_name VARCHAR(255),
    name_given_name VARCHAR(255),
    name_middle_name VARCHAR(255),
    name_honorific_prefix VARCHAR(255),
    name_honorific_suffix VARCHAR(255),
    display_name VARCHAR(255),
    nick_name VARCHAR(255),
    profile_url VARCHAR(255),
    title VARCHAR(255),
    user_type VARCHAR(255),
    preferred_language VARCHAR(255),
    locale VARCHAR(255),
    timezone VARCHAR(255),
    active BOOLEAN NOT NULL,
    password VARCHAR(255),
    enterprise_employee_number VARCHAR(255),
    enterprise_cost_center VARCHAR(255),
    enterprise_organization VARCHAR(255),
    enterprise_division VARCHAR(255),
    enterprise_department VARCHAR(255),
    enterprise_manager_value VARCHAR(255),
    enterprise_manager_ref VARCHAR(255),
    enterprise_manager_display VARCHAR(255),
    emails JSON,
    phone_numbers JSON,
    addresses JSON,
    entitlements JSON,
    roles JSON,
    ims JSON,
    photos JSON,
    x509_certificates JSON,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    last_modified TIMESTAMP WITH TIME ZONE NOT NULL,
    version BIGINT,
    CONSTRAINT fk_scim_users_workspace FOREIGN KEY (workspace_id) REFERENCES workspaces (id) ON DELETE CASCADE,
    CONSTRAINT uk_scim_users_workspace_user_name UNIQUE (workspace_id, user_name),
    CONSTRAINT uk_scim_users_id_workspace UNIQUE (id, workspace_id)
);

CREATE INDEX IF NOT EXISTS idx_user_external_id ON scim_users (workspace_id, external_id);

CREATE TABLE IF NOT EXISTS scim_groups (
    id UUID PRIMARY KEY,
    workspace_id UUID NOT NULL,
    external_id VARCHAR(255),
    display_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    last_modified TIMESTAMP WITH TIME ZONE NOT NULL,
    version BIGINT,
    CONSTRAINT fk_scim_groups_workspace FOREIGN KEY (workspace_id) REFERENCES workspaces (id) ON DELETE CASCADE,
    CONSTRAINT uk_scim_groups_workspace_display_name UNIQUE (workspace_id, display_name),
    CONSTRAINT uk_scim_groups_id_workspace UNIQUE (id, workspace_id)
);

CREATE INDEX IF NOT EXISTS idx_group_external_id ON scim_groups (workspace_id, external_id);

CREATE TABLE IF NOT EXISTS scim_group_memberships (
    id UUID PRIMARY KEY,
    group_id UUID NOT NULL,
    workspace_id UUID NOT NULL,
    member_value UUID NOT NULL,
    member_type VARCHAR(255) NOT NULL,
    display VARCHAR(255),
    CONSTRAINT fk_scim_group_memberships_group FOREIGN KEY (group_id, workspace_id)
        REFERENCES scim_groups (id, workspace_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_group_memberships_workspace_group_id ON scim_group_memberships (workspace_id, group_id);
CREATE INDEX IF NOT EXISTS idx_membership_member_value ON scim_group_memberships (member_value);
CREATE INDEX IF NOT EXISTS idx_membership_group_id ON scim_group_memberships (group_id);

CREATE TABLE IF NOT EXISTS workspace_tokens (
    id UUID PRIMARY KEY,
    workspace_id UUID NOT NULL,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description VARCHAR(255),
    expires_at TIMESTAMP WITH TIME ZONE,
    revoked BOOLEAN NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT fk_workspace_tokens_workspace FOREIGN KEY (workspace_id) REFERENCES workspaces (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_workspace_tokens_workspace_id_name ON workspace_tokens (workspace_id, name);

CREATE TABLE IF NOT EXISTS scim_request_logs (
    id UUID PRIMARY KEY,
    workspace_id UUID NOT NULL,
    http_method VARCHAR(255) NOT NULL,
    request_path VARCHAR(255) NOT NULL,
    http_status INTEGER,
    request_body TEXT,
    response_body TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT fk_scim_request_logs_workspace FOREIGN KEY (workspace_id) REFERENCES workspaces (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_scim_request_logs_workspace_created_at ON scim_request_logs (workspace_id, created_at DESC);
