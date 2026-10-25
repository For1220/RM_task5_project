#!/usr/bin/env python3
"""Generate 5-segment middle light bars for the RoboMaster 2026 energy rune.

The original POWER.glb has three spatial segments per arm (LEGGING_1/2/3).
This script rebuilds the same ribbon surface clipped into 5 equal-length
segments, keeping the original material (BLUE_EMISSION / RED_EMISSION).

It only READS assets/POWER.glb and writes new files:
    assets/POWER_LEGGING5_FACE1.glb
    assets/POWER_LEGGING5_FACE2.glb

Usage:
    python3 tools/make_legging5.py
    python3 tools/make_legging5.py --offset 0.0      # no lift off the surface
"""

from __future__ import annotations

import argparse
import json
import math
import os
import struct

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "blender", "POWER_COL.glb")
SEGMENTS = 5


# ----------------------------------------------------------------------------
# GLB reading
# ----------------------------------------------------------------------------
def read_glb(path: str):
    data = open(path, "rb").read()
    magic, version, _length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError("not a GLB file")
    offset = 12
    doc = None
    binary = b""
    while offset < len(data):
        clen, ctype = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8: offset + 8 + clen]
        if ctype == 0x4E4F534A:      # JSON
            doc = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:    # BIN
            binary = chunk
        offset += 8 + clen
    return doc, binary


def node_local(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
    t = np.array(node.get("translation", [0, 0, 0]), dtype=np.float64)
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    s = np.array(node.get("scale", [1, 1, 1]), dtype=np.float64)
    r = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ], dtype=np.float64)
    m = np.eye(4)
    m[:3, :3] = r * s
    m[:3, 3] = t
    return m


class Source:
    def __init__(self, path):
        self.doc, self.bin = read_glb(path)
        self.nodes = self.doc["nodes"]
        self.accessors = self.doc["accessors"]
        self.buffer_views = self.doc["bufferViews"]
        self.parent = {}
        for i, n in enumerate(self.nodes):
            for c in n.get("children", []):
                self.parent[c] = i
        self.index = {n.get("name", ""): i for i, n in enumerate(self.nodes)}

    def global_matrix(self, i):
        m = node_local(self.nodes[i])
        k = i
        while k in self.parent:
            k = self.parent[k]
            m = node_local(self.nodes[k]) @ m
        return m

    def _accessor(self, ai):
        a = self.accessors[ai]
        bv = self.buffer_views[a["bufferView"]]
        offset = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        comp = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32,
                5126: np.float32}[a["componentType"]]
        ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        stride = bv.get("byteStride", 0)
        if stride and stride != ncomp * np.dtype(comp).itemsize:
            raw = np.frombuffer(self.bin, dtype=np.uint8,
                                count=stride * a["count"], offset=offset)
            raw = raw.reshape(a["count"], stride)[:, :ncomp * np.dtype(comp).itemsize]
            arr = raw.copy().view(comp).reshape(a["count"], ncomp)
        else:
            arr = np.frombuffer(self.bin, dtype=comp,
                                count=a["count"] * ncomp, offset=offset).reshape(-1, ncomp)
        return arr

    def triangles(self, node_index, face_inv):
        """Return triangles in FACE-local space as (p0,p1,p2,n0,n1,n2)."""
        node = self.nodes[node_index]
        mesh = self.doc["meshes"][node["mesh"]]
        gm = self.global_matrix(node_index)
        m = face_inv @ gm
        rot = m[:3, :3]
        normal_rot = np.linalg.inv(rot).T
        out = []
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            pos = self._accessor(attrs["POSITION"]).astype(np.float64)
            nrm = self._accessor(attrs["NORMAL"]).astype(np.float64) \
                if "NORMAL" in attrs else None
            idx = self._accessor(prim["indices"]).astype(np.int64).reshape(-1) \
                if "indices" in prim else np.arange(len(pos))

            world = (rot @ pos.T).T + m[:3, 3]
            world_n = (normal_rot @ nrm.T).T if nrm is not None else None
            if world_n is not None:
                ln = np.linalg.norm(world_n, axis=1, keepdims=True)
                world_n = np.divide(world_n, ln, out=np.zeros_like(world_n), where=ln > 0)

            for t in range(0, len(idx) - 2, 3):
                i0, i1, i2 = idx[t], idx[t + 1], idx[t + 2]
                p = [world[i0], world[i1], world[i2]]
                if np.linalg.norm(np.cross(p[1] - p[0], p[2] - p[0])) < 1e-12:
                    continue
                n = [world_n[i0], world_n[i1], world_n[i2]] if world_n is not None else None
                out.append((p, n))
        return out


# ----------------------------------------------------------------------------
# Clipping
# ----------------------------------------------------------------------------
def clip_triangle(tri, axis, lo, hi):
    """Clip a triangle to the slab lo <= dot(p, axis) <= hi.

    tri = (points[3], normals[3]|None)
    Returns list of (points, normals) polygons with 3..5 vertices.
    """
    pts, nrms = tri
    poly = [[pts[i], None if nrms is None else nrms[i]] for i in range(3)]

    for sign, bound in ((1.0, lo), (-1.0, hi)):
        if not poly:
            return []
        out = []
        def value(v):
            return sign * float(np.dot(v[0], axis)) - sign * bound
        prev = poly[-1]
        prev_val = value(prev)
        prev_in = prev_val >= -1e-9
        for cur in poly:
            cur_val = value(cur)
            cur_in = cur_val >= -1e-9
            if cur_in != prev_in:
                denom = prev_val - cur_val
                t = prev_val / denom if abs(denom) > 1e-15 else 0.0
                p = prev[0] + (cur[0] - prev[0]) * t
                n = None
                if prev[1] is not None and cur[1] is not None:
                    n = prev[1] + (cur[1] - prev[1]) * t
                    ln = np.linalg.norm(n)
                    if ln > 1e-12:
                        n = n / ln
                out.append([p, n])
            if cur_in:
                out.append([cur[0], cur[1]])
            prev, prev_val, prev_in = cur, cur_val, cur_in
        poly = out
    return poly


def fan(poly):
    if len(poly) < 3:
        return []
    out = []
    for i in range(1, len(poly) - 1):
        out.append((poly[0], poly[i], poly[i + 1]))
    return out


# ----------------------------------------------------------------------------
# GLB writing
# ----------------------------------------------------------------------------
def write_glb(path, root_name, groups, material):
    """groups: list of (group_name, [ (segment_name, tris) ... ])."""
    doc = {
        "asset": {"version": "2.0", "generator": "RM2026 legging5 generator"},
        "scene": 0,
        "scenes": [{"name": root_name, "nodes": [0]}],
        "nodes": [{"name": root_name, "children": []}],
        "meshes": [],
        "materials": [material],
        "accessors": [],
        "bufferViews": [],
        "buffers": [],
    }
    if material.get("extensions", {}).get("KHR_materials_emissive_strength"):
        doc["extensionsUsed"] = ["KHR_materials_emissive_strength"]

    blob = bytearray()

    def add_view(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        view = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)}
        if target:
            view["target"] = target
        blob.extend(data)
        doc["bufferViews"].append(view)
        return len(doc["bufferViews"]) - 1

    def add_accessor(view, count, ctype, atype, mn=None, mx=None):
        acc = {"bufferView": view, "componentType": ctype,
               "count": count, "type": atype}
        if mn is not None:
            acc["min"] = [float(x) for x in mn]
            acc["max"] = [float(x) for x in mx]
        doc["accessors"].append(acc)
        return len(doc["accessors"]) - 1

    for group_name, segs in groups:
        group_node = {"name": group_name, "children": []}
        doc["nodes"].append(group_node)
        group_idx = len(doc["nodes"]) - 1
        doc["nodes"][0]["children"].append(group_idx)

        for seg_name, tris in segs:
            if not tris:
                continue
            verts = []
            normals = []
            for a, b, c in tris:
                for v in (a, b, c):
                    verts.append(v[0])
                    normals.append(v[1] if v[1] is not None else np.zeros(3))
            verts = np.asarray(verts, dtype=np.float32)
            normals = np.asarray(normals, dtype=np.float32)

            pv = add_view(verts.tobytes(), 34962)
            pa = add_accessor(pv, len(verts), 5126, "VEC3",
                              verts.min(axis=0), verts.max(axis=0))
            nv = add_view(normals.tobytes(), 34962)
            na = add_accessor(nv, len(normals), 5126, "VEC3")

            doc["meshes"].append({
                "name": seg_name,
                "primitives": [{
                    "attributes": {"POSITION": pa, "NORMAL": na},
                    "material": 0,
                }],
            })
            mesh_idx = len(doc["meshes"]) - 1
            doc["nodes"].append({"name": seg_name, "mesh": mesh_idx})
            group_node["children"].append(len(doc["nodes"]) - 1)

    while len(blob) % 4:
        blob.append(0)
    doc["buffers"] = [{"byteLength": len(blob)}]

    js = json.dumps(doc, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(blob)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(blob), 0x004E4942))
        f.write(blob)


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
def build_face(src: Source, face_name: str, offset: float):
    face_i = src.index[face_name]
    face_global = src.global_matrix(face_i)
    face_inv = np.linalg.inv(face_global)
    face_rot = face_global[:3, :3]

    # Face-plane normal: normal of the best-fit plane through the 5 target centres.
    centres = np.array([
        (face_inv @ src.global_matrix(src.index[f"{face_name}_TARGET_{k}_ACTIVE"]))[:3, 3]
        for k in range(1, 6)
    ])
    centre = centres.mean(axis=0)
    _, _, vt = np.linalg.svd(centres - centre)
    plane_n = vt[2]
    # Orient the plane normal so it points to the visible side of the ribbon.
    probe = (face_inv @ src.global_matrix(src.index[f"{face_name}_TARGET_1_LEGGING_1"]))[:3, 3]
    if np.dot(probe - centre, plane_n) < 0:
        plane_n = -plane_n
    plane_n /= np.linalg.norm(plane_n)

    material = None
    # 直接复制源文件里灯条实际使用的材质，保证和场景自带 LEGGING 完全一致
    probe_node = src.index[f"{face_name}_TARGET_1_LEGGING_1"]
    probe_mesh = src.doc["meshes"][src.nodes[probe_node]["mesh"]]
    mat_index = probe_mesh["primitives"][0].get("material")
    if mat_index is None:
        raise KeyError(f"{face_name} LEGGING material")
    material = json.loads(json.dumps(src.doc["materials"][mat_index]))

    groups = []
    report = []
    for k in range(1, 6):
        target_local = (face_inv @ src.global_matrix(src.index[f"{face_name}_TARGET_{k}_ACTIVE"]))[:3, 3]
        u = target_local - centre
        u -= plane_n * np.dot(u, plane_n)
        u /= np.linalg.norm(u)

        tris = []
        for s in (1, 2, 3):
            node = src.index[f"{face_name}_TARGET_{k}_LEGGING_{s}"]
            tris.extend(src.triangles(node, face_inv))

        ts = np.array([np.dot(p, u) for tri, _ in tris for p in tri])
        t0, t1 = float(ts.min()), float(ts.max())
        length = t1 - t0
        cuts = np.linspace(t0, t1, SEGMENTS + 1)

        segs = []
        for s in range(SEGMENTS):
            lo, hi = float(cuts[s]), float(cuts[s + 1])
            out_tris = []
            for tri in tris:
                poly = clip_triangle(tri, u, lo, hi)
                for a, b, c in fan(poly):
                    out_tris.append((a, b, c))
            # Lift the ribbon a hair off the original surface along the face normal.
            if offset:
                for tri in out_tris:
                    for v in tri:
                        v[0] = v[0] + plane_n * offset
            segs.append((f"TARGET_{k}_SEG_{s + 1}", out_tris))
        groups.append((f"TARGET_{k}", segs))
        report.append((k, t0, t1, length, sum(len(x[1]) for x in segs)))

    return groups, material, report, centre, plane_n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=SRC)
    ap.add_argument("--offset", type=float, default=0.0005,
                    help="lift along face normal in metres (default 0.5 mm)")
    args = ap.parse_args()

    src = Source(args.src)
    for face, mat, suffix in (("FACE_1", "RED_EMISSION", "FACE1"),
                              ("FACE_2", "BLUE_EMISSION", "FACE2")):
        groups, material, report, centre, n = build_face(src, face, args.offset)
        out = os.path.join(ROOT, "assets", f"POWER_LEGGING5_{suffix}.glb")
        write_glb(out, f"POWER_LEGGING5_{suffix}", groups, material)
        print(f"\n{face} -> {out}")
        print(f"  material: {material['name']}   plane normal: {np.round(n, 5)}")
        for k, t0, t1, length, tris in report:
            print(f"  TARGET_{k}: t=[{t0:.4f}, {t1:.4f}]  L={length:.4f} m  "
                  f"segment={length / SEGMENTS:.4f} m  tris={tris}")


if __name__ == "__main__":
    main()
