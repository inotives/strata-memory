# Share index domain data rather than database primitives

Markdown parsing and filesystem traversal will produce backend-neutral index data such as documents, sections, links, embeddings, and search results. SQLite and Turso adapters will persist and query those values independently; connection types, transactions, statements, rows, and backend SQL will not enter the shared indexing layer.
