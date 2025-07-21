// baesd on proper geometry no cheating
// inspired by other shader 

#define PI 3.14159265359
#define TAU 6.28318530718
#define FOV 2.5
#define SAMPLES 1
#define MAX_DIST 100.0

// -- rng stuff --
uvec4 randState;

void initRng(vec2 px, int frame) {
    randState = uvec4(px, uint(frame), uint(px.x + px.y));
}

uvec4 randStep(inout uvec4 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y*v.w; v.y += v.z*v.x; v.z += v.x*v.y; v.w += v.y*v.z;
    v ^= (v >> 16u);
    v.x += v.y*v.w; v.y += v.z*v.x; v.z += v.x*v.y; v.w += v.y*v.z;
    return v;
}

vec2 randomVec2() {
    return vec2(randStep(randState).xy) / float(0xffffffffu);
}

vec2 gaussian2D(float spread, vec2 mean) {
    vec2 r = randomVec2();
    float mag = sqrt(-2.0 * log(r.x)) * spread;
    return mean + mag * vec2(cos(TAU * r.y), sin(TAU * r.y));
}

// --- quaternion and matrix stuff ---
vec4 rotAxis(vec3 axis, float angle) {
    float h = angle * 0.5;
    return normalize(vec4(axis * sin(h), cos(h)));
}

vec4 qmul(vec4 a, vec4 b) {
    return vec4(
        a.w * b.xyz + b.w * a.xyz + cross(a.xyz, b.xyz),
        a.w * b.w - dot(a.xyz, b.xyz)
    );
}

mat3 qmat(vec4 q) {
    vec3 q2 = q.xyz * 2.0;
    float x = q.x, y = q.y, z = q.z, w = q.w;

    return mat3(
        1.0 - 2.0 * (y*y + z*z), 2.0 * (x*y - w*z), 2.0 * (x*z + w*y),
        2.0 * (x*y + w*z), 1.0 - 2.0 * (x*x + z*z), 2.0 * (y*z - w*x),
        2.0 * (x*z - w*y), 2.0 * (y*z + w*x), 1.0 - 2.0 * (x*x + y*y)
    );
}

mat3 getWormholeTransform(float t) {
    float offset = smoothstep(10.0, 20.0, abs(t)); // only activate outside the wormhole
    float angle = sin(iTime * 0.3) * 0.3 * offset;
    float wobble = sin(iTime * 0.5 + t * 0.1) * 0.1 * offset;

    vec3 axis = normalize(vec3(wobble, 2.0, wobble));
    return qmat(rotAxis(axis, angle));
}

// --- wormhol e ---
float R(float pos) {
    const float minR = 1.0;
    const float throatLen = 6.0;
    const float M = 0.5;
    float x = 2.0 * (abs(pos) - throatLen) / (PI * M);
    return (abs(pos) > throatLen)
        ? (minR + M * (x * atan(x) - 0.5 * log(1.0 + x * x)))
        : minR;
}

vec2 metric(vec2 q) { return vec2(1.0, pow(R(q.x), 2.0)); }
vec2 invMetric(vec2 q) { float r2 = R(q.x); return vec2(1.0, 1.0 / (r2 * r2)); }
vec2 toMom(vec2 q, vec2 qdot) { return metric(q) * qdot; }
vec2 fromMom(vec2 q, vec2 p) { return invMetric(q) * p; }

void takeStep(inout vec2 q, inout vec2 p) {
    vec2 qdot = fromMom(q, p);
    vec2 dq = vec2(0.0, 0.005);
    vec2 velSq = qdot * qdot;

    vec2 dHdq = vec2(
        dot(metric(q + dq.yx), velSq),
        dot(metric(q + dq.xy), velSq)
    ) - vec2(dot(metric(q), velSq));

    dHdq /= 0.005;

    float r = R(q.x);
    float stepSize = mix(0.3, 0.6, clamp(r / 10.0, 0.0, 1.0));
    p += dHdq * stepSize;
    q += 2.0 * qdot * stepSize;
}

void getInitial(vec3 pos, vec3 dir, out vec2 q, out vec2 qdot, out vec3 x1, out vec3 x2) {
    mat3 wh = getWormholeTransform(length(pos));
    x1 = normalize(wh * pos);
    vec3 x0 = normalize(cross(wh * dir, x1));
    x2 = normalize(cross(x1, x0));
    q = vec2(length(pos) - 25.0, 0.0);
    qdot = vec2(dot(x1, dir), dot(x2, dir) / R(q.x));
}

void toWorld(vec2 q, vec2 qdot, vec3 x1, vec3 x2, out vec3 pos, out vec3 dir) {
    vec2 ang = vec2(cos(q.y), sin(q.y));
    vec2 tang = vec2(-sin(q.y), cos(q.y));
    vec2 v = ang * qdot.x + tang * qdot.y * R(q.x);
    dir = v.x * x1 + v.y * x2;
    pos = abs(q.x) * (ang.x * x1 + ang.y * x2);
}

void traceRay(inout vec3 pos, inout vec3 dir, out float l) {
    vec3 x1, x2;
    vec2 q, qdot;
    getInitial(pos, dir, q, qdot, x1, x2);
    vec2 p = toMom(q, qdot);

    for (int i = 0; i < 512; ++i) {
        takeStep(q, p);
        if (abs(q.x) > MAX_DIST) break;
    }

    qdot = fromMom(q, p);
    toWorld(q, qdot, x1, x2, pos, dir);
    l = q.x;
}

// --- cam ---
vec2 dirToUV(vec3 d) {
    return vec2(
        0.5 + atan(d.z, d.x) / TAU,
        0.5 - asin(d.y) / PI
    );
}

vec3 encodeHDR(vec4 c) {
    float len = length(c.rgb);
    return len * normalize(c.rgb + 1e-4);
}

vec2 dragRot = vec2(0.0);

bool getCam(vec2 uv, out vec3 ro, out vec3 rd, float t) {
    float mouseSpeed = 2.0;
    vec2 m = iMouse.xy / iResolution.xy;
    vec2 clickStart = iMouse.zw / iResolution.xy;

    if (iMouse.z > 0.0) {
        dragRot = (m - clickStart) * mouseSpeed * PI;
    }

    vec4 yaw = rotAxis(vec3(0, 1, 0), dragRot.x);
    vec4 pitch = rotAxis(vec3(1, 0, 0), dragRot.y);
    vec4 rot = normalize(qmul(yaw, pitch));
    mat3 camRot = qmat(rot);

    vec3 camPos = normalize(vec3(0.0, 1.0, 0.0)) * (31. + t);
    ro = camPos;
    rd = normalize(camRot * vec3(FOV * uv, 1.0));
    return true;
}

// --- main pass ---
vec4 render(vec2 fragCoord, float t) {
    fragCoord += gaussian2D(0.5, vec2(0));
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;

    vec3 ro, rd;
    if (!getCam(uv, ro, rd, t)) return vec4(0);
    float dist;
    traceRay(ro, rd, dist);

    vec3 col = vec3(0.0);
    if (abs(dist) > 5.0) {
        col = (dist > 0.0) ? encodeHDR(texture(iChannel0, rd)) : encodeHDR(texture(iChannel1, rd));
    }

    return vec4(col, 1.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    initRng(fragCoord, iFrame);
    fragColor = vec4(0.0);

    float t = sin(iTime * 0.1) * 20.0;

    for (int i = 0; i < SAMPLES; ++i) {
        fragColor += render(fragCoord, t);
    }

    vec3 finalColor = fragColor.rgb / float(SAMPLES);
    finalColor = pow(finalColor, vec3(1.0 / 2.2));
    fragColor = vec4(finalColor, 1.0);
}
