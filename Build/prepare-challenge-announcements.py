#!/usr/bin/env python3
"""Render original Mandarin introductions for flight challenges with local Sherpa-ONNX."""

import argparse
import json
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
SPEAKERS = ((3, 1.04), (17, 1.07), (58, 1.04))

# Optional published reference, speaker index and original line.
# Airline names replace their two-character designators in spoken Mandarin.
SCRIPTS = {
    "SHA-PEK": ("MU9191", 0, "东航九一九一曾用国产九一九客机。看飞机怎样从跑道上抬起机头！"),
    "SHA-CGO": ("MU5395", 1, "东航五三九五曾飞往郑州。离开地面后，看看起落架怎样收起来。"),
    "SHA-XMN": ("MU5247", 2, "东航五二四七曾飞往海边的厦门。练习侧风降落时，试着稳住机头。"),
    "PVG-CAN": (None, 0, "从长江口飞向广州。巡航遇上气流，试一试怎样稳住机翼。"),
    "PKX-TFU": (None, 1, "大兴和天府都有多条跑道。来找一找，这次模拟选了哪一条？"),
    "PEK-FOC": (None, 2, "我们从北京飞向福州。找到海边的跑道，把机头对准中线。"),
    "PEK-CKG": (None, 0, "下一站是山城重庆。试试比较飞机的高度和机场的海拔。"),
    "PEK-SYX": (None, 1, "我们一路向南飞往三亚。快到时，看看襟翼怎样帮助飞机慢下来。"),
    "PVG-SZX": (None, 2, "浦东和宝安都靠近海边。猜一猜，两座机场的跑道方向一样吗？"),
    "TFU-PVG": (None, 0, "从成都盆地飞到长江口。切到机外，看看这架飞机的涂装。"),
    "SHA-HKG": ("MU721", 1, "东航七二一曾用国产客机飞到香港。比一比两座机场的跑道吧！"),
    "PVG-SIN": ("SQ827", 2, "收录班表里的新航八二七飞往新加坡。地图上，看看赤道在哪里。"),
    "HND-JFK": ("JL006", 0, "日航零零六曾飞越太平洋。打开地球，找找国际日期变更线。"),
    "HKG-DFW": ("CX876", 1, "资料里的国泰八七六用过空客三五零。切到机外。看看两边的机翼，翼尖在哪里？"),
    "DXB-LHR": ("EK003", 2, "资料里的阿联酋航空零零三用双层客机。数一数，有几台发动机？"),
    "SIN-JFK": ("SQ24", 0, "收录班表里的新航二四飞往纽约。猜猜这条超远航线朝哪里弯？"),
    "SIN-PER": ("SQ225", 1, "班表里的新航二二五飞向珀斯。从新加坡出发，我们会跨过赤道。"),
    "HKG-SYD": (None, 2, "从香港飞往悉尼。落地时，听一听机轮接触跑道的声音。"),
    "FRA-IAD": ("LH416", 0, "汉莎四一六曾为波音七四七杠八客机首航。找找机头上层的窗户！"),
    "GRU-LIS": (None, 1, "从巴西飞往葡萄牙。转一转地球，看看大西洋有多宽。"),
    "AMS-CPT": (None, 2, "从阿姆斯特丹飞向开普敦。练习侧风降落，试着对准跑道中线。"),
    "SYD-YVR": (None, 0, "悉尼和温哥华在太平洋两边。找出赤道，看看飞机在哪儿跨过去。"),
}


def verify_references() -> None:
    files = PROJECT / "App/Resources"
    catalogue = json.loads((files / "airport-data.json").read_text())
    published = {(f"{route['origin']}-{route['destination']}", route.get("flightNumber"))
                 for route in catalogue["routes"]}
    for route, (number, _, _) in SCRIPTS.items():
        if number and (route, number) not in published:
            raise ValueError(f"{number} is absent from the published references for {route}")


def generate(sherpa: Path, model: Path, output: Path, routes: list[str]) -> None:
    rules = ",".join(str(model / f"{item}-zh.fst") for item in ("phone", "date", "number"))
    lexicon = ",".join(str(model / f"lexicon-{item}.txt") for item in ("zh", "us-en"))
    synthesis = [
        str(sherpa),
        f"--kokoro-model={model / 'model.int8.onnx'}",
        f"--kokoro-voices={model / 'voices.bin'}",
        f"--kokoro-tokens={model / 'tokens.txt'}",
        f"--kokoro-lexicon={lexicon}",
        f"--tts-rule-fsts={rules}",
        "--num-threads=1",
    ]

    def render(route: str) -> None:
        _, voice, line = SCRIPTS[route]
        speaker, speed = SPEAKERS[voice]
        name = f"challenge-{route}"
        with tempfile.TemporaryDirectory(prefix="atlas-challenge-voice-") as temporary:
            wav = Path(temporary) / "speech.wav"
            result = subprocess.run([
                *synthesis,
                f"--sid={speaker}",
                f"--speed={speed}",
                f"--output-filename={wav}",
                line,
            ], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            if result.returncode:
                raise RuntimeError(f"Could not render {name}: {result.stderr}")
            subprocess.run([
                "ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(wav),
                "-af", ("highpass=f=75,acompressor=threshold=0.16:ratio=2:attack=18:release=95,"
                        "loudnorm=I=-19:LRA=7:TP=-2,afade=t=in:st=0:d=0.025,"
                        "areverse,afade=t=in:st=0:d=0.035,areverse,adelay=45:all=1,apad=pad_dur=0.09"),
                "-ar", "24000", "-ac", "1", "-c:a", "aac", "-b:a", "48k",
                "-metadata", "comment=使用 Kokoro-82M-v1.1-zh 合成的原创模拟航线介绍",
                str(output / f"{name}.m4a"),
            ], check=True)
        print(name, flush=True)

    output.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=4) as workers:
        list(workers.map(render, routes or SCRIPTS))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sherpa", type=Path, help="Path to sherpa-onnx-offline-tts")
    parser.add_argument("model", type=Path, help="Unpacked kokoro-int8-multi-lang-v1_1 directory")
    parser.add_argument("--output", type=Path, default=PROJECT / "App/Resources/ChallengeVoices")
    parser.add_argument("--route", action="append", default=[], choices=tuple(SCRIPTS),
                        help="Render one route. Repeat the option to render multiple routes.")
    args = parser.parse_args()
    verify_references()
    generate(args.sherpa.resolve(), args.model.resolve(), args.output.resolve(), args.route)
