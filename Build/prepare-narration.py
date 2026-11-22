#!/usr/bin/env python3
"""Build the bundled Mandarin narration for the flight guide using local Sherpa-ONNX."""

import argparse
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

VOICES = {
    "captain": (58, 0.96, {
        "departing": "各位旅客，我们即将起飞。请系好安全带。",
        "cruise": "这里是机长广播。我们已进入巡航，感谢各位陪伴这段航程。",
        "approach": "各位旅客，飞机开始下降，准备降落。",
        "arrived": "我们已顺利抵达。感谢您与我们同行。",
        "rotate": "请轻抬机头，确认后继续爬升。",
        "gearUp": "飞机已经离地。请收起起落架。",
        "gearDown": "已进入最后进近，请放下起落架。",
    }),
    "guide": (3, 1.04, {
        "departing": "我们准备出发啦。一起来体验起飞。",
        "cruise": "现在进入巡航。屏幕上显示的是两座机场之间的大圆距离。",
        "approach": "目的地就在前面。看看飞机怎样进近和降落。",
        "arrived": "我们到了。点开下方按钮，就能认识这座机场。",
        "rotate": "轻轻调高机头，准备离开跑道。",
        "gearUp": "已经起飞啦！收起起落架，继续巡航。",
        "gearDown": "准备着陆啦！先放下起落架。",
    }),
    "story": (17, 0.93, {
        "departing": "沿着跑道向前，这段旅程开始了。",
        "cruise": "此刻，飞机飞在云层之上。两座机场，被这一段航程连了起来。",
        "approach": "远处的机场渐渐靠近。我们开始下降。",
        "arrived": "轮胎触地，抵达的这一刻到了。下一站，去看看这座机场吧。",
        "rotate": "让机头缓缓向上。离地的时刻，就在眼前。",
        "gearUp": "飞机离开了地面。收起起落架，我们继续前行。",
        "gearDown": "跑道就在前方。放下起落架，准备和地面相遇。",
    }),
}


def generate(sherpa: Path, model: Path, output: Path) -> None:
    rules = ",".join(str(model / f"{item}-zh.fst") for item in ("phone", "date", "number"))
    lexicon = ",".join(str(model / f"lexicon-{item}.txt") for item in ("zh", "us-en"))
    common = [
        str(sherpa),
        f"--kokoro-model={model / 'model.int8.onnx'}",
        f"--kokoro-voices={model / 'voices.bin'}",
        f"--kokoro-tokens={model / 'tokens.txt'}",
        f"--kokoro-lexicon={lexicon}",
        f"--tts-rule-fsts={rules}",
        "--num-threads=2",
    ]

    def render(task):
        voice, speaker, speed, cue, line = task
        key = f"narration-{voice}-{cue}"
        with tempfile.TemporaryDirectory(prefix=f"{key}-") as temporary:
            wav = Path(temporary) / f"{key}.wav"
            subprocess.run([
                *common,
                f"--sid={speaker}",
                f"--speed={speed}",
                f"--output-filename={wav}",
                line,
            ], check=True, stdout=subprocess.DEVNULL)
            subprocess.run([
                "ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(wav),
                "-af", "loudnorm=I=-19:LRA=7:TP=-2",
                "-ar", "24000", "-ac", "1", "-c:a", "aac", "-b:a", "48k",
                "-metadata", "comment=预制人工智能合成语音；Kokoro-82M-v1.1-zh",
                str(output / f"{key}.m4a"),
            ], check=True)
        print(key, flush=True)

    tasks = [(voice, speaker, speed, cue, line)
             for voice, (speaker, speed, cues) in VOICES.items()
             for cue, line in cues.items()]
    output.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=3) as workers:
        list(workers.map(render, tasks))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sherpa", type=Path, help="Path to sherpa-onnx-offline-tts")
    parser.add_argument("model", type=Path, help="Unpacked kokoro-int8-multi-lang-v1_1 directory")
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).resolve().parents[1] / "App/Resources/Narration")
    args = parser.parse_args()
    generate(args.sherpa.resolve(), args.model.resolve(), args.output.resolve())
