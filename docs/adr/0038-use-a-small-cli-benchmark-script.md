# Use a small CLI benchmark script

Phase 6 performance measurements will use a repository script that invokes the real Strata CLI, discards one warm-up run, records repeated wall-clock timings with the platform time utility, and reports the median. Strata will not add a benchmarking framework dependency for this evaluation.
