# Apple Silicon Install Validation — 2026-06-24

Platform: native `Darwin/arm64`

Branch: `feat/phase-6-macos-turso`

## Results

- Shell syntax: pass
- Installer fixture: pass
- Native init, index, search, semantic refresh, semantic status, and doctor smoke: pass
- `STRATA_CARGO_OFFLINE=1` install: pass
- Intel macOS rejection message: pass
- Missing Cargo prerequisite message: pass

Repeat the native acceptance flow with:

```bash
bash test/macos_arm64_smoke.sh
```
