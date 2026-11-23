#!/usr/bin/env python3
"""Render the Mandarin catalogue with Kokoro v1.1-zh and Misaki's contextual frontend.

Build-time Python dependencies: misaki 0.9.4 (zh_frontend), jieba, pypinyin,
pypinyin-dict, addict, numpy, onnxruntime and soundfile. Requires ffmpeg.
Pass the unpacked sherpa-onnx kokoro-int8-multi-lang-v1_1 directory.
"""
import argparse
import json
import re
import shutil
import subprocess
import tempfile
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import jieba
import numpy as np
import onnxruntime as ort
import soundfile as sf
from misaki.zh_frontend import ZHFrontend
from pypinyin import load_phrases_dict

RESOURCES = Path(__file__).resolve().parents[1] / "App/Resources"
# Context-sensitive words are kept together during segmentation, then tone sandhi is applied.
READINGS = {
    "重庆": "chong2 qing4", "厦门": "xia4 men2", "长乐": "chang2 le4",
    "长江口": "chang2 jiang1 kou3", "成都": "cheng2 du1", "首都": "shou3 du1",
    "大兴": "da4 xing1", "着陆": "zhuo2 lu4", "滑行道": "hua2 xing2 dao4",
    "滑行": "hua2 xing2", "执飞": "zhi2 fei1", "航行": "hang2 xing2",
    "机长": "ji1 zhang3", "翼展": "yi4 zhan3", "系好": "ji4 hao3",
    "系紧": "ji4 jin3", "高崎": "gao1 qi2", "浦东": "pu3 dong1",
    "降落": "jiang4 luo4", "秘鲁": "bi4 lu3", "阿联酋": "a1 lian2 qiu2",
}
PUNCT = str.maketrans({"，": ",", "。": ".", "！": "!", "？": "?", "、": ",", "；": ";"})
FOLDERS = {"narration": "Narration", "route": "RouteVoices", "challenge": "ChallengeVoices",
           "carrier": "CarrierCabin", "observation": "ObservationVoices"}


def load_engine(model):
    global frontend, session, voices, vocab
    frontend = ZHFrontend()
    for phrase in READINGS:
        jieba.add_word(phrase, freq=1_000_000, tag="n")
    load_phrases_dict({k: [[p] for p in v.split()] for k, v in READINGS.items()})
    vocab = dict((k, int(v)) for k, v in
                 (line.rsplit(" ", 1) for line in (model / "tokens.txt").read_text().splitlines()))
    voices = np.memmap(model / "voices.bin", np.float32, "r").reshape(-1, 510, 256)
    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(model / "model.int8.onnx"), options, providers=["CPUExecutionProvider"])


def voice_for(key):
    # Pauses and wording carry the roles. Each voice keeps its own consistent timbre.
    if key.startswith("observation-captain-"): return 90, 0.97
    if key.startswith("observation-story-"): return 49, 0.94
    if key.startswith("narration-"):
        return {"captain": (90, 0.97), "guide": (3, 1.02), "story": (49, 0.94)}[key.split("-")[1]]
    if key.startswith("carrier-"):
        return next((v, 0.98) for k, v in
                    {"air-china": 38, "china-eastern": 15, "china-southern": 67, "xiamen-air": 5}.items()
                    if key.startswith("carrier-" + k + "-"))
    if key.startswith("route-"):
        return (58, 0.97) if key.endswith("-0") else (3, 1.00)
    return (3, 0.98) if key.startswith("observation-") else (58, 1.00)


def render(job):
    key, text = job
    folder = RESOURCES / FOLDERS[key.split("-")[0]]
    speaker, tempo = voice_for(key)
    pieces = []
    for phrase in re.findall(r"[^。！？]+[。！？]?", text):
        phones, _ = frontend(phrase.translate(PUNCT))
        ids = [vocab[c] for c in phones]
        if not 0 < len(ids) < 510:
            raise ValueError(f"Invalid phoneme count for {key}")
        result = session.run(None, {"tokens": np.array([[0, *ids, 0]], np.int64),
                                    "style": voices[speaker, len(ids):len(ids)+1],
                                    "speed": np.array([tempo], np.float32)})[0].reshape(-1)
        active = np.flatnonzero(np.abs(result) > 0.003)
        if not active.size or not np.isfinite(result).all():
            raise ValueError(f"Silent or invalid speech: {key}")
        audio = result[max(0, active[0]-960):active[-1]+1920]
        pieces.extend((audio, np.zeros(4800 if phrase.endswith("？") else 3600, np.float32)))
    with tempfile.TemporaryDirectory() as temporary:
        wav = Path(temporary) / "voice.wav"
        out = Path(temporary) / "voice.m4a"
        sf.write(wav, np.concatenate(pieces), 24000)
        subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-i", str(wav), "-af",
                        "highpass=f=65,loudnorm=I=-19:TP=-2:LRA=9", "-ar", "24000",
                        "-c:a", "aac", "-b:a", "72k", "-metadata", "comment=原创普通话 AI 合成配音 · Kokoro v1.1-zh",
                        str(out)], check=True)
        # Keep intermediates outside Xcode's synchronized resource directories.
        with tempfile.NamedTemporaryFile(prefix=".render-", dir=folder, delete=False) as target:
            pending = Path(target.name)
        try:
            shutil.copyfile(out, pending)
            pending.replace(folder / (key + ".m4a"))
        finally:
            pending.unlink(missing_ok=True)
    return key


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=Path)
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--prefix", default="")
    args = parser.parse_args()
    missions = json.loads((RESOURCES / "ObservationVoices/observation-scripts.json").read_text())
    catalogue = {"observation-" + k: v for k, v in missions.items()}
    for role in ("captain", "story"):
        catalogue.update({f"observation-{role}-{k}": v for k, v in missions.items()})
    catalogue.update(json.loads((RESOURCES / "Narration/flight-transcripts.json").read_text()))
    jobs = [(k, v) for k, v in catalogue.items() if k.startswith(args.prefix) and re.search("[一-龥]", v)]
    if not jobs:
        parser.error("No matching Mandarin scripts")
    with ProcessPoolExecutor(args.workers, initializer=load_engine, initargs=(args.model,)) as pool:
        for key in pool.map(render, jobs):
            print(key, flush=True)
