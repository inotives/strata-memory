# Extract SQLite behind the backend contract first

Implementation will first move the existing SQLite behavior behind the new operation-level backend module and restore the full current test suite before adding Turso code. This checkpoint separates regressions caused by restructuring from incompatibilities in the experimental backend.
