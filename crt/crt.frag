#version 300 es
// LV-426 CRT mode: the whole desktop on a Nostromo green-phosphor tube.
// Curved glass, monochrome phosphor, thick scanlines, an aperture grille,
// bloom and a dark bezel. Scanlines roll and a brighter refresh band sweeps
// down the tube; using `time` makes Hyprland redraw every frame while CRT
// mode is on. Tuning knobs are the constants below.
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
uniform float time;
out vec4 fragColor;

const float CURVE      = 0.10;   // barrel distortion strength
const float SCAN_PX    = 6.0;    // scanline period in physical pixels
const float SCAN_DEPTH = 0.55;   // how dark the gaps between scanlines get
const float MONO       = 0.88;   // 0 = original colors, 1 = pure phosphor
const float BLOOM      = 0.55;
const float ROLL_SPEED = 18.0;   // scanline drift, physical pixels per second
const float BAND_SPEED = 0.12;   // refresh band sweeps per second (0 = off)
const float BAND_GLOW  = 0.18;   // refresh band brightness
const float FLICKER    = 0.035;  // constant fine brightness flutter (0 = off)
const float GLITCH     = 0.06;   // chance per quarter-second of a brief brownout
const float GLITCH_DIP = 0.22;   // how far the screen dims during a brownout
const vec3  PHOSPHOR   = vec3(0.42, 1.0, 0.62);

// Power transitions. POWER 1 = tube warming up (CRT mode engaging),
// POWER -1 = tube switching off (lv426-crt generates that copy at runtime).
// Hyprland starts `time` at an unknown point in [0, 1) seconds, so both
// transitions begin at time = 1.0; before that the tube is dark (power on)
// or still showing (power off).
#define POWER 1
const float T_START = 1.0;

// How much of the tube is lit: x = horizontal extent, y = vertical extent
// (1 = full), z = brightness boost, w = central beam line glow.
vec4 powerState(float t) {
    float a = t - T_START;
#if POWER == 1
    if (a < 0.0) return vec4(0.0, 0.0, 0.0, 0.0);
    float hs = smoothstep(0.0, 0.07, a);                     // line draws across
    float vs = 0.004 + 0.996 * smoothstep(0.07, 0.38, a);    // then opens vertically
    float boost = 1.0 + 2.2 * exp(-a * 3.2);                 // overexposed, settling
    float beam = (1.0 - smoothstep(0.05, 0.45, a)) * hs;
    return vec4(hs, vs, boost, beam);
#else
    if (a < 0.0) return vec4(1.0, 1.0, 1.0, 0.0);
    float vs = 1.0 - smoothstep(0.0, 0.12, a) * 0.996;       // collapses to a line
    float hs = 1.0 - smoothstep(0.12, 0.28, a) * 0.992;      // then to a dot
    float boost = 1.0 + 2.5 * smoothstep(0.0, 0.12, a);
    float beam = smoothstep(0.06, 0.14, a) * (1.0 - smoothstep(0.3, 0.9, a));
    return vec4(hs, vs, boost * (1.0 - smoothstep(0.28, 0.5, a)), beam);
#endif
}

vec2 warp(vec2 uv) {
    vec2 c = uv * 2.0 - 1.0;
    c *= 1.0 + CURVE * dot(c.yx, c.yx);
    return c * 0.5 + 0.5;
}

float hash(float n) {
    return fract(sin(n * 12.9898) * 43758.5453);
}

vec3 sampleTex(vec2 uv) {
    return texture(tex, clamp(uv, 0.0, 1.0)).rgb;
}

void main() {
    vec2 uv = warp(v_texcoord);

    // Power transition: squeeze the picture into the lit part of the tube.
    vec4 pw = powerState(time);
    vec2 tube = uv - 0.5;
    float lit = step(abs(tube.x), pw.x * 0.5) * (1.0 - smoothstep(pw.y * 0.5, pw.y * 0.5 + 0.004, abs(tube.y)));
    float beam = pw.w * exp(-tube.y * tube.y * 40000.0) * exp(-tube.x * tube.x / max(pw.x * pw.x * 0.08, 1e-5));
    uv = vec2(tube.x / max(pw.x, 1e-3), tube.y / max(pw.y, 1e-3)) + 0.5;

    // Brownout: now and then the tube sags for a moment, dimming and
    // smearing sideways a little before it recovers.
    float slot = floor(time * 4.0);
    float glitch = step(1.0 - GLITCH, hash(slot + 17.0)) * (1.0 - fract(time * 4.0));
    uv.x += glitch * 0.0025 * sin(uv.y * 240.0 + time * 90.0);

    // Outside the curved glass: bezel black, with rounded corners.
    vec2 edge = abs(tube) * 2.0;   // the glass itself, not the squeezed picture
    vec2 corner = max(edge - 0.94, 0.0) / 0.06;
    float inside = step(edge.x, 1.0) * step(edge.y, 1.0) * (1.0 - smoothstep(0.85, 1.0, length(corner)));
    if (inside <= 0.0 || lit <= 0.0) { fragColor = vec4(PHOSPHOR * beam * inside, 1.0); return; }

    vec2 px = vec2(1.0) / vec2(textureSize(tex, 0));

    // Color fringe that grows toward the edges.
    vec2 fringe = (uv - 0.5) * px * 6.0;
    vec3 col = vec3(sampleTex(uv + fringe).r, sampleTex(uv).g, sampleTex(uv - fringe).b);

    // Bloom: wide cross + diagonal blur, so bright text glows into its surroundings.
    vec3 glow = vec3(0.0);
    for (int i = 1; i <= 3; i++) {
        float r = float(i) * 3.0;
        glow += sampleTex(uv + vec2(px.x * r, 0.0)) + sampleTex(uv - vec2(px.x * r, 0.0))
              + sampleTex(uv + vec2(0.0, px.y * r)) + sampleTex(uv - vec2(0.0, px.y * r))
              + sampleTex(uv + px * r * 0.7) + sampleTex(uv - px * r * 0.7);
    }
    glow /= 18.0;

    // Monochrome phosphor.
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    float glowLuma = dot(glow, vec3(0.299, 0.587, 0.114));
    vec3 mono = PHOSPHOR * pow(luma, 0.85) * 1.15;
    col = mix(col, mono, MONO);
    col += PHOSPHOR * glowLuma * BLOOM;

    // Scanlines, following the curved glass.
    float line = fract((uv.y * float(textureSize(tex, 0).y) - time * ROLL_SPEED) / SCAN_PX);
    float scan = mix(1.0 - SCAN_DEPTH, 1.0, pow(sin(line * 3.14159), 1.5));
    col *= scan;

    // Refresh band: a soft bright bar rolling down the tube, top to bottom.
    float band = fract(time * BAND_SPEED);
    float dist = uv.y - band;             // uv.y is 0 at the top
    dist = dist - floor(dist + 0.5);      // wrap around
    col *= 1.0 + BAND_GLOW * exp(-dist * dist * 900.0) + 0.05 * exp(-dist * dist * 60.0);

    // Flicker: per-frame flutter plus the brownout dip.
    float flicker = 1.0 - FLICKER * hash(floor(time * 30.0));
    flicker *= 1.0 - GLITCH_DIP * glitch * (0.6 + 0.4 * sin(time * 70.0));
    col *= flicker;

    // Aperture grille: faint vertical triads.
    float triad = mod(gl_FragCoord.x, 3.0);
    col *= 0.9 + 0.1 * step(1.0, triad);

    // Tube vignette and a faint phosphor floor so blacks look lit.
    vec2 d = tube;
    col *= 1.0 - dot(d, d) * 1.4;
    col += PHOSPHOR * 0.012;

    col = col * lit * pw.z + mix(PHOSPHOR, vec3(1.0), 0.6) * beam;
    fragColor = vec4(col * inside, 1.0);
}
