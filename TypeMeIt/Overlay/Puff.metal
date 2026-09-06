#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Procedural smoke puff for SwiftUI's colorEffect. Everything is computed per
// pixel from 3D simplex noise; there are no textures. The third noise axis is
// time, so the field evolves rather than scrolls.
//
// The `smoke` namespace is also the source of the web version: web/generate.py
// transpiles it to GLSL, so it must stay within the subset both languages
// share (see that script for the substitutions it makes).

namespace smoke {

// Overall puff radius for an expansion value, in view units where the short
// side spans -0.5...0.5.
static float radius(float e) { return mix(0.05, 0.25, e); }

static float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float4 mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float4 permute(float4 x) { return mod289(((x * 34.0) + 1.0) * x); }
static float4 taylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

// Simplex noise (Gustavson / McEwan), range roughly -1...1.
static float snoise(float3 v) {
    const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);
    const float4 D = float4(0.0, 0.5, 1.0, 2.0);

    float3 i = floor(v + dot(v, C.yyy));
    float3 x0 = v - i + dot(i, C.xxx);

    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g.xyz, l.zxy);
    float3 i2 = max(g.xyz, l.zxy);

    float3 x1 = x0 - i1 + C.xxx;
    float3 x2 = x0 - i2 + C.yyy;
    float3 x3 = x0 - D.yyy;

    i = mod289(i);
    float4 p = permute(permute(permute(
        i.z + float4(0.0, i1.z, i2.z, 1.0))
        + i.y + float4(0.0, i1.y, i2.y, 1.0))
        + i.x + float4(0.0, i1.x, i2.x, 1.0));

    float n_ = 0.142857142857;
    float3 ns = n_ * D.wyz - D.xzx;

    float4 j = p - 49.0 * floor(p * ns.z * ns.z);
    float4 x_ = floor(j * ns.z);
    float4 y_ = floor(j - 7.0 * x_);

    float4 x = x_ * ns.x + ns.yyyy;
    float4 y = y_ * ns.x + ns.yyyy;
    float4 h = 1.0 - abs(x) - abs(y);

    float4 b0 = float4(x.xy, y.xy);
    float4 b1 = float4(x.zw, y.zw);

    float4 s0 = floor(b0) * 2.0 + 1.0;
    float4 s1 = floor(b1) * 2.0 + 1.0;
    float4 sh = -step(h, float4(0.0));

    float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

    float3 p0 = float3(a0.xy, h.x);
    float3 p1 = float3(a0.zw, h.y);
    float3 p2 = float3(a1.xy, h.z);
    float3 p3 = float3(a1.zw, h.w);

    float4 norm = taylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;

    float4 m = max(0.6 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, float4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// Five octaves, the xy plane rotated between octaves so no lattice direction
// survives into the result. Range roughly -1...1.
static float fbm(float3 p) {
    const float2x2 rot = float2x2(0.80, 0.60, -0.60, 0.80);
    float sum = 0.0;
    float amp = 0.5;
    float norm = 0.0;
    for (int i = 0; i < 5; i++) {
        sum += amp * snoise(p);
        norm += amp;
        p = float3(rot * p.xy * 2.03, p.z * 1.7 + 11.3);
        amp *= 0.5;
    }
    return sum / norm;
}

// Coarse shape of the puff: a soft core with a ring of six lobes around it,
// each swelling and drifting on its own slow cycle, plus one low octave of
// noise so the lobes are not perfect spheres. This is what gets lit. Time is
// only ever an oscillator phase or the third noise axis, so nothing drifts
// unbounded. `uv` is centred and normalised so the view's short side spans
// -0.5...0.5.
static float shape(float2 uv, float time, float e) {
    // The lobed mass sits well inside the puff's overall radius; the thin haze
    // added in `field` carries the fade out to the full extent.
    float R = radius(e) * 0.68;

    float mass = 0.85 * exp(-dot(uv, uv) / (R * R * 0.32));

    float spin = time * 0.045;
    for (int i = 0; i < 6; i++) {
        float k = float(i);
        float ang = spin + k * 1.0472 + 0.30 * sin(time * 0.31 + k * 1.7);
        float reach = R * (0.58 + 0.12 * sin(time * 0.43 + k * 2.3));
        float2 c = reach * float2(cos(ang), sin(ang));
        float r = R * (0.42 + 0.08 * sin(time * 0.37 + k * 0.9));
        float2 q = uv - c;
        mass += exp(-dot(q, q) / (r * r * 0.40));
    }

    float low = snoise(float3(uv * (1.6 / R), time * 0.12));
    return mass * (0.82 + 0.22 * low);
}

// Advected fractal noise, 0...1. Features ride outwards from the centre as
// `flow` increases and back in as it decreases: the domain is zoomed by the
// fractional part of `flow`, and two layers half a cycle apart are cross-faded
// so each one resets while its weight is zero. Nothing ever leaves float
// range, however long the app runs.
static float flowNoise(float2 uv, float flow, float time, float R) {
    float n = 0.0;
    float wsq = 0.0;
    for (int layer = 0; layer < 2; layer++) {
        float ph = flow + 0.5 * float(layer);
        float fi = fract(ph);
        float w = 1.0 - abs(2.0 * fi - 1.0);
        float zoom = exp2(-fi);
        float z = floor(ph) * 17.3 + float(layer) * 31.7;
        float2 p = uv * (2.75 / R) * zoom;
        float2 warp = float2(
            fbm(float3(p * 0.5, z + time * 0.08)),
            fbm(float3(p * 0.5 + float2(5.2, 1.3), z + 7.0 + time * 0.08)));
        n += w * fbm(float3(p + 0.9 * warp, z + 3.1 + time * 0.12));
        wsq += w * w;
    }
    // Blending two independent fields lowers the variance mid-fade; dividing
    // by the weight norm keeps the contrast constant through the cycle.
    n /= sqrt(wsq);
    return smoothstep(-0.55, 0.6, n);
}

// Same two-layer advection for the fine grain.
static float flowGrain(float2 uv, float flow, float time, float R) {
    float g = 0.0;
    float wsq = 0.0;
    for (int layer = 0; layer < 2; layer++) {
        float ph = flow + 0.5 * float(layer);
        float fi = fract(ph);
        float w = 1.0 - abs(2.0 * fi - 1.0);
        g += w * snoise(float3(uv * (6.5 / R) * exp2(-fi), floor(ph) * 5.1 + float(layer) * 9.7 + time * 0.2));
        wsq += w * w;
    }
    return 0.5 + 0.5 * g / sqrt(wsq);
}

// Smoke density of the body, 0...~1.4: the shape carved by the advected
// noise `n`, then thinned with distance from the centre so the rim is
// translucent wisps.
static float field(float2 uv, float time, float e, float n) {
    float R = radius(e);
    float d2 = dot(uv, uv) / (R * R);
    // Dense lobed core plus a wide, thin haze that reaches the full radius.
    float mass = shape(uv, time, e) + 0.42 * exp(-1.1 * d2);

    // Noise bites hardest where the mass is thin, so the rim is carved into
    // wisps while the centre stays solid.
    float thin = 1.0 - saturate(mass);
    float density = mass * (1.0 - (0.38 + 0.55 * thin) * (1.0 - n));

    // Radial falloff: dense middle, thin edge.
    density *= exp(-1.1 * d2);

    return max(0.0, density - 0.12);
}

// Fragments left behind when the puff retracts: the body's own density as it
// was at the size it is retreating from (`trail`), kept only outside the
// current body, and only where a slow low-frequency mask and the densest
// clumps of the advected noise coincide. So they are bits of the larger
// cloud left inside its old footprint, and they fade as the trail catches up.
static float orphans(float2 uv, float time, float e, float trail, float n) {
    float gap = trail - e;
    if (gap <= 0.005) { return 0.0; }
    float Re = radius(e);
    float d = length(uv);
    float was = field(uv, time, trail, n);
    float outside = smoothstep(Re * 1.05, Re * 1.5, d);
    float mask = smoothstep(0.6, 0.88, 0.5 + 0.5 * snoise(float3(uv * (1.1 / radius(0.5)) + 7.0, time * 0.06)));
    float clumps = n * n * n;
    return 0.6 * was * outside * mask * clumps * saturate(gap * 4.0);
}

// Fixed amount of smoke: opacity falls with the area it is spread over, so
// the small puff is dense and the expanded one is the same smoke spread thin.
static float conserve(float e) {
    return clamp(pow(radius(0.35) / radius(e), 2.0), 0.12, 3.0);
}

// MARK: Lightning

static float hash11(float p) { return fract(sin(p * 127.1 + 311.7) * 43758.5453); }

static float segmentDistance(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}

// The `k`th of `n` corners of a jagged path from `a` to `b`: the straight
// line between them, each corner knocked sideways by up to `wander`, most in
// the middle and not at all at the ends, so the path stays where it was
// aimed. Seeded by `seed`, so every strike takes a different route.
static float2 boltCorner(float seed, float2 a, float2 b, float wander, int n, int k) {
    float t = float(k) / float(n);
    float2 off = float2(hash11(seed + float(k) * 7.3) - 0.5, 0.5 * (hash11(seed + float(k) * 3.1 + 50.0) - 0.5));
    return mix(a, b, t) + wander * sin(3.14159 * t) * off;
}

// Distance from `uv` to that path.
static float boltDistance(float2 uv, float seed, float2 a, float2 b, float wander, int n) {
    float d = 1e9;
    float2 p = boltCorner(seed, a, b, wander, n, 0);
    for (int i = 1; i <= n; i++) {
        float2 q = boltCorner(seed, a, b, wander, n, i);
        d = min(d, segmentDistance(uv, p, q));
        p = q;
    }
    return d;
}

// Lightning behind the puff, struck `age` seconds ago: the light thrown
// forward through the smoke by a jagged channel with one branch, 0...1. The
// channel itself is never drawn; only its broad glow is, so it reads as a
// flash behind a layer of cloud. Carries the envelope: an instant flash, two
// dimmer re-strikes down the same channel, then a fade gone within a second.
static float lightning(float2 uv, float R, float seed, float age) {
    if (age < 0.0 || age > 1.0) { return 0.0; }
    float env = 0.0;
    env += step(0.0, age) * exp(-age * 14.0);
    env += 0.5 * step(0.1, age) * exp(-(age - 0.1) * 14.0);
    env += 0.3 * step(0.22, age) * exp(-(age - 0.22) * 12.0);
    env += 0.08 * exp(-age * 4.0) * (1.0 - age);
    if (env < 0.003) { return 0.0; }

    // Main channel down through the body of the cloud.
    float2 a = float2((hash11(seed) - 0.5) * 0.7 * R, -0.72 * R);
    float2 b = float2((hash11(seed + 1.0) - 0.5) * 0.7 * R, 0.72 * R);
    float wander = 0.55 * R;
    float d = boltDistance(uv, seed, a, b, wander, 7);

    // A branch peels off partway down and heads out sideways, not as far.
    int fork = 2 + int(hash11(seed + 9.0) * 3.0);
    float2 c = boltCorner(seed, a, b, wander, 7, fork);
    float side = hash11(seed + 21.0) < 0.5 ? -1.0 : 1.0;
    float2 e = c + float2(side * 0.42 * R, 0.3 * R);
    float db = boltDistance(uv, seed + 77.0, c, e, 0.2 * R, 3);
    d = min(d, db + 0.05 * R);

    // A bright core of light around the channel, blurred wide by the smoke.
    float glow = 0.6 * exp(-(d * d) / (0.06 * R * R)) + 0.5 * exp(-d / (0.35 * R));
    return env * saturate(glow);
}

// Colour of the puff at `position` in a view of `size`, premultiplied.
// expansion: 0 = fully retracted wisp, 1 = fully expanded cloud.
// trail: the expansion the puff is retreating from, >= expansion. Fragments
//        are left in the shell between the two; equal means none.
// flow: outward drift phase; one unit doubles the distance of every feature.
//       Increase it to stream smoke outwards, hold it to let it hang.
// strike: the `time` at which lightning last struck, or negative for none.
//         The bolt lasts a second; the value also seeds its route.
// tint: colour of the smoke; alpha scales overall opacity.
static half4 render(float2 position, float2 size, float time, float expansion, float trail, float flow, float strike, half4 tint) {
    float scale = min(size.x, size.y);
    float2 uv = (position - 0.5 * size) / scale;
    float e = saturate(expansion);
    float tr = max(e, saturate(trail));

    // Beyond 1.6 radii the density floor has removed everything, so skip the
    // noise there; most of the view is this cheap.
    if (dot(uv, uv) > 2.56 * radius(tr) * radius(tr)) { return half4(0.0); }

    // The noise is scaled by a fixed mid radius, not the current one, so a
    // change of size moves smoke through the field instead of zooming it.
    float n = flowNoise(uv, flow, time, radius(0.5));
    float body = field(uv, time, e, n);
    float left = orphans(uv, time, e, tr, n);
    float f = body + left;

    // `time` wraps hourly in the app, so a strike just before the wrap is
    // still young just after it.
    float age = time - strike;
    if (age < -1800.0) { age += 3600.0; }
    if (f <= 0.0) { return half4(0.0); }
    float bolt = strike < 0.0 ? 0.0 : lightning(uv, radius(e), strike, age);

    // Light the coarse shape from the upper left: each lobe gets a bright
    // top and a shadowed underside, and the fine carving stays unlit so it
    // reads as vapour rather than rock.
    float R = radius(e) * 0.68;
    float h = R * 0.12;
    float s0 = shape(uv, time, e);
    float2 grad = float2(shape(uv + float2(h, 0.0), time, e) - s0,
                         shape(uv + float2(0.0, h), time, e) - s0) / h;
    float2 light = normalize(float2(-0.4, -1.0));
    float lit = saturate(0.5 - 0.13 * R * dot(grad, light));

    // Fine grain, one high octave at low weight, drifting with the flow.
    float grain = flowGrain(uv, flow, time, radius(0.5));

    // Beer-Lambert style opacity: dense centre, soft translucent edges. The
    // body is as thin as its own size demands; the fragments as thin as the
    // size they were shed from.
    float alpha = 1.0 - exp(-1.9 * (conserve(e) * body + conserve(tr) * left));
    // A white or grey tint takes deep shadows; a coloured one is shaded
    // only lightly, since darkening a hue towards black reads as soot.
    float peak = max(tint.r, max(tint.g, tint.b));
    float saturation = peak > 0.0 ? (peak - min(tint.r, min(tint.g, tint.b))) / peak : 0.0;
    float floor_ = mix(0.64, 0.86, saturation);
    float shade = mix(floor_, 1.0, lit) * mix(mix(0.88, 0.96, saturation), 1.0, saturate(f)) * (0.96 + 0.06 * grain);

    float a = alpha * tint.a;
    float3 rgb = float3(tint.rgb) * shade;

    // The light comes from behind: the thin haze in front of it whitens
    // and thickens, while the dense lobes stay shaded as silhouettes, so
    // the flash reads as being behind a layer of cloud.
    float3 electric = float3(0.84, 0.9, 1.0);
    float lit = bolt * mix(1.0, 0.25, saturate(f));
    rgb = mix(rgb, electric, 0.75 * lit);
    a += (1.0 - a) * 0.45 * lit;

    return half4(half3(rgb * a), half(a));
}

} // namespace smoke

/// position, color: supplied by SwiftUI. The remaining arguments are
/// documented on smoke::render.
[[stitchable]] half4 puff(float2 position, half4 color, float2 size, float time, float expansion, float trail, float flow, float strike, half4 tint) {
    return smoke::render(position, size, time, expansion, trail, flow, strike, tint);
}
