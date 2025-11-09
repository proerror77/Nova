-- Migration: 双因素认证 (2FA) 表和字段
-- 遵循 Linus 设计原则: 备用码独立表，不存储 JSON 哈希

-- 1. 用户表添加 2FA 字段
ALTER TABLE users ADD COLUMN totp_secret VARCHAR(32) NULL;
ALTER TABLE users ADD COLUMN totp_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN two_fa_enabled_at TIMESTAMP WITH TIME ZONE NULL;

-- 2. 创建备用码独立表 (Linus 正确方案)
CREATE TABLE two_fa_backup_codes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_hash VARCHAR(64) NOT NULL UNIQUE,  -- SHA256 哈希
    is_used BOOLEAN NOT NULL DEFAULT FALSE,
    used_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    -- 数据一致性约束: 已使用需要有时间戳，未使用则 NULL
    CONSTRAINT used_consistency CHECK (
        (is_used = FALSE AND used_at IS NULL) OR
        (is_used = TRUE AND used_at IS NOT NULL)
    )
);

-- 创建索引优化查询
CREATE INDEX idx_backup_codes_user_id ON two_fa_backup_codes(user_id);
CREATE INDEX idx_backup_codes_hash ON two_fa_backup_codes(code_hash);
-- 优化: 查询未使用的备用码
CREATE INDEX idx_backup_codes_unused ON two_fa_backup_codes(user_id, is_used) WHERE is_used = FALSE;

-- 3. 创建 2FA 会话表 (用于临时 2FA 验证状态)
CREATE TABLE two_fa_sessions (
    session_id VARCHAR(64) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL
);

-- 创建索引用于快速过期清理
CREATE INDEX idx_two_fa_sessions_expires ON two_fa_sessions(expires_at);

-- 4. 为 auth_logs 添加 2FA 相关类型支持
-- auth_logs 表已在 002 迁移中创建，不需要修改

-- 5. 审计日志: 记录 2FA 启用/禁用事件
-- 这通过应用代码在 auth_logs 中记录，event_type 使用 'totp_enabled' / 'totp_disabled' / '2fa_verified'
