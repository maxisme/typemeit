#!/usr/bin/env python3
"""Generate the feedback cues in TypeMeIt/Resources. Run after changing anything here.

pin    a dust pop: one click with a whisper of crackle behind it
stop   a valve hum letting go
"""
import math
import struct
import wave

RATE = 48000
PEAK = 0.4
TAU = math.tau


def rng(seed):
    s = seed or 1
    def f():
        nonlocal s
        s = (s * 1103515245 + 12345) & 0x7FFFFFFF
        return s / 0x3FFFFFFF - 1
    return f


def frames(ms):
    return math.ceil(ms / 1000 * RATE)


def smoother(x):
    c = min(max(x, 0.0), 1.0)
    return c * c * c * (c * (c * 6 - 15) + 10)


def onepole(xs, cutoff):
    a = 1 - math.exp(-TAU * cutoff / RATE)
    y = 0.0
    out = []
    for x in xs:
        y += a * (x - y)
        out.append(y)
    return out


def dust_pop():
    r = rng(7)
    o = [1.0, -0.6, 0.3]
    for i in range(3, frames(260)):
        o.append(r() * 0.02 * math.exp(-i / RATE * 20))
    return onepole(o, 3000)


def hum_off():
    n = frames(700)
    ph = 0.0
    out = []
    for k in range(n):
        t = k / n
        ph += TAU * 82.4 * (1 - 0.08 * t) / RATE
        out.append(smoother(t / 0.03) * math.exp(-t * 4.2) * (math.sin(ph) + 0.3 * math.sin(2 * ph)))
    return out


def write(path, samples, peak=PEAK):
    scale = peak / max(abs(s) for s in samples)
    data = bytearray()
    for s in samples:
        v = int(max(-1.0, min(1.0, s * scale)) * 32767)
        data += struct.pack("<hh", v, v)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(data))


write("TypeMeIt/Resources/pop_pin.wav", dust_pop())
# the stop sits under the start and pin
write("TypeMeIt/Resources/pop_stop.wav", hum_off(), peak=0.28)
