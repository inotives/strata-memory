CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts USING fts5(
  title,
  description,
  tags,
  content,
  content='memory_index',
  content_rowid='rowid'
);
