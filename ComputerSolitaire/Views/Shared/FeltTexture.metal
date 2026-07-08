#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

/// Integer hash (lowbias32-style): stays uncorrelated at any coordinate,
/// unlike fract/sin float hashes which streak at large positions.
static float hash21(float2 p) {
    uint2 q = uint2(int2(floor(p)));
    uint h = q.x * 1597334673u ^ q.y * 3812015801u;
    h = (h ^ (h >> 16)) * 0x7feb352du;
    h = (h ^ (h >> 15)) * 0x846ca68bu;
    h = h ^ (h >> 16);
    return float(h) * (1.0 / 4294967296.0);
}

/// Felt table texture: modulates the base color's luminance with fine grain,
/// a top sheen, and a size-relative vignette.
[[ stitchable ]] half4 feltTexture(float2 position, half4 color, float2 size) {
    if (color.a <= 0.0h) {
        return color;
    }

    // Fine grain on a one-point grid — coarse enough to read as fabric
    // tooth at viewing distance, fine enough to stay uniform.
    float grain = hash21(position) - 0.5;

    // Taper grain on light base colors, where the same multiplicative
    // amplitude reads much grittier than on dark ones.
    float luma = dot(float3(color.rgb), float3(0.299, 0.587, 0.114));
    float grainAmp = 0.15 * mix(1.0, 0.5, smoothstep(0.35, 0.85, luma));

    float lum = 1.0 + grain * grainAmp;

    // Sheen: light falling from the top of the table.
    float sheen = 1.0 - smoothstep(0.0, size.y * 0.45, position.y);
    lum += sheen * 0.06;

    // Vignette, relative to the view's diagonal.
    float2 centered = (position - size * 0.5) / (0.5 * length(size));
    float vignette = smoothstep(0.35, 1.05, length(centered));
    lum *= 1.0 - vignette * 0.28;

    return half4(clamp(color.rgb * half(lum), 0.0h, 1.0h), color.a);
}
