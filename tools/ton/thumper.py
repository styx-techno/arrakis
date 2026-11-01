#!/usr/bin/env python3
"""Erzeugt sound/thumper.ogg: ein Schlag des Thumpers (arrakis-thump, 0.16.2).

Max im Spiel (01.11.2026, T34 Frage 1): Der Thumper pocht sichtbar, ist aber nicht zu hören. scripts/thumper.lua spielt
den Ton einmal je Sekunde (ein Stampfzyklus der Animation). Synthetisch: tiefer Schlag mit fallender Tonhöhe (70 → 38 Hz,
schnell abklingend), ein kurzes metallisches Klacken des Stempels und ein Rieseln von Sand. 0,9 s lang.

Aufruf: python3 tools/ton/thumper.py [Ziel.ogg]   (braucht numpy und ffmpeg mit libvorbis)
"""
import pathlib
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
DUR = 0.9


def lowpass(signal, cutoff):
    spec = np.fft.rfft(signal)
    freqs = np.fft.rfftfreq(len(signal), 1 / SR)
    spec *= 1 / (1 + (freqs / cutoff) ** 4)
    return np.fft.irfft(spec, len(signal))


def bandpass(signal, lo, hi):
    spec = np.fft.rfft(signal)
    freqs = np.fft.rfftfreq(len(signal), 1 / SR)
    spec *= (1 / (1 + (freqs / hi) ** 4)) * (1 - 1 / (1 + (freqs / lo) ** 4))
    return np.fft.irfft(spec, len(signal))


def main():
    target = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[2] / "sound" / "thumper.ogg"
    rng = np.random.default_rng(1965)
    t = np.arange(int(SR * DUR)) / SR
    freq = 38 + 32 * np.exp(-t / 0.06)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    boom = (np.sin(phase) + 0.45 * np.sin(2 * phase) + 0.2 * np.sin(3 * phase)) * np.exp(-t / 0.22)
    attack = int(0.004 * SR)
    boom[:attack] *= np.linspace(0, 1, attack)
    clank = bandpass(rng.standard_normal(len(t)), 500, 1800) * np.exp(-t / 0.025)
    clank /= np.max(np.abs(clank))
    sand = lowpass(rng.standard_normal(len(t)), 900) * np.exp(-((t - 0.12) / 0.18) ** 2)
    sand /= np.max(np.abs(sand))
    mix = boom / np.max(np.abs(boom)) + 0.22 * clank + 0.12 * sand
    fade = int(0.15 * SR)
    mix[-fade:] *= np.cos(np.linspace(0, np.pi / 2, fade)) ** 2
    mix *= 0.95 / np.max(np.abs(mix))
    pcm = (mix * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        wav = pathlib.Path(tmp) / "thump.wav"
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
