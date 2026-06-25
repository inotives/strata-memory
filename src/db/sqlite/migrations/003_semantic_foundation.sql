CREATE TABLE IF NOT EXISTS semantic_models (
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  embedding_dim INTEGER,
  configured_at TEXT NOT NULL,
  PRIMARY KEY (provider, model)
);

CREATE TABLE IF NOT EXISTS semantic_embeddings (
  path TEXT NOT NULL,
  target_type TEXT NOT NULL CHECK(target_type IN ('description', 'section')),
  section_start_line INTEGER,
  content_hash TEXT NOT NULL,
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  embedding_dim INTEGER NOT NULL,
  vector BLOB,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (path, target_type, section_start_line, provider, model)
);

CREATE INDEX IF NOT EXISTS semantic_embeddings_content_hash_idx
ON semantic_embeddings(content_hash);
