CREATE INDEX IF NOT EXISTS memory_fts
ON memory_index USING fts (title, description, tags, content);
