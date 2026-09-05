#!/usr/bin/env python3
"""Generate the feedback cues in TypeMeIt/Resources. Run after changing anything here.

start  an exhale: soft wind whose formant glides up as it fades, 620 ms
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


def resonate(xs, f, bw, gain=1.0):
    r = math.exp(-math.pi * bw / RATE)
    c = 2 * r * math.cos(TAU * f / RATE)
    r2 = r * r
    y1 = y2 = 0.0
    out = []
    for x in xs:
        y = x * (1 - r) + c * y1 - r2 * y2
        y2, y1 = y1, y
        out.append(y * gain)
    return out


def inhale(ms, f1, f2, bed, seed, peak=0.55, tail=4.5, bw1=140, bw2=260, g2=0.45, bed_hz=180, lp=1400):
    # the buffer runs 45% past the breath so the tail settles instead of being cut
    r = rng(seed)
    n = [r() for _ in range(frames(ms * 1.45))]
    breath = ms / 1000 * RATE
    for i in range(len(n)):
        t = i / breath
        n[i] *= smoother(t / peak) if t < peak else math.exp(-(t - peak) * tail)
    a = resonate(n, f1, bw1)
    b = resonate(n, f2, bw2, g2)
    low = onepole(n, bed_hz)
    return onepole([a[i] + b[i] + low[i] * bed for i in range(len(n))], lp)


def dust_pop():
    r = rng(7)
    o = [1.0, -0.6, 0.3]
    for i in range(3, frames(260)):
        o.append(r() * 0.02 * math.exp(-i / RATE * 20))
    return onepole(o, 3000)


def exhale_rising(ms=520, seed=4, tail=3.2):
    # the inhale mirrored: a fast onset, then the one formant glides up more
    # than an octave as the breath decays
    r = rng(seed)
    n = [r() for _ in range(frames(ms))]
    L = len(n)
    for i in range(L):
        t = i / L
        n[i] *= smoother(t / 0.12) * math.exp(-max(0.0, t - 0.12) * tail)
    res = math.exp(-math.pi * 160 / RATE)
    y1 = y2 = 0.0
    e = []
    for j in range(L):
        f = 180 * 2.2 ** (j / L)
        c = 2 * res * math.cos(TAU * f / RATE)
        y = n[j] * (1 - res) + c * y1 - res * res * y2
        y2, y1 = y1, y
        e.append(y)
    low = onepole(n, 180)
    return onepole([e[i] + 0.6 * low[i] for i in range(L)], 1600)


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


write("TypeMeIt/Resources/pop_start.wav", exhale_rising(ms=620, tail=2.8), peak=0.2)
write("TypeMeIt/Resources/pop_pin.wav", dust_pop())
# the stop sits under the start and pin
write("TypeMeIt/Resources/pop_stop.wav", hum_off(), peak=0.28)
