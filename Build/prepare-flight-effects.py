#!/usr/bin/env python3
"""Render original synthesized sounds for the flight simulator."""

from array import array
from math import exp, pi, sin
from pathlib import Path
import random
import subprocess
import tempfile
import wave

RATE = 24000
TAU = 2 * pi
DESTINATION = Path(__file__).resolve().parents[1] / "App/Resources/FlightEffects"


def loop_texture(kind):
    rng = random.Random(1734 + len(kind))
    duration = 4
    count = duration * RATE
    irregular = [rng.uniform(-1, 1) for _ in range(count)]
    low = [sum(irregular[(index + shift) % count] for shift in range(-5, 6)) / 11
           for index in range(count)]
    for index, noise in enumerate(irregular):
        t = index / RATE
        deep = (sin(TAU * 37 * t) + 0.48 * sin(TAU * 63 * t) + 0.34 * sin(TAU * 86 * t)) * 0.23
        filtered = low[index]
        if kind == "engine":
            fan = 0.07 * sin(TAU * 173 * t + 0.55 * sin(TAU * 8 * t)) + 0.045 * sin(TAU * 284 * t)
            yield deep + fan + filtered * 0.47 + noise * 0.035
        elif kind == "airflow":
            yield (0.62 * filtered + 0.13 * noise) * (0.85 + 0.15 * sin(TAU * 0.75 * t))
        elif kind == "roll":
            yield (0.20 * sin(TAU * 25 * t) + 0.68 * filtered + 0.045 * noise) * (0.82 + 0.18 * sin(TAU * 4.5 * t))
        else:
            yield deep * 0.35 + filtered * 0.38 + noise * 0.024


def one_shot(kind, duration):
    rng = random.Random(2311 + len(kind))
    smooth = 0.0
    for index in range(round(duration * RATE)):
        t = index / RATE
        random_sample = rng.uniform(-1, 1)
        smooth += 0.22 * (random_sample - smooth)
        if kind == "chime":
            bell = lambda offset, frequency: (0.31 * sin(TAU * frequency * max(0, t - offset))
                                              * exp(-6.6 * (t - offset)) * min(1, (t - offset) / 0.014)
                                              if t >= offset else 0)
            sample = bell(0, 659) + bell(0.31, 523)
        elif kind == "switch":
            sample = (smooth * 0.55 + random_sample * 0.24) * exp(-60 * t)
        elif kind == "touchdown":
            thump = 0.43 * sin(TAU * 53 * t) * exp(-6.1 * t)
            tire = (smooth * 0.5 + random_sample * 0.2) * exp(-4.2 * t)
            sample = thump + tire
        elif kind == "gear":
            motor = 0.14 * sin(TAU * (105 * t + 3 * t * t)) + 0.22 * smooth
            sample = motor * sin(pi * t / duration) + 0.19 * smooth * exp(-160 * abs(t - duration * .86))
        elif kind == "reverse":
            sample = (smooth * 0.62 + sin(TAU * 48 * t) * 0.20) * sin(pi * t / duration)
        else:
            sample = (0.16 * sin(TAU * (81 * t + 9 * t * t)) + 0.17 * smooth) * sin(pi * t / duration)
        fade = min(1, t / 0.006, (duration - t) / 0.026)
        yield sample * fade


def write_asset(directory, name, samples):
    wav = directory / (name + ".wav")
    pcm = array("h", (round(32767 * max(-1, min(1, sample))) for sample in samples))
    with wave.open(str(wav), "wb") as audio:
        audio.setparams((1, 2, RATE, len(pcm), "NONE", "not compressed"))
        audio.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(wav),
                    "-c:a", "aac", "-b:a", "56k", "-metadata", "comment=Original synthesized flight simulation effect",
                    str(DESTINATION / ("flight-" + name + ".m4a"))], check=True)


if __name__ == "__main__":
    DESTINATION.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="atlas-flight-effects-") as scratch:
        directory = Path(scratch)
        for loop in ("cabin", "engine", "airflow", "roll"):
            write_asset(directory, loop, loop_texture(loop))
        for cue, seconds in (("chime", 1.24), ("switch", 0.16), ("touchdown", 1.05),
                             ("gear", 1.7), ("reverse", 2.1), ("flaps", 0.9)):
            write_asset(directory, cue, one_shot(cue, seconds))
