# Mark Turso as experimental without noisy search output

When Turso is active, `db-migrate`, `refresh`, `semantic-status`, and `doctor` will show one concise experimental-backend warning, and relevant JSON output will include `experimental: true`. Normal search result output will not repeat the warning on every invocation; errors still identify Turso explicitly.
