#include <metal_stdlib>
using namespace metal;

// Заставка: сплошной фон и стекло с вырезом по логотипу.
// Внутри стекла вихрь искажается полем потока.
// Цвет считается в линейном sRGB и кодируется sRGB-кривой под bgra8Unorm.

struct IntroUniforms {
    float elapsed;
    float progress;
    float2 resolution;
};

struct VertexOut {
    float4 position [[position]];
};

// SolidColor
constant float3 kBackgroundSRGB = float3(14.0, 18.0, 22.0) / 255.0; // #0e1216

// Стекло
constant float kGlassScale = 0.41;
constant float kGlassRefraction = 1.09;
constant float kGlassThickness = 0.27;
constant float kGlassAberration = 0.89;
constant float kGlassEdgeSoftness = 0.2;
constant float kGlassFresnel = 0.01;
constant float kGlassFresnelSoftness = 0.14;
constant bool kGlassCutout = true;
constant float2 kGlassCenter = float2(0.5, 0.5);
constant float kGlassLightAngle = 300.0;
constant float kGlassHighlight = 0.05;
constant float kGlassHighlightSoftness = 0.5;
constant float3 kGlassHighlightColor = float3(1.0); // #ffffff
constant float3 kGlassFresnelColor = float3(1.0);   // #ffffff

// Swirl
constant float3 kSwirlColorA = float3(1.0, 1.0, 1.0); // #ffffff
constant float3 kSwirlColorB = float3(1.0, 0.0, 0.0); // #ff0000, интерполяция в OKLab
constant float kSwirlBlend = 56.0;
constant float kSwirlDetail = 4.2;
constant float kSwirlSpeed = 0.1;

// FlowField (edges: mirror, seed: 0)
constant float kFlowDetail = 1.0;
constant float kFlowEvolutionSpeed = 1.5;
constant float kFlowSpeed = 1.8;
constant float kFlowStrength = 0.5;

// Поле логотипа: 512×512 uint16, расстояние = v / 32767.5 − 1 в единицах поля (поле = 1).
// Текстура r16Unorm отдаёт v / 65535, поэтому множитель 65535 / 32767.5.
constant float kSdfDecodeScale = 65535.0 / 32767.5;
constant float kSdfGradientStep = 0.01;

constant float kTwoPi = 6.283185307179586;
constant float kDegToRad = 0.017453292519943295;

vertex VertexOut liquidMetalVertex(uint vertexID [[vertex_id]]) {
    const float2 corners[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    VertexOut out;
    out.position = float4(corners[vertexID], 0.0, 1.0);
    return out;
}

// MARK: - Цвет

static float3 srgbToLinear(float3 c) {
    return select(pow((c + 0.055) / 1.055, float3(2.4)), c / 12.92, c <= 0.04045);
}

static float3 linearToSrgb(float3 c) {
    return select(pow(c, float3(0.41666)) * 1.055 - 0.055, c * 12.92, c <= 0.0031308);
}

static float3 rgbToOklab(float3 rgb) {
    float l = dot(rgb, float3(0.4122214708, 0.5363325363, 0.0514459929));
    float m = dot(rgb, float3(0.2119034982, 0.6806995451, 0.1073969566));
    float s = dot(rgb, float3(0.0883024619, 0.2817188376, 0.6299787005));
    float3 lms = sign(float3(l, m, s)) * pow(abs(float3(l, m, s)), float3(1.0 / 3.0));
    return float3(
        dot(lms, float3(0.2104542553, 0.7936177850, -0.0040720468)),
        dot(lms, float3(1.9779984951, -2.4285922050, 0.4505937099)),
        dot(lms, float3(0.0259040371, 0.7827717662, -0.8086757660))
    );
}

static float3 oklabToRgb(float3 lab) {
    float l = lab.x + lab.y * 0.3963377774 + lab.z * 0.2158037573;
    float m = lab.x - lab.y * 0.1055613458 - lab.z * 0.0638541728;
    float s = lab.x - lab.y * 0.0894841775 - lab.z * 1.2914855480;
    float3 lms = float3(l * l * l, m * m * m, s * s * s);
    return float3(
        dot(lms, float3(4.0767416621, -3.3077115913, 0.2309699292)),
        dot(lms, float3(-1.2684380046, 2.6097574011, -0.3413193965)),
        dot(lms, float3(-0.0041960863, -0.7034186147, 1.7076147010))
    );
}

// MARK: - MaterialX Perlin (mx_perlin_noise_float, 3D)

static uint mxRotl32(uint x, uint k) {
    return (x << k) | (x >> (32u - k));
}

static uint mxBjfinal(uint a, uint b, uint c) {
    c ^= b; c -= mxRotl32(b, 14u);
    a ^= c; a -= mxRotl32(c, 11u);
    b ^= a; b -= mxRotl32(a, 25u);
    c ^= b; c -= mxRotl32(b, 16u);
    a ^= c; a -= mxRotl32(c, 4u);
    b ^= a; b -= mxRotl32(a, 14u);
    c ^= b; c -= mxRotl32(b, 24u);
    return c;
}

static uint mxHashInt(int x, int y, int z) {
    const uint seed = 0xdeadbeefu + (3u << 2u) + 13u;
    return mxBjfinal(seed + uint(x), seed + uint(y), seed + uint(z));
}

static float mxGradient(uint hash, float x, float y, float z) {
    uint h = hash & 15u;
    float u = h < 8u ? x : y;
    float v = h < 4u ? y : ((h == 12u || h == 14u) ? x : z);
    return ((h & 1u) != 0u ? -u : u) + ((h & 2u) != 0u ? -v : v);
}

static float mxFade(float t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

static float mxNoise3(float3 p) {
    int3 i = int3(floor(p));
    float3 f = p - float3(i);
    float u = mxFade(f.x);
    float v = mxFade(f.y);
    float w = mxFade(f.z);
    float n000 = mxGradient(mxHashInt(i.x,     i.y,     i.z),     f.x,       f.y,       f.z);
    float n100 = mxGradient(mxHashInt(i.x + 1, i.y,     i.z),     f.x - 1.0, f.y,       f.z);
    float n010 = mxGradient(mxHashInt(i.x,     i.y + 1, i.z),     f.x,       f.y - 1.0, f.z);
    float n110 = mxGradient(mxHashInt(i.x + 1, i.y + 1, i.z),     f.x - 1.0, f.y - 1.0, f.z);
    float n001 = mxGradient(mxHashInt(i.x,     i.y,     i.z + 1), f.x,       f.y,       f.z - 1.0);
    float n101 = mxGradient(mxHashInt(i.x + 1, i.y,     i.z + 1), f.x - 1.0, f.y,       f.z - 1.0);
    float n011 = mxGradient(mxHashInt(i.x,     i.y + 1, i.z + 1), f.x,       f.y - 1.0, f.z - 1.0);
    float n111 = mxGradient(mxHashInt(i.x + 1, i.y + 1, i.z + 1), f.x - 1.0, f.y - 1.0, f.z - 1.0);
    float result = (1.0 - w) * ((1.0 - v) * (n000 * (1.0 - u) + n100 * u) + v * (n010 * (1.0 - u) + n110 * u))
                 + w * ((1.0 - v) * (n001 * (1.0 - u) + n101 * u) + v * (n011 * (1.0 - u) + n111 * u));
    return 0.982 * result;
}

// MARK: - FlowField

static float2 flowFieldUV(float2 uv, float aspect, float time, float evolutionTime) {
    float2 p = float2(uv.x * aspect, uv.y);
    float scale = kFlowDetail;

    float drift1 = time * 0.7;
    float angle1 = mxNoise3(float3(p.x * scale + drift1 * 0.3,
                                   p.y * scale + drift1 * 0.5,
                                   evolutionTime * 0.2)) * kTwoPi;

    float drift2 = time * 0.5;
    float angle2 = mxNoise3(float3(p.x * (scale * 2.3) + drift2 * -0.4 + 173.5,
                                   p.y * (scale * 2.3) + drift2 * 0.3 + 291.7,
                                   evolutionTime * 0.15 + 50.0)) * kTwoPi;

    float drift3 = time * 0.3;
    float angle3 = mxNoise3(float3(p.x * (scale * 4.7) + drift3 * 0.2 + 527.3,
                                   p.y * (scale * 4.7) + drift3 * -0.6 + 839.1,
                                   evolutionTime * 0.1 + 100.0)) * kTwoPi;

    float2 flow = float2(cos(angle1), sin(angle1))
                + float2(cos(angle2), sin(angle2)) * 0.5
                + float2(cos(angle3), sin(angle3)) * 0.25;
    flow /= max(length(flow), 0.001);
    return uv + float2(flow.x * kFlowStrength / aspect, flow.y * kFlowStrength);
}

static float2 mirrorEdges(float2 uv) {
    float2 m = fmod(abs(uv), 2.0);
    return select(m, 2.0 - m, m >= 1.0);
}

// MARK: - Swirl

static float swirlPattern(float2 uv, float t) {
    float detail = kSwirlDetail;

    float freq1 = detail;
    float2 d1 = float2(
        uv.x + (sin(uv.y * (freq1 * 1.7) + t * 0.8) * 0.12 + cos(uv.x * (freq1 * 0.9) - t * 0.5) * 0.05),
        uv.y + (cos(uv.x * (freq1 * 1.3) - t * 0.6) * 0.12 + sin(uv.y * (freq1 * 1.1) + t * 0.7) * 0.05)
    );
    float pattern1 = sin(d1.x * (freq1 * 2.1) + d1.y * (freq1 * 1.8) + t * 0.4);

    float freq2 = detail * 2.1;
    float2 d2 = float2(
        d1.x + (cos(d1.y * (freq2 * 2.7) - t * 0.45) * 0.07 + sin(d1.x * (freq2 * 1.9) + t * 0.6) * 0.04),
        d1.y + (sin(d1.x * (freq2 * 2.3) + t * 0.65) * 0.07 + cos(d1.y * (freq2 * 1.6) - t * 0.4) * 0.04)
    );
    float pattern2 = cos(d2.x * (freq2 * 1.4) - d2.y * (freq2 * 1.9) + t * 0.35);

    float freq3 = detail * 3.7;
    float2 d3 = float2(
        d2.x + (sin(d2.y * (freq3 * 1.8) + t * 0.85) * 0.04 + cos(d2.x * (freq3 * 1.3) - t * 0.55) * 0.025 + sin((d2.x + d2.y) * (freq3 * 0.7) + t * 0.9) * 0.02),
        d2.y + (cos(d2.x * (freq3 * 1.6) - t * 0.75) * 0.04 + sin(d2.y * (freq3 * 1.1) + t * 0.5) * 0.025 + cos((d2.x + d2.y) * (freq3 * 0.8) - t * 0.95) * 0.02)
    );
    float pattern3 = sin(d3.x * (freq3 * 1.1) + d3.y * (freq3 * 1.5) - t * 0.55);

    return pattern1 * 0.45 + pattern2 * 0.35 + pattern3 * 0.2;
}

static float3 swirlColor(float2 uv, float t) {
    float pattern = swirlPattern(uv, t);
    float bias = (kSwirlBlend - 50.0) * 0.006;
    float mixT = smoothstep(0.3, 0.7, pattern * 0.5 + 0.5 + bias);
    float3 color = oklabToRgb(mix(rgbToOklab(kSwirlColorA), rgbToOklab(kSwirlColorB), mixT));
    float shimmer = sin(t * 2.5 + pattern * 8.0) * 0.015 + 1.0;
    return color * shimmer;
}

// Содержимое под стеклом: Swirl, искажённый FlowField.
struct ChildClock {
    float swirl;
    float flow;
    float evolution;
};

static float3 glassChild(float2 uv, float aspect, ChildClock clock) {
    float2 warped = mirrorEdges(flowFieldUV(uv, aspect, clock.flow, clock.evolution));
    return swirlColor(warped, clock.swirl);
}

// MARK: - Glass

static float sampleShape(texture2d<float> field, sampler s, float2 uv) {
    return field.sample(s, uv).r * kSdfDecodeScale - 1.0;
}

fragment float4 liquidMetalFragment(
    VertexOut in [[stage_in]],
    constant IntroUniforms &uniforms [[buffer(0)]],
    texture2d<float> shapeField [[texture(0)]]
) {
    constexpr sampler fieldSampler(filter::linear, address::clamp_to_edge);

    float2 resolution = uniforms.resolution;
    if (resolution.x < 1.0 || resolution.y < 1.0) {
        return float4(kBackgroundSRGB, 1.0);
    }

    // uv с началом внизу слева, поле логотипа занимает квадрат scale × высота.
    float2 uv = float2(in.position.x / resolution.x, 1.0 - in.position.y / resolution.y);
    float aspect = resolution.x / resolution.y;
    float2 sdfUV = float2((uv.x - kGlassCenter.x) * aspect, uv.y - kGlassCenter.y) / kGlassScale + 0.5;

    float sdfRaw = sampleShape(shapeField, fieldSampler, sdfUV);
    float sdfX = sampleShape(shapeField, fieldSampler, sdfUV + float2(kSdfGradientStep, 0.0));
    float sdfY = sampleShape(shapeField, fieldSampler, sdfUV + float2(0.0, kSdfGradientStep));
    float2 grad = float2(sdfX - sdfRaw, sdfY - sdfRaw) / kSdfGradientStep;

    float sdf = sdfRaw / kGlassScale;
    float pxH = 1.0 / resolution.y;
    float sharp = max(kGlassEdgeSoftness * 0.5, 0.001);
    float w1 = max(sharp * 0.03125, pxH * 1.5);
    float rb1 = saturate(-sdf / w1);
    float transition = smoothstep(0.0, 1.0, rb1);
    if (kGlassCutout && transition <= 0.0) {
        return float4(kBackgroundSRGB, 1.0);
    }

    // Преломление: плоская пластина, сила спадает от края внутрь как (1 − depth)².
    float thickness = kGlassThickness * 0.5;
    float thicknessRange = max(thickness * 0.3, 0.005);
    float depthNorm = saturate(-sdf / thicknessRange);
    float refrStrength = (1.0 - depthNorm) * (1.0 - depthNorm);
    float refrScale = kGlassRefraction * 0.15;
    float slopeLen = max(length(grad), 0.0001);
    float slopeScale = min(1.0, 12.0 / slopeLen);
    float2 offset = -grad * slopeScale * refrScale * refrStrength;
    offset.x /= aspect;
    float2 lensUV = uv + offset;
    float2 chromatic = offset * (kGlassAberration * 0.06);
    float2 rUV = lensUV + chromatic;
    float2 bUV = lensUV - chromatic;

    ChildClock clock = {
        uniforms.elapsed * kSwirlSpeed,
        uniforms.elapsed * kFlowSpeed * 0.1,
        uniforms.elapsed * kFlowEvolutionSpeed * 0.1
    };
    float3 baseColor = glassChild(uv, aspect, clock);
    float3 refracted = float3(
        glassChild(saturate(rUV), aspect, clock).r,
        glassChild(saturate(lensUV), aspect, clock).g,
        glassChild(saturate(bUV), aspect, clock).b
    );

    float lightX = cos(kGlassLightAngle * kDegToRad);
    float lightY = sin(kGlassLightAngle * kDegToRad);

    // Тонкий направленный блик по контуру.
    float w2 = max(sharp * 0.0625, pxH * 1.5);
    float ring = saturate(-(sdf - pxH) / w2) - saturate(-sdf / w2);
    float lightFacing = saturate((grad.x * lightX + grad.y * lightY) * 0.5 + 0.5);
    float rb2 = ring * lightFacing * kGlassHighlight;

    // Блик Фонга по нормали поля, взгляд вдоль +z.
    float3 normal = normalize(float3(grad, 2.0));
    float nDotH = dot(normal, float3(lightX, lightY, 2.0) * 0.4472135954999579);
    float shininess = exp2(8.0 - kGlassHighlightSoftness * 7.0);
    float specular = pow(saturate(nDotH), shininess) * kGlassHighlight * refrStrength;

    // Френелевское свечение у края.
    float fresnelWidth = max(kGlassFresnelSoftness * 0.06, 0.001);
    float fresnelDepth = saturate(-sdf / fresnelWidth);
    float fresnelRim = (1.0 - fresnelDepth) * (1.0 - fresnelDepth) * kGlassFresnel * rb1;

    float3 lit = refracted + kGlassHighlightColor * (rb2 + specular) + kGlassFresnelColor * fresnelRim;
    float4 composited = mix(float4(baseColor, 1.0), float4(lit, 1.0 + rb2), transition);
    float alpha = saturate(composited.a * (kGlassCutout ? transition : 1.0));

    float3 color = mix(srgbToLinear(kBackgroundSRGB), composited.rgb, alpha);
    return float4(linearToSrgb(saturate(color)), 1.0);
}
