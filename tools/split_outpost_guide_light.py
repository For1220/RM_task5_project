#!/usr/bin/env python3
"""Split the outpost dart guide light out of assets/OUTPOST.glb.

The original OUTPOST.glb bakes the green dart guide light into two large
multi-material meshes.  This script:

  * removes the green guide-light primitives from those meshes
  * creates GUIDE_LIGHT_ON_*  (original green emissive material)
  * creates GUIDE_LIGHT_OFF_* (dark unlit material, 3 % smaller so it sits
    inside the ON mesh and is hidden while the ON mesh is visible)
  * writes a NEW file, leaving assets/OUTPOST.glb untouched

Usage:
    python3 tools/split_outpost_guide_light.py
    python3 tools/split_outpost_guide_light.py --output assets/OUTPOST_SPLIT.glb
"""

from __future__ import annotations

import argparse
import json
import os
import struct

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "OUTPOST.glb")
OUT = os.path.join(ROOT, "assets", "OUTPOST_GUIDE_LIGHT.glb")

# mat_25: green emissive guide light (520 nm)
GUIDE_MATERIAL_INDEX = 1
OFF_SCALE = 0.97


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, _length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError("not a GLB")
    offset = 12
    doc = None
    binary = b""
    while offset < len(data):
        clen, ctype = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8: offset + 8 + clen]
        if ctype == 0x4E4F534A:
            doc = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:
            binary = chunk
        offset += 8 + clen
    return doc, binary


def write_glb(path, doc, binary):
    js = json.dumps(doc, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    while len(js) % 4:
        js += b" "
    while len(binary) % 4:
        binary += b"\x00"
    total = 12 + 8 + len(js) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(binary), 0x004E4942))
        f.write(binary)


def off_matrix(center):
    s = OFF_SCALE
    cx, cy, cz = center
    # glTF matrix is column-major
    return [
        s, 0.0, 0.0, 0.0,
        0.0, s, 0.0, 0.0,
        0.0, 0.0, s, 0.0,
        (1.0 - s) * cx, (1.0 - s) * cy, (1.0 - s) * cz, 1.0,
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=SRC)
    ap.add_argument("--output", default=OUT)
    args = ap.parse_args()

    doc, binary = read_glb(args.src)
    nodes = doc["nodes"]
    meshes = doc["meshes"]
    accessors = doc["accessors"]

    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i

    # Create a dark, unlit material for the OFF state.
    off_material = {
        "name": "GUIDE_LIGHT_OFF",
        "doubleSided": True,
        "pbrMetallicRoughness": {
            "baseColorFactor": [0.012, 0.028, 0.012, 1.0],
            "metallicFactor": 0.1,
            "roughnessFactor": 0.55,
        },
    }
    off_mat_index = len(doc["materials"])
    doc["materials"].append(off_material)

    # Find every primitive that uses the green guide-light material.
    targets = []
    for mi, mesh in enumerate(meshes):
        for pi, prim in enumerate(mesh["primitives"]):
            if prim.get("material") == GUIDE_MATERIAL_INDEX:
                targets.append((mi, pi))

    if not targets:
        raise SystemExit("no guide-light primitives found")

    print(f"found {len(targets)} guide-light primitives")

    # Process from the end so removing primitives does not shift indices.
    for mi, pi in sorted(targets, reverse=True):
        mesh = meshes[mi]
        prim = mesh["primitives"].pop(pi)

        # Find the node that owns this mesh (a mesh may be referenced by one node here).
        owner = None
        for ni, n in enumerate(nodes):
            if n.get("mesh") == mi:
                owner = ni
                break
        if owner is None:
            raise SystemExit(f"no node owns mesh {mi}")

        base = nodes[owner].get("name", f"MESH_{mi}")
        # Name the pair after the outpost copy it belongs to (OUTPOST_1 / OUTPOST_2).
        label = base.replace(".", "_")
        k = owner
        while k is not None:
            nm = nodes[k].get("name", "")
            if nm in ("OUTPOST_1", "OUTPOST_2"):
                label = nm[-1]
                break
            k = parent.get(k)

        # AABB center of the guide-light primitive in mesh-local space.
        pos_acc = accessors[prim["attributes"]["POSITION"]]
        mn = np.array(pos_acc["min"], dtype=float)
        mx = np.array(pos_acc["max"], dtype=float)
        center = (mn + mx) * 0.5

        on_mesh = {
            "name": f"GUIDE_LIGHT_ON_{label}",
            "primitives": [dict(prim)],
        }
        off_prim = dict(prim)
        off_prim["material"] = off_mat_index
        off_mesh = {
            "name": f"GUIDE_LIGHT_OFF_{label}",
            "primitives": [off_prim],
        }
        on_idx = len(meshes)
        meshes.append(on_mesh)
        off_idx = len(meshes)
        meshes.append(off_mesh)

        on_node = {
            "name": f"GUIDE_LIGHT_ON_{label}",
            "mesh": on_idx,
        }
        off_node = {
            "name": f"GUIDE_LIGHT_OFF_{label}",
            "mesh": off_idx,
            "matrix": off_matrix(center),
        }
        on_node_idx = len(nodes)
        nodes.append(on_node)
        off_node_idx = len(nodes)
        nodes.append(off_node)

        nodes[owner].setdefault("children", [])
        nodes[owner]["children"].extend([on_node_idx, off_node_idx])

        print(
            f"  mesh {mi} prim {pi} -> {base}: "
            f"ON={on_node['name']} OFF={off_node['name']} "
            f"center={np.round(center, 5)}"
        )

    write_glb(args.output, doc, binary)
    print(f"\nwritten: {args.output}")
    print(f"nodes: {len(nodes)}  meshes: {len(meshes)}  materials: {len(doc['materials'])}")


if __name__ == "__main__":
    main()
