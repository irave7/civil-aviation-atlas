#!/usr/bin/env python3
"""Build bundled flight guide and fictional carrier announcements using local Sherpa-ONNX."""

import argparse
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

VOICES = {
    "captain": (90, 1.00, {
        "departing": "各位旅客，我们马上起飞。请确认安全带已经系好。",
        "cruise": "这里是驾驶舱。飞机已经进入巡航，祝各位旅途愉快。",
        "approach": "飞行即将进入降落阶段。我们现在开始下降。",
        "arrived": "我们已经停稳。谢谢各位一路相伴。",
        "rotate": "速度到了。轻轻抬起机头，保持平稳爬升。",
        "gearUp": "飞机离开地面了。现在可以收起起落架。",
        "gearDown": "跑道就在前方。请放下起落架，准备着陆。",
        "briefing": "各位旅客，欢迎登机。我们再确认一下天气和跑道，就可以出发了。",
        "taxiOut": "我们正滑向起飞跑道。请留在座位上，系好安全带。",
        "roll": "飞机已经开始加速。请留意空速和剩余跑道。",
        "touchdown": "机轮已经接地。保持方向，慢慢减速。",
        "taxiIn": "我们正在滑向停机位。请等飞机停稳再起身。",
    }),
    "guide": (26, 1.03, {
        "departing": "准备好了吗？我们就要从这条跑道起飞了。",
        "cruise": "我们飞稳了。看看地图，飞机已经飞到哪里了？",
        "approach": "快到了。你可以切到地图，看看飞机是怎么飞向跑道的。",
        "arrived": "我们到了！有空的话，再去看看这座机场吧。",
        "rotate": "速度够了。现在轻轻抬起机头。",
        "gearUp": "飞机离开地面了。收起起落架，我们接着往上飞。",
        "gearDown": "马上要降落了。别忘了放下起落架。",
        "briefing": "欢迎登机。先看看天气和起降跑道，准备好了我们就出发。",
        "taxiOut": "飞机动起来了。地图上这条细线就是我们要走的滑行道。",
        "roll": "我们正在跑道上加速。留意一下空速是怎么升起来的。",
        "touchdown": "飞机落地了。稳住方向，再慢慢把速度降下来。",
        "taxiIn": "离停机位不远了。等我们停稳，就能看这次的飞行记录。",
    }),
    "story": (49, 0.98, {
        "departing": "跑道就在前方。这趟旅程要开始了。",
        "cruise": "飞机在云层上方平稳前行。两座城市之间的距离正在一点点缩短。",
        "approach": "远处的机场越来越近。我们正从云层上方慢慢下降。",
        "arrived": "飞机停稳了。接下来的时间，留给这座刚到的机场。",
        "rotate": "让机头轻轻向上。跑道很快就要从视野里退下去了。",
        "gearUp": "地面渐渐远了。收起起落架，继续向上飞吧。",
        "gearDown": "已经可以看到跑道了。放下起落架，准备回到地面。",
        "briefing": "舱门快关上了。出发前，我们再看一眼天气和跑道。",
        "taxiOut": "机轮缓缓转动。顺着这条滑行道走，就是起飞跑道。",
        "roll": "引擎声高起来了。地面的标线开始向后掠过。",
        "touchdown": "机轮碰到地面了。飞机沿着跑道慢慢减速。",
        "taxiIn": "飞机已经离开跑道。再滑一小段，这趟飞行就结束了。",
    }),
}

CARRIERS = {
    # Kokoro v1.1-zh voices are generic synthetic speakers.
    # https://k2-fsa.github.io/sherpa/onnx/tts/all/Chinese-English/kokoro-multi-lang-v1_1.html
    "air-china": (38, 0.97, {
        "briefing": "欢迎搭乘中国国际航空模拟航班。请就座，我们即将启程。",
        "departing": "各位旅客，飞机即将进入跑道。请检查安全带是否系紧。",
        "approach": "飞机正在下降。请收起小桌板，并将椅背调直。",
        "arrived": "飞机已经停稳。感谢您体验中国国际航空模拟航班。",
    }),
    "china-eastern": (15, 0.99, {
        "briefing": "您好，欢迎体验中国东方航空模拟航班。我们正在做出发前的准备。",
        "departing": "我们即将起飞。请保持就座，将随身物品放好。",
        "approach": "目的地就在前方。降落前，请将安全带继续系好。",
        "arrived": "飞机已经停稳。感谢您搭乘中国东方航空模拟航班。",
    }),
    "china-southern": (67, 0.96, {
        "briefing": "欢迎搭乘中国南方航空模拟航班。一切就绪后，我们将开始滑行。",
        "departing": "前方就是起飞跑道。请坐稳，并确认安全带已经系好。",
        "approach": "我们正在接近目的地。请收好手边的物品，准备降落。",
        "arrived": "旅程到这里就结束了。感谢您体验中国南方航空模拟航班。",
    }),
    "xiamen-air": (5, 0.99, {
        "briefing": "欢迎体验厦门航空模拟航班。请找好座位，准备一起出发。",
        "departing": "各位旅客，我们准备起飞了。请继续保持安全带系好。",
        "approach": "飞机正在下降。请调整好座椅，等候降落。",
        "arrived": "我们已经到达模拟航程的终点。感谢您选择厦门航空。",
    }),
    "japan-airlines": (0, 0.95, {
        "briefing": "Welcome aboard this simulated Japan Airlines flight. Please settle in as we prepare to depart.",
        "departing": "We are nearing the runway. Please remain seated with your seat belt fastened.",
        "approach": "Our aircraft is descending. Please stow your tray table as we prepare to land.",
        "arrived": "We have reached our stand. Thank you for joining this Japan Airlines flight simulation.",
    }),
    "singapore-airlines": (1, 0.96, {
        "briefing": "Hello, and welcome to this Singapore Airlines flight simulation. We will be on our way shortly.",
        "departing": "We are preparing for takeoff. Please keep the aisle clear and fasten your seat belt.",
        "approach": "We will be landing shortly. Please put away your loose items and return to your seat.",
        "arrived": "The aircraft is parked. Thank you for flying with Singapore Airlines in this simulation.",
    }),
    "emirates": (2, 0.98, {
        "briefing": "Welcome aboard this Emirates flight simulation. We are making our final preparations to leave the stand.",
        "departing": "Takeoff is just ahead. Please check that your seat belt is secure.",
        "approach": "We have started our descent. Please return your seat to its upright position.",
        "arrived": "This simulated journey has come to an end. Thank you for travelling with Emirates.",
    }),
    "lufthansa": (1, 0.92, {
        "briefing": "Welcome aboard our simulated Lufthansa flight. Please take your seat as we get ready for departure.",
        "departing": "The aircraft is ready for takeoff. Please stay seated and keep your seat belt fastened.",
        "approach": "We are approaching our destination. Please close your tray table before we land.",
        "arrived": "We have arrived and parked. Thank you for taking part in this Lufthansa flight simulation.",
    }),
}

# The base US English lexicon omits these inflections and proper names.
ENGLISH_CARRIER_PRONUNCIATIONS = """airlines ˈ ɛ ɹ l ˌ I n z
arrived ə ɹ ˈ I v d
emirates ˈ ɛ m ə ɹ ə t s
fastened f ˈ æ s ᵊ n d
lufthansa l ˈ ʊ f t h ˌ ɑ n z ə
"""


def generate(sherpa: Path, model: Path, output: Path, cues_to_render: list[str], carriers: bool) -> None:
    rules = ",".join(str(model / f"{item}-zh.fst") for item in ("phone", "date", "number"))
    lexicons = [model / f"lexicon-{item}.txt" for item in ("zh", "us-en")]
    common = [
        str(sherpa),
        f"--kokoro-model={model / 'model.int8.onnx'}",
        f"--kokoro-voices={model / 'voices.bin'}",
        f"--kokoro-tokens={model / 'tokens.txt'}",
        f"--tts-rule-fsts={rules}",
        "--num-threads=2",
    ]

    def render(task):
        voice, speaker, speed, cue, line = task
        prefix = "carrier" if carriers else "narration"
        key = f"{prefix}-{voice}-{cue}"
        comment = ("原创模拟航司广播，人工智能合成语音；Kokoro-82M-v1.1-zh" if carriers
                   else "预制人工智能合成语音；Kokoro-82M-v1.1-zh")
        with tempfile.TemporaryDirectory(prefix=f"{key}-") as temporary:
            wav = Path(temporary) / f"{key}.wav"
            clip_lexicons = lexicons
            if carriers and speaker < 3:
                pronunciations = Path(temporary) / "carrier-lexicon.txt"
                pronunciations.write_text(ENGLISH_CARRIER_PRONUNCIATIONS, encoding="utf-8")
                clip_lexicons = [*lexicons, pronunciations]
            result = subprocess.run([
                *common,
                "--kokoro-lexicon=" + ",".join(map(str, clip_lexicons)),
                f"--sid={speaker}",
                f"--speed={speed}",
                f"--output-filename={wav}",
                line,
            ], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            if result.returncode or "OOV word skipped" in result.stderr:
                raise RuntimeError(f"Failed to synthesize all words in {key}:\n{result.stderr}")
            subprocess.run([
                "ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(wav),
                "-af", ("highpass=f=75,loudnorm=I=-19:LRA=7:TP=-2,"
                        "afade=t=in:st=0:d=0.025,areverse,afade=t=in:st=0:d=0.035,areverse,"
                        "adelay=45:all=1,apad=pad_dur=0.09"),
                "-ar", "24000", "-ac", "1", "-c:a", "aac", "-b:a", "48k",
                "-metadata", f"comment={comment}",
                str(output / f"{key}.m4a"),
            ], check=True)
        print(key, flush=True)

    tasks = [(voice, speaker, speed, cue, line)
             for voice, (speaker, speed, cues) in (CARRIERS if carriers else VOICES).items()
             for cue, line in cues.items() if not cues_to_render or cue in cues_to_render]
    output.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=3) as workers:
        list(workers.map(render, tasks))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sherpa", type=Path, help="Path to sherpa-onnx-offline-tts")
    parser.add_argument("model", type=Path, help="Unpacked kokoro-int8-multi-lang-v1_1 directory")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--carriers", action="store_true",
                        help="Render fictional cabin announcements to App/Resources/CarrierCabin.")
    parser.add_argument("--cue", action="append", default=[],
                        choices=tuple(VOICES["captain"][2]), help="Limit rendering to this cue; repeat as needed.")
    args = parser.parse_args()
    if args.carriers and not set(args.cue).issubset(CARRIERS["air-china"][2]):
        parser.error("Carrier announcements cover briefing, departing, approach and arrived.")
    folder = "CarrierCabin" if args.carriers else "Narration"
    output = args.output or (Path(__file__).resolve().parents[1] / "App/Resources" / folder)
    generate(args.sherpa.resolve(), args.model.resolve(), output.resolve(), args.cue, args.carriers)
