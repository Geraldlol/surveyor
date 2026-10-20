"""Unit tests for tools/surveyor-data/build.py on synthetic WDT/ADT bytes and CSV text."""

from __future__ import annotations

import io
import struct
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build  # noqa: E402

MAP_HEADER = (
    "ID,Directory,MapName_lang,MapDescription0_lang,MapDescription1_lang,PvpShortDescription_lang,"
    "PvpLongDescription_lang,Corpse_0,Corpse_1,MapType,InstanceType,ExpansionID,AreaTableID,LoadingScreenID,"
    "TimeOfDayOverride,ParentMapID,CosmeticParentMapID,TimeOffset,MinimapIconScale,CorpseMapID,MaxPlayers,"
    "WindSettingsID,ZmpFileDataID,WdtFileDataID,OceanLiquidTypeID,NavigationMaxDistance,PreloadFileDataID,"
    "Flags_0,Flags_1,Flags_2"
)
AREA_HEADER = (
    "ID,ZoneName,AreaName_lang,ContinentID,ParentAreaID,AreaBit,SoundProviderPref,SoundProviderPrefUnderwater,"
    "AmbienceID,UwAmbience,ZoneMusic,UwZoneMusic,ExplorationLevel,IntroSound,UwIntroSound,FactionGroupMask,"
    "Ambient_multiplier,MountFlags,PvpCombatWorldStateID,WildBattlePetLevelMin,WildBattlePetLevelMax,"
    "WindSettingsID,ContentTuningID,Flags_0,Flags_1,LiquidTypeID_0,LiquidTypeID_1,LiquidTypeID_2,LiquidTypeID_3"
)


def map_csv(wdt0: int, wdt1: int) -> str:
    return "\n".join(
        [
            MAP_HEADER,
            f'0,Azeroth,"Eastern Kingdoms",,,,,0,0,1,0,0,0,4,-1,-1,-1,0,1,-1,0,136,804940,{wdt0},1250,0,0,1,2,3',
            "13,test,Testing,,,,,0,0,1,0,0,0,0,-1,-1,-1,0,1,-1,0,0,0,999,0,0,0,0,0,0",
            f"1,Kalimdor,Kalimdor,,,,,0,0,1,0,0,0,3,-1,-1,-1,0,1,-1,0,136,804935,{wdt1},1250,0,0,1,2,3",
        ]
    ) + "\n"


def area_row(aid, name, continent, parent, bit, level) -> str:
    rest = ",".join(["0"] * 16)
    return f"{aid},Z{aid},{name},{continent},{parent},{bit},0,0,0,0,0,0,{level},{rest}"


def area_csv(rows) -> str:
    return "\n".join([AREA_HEADER] + [area_row(*r) for r in rows]) + "\n"


def chunk(tag: str, data: bytes) -> bytes:
    return tag[::-1].encode("ascii") + struct.pack("<I", len(data)) + data


def mcnk(col, row, ix, iy, area, shift=0.0) -> bytes:
    head = bytearray(128)
    struct.pack_into("<II", head, 0x04, ix, iy)
    struct.pack_into("<I", head, 0x34, area)
    gx, gy = col * 16 + ix, row * 16 + iy
    struct.pack_into("<fff", head, 0x68, build.ORIGIN - gy * build.CHUNK + shift, build.ORIGIN - gx * build.CHUNK, 0.0)
    return chunk("MCNK", bytes(head) + b"\0" * 16)


def adt(col, row, area_of, count=256, shift=0.0) -> bytes:
    """area_of(gx, gy) -> areaId. Chunks are written in reverse index order to prove indexX/indexY are read."""
    body = chunk("MVER", struct.pack("<I", 18)) + chunk("MHDR", b"\0" * 64) + chunk("MH2O", b"")
    cells = [(ix, iy) for iy in range(16) for ix in range(16)][::-1][:count]
    for n, (ix, iy) in enumerate(cells):
        body += mcnk(col, row, ix, iy, area_of(col * 16 + ix, row * 16 + iy), shift if n == 0 else 0.0)
    return body


def wdt(tiles: dict) -> bytes:
    maid = bytearray(64 * 64 * 32)
    for (col, row), fdid in tiles.items():
        struct.pack_into("<IIIIIIII", maid, (row * 64 + col) * 32, fdid, fdid + 1, fdid + 2, 0, 0, 0, 0, 0)
    return (
        chunk("MVER", struct.pack("<I", 18))
        + chunk("MPHD", b"\0" * 32)
        + chunk("MAIN", b"\0" * (64 * 64 * 8))
        + chunk("MAID", bytes(maid))
    )


def signed_area(loop) -> int:
    return sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(loop, loop[1:] + loop[:1]))


class ParsingTests(unittest.TestCase):
    def test_chunk_tags_are_stored_reversed(self):
        buf = chunk("MCNK", b"abc") + chunk("MVER", b"")
        self.assertEqual(build.read_chunks(buf), [("MCNK", b"abc"), ("MVER", b"")])
        self.assertEqual(buf[:4], b"KNCM")

    def test_chunk_overrun_is_an_error(self):
        with self.assertRaises(build.BuildError):
            build.read_chunks(b"KNCM" + struct.pack("<I", 10) + b"abc")

    def test_mcnk_header_offsets(self):
        data = build.read_chunks(mcnk(32, 48, 5, 7, 87))[0][1]
        ix, iy, area, wx, wy = build.parse_mcnk_header(data)
        self.assertEqual((ix, iy, area), (5, 7, 87))
        self.assertAlmostEqual(wx, 17066.6667 - (48 * 16 + 7) * 33.33333, places=1)
        self.assertAlmostEqual(wy, 17066.6667 - (32 * 16 + 5) * 33.33333, places=1)

    def test_tile_32_48_chunk_0_sits_at_known_position(self):
        data = build.read_chunks(mcnk(32, 48, 0, 0, 1))[0][1]
        _, _, _, wx, wy = build.parse_mcnk_header(data)
        self.assertAlmostEqual(wx, -8533.333, places=2)
        self.assertAlmostEqual(wy, 0.0, places=2)

    def test_maid_lists_present_tiles(self):
        tiles = build.parse_maid(wdt({(32, 48): 1000, (5, 2): 2000, (63, 63): 3000}))
        self.assertEqual(tiles, [(5, 2, 2000), (32, 48, 1000), (63, 63, 3000)])

    def test_maid_missing_is_an_error(self):
        with self.assertRaises(build.BuildError):
            build.parse_maid(chunk("MVER", b"\0" * 4))

    def test_adt_reads_256_chunks_into_global_grid(self):
        chunks = build.parse_adt(adt(2, 3, lambda gx, gy: gx * 10000 + gy), 2, 3)
        self.assertEqual(len(chunks), 256)
        self.assertEqual({(gx, gy) for gx, gy, _ in chunks}, {(32 + i, 48 + j) for i in range(16) for j in range(16)})
        self.assertTrue(all(a == gx * 10000 + gy for gx, gy, a in chunks))

    def test_adt_with_wrong_chunk_count_is_an_error(self):
        with self.assertRaises(build.BuildError):
            build.parse_adt(adt(0, 0, lambda gx, gy: 1, count=255), 0, 0)

    def test_adt_position_off_the_grid_is_an_error(self):
        with self.assertRaises(build.BuildError):
            build.parse_adt(adt(0, 0, lambda gx, gy: 1, shift=1.0), 0, 0)

    def test_map_csv_reads_wdt_by_header_name(self):
        self.assertEqual(build.read_map_wdts(map_csv(775971, 782779)), {0: 775971, 1: 782779})

    def test_area_csv_fields(self):
        areas = build.read_areas(area_csv([(87, "Goldshire", 0, 12, 548, 5), (9, '"Say ""hi"", Northshire"', 0, 12, 125, 0)]))
        self.assertEqual(areas[87], build.Area(87, "Goldshire", 0, 12, 548, 5))
        self.assertEqual(areas[9].name, 'Say "hi", Northshire')


class TracingTests(unittest.TestCase):
    def assertSimple(self, loops):
        for loop in loops:
            self.assertGreaterEqual(len(loop), 4)
            self.assertEqual(len(set(loop)), len(loop), f"loop revisits a vertex: {loop}")
            for a, b in zip(loop, loop[1:] + loop[:1]):
                self.assertTrue(a[0] == b[0] or a[1] == b[1], "edges are axis-aligned")
                self.assertNotEqual(a, b)
            for p, v, n in zip(loop[-1:] + loop[:-1], loop, loop[1:] + loop[:1]):
                self.assertFalse(p[0] == v[0] == n[0] or p[1] == v[1] == n[1], f"collinear vertex {v}")

    def test_single_chunk(self):
        loops = build.trace_loops({(5, 7)})
        self.assertEqual(loops, [[(5, 7), (6, 7), (6, 8), (5, 8)]])
        self.assertGreater(signed_area(loops[0]), 0)

    def test_two_by_two_block(self):
        loops = build.trace_loops({(0, 0), (1, 0), (0, 1), (1, 1)})
        self.assertEqual(loops, [[(0, 0), (2, 0), (2, 2), (0, 2)]])

    def test_l_shape(self):
        loops = build.trace_loops({(0, 0), (0, 1), (1, 1)})
        self.assertEqual(loops, [[(0, 0), (1, 0), (1, 1), (2, 1), (2, 2), (0, 2)]])
        self.assertSimple(loops)

    def test_ring_with_hole_gives_two_loops(self):
        cells = {(x, y) for x in range(3) for y in range(3)} - {(1, 1)}
        loops = build.trace_loops(cells)
        self.assertEqual(loops, [[(0, 0), (3, 0), (3, 3), (0, 3)], [(1, 1), (1, 2), (2, 2), (2, 1)]])
        self.assertGreater(signed_area(loops[0]), 0)
        self.assertLess(signed_area(loops[1]), 0)
        self.assertSimple(loops)

    def test_collinear_edges_merge(self):
        loops = build.trace_loops({(x, 4) for x in range(10, 15)})
        self.assertEqual(loops, [[(10, 4), (15, 4), (15, 5), (10, 5)]])

    def test_diagonal_cells_keep_to_their_own_cell(self):
        loops = build.trace_loops({(0, 0), (1, 1)})
        self.assertEqual(loops, [[(0, 0), (1, 0), (1, 1), (0, 1)], [(1, 1), (2, 1), (2, 2), (1, 2)]])

    def test_hole_pinched_to_the_outside_splits_into_simple_loops(self):
        cells = {(x, y) for x in range(3) for y in range(3)} - {(1, 1), (2, 2)}
        loops = build.trace_loops(cells)
        self.assertEqual(
            loops,
            [[(0, 0), (3, 0), (3, 2), (2, 2), (2, 3), (0, 3)], [(1, 1), (1, 2), (2, 2), (2, 1)]],
        )
        self.assertGreater(signed_area(loops[0]), 0)
        self.assertLess(signed_area(loops[1]), 0)
        self.assertSimple(loops)

    def test_two_holes_pinched_together_split_into_simple_loops(self):
        cells = {(x, y) for x in range(4) for y in range(4)} - {(1, 1), (2, 2)}
        loops = build.trace_loops(cells)
        self.assertEqual(len(loops), 3)
        self.assertEqual(sum(1 for lp in loops if signed_area(lp) < 0), 2)
        self.assertSimple(loops)

    def test_irregular_shape_loops_are_simple(self):
        cells = {(x, y) for x in range(6) for y in range(5)} - {(2, 2), (3, 2), (5, 0), (0, 4), (4, 4)}
        loops = build.trace_loops(cells)
        self.assertEqual(len(loops), 2)
        self.assertSimple(loops)

    def test_outline_box_and_inner_chunk(self):
        o = build.outline({(0, 0), (0, 1), (1, 1)})
        self.assertEqual((o.x0, o.y0, o.x1, o.y1, o.chunks), (0, 0, 2, 2, 3))
        self.assertIn((o.px, o.py), {(0, 0), (0, 1), (1, 1)})
        self.assertEqual(o.vertices, 6)


AREAS = [
    (9, '"Northshire Valley"', 0, 12, 125, 0),
    (12, '"Elwynn Forest"', 0, 0, 126, 0),
    (87, "Goldshire", 0, 12, 548, 5),
    (88, "Deep", 0, 87, 549, 7),
    (14, "Durotar", 1, 0, 200, 0),
    (500, "CopyTown", 1, 0, 201, 3),  # owned on map 0: another continent
    (600, "LoopA", 0, 601, 1, 1),
    (601, "LoopB", 0, 600, 2, 1),
]


class ModelTests(unittest.TestCase):
    def setUp(self):
        self.areas = build.read_areas(area_csv(AREAS))

    def test_root_zone_walks_parents(self):
        self.assertEqual(build.root_zone(self.areas, 88), 12)
        self.assertEqual(build.root_zone(self.areas, 12), 12)
        self.assertEqual(build.root_zone(self.areas, 600), 600, "a cycle past 8 hops is its own root")

    def test_roll_up_and_skips(self):
        chunks = [(0, 0, 9), (1, 0, 87), (2, 0, 88), (3, 0, 0), (4, 0, 777), (5, 0, 777), (6, 0, 778), (7, 0, 500)]
        m = build.build_map(0, 100, [(0, 0, chunks)], self.areas)
        self.assertEqual(sorted(m.borders), [9, 87, 88, 500])
        self.assertEqual(sorted(m.zones), [12, 500])
        self.assertEqual(m.zones[12].chunks, 3)
        self.assertEqual(m.zones[12].loops, (((0, 0), (3, 0), (3, 1), (0, 1)),))
        self.assertEqual((m.chunks, m.skipped_zero, m.skipped_missing, m.missing_ids), (8, 1, 3, [777, 778]))
        self.assertEqual((m.other_continent, m.other_continent_ids), (1, [500]))

    def test_ancestors_are_kept(self):
        self.assertEqual(build.with_ancestors(self.areas, {88}), {88, 87, 12})
        self.assertEqual(build.with_ancestors(self.areas, {600}), {600, 601})

    def test_lua_string_escapes(self):
        self.assertEqual(build.lua_string('a"b\\c\ndé'), '"a\\"b\\\\c\\010dé"')
        self.assertEqual(build.lua_string("x\n1"), '"x\\0101"', "three-digit escape so a following digit is not absorbed")


def synthetic_inputs():
    files = {
        100: wdt({(32, 48): 1000}),
        200: wdt({(10, 20): 2000, (11, 20): 2001}),
        1000: adt(32, 48, lambda gx, gy: 0 if gx % 16 == 15 else (9 if gy % 16 < 4 else (87 if gx % 16 < 8 else 88))),
        2000: adt(10, 20, lambda gx, gy: 14 if (gx + gy) % 5 else 0),
        2001: adt(11, 20, lambda gx, gy: 14),
    }
    return map_csv(100, 200).encode(), area_csv(AREAS).encode(), files


class EmitterTests(unittest.TestCase):
    def run_generate(self):
        mcsv, acsv, files = synthetic_inputs()
        return build.generate("1.60.1.70450", "wow_classic_beta", mcsv, acsv, files.__getitem__)

    def test_output_is_stable_across_runs(self):
        first, second = self.run_generate(), self.run_generate()
        self.assertEqual(sorted(first), sorted(build.OUTPUT_NAMES))
        self.assertEqual(first, second)

    def test_output_format(self):
        out = self.run_generate()
        for name, data in out.items():
            text = data.decode("utf-8")
            self.assertNotIn("\r", text, name)
            self.assertTrue(text.endswith("\n"), name)
            for line in text.split("\n"):
                self.assertEqual(line, line.rstrip(), f"{name}: trailing whitespace")
        areas = out["Areas.lua"].decode()
        self.assertIn('\t[87] = { "Goldshire", 12, 5, 548, 0 },\n', areas)
        self.assertIn('\t[12] = { "Elwynn Forest", 0, 0, 126, 0 },\n', areas)
        self.assertNotIn("[600]", areas)
        self.assertTrue(areas.startswith("-- Generated by tools/surveyor-data/build.py from Forever 1.60.1.70450."))
        b0 = out["Borders0.lua"].decode()
        self.assertIn("\nlocal _, ns = ...\n", b0)
        self.assertIn("\nns.Borders[0] = {}\n", b0)
        self.assertIn("\nns.Zones[0][12] = { 512, 768, 527, 784, ", b0)
        ids = [int(line.split("[")[2].split("]")[0]) for line in b0.split("\n") if line.startswith("ns.Borders[0][")]
        self.assertEqual(ids, [9, 87, 88])
        self.assertIn("\nns.Borders[1][14] = { 160, 320, 192, 336, ", out["Borders1.lua"].decode())

    def test_manifest_counts(self):
        import json

        doc = json.loads(self.run_generate()["MANIFEST.json"])
        self.assertEqual(doc["maps"]["0"]["tiles"], 1)
        self.assertEqual(doc["maps"]["0"]["skipped"]["areaZero"], 16)
        self.assertEqual(doc["maps"]["1"]["chunks"], 512)
        self.assertEqual(doc["maps"]["1"]["wdtFileDataID"], 200)
        self.assertEqual(doc["areas"], 5)  # owners 9, 87, 88, 14 plus ancestor 12
        self.assertEqual(doc["maps"]["1"]["zones"], 1)


class CliTests(unittest.TestCase):
    def test_write_then_check(self):
        mcsv, acsv, files = synthetic_inputs()
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "src"
            (src / "wago" / "B").mkdir(parents=True)
            (src / "casc" / "P" / "B").mkdir(parents=True)
            (src / "wago" / "B" / "Map.csv").write_bytes(mcsv)
            (src / "wago" / "B" / "AreaTable.csv").write_bytes(acsv)
            for fdid, data in files.items():
                (src / "casc" / "P" / "B" / f"{fdid}.blp").write_bytes(data)
            out = Path(tmp) / "out"
            args = ["--sources", str(src), "--build", "B", "--product", "P", "--out", str(out)]
            sink = io.StringIO()
            with redirect_stdout(sink), redirect_stderr(sink):
                self.assertEqual(build.main(args + ["--check"]), 1, "nothing written yet")
                self.assertFalse(out.exists(), "--check writes nothing")
                self.assertEqual(build.main(args), 0)
                self.assertEqual(build.main(args + ["--check"]), 0)
                (out / "MANIFEST.json").write_bytes(b"{}\n")
                self.assertEqual(build.main(args + ["--check"]), 1)
                self.assertEqual((out / "MANIFEST.json").read_bytes(), b"{}\n")
                (src / "casc" / "P" / "B" / "2001.blp").unlink()
                self.assertEqual(build.main(args), 2, "a missing cache file is a build error")


if __name__ == "__main__":
    unittest.main()
