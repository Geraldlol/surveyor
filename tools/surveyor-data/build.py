#!/usr/bin/env python3
"""Build Surveyor's exploration-border tables from the Forever client's terrain.

Offline and read only: reads Map.csv, AreaTable.csv, LiquidType.csv, the WDTs of maps 0 and 1
and every root ADT from a Polestar CASC cache, and writes Surveyor/Data/*.lua
plus MANIFEST.json. `--check` regenerates in memory and compares byte for byte
without writing anything. Standard library only. See README.md.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import struct
import sys
from dataclasses import dataclass
from pathlib import Path

MAPS = (0, 1)
MAX_HOPS = 8
TILE = 1600.0 / 3.0  # 533.3333 yd
CHUNK = TILE / 16.0  # 33.3333 yd
ORIGIN = 32.0 * TILE  # 17066.6667 yd
POSITION_TOLERANCE = 0.01

REPO = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO / "Surveyor" / "Data"
OUTPUT_NAMES = ("Areas.lua", "Borders0.lua", "Borders1.lua", "MANIFEST.json")


class BuildError(Exception):
    pass


# --------------------------------------------------------------------------
# Binary parsing


def read_chunks(buf: bytes, start: int = 0, end: int | None = None) -> list[tuple[str, bytes]]:
    """Top-level chunk walk: 4-byte tag stored reversed, u32 LE size, data."""
    end = len(buf) if end is None else end
    out = []
    o = start
    while o + 8 <= end:
        tag = buf[o : o + 4][::-1].decode("latin-1")
        (size,) = struct.unpack_from("<I", buf, o + 4)
        if o + 8 + size > end:
            raise BuildError(f"chunk {tag} at {o} ({size} bytes) runs past the end ({end})")
        out.append((tag, buf[o + 8 : o + 8 + size]))
        o += 8 + size
    return out


def parse_maid(wdt: bytes) -> list[tuple[int, int, int]]:
    """Return (col, row, root ADT fdid) for every present tile, in index order."""
    maid = next((data for tag, data in read_chunks(wdt) if tag == "MAID"), None)
    if maid is None or len(maid) < 64 * 64 * 32:
        raise BuildError("WDT has no full MAID chunk")
    tiles = []
    for i in range(64 * 64):
        (root,) = struct.unpack_from("<I", maid, i * 32)
        if root:
            tiles.append((i % 64, i // 64, root))
    return tiles


def parse_mcnk_header(data: bytes) -> tuple[int, int, int, float, float]:
    """Return (indexX, indexY, areaId, wx, wy) from an MCNK chunk's 128-byte header."""
    if len(data) < 128:
        raise BuildError(f"MCNK header is {len(data)} bytes, expected at least 128")
    (index_x, index_y) = struct.unpack_from("<II", data, 0x04)
    (area_id,) = struct.unpack_from("<I", data, 0x34)
    (wx, wy) = struct.unpack_from("<ff", data, 0x68)
    return index_x, index_y, area_id, wx, wy


def parse_mh2o(data: bytes) -> list[list[tuple[int, float, int, int, int, int]]]:
    """Per MCNK slot (indexY * 16 + indexX): (liquidType, minHeight, xOffset, yOffset, width, height)."""
    if len(data) < 256 * 12:
        raise BuildError(f"MH2O is {len(data)} bytes, shorter than its 256 headers")
    slots = []
    for i in range(256):
        offset, count, _attributes = struct.unpack_from("<III", data, i * 12)
        layers = []
        for k in range(count):
            o = offset + k * 24
            if o + 24 > len(data):
                raise BuildError(f"MH2O instance {k} of chunk {i} runs past the end")
            liquid, _lvf, min_height, _max_height, x, y, w, h = struct.unpack_from("<HHffBBBB", data, o)
            layers.append((liquid, min_height, x, y, w, h))
        slots.append(layers)
    return slots


def terrain_max(data: bytes) -> float:
    """Highest terrain vertex of an MCNK: zBase (0x70) plus the largest of the 145 MCVT heights."""
    (z_base,) = struct.unpack_from("<f", data, 0x70)
    o = 128
    while o + 8 <= len(data):
        tag = data[o : o + 4][::-1]
        (size,) = struct.unpack_from("<I", data, o + 4)
        if tag == b"MCVT":
            if size < 145 * 4 or o + 8 + size > len(data):
                raise BuildError(f"MCVT is {size} bytes, expected 580")
            return z_base + max(struct.unpack_from("<145f", data, o + 8))
        o += 8 + size
    raise BuildError("MCNK has no MCVT subchunk")


def is_open_sea(layers, ocean: frozenset, data: bytes) -> bool:
    """An ocean layer covering the whole chunk whose surface is above all of the chunk's terrain."""
    full = [m for liquid, m, x, y, w, h in layers if liquid in ocean and (x, y, w, h) == (0, 0, 8, 8)]
    return bool(full) and max(full) > terrain_max(data)


def read_ocean_types(text: str) -> frozenset:
    """LiquidType ids that are ocean: SoundBank 1 or Flags bit 0x400."""
    return frozenset(
        int(row["ID"]) for row in _rows(text) if int(row["SoundBank"]) == 1 or int(row["Flags"]) & 0x400
    )


def parse_adt(adt: bytes, col: int, row: int, ocean: frozenset = frozenset()) -> list[tuple[int, int, int, bool]]:
    """Return (gx, gy, areaId, openSea) for the 256 chunks of a root ADT at tile (col, row)."""
    top = read_chunks(adt)
    mcnks = [data for tag, data in top if tag == "MCNK"]
    mh2o = next((data for tag, data in top if tag == "MH2O"), None)
    liquids = parse_mh2o(mh2o) if mh2o is not None else None
    if len(mcnks) != 256:
        raise BuildError(f"tile {col}_{row}: {len(mcnks)} MCNK chunks, expected 256")
    seen = set()
    out = []
    for n, data in enumerate(mcnks):
        ix, iy, area, wx, wy = parse_mcnk_header(data)
        if ix > 15 or iy > 15 or (ix, iy) in seen:
            raise BuildError(f"tile {col}_{row}: bad or repeated MCNK index ({ix}, {iy})")
        seen.add((ix, iy))
        gx, gy = col * 16 + ix, row * 16 + iy
        if n == 0:
            ex, ey = ORIGIN - gy * CHUNK, ORIGIN - gx * CHUNK
            if abs(wx - ex) > POSITION_TOLERANCE or abs(wy - ey) > POSITION_TOLERANCE:
                raise BuildError(
                    f"tile {col}_{row}: first MCNK at ({wx:.3f}, {wy:.3f}), grid says ({ex:.3f}, {ey:.3f})"
                )
        sea = liquids is not None and is_open_sea(liquids[iy * 16 + ix], ocean, data)
        out.append((gx, gy, area, sea))
    return out


# --------------------------------------------------------------------------
# CSV


@dataclass(frozen=True)
class Area:
    id: int
    name: str
    continent: int
    parent: int
    bit: int
    level: int


def _rows(text: str) -> list[dict[str, str]]:
    return list(csv.DictReader(io.StringIO(text, newline="")))


def read_map_wdts(text: str) -> dict[int, int]:
    """Map ID -> WdtFileDataID for maps 0 and 1, by header name."""
    out = {}
    for row in _rows(text):
        mid = int(row["ID"])
        if mid in MAPS:
            out[mid] = int(row["WdtFileDataID"])
    missing = [m for m in MAPS if not out.get(m)]
    if missing:
        raise BuildError(f"Map.csv has no WdtFileDataID for map(s) {missing}")
    return out


def read_areas(text: str) -> dict[int, Area]:
    out = {}
    for row in _rows(text):
        a = Area(
            id=int(row["ID"]),
            name=row["AreaName_lang"],
            continent=int(row["ContinentID"]),
            parent=int(row["ParentAreaID"]),
            bit=int(row["AreaBit"]),
            level=int(row["ExplorationLevel"]),
        )
        out[a.id] = a
    return out


def root_zone(areas: dict[int, Area], area_id: int) -> int:
    """Follow ParentAreaID to 0, at most MAX_HOPS hops; otherwise the area is its own root."""
    cur = area_id
    for _ in range(MAX_HOPS):
        parent = areas[cur].parent
        if parent == 0:
            return cur
        if parent not in areas:
            return area_id
        cur = parent
    return cur if areas[cur].parent == 0 else area_id


def with_ancestors(areas: dict[int, Area], ids) -> set[int]:
    """The ids plus every ancestor, so each kept parent id resolves."""
    keep = set()
    stack = list(ids)
    while stack:
        aid = stack.pop()
        if aid in keep:
            continue
        keep.add(aid)
        parent = areas[aid].parent
        if parent:
            if parent not in areas:
                raise BuildError(f"area {aid} names parent {parent}, which is not in AreaTable")
            stack.append(parent)
    return keep


# --------------------------------------------------------------------------
# Outline tracing
#
# Grid space: gx grows east, gy grows south; cell (x, y) spans corners
# (x, y)..(x+1, y+1). Every boundary edge is directed with its cell on the
# left in (gx, gy) math orientation, so outer loops run counter-clockwise in
# grid space (clockwise on screen, where gy points down) and holes run the
# other way. Where two cells touch only at a corner, the walk takes the left
# turn, which keeps it on the same cell (diagonal cells are not joined).

_TURN_ORDER = {1: 0, 0: 1, -1: 2}  # left, straight, right


def _edges(cells: set[tuple[int, int]]) -> dict[tuple[int, int], list[tuple[int, int]]]:
    out: dict[tuple[int, int], list[tuple[int, int]]] = {}

    def add(start, direction):
        out.setdefault(start, []).append(direction)

    for x, y in cells:
        if (x, y - 1) not in cells:
            add((x, y), (1, 0))
        if (x + 1, y) not in cells:
            add((x + 1, y), (0, 1))
        if (x, y + 1) not in cells:
            add((x + 1, y + 1), (-1, 0))
        if (x - 1, y) not in cells:
            add((x, y + 1), (0, -1))
    return out


def _next_direction(incoming, choices):
    def rank(d):
        cross = incoming[0] * d[1] - incoming[1] * d[0]
        return _TURN_ORDER[cross]

    return min(choices, key=rank)


def _simplify(points: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """Drop vertices between two collinear edges, then start at the minimum vertex."""
    n = len(points)
    kept = []
    for i in range(n):
        px, py = points[i - 1]
        x, y = points[i]
        nx, ny = points[(i + 1) % n]
        d_in = ((x - px > 0) - (x - px < 0), (y - py > 0) - (y - py < 0))
        d_out = ((nx - x > 0) - (nx - x < 0), (ny - y > 0) - (ny - y < 0))
        if d_in != d_out:
            kept.append((x, y))
    start = kept.index(min(kept))
    return kept[start:] + kept[:start]


def _split_at_repeats(points: list[tuple[int, int]]) -> list[list[tuple[int, int]]]:
    """Split a closed walk that passes a vertex twice into simple closed loops.

    A walk can touch itself where a hole meets the outside (or another hole)
    at a single corner. Each piece keeps the walk's edge directions, so outer
    pieces stay counter-clockwise and hole pieces clockwise.
    """
    pieces = []
    stack: list[tuple[int, int]] = []
    index: dict[tuple[int, int], int] = {}
    for p in points:
        i = index.get(p)
        if i is None:
            index[p] = len(stack)
            stack.append(p)
            continue
        pieces.append(stack[i:])
        for q in stack[i + 1 :]:
            del index[q]
        del stack[i + 1 :]
    pieces.append(stack)
    return pieces


def trace_loops(cells) -> list[list[tuple[int, int]]]:
    """Closed outline loops of a cell set, simplified and sorted deterministically."""
    cells = set(cells)
    out_edges = _edges(cells)
    used = set()
    loops = []
    for start in sorted(out_edges):
        for direction in sorted(out_edges[start]):
            if (start, direction) in used:
                continue
            points = []
            v, d = start, direction
            while (v, d) not in used:
                used.add((v, d))
                points.append(v)
                v = (v[0] + d[0], v[1] + d[1])
                d = _next_direction(d, out_edges[v])
            if (v, d) != (start, direction):
                raise BuildError(f"outline walk from {start} did not close")
            for piece in _split_at_repeats(points):
                loop = _simplify(piece)
                if len(loop) < 4:
                    raise BuildError(f"outline loop from {start} has {len(loop)} vertices")
                loops.append(loop)
    loops.sort(key=lambda lp: (lp[0], len(lp)))
    return loops


@dataclass(frozen=True)
class Outline:
    x0: int
    y0: int
    x1: int
    y1: int
    px: int
    py: int
    chunks: int
    loops: tuple

    @property
    def vertices(self) -> int:
        return sum(len(lp) for lp in self.loops)


def outline(cells) -> Outline:
    cells = set(cells)
    if not cells:
        raise BuildError("outline of an empty cell set")
    xs = [c[0] for c in cells]
    ys = [c[1] for c in cells]
    n, sx, sy = len(cells), sum(xs), sum(ys)
    # The cell whose centre is nearest the mean centre (integer arithmetic, scaled by n).
    px, py = min(cells, key=lambda c: ((n * c[0] - sx) ** 2 + (n * c[1] - sy) ** 2, c[1], c[0]))
    loops = tuple(tuple(lp) for lp in trace_loops(cells))
    return Outline(min(xs), min(ys), max(xs) + 1, max(ys) + 1, px, py, n, loops)


# --------------------------------------------------------------------------
# Model


@dataclass
class MapData:
    map_id: int
    wdt: int
    tiles: int
    chunks: int
    skipped_zero: int
    skipped_missing: int
    missing_ids: list
    other_continent: int
    other_continent_ids: list
    sea_chunks: int  # tagged chunks dropped as open sea
    sea_areas: list  # areas whose every chunk is open sea (absent from borders/zones)
    owners: set  # every area owning a tagged chunk, sea or not
    borders: dict  # areaId -> Outline
    zones: dict  # root zone id -> Outline


def build_map(map_id: int, wdt: int, tiles: list, areas: dict[int, Area]) -> MapData:
    """tiles: list of (col, row, [(gx, gy, areaId, openSea), ...]). Open-sea chunks are not traced."""
    by_area: dict[int, set] = {}
    owners = set()
    zero = missing = other = sea = 0
    missing_ids, other_ids = set(), set()
    chunk_count = 0
    for _col, _row, chunks in tiles:
        for gx, gy, aid, open_sea in chunks:
            chunk_count += 1
            if aid == 0:
                zero += 1
                continue
            if aid not in areas:
                missing += 1
                missing_ids.add(aid)
                continue
            if areas[aid].continent != map_id:
                other += 1
                other_ids.add(aid)
            owners.add(aid)
            if open_sea:
                sea += 1
                continue
            by_area.setdefault(aid, set()).add((gx, gy))
    by_zone: dict[int, set] = {}
    for aid, cells in by_area.items():
        by_zone.setdefault(root_zone(areas, aid), set()).update(cells)
    return MapData(
        map_id=map_id,
        wdt=wdt,
        tiles=len(tiles),
        chunks=chunk_count,
        skipped_zero=zero,
        skipped_missing=missing,
        missing_ids=sorted(missing_ids),
        other_continent=other,
        other_continent_ids=sorted(other_ids),
        sea_chunks=sea,
        sea_areas=sorted(owners - set(by_area)),
        owners=owners,
        borders={aid: outline(c) for aid, c in sorted(by_area.items())},
        zones={zid: outline(c) for zid, c in sorted(by_zone.items())},
    )


# --------------------------------------------------------------------------
# Emitters


def lua_string(s: str) -> str:
    out = []
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ord(ch) < 32 or ord(ch) == 127:
            out.append(f"\\{ord(ch):03d}")
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def header(build: str) -> list[str]:
    return [
        f"-- Generated by tools/surveyor-data/build.py from Forever {build}. Do not edit.",
        "-- luacheck: no max line length",
        "local _, ns = ...",
    ]


def emit_areas(build: str, areas: dict[int, Area], keep: set[int]) -> bytes:
    lines = header(build)
    lines.append(f"ns.DataBuild = {lua_string(build)}")
    lines.append("-- id = { enUS name, ParentAreaID, ExplorationLevel, AreaBit, ContinentID }")
    lines.append("ns.Areas = {")
    for aid in sorted(keep):
        a = areas[aid]
        lines.append(f"\t[{aid}] = {{ {lua_string(a.name)}, {a.parent}, {a.level}, {a.bit}, {a.continent} }},")
    lines.append("}")
    return ("\n".join(lines) + "\n").encode("utf-8")


def _outline_lua(o: Outline) -> str:
    loops = ", ".join("{ " + ", ".join(f"{x}, {y}" for x, y in lp) + " }" for lp in o.loops)
    return f"{{ {o.x0}, {o.y0}, {o.x1}, {o.y1}, {o.px}, {o.py}, {o.chunks}, {{ {loops} }} }}"


def emit_borders(build: str, m: MapData) -> bytes:
    lines = header(build)
    lines += [
        "ns.Borders = ns.Borders or {}",
        "ns.Zones = ns.Zones or {}",
        "-- [areaId] = { x0, y0, x1, y1, px, py, chunks, { loop, loop, ... } }",
        "--   x0..y1: bounding box in chunk-corner units (gx, gy), inclusive-exclusive",
        "--   px, py: a chunk inside the area (its cell indices; centre is +0.5)",
        "--   chunks: number of chunks",
        "--   loop: { gx1, gy1, gx2, gy2, ... } closed, last vertex joins the first",
        "--   outer loops run counter-clockwise in (gx, gy) (clockwise on screen), holes the other way",
        "--   ns.Zones: the same, per top-level zone (ParentAreaID walked to 0)",
        f"ns.Borders[{m.map_id}] = {{}}",
    ]
    for aid, o in m.borders.items():
        lines.append(f"ns.Borders[{m.map_id}][{aid}] = {_outline_lua(o)}")
    lines.append(f"ns.Zones[{m.map_id}] = {{}}")
    for zid, o in m.zones.items():
        lines.append(f"ns.Zones[{m.map_id}][{zid}] = {_outline_lua(o)}")
    return ("\n".join(lines) + "\n").encode("utf-8")


def emit_manifest(
    build: str, product: str, maps: list[MapData], areas: dict[int, Area], areas_kept: int, hashes: dict
) -> bytes:
    doc = {
        "build": build,
        "product": product,
        "inputs": {"sha256": hashes},
        "areas": areas_kept,
        "maps": {
            str(m.map_id): {
                "wdtFileDataID": m.wdt,
                "tiles": m.tiles,
                "chunks": m.chunks,
                "skipped": {
                    "areaZero": m.skipped_zero,
                    "notInAreaTable": m.skipped_missing,
                    "notInAreaTableIds": m.missing_ids,
                },
                "otherContinent": {"chunks": m.other_continent, "ids": m.other_continent_ids},
                "openSea": {
                    "chunksDropped": m.sea_chunks,
                    "areasDropped": [{"id": a, "name": areas[a].name} for a in m.sea_areas],
                },
                "areas": len(m.borders),
                "zones": len(m.zones),
                "vertices": {
                    "borders": sum(o.vertices for o in m.borders.values()),
                    "zones": sum(o.vertices for o in m.zones.values()),
                },
            }
            for m in maps
        },
    }
    return (json.dumps(doc, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")


def generate(
    build: str, product: str, map_csv: bytes, area_csv: bytes, liquid_csv: bytes, read_file
) -> dict[str, bytes]:
    """read_file(fdid) -> bytes. Returns output file name -> bytes."""
    wdts = read_map_wdts(map_csv.decode("utf-8-sig"))
    areas = read_areas(area_csv.decode("utf-8-sig"))
    ocean = read_ocean_types(liquid_csv.decode("utf-8-sig"))
    maps = []
    for map_id in MAPS:
        tiles = []
        for col, row, root in parse_maid(read_file(wdts[map_id])):
            tiles.append((col, row, parse_adt(read_file(root), col, row, ocean)))
        maps.append(build_map(map_id, wdts[map_id], tiles, areas))
    owners = set()
    for m in maps:
        owners.update(m.owners)
    keep = with_ancestors(areas, owners)
    hashes = {
        "AreaTable.csv": hashlib.sha256(area_csv).hexdigest(),
        "LiquidType.csv": hashlib.sha256(liquid_csv).hexdigest(),
        "Map.csv": hashlib.sha256(map_csv).hexdigest(),
    }
    out = {"Areas.lua": emit_areas(build, areas, keep)}
    for m in maps:
        out[f"Borders{m.map_id}.lua"] = emit_borders(build, m)
    out["MANIFEST.json"] = emit_manifest(build, product, maps, areas, len(keep), hashes)
    return out


# --------------------------------------------------------------------------
# CLI


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, required=True, help="Polestar CASC cache root (read only)")
    parser.add_argument("--build", required=True, help="client build, e.g. 1.60.1.70450")
    parser.add_argument("--product", required=True, help="CASC product, e.g. wow_classic_beta")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="output directory (default Surveyor/Data)")
    parser.add_argument("--check", action="store_true", help="compare with the committed output; write nothing")
    args = parser.parse_args(argv)

    wago = args.sources / "wago" / args.build
    casc = args.sources / "casc" / args.product / args.build

    def read_file(fdid: int) -> bytes:
        path = casc / f"{fdid}.blp"
        if not path.is_file():
            raise BuildError(f"FileDataID {fdid} is not in the cache ({path.name}); nothing is fetched")
        return path.read_bytes()

    try:
        outputs = generate(
            args.build,
            args.product,
            (wago / "Map.csv").read_bytes(),
            (wago / "AreaTable.csv").read_bytes(),
            (wago / "LiquidType.csv").read_bytes(),
            read_file,
        )
    except (BuildError, OSError, KeyError, ValueError) as error:
        print(f"surveyor-data: {error}", file=sys.stderr)
        return 2

    if args.check:
        drift = []
        for name in OUTPUT_NAMES:
            path = args.out / name
            if not path.is_file() or path.read_bytes() != outputs[name]:
                drift.append(name)
        if drift:
            print("surveyor-data: drift in " + ", ".join(drift), file=sys.stderr)
            return 1
        print("surveyor-data: output matches (" + ", ".join(OUTPUT_NAMES) + ")")
        return 0

    args.out.mkdir(parents=True, exist_ok=True)
    for name in OUTPUT_NAMES:
        (args.out / name).write_bytes(outputs[name])
        print(f"wrote {name} ({len(outputs[name])} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
