CREATE TABLE IF NOT EXISTS schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS memory_index (
  id TEXT PRIMARY KEY,
  path TEXT UNIQUE NOT NULL,
  title TEXT,
  description TEXT,
  strata TEXT NOT NULL CHECK(strata IN ('1_draft', '2_knowledge', '3_intelligence', '0_core')),
  status TEXT NOT NULL CHECK(status IN ('pending', 'verified', 'archived', 'generated', 'core')),
  tags TEXT,
  sources TEXT,
  source_note TEXT,
  version INTEGER DEFAULT 1,
  last_edit_summary TEXT,
  created TEXT,
  modified TEXT,
  content TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  metadata TEXT
);

CREATE TABLE IF NOT EXISTS links (
  source_path TEXT NOT NULL,
  target TEXT NOT NULL,
  target_type TEXT NOT NULL CHECK(target_type IN ('local', 'url', 'unresolved')),
  link_text TEXT,
  line INTEGER,
  created_at TEXT NOT NULL,
  PRIMARY KEY (source_path, target, line)
);

CREATE TABLE IF NOT EXISTS sections (
  path TEXT NOT NULL,
  heading TEXT NOT NULL,
  level INTEGER NOT NULL,
  start_line INTEGER NOT NULL,
  end_line INTEGER,
  content TEXT NOT NULL,
  PRIMARY KEY (path, start_line)
);
