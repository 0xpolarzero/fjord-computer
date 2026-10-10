// Amont Labs signature: a mountain massif of points with a braided Fonte river, in real time.
//
//   import { mount } from './signature.js';
//   const sig = await mount(el, { theme: 'dark' | 'light', transparent: true });
//   sig.exportPNG(4800, 3200, 'dark', { download: true });   // or returns a Blob
//
// All geometry is baked offline (scripts/make_signature_data.py): no sampling at run time, one draw call for the
// terrain, one for the river, one sprite for the source. Pixel sizes are expressed in "design pixels" of the
// 4800 x 3200 master frame and multiplied by the current frame scale, so a still looks the same at any size.
import * as THREE from 'three';

const DATA = new URL('/signature/', location.origin);
const FONTE = [0x0F / 255, 0x9A / 255, 0xC3 / 255];
const hex = (h) => [(h >> 16 & 255) / 255, (h >> 8 & 255) / 255, (h & 255) / 255];

const THEMES = {
  dark:  { bg: '#101418', lo: hex(0xA3AAB0), hi: hex(0xE6E9E4), r: [0.78, 0.28, 0.42], aK: [0.22, 0.78], dim: 0.35, thin: 0 },
  light: { bg: '#F7F8F5', lo: hex(0x5C636A), hi: hex(0x101418), r: [0.70, 0.24, 0.26], aK: [0.30, 0.62], dim: 0.20, thin: 0.22 },
};

const IMG_THEMES = {
  dark:  { r: [0.92, 0.06, 0.32], aK: [0.62, 0.70], dim: 0.0, thin: 0 },
  light: { r: [0.92, 0.08, 0.30], aK: [0.50, 0.62], dim: 0.0, thin: 0.12 },
};

// ------------------------------------------------------------------ shaders
const VERT_TERRAIN = /* glsl */`
attribute vec2 aAttr;                 // tone, seed
uniform vec3 uBox;
uniform float uPx, uIntro, uMinD, uThin, uSizeK;
uniform vec3 uRad;                    // radius = x + y (1 - depth) + z tone  [design px]
uniform vec2 uAlphaK;
uniform vec2 uDepth;                  // near, far for the depth fade
uniform float uDim;
uniform vec3 uLo, uHi;
uniform float uLight;
uniform vec2 uJ;                      // journey: alpha factor, keep probability
uniform float uBotFade;               // hero: soft fade toward the bottom edge (screen space)
varying vec3 vCol;
varying float vA;
varying float vD;
float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }
void main() {
  float tone = aAttr.x, seed = aAttr.y;
  vec3 p = position * uBox;
  // intro: ridges first (bright points settle early), noise offset along a rising direction
  float delay = (1.0 - tone) * 0.55 + seed * 0.22;
  float q = clamp((uIntro - delay) / 0.62, 0.0, 1.0);
  float e = 1.0 - pow(1.0 - q, 3.0);
  vec3 off = vec3(hash(seed * 91.7) - 0.5, 0.35 + hash(seed * 17.3), hash(seed * 53.1) - 0.5) * 900.0;
  p += (1.0 - e) * off;
  vec4 mv = modelViewMatrix * vec4(p, 1.0);
  float dn = clamp((-mv.z - uDepth.x) / (uDepth.y - uDepth.x), 0.0, 1.0);
  float r = (uRad.x + uRad.y * (1.0 - dn) + uRad.z * tone) * uSizeK;
  float a = clamp(uAlphaK.x + uAlphaK.y * pow(tone, 0.9), 0.0, 1.0) * (0.75 + 0.25 * hash(seed * 7.7)) * (1.0 - uDim * dn);
  float d = 2.0 * r * uPx;
  if (d < uMinD) { a *= (d * d) / (uMinD * uMinD); d = uMinD; }
  // light theme reads as a scan: the faintest points are thinned
  if (tone < 0.30 && hash(seed * 3.3) < uThin * 3.0) a *= 1.0 - uLight;
  a *= q * uJ.x;
  if (hash(seed * 5.1) > uJ.y) a = 0.0;
  vCol = mix(uLo, uHi, clamp(mix(tone * 1.15 - 0.05, step(0.30, tone), uLight), 0.0, 1.0));
  vec4 gp = projectionMatrix * mv;
  vA = a * (1.0 - uBotFade * smoothstep(0.72, 1.0, 0.5 - 0.5 * gp.y / gp.w)); vD = d;
  gl_Position = gp;
  gl_PointSize = d + 2.0;
}`;

const FRAG_DISC = /* glsl */`
varying vec3 vCol;
varying float vA;
varying float vD;
void main() {
  vec2 c = (gl_PointCoord * 2.0 - 1.0) * (vD * 0.5 + 1.0);   // pixels from the centre
  float r = length(c);
  float w = max(fwidth(r), 1e-4);
  float cov = 1.0 - smoothstep(vD * 0.5 - w * 0.5, vD * 0.5 + w * 0.5, r);
  float a = vA * cov;
  gl_FragColor = vec4(vCol * a, a);                           // premultiplied
}`;

const VERT_RIVER = /* glsl */`
attribute vec4 aP;                    // phase, channel, lateral gaussian, seed
uniform sampler2D uRiver;
uniform float uNS, uTime, uSpeed, uPx, uIntro, uMinD, uPulse, uLight, uSizeK;
varying vec3 vCol;
varying float vA;
varying float vD;
vec4 tex(float row, float f) {
  float x = clamp(f, 0.0, 1.0) * (uNS - 1.0);
  float i0 = floor(x);
  vec4 a = texelFetch(uRiver, ivec2(int(i0), int(row)), 0);
  vec4 b = texelFetch(uRiver, ivec2(int(min(i0 + 1.0, uNS - 1.0)), int(row)), 0);
  return mix(a, b, x - i0);
}
void main() {
  float ch = aP.y, seed = aP.w;
  float jit = 0.9 + 0.2 * fract(seed * 91.3);
  float u = fract(aP.x + uTime * uSpeed * jit);
  vec4 c0 = tex(ch * 2.0, u);
  vec4 st = tex(ch * 2.0 + 1.0, u);
  vec4 ca = tex(ch * 2.0, u - 0.004), cb = tex(ch * 2.0, u + 0.004);
  vec3 t = normalize(cb.xyz - ca.xyz + vec3(1e-4));
  vec3 n = normalize(vec3(-t.z, 0.0, t.x));
  vec3 p = c0.xyz + n * aP.z * c0.w;
  // reveal downstream from the source during the intro (the river comes last)
  float reveal = smoothstep(0.0, 1.0, (uIntro - 1.05) / 1.1);
  float shown = step(u, reveal * 1.05);
  float on = step(seed, st.y * st.x) * shown;
  float rnd = fract(seed * 13.7);
  float wave = 0.5 + 0.5 * sin(6.2831853 * (u * 4.0 - uTime * 0.12));
  float pulse = 1.0 + uPulse * (0.55 * exp(-u * 9.0) * (0.5 + 0.5 * sin(uTime * 1.7)) + 0.10 * wave);
  float r = (1.1 + 0.55 * (1.0 - u) + 0.35 * rnd) * pulse * uSizeK;
  float a = mix(0.80 + 0.20 * rnd, 0.78 + 0.22 * sqrt(1.0 - u), uLight) * on * (1.0 - smoothstep(0.88, 1.0, u));
  float d = 2.0 * r * uPx;
  if (d < uMinD) { a *= (d * d) / (uMinD * uMinD); d = uMinD; }
  vCol = vec3(${FONTE.map(v => v.toFixed(5)).join(',')});
  vA = a; vD = d;
  vec4 mv = modelViewMatrix * vec4(p, 1.0);
  gl_Position = projectionMatrix * mv;
  gl_PointSize = d + 2.0;
}`;

// image source: river particles keep the reference position and flow a short stretch downstream along the centreline
const VERT_RIVER_IMG = /* glsl */`
attribute vec4 aP;                    // s0, seed, size, 0
uniform sampler2D uRiver;
uniform float uNS, uTime, uSpeed, uPx, uIntro, uMinD, uPulse, uLight, uSizeK, uFlow, uFlowT, uConv, uBotFade;
varying vec3 vCol;
varying float vA;
varying float vD;
vec3 cl(float f) {
  float x = clamp(f, 0.0, 1.0) * (uNS - 1.0);
  float i0 = floor(x);
  vec3 a = texelFetch(uRiver, ivec2(int(i0), 0), 0).xyz;
  vec3 b = texelFetch(uRiver, ivec2(int(min(i0 + 1.0, uNS - 1.0)), 0), 0).xyz;
  return mix(a, b, x - i0);
}
void main() {
  float s0 = aP.x, seed = aP.y;
  float ph = fract(uFlowT * 6.0 * (0.85 + 0.3 * fract(seed * 91.3)) + seed * 7.13);
  float win = 0.022 * uFlow;
  float u = clamp(s0 + win * ph, 0.0, 1.0);
  vec3 p = cl(u) + (position - cl(s0)) * (1.0 - 0.8 * uConv);   // uConv: the river narrows to a thread
  float env = uFlow > 0.0 ? sin(3.14159265 * ph) : 1.0;
  float reveal = smoothstep(0.0, 1.0, (uIntro - 1.05) / 1.1);
  float shown = step(s0, reveal * 1.05);
  float wave = 0.5 + 0.5 * sin(6.2831853 * (s0 * 4.0 - uTime * 0.12));
  float pulse = 1.0 + uPulse * (0.55 * exp(-s0 * 9.0) * (0.5 + 0.5 * sin(uTime * 1.7)) + 0.10 * wave);
  float r = (1.12 + 0.40 * aP.z) * pulse * uSizeK;
  float a = (0.80 + 0.20 * aP.z) * (0.85 + 0.15 * env) * shown * (1.0 - smoothstep(0.93, 1.0, s0)) * (1.0 - uConv * smoothstep(0.04, 0.2, s0));
  float d = 2.0 * r * uPx;
  if (d < uMinD) { a *= (d * d) / (uMinD * uMinD); d = uMinD; }
  vCol = vec3(${FONTE.map(v => v.toFixed(5)).join(',')});
  vec4 gp = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
  vA = a * (1.0 - uBotFade * smoothstep(0.72, 1.0, 0.5 - 0.5 * gp.y / gp.w)); vD = d;
  gl_Position = gp;
  gl_PointSize = d + 2.0;
}`;

const VERT_SOURCE = /* glsl */`
uniform float uPx, uTime, uIntro, uPulse, uGs;
varying float vK;
varying float vS;
void main() {
  float k = smoothstep(0.9, 1.25, uIntro);
  float pulse = 1.0 + uPulse * 0.14 * sin(uTime * 1.7);
  vK = k * pulse;
  float R = 26.0 * uGs * uPx;                                       // glow reach in design px -> device px
  vS = R;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  gl_PointSize = 2.0 * R + 2.0;
}`;
const FRAG_SOURCE = /* glsl */`
uniform float uPx, uLight, uGs;
varying float vK;
varying float vS;
void main() {
  vec2 c = (gl_PointCoord * 2.0 - 1.0) * (vS + 1.0);
  float r = length(c) / uPx / uGs;                                  // design px from the centre
  float w = max(fwidth(r), 1e-4);
  float core = 1.0 - smoothstep(5.6 - w * 0.5, 5.6 + w * 0.5, r);
  // soft halo: one smooth falloff from the core edge, no step (a pale ring on paper otherwise)
  float halo = exp(-pow(max(r - mix(5.0, 4.0, uLight), 0.0) / mix(9.0, 6.0, uLight), mix(1.2, 1.5, uLight))) * mix(0.95, 0.42, uLight) * (1.0 - smoothstep(14.0, 26.0, r));
  vec3 fonte = vec3(${FONTE.map(v => v.toFixed(5)).join(',')});
  vec3 hot = mix(fonte, vec3(0.62, 0.92, 1.0), 0.30 * (1.0 - uLight));
  float a = clamp(core + halo * (1.0 - core) * vK, 0.0, 1.0) * clamp(vK * 1.4, 0.0, 1.0);
  vec3 col = mix(fonte, hot, core);
  gl_FragColor = vec4(col * a, a);
}`;

// ------------------------------------------------------------------ helpers
function premultMaterial(extra) {
  return new THREE.ShaderMaterial({
    transparent: true, depthTest: false, depthWrite: false,
    blending: THREE.CustomBlending, blendEquation: THREE.AddEquation,
    blendSrc: THREE.OneFactor, blendDst: THREE.OneMinusSrcAlphaFactor,
    blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneMinusSrcAlphaFactor,
    ...extra,
  });
}
async function getBuf(name) {
  const r = await fetch(new URL(name, DATA));
  if (!r.ok) throw new Error(`signature: ${name} ${r.status}`);
  return r.arrayBuffer();
}
const smooth = (t) => t * t * (3 - 2 * t);

export function webglAvailable() {
  try { const c = document.createElement('canvas'); return !!c.getContext('webgl2'); } catch { return false; }
}

// ------------------------------------------------------------------ mount
export async function mount(el, opts = {}) {
  const o = {
    theme: 'dark', transparent: true, lod: 'auto', dprCap: 2, fit: 'cover', anchor: [0.5, 0.5],
    source: 'image', motion: 'auto', parallax: true, dev: false, poster: null, speed: 0.024, intro: true, journey: false, ...opts,
  };
  const reduced = o.motion === 'static' || (o.motion === 'auto' && matchMedia('(prefers-reduced-motion: reduce)').matches);
  if (!webglAvailable()) {
    if (o.poster) { const im = new Image(); im.src = o.poster; im.alt = ''; im.style.cssText = 'width:100%;height:100%;object-fit:cover;display:block'; el.append(im); }
    return { fallback: true, destroy() { el.replaceChildren(); } };
  }
  const img = o.source === 'image', pre = '';
  const meta = await (await fetch(new URL(pre + 'meta.json', DATA))).json();
  const coarse = matchMedia('(pointer: coarse)').matches || Math.min(innerWidth, innerHeight) < 640;
  const lod = o.lod === 'auto' ? (coarse ? 'lo' : 'hi') : o.lod;
  const [tb, rb] = await Promise.all([getBuf(`${pre}terrain-${lod}.bin`), getBuf(`${pre}river.bin`)]);

  // ---- renderer
  const canvas = document.createElement('canvas');
  canvas.style.cssText = 'display:block;width:100%;height:100%';
  el.append(canvas);
  const renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: false, premultipliedAlpha: true, powerPreference: 'high-performance', preserveDrawingBuffer: false });
  renderer.setClearColor(0x000000, 0);
  renderer.autoClear = true;
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera();
  camera.near = 1500; camera.far = 90000;
  const cam = meta.camera;

  // ---- terrain
  const n = tb.byteLength / 8;
  const i16 = new Int16Array(tb), u8 = new Uint8Array(tb);        // 8 bytes per point: int16 x3, uint8 x2 (little-endian)
  const pos = new Int16Array(n * 3), attr = new Uint8Array(n * 2);
  for (let i = 0; i < n; i++) {
    pos[i * 3] = i16[i * 4]; pos[i * 3 + 1] = i16[i * 4 + 1]; pos[i * 3 + 2] = i16[i * 4 + 2];
    attr[i * 2] = u8[i * 8 + 6]; attr[i * 2 + 1] = u8[i * 8 + 7];
  }
  const tgeo = new THREE.BufferGeometry();
  tgeo.setAttribute('position', new THREE.BufferAttribute(pos, 3, true));
  tgeo.setAttribute('aAttr', new THREE.BufferAttribute(attr, 2, true));
  const U = {
    uPx: { value: 1 }, uTime: { value: 0 }, uIntro: { value: 9 }, uMinD: { value: 1.0 }, uSizeK: { value: 1 },
    uBotFade: { value: 0 }, uConv: { value: 0 }, uLight: { value: 0 }, uPulse: { value: reduced ? 0 : 1 }, uFlow: { value: reduced ? 0 : 1 },
  };
  const tmat = premultMaterial({
    vertexShader: VERT_TERRAIN, fragmentShader: FRAG_DISC,
    uniforms: {
      ...U, uBox: { value: new THREE.Vector3(...meta.box) },
      uRad: { value: new THREE.Vector3() }, uAlphaK: { value: new THREE.Vector2() }, uDepth: { value: img ? new THREE.Vector2(meta.depth[0], meta.depth[1]) : new THREE.Vector2(cam.dist * 0.72, cam.dist * 1.55) },
      uJ: { value: new THREE.Vector2(1, 1) }, uDim: { value: 0.3 }, uLo: { value: new THREE.Vector3() }, uHi: { value: new THREE.Vector3() }, uThin: { value: 0 },
    },
  });
  const terrain = new THREE.Points(tgeo, tmat);
  terrain.frustumCulled = false;
  scene.add(terrain);

  // ---- river
  const R = meta.river;
  const nRows = R.channels * 2;
  let rtex, rgeo, rmat;
  if (img) {
    const clF = new Float32Array(rb, 0, R.samples * 4);
    const part = new Float32Array(rb, R.samples * 16, R.particles * 6);
    rtex = new THREE.DataTexture(clF, R.samples, 1, THREE.RGBAFormat, THREE.FloatType);
    const posA = new Float32Array(R.particles * 3), aPA = new Float32Array(R.particles * 4);
    for (let i = 0; i < R.particles; i++) {
      posA.set(part.subarray(i * 6, i * 6 + 3), i * 3);
      aPA[i * 4] = part[i * 6 + 3]; aPA[i * 4 + 1] = part[i * 6 + 4]; aPA[i * 4 + 2] = part[i * 6 + 5];
    }
    rgeo = new THREE.BufferGeometry();
    rgeo.setAttribute('position', new THREE.BufferAttribute(posA, 3));
    rgeo.setAttribute('aP', new THREE.BufferAttribute(aPA, 4));
  } else {
    const rowsF = new Float32Array(rb, 0, R.samples * nRows * 4);
    const partF = new Float32Array(rb, R.samples * nRows * 16, R.particles * 4);
    rtex = new THREE.DataTexture(rowsF, R.samples, nRows, THREE.RGBAFormat, THREE.FloatType);
    rgeo = new THREE.BufferGeometry();
    rgeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(R.particles * 3), 3));
    rgeo.setAttribute('aP', new THREE.BufferAttribute(partF, 4));
  }
  const centre = img ? new Float32Array(rb, 0, R.samples * 4) : null;   // river centreline, s = 0 at the source
  rtex.minFilter = rtex.magFilter = THREE.NearestFilter; rtex.needsUpdate = true;
  rmat = premultMaterial({
    vertexShader: img ? VERT_RIVER_IMG : VERT_RIVER, fragmentShader: FRAG_DISC,
    uniforms: { ...U, uRiver: { value: rtex }, uNS: { value: R.samples }, uSpeed: { value: o.speed }, uFlowT: { value: 0 } },
  });
  const river = new THREE.Points(rgeo, rmat);
  river.frustumCulled = false;
  scene.add(river);

  // ---- source
  const sgeo = new THREE.BufferGeometry();
  sgeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(img ? meta.src : meta.source), 3));
  const smat = premultMaterial({ vertexShader: VERT_SOURCE, fragmentShader: FRAG_SOURCE, uniforms: { ...U, uGs: { value: img ? 1.5 : 1 } } });
  const source = new THREE.Points(sgeo, smat);
  source.frustumCulled = false;
  scene.add(source);

  // ---- state
  const S = {
    theme: o.theme, drawN: n, size: 1, speed: o.speed, fit: o.fit, anchor: o.anchor, camMode: 'hero',
    sy: 0, vh: 1, max: 1, jp: 0, jh: 0, lastY: 0, jvs: 0, jvv: 0, tgt: [0.5, 0.6], flowT: 0, projBase: null, journey: o.journey,
    t: 0, intro0: null, px: 0, py: 0, tpx: 0, tpy: 0, running: true, visible: true, controls: null,
  };
  const frame = { cw: 1, ch: 1, k: 1, a: 0, b: 0, kDev: 1 };

  // theme: every uniform glides to its target (0.5 s, same timing as the page's CSS colour fade)
  const TW = { from: null, to: null, t0: 0, dur: 500 };
  const themeVec = (name) => {
    const th = { ...THEMES[name], ...(img ? IMG_THEMES[name] : {}) };
    return { th, v: [...th.r, ...th.aK, th.dim, ...th.lo, ...th.hi, th.thin, name === 'light' ? 1 : 0] };
  };
  const curVec = () => {
    const m = tmat.uniforms;
    return [m.uRad.value.x, m.uRad.value.y, m.uRad.value.z, m.uAlphaK.value.x, m.uAlphaK.value.y, m.uDim.value,
      m.uLo.value.x, m.uLo.value.y, m.uLo.value.z, m.uHi.value.x, m.uHi.value.y, m.uHi.value.z, m.uThin.value, U.uLight.value];
  };
  function setVec(v) {
    const m = tmat.uniforms;
    m.uRad.value.set(v[0], v[1], v[2]); m.uAlphaK.value.set(v[3], v[4]); m.uDim.value = v[5];
    m.uLo.value.set(v[6], v[7], v[8]); m.uHi.value.set(v[9], v[10], v[11]); m.uThin.value = v[12]; U.uLight.value = v[13];
  }
  function stepTheme(now) {
    if (!TW.to) return false;
    const k = Math.min(1, (now - TW.t0) / TW.dur), e = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
    setVec(TW.from.map((a, i) => a + (TW.to[i] - a) * e));
    if (k >= 1) TW.to = null;
    return true;
  }
  function applyTheme(name, animate = false) {
    const { th, v } = themeVec(name); S.theme = name;
    if (animate && !reduced && S.started) { TW.from = curVec(); TW.to = v; TW.t0 = performance.now(); }
    else { TW.to = null; setVec(v); }
    if (!o.transparent) renderer.setClearColor(th.bg, 1); else renderer.setClearColor(0x000000, 0);
    el.dispatchEvent(new CustomEvent('signature:theme', { detail: name }));
  }

  // projection of the 3:2 master frame into a w x h view (px). Optional sub-window (tile) of the view.
  function setProjection(w, h, fit, anchor, tile) {
    const k = fit === 'contain' ? Math.min(w / cam.W0, h / cam.H0) : Math.max(w / cam.W0, h / cam.H0);
    const a = (w - k * cam.W0) * anchor[0], b = (h - k * cam.H0) * anchor[1];
    const f = cam.fk * cam.W0;
    const t = tile || { x: 0, y: 0, w, h };
    const aa = a - t.x, bb = b - t.y;
    const cx = 2 / t.w * (aa + k * cam.tx * cam.W0) - 1;
    const cy = 1 - 2 / t.h * (bb + k * cam.ty * cam.H0);
    const A = 2 * k * f / t.w, B = 2 * k * f / t.h;
    const nr = camera.near, fr = camera.far;
    camera.projectionMatrix.set(
      A, 0, -cx, 0,
      0, B, -cy, 0,
      0, 0, -(fr + nr) / (fr - nr), -2 * fr * nr / (fr - nr),
      0, 0, -1, 0);
    camera.projectionMatrixInverse.copy(camera.projectionMatrix).invert();
    if (!tile) S.projBase = camera.projectionMatrix.elements.slice();
    return k;
  }
  camera.updateProjectionMatrix = () => {};                      // projection is ours; keep OrbitControls from resetting it

  const T0 = new THREE.Vector3();
  function pose(dAz = 0, dPitch = 0, T = T0) {
    const az = (cam.az + dAz) * Math.PI / 180, pi = (cam.pitch + dPitch) * Math.PI / 180;
    const fwd = new THREE.Vector3(Math.sin(az) * Math.cos(pi), -Math.sin(pi), -Math.cos(az) * Math.cos(pi));
    camera.position.copy(fwd).multiplyScalar(-cam.dist).add(T);
    camera.up.set(0, 1, 0);
    camera.lookAt(camera.position.x + fwd.x, camera.position.y + fwd.y, camera.position.z + fwd.z);
    camera.updateMatrixWorld(true);
    return fwd;
  }

  // ---- journey: scrolling the page travels up the valley toward the source (see README: scroll choreography)
  const J = {
    dolly: 0.34,                       // fraction of the way toward the river point reached at the bottom of the page
    path: [0.62, 0.0],                 // river parameter s (1 = downstream, 0 = source) at the top and bottom of the page
    dimText: 0.30, dimEnd: 0.07,       // terrain alpha while text is on screen / at the end of the page
    keepText: 0.62, keepEnd: 0.14,     // fraction of terrain points kept (same two stops)
    light: { dimText: 0.13, keepText: 0.4 },   // the light theme needs more dimming than the dark one
    smooth: 0.05,                      // smoothing time (s) of the scroll velocity that drives the river speed
  };
  const sm = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
  const lerp = (a, b, t) => a + (b - a) * t;
  function damp(x, v, target, smooth, dt) {   // critically damped spring (Game Programming Gems 4)
    const w = 2 / smooth, e = 1 / (1 + w * dt + 0.48 * w * w * dt * dt + 0.235 * w * w * w * dt * dt * dt);
    const d = x - target, t = (v + w * d) * dt;
    return [target + (d + t) * e, (v - w * t) * e];
  }
  function riverPoint(sv, out) {
    const x = Math.min(1, Math.max(0, sv)) * (R.samples - 1), i = Math.floor(x), f = x - i, j = Math.min(i + 1, R.samples - 1);
    return out.set(lerp(centre[i * 4], centre[j * 4], f), lerp(centre[i * 4 + 1], centre[j * 4 + 1], f), lerp(centre[i * 4 + 2], centre[j * 4 + 2], f));
  }
  const Pv = new THREE.Vector3(), Bv = new THREE.Vector3(), Tv = new THREE.Vector3(), Sv = new THREE.Vector3();
  const srcWorld = new THREE.Vector3(...(img ? meta.src : meta.source));

  function resize() {
    const dpr = Math.min(devicePixelRatio || 1, o.dprCap);
    const cw = Math.max(1, el.clientWidth), ch = Math.max(1, el.clientHeight);
    renderer.setPixelRatio(dpr);
    renderer.setSize(cw, ch, false);
    const fit = S.fit === 'auto' ? (cw / ch < 1 ? 'contain' : 'cover') : S.fit;
    const k = setProjection(cw, ch, fit, S.anchor);
    U.uPx.value = k * dpr; frame.kDev = k * dpr; frame.cw = cw; frame.ch = ch;
    U.uMinD.value = 1.05;
    // sub-pixel points on small screens: keep them visible rather than blurred away
  }

  if (lod === 'lo') U.uSizeK.value = 1.18;
  applyTheme(o.theme);
  pose(); resize();
  const ro = new ResizeObserver(resize); ro.observe(el);

  // ---- motion
  const pointer = (e) => {
    const r = el.getBoundingClientRect();
    S.tpx = ((e.clientX - r.left) / r.width) * 2 - 1; S.tpy = ((e.clientY - r.top) / r.height) * 2 - 1;
  };
  if (!reduced && o.parallax) addEventListener('pointermove', pointer, { passive: true });
  const io = new IntersectionObserver((es) => { S.visible = es[0].isIntersecting; if (S.visible) kick(); });
  io.observe(el);
  const onVis = () => { if (!document.hidden) kick(); };
  document.addEventListener('visibilitychange', onVis);

  let raf = 0, last = 0;
  function kick() { if (!raf && S.running) { last = performance.now(); raf = requestAnimationFrame(tick); } }
  function tick(now) {
    raf = 0;
    if (!S.running || !S.visible || document.hidden) return;
    if (S.pre) S.pre(now);                          // e.g. lenis.raf(now): scroll is advanced in the same frame we render
    const dt = Math.min((now - last) / 1000, 0.1); last = now;
    if (S.intro0 === null) S.intro0 = now;
    S.t += dt;
    U.uTime.value = S.t;
    stepTheme(now); S.started = true;
    U.uIntro.value = reduced || !o.intro ? 9 : Math.min((now - S.intro0) / 1000 / 2.2 * 1.9 + 0.0, 9);
    let T = T0, dollied = 0;
    if (S.journey) {
      // coupled directly to the page: read the scroll position in this very frame, no spring on camera, dim or pan
      const y = Math.max(0, scrollY);
      S.jp = S.max > 0 ? Math.min(1, y / S.max) : 0; S.jh = y / S.vh;
      // only the secondary effect (river speed) gets a very short smoothing of the scroll velocity
      const vel = (y - S.lastY) / Math.max(dt, 1e-3) / S.vh; S.lastY = y;
      [S.jvs, S.jvv] = damp(S.jvs, S.jvv, vel, J.smooth, dt);
      const p = S.jp, h = S.jh, text = sm(0.04, 0.62, h), foot = sm(0.74, 1.0, p), conv = sm(0.62, 1.0, p);
      // dolly toward a point that travels up the river
      riverPoint(lerp(J.path[0], J.path[1], sm(0, 1, p)), Pv);
      Bv.set(0, 0, cam.dist);
      Tv.copy(Pv).sub(Bv).multiplyScalar(J.dolly * sm(0, 1, p));
      T = Tv; dollied = Tv.z;
      const L = U.uLight.value, dT = lerp(J.dimText, J.light.dimText, L), kT = lerp(J.keepText, J.light.keepText, L);
      tmat.uniforms.uJ.value.set(lerp(lerp(1, dT, text), J.dimEnd, foot), lerp(lerp(1, kT, text), J.keepEnd, foot));
      U.uBotFade.value = 1 - text; U.uConv.value = conv;
      smat.uniforms.uGs.value = 1.5 * (1 + 0.9 * sm(0.5, 1.0, p));
      U.uPulse.value = reduced ? 0 : 1 - 0.45 * foot;
      tmat.uniforms.uDepth.value.set(meta.depth[0] - dollied, meta.depth[1] - dollied);
    }
    // river flow clock: speed follows scroll velocity a little
    const boost = S.journey ? Math.min(2.2, Math.abs(S.jvs) * 0.6) : 0;
    S.flowT += dt * S.speed * (1 + boost);
    rmat.uniforms.uFlowT.value = S.flowT;
    if (S.camMode === 'hero') {
      S.px += (S.tpx - S.px) * Math.min(1, dt * 2.2); S.py += (S.tpy - S.py) * Math.min(1, dt * 2.2);
      const drift = reduced ? 0 : 1;
      const aA = cam.drift[0] * 0.41, aP = cam.drift[1] * 0.3;
      const dAz = drift * aA * Math.sin(S.t * 0.11) + S.px * aA, dP = drift * aP * Math.sin(S.t * 0.07 + 1.3) - S.py * aP * 1.1;
      pose(dAz, dP, T);
    }
    if (S.journey && S.projBase) {
      // pan the whole image so the source lands on its target at the end of the page
      const e = camera.projectionMatrix.elements;
      e[8] = S.projBase[8]; e[9] = S.projBase[9];
      const w = sm(0.5, 1.0, S.jp);
      if (w > 0) {
        Sv.copy(srcWorld).project(camera);
        e[8] -= (S.tgt[0] * 2 - 1 - Sv.x) * w; e[9] -= (1 - S.tgt[1] * 2 - Sv.y) * w;
      }
    }
    renderer.render(scene, camera);
    if (!reduced || U.uIntro.value < 9) raf = requestAnimationFrame(tick);
    else if (reduced) { /* static: one frame is enough */ }
  }
  if (reduced) { S.t = 18; U.uTime.value = S.t; U.uIntro.value = 9; renderer.render(scene, camera); }
  else kick();

  // ---- export
  async function exportPNG(width, height, theme = S.theme, eo = {}) {
    const x = { tile: 2048, margin: 40, fit: S.fit === 'auto' ? 'cover' : S.fit, anchor: S.anchor, time: 18, download: false, name: null, background: false, ...eo };
    const prev = { theme: S.theme, dpr: renderer.getPixelRatio(), size: renderer.getSize(new THREE.Vector2()), u: { ...Object.fromEntries(Object.entries(U).map(([k, v]) => [k, v.value])) }, cc: renderer.getClearColor(new THREE.Color()).getHex(), ca: renderer.getClearAlpha() };
    const wasRunning = S.running; S.running = false; cancelAnimationFrame(raf); raf = 0;
    const transparentPrev = o.transparent; o.transparent = !x.background;
    applyTheme(theme);
    U.uTime.value = x.time; U.uIntro.value = 9; U.uBotFade.value = 0; U.uConv.value = 0; tmat.uniforms.uJ.value.set(1, 1); smat.uniforms.uGs.value = img ? 1.5 : 1; U.uMinD.value = 0.0; if (img) U.uFlow.value = 0;
    pose(0, 0);
    renderer.setPixelRatio(1);
    const out = document.createElement('canvas'); out.width = width; out.height = height;
    const ctx = out.getContext('2d');
    const k = x.fit === 'contain' ? Math.min(width / cam.W0, height / cam.H0) : Math.max(width / cam.W0, height / cam.H0);
    U.uPx.value = k;
    const T = Math.min(x.tile, renderer.capabilities.maxTextureSize - 2 * x.margin), m = x.margin;
    for (let ty = 0; ty < height; ty += T) for (let tx = 0; tx < width; tx += T) {
      const tw = Math.min(T, width - tx), th = Math.min(T, height - ty);
      const win = { x: tx - m, y: ty - m, w: tw + 2 * m, h: th + 2 * m };
      renderer.setSize(win.w, win.h, false);
      setProjection(width, height, x.fit, x.anchor, win);
      renderer.render(scene, camera);
      ctx.drawImage(renderer.domElement, m, m, tw, th, tx, ty, tw, th);
    }
    // restore the live view
    o.transparent = transparentPrev; applyTheme(prev.theme);
    for (const [kk, v] of Object.entries(prev.u)) U[kk].value = v;
    renderer.setPixelRatio(prev.dpr); renderer.setSize(prev.size.x, prev.size.y, false);
    resize(); S.running = wasRunning; kick();
    const blob = await new Promise((res) => out.toBlob(res, 'image/png'));
    if (x.download) {
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob); a.download = x.name || `amont-signature-${theme}-${width}x${height}.png`;
      document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 4000);
    }
    return blob;
  }

  const api = {
    renderer, scene, camera, meta, state: S, uniforms: U, terrainMaterial: tmat, riverMaterial: rmat, lod, count: n, reduced,
    setTheme: (t) => { applyTheme(t, true); kick(); if (reduced) renderer.render(scene, camera); },
    setSizeScale: (v) => { U.uSizeK.value = v; S.size = v; kick(); },
    setCount: (c) => { tgeo.setDrawRange(0, Math.min(n, Math.round(c))); S.drawN = c; kick(); },
    setRiverSpeed: (v) => { S.speed = v; },
    setPreFrame: (fn) => { S.pre = fn; },
    setMetrics: (vh, max) => { S.vh = vh; S.max = max; },
    setSourceTarget: (x, y) => { S.tgt = [x, y]; },
    setFit: (f, anchor) => { S.fit = f; if (anchor) S.anchor = anchor; resize(); kick(); },
    replayIntro: () => { S.intro0 = null; kick(); },
    exportPNG,
    destroy() {
      S.running = false; cancelAnimationFrame(raf); ro.disconnect(); io.disconnect();
      removeEventListener('pointermove', pointer); document.removeEventListener('visibilitychange', onVis);
      tgeo.dispose(); rgeo.dispose(); sgeo.dispose(); tmat.dispose(); rmat.dispose(); smat.dispose(); rtex.dispose();
      renderer.dispose(); canvas.remove();
    },
  };
  return api;
}
