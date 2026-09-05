#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Procedural smoke puff for SwiftUI's colorEffect. Everything is computed per
// pixel from 3D simplex noise; there are no textures. The third noise axis is
// time, so the field evolves rather than scrolls.

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

// Smoke density, 0...~1.4: the shape carved by advected fractal noise, then
// thinned with distance from the centre so the rim is translucent wisps.
static float field(float2 uv, float time, float e, float flow) {
    float R = radius(e);
    float d2 = dot(uv, uv) / (R * R);
    // Dense lobed core plus a wide, thin haze that reaches the full radius.
    float mass = shape(uv, time, e) + 0.42 * exp(-1.1 * d2);
    // The noise is scaled by a fixed mid radius, not the current one, so a
    // change of size moves smoke through the field instead of zooming it.
    float n = flowNoise(uv, flow, time, radius(0.5));

    // Noise bites hardest where the mass is thin, so the rim is carved into
    // wisps while the centre stays solid.
    float thin = 1.0 - saturate(mass);
    float density = mass * (1.0 - (0.38 + 0.55 * thin) * (1.0 - n));

    // Radial falloff: dense middle, thin edge.
    density *= exp(-1.1 * d2);

    return max(0.0, density - 0.12);
}

} // namespace smoke

/// position, color: supplied by SwiftUI.
/// size: the view's size in points.
/// time: seconds, any origin.
/// expansion: 0 = fully retracted wisp, 1 = fully expanded cloud.
/// flow: outward drift phase; one unit doubles the distance of every feature.
///       Increase it to stream smoke outwards, hold it to let it hang.
/// tint: colour of the smoke; alpha scales overall opacity.
[[stitchable]] half4 puff(float2 position, half4 color, float2 size, float time, float expansion, float flow, half4 tint) {
    using namespace smoke;

    float scale = min(size.x, size.y);
    float2 uv = (position - 0.5 * size) / scale;
    float e = saturate(expansion);

    float f = field(uv, time, e, flow);
    if (f <= 0.0) { return half4(0.0); }

    // Light the coarse shape from the upper left: each lobe gets a bright
    // top and a shadowed underside, and the fine carving stays unlit so it
    // reads as vapour rather than rock.
    float R = radius(e) * 0.68;
    float h = R * 0.12;
    float s0 = shape(uv, time, e);
    float2 grad = float2(shape(uv + float2(h, 0.0), time, e) - s0,
                         shape(uv + float2(0.0, h), time, e) - s0) / h;
    const float2 light = normalize(float2(-0.4, -1.0));
    float lit = saturate(0.5 - 0.13 * R * dot(grad, light));

    // Fine grain, one high octave at low weight, drifting with the flow.
    float grain = flowGrain(uv, flow, time, radius(0.5));

    // Beer-Lambert style opacity: dense centre, soft translucent edges. There
    // is a fixed amount of smoke: opacity falls with the puff's area, so the
    // small puff is dense and the expanded one is the same smoke spread thin.
    float conserve = clamp(pow(radius(0.35) / radius(e), 2.0), 0.12, 3.0);
    float alpha = 1.0 - exp(-1.9 * conserve * f);
    float shade = mix(0.64, 1.0, lit) * mix(0.88, 1.0, saturate(f)) * (0.96 + 0.06 * grain);

    half a = half(alpha) * tint.a;
    return half4(tint.rgb * half(shade) * a, a);
}
