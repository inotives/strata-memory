# Compare search relevance rather than backend-specific scores

SQLite and Turso search parity will compare result paths, ordering, filters, snippets, and output contracts rather than exact numeric ranks. For the curated evaluation query set, both backends must return the same top result and have at least 80% overlap among the top ten results; backend-specific score values may differ.
