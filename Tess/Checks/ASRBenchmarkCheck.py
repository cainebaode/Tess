"""Metric regression checks: repeated terms, failed recognition and split comparability."""
import importlib.util
from pathlib import Path

module_path = Path(__file__).resolve().parents[2] / "scripts/compare-asr.py"
spec = importlib.util.spec_from_file_location("compare", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert module.alignment("甲乙丙", "甲丙")[:2] == (1, 1)
assert module.alignment("prd", "pld")[0] == 1
assert module.percentile([.2, .5, .7], .95) == .7
sample = dict(id="one", reference="PRD 然后 PRD", category="mixed", source="synthetic", split="smoke", terms=["PRD"])
run = dict(id="one", iteration=1, transcript="PRD 然后 PLD", elapsedSeconds=.1, durationSeconds=12)
report = dict(condition="A", model="qwenSmall", samples=[sample], results=[run, dict(run, iteration=2), dict(run, iteration=3)],
              loadSeconds=1, coldInference=run, peakResidentBytes=1024**2, audioSHA256={"a": "hash"}, implementationSHA256="hash")
summary = module.summarize(report)
assert (summary["termErrors"], summary["termOccurrences"]) == (1, 2)
assert summary["independentRecordings"] == 1
failed = module.summarize(dict(report, results=[dict(run, transcript=None, error="timeout")]))
assert failed["failures"] == 1 and failed["deletions"] == len(module.normalized(sample["reference"]))
assert failed["warmP95Seconds"] is None
try:
    module.compare([report, dict(report, audioSHA256={"a": "different"})])
    raise AssertionError("Mismatched audio accepted")
except ValueError:
    pass
print("ASR metric checks passed: character/deletion alignment, repeated term occurrences, latency repetitions, failures and same-corpus guard.")
