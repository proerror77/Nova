-- Message reactions (emoji reactions on messages)
CREATE TABLE IF NOT EXISTS message_reactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id UUID NOT NULL,
    user_id UUID NOT NULL,
    emoji VARCHAR(20) NOT NULL,  -- Unicode emoji or emoji code (😀, :smile:, etc)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_reactions_message FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
    CONSTRAINT fk_reactions_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT unique_reaction UNIQUE(message_id, user_id, emoji)
);

CREATE INDEX idx_reactions_message_id ON message_reactions(message_id);
CREATE INDEX idx_reactions_user_id ON message_reactions(user_id);
CREATE INDEX idx_reactions_created_at ON message_reactions(created_at DESC);

-- File attachments (for messages with files)
CREATE TABLE IF NOT EXISTS message_attachments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id UUID NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    file_type VARCHAR(100),  -- MIME type
    file_size INT NOT NULL,  -- bytes
    s3_key VARCHAR(500) NOT NULL,  -- S3 object key for retrieval
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_attachments_message FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);

CREATE INDEX idx_attachments_message_id ON message_attachments(message_id);
CREATE INDEX idx_attachments_created_at ON message_attachments(created_at DESC);
