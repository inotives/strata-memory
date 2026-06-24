# Require native Apple Silicon validation

Apple Silicon support requires tests to execute natively on `aarch64-apple-darwin`. Use a native macOS ARM CI runner when available; otherwise run and record the documented local smoke workflow on Apple Silicon hardware. Cross-compilation alone does not qualify the platform as supported.
