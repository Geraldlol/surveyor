# Surveyor

A World of Warcraft: Forever addon that shows you exactly where the game will pay you for exploring.

Every area that gives discovery XP has a hard edge, and that edge comes straight from the terrain files. The map is built from 33-yard chunks, and each chunk is tagged with the area it belongs to. Surveyor pulls those tags out of the client data, traces the outline of every area, and draws it on your world map. The line you see is the line the server uses, not an approximation.

## What you get

- On a zone map, every area that awards exploration XP is outlined along its real border. Areas you haven't found yet are gold. Areas you've already discovered are green and faded.
- On a continent map, the top-level zone outlines are drawn instead.
- Area names sit inside each outline.
- By default only areas that actually pay XP are shown. `/survey all` shows every area with a discovery flag, including the ones that only clear fog.

## Commands

```
/survey            show status
/survey on | off   toggle the layer
/survey names      toggle the labels
/survey xp         only areas that pay XP (default)
/survey all        every area with a discovery flag
```

## Install

Copy the `Surveyor` folder into `World of Warcraft/_forever_/Interface/AddOns/` (or wherever your Forever client keeps addons), or install the release zip through your addon manager.

## How the data is made

`tools/surveyor-data/` holds the offline build that reads the client's map files and writes `Surveyor/Data/`. See its README to reproduce it. The committed tables are from client build 1.60.1.70450.

## Known gaps

- Buildings and caves that override the terrain area (WMO interiors) aren't handled yet.
- No minimap drawing yet.
- Forever only. It relies on map APIs that older clients don't have.

## Tests

```
py -3 -m unittest discover -s tools/surveyor-data/tests -v
py -3 tools/run-addon-tests.py tests/surveyor/run.lua
```

The Lua tests run under a real Lua 5.1 (Lupa) with a mocked client; see the header of `tools/run-addon-tests.py` for the one-time install.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE). The bundled Ace3 libraries carry their own license in `Surveyor/Libs/LICENSE-Ace3.txt`.
