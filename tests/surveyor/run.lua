-- Surveyor generated data (Surveyor/Data/*.lua), loaded under Lua 5.1 through
-- a fake addon vararg. Checks structure and a few known AreaTable rows.
-- Also checks Surveyor/Grid.lua and paints Surveyor/Map.lua against a mock client.
-- This verifies offline data and logic, not client loading or drawing.

local passed, failed = 0, 0

local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. "\n" .. err)
    end
end

local ns = {}
for _, file in ipairs({ "Areas.lua", "Borders0.lua", "Borders1.lua" }) do
    local chunk = assert(loadfile("Surveyor/Data/" .. file))
    chunk("Surveyor", ns)
end

local function count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

local function checkEntry(where, id, e)
    local x0, y0, x1, y1, px, py, chunks, loops = e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8]
    local tag = where .. "[" .. id .. "]"
    assert(x0 >= 0 and y0 >= 0 and x1 <= 1024 and y1 <= 1024, tag .. ": box outside 0..1024")
    assert(x0 < x1 and y0 < y1, tag .. ": empty box")
    assert(px >= x0 and px < x1 and py >= y0 and py < y1, tag .. ": inner chunk outside the box")
    assert(type(chunks) == "number" and chunks >= 1, tag .. ": chunk count")
    assert(type(loops) == "table" and #loops >= 1, tag .. ": no loops")
    for li, loop in ipairs(loops) do
        local n = #loop
        assert(n >= 8 and n % 2 == 0, tag .. " loop " .. li .. ": length " .. n)
        local seen = {}
        for i = 1, n, 2 do
            local key = loop[i] * 2048 + loop[i + 1]
            assert(not seen[key], tag .. " loop " .. li .. ": vertex " .. loop[i] .. "," .. loop[i + 1] .. " repeats")
            seen[key] = true
        end
        for i = 1, n, 2 do
            local x, y = loop[i], loop[i + 1]
            assert(x >= x0 and x <= x1 and y >= y0 and y <= y1, tag .. " loop " .. li .. ": vertex outside the box")
            local j = (i + 2 > n) and 1 or i + 2
            assert(not (x == loop[j] and y == loop[j + 1]), tag .. " loop " .. li .. ": repeated consecutive vertex")
        end
    end
end

test("data build is stamped", function()
    equal(ns.DataBuild, "1.60.1.70450", "DataBuild")
end)

test("both continents have borders and zones", function()
    for m = 0, 1 do
        assert(type(ns.Borders[m]) == "table" and count(ns.Borders[m]) > 0, "Borders[" .. m .. "] empty")
        assert(type(ns.Zones[m]) == "table" and count(ns.Zones[m]) > 0, "Zones[" .. m .. "] empty")
    end
end)

test("every id and parent resolves in Areas", function()
    for m = 0, 1 do
        for _, set in ipairs({ ns.Borders[m], ns.Zones[m] }) do
            for id in pairs(set) do
                assert(ns.Areas[id], "id " .. id .. " on map " .. m .. " is not in Areas")
            end
        end
    end
    for id, row in pairs(ns.Areas) do
        local parent = row[2]
        assert(parent == 0 or ns.Areas[parent], "parent " .. parent .. " of " .. id .. " is not in Areas")
        assert(type(row[1]) == "string" and type(row[3]) == "number" and type(row[4]) == "number"
            and type(row[5]) == "number", "row shape of " .. id)
    end
end)

test("every border and zone entry is well formed", function()
    for m = 0, 1 do
        for id, e in pairs(ns.Borders[m]) do
            checkEntry("Borders[" .. m .. "]", id, e)
        end
        for id, e in pairs(ns.Zones[m]) do
            checkEntry("Zones[" .. m .. "]", id, e)
        end
    end
end)

test("known rows: Goldshire, Stormwind City, Orgrimmar", function()
    local g = ns.Areas[87]
    equal(g[1], "Goldshire", "87 name")
    equal(g[2], 12, "87 parent")
    equal(g[3], 5, "87 level")
    equal(g[4], 548, "87 bit")
    equal(g[5], 0, "87 continent")
    assert(ns.Borders[0][87], "Borders[0][87] missing")
    equal(ns.Areas[1519][1], "Stormwind City", "1519 name")
    assert(ns.Borders[1][1637], "Borders[1][1637] (Orgrimmar) missing")
    equal(ns.Areas[1637][1], "Orgrimmar", "1637 name")
end)

test("Elwynn Forest zone covers Goldshire and Northshire", function()
    assert(ns.Zones[0][12], "Zones[0][12] missing")
    assert(ns.Zones[0][12][7] >= ns.Borders[0][87][7] + ns.Borders[0][9][7], "zone 12 chunk count")
end)

-- Grid: pure chunk-corner math (Surveyor/Grid.lua), loaded into the data namespace.

assert(loadfile("Surveyor/Grid.lua"))("Surveyor", ns)
local Grid = ns.Grid

local function near(actual, expected, message, tolerance)
    assert(type(actual) == "number" and math.abs(actual - expected) <= (tolerance or 1e-6),
        (message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

test("grid: chunk 0 of tile 32_48 is at wx -8533.333, wy 0", function()
    near(Grid.ORIGIN, 17066.6667, "ORIGIN", 1e-3)
    near(Grid.CHUNK, 33.3333, "CHUNK", 1e-3)
    local wx, wy = Grid.ToWorld(512, 768)
    near(wx, -8533.333, "wx", 1e-3)
    near(wy, 0, "wy")
end)

test("grid: a tile box becomes its world rect", function()
    local minX, maxX, minY, maxY = Grid.BoxToWorld({ 512, 768, 528, 784 })
    near(minX, -9066.667, "minX", 1e-3)
    near(maxX, -8533.333, "maxX", 1e-3)
    near(minY, -533.333, "minY", 1e-3)
    near(maxY, 0, "maxY")
end)

test("grid: rect intersection", function()
    assert(Grid.RectsMeet(0, 10, 0, 10, 5, 15, 5, 15), "overlap")
    assert(Grid.RectsMeet(0, 10, 0, 10, 2, 3, 2, 3), "contained")
    assert(not Grid.RectsMeet(0, 10, 0, 10, 11, 20, 0, 10), "disjoint in x")
    assert(not Grid.RectsMeet(0, 10, 0, 10, 0, 10, -5, -1), "disjoint in y")
    assert(not Grid.RectsMeet(0, 10, 0, 10, 10, 20, 0, 10), "touching edges do not meet")
    assert(Grid.RectsMeet(-1e9, 1e9, -1e9, 1e9, Grid.BoxToWorld(ns.Zones[0][12])), "Elwynn meets everything")
    local a1, a2, a3, a4 = Grid.BoxToWorld(ns.Zones[0][12])
    assert(Grid.RectsMeet(a1, a2, a3, a4, Grid.BoxToWorld(ns.Borders[0][87])), "Elwynn meets Goldshire")
    assert(not Grid.RectsMeet(a1, a2, a3, a4, Grid.BoxToWorld(ns.Borders[1][1637])), "Elwynn misses Orgrimmar")
end)

test("grid: edge iteration closes the loop", function()
    local got = {}
    for i, ax, ay, bx, by in Grid.Edges({ 0, 0, 2, 0, 2, 1, 0, 1 }) do
        got[#got + 1] = table.concat({ i, ax, ay, bx, by }, ",")
    end
    equal(#got, 4, "edge count")
    equal(got[1], "1,0,0,2,0", "first edge")
    equal(got[3], "5,2,1,0,1", "third edge")
    equal(got[4], "7,0,1,0,0", "closing edge")
    for _ in Grid.Edges({}) do
        error("empty loop yielded an edge")
    end
end)

test("grid: mode filter", function()
    assert(Grid.Passes("xp", { "a", 0, 5 }), "xp keeps level 5")
    assert(not Grid.Passes("xp", { "a", 0, 0 }), "xp drops level 0")
    assert(Grid.Passes("all", { "a", 0, 0 }), "all keeps level 0")
    assert(not Grid.Passes("all", nil), "unknown area dropped")
    assert(Grid.Passes("xp", ns.Areas[87]), "Goldshire pays XP")
end)

test("grid: linear world-to-map and the off-map edge test", function()
    local x00, y00 = Grid.ToWorld(8, 16)
    local x11, y11 = Grid.ToWorld(16, 24)
    local nx, ny = Grid.WorldToMapLinear(x00, y00, x00, y00, x11, y11)
    near(nx, 0, "corner nx")
    near(ny, 0, "corner ny")
    local wx, wy = Grid.ToWorld(10, 22)
    nx, ny = Grid.WorldToMapLinear(wx, wy, x00, y00, x11, y11)
    near(nx, 0.25, "nx")
    near(ny, 0.75, "ny")
    assert(Grid.EdgeOutside(-0.5, 0.2, -0.1, 0.8), "both left")
    assert(Grid.EdgeOutside(0.2, 1.5, 0.3, 1.1), "both below")
    assert(not Grid.EdgeOutside(-0.5, 0.5, 1.5, 0.5), "crossing the map")
    assert(not Grid.EdgeOutside(-0.5, 0.5, 0.5, -0.5), "outside on different sides")
end)

-- Map: Surveyor/Map.lua against a mock client. A synthetic zone map 100 covers
-- chunk corners gx 8..16, gy 16..24 on continent 0; the canvas is 800x600 at scale 2.

local Region = {}
Region.__index = Region
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:SetStartPoint(point, rel, x, y) self.start = { point, rel, x, y } end
function Region:SetEndPoint(point, rel, x, y) self.finish = { point, rel, x, y } end
function Region:SetColorTexture() end
function Region:SetVertexColor(r, g, b) self.color = { r, g, b } end
function Region:SetTextColor(r, g, b) self.color = { r, g, b } end
function Region:SetAlpha(a) self.alpha = a end
function Region:SetThickness(t) self.thickness = t end
function Region:SetText(t) self.text = t end
function Region:ClearAllPoints() self.point = nil end
function Region:SetPoint(...) self.point = { ... } end
function Region:SetSize(w, h) self.size = { w, h } end
function Region:EnableMouse() end
function Region:SetScript(name, fn) self.scripts[name] = fn end
function Region:RegisterEvent(name) self.events[#self.events + 1] = name end
function Region:GetWidth() return self.width end
function Region:GetHeight() return self.height end
function Region:SetFrameLevel(level) self.level = level end
function Region:GetFrameLevel() return self.level end
function Region:SetFrameStrata(strata) self.strata = strata end
function Region:GetFrameStrata() return self.strata end
function Region:CreateLine(_, layer)
    local l = setmetatable({ layer = layer }, Region)
    self.lines[#self.lines + 1] = l
    return l
end
function Region:CreateFontString(_, layer, template)
    local f = setmetatable({ layer = layer, template = template }, Region)
    self.strings[#self.strings + 1] = f
    return f
end

local function newFrame(parent)
    return setmetatable({ parent = parent, scripts = {}, events = {}, lines = {}, strings = {} }, Region)
end

local mock = { mapID = 100, scale = 2, explored = {}, probes = 0, levelTypes = {} }
mock.levels = {
    GetValidFrameLevel = function(_, levelType)
        mock.levelTypes[#mock.levelTypes + 1] = levelType
        return 42
    end,
}
local canvasMock = newFrame(nil)
canvasMock.width, canvasMock.height = 800, 600
canvasMock.level, canvasMock.strata = 7, "HIGH"
local created = {}
local x00, y00 = Grid.ToWorld(8, 16)
local x11, y11 = Grid.ToWorld(16, 24)
local mapInfo = { [100] = { mapType = 3 }, [200] = { mapType = 2 }, [300] = { mapType = 4 }, [400] = { mapType = 3 } }

local saved = {}
for _, name in ipairs({ "CreateFrame", "CreateVector2D", "WorldMapFrame", "C_Map", "C_MapExplorationInfo" }) do
    saved[name] = _G[name]
end

local function installMocks()
    _G.CreateVector2D = function(x, y) return { x = x, y = y } end
    _G.CreateFrame = function(_, _, parent)
        local f = newFrame(parent)
        created[#created + 1] = f
        return f
    end
    _G.WorldMapFrame = {
        GetCanvas = function() return canvasMock end,
        GetMapID = function() return mock.mapID end,
        GetCanvasScale = function() return mock.scale end,
        GetPinFrameLevelsManager = function() return mock.levels end,
    }
    _G.C_Map = {
        GetMapInfo = function(id) return mapInfo[id] end,
        GetWorldPosFromMapPos = function(_, pos)
            return 0, { x = x00 + pos.y * (x11 - x00), y = y00 + pos.x * (y11 - y00) }
        end,
        GetMapPosFromWorldPos = function(_, pos, id)
            return id, { x = (pos.y - y00) / (y11 - y00), y = (pos.x - x00) / (x11 - x00) }
        end,
        GetAreaInfo = function() return nil end,
    }
    _G.C_MapExplorationInfo = {
        GetExploredAreaIDsAtPosition = function()
            mock.probes = mock.probes + 1
            return mock.explored
        end,
    }
end

local notices = {}
local sns = {
    Areas = {
        [900] = { "Test Vale", 0, 5, 1, 0 },
        [901] = { "Quiet Hollow", 0, 0, 2, 0 },
        [903] = { "Busy Fields", 0, 5, 3, 0 },
        [950] = { "Test Zone", 0, 0, 4, 0 },
        [999] = { "Far Away", 0, 5, 5, 0 },
    },
    Borders = { [0] = {
        [900] = { 10, 20, 12, 22, 10, 20, 4, { { 10, 20, 12, 20, 12, 22, 10, 22 } } },
        [901] = { 13, 17, 14, 18, 13, 17, 1, { { 13, 17, 14, 17, 14, 18, 13, 18 } } },
        [999] = { 100, 100, 101, 101, 100, 100, 1, { { 100, 100, 101, 100, 101, 101, 100, 101 } } },
    } },
    Zones = { [0] = {
        [950] = { 8, 16, 16, 24, 9, 17, 64, { { 9, 17, 15, 17, 15, 23 } } },
    } },
    Settings = { enabled = true, mode = "xp", names = true, thickness = 2 },
    Print = function(msg) notices[#notices + 1] = msg end,
}

local function loadMap(target)
    assert(loadfile("Surveyor/Grid.lua"))("Surveyor", target)
    assert(loadfile("Surveyor/Map.lua"))("Surveyor", target)
    return target.Map
end

local function shown(list)
    local out = {}
    for _, r in ipairs(list) do
        if r.shown then
            out[#out + 1] = r
        end
    end
    return out
end

local function sameColor(r, rgb, alpha, message)
    near(r.color[1], rgb[1], message .. " r")
    near(r.color[2], rgb[2], message .. " g")
    near(r.color[3], rgb[3], message .. " b")
    near(r.alpha, alpha, message .. " alpha")
end

local GOLD, GREEN, WHITE = { 1, 0.82, 0.2 }, { 0.4, 0.75, 0.45 }, { 0.9, 0.9, 0.9 }
local Map, layer

test("map: a missing client API leaves the layer off", function()
    installMocks()
    _G.WorldMapFrame = nil
    local M = loadMap({ Settings = sns.Settings })
    equal(M.Init(), false, "Init without WorldMapFrame")
    equal(M.IsActive(), false, "IsActive")
    M.Paint()
    equal(#created, 0, "frames created")
end)

test("map: one xp area on a zone map paints four gold edges and its name", function()
    installMocks()
    Map = loadMap(sns)
    equal(Map.Init(), true, "Init")
    layer = created[1]
    equal(layer.parent, canvasMock, "layer parent")
    equal(mock.levelTypes[1], "PIN_FRAME_LEVEL_MAP_HIGHLIGHT", "pin level type requested")
    equal(layer.level, 42, "layer frame level from the pin levels manager")
    equal(layer.strata, "HIGH", "layer strata follows the canvas")
    equal(layer.events[1], "MAP_EXPLORATION_UPDATED", "first event")
    equal(#layer.events, 4, "events registered")
    Map.Paint()
    equal(layer.size[1], 800, "layer width")
    equal(layer.size[2], 600, "layer height")
    local ls = shown(layer.lines)
    equal(#ls, 4, "lines shown")
    local expected = { { 200, -300, 400, -300 }, { 400, -300, 400, -450 }, { 400, -450, 200, -450 }, { 200, -450, 200, -300 } }
    for i, e in ipairs(expected) do
        local l = ls[i]
        equal(l.layer, "ARTWORK", "line layer")
        equal(l.start[1], "TOPLEFT", "start anchor")
        equal(l.start[2], layer, "start relative")
        near(l.start[3], e[1], "edge " .. i .. " x1")
        near(l.start[4], e[2], "edge " .. i .. " y1")
        near(l.finish[3], e[3], "edge " .. i .. " x2")
        near(l.finish[4], e[4], "edge " .. i .. " y2")
        near(l.thickness, 1, "thickness 2 / scale 2")
        sameColor(l, GOLD, 0.9, "edge " .. i)
    end
    local fs = shown(layer.strings)
    equal(#fs, 1, "labels shown")
    equal(fs[1].text, "Test Vale", "label falls back to the enUS name")
    equal(fs[1].point[1], "CENTER", "label anchor")
    near(fs[1].point[4], 250, "label x")
    near(fs[1].point[5], -337.5, "label y")
    sameColor(fs[1], GOLD, 0.9, "label")
end)

test("map: exploration events repaint after the throttle; explored areas turn green", function()
    mock.explored = { 900 }
    layer.scripts.OnEvent(layer, "MAP_EXPLORATION_UPDATED")
    layer.scripts.OnUpdate(layer, 0.05)
    sameColor(shown(layer.lines)[1], GOLD, 0.9, "before the throttle")
    layer.scripts.OnUpdate(layer, 0.06)
    for _, l in ipairs(shown(layer.lines)) do
        sameColor(l, GREEN, 0.55, "explored edge")
    end
    local probes = mock.probes
    layer.scripts.OnUpdate(layer, 0.2)
    equal(mock.probes, probes, "no repaint when nothing changed")
    mock.explored = { 12345 }
    layer.scripts.OnEvent(layer, "MAP_EXPLORATION_UPDATED")
    layer.scripts.OnUpdate(layer, 0.2)
    sameColor(shown(layer.lines)[1], GREEN, 0.55, "unknown id counts as explored")
    mock.explored = { 901 }
    layer.scripts.OnEvent(layer, "MAP_EXPLORATION_UPDATED")
    layer.scripts.OnUpdate(layer, 0.2)
    sameColor(shown(layer.lines)[1], GOLD, 0.9, "another known area only")
    mock.explored = {}
    layer.scripts.OnEvent(layer, "MAP_EXPLORATION_UPDATED")
    layer.scripts.OnUpdate(layer, 0.2)
end)

test("map: all mode adds the level-0 area; xp mode hides the leftovers", function()
    sns.Settings.mode = "all"
    Map.Invalidate()
    layer.scripts.OnUpdate(layer, 0.2)
    equal(#shown(layer.lines), 8, "lines in all mode")
    equal(#shown(layer.strings), 2, "labels in all mode")
    sns.Settings.mode = "xp"
    Map.Invalidate()
    Map.Paint()
    equal(#shown(layer.lines), 4, "lines in xp mode")
    equal(#layer.lines, 8, "pool kept")
    for i = 5, 8 do
        equal(layer.lines[i].shown, false, "leftover line " .. i)
    end
    equal(layer.strings[2].shown, false, "leftover label")
    sns.Settings.names = false
    Map.Invalidate()
    Map.Paint()
    equal(#shown(layer.strings), 0, "names off")
    sns.Settings.names = true
end)

test("map: continent maps draw zone outlines in white; other map types draw nothing", function()
    mock.mapID = 200
    Map.Paint()
    local ls = shown(layer.lines)
    equal(#ls, 3, "zone triangle edges")
    sameColor(ls[1], WHITE, 0.7, "zone edge")
    equal(shown(layer.strings)[1].text, "Test Zone", "zone label")
    mock.mapID = 300
    Map.Paint()
    equal(#shown(layer.lines), 0, "dungeon map lines")
    equal(#shown(layer.strings), 0, "dungeon map labels")
    mock.mapID = nil
    Map.Paint()
    equal(#shown(layer.lines), 0, "no map lines")
    mock.mapID = 100
    sns.Settings.enabled = false
    Map.Invalidate()
    Map.Paint()
    equal(#shown(layer.lines), 0, "disabled")
    sns.Settings.enabled = true
end)

test("map: the line cap stops at 8000 with one notice", function()
    local loop = {}
    for i = 1, 4100 do
        loop[#loop + 1] = 13 + (i % 2)
        loop[#loop + 1] = 19
        loop[#loop + 1] = 13 + (i % 2)
        loop[#loop + 1] = 20
    end
    sns.Borders[0][903] = { 13, 19, 15, 21, 13, 19, 1, { loop } }
    mock.mapID = 400
    Map.Paint()
    equal(#shown(layer.lines), 8000, "lines at the cap")
    equal(#layer.lines, 8000, "pool size")
    equal(#notices, 1, "notices")
    Map.Invalidate()
    Map.Paint()
    equal(#notices, 1, "notice is one-time")
    sns.Borders[0][903] = nil
    mock.mapID = 100
end)

test("map: frame level falls back to canvas + 1 without a usable pin levels manager", function()
    installMocks()
    _G.WorldMapFrame.GetPinFrameLevelsManager = nil
    local M = loadMap({ Settings = sns.Settings })
    equal(M.Init(), true, "Init without the manager")
    local f = created[#created]
    equal(f.level, 8, "canvas level + 1")
    equal(f.strata, "HIGH", "strata")
    installMocks()
    _G.WorldMapFrame.GetPinFrameLevelsManager = function()
        return { GetValidFrameLevel = function() error("unknown level type") end }
    end
    M = loadMap({ Settings = sns.Settings })
    equal(M.Init(), true, "Init with a failing manager")
    equal(created[#created].level, 8, "erroring manager falls back")
end)

for name, value in pairs(saved) do
    _G[name] = value
end

print(string.format("SURVEYOR: %d passed, %d failed (data, grid math and a mocked map paint under Lua 5.1; no client execution)", passed, failed))
assert(failed == 0, "Surveyor data tests failed")
