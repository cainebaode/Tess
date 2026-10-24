#!/usr/bin/env python3
"""Generate an isolated macOS TTS corpus, or score an offline ASR benchmark report."""
import argparse
import json
import math
import re
import subprocess
import unicodedata
import wave
from pathlib import Path


CORPUS = [
    ("zh_daily", "Chinese", "请把今天讨论的方案整理成三点，先说明目标，再列出需要确认的问题，最后写清楚下一步安排。", "Tingting", "zh"),
    ("en_daily", "English", "Please send the revised proposal tomorrow morning. Keep the original deadline and explain which questions still need an answer. Also keep the version number in the subject line so everyone can find the correct document.", "Samantha", "en"),
    ("mixed_terms", "Mixed", "请检查 SwiftUI 的状态更新，API 请求失败时保留原文，不要把 JSON 里面的 model 字段删除。", "Tingting", None),
    ("numbers", "Numbers", "会议改到十月二十一日下午三点半，预算是一千两百五十元，不是一万两千五百元。参会人数是十二人，请核对这三个数字以后再发通知。", "Tingting", "zh"),
    ("negation", "Negation", "不要删除原来的文件，也不要自动发送。只有我明确确认以后，才可以保存新的版本。如果没有收到确认，就继续等待我的回复。", "Tingting", "zh"),
    ("correction", "Correction", "明天下午两点，不对，改成后天下午三点。请保留两个版本，刚才说错了，只保留最终版本。", "Tingting", "zh"),
    ("long_zh", "Long", "今天我们讨论的是一个日常输入工具。首先，用户按下快捷键以后，需要马上知道是否已经开始录音。如果模型还在准备，就应该说明正在等待什么，不能显示已经开始听写。其次，录音结束以后，要把语音识别和文字整理分开处理。识别在本机完成，文字整理只有在用户配置了服务以后才会运行。遇到网络错误时，原始文字必须保留。第三，如果用户切换到其他应用，系统需要重新确认输入位置，不能把文字放到错误的窗口里。最后，我们要检查取消和快速再次唤起的情况。前一次已经取消的请求，即使稍后返回，也不能覆盖新结果。完成这些检查以后，再邀请用户用自己的真实表达测试中文、英文以及混合输入，并记录需要修改的地方。", "Tingting", "zh"),
]


def generate(folder):
    folder.mkdir(parents=True, exist_ok=True)
    samples = []
    for key, category, reference, voice, language in CORPUS:
        audio = folder / f"{key}.wav"
        subprocess.run(["say", "-v", voice, "-r", "180", "-o", str(audio),
                        "--data-format=LEI16@16000", "--channels=1", reference], check=True)
        samples.append(dict(id=key, category=category, reference=reference,
                            audioFile=audio.name, language=language))
    with wave.open(str(folder / "silence.wav"), "wb") as audio:
        audio.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
        audio.writeframes(b"\0\0" * 16000 * 3)
    samples.append(dict(id="silence", category="Silence", reference="", audioFile="silence.wav", language=None))
    (folder / "corpus.json").write_text(json.dumps(samples, ensure_ascii=False, indent=2))
    (folder / "provenance.json").write_text(json.dumps(dict(
        source="Synthetic macOS say TTS, local system voices; silence is zero PCM.",
        chineseVoice="Tingting", englishVoice="Samantha", wordsPerMinute=180,
        format="16 kHz mono signed 16-bit PCM", humanAcceptance=False), ensure_ascii=False, indent=2))
    print(folder / "corpus.json")


def distance(a, b):
    row = list(range(len(b) + 1))
    for i, item in enumerate(a, 1):
        new = [i]
        for j, other in enumerate(b, 1):
            new.append(min(new[-1] + 1, row[j] + 1, row[j - 1] + (item != other)))
        row = new
    return row[-1]


def normalized(text):
    return unicodedata.normalize("NFKC", text).lower()


def cer_tokens(text):
    return [c for c in normalized(text) if c.isalnum()]


def word_tokens(text):
    return re.findall(r"[a-z]+(?:'[a-z]+)?|\d+(?:\.\d+)?", normalized(text))


def han_tokens(text):
    return re.findall(r"[\u3400-\u9fff]", normalized(text))


def percent(errors, count):
    return f"{errors / count:.1%}" if count else "—"


def quantile(values, p):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * p) - 1)] if ordered else 0


def report(path):
    data = json.loads(path.read_text())
    samples = {sample["id"]: sample for sample in data["samples"]}
    rows = []
    scored = []
    for result in data["results"]:
        sample = samples[result["id"]]
        expected = sample["reference"]
        actual = result.get("transcript") or ""
        tokens = word_tokens if sample["category"] == "English" else cer_tokens
        ref, hyp = tokens(expected), tokens(actual)
        errors = distance(ref, hyp)
        metric = "WER" if sample["category"] == "English" else "CER"
        score = dict(result, metric=metric, editDistance=errors, referenceTokens=len(ref))
        if sample["category"] == "Mixed":
            han_ref, han_hyp = han_tokens(expected), han_tokens(actual)
            en_ref, en_hyp = word_tokens(expected), word_tokens(actual)
            score.update(hanCER=distance(han_ref, han_hyp) / len(han_ref) if han_ref else None,
                         englishWER=distance(en_ref, en_hyp) / len(en_ref) if en_ref else None)
            displayed_score = f"Han CER {score['hanCER']:.1%}; English WER {score['englishWER']:.1%}"
        else:
            displayed_score = f"{metric} {percent(errors, len(ref))}"
        scored.append(score)
        status = "silence rejected" if not expected and result.get("error") and not actual else (result.get("error") or "completed")
        rows.append(f"| {result['id']} | {result['iteration']} | {result['durationSeconds']:.2f} | {result['elapsedSeconds']:.3f} | {displayed_score} | {status} |")
    timed = [r["elapsedSeconds"] for r in data["results"] if r.get("transcript") is not None]
    short = [r["elapsedSeconds"] for r in data["results"] if r.get("transcript") is not None and 10 <= r["durationSeconds"] <= 30]
    cold = data["coldInference"]
    lines = ["# Tess synthetic ASR baseline", "", data["evidence"], "",
             f"- Model: {data['model']} · {data['repository']}",
             f"- Hardware: {data['hardware']} · RAM {data['physicalMemoryBytes'] / 2**30:.0f} GiB · {data['operatingSystem']}",
             f"- Process-cold model load: {data['loadSeconds']:.3f}s; first inference: {cold['elapsedSeconds']:.3f}s. OS file caches were not cleared.",
             f"- Warm inference P50/P95 (all speech, n={len(timed)}): {quantile(timed, .5):.3f}s / {quantile(timed, .95):.3f}s.",
             f"- Warm 10–30s speech P50/P95 (n={len(short)}): {quantile(short, .5):.3f}s / {quantile(short, .95):.3f}s.",
             f"- Process peak resident memory (getrusage high-water mark): {data['peakResidentBytes'] / 2**30:.3f} GiB.",
             "- CER ignores punctuation/spacing/case; number orthography remains exact. English WER is word based. Mixed segment metrics are in scored.json.",
             "- No cloud comparison, microphone, noise/accent sample, manual correction time, or text-shaping quality was measured. No best-model conclusion.", "",
             "| Sample | Repeat | Audio s | ASR s | Error rate | Outcome |", "|---|---:|---:|---:|---|---|"] + rows + ["", "## References and actual transcripts", ""]
    for sample in data["samples"]:
        matching = [r for r in data["results"] if r["id"] == sample["id"]]
        lines += [f"### {sample['id']}", "", "Reference: " + sample["reference"], ""]
        unique = {}
        for result in matching:
            text = result.get("transcript") or result.get("error")
            unique.setdefault(text, []).append(str(result["iteration"]))
        for text, repeats in unique.items():
            lines.append(f"Repeats {', '.join(repeats)}: {text}")
        lines.append("")
    summary = path.with_name("20261011-01-synthetic-asr-baseline.md")
    summary.write_text("\n".join(lines))
    path.with_name("scored.json").write_text(json.dumps(scored, ensure_ascii=False, indent=2))
    print(summary)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--generate", type=Path)
    group.add_argument("--report", type=Path)
    args = parser.parse_args()
    generate(args.generate) if args.generate else report(args.report)
