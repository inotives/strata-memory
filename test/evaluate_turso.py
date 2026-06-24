#!/usr/bin/env python3
import json
import os
import platform
import shutil
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "test/fixtures/turso-evaluation"
REPORT = ROOT / "docs/evaluations/turso-v0.6.1.md"
LATEST = ROOT / "docs/evaluations/turso-latest.md"
ENV = {**os.environ, "STRATA_CARGO_OFFLINE": "1"}


def run(*args, capture=False):
    result = subprocess.run(
        [str(arg) for arg in args],
        cwd=ROOT,
        env=ENV,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
        stderr=subprocess.PIPE if capture else subprocess.DEVNULL,
    )
    return result.stdout.strip() if capture else ""


def configure(path, backend):
    text = path.read_text()
    text = text.replace('backend: "sqlite"', f'backend: "{backend}"')
    text = text.replace('provider: ""', 'provider: "builtin-hash"')
    text = text.replace('model: ""', 'model: "hash-v1"')
    text = text.replace("embedding_dim: 0", "embedding_dim: 64")
    path.write_text(text)


def search(binary, vault, query, mode, include_archived=False):
    args = [binary, "search", "--vault", vault, "--query", query, "--limit", "10", "--json"]
    if mode == "hybrid":
        args.append("--hybrid")
    if include_archived:
        args.append("--include-archived")
    payload = json.loads(run(*args, capture=True))
    results = payload["results"]
    paths = [item if isinstance(item, str) else item["path"] for item in results]
    contract_ok = all(
        isinstance(item, str)
        or {"path", "title", "status", "rank", "snippet"}.issubset(item)
        for item in results
    )
    return paths, contract_ok


def measure(command, runs):
    values = []
    run(*command)
    for _ in range(runs):
        started = time.perf_counter()
        run(*command)
        values.append((time.perf_counter() - started) * 1000)
    return values


def summary(values):
    return {
        "median": statistics.median(values),
        "min": min(values),
        "max": max(values),
    }


def fmt(metric):
    return f'{metric["median"]:.2f} ms ({metric["min"]:.2f}-{metric["max"]:.2f})'


def main():
    queries = []
    for line in (FIXTURE / "queries.tsv").read_text().splitlines():
        name, mode, query, expected, archived = line.split("\t")
        queries.append((name, mode, query, expected, archived == "true"))

    with tempfile.TemporaryDirectory(prefix="strata-turso-evaluation-") as temp:
        vault = Path(temp) / "vault"
        run(ROOT / "install.sh", "--vault", vault)
        shutil.copytree(FIXTURE / "2_knowledge", vault / "2_knowledge", dirs_exist_ok=True)
        binary = vault / "0_core/bin/strata"
        config = vault / "0_core/config/configs.yaml"
        original_config = config.read_text()
        results = {}

        for backend in ("sqlite", "turso"):
            config.write_text(original_config)
            configure(config, backend)
            run(binary, "refresh", "--vault", vault)
            run(binary, "semantic-refresh", "--vault", vault)

            correctness = {}
            fts_times = []
            hybrid_times = []
            for name, mode, query, expected, include_archived in queries:
                paths, contract_ok = search(
                    binary, vault, query, mode, include_archived
                )
                correctness[name] = {
                    "paths": paths,
                    "expected": expected,
                    "contract_ok": contract_ok,
                }
                command = [
                    binary,
                    "search",
                    "--vault",
                    vault,
                    "--query",
                    query,
                    "--limit",
                    "10",
                    "--json",
                ]
                if mode == "hybrid":
                    command.append("--hybrid")
                if include_archived:
                    command.append("--include-archived")
                timings = measure(command, 10)
                (hybrid_times if mode == "hybrid" else fts_times).extend(timings)

            refresh_times = measure(
                [binary, "refresh", "--vault", vault], 3
            )
            db = vault / "0_core/db" / (
                "strata.db" if backend == "sqlite" else "strata-turso.db"
            )
            size = sum(
                path.stat().st_size
                for path in db.parent.iterdir()
                if path.name.startswith(db.name)
            )
            results[backend] = {
                "correctness": correctness,
                "refresh": summary(refresh_times),
                "fts": summary(fts_times),
                "hybrid": summary(hybrid_times),
                "size": size,
            }

        config.write_text(original_config)
        configure(config, "turso")
        interrupted = subprocess.Popen(
            [binary, "refresh", "--vault", vault],
            cwd=ROOT,
            env=ENV,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        interrupted.kill()
        interrupted.wait()
        run(binary, "refresh", "--vault", vault)
        recovery_paths, _ = search(binary, vault, "Quantum Ledger", "fts")
        recovery_ok = recovery_paths[:1] == [
            "2_knowledge/research/quantum-ledger.md"
        ]

    failed = []
    parity_rows = []
    for name, _, _, expected, _ in queries:
        sqlite = results["sqlite"]["correctness"][name]
        turso = results["turso"]["correctness"][name]
        sqlite_top = sqlite["paths"][0] if sqlite["paths"] else ""
        turso_top = turso["paths"][0] if turso["paths"] else ""
        union = set(sqlite["paths"]) | set(turso["paths"])
        overlap = (
            1.0
            if not union
            else len(set(sqlite["paths"]) & set(turso["paths"])) / len(union)
        )
        expected_ok = sqlite_top == expected and turso_top == expected
        parity_ok = sqlite_top == turso_top and overlap >= 0.8
        contract_ok = sqlite["contract_ok"] and turso["contract_ok"]
        if not expected_ok:
            failed.append(f"{name}: expected top result mismatch")
        if not parity_ok:
            failed.append(f"{name}: top result or top-ten overlap mismatch")
        if not contract_ok:
            failed.append(f"{name}: output contract mismatch")
        parity_rows.append((name, sqlite_top, turso_top, overlap))

    ratios = {
        key: results["turso"][key]["median"] / results["sqlite"][key]["median"]
        for key in ("refresh", "fts", "hybrid")
    }
    size_ratio = results["turso"]["size"] / results["sqlite"]["size"]
    for label, ratio in ratios.items():
        if ratio > 2:
            failed.append(f"{label} latency ratio {ratio:.2f} exceeds 2x")
    if size_ratio > 2:
        failed.append(f"database size ratio {size_ratio:.2f} exceeds 2x")
    if not recovery_ok:
        failed.append("interrupted refresh recovery failed")
    failed.append("Linux validation pending")
    verdict = "continue-evaluation"

    lines = [
        "# Turso 0.6.1 Evaluation",
        "",
        f"- Platform: `{platform.system()}/{platform.machine()}`",
        "- SQLite remains the default backend.",
        "- Dataset: committed synthetic fixture only; private-vault benchmarking was not run.",
        "",
        "## Correctness",
        "",
        "| Query | SQLite top | Turso top | Top-10 overlap |",
        "|---|---|---|---:|",
    ]
    for name, sqlite_top, turso_top, overlap in parity_rows:
        lines.append(
            f"| {name} | `{sqlite_top or '(none)'}` | `{turso_top or '(none)'}` | {overlap:.0%} |"
        )
    lines += [
        "",
        "## Aggregate Measurements",
        "",
        "| Metric | SQLite | Turso | Ratio |",
        "|---|---:|---:|---:|",
        f'| Full refresh | {fmt(results["sqlite"]["refresh"])} | {fmt(results["turso"]["refresh"])} | {ratios["refresh"]:.2f}x |',
        f'| FTS query | {fmt(results["sqlite"]["fts"])} | {fmt(results["turso"]["fts"])} | {ratios["fts"]:.2f}x |',
        f'| Hybrid query | {fmt(results["sqlite"]["hybrid"])} | {fmt(results["turso"]["hybrid"])} | {ratios["hybrid"]:.2f}x |',
        f'| Index size | {results["sqlite"]["size"]} bytes | {results["turso"]["size"]} bytes | {size_ratio:.2f}x |',
        "",
        f"- Interrupted refresh recovery: {'pass' if recovery_ok else 'fail'}",
        "- Search timing: one warm-up plus ten runs per curated query.",
        "- Refresh timing: one warm-up plus three runs per backend.",
        "",
        "## Failed Gates",
        "",
    ]
    lines.extend(f"- {item}" for item in failed)
    lines += ["", "## Verdict", "", verdict, ""]
    REPORT.write_text("\n".join(lines))
    LATEST.write_text(
        "# Latest Turso Evaluation\n\nSee [Turso 0.6.1 evaluation](turso-v0.6.1.md).\n"
    )
    print(REPORT)
    print(f"verdict={verdict}")


if __name__ == "__main__":
    main()
