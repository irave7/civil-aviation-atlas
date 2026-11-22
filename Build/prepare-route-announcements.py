#!/usr/bin/env python3
"""Build original Mandarin airport announcements using local Sherpa-ONNX."""

import argparse
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

AIRPORTS = {
    "SHA": "上海虹桥国际机场",
    "PEK": "北京首都国际机场",
    "FOC": "福州长乐国际机场",
    "PVG": "上海浦东国际机场",
    "CAN": "广州白云国际机场",
    "TFU": "成都天府国际机场",
    "SIN": "新加坡樟宜机场",
    "HND": "东京羽田机场",
    "JFK": "纽约肯尼迪国际机场",
    "SFO": "旧金山国际机场",
    "PKX": "北京大兴国际机场",
    "XMN": "厦门高崎国际机场",
    "SZX": "深圳宝安国际机场",
    "HKG": "香港国际机场",
    "NRT": "东京成田国际机场",
    "ICN": "首尔仁川国际机场",
    "LAX": "洛杉矶国际机场",
    "LHR": "伦敦希思罗机场",
    "DXB": "迪拜国际机场",
}

AIRPORT_LINES = {
    "departure": (
        "飞机目前停靠在{airport}。各项准备就绪后，我们就会开始滑行。",
        "您好，我们将从{airport}出发。接下来可以看看窗外，飞机会沿滑行道前往跑道。",
    ),
    "arrival": (
        "飞机已在{airport}停稳。请带好您的随身物品，祝您接下来的旅程愉快。",
        "欢迎来到{airport}。下机前请看一看座椅周围，有没有遗漏的随身物品。",
    ),
}

REGIONAL_LINES = {
    "CN": {
        "departure": (
            "各位旅客，我们即将从中国大陆的始发机场出发。准备完成后，飞机会滑向起飞跑道。",
            "您好，我们正在准备出发。打开地图，就可以跟着飞机走完起飞前的这段滑行。",
        ),
        "arrival": (
            "飞机已在中国大陆的目的地机场停稳。您可以在地图上查看本次到达的机场。",
            "您好，飞机已滑达停靠区。准备下机时，请记得拿好您的物品。",
        ),
    },
    "ASIA": {
        "departure": (
            "各位旅客，我们即将从亚洲的始发机场启程。机组正在完成最后的准备。",
            "欢迎登机。出发前，可以先在地图上看看我们正在停靠的亚洲机场。",
        ),
        "arrival": (
            "我们已抵达亚洲的目的地机场。飞机已经停稳，请带好随身物品。",
            "我们到了，欢迎来到这座亚洲机场。祝您接下来的行程一切顺利。",
        ),
    },
    "WORLD": {
        "departure": (
            "各位旅客，我们已经做好出发准备。稍后，飞机将沿滑行道驶向起飞跑道。",
            "您好，起点机场就在窗外。起飞后，可以在地图上查看飞机的位置和前进方向。",
        ),
        "arrival": (
            "飞机已在目的地机场停稳。请确认随身物品已经带齐，感谢您的同行。",
            "您好，我们到达啦。您可以继续在地图上看看这座机场，祝您旅途愉快。",
        ),
    },
}

# Generic synthetic Kokoro v1.1-zh speakers, with a calm and a brighter delivery.
SPEAKERS = ((58, 0.98), (3, 1.02))


def generate(sherpa: Path, model: Path, output: Path, keys: list[str]) -> None:
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
    scripts = {
        key: {phase: tuple(line.format(airport=airport) for line in lines)
              for phase, lines in AIRPORT_LINES.items()}
        for key, airport in AIRPORTS.items()
    }
    scripts.update(REGIONAL_LINES)

    def render(task: tuple[str, str, int, str]) -> None:
        key, phase, variant, line = task
        speaker, speed = SPEAKERS[variant]
        name = f"route-{key}-{phase}-{variant}"
        with tempfile.TemporaryDirectory(prefix="atlas-route-voice-") as temporary:
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
                "-metadata", "comment=原创模拟机场广播，人工智能合成语音；Kokoro-82M-v1.1-zh",
                str(output / f"{name}.m4a"),
            ], check=True)
        print(name, flush=True)

    tasks = [(key, phase, variant, line)
             for key in (keys or scripts)
             for phase, lines in scripts[key].items()
             for variant, line in enumerate(lines)]
    output.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=4) as workers:
        list(workers.map(render, tasks))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sherpa", type=Path, help="Path to sherpa-onnx-offline-tts")
    parser.add_argument("model", type=Path, help="Unpacked kokoro-int8-multi-lang-v1_1 directory")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "App/Resources/RouteVoices")
    parser.add_argument("--key", action="append", default=[], choices=tuple(AIRPORTS | REGIONAL_LINES),
                        help="Render one airport or region key. Repeat the option to render multiple keys.")
    args = parser.parse_args()
    generate(args.sherpa.resolve(), args.model.resolve(), args.output.resolve(), args.key)
