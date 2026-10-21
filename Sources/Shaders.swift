/// Compiled at runtime. Uniform structs hold only scalars so the Swift structs in Renderer.swift match byte for byte.
let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct StampU { float virtW, virtH, cardW, cardH, atlasW, atlasH, offX, offY, strideExtra, pad0, pad1, pad2; };
struct Stamp { float x, y, scale; int card; };
struct StampOut { float4 pos [[position]]; float2 local; int card [[flat]]; };

vertex StampOut stampVS(uint vid [[vertex_id]], uint iid [[instance_id]],
                        constant Stamp *stamps [[buffer(0)]], constant StampU &u [[buffer(1)]]) {
    const float2 corners[6] = { float2(0,0), float2(1,0), float2(0,1), float2(1,0), float2(1,1), float2(0,1) };
    Stamp s = stamps[iid];
    float2 c = corners[vid];
    float2 card = float2(u.cardW, u.cardH);
    float2 p = float2(s.x, s.y) + c * card * s.scale;
    StampOut o;
    o.pos = float4(p.x / u.virtW * 2 - 1, 1 - p.y / u.virtH * 2, 0, 1);
    o.local = c * card;
    o.card = s.card;
    return o;
}

fragment float4 stampFS(StampOut in [[stage_in]], texture2d<float> atlas [[texture(0)]], constant StampU &u [[buffer(1)]]) {
    int cw = int(u.cardW), ch = int(u.cardH);
    int px = clamp(int(floor(in.local.x)), 0, cw - 1);
    int py = clamp(int(floor(in.local.y)), 0, ch - 1);
    int aw = int(u.atlasW), ah = int(u.atlasH);
    int cx = (in.card % 13) * cw + int(u.offX);
    int cy = (in.card / 13) * ch + int(u.offY);
    // Copy with a wrong row stride, like a blitter given the wrong pitch.
    int stride = aw + int(u.strideExtra);
    int total = aw * ah;
    int lin = cy * aw + cx + py * stride + px;
    lin = ((lin % total) + total) % total;
    float4 c = atlas.read(uint2(uint(lin % aw), uint(lin / aw)));
    if (c.a < 0.5) discard_fragment();
    return float4(c.rgb, 1);
}

struct FSOut { float4 pos [[position]]; };

vertex FSOut fullVS(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    FSOut o;
    o.pos = float4(p * 2 - 1, 0, 1);
    return o;
}

float hash11(float n) { return fract(sin(n * 127.1 + 311.7) * 43758.5453); }

float4 readWrap(texture2d<float> t, int2 p, int W, int H) {
    p.x = ((p.x % W) + W) % W;
    p.y = ((p.y % H) + H) % H;
    return t.read(uint2(p));
}

struct CanvasU { float mode, texW, texH, seed, bands, amount, dx, dy, rx0, ry0, rx1, ry1, feltR, feltG, feltB, pad; };

fragment float4 canvasFS(FSOut in [[stage_in]], texture2d<float> src [[texture(0)]], constant CanvasU &u [[buffer(0)]]) {
    int2 p = int2(in.pos.xy);
    int m = int(u.mode);
    if (m == 1) {
        float band = floor(in.pos.y / u.texH * u.bands);
        if (hash11(band + u.seed * 13.0) > 0.4) p.x += int((hash11(band * 7.3 + u.seed) * 2 - 1) * u.amount);
    } else if (m == 2) {
        p -= int2(int(u.dx), int(u.dy));
    } else if (m == 3) {
        if (in.pos.x >= u.rx0 && in.pos.x < u.rx1 && in.pos.y >= u.ry0 && in.pos.y < u.ry1) return float4(u.feltR, u.feltG, u.feltB, 1);
    } else if (m == 4) {
        float h = hash11(floor(in.pos.x / u.bands) + u.seed);
        if (h > 0.5) p.y -= int(ceil(u.amount * h));
    }
    return readWrap(src, p, int(u.texW), int(u.texH));
}

struct PostU { float texW, texH, time, seed, hue, paletteMix, paletteShift, invert, split, tear, feltMix, ftR, ftG, ftB, pixelScale, pad; };

constant float3 ega[16] = {
    float3(0,0,0), float3(0,0,0.5), float3(0,0.5,0), float3(0,0.5,0.5),
    float3(0.5,0,0), float3(0.5,0,0.5), float3(0.5,0.5,0), float3(0.75,0.75,0.75),
    float3(0.5,0.5,0.5), float3(0,0,1), float3(0,1,0), float3(0,1,1),
    float3(1,0,0), float3(1,0,1), float3(1,1,0), float3(1,1,1)
};

float3 hueRotate(float3 c, float a) {
    float3 k = float3(0.57735);
    float ca = cos(a), sa = sin(a);
    return clamp(c * ca + cross(k, c) * sa + k * dot(k, c) * (1 - ca), 0.0, 1.0);
}

fragment float4 postFS(FSOut in [[stage_in]], texture2d<float> src [[texture(0)]], constant PostU &u [[buffer(0)]]) {
    int W = int(u.texW), H = int(u.texH);
    float2 p = in.pos.xy;
    if (u.tear > 0) {
        float tick = floor(u.time * 15.0);
        float band = floor(p.y / (24.0 * u.pixelScale));
        if (hash11(band * 3.1 + tick * 0.9 + u.seed) < u.tear * 0.35)
            p.x += (hash11(band + tick * 1.3) * 2 - 1) * u.tear * 0.25 * u.texW;
    }
    int2 ip = int2(p);
    int s = int(u.split);
    float3 c = float3(readWrap(src, ip + int2(s, 0), W, H).r,
                      readWrap(src, ip, W, H).g,
                      readWrap(src, ip - int2(s, 0), W, H).b);
    if (u.feltMix > 0 && distance(c, float3(0, 128.0 / 255.0, 0)) < 0.06)
        c = mix(c, float3(u.ftR, u.ftG, u.ftB), u.feltMix);
    if (u.paletteMix > 0) {
        int best = 0;
        float bd = 1e9;
        for (int i = 0; i < 16; i++) {
            float d = distance_squared(c, ega[i]);
            if (d < bd) { bd = d; best = i; }
        }
        c = mix(c, ega[(best + int(u.paletteShift)) % 16], u.paletteMix);
    }
    if (u.hue != 0) c = hueRotate(c, u.hue);
    c = mix(c, 1 - c, u.invert);
    return float4(c, 1);
}
"""
