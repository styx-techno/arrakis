#!/usr/bin/env python3
"""Erzeugt sound/sand-drone.ogg: tiefes Brummen für die Unruhe (arrakis-rumble, 0.16.1).

Max im Spiel (01.11.2026, T20 Schritt 2): Das alte Rumpeln (demolisher-tail-rumble) klang wie hochfrequentes
Knistern; zu einer großen Maschine passt ein tieferes Brummen / Droning. Der Ton ist synthetisch: Grundton 41 Hz mit
Obertönen bis gut 200 Hz, eine leicht verstimmte zweite Stimme (langsame Schwebung), ein Motor-Pulsieren mit 2,2 Hz und
tiefpassgefiltertes Rauschen als Sandgrollen. 5,5 s lang mit weichem Ein- und Ausblenden, damit sich die Töne im
5-s-Takt (vibration.RUMBLE_TICKS) zu einem durchgehenden Brummen überlappen.

Aufruf: python3 tools/ton/brummen.py [Ziel.ogg]   (braucht numpy und ffmpeg mit libvorbis)
"""
import pathlib
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
DUR = 5.5
F0 = 41.0


def lowpass(signal, cutoff):
    spec = np.fft.rfft(signal)
    freqs = np.fft.rfftfreq(len(signal), 1 / SR)
    spec *= 1 / (1 + (freqs / cutoff) ** 4)
    return np.fft.irfft(spec, len(signal))


def main():
    target = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[2] / "sound" / "sand-drone.ogg"
    rng = np.random.default_rng(1909)
    t = np.arange(int(SR * DUR)) / SR
    tone = np.zeros_like(t)
    for n, amp in ((1, 1.0), (2, 0.8), (3, 0.55), (4, 0.35), (5, 0.2)):
        tone += amp * np.sin(2 * np.pi * F0 * n * t + n * 0.7)
        tone += 0.5 * amp * np.sin(2 * np.pi * F0 * 1.007 * n * t + n * 1.9)
    throb = 1 - 0.25 * (0.5 + 0.5 * np.sin(2 * np.pi * 2.2 * t))
    tone *= throb
    noise = np.cumsum(rng.standard_normal(len(t)))
    noise -= np.convolve(noise, np.ones(4410) / 4410, mode="same")
    noise = lowpass(noise, 120)
    noise /= np.max(np.abs(noise))
    mix = tone / np.max(np.abs(tone)) + 0.45 * noise
    mix = lowpass(mix, 300)
    fade_in, fade_out = int(0.8 * SR), int(1.2 * SR)
    env = np.ones_like(t)
    env[:fade_in] = np.sin(np.linspace(0, np.pi / 2, fade_in)) ** 2
    env[-fade_out:] = np.cos(np.linspace(0, np.pi / 2, fade_out)) ** 2
    mix *= env
    mix *= 0.9 / np.max(np.abs(mix))
    pcm = (mix * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        wav = pathlib.Path(tmp) / "drone.wav"
        with wave.open(str(wav), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        target.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "4", str(target)], check=True)
    print(target, target.stat().st_size, "Bytes")


if __name__ == "__main__":
    main()
