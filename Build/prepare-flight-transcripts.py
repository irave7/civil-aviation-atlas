#!/usr/bin/env python3
"""Export matching captions for the bundled flight recordings from their generation scripts."""
import argparse
import json
import runpy
from pathlib import Path

BUILD = Path(__file__).resolve().parent
OUTPUT = BUILD.parent / "App/Resources/Narration/flight-transcripts.json"


def transcripts():
    narration = runpy.run_path(str(BUILD / "prepare-narration.py"))
    route = runpy.run_path(str(BUILD / "prepare-route-announcements.py"))
    challenge = runpy.run_path(str(BUILD / "prepare-challenge-announcements.py"))
    captions = {}
    for prefix, voices in (("narration", narration["VOICES"]), ("carrier", narration["CARRIERS"])):
        for voice, (_, _, scripts) in voices.items():
            for stage, line in scripts.items():
                captions[f"{prefix}-{voice}-{stage}"] = line
    for code, name in route["AIRPORTS"].items():
        for phase, variants in route["AIRPORT_LINES"].items():
            for index, line in enumerate(variants):
                captions[f"route-{code}-{phase}-{index}"] = line.format(airport=name)
    for region, phases in route["REGIONAL_LINES"].items():
        for phase, variants in phases.items():
            for index, line in enumerate(variants):
                captions[f"route-{region}-{phase}-{index}"] = line
    for pair, (_, _, line) in challenge["SCRIPTS"].items():
        captions[f"challenge-{pair}"] = line
    return json.dumps(captions, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    if parser.parse_args().check:
        if OUTPUT.read_text(encoding="utf-8") != transcripts():
            raise SystemExit("Rebuild flight-transcripts.json to match the recorded scripts.")
    else:
        OUTPUT.write_text(transcripts(), encoding="utf-8")
