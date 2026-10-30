#!/usr/bin/env python3
"""Summarize explicit local ASRBenchmark reports; never reads app settings or recordings."""
import argparse
import json
import math
import re
import unicodedata
from pathlib import Path


def normalized(text):
    return "".join(c for c in unicodedata.normalize("NFKC", text).lower()
                   if not c.isspace() and not unicodedata.category(c).startswith("P"))


def alignment(reference, transcript):
    # Keep the alignment to count deletions and term occurrences at their actual positions.
    n, m = len(reference), len(transcript)
    matrix = [list(range(m + 1))] + [[i] + [0] * m for i in range(1, n + 1)]
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            matrix[i][j] = min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1,
                               matrix[i - 1][j - 1] + (reference[i - 1] != transcript[j - 1]))
    i, j = n, m
    positions, deletions = {}, 0
    while i or j:
        if i and j and matrix[i][j] == matrix[i - 1][j - 1] + (reference[i - 1] != transcript[j - 1]):
            if reference[i - 1] == transcript[j - 1]:
                positions[i - 1] = j - 1
            i, j = i - 1, j - 1
        elif i and matrix[i][j] == matrix[i - 1][j] + 1:
            deletions += 1
            i -= 1
        else:
            j -= 1
    return matrix[n][m], deletions, positions


def percentile(values, quantile):
    values = sorted(values)
    return values[max(0, math.ceil(len(values) * quantile) - 1)] if values else None


def summarize(report):
    first_runs = {r["id"]: r for r in report["results"] if r["iteration"] == 1}
    total, errors, deletions, term_total, term_errors = 0, 0, 0, 0, 0
    chinese_total, chinese_errors = 0, 0
    term_status = {}
    for sample in report["samples"]:
        result = first_runs[sample["id"]]
        reference = normalized(sample["reference"])
        transcript = normalized(result.get("transcript") or "")
        count, missing, positions = alignment(reference, transcript)
        total += len(reference)
        errors += count
        deletions += missing
        if sample["category"] in ("chinese", "ordinary_chinese"):
            chinese_total += len(reference)
            chinese_errors += count
        for term in sample.get("terms") or []:
            matches = list(re.finditer(re.escape(normalized(term)), reference))
            if not matches:
                raise ValueError(f"Term label absent from reference: {sample['id']}")
            for match in matches:
                indexes = [positions.get(k) for k in range(match.start(), match.end())]
                correct = all(k is not None for k in indexes) and indexes == list(range(indexes[0], indexes[0] + len(indexes)))
                key = f"{sample['id']}:{match.start()}:{match.end()}"
                term_status[key] = correct
                term_total += 1
                term_errors += not correct
    latency = [r["elapsedSeconds"] for r in report["results"] if r.get("error") is None]
    long_latency = [r["elapsedSeconds"] for r in report["results"]
                    if r.get("error") is None and 10 <= r["durationSeconds"] <= 30]
    summary = {
        "condition": report["condition"], "model": report["model"],
        "sources": sorted({s.get("source", "unknown") for s in report["samples"]}),
        "splits": sorted({s.get("split", "unknown") for s in report["samples"]}),
        "independentRecordings": len(report["samples"]), "characters": total, "errors": errors,
        "cer": errors / total if total else None, "deletions": deletions,
        "termErrors": term_errors, "termOccurrences": term_total,
        "ordinaryChineseErrors": chinese_errors, "ordinaryChineseCharacters": chinese_total,
        "loadSeconds": report["loadSeconds"], "coldInferenceSeconds": report["coldInference"]["elapsedSeconds"],
        "warmP50Seconds": percentile(latency, .5), "warmP95Seconds": percentile(latency, .95),
        "warm10to30SecondsP95": percentile(long_latency, .95),
        "peakResidentMiB": report["peakResidentBytes"] / 1024**2,
        "failures": sum(r.get("error") is not None for r in report["results"]),
        "coldFailures": int(report["coldInference"].get("error") is not None),
        "promptSnapshot": report.get("promptSnapshot"), "termStatus": term_status,
        "languageOverrides": sorted({str(r.get("languageOverride")) for r in report["results"]}),
    }
    return summary


def compare(reports):
    first = reports[0]
    for report in reports:
        if report["audioSHA256"] != first["audioSHA256"] or report["samples"] != first["samples"]:
            raise ValueError("Cannot compare different audio, references, labels or splits")
        if report["implementationSHA256"] != first["implementationSHA256"]:
            raise ValueError("Cannot compare different Swift implementations")
    summaries = [summarize(report) for report in reports]
    categories = {sample["id"]: sample["category"] for sample in first["samples"]}
    for summary in summaries:
        baseline = next((s for s in summaries if s["model"] == summary["model"] and not s["promptSnapshot"]
                         and s["languageOverrides"] == summary["languageOverrides"]), None)
        if baseline is not None and summary["promptSnapshot"]:
            new = [key for key, correct in baseline["termStatus"].items() if correct and not summary["termStatus"].get(key)]
            summary["newTermErrorsVersusSameModel"] = len(new)
            summary["newAmbiguityTermErrors"] = sum(categories[key.rsplit(":", 2)[0]] == "ambiguity" for key in new)
    return {
        "accuracyStatus": "Unverified: technical reports do not establish human accuracy improvement.",
        "method": "NFKC, lowercase, omit whitespace/punctuation; accuracy uses first warm run only. Latency uses all warm runs, nearest-rank p50/p95. Cold load/inference separate. Failures count as missing reference text. Terms use reference-aligned occurrences. No statistical significance claim.",
        "conditions": summaries,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="+", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = compare([json.loads(path.read_text()) for path in args.reports])
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    for row in report["conditions"]:
        print(f"{row['condition']}: CER {row['errors']}/{row['characters']}; terms {row['termErrors']}/{row['termOccurrences']}; warm p50/p95 {row['warmP50Seconds']}/{row['warmP95Seconds']}s; peak {row['peakResidentMiB']:.1f} MiB; failures {row['failures']}")


if __name__ == "__main__":
    main()
