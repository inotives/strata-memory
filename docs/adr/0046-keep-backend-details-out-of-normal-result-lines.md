# Keep backend details out of normal result lines

Human output will identify the active index backend in `db-migrate`, `semantic-status`, and `doctor`, and every backend-specific error will name it. Normal search result lines and routine index/refresh success output remain concise unless backend identity is needed to diagnose behavior.
