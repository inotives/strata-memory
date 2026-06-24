# Keep backend-specific index migrations

SQLite and Turso will own separate migration sets because their full-text and vector schemas are not interchangeable. The backends must provide equivalent logical index capabilities and expose their own applied schema version; migration numbers and SQL files do not need to match across backends.
