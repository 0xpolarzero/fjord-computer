#!/usr/bin/env python3
"""Fjord Computer signature: the real Naeroyfjord (Sogn, Norway) baked for the Amont Labs real-time renderer.

    python3 docs/design/fjord/tools/make_fjord_signature.py            # bake -> docs/design/fjord/signature/
    python3 docs/design/fjord/tools/make_fjord_signature.py --check    # bake, then render tools/check.png
    python3 docs/design/fjord/tools/make_fjord_signature.py --check-only   # only re-render check.png from the bins

Reuses the Amont studio pipeline without touching it (imported from AMONT_SCRIPTS, default
~/code/projects/amont/scripts): make_relief (Terrarium z14 tile fetch), make_signature (terrain, camera,
priority-flood routing) and make_signature_data (world-space points, blue noise, z-buffer visibility, river
channels, binary format). Everything that would write into the amont repo is redirected here:
tiles -> tools/cache/, stage-1 cache -> tools/cache/stage1/, output -> signature/ (or $SIG_OUT).

Output is the "data" format of signature.js (mount(el, { source: 'data' })): terrain-hi.bin, terrain-lo.bin,
river.bin, meta.json, exactly as documented in make_signature_data.py.

What is fjord-specific here:
  * the DEM is clamped at 0 m (Terrarium has the sea at ~0) and terrain points on the water are dropped, so the
    fjord reads as a dark channel between the walls;
  * the river is routed from a 1660 m plateau summit on the south-east bank down its stream into the fjord and cut
    a little past the shore, so its fade-out happens on the water;
  * the fjord surface is carried by extra river channels: the fjord centreline (medial path of the water mask) is
    cut into short overlapping stretches, one channel each, with a wide spread (a fraction of the local half
    width) and a sin envelope on the density. All channels share the renderer's speed in u, so a short channel is a
    slow one in metres: the sheet drifts seaward at a fraction of the river's speed. No renderer change needed.
"""
import json, math, os, sys, time
import numpy as np
from scipy.ndimage import distance_transform_edt, gaussian_filter
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra

HERE = os.path.dirname(os.path.abspath(__file__))
FJORD = os.path.dirname(HERE)
OUT = os.environ.get("SIG_OUT") or os.path.join(FJORD, "signature")
os.environ["SIG_OUT"] = OUT                       # make_signature_data reads it at import
AMONT = os.environ.get("AMONT_SCRIPTS") or os.path.expanduser("~/code/projects/amont/scripts")
TILES = os.path.join(HERE, "cache")
STAGE1 = os.path.join(HERE, "cache", "stage1")
os.makedirs(OUT, exist_ok=True); os.makedirs(STAGE1, exist_ok=True)
sys.path.insert(0, AMONT)

import make_relief as mr                          # noqa: E402
mr.CACHE = TILES                                  # get_tile reads the module global at call time
import make_signature as ms                       # noqa: E402
import make_signature_data as msd                 # noqa: E402

# ------------------------------------------------------------------ place, camera, sampling
# z14 tiles 8496..8518 x 4663..4682: 60.82-61.02 N, 6.70-7.18 E (Naeroyfjord, its head at Gudvangen and the
# junction with Aurlandsfjord). Water (Terrarium ~0 m) covers ~6.6 % of the block.
ms.BLOCKS["naeroy"] = (8496, 8518, 4663, 4682)
SRC = (60.9057, 6.9392)                           # 1660 m summit on the SE bank; its stream falls NW into the fjord bend
HEAD = (60.8790, 6.8430)                          # Gudvangen, head of the fjord
SEA = (60.9850, 7.0400)                           # junction with Aurlandsfjord (seaward end)

CFG = dict(ms.CFG)
CFG.update(dict(
    block="naeroy", tgt=(60.932, 6.905), az=235.0, pitch=46.0, dist=24000.0, fk=1.8, tx=0.56, ty=0.50,
    vex=1.35, summit=SRC, reach=10000.0, up=1, src_drop=120.0,
    mask_c=(0.55, 0.46), mask_ang=33.0, mask_a=0.70, mask_b=0.36, mask_floor=0.06,
    dens=0.30, w_floor=0.04, w_base=0.02, w_face=0.07, w_ridge=1.1, w_sil=0.40, t_lit=0.42,
    c16=0.45, c16w=0.2, c8=0.30, c8w=0.30, w_hatch=1.0, step=3.0,
    river_n=14000, braid=140, rs0=1.4, rs1=4.5, rfade=0.20, river_end=0,
    streams=((0.0, 1.0, 0.0), (1.0, 0.40, 1.0), (-1.0, 0.35, 2.0)),
    # fjord sheet
    fj_len=900.0, fj_spread=0.38, fj_n=11000, fj_dens=0.85, fj_into=260.0,
))
CFG.update(json.loads(os.environ.get("FJ_CFG", "{}")))
CFG = {k: (tuple(v) if isinstance(v, list) else v) for k, v in CFG.items()}
msd.SAMPLING_KEYS |= {"fj_len", "fj_spread", "fj_n", "fj_dens", "fj_into", "water_z"}
msd.CFG.clear(); msd.CFG.update(CFG)
msd.CACHE = STAGE1
msd.OUT = OUT
msd.HI = int(os.environ.get("SIG_HI", 190000)); msd.LO = int(os.environ.get("SIG_LO", 64000))
msd.NS = int(os.environ.get("SIG_NS", 512))
log = msd.log

# sea level: Terrarium has the fjord at 0 +- 0.3 m; clamp so the surface is one flat sheet
_init = ms.Terrain.__init__
def _terrain_init(self, cfg):
    _init(self, cfg)
    self.Z = np.maximum(self.Z, 0.0)
ms.Terrain.__init__ = _terrain_init

# ------------------------------------------------------------------ fjord centreline
def water_grid(T, ds=3):
    x0, x1, y0, y1 = ms.BLOCKS[CFG["block"]]
    arr, _, _ = mr.dem_window(x0 * 256, y0 * 256, (x1 + 1) * 256 - 1, (y1 + 1) * 256 - 1)
    Z = gaussian_filter(np.maximum(arr, 0), 1.0)[::ds, ::ds]
    return Z <= 0.6, ds

def fjord_centreline(T, ds=3):
    """Medial path of the water mask from the fjord head to the seaward end: (E, N, half width m)."""
    wet, ds = water_grid(T, ds)
    dist = distance_transform_edt(wet) * ds * T.mpp            # metres to the shore
    h, w = wet.shape
    idx = -np.ones(wet.shape, np.int64); cells = np.flatnonzero(wet.ravel()); idx.flat[cells] = np.arange(cells.size)
    R, C = np.divmod(cells, w)
    rows, cols, wts = [], [], []
    for dr, dc in ((0, 1), (1, 0), (1, 1), (1, -1)):
        rr, cc = R + dr, C + dc
        ok = (rr >= 0) & (rr < h) & (cc >= 0) & (cc < w)
        a = np.arange(cells.size)[ok]; b = idx[rr[ok], cc[ok]]
        g = b >= 0; a, b = a[g], b[g]
        dm = 0.5 * (dist.flat[cells[a]] + dist.flat[cells[b]])
        wts.append(math.hypot(dr, dc) / (dm + 5.0) ** 2); rows.append(a); cols.append(b)
    G = coo_matrix((np.concatenate(wts), (np.concatenate(rows), np.concatenate(cols))), shape=(cells.size,) * 2).tocsr()
    def node(lat, lon):
        E, N = T_world(T, lat, lon); r, c = int(round(-N / T.mpp / ds)), int(round(E / T.mpp / ds))
        rr, cc = np.divmod(cells, w); k = np.argmin((rr - r) ** 2 + (cc - c) ** 2); return k
    a, b = node(*HEAD), node(*SEA)
    _, pred = dijkstra(G, directed=False, indices=a, return_predecessors=True)
    path = [b]
    while path[-1] != a and pred[path[-1]] >= 0: path.append(pred[path[-1]])
    path = path[::-1]                                          # head -> sea: the direction the water drifts
    r, c = np.divmod(cells[path], w)
    E = gaussian_filter(c * ds * T.mpp, 6, mode="nearest"); N = gaussian_filter(-r * ds * T.mpp, 6, mode="nearest")
    hw = gaussian_filter(dist[r, c], 8, mode="nearest")
    return E, N, hw

def T_world(T, lat, lon):
    x0, _, y0, _ = ms.BLOCKS[CFG["block"]]
    x, y = mr.merc(lat, lon)
    return (x - x0 * 256) * T.mpp, -(y - y0 * 256) * T.mpp

def fjord_channels(T, cams, zbs, tE, tN, tZ):
    """Short overlapping stretches of the fjord centreline, one river channel each: rows (2k, NS, 4), weights."""
    cfg = CFG; hero = cams[0]; NS = msd.NS
    E, N, hw = fjord_centreline(T)
    X, Y, D = hero.proj(E, N, np.zeros_like(E))
    m = 250
    inside = (X > -m) & (X < ms.W0 + m) & (Y > -m) & (Y < ms.H0 + m) & (D > 300)
    ii = np.flatnonzero(inside); E, N, hw, D = E[ii[0]:ii[-1] + 1], N[ii[0]:ii[-1] + 1], hw[ii[0]:ii[-1] + 1], D[ii[0]:ii[-1] + 1]
    s = np.concatenate([[0], np.cumsum(np.hypot(np.diff(E), np.diff(N)))])
    Lf = cfg["fj_len"]; starts = np.arange(-0.5 * Lf, s[-1] - 0.5 * Lf, 0.5 * Lf)   # 50 % overlap: envelopes sum to ~1
    rows, wts = [], []
    for s0 in starts:
        u = np.clip(s0 + np.linspace(0, Lf, NS), 0, s[-1])
        e = np.interp(u, s, E); n = np.interp(u, s, N); h = np.interp(u, s, hw); dd = np.interp(u, s, D)
        z = np.full(NS, 1.0)                                    # 1 m above the sea surface
        f = np.linspace(0, 1, NS)
        env = np.sin(np.pi * f) ** 1.3
        vh = msd.visible_in(hero, zbs[0], e, n, z, tol=0.012, add=40.0); cnt = vh.astype(int)
        for c, zb in zip(cams[1:], zbs[1:]): cnt += msd.visible_in(c, zb, e, n, z, tol=0.012, add=40.0)
        vis = gaussian_filter((vh & (cnt >= 4)).astype(np.float32), 6)
        if vis.max() < 0.05: continue
        r = np.zeros((2, NS, 4), np.float32)
        r[0, :, 0] = e - tE; r[0, :, 1] = z - tZ; r[0, :, 2] = -(n - tN); r[0, :, 3] = cfg["fj_spread"] * h
        r[1, :, 0] = vis; r[1, :, 1] = cfg["fj_dens"] * env
        rows.append(r)
        # particles per channel ~ its screen area, so the sheet has an even screen density near and far
        area = Lf * 2 * cfg["fj_spread"] * float(h.mean()) * (hero.f / float(dd.mean())) ** 2 * float(vis.mean())
        wts.append(area)
    log("fjord sheet", len(rows), "channels over", int(s[-1]), "m of centreline")
    return np.concatenate(rows), np.array(wts)

# ------------------------------------------------------------------ bake
def drop_water(A):
    keep = A["Z"] > CFG.get("water_z", 2.5)
    log("terrain points on the water dropped", int((~keep).sum()))
    return {k: v[keep] for k, v in A.items()}

def cut_at_sea(T, path, into):
    """Cut the routed path a little after it reaches the sea (the flow tree would follow the fjord out)."""
    wet, ds = water_grid(T)
    r = np.clip((-path[:, 1] / T.mpp / ds).astype(int), 0, wet.shape[0] - 1)
    c = np.clip((path[:, 0] / T.mpp / ds).astype(int), 0, wet.shape[1] - 1)
    w = np.flatnonzero(wet[r, c])
    if not w.size: return path
    s = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(path, axis=0).T))])
    end = int(np.searchsorted(s, s[w[0]] + into))
    return path[:max(end, w[0] + 2)]

def bake():
    T, S, d = msd.stage1()
    tE, tN, tZ = d["tE"], d["tN"], d["tZ"]
    cams = [msd.make_cam(T, CFG, (tE, tN, tZ), da, dp) for da, dp in msd.DRIFT]
    zbs = d["zbs"]
    A = drop_water(msd.sample_points(d))
    A["x"] = A["E"] - tE; A["y"] = A["Z"] - tZ; A["z"] = -(A["N"] - tN)
    box = tuple(float(np.ceil(np.abs(A[k]).max() * 1.001)) for k in "xyz")
    rng = np.random.default_rng(7)
    n = len(A["x"]); perm = rng.permutation(n)
    hi = perm[:min(msd.HI, n)]
    msd.write_terrain("terrain-hi.bin", A, hi, box)
    wlo = 0.35 + A["T"][hi]
    pick = rng.random(len(hi)) < (msd.LO / len(hi)) * wlo / wlo.mean()
    lo = hi[pick]; lo = lo[rng.permutation(len(lo))]
    msd.write_terrain("terrain-lo.bin", A, lo, box)
    path = cut_at_sea(T, d["path"], CFG["fj_into"])
    rows, weights, src, L = msd.build_river(T, S, cams, zbs, tE, tN, tZ, path)
    frows, fw = fjord_channels(T, cams, zbs, tE, tN, tZ)
    nr, nf = int(CFG["river_n"]), int(CFG["fj_n"])
    w = np.array(weights) / sum(weights)
    chan_r = rng.choice(len(weights), nr, p=w)
    chan_f = len(weights) + rng.choice(len(fw), nf, p=fw / fw.sum())
    chan = np.concatenate([chan_r, chan_f]).astype(np.float32)
    npart = nr + nf
    part = np.stack([rng.random(npart), chan, rng.standard_normal(npart), rng.random(npart)], 1).astype("<f4")
    part = part[rng.permutation(npart)]
    allrows = np.concatenate([rows, frows]).astype("<f4")
    with open(os.path.join(OUT, "river.bin"), "wb") as fh:
        fh.write(allrows.tobytes()); fh.write(part.tobytes())
    nch = allrows.shape[0] // 2
    meta = dict(
        camera=dict(target=[0.0, 0.0, 0.0], az=CFG["az"], pitch=CFG["pitch"], dist=CFG["dist"], fk=CFG["fk"], tx=CFG["tx"], ty=CFG["ty"],
                    W0=ms.W0, H0=ms.H0, drift=[2.2, 1.2]),
        box=list(box), counts=dict(hi=int(len(hi)), lo=int(len(lo))), source=[float(v) for v in src],
        river=dict(samples=msd.NS, channels=int(nch), particles=int(npart), length=float(L)),
        vex=CFG["vex"],
        place=dict(name="Naeroyfjord, Sogn, Norway", source_latlon=list(SRC), target_latlon=list(CFG["tgt"]),
                   river_channels=len(weights), fjord_channels=int(nch - len(weights)), dem="AWS Terrarium z14"),
    )
    json.dump(meta, open(os.path.join(OUT, "meta.json"), "w"), indent=1)
    for f in ("terrain-hi.bin", "terrain-lo.bin", "river.bin", "meta.json"):
        log(f, os.path.getsize(os.path.join(OUT, f)) // 1024, "KB")
    log("done", meta["counts"], meta["river"])

# ------------------------------------------------------------------ check render (CPU emulation of signature.js, data mode)
THEMES = {
    "dark": dict(bg=(0x10, 0x14, 0x18), lo=(0xA3, 0xAA, 0xB0), hi=(0xE6, 0xE9, 0xE4), r=(0.78, 0.28, 0.42), aK=(0.22, 0.78), dim=0.35, thin=0.0, light=0),
    "light": dict(bg=(0xF7, 0xF8, 0xF5), lo=(0x5C, 0x63, 0x6A), hi=(0x10, 0x14, 0x18), r=(0.70, 0.24, 0.26), aK=(0.30, 0.62), dim=0.20, thin=0.22, light=1),
}
FONTE = np.array([0x0F, 0x9A, 0xC3]) / 255

def fract(x): return x - np.floor(x)
def hsh(x): return fract(np.sin(x * 127.1) * 43758.5453)

from PIL import Image

def check(path, Wout=1600, dpr=2, t=18.0, speed=0.024, lod="hi"):
    """Wout css px wide at devicePixelRatio dpr (rendered at Wout*dpr, then downsampled)."""
    Wc = Wout * dpr
    meta = json.load(open(os.path.join(OUT, "meta.json")))
    cam = meta["camera"]; box = np.array(meta["box"])
    rec = np.fromfile(os.path.join(OUT, f"terrain-{lod}.bin"), dtype=[("p", "<i2", 3), ("t", "u1"), ("s", "u1")])
    P = rec["p"].astype(np.float32) / 32767 * box; tone = rec["t"] / 255.0; seed = rec["s"] / 255.0
    C = ms.Camera((0.0, 0.0, 0.0), cam["az"], cam["pitch"], cam["dist"], cam["fk"] * ms.W0, cam["tx"], cam["ty"])
    proj = lambda p: C.proj(p[:, 0], -p[:, 2], p[:, 1])           # world (x east, y up, z -north) -> camera (E, N, Z)
    k = Wc / ms.W0; Hc = int(round(ms.H0 * k)); uPx = k; minD = 1.05
    R = meta["river"]; NS, nch = R["samples"], R["channels"]
    raw = np.fromfile(os.path.join(OUT, "river.bin"), dtype="<f4")
    rows = raw[:NS * nch * 2 * 4].reshape(nch * 2, NS, 4); part = raw[NS * nch * 2 * 4:].reshape(-1, 4)
    def tex(row, f):
        x = np.clip(f, 0, 1) * (NS - 1); i0 = np.floor(x).astype(int); i1 = np.minimum(i0 + 1, NS - 1); fr = (x - i0)[:, None]
        return rows[row, i0] * (1 - fr) + rows[row, i1] * fr
    ims = []
    for name, th in THEMES.items():
        X, Y, D = proj(P)
        dn = np.clip((D - cam["dist"] * 0.72) / (cam["dist"] * 0.83), 0, 1)
        r = th["r"][0] + th["r"][1] * (1 - dn) + th["r"][2] * tone
        a = np.clip(th["aK"][0] + th["aK"][1] * tone ** 0.9, 0, 1) * (0.75 + 0.25 * hsh(seed * 7.7)) * (1 - th["dim"] * dn)
        dd = 2 * r * uPx; small = dd < minD; a = np.where(small, a * (dd / minD) ** 2, a); dd = np.where(small, minD, dd)
        if th["light"]: a = np.where((tone < 0.30) & (hsh(seed * 3.3) < th["thin"] * 3), 0, a)
        lo, hi = np.array(th["lo"]) / 255, np.array(th["hi"]) / 255
        mixk = np.clip(np.where(th["light"], (tone >= 0.30).astype(float), tone * 1.15 - 0.05), 0, 1)[:, None]
        col = lo + (hi - lo) * mixk
        pre_t = ms.splat(X * k, Y * k, dd / 2, a, col, Wc, Hc, 2)
        # river + fjord sheet
        ch, sd = part[:, 1].astype(int), part[:, 3]
        jit = 0.9 + 0.2 * fract(sd * 91.3)
        u = fract(part[:, 0] + t * speed * jit)
        c0 = np.zeros((len(u), 4)); st = np.zeros((len(u), 4)); ca = np.zeros((len(u), 4)); cb = np.zeros((len(u), 4))
        for c in range(nch):
            m = ch == c
            if not m.any(): continue
            c0[m] = tex(2 * c, u[m]); st[m] = tex(2 * c + 1, u[m]); ca[m] = tex(2 * c, u[m] - 0.004); cb[m] = tex(2 * c, u[m] + 0.004)
        tv = cb[:, :3] - ca[:, :3] + 1e-4; tv /= np.linalg.norm(tv, axis=1)[:, None]
        nv = np.stack([-tv[:, 2], np.zeros(len(u)), tv[:, 0]], 1); nv /= np.linalg.norm(nv, axis=1)[:, None] + 1e-9
        p = c0[:, :3] + nv * (part[:, 2] * c0[:, 3])[:, None]
        on = sd < st[:, 1] * st[:, 0]
        rnd = fract(sd * 13.7)
        rr = 1.1 + 0.55 * (1 - u) + 0.35 * rnd
        ra = (0.78 + 0.22 * np.sqrt(1 - u)) if th["light"] else (0.80 + 0.20 * rnd)
        ra = ra * on * (1 - ms.smoothstep(0.88, 1.0, u))
        dd = 2 * rr * uPx; small = dd < minD; ra = np.where(small, ra * (dd / minD) ** 2, ra); dd = np.where(small, minD, dd)
        Xr, Yr, _ = proj(p)
        g = ra > 0
        pre_r = ms.splat(Xr[g] * k, Yr[g] * k, dd[g] / 2, ra[g], np.tile(FONTE, (int(g.sum()), 1)), Wc, Hc, 2)
        sx, sy, _ = proj(np.array([meta["source"]], np.float32))
        pre_r = ms.over(ms.source_layer((float(sx[0] * k), float(sy[0] * k)), Wc, Hc, 2, name, sc=0.45 * dpr), pre_r)
        ims.append(ms.comp(ms.over(pre_r, pre_t), th["bg"]).resize((Wout, int(round(Hc / dpr))), Image.LANCZOS))
    Wc, Hc = ims[0].size
    sheet = Image.new("RGB", (Wc, Hc * 2 + 8), (128, 128, 128))
    sheet.paste(ims[0], (0, 0)); sheet.paste(ims[1], (0, Hc + 8))
    sheet.save(path)
    log("check", path)

if __name__ == "__main__":
    a = sys.argv[1:]
    if "--check-only" not in a: bake()
    if "--check" in a or "--check-only" in a: check(os.path.join(HERE, "check.png"))
