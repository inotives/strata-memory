# Fix benchmark sample counts

Each search benchmark will discard one warm-up and record ten measured runs per query. Full refresh benchmarks will discard one warm-up and record three measured runs because rebuilds are substantially more expensive; reports include the median and observed minimum-to-maximum range.
