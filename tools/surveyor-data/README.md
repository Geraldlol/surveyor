# Surveyor data build

An offline build that turns the Forever client's terrain area grid into the
exploration-border tables the Surveyor addon loads. It reads a local CASC
cache and DB2 CSV exports, never fetches anything, and never writes into
the cache.

## Reproduce

Requires Python 3.10+ and the standard library. From the workspace root:

```powershell
$cache = 'path/to/casc-cache'   # see "Getting the inputs" below
py -3 -m unittest discover -s tools/surveyor-data/tests -v
py -3 tools/surveyor-data/build.py --sources $cache --build 1.60.1.70450 --product wow_classic_beta
py -3 tools/surveyor-data/build.py --sources $cache --build 1.60.1.70450 --product wow_classic_beta --check
py -3 tools/run-addon-tests.py tests/surveyor/run.lua
```

`--check` regenerates in memory, compares all five outputs byte for byte with
`Surveyor/Data/`, writes nothing, and exits 1 on drift. A missing cache file, a
CSV found in neither lookup directory, or a malformed input exits 2.
`--out <dir>` writes elsewhere (the tests use it). `--inputs <dir>` names the
committed inputs root (default: `inputs` next to `build.py`).


## Getting the inputs

The build does not download anything. Fill the cache yourself from
[wago.tools](https://wago.tools): the CSV exports of `Map`, `AreaTable` and
`LiquidType` for the client build go under `wago/<build>/`, and the client
files go under `casc/<product>/<build>/<FileDataID>.blp` (the raw bytes of
`https://wago.tools/api/casc/<FileDataID>?download&version=<build>`). The
files needed are the two WDTs named by `Map.csv` (`WdtFileDataID` of maps 0
and 1) and every root ADT their `MAID` chunks name; a missing file stops the
build with its FileDataID so you can fetch it.
## Input layout

Each `<name>.csv` below is looked up first as `<sources>/wago/<build>/<name>.csv`
and then as `<inputs>/wago/<build>/<name>.csv`; the first file found is used and
its SHA-256 goes into the manifest.

Under `--sources` (a Polestar CASC cache root, read only):

- `wago/<build>/Map.csv`: `WdtFileDataID` of maps 0 (Eastern Kingdoms) and 1
  (Kalimdor), read by header name.
- `wago/<build>/AreaTable.csv`: `ID`, `AreaName_lang`, `ContinentID`,
  `ParentAreaID`, `AreaBit`, `ExplorationLevel`.
- `casc/<product>/<build>/<fdid>.blp`: client files by FileDataID (every file
  has the `.blp` suffix in this cache, whatever its type). The two WDTs and every
  root ADT they list must be present.

Under `--inputs` (committed in this repo, because the cache does not carry them):

- `wago/<build>/WorldMapOverlay.csv`: wago.tools export of the `WorldMapOverlay`
  table for the build. Read by header name: `ID`, `UiMapArtID`, `TextureWidth`,
  `TextureHeight`, `OffsetX`, `OffsetY`, `AreaID_0` to `AreaID_3`.
- `wago/<build>/UiMapXMapArt.csv`: wago.tools export of `UiMapXMapArt` for the
  build: `UiMapArtID`, `UiMapID` (one art can serve several maps or phases).

From the WDT the build reads `MAID` (64 x 64 tiles, root ADT FileDataID first
of 8 u32 per tile). From each root ADT it reads the 256 `MCNK` headers:
`indexX` (0x04), `indexY` (0x08), `areaId` (0x34). The first chunk's position
(0x68) must agree with the grid formula below within 0.01 yd, or the build fails.

Open sea is dropped before tracing. Open-ocean chunks carry the neighbouring
zone's areaId (or a sea zone's), which would draw zone outlines as tile-shaped
rectangles far out to sea. A chunk counts as open sea when its `MH2O` entry has an
ocean instance covering the whole chunk (xOffset 0, yOffset 0, width 8,
height 8) whose `minHeight` is above the chunk's highest terrain vertex (zBase at
MCNK 0x70 plus the largest of the 145 `MCVT` heights). Ocean liquid types come
from `wago/<build>/LiquidType.csv` (`SoundBank == 1` or `Flags & 0x400`). The file
is required. Height alone is not used, because dry land such as Bloodhoof Village
and Un'Goro lies below z 0. An area whose every chunk is open sea is left out of
`ns.Borders` and `ns.Zones` but stays in `ns.Areas`.

## Output format

All files are deterministic: sorted ids, LF, tabs, no timestamps or paths.

- `Surveyor/Data/Areas.lua`: `ns.DataBuild` and
  `ns.Areas[id] = { enUS name, ParentAreaID, ExplorationLevel, AreaBit, ContinentID }`
  for every area that owns a chunk on map 0 or 1, plus all their ancestors.
- `Surveyor/Data/Borders0.lua`, `Borders1.lua`: one statement per area,
  `ns.Borders[map][areaId] = { x0, y0, x1, y1, px, py, chunks, { loop, ... } }`,
  and the same per top-level zone in `ns.Zones[map][zoneId]` (the zone is
  `ParentAreaID` walked to 0, at most 8 hops; otherwise the area is its own zone).
  Coordinates are integer chunk corners on a 1024 x 1024 grid:
  `gx = tileCol * 16 + indexX` (east), `gy = tileRow * 16 + indexY` (south).
  The addon converts a corner to world yards with
  `wx = 17066.6667 - gy * 33.3333`, `wy = 17066.6667 - gx * 33.3333`.
  The box is inclusive-exclusive, `px, py` is the chunk nearest the area's
  centroid, and each loop is a closed flat `{ gx1, gy1, gx2, gy2, ... }` list
  with collinear vertices merged, starting at its minimum vertex. Outer loops run
  counter-clockwise in (gx, gy) (clockwise on screen) and holes the other way;
  cells that touch only at a corner get separate loops.
- `Surveyor/Data/MANIFEST.json`: build, product, input SHA-256s, and per map
  the WDT FileDataID, tile and chunk counts, skipped chunks (area 0 or not in
  AreaTable, with the distinct ids), chunks whose area row names another
  continent, chunks dropped as open sea and the areas left with none (ids and
  names), area and zone counts, and vertex totals.

- `Surveyor/Data/Overlays.lua`: one statement per uiMapID,
  `ns.Overlays[uiMapID] = { { w, h, x, y, { areaId, ... } }, ... }`, where
  `w, h, x, y` are the overlay's `TextureWidth`, `TextureHeight`, `OffsetX`,
  `OffsetY` (the same four numbers `GetExploredMapTextures(uiMapID)` returns)
  and the list holds its non-zero `AreaID_0..3` in column order. The overlay's
  `UiMapArtID` is joined to every `UiMapID` that `UiMapXMapArt` gives it; an
  overlay listed twice for one map (two phase rows) appears once. Maps are
  sorted, and entries sorted by `(w, h, x, y, areas)`. The addon matches the
  client's explored textures against these to learn which areas are explored.
  An overlay whose art has no `UiMapXMapArt` row is dropped and counted first;
  of the rest, one with no area id is dropped and counted. The manifest's
  `overlays` block records `maps`, `entries`, `droppedNoUiMap`, `droppedNoArea`.

Generated Lua carries `-- luacheck: no max line length`; a loop is one line.

## Known gaps

- WMO interiors: indoor areas come from WMOAreaTable overrides, not from the
  terrain grid. They are not joined, so an indoor-only subzone has no border
  and an indoor part of an outdoor area is drawn as its terrain chunk.
- The border is the chunk outline (33.3 yd steps), the same resolution the
  terrain areaId has; it is not smoothed.
- The sea test works per whole chunk. A coastal chunk that is partly ocean, or
  whose terrain peaks above the surface (reefs, rocks), is kept, so coasts stay
  ragged by up to one chunk. Inland water (lakes, rivers, slime, magma) is never
  dropped.
