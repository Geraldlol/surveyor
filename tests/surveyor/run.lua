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

local overlaysFile = io.open("Surveyor/Data/Overlays.lua", "r")
if overlaysFile then
    overlaysFile:close()
    test("overlays are well formed", function()
        assert(loadfile("Surveyor/Data/Overlays.lua"))("Surveyor", ns)
        assert(type(ns.Overlays) == "table" and count(ns.Overlays) > 0, "Overlays empty")
        local function integer(v)
            return type(v) == "number" and v == math.floor(v)
        end
        for mapID, list in pairs(ns.Overlays) do
            assert(integer(mapID) and mapID > 0, "map id " .. tostring(mapID))
            assert(type(list) == "table" and #list > 0, "Overlays[" .. mapID .. "] empty")
            for i, o in ipairs(list) do
                local where = "Overlays[" .. mapID .. "][" .. i .. "]"
                assert(type(o) == "table" and #o == 5, where .. " shape")
                -- a few client rows are 0 x 0 (Mulgore 1412 has one)
                assert(integer(o[1]) and o[1] >= 0 and integer(o[2]) and o[2] >= 0, where .. " size")
                assert(integer(o[3]) and integer(o[4]), where .. " offset")
                assert(type(o[5]) == "table", where .. " area ids")
                for _, id in ipairs(o[5]) do
                    assert(integer(id) and id > 0, where .. " area id " .. tostring(id))
                end
            end
        end
    end)
else
    print("SKIP overlays: Surveyor/Data/Overlays.lua not present")
end

local mapAreasFile = io.open("Surveyor/Data/MapAreas.lua", "r")
if mapAreasFile then
    mapAreasFile:close()
    test("map areas name known areas by numeric map id", function()
        assert(loadfile("Surveyor/Data/MapAreas.lua"))("Surveyor", ns)
        assert(type(ns.MapAreas) == "table" and count(ns.MapAreas) > 0, "MapAreas empty")
        for mapID, areaId in pairs(ns.MapAreas) do
            assert(type(mapID) == "number", "map id " .. tostring(mapID))
            assert(type(areaId) == "number" and ns.Areas[areaId], "MapAreas[" .. mapID .. "] = " .. tostring(areaId) .. " not in Areas")
        end
    end)
else
    print("SKIP map areas: Surveyor/Data/MapAreas.lua not present")
end

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

test("grid: point in area with a bbox prefilter and even-odd loops", function()
    local L = { 0, 0, 4, 4, 0, 0, 12, { { 0, 0, 4, 0, 4, 2, 2, 2, 2, 4, 0, 4 } } }
    assert(Grid.Contains(L, 1.5, 1.5), "inside")
    assert(Grid.Contains(L, 3.5, 1.5), "inside the arm")
    assert(not Grid.Contains(L, 3.5, 3.5), "in the box, outside the loop")
    assert(not Grid.Contains(L, 5.5, 1.5), "outside the box")
    local ring = { 0, 0, 6, 6, 0, 0, 32, { { 0, 0, 6, 0, 6, 6, 0, 6 }, { 2, 2, 2, 4, 4, 4, 4, 2 } } }
    assert(Grid.Contains(ring, 1.5, 3.5), "ring")
    assert(not Grid.Contains(ring, 3.5, 3.5), "hole")
    assert(Grid.Contains(ring, 5.5, 5.5), "ring corner")
    local g = ns.Borders[0][87]
    assert(Grid.Contains(g, g[5] + 0.5, g[6] + 0.5), "Goldshire contains its interior chunk")
end)

test("grid: overlap ratio, root walk and the inverse conversion", function()
    near(Grid.OverlapRatio(0, 10, 0, 10, 5, 15, 0, 10), 0.5, "half")
    near(Grid.OverlapRatio(0, 10, 0, 10, 2, 3, 2, 3), 1, "inside")
    near(Grid.OverlapRatio(0, 10, 0, 10, 20, 30, 0, 10), 0, "disjoint")
    near(Grid.OverlapRatio(0, 10, 0, 10, 2, 2, 0, 10), 0, "empty box")
    local areas = { [1] = { "a", 0 }, [2] = { "b", 1 }, [3] = { "c", 2 }, [10] = { "x", 11 }, [11] = { "y", 10 } }
    equal(Grid.RootOf(areas, 3), 1, "two hops")
    equal(Grid.RootOf(areas, 1), 1, "root of a root")
    equal(Grid.RootOf(areas, 10), nil, "cycle")
    equal(Grid.RootOf(areas, 99), nil, "unknown id")
    equal(Grid.RootOf(ns.Areas, 87), 12, "Goldshire is in Elwynn")
    local gx, gy = Grid.FromWorld(Grid.ToWorld(10.5, 20.25))
    near(gx, 10.5, "FromWorld gx")
    near(gy, 20.25, "FromWorld gy")
end)

-- Map: Surveyor/Map.lua against a mock client. A synthetic zone map 100 covers
-- chunk corners gx 8..16, gy 16..24 on continent 0; the canvas is 800x600 at scale 2.

local mock = {
    mapID = 100, scale = 2, explored = {}, probes = 0, textures = {}, textureCalls = 0, levelTypes = {}, texture = true,
}
local Region = {}
Region.__index = Region
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:SetStartPoint(point, rel, x, y) self.start = { point, rel, x, y } end
function Region:SetEndPoint(point, rel, x, y) self.finish = { point, rel, x, y } end
function Region:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
function Region:SetTexture(path)
    if mock.texture == "error" then
        error("bad texture")
    end
    if mock.texture == false then
        return false
    end
    self.texture = path
    return true
end
function Region:SetVertexColor(r, g, b) self.color = { r, g, b } end
function Region:SetTextColor(r, g, b) self.color = { r, g, b } end
function Region:SetAlpha(a) self.alpha = a end
function Region:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end
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
local mapInfo = {
    [100] = { mapType = 3 }, [200] = { mapType = 2 }, [300] = { mapType = 4 }, [400] = { mapType = 3 }, [600] = { mapType = 3 },
    [700] = { mapType = 3 },
}

local saved = {}
for _, name in ipairs({ "CreateFrame", "CreateVector2D", "WorldMapFrame", "C_Map", "C_MapExplorationInfo", "GetSubZoneText", "GetZoneText" }) do
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
        GetExploredMapTextures = function()
            mock.textureCalls = mock.textureCalls + 1
            return mock.textures
        end,
    }
end

local notices = {}
local sns = {
    Areas = {
        [900] = { "Test Vale", 950, 5, 1, 0 },
        [901] = { "Quiet Hollow", 950, 0, 2, 0 },
        [903] = { "Busy Fields", 950, 5, 3, 0 },
        [960] = { "Next Zone", 0, 0, 6, 0 },
        [961] = { "Border Post", 960, 5, 7, 0 },
        [950] = { "Test Zone", 0, 0, 4, 0 },
        [999] = { "Far Away", 0, 5, 5, 0 },
    },
    Borders = { [0] = {
        [900] = { 10, 20, 12, 22, 10, 20, 4, { { 10, 20, 12, 20, 12, 22, 10, 22 } } },
        [901] = { 13, 17, 14, 18, 13, 17, 1, { { 13, 17, 14, 17, 14, 18, 13, 18 } } },
        [999] = { 100, 100, 101, 101, 100, 100, 1, { { 100, 100, 101, 100, 101, 101, 100, 101 } } },
        [961] = { 15, 18, 16, 19, 15, 18, 1, { { 15, 18, 16, 18, 16, 19, 15, 19 } } },
    } },
    Zones = { [0] = {
        [950] = { 8, 16, 16, 24, 9, 17, 64, { { 9, 17, 15, 17, 15, 23 } } },
        -- 12.5% of its box lies on the test maps; its loop is entirely off them
        [960] = { 14, 16, 30, 24, 20, 20, 128, { { 17, 17, 29, 17, 29, 23, 17, 23 } } },
    } },
    -- Map 100's overlays: Test Vale, Quiet Hollow, and one revealing 25 ids the data lacks.
    Overlays = { [100] = {
        { 256, 128, 10, 20, { 900 } },
        { 128, 64, 300, 40, { 901 } },
        { 64, 64, 500, 500, {} },
    } },
    Settings = { enabled = true, mode = "xp", names = true, thickness = 2 },
    Print = function(msg) notices[#notices + 1] = msg end,
}

for id = 1001, 1025 do
    table.insert(sns.Overlays[100][3][5], id)
end
local OV = sns.Overlays[100]

-- The client's explored-texture entry for a baked overlay.
local function tex(o)
    return { textureWidth = o[1], textureHeight = o[2], offsetX = o[3], offsetY = o[4] }
end

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

local GOLD, GREEN, BLACK = { 1, 0.82, 0.2 }, { 0.4, 0.75, 0.45 }, { 0, 0, 0 }
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
    equal(#ls, 8, "lines shown: four edges over four shadows")
    local expected = { { 200, -300, 400, -300 }, { 400, -300, 400, -450 }, { 400, -450, 200, -450 }, { 200, -450, 200, -300 } }
    for i, e in ipairs(expected) do
        for _, l in ipairs({ ls[2 * i - 1], ls[2 * i] }) do
            equal(l.layer, "ARTWORK", "line layer")
            equal(l.texture, nil, "no file texture")
            equal(table.concat(l.colorTexture, ","), "1,1,1,1", "solid colour texture")
            equal(l.start[1], "TOPLEFT", "start anchor")
            equal(l.start[2], layer, "start relative")
            near(l.start[3], e[1], "edge " .. i .. " x1")
            near(l.start[4], e[2], "edge " .. i .. " y1")
            near(l.finish[3], e[3], "edge " .. i .. " x2")
            near(l.finish[4], e[4], "edge " .. i .. " y2")
        end
        near(ls[2 * i - 1].thickness, 1.5, "shadow thickness (2 + 1) / scale 2")
        sameColor(ls[2 * i - 1], BLACK, 0.5, "shadow " .. i)
        equal(ls[2 * i - 1].sublevel, 0, "shadow " .. i .. " sublevel")
        near(ls[2 * i].thickness, 1, "thickness 2 / scale 2")
        equal(ls[2 * i].sublevel, 1, "edge " .. i .. " sublevel")
        sameColor(ls[2 * i], GOLD, 0.9, "edge " .. i)
    end
    local fs = shown(layer.strings)
    equal(#fs, 1, "labels shown")
    equal(fs[1].text, "Test Vale", "label falls back to the enUS name")
    equal(fs[1].point[1], "CENTER", "label anchor")
    near(fs[1].point[4], 250, "label x")
    near(fs[1].point[5], -337.5, "label y")
    sameColor(fs[1], GOLD, 0.9, "label")
end)

test("map: explored overlays decide the colour; events and map changes rebuild the set", function()
    local probes = mock.probes
    mock.explored = { 900, 901 }
    mock.textures = { tex(OV[2]) }
    layer.scripts.OnEvent(layer, "MAP_EXPLORATION_UPDATED")
    layer.scripts.OnUpdate(layer, 0.2)
    sameColor(shown(layer.lines)[2], GOLD, 0.9, "overlay absent: gold although the position API names the area")
    sns.Settings.mode = "all"
    Map.Invalidate()
    Map.Paint()
    local ls = shown(layer.lines)
    equal(#ls, 16, "Test Vale and Quiet Hollow")
    sameColor(ls[2], GOLD, 0.9, "Test Vale still gold")
    sameColor(ls[10], GREEN, 0.55, "Quiet Hollow's overlay is explored")
    sns.Settings.mode = "xp"
    Map.Invalidate()
    Map.Paint()
    local calls = mock.textureCalls
    mock.textures = { tex(OV[2]), tex(OV[1]) }
    Map.Invalidate()
    Map.Paint()
    equal(mock.textureCalls, calls, "a settings repaint keeps the set")
    sameColor(shown(layer.lines)[2], GOLD, 0.9, "no event yet: gold")
    layer.scripts.OnEvent(layer, "MAP_EXPLORATION_UPDATED")
    layer.scripts.OnUpdate(layer, 0.05)
    sameColor(shown(layer.lines)[2], GOLD, 0.9, "before the throttle")
    layer.scripts.OnUpdate(layer, 0.06)
    equal(mock.textureCalls, calls + 1, "one rebuild for the new revision")
    ls = shown(layer.lines)
    for i = 2, #ls, 2 do
        sameColor(ls[i], GREEN, 0.55, "newly explored edge")
        sameColor(ls[i - 1], BLACK, 0.5, "shadow under an explored edge")
    end
    layer.scripts.OnUpdate(layer, 0.2)
    equal(mock.textureCalls, calls + 1, "no rebuild when nothing changed")
    mock.mapID = 200
    layer.scripts.OnUpdate(layer, 0.2)
    mock.mapID = 100
    layer.scripts.OnUpdate(layer, 0.2)
    equal(mock.textureCalls, calls + 2, "returning to the map rebuilds the set")
    equal(mock.probes, probes, "the position API is not asked on a map with baked overlays")
    mock.textures, mock.explored = {}, {}
    layer.scripts.OnEvent(layer, "MAP_EXPLORATION_UPDATED")
    layer.scripts.OnUpdate(layer, 0.2)
    sameColor(shown(layer.lines)[2], GOLD, 0.9, "empty list: gold again")
end)

test("map: a map without baked overlays falls back to the position probe", function()
    mock.mapID = 700
    mock.textures = { tex(OV[1]) }
    mock.explored = { 900 }
    Map.Paint()
    sameColor(shown(layer.lines)[2], GREEN, 0.55, "the position API names the area")
    mock.explored = { 12345 }
    Map.Paint()
    sameColor(shown(layer.lines)[2], GOLD, 0.9, "an unknown id alone no longer counts as explored")
    mock.explored, mock.textures = {}, {}
    mock.mapID = 100
    Map.Paint()
end)

test("map: a missing, failing or listless textures API falls back to the position probe", function()
    local api = _G.C_MapExplorationInfo.GetExploredMapTextures
    mock.explored = { 900 }
    for label, fn in pairs({
        missing = false,
        failing = function() error("no textures") end,
        listless = function() return nil end,
    }) do
        _G.C_MapExplorationInfo.GetExploredMapTextures = fn or nil
        layer.scripts.OnEvent(layer, "MAP_EXPLORATION_UPDATED")
        Map.Paint()
        sameColor(shown(layer.lines)[2], GREEN, 0.55, "textures API " .. label)
    end
    _G.C_MapExplorationInfo.GetExploredMapTextures = api
    mock.explored = {}
    layer.scripts.OnEvent(layer, "MAP_EXPLORATION_UPDATED")
    Map.Paint()
    sameColor(shown(layer.lines)[2], GOLD, 0.9, "textures API back")
end)

test("map: all mode adds the level-0 area; xp mode hides the leftovers", function()
    sns.Settings.mode = "all"
    Map.Invalidate()
    layer.scripts.OnUpdate(layer, 0.2)
    equal(#shown(layer.lines), 16, "lines in all mode")
    equal(#shown(layer.strings), 2, "labels in all mode")
    sns.Settings.mode = "xp"
    Map.Invalidate()
    Map.Paint()
    equal(#shown(layer.lines), 8, "lines in xp mode")
    equal(#layer.lines, 16, "pool kept")
    for i = 9, 16 do
        equal(layer.lines[i].shown, false, "leftover line " .. i)
    end
    equal(layer.strings[2].shown, false, "leftover label")
    sns.Settings.names = false
    Map.Invalidate()
    Map.Paint()
    equal(#shown(layer.strings), 0, "names off")
    sns.Settings.names = true
end)

test("map: continent maps and other non-zone map types draw nothing", function()
    mock.mapID = 200
    Map.Paint()
    equal(#shown(layer.lines), 0, "continent map lines")
    assert(sns.Settings.names, "names on")
    equal(#shown(layer.strings), 0, "continent map labels")
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

-- Busy Fields (903) with a zig-zag loop of 2 * n edges, next to Test Vale's 4.
local function busyFields(n)
    local loop = {}
    for i = 1, n do
        loop[#loop + 1] = 13 + (i % 2)
        loop[#loop + 1] = 19
        loop[#loop + 1] = 13 + (i % 2)
        loop[#loop + 1] = 20
    end
    sns.Borders[0][903] = { 13, 19, 15, 21, 13, 19, 1, { loop } }
end

local function blackLines(list)
    local n = 0
    for _, l in ipairs(shown(list)) do
        if l.color[1] == 0 and l.color[2] == 0 and l.color[3] == 0 then
            n = n + 1
        end
    end
    return n
end

test("map: shadows are left out when they would pass the 8000-line cap", function()
    busyFields(1998) -- 3996 + 4 edges: shadows fit exactly
    mock.mapID = 400
    Map.Paint()
    local ls = shown(layer.lines)
    equal(#ls, 8000, "edges and shadows")
    equal(blackLines(layer.lines), 4000, "one shadow per edge")
    sameColor(ls[7999], BLACK, 0.5, "last shadow")
    near(ls[7999].thickness, 1.5, "last shadow thickness")
    sameColor(ls[8000], GOLD, 0.9, "last edge")
    busyFields(1999) -- 3998 + 4 edges: shadows would make 8004
    Map.Invalidate()
    Map.Paint()
    equal(#shown(layer.lines), 4002, "edges only")
    equal(blackLines(layer.lines), 0, "no shadows")
    equal(#notices, 0, "under the cap without shadows: no notice")
    sns.Borders[0][903] = nil
    mock.mapID = 100
end)

test("map: the line cap stops at 8000 with one notice", function()
    busyFields(4100)
    mock.mapID = 400
    Map.Paint()
    equal(#shown(layer.lines), 8000, "lines at the cap")
    equal(blackLines(layer.lines), 0, "no shadows over the cap")
    equal(#layer.lines, 8000, "pool size")
    equal(#notices, 1, "notices")
    Map.Invalidate()
    Map.Paint()
    equal(#notices, 1, "notice is one-time")
    sns.Borders[0][903] = nil
    mock.mapID = 100
end)

test("map: a zone map hides a neighbouring zone's subzone and draws its own", function()
    sns.Settings.mode = "xp"
    mock.mapID = 100
    Map.Invalidate()
    Map.Paint()
    local ls = shown(layer.lines)
    equal(#ls, 8, "only Test Vale's edges and their shadows")
    for _, l in ipairs(ls) do
        assert(l.start[3] <= 400 + 1e-6 and l.finish[3] <= 400 + 1e-6, "an edge of the neighbour's subzone was drawn")
    end
    local fs = shown(layer.strings)
    equal(#fs, 1, "labels")
    equal(fs[1].text, "Test Vale", "own subzone label")
    local own = sns.Zones[0][950]
    sns.Zones[0][950] = nil
    mock.mapID = 600
    Map.Paint()
    equal(#shown(layer.lines), 16, "no zone of its own: every area meeting the map, neighbour included")
    sns.Zones[0][950] = own
    mock.mapID = 100
    Map.Paint()
end)

test("map: hideExplored leaves out explored areas' lines, shadows and names", function()
    sns.Settings.mode = "all"
    mock.textures = { tex(OV[2]) } -- Quiet Hollow explored, Test Vale not
    layer.scripts.OnEvent(layer, "MAP_EXPLORATION_UPDATED")
    Map.Invalidate()
    Map.Paint()
    equal(#shown(layer.lines), 16, "both areas before hiding")
    equal(#shown(layer.strings), 2, "both names before hiding")
    sns.Settings.hideExplored = true
    Map.Invalidate()
    layer.scripts.OnUpdate(layer, 0.2)
    local ls = shown(layer.lines)
    equal(#ls, 8, "only Test Vale's edges and their shadows")
    for i = 2, #ls, 2 do
        sameColor(ls[i - 1], BLACK, 0.5, "shadow under the unexplored edge")
        sameColor(ls[i], GOLD, 0.9, "unexplored edge")
    end
    local fs = shown(layer.strings)
    equal(#fs, 1, "one name")
    equal(fs[1].text, "Test Vale", "the unexplored area's name")
    sns.Settings.hideExplored = false
    Map.Invalidate()
    layer.scripts.OnUpdate(layer, 0.2)
    ls = shown(layer.lines)
    equal(#ls, 16, "turning it off restores the explored area")
    sameColor(ls[10], GREEN, 0.55, "Quiet Hollow green again")
    equal(#shown(layer.strings), 2, "names restored")
    sns.Settings.mode = "xp"
    mock.textures = {}
    layer.scripts.OnEvent(layer, "MAP_EXPLORATION_UPDATED")
    Map.Paint()
end)

test("map: the shadow budget ignores hidden explored areas", function()
    local noticed = #notices
    busyFields(1999) -- 3998 + 4 edges: shadows for both would make 8004
    mock.mapID = 400 -- no baked overlays: the position probe decides
    mock.explored = { 903 }
    Map.Paint()
    equal(#shown(layer.lines), 4002, "explored Busy Fields shown: edges only")
    equal(blackLines(layer.lines), 0, "no shadows")
    sns.Settings.hideExplored = true
    Map.Invalidate()
    Map.Paint()
    local ls = shown(layer.lines)
    equal(#ls, 8, "Busy Fields hidden: Test Vale's edges and their shadows")
    equal(blackLines(layer.lines), 4, "shadows fit once the hidden edges are not counted")
    sameColor(ls[2], GOLD, 0.9, "Test Vale unexplored")
    equal(#notices, noticed, "no new cap notice")
    sns.Settings.hideExplored = false
    sns.Borders[0][903] = nil
    mock.explored = {}
    mock.mapID = 100
    Map.Invalidate()
    Map.Paint()
end)

test("map: probe reports the player's map, data area and explored ids", function()
    mock.explored = { 900, 4242 }
    mock.textures = { tex(OV[1]), tex(OV[3]), { textureWidth = 1, textureHeight = 1, offsetX = 0, offsetY = 0 } }
    _G.C_Map.GetBestMapForUnit = function() return 100 end
    _G.C_Map.GetPlayerMapPosition = function() return { x = 0.3125, y = 0.5625 } end
    _G.GetSubZoneText = function() return "Test Vale" end
    _G.GetZoneText = function() return "Test Zone" end
    local out = Map.Probe()
    equal(#out, 12, "line count")
    equal(out[1], "map 100 type 3", "map line")
    equal(out[2], "zone: 950 Test Zone (by overlap)", "zone line")
    equal(out[3], "areas on this map: 2", "area count line")
    equal(out[4], "player 0.3125, 0.5625", "position line")
    assert(out[5]:find("world continent 0: x ", 1, true) == 1 and out[5]:find("(grid 10.50, 20.50)", 1, true), out[5])
    equal(out[6], "data area 900 Test Vale: level 5, root 950 Test Zone", "data area line")
    equal(out[7], 'subzone "Test Vale", zone "Test Zone"', "zone text line")
    equal(out[8], "baked overlays for map 100: 3", "baked overlay count")
    equal(out[9], "explored textures from the client: 3, matched 2", "texture counts")
    local parts = { "900 Test Vale" }
    for id = 1001, 1019 do
        parts[#parts + 1] = id .. " " .. id
    end
    parts[#parts + 1] = "..."
    equal(out[10], "explored areas by overlay: " .. table.concat(parts, ", "), "matched ids, 20 then ...")
    equal(out[11], "data area 900 in the explored set: yes", "player's area in the set")
    equal(out[12], "position API not used on this map; the overlays decide", "position API skipped on an overlay map")
    mock.textures = { tex(OV[2]) }
    out = Map.Probe()
    equal(out[10], "explored areas by overlay: 901 Quiet Hollow", "one matched id")
    equal(out[11], "data area 900 in the explored set: no", "player's area not in the set")
    equal(#out, 12, "still no position lines")
    _G.C_Map.GetBestMapForUnit = function() return 700 end
    out = Map.Probe()
    equal(out[2], "zone: 950 Test Zone (by overlap)", "zone line on map 700")
    equal(out[8], "baked overlays for map 700: none", "no baked overlays")
    equal(out[9], "explored ids at player: 2", "position probe follows on a map without overlays")
    equal(out[10], "  900 (Test Vale): in Borders yes, layer verdict explored", "known id on the fallback map")
    equal(out[11], "  4242 (4242): in Borders no, layer verdict n/a", "unknown id on the fallback map")
    _G.C_Map.GetBestMapForUnit = function() return 100 end
    _G.C_MapExplorationInfo = nil
    out = Map.Probe()
    equal(out[9], "C_MapExplorationInfo.GetExploredMapTextures missing", "missing textures API")
    equal(out[#out], "position API not used on this map; the overlays decide", "overlay map never reaches the position API")
    _G.C_Map.GetBestMapForUnit = nil
    out = Map.Probe()
    equal(#out, 1, "missing best map stops early")
    equal(out[1], "C_Map.GetBestMapForUnit missing", "missing best map")
    mock.explored, mock.textures = {}, {}
end)

test("map: without overlay data the layer paints and probes from the position API", function()
    installMocks()
    local M = loadMap({ Settings = sns.Settings, Areas = sns.Areas, Borders = sns.Borders, Zones = sns.Zones })
    equal(M.Init(), true, "Init")
    local f = created[#created]
    mock.explored = { 900 }
    mock.textures = { tex(OV[1]) }
    M.Paint()
    sameColor(shown(f.lines)[2], GREEN, 0.55, "position API decides")
    _G.C_Map.GetBestMapForUnit = function() return 100 end
    _G.C_Map.GetPlayerMapPosition = function() return { x = 0.3125, y = 0.5625 } end
    local out = M.Probe()
    equal(out[8], "baked overlays for map 100: none", "no Overlays table")
    _G.C_MapExplorationInfo = nil
    f.scripts.OnEvent(f, "MAP_EXPLORATION_UPDATED")
    M.Paint()
    sameColor(shown(f.lines)[2], GOLD, 0.9, "no exploration API: gold")
    out = M.Probe()
    equal(out[#out], "C_MapExplorationInfo.GetExploredAreaIDsAtPosition missing", "probe without the API")
    mock.explored, mock.textures = {}, {}
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

test("map: opacity 50 halves the alpha of edges, shadows and names", function()
    installMocks()
    local settings = { enabled = true, mode = "xp", names = true, thickness = 2, opacity = 50 }
    local M = loadMap({ Settings = settings, Areas = sns.Areas, Borders = sns.Borders, Zones = sns.Zones })
    equal(M.Init(), true, "Init")
    local f = created[#created]
    M.Paint()
    local ls = shown(f.lines)
    equal(#ls, 8, "lines shown")
    for i = 2, #ls, 2 do
        sameColor(ls[i - 1], BLACK, 0.25, "shadow at 50%")
        sameColor(ls[i], GOLD, 0.45, "edge at 50%")
    end
    sameColor(shown(f.strings)[1], GOLD, 0.45, "label at 50%")
    settings.opacity = 100
    M.Invalidate()
    f.scripts.OnUpdate(f, 0.2)
    sameColor(shown(f.lines)[2], GOLD, 0.9, "edge back at 100%")
end)

-- The Azshara shape (uiMap 1447): its own zone 1600 overlaps the map rect only 57%
-- (its box reaches north of the map), while a tiny foreign root 1700 lies fully inside.
local function zoneCase(mapAreas)
    installMocks()
    mapInfo[1447] = { mapType = 3 }
    local t = {
        Settings = { enabled = true, mode = "xp", names = true, thickness = 2 },
        Areas = {
            [1600] = { "Big Zone", 0, 0, 1, 0 },
            [1601] = { "Shore", 1600, 5, 2, 0 },
            [1603] = { "Deep Cove", 1601, 5, 3, 0 },
            [1700] = { "The Great Sea", 0, 5, 4, 0 },
        },
        Borders = { [0] = {
            [1601] = { 9, 17, 10, 18, 9, 17, 1, { { 9, 17, 10, 17, 10, 18, 9, 18 } } },
            [1603] = { 11, 18, 12, 19, 11, 18, 1, { { 11, 18, 12, 18, 12, 19, 11, 19 } } },
            [1700] = { 13, 20, 14, 21, 13, 20, 1, { { 13, 20, 14, 20, 14, 21, 13, 21 } } },
        } },
        Zones = { [0] = {
            [1600] = { 8, 10, 16, 24, 9, 17, 2, { { 9, 17, 10, 17, 10, 18, 9, 18 } } },
            [1700] = { 13, 20, 14, 21, 13, 20, 1, { { 13, 20, 14, 20, 14, 21, 13, 21 } } },
        } },
        MapAreas = mapAreas,
    }
    local M = loadMap(t)
    equal(M.Init(), true, "Init")
    local f = created[#created]
    mock.mapID = 1447
    M.Paint()
    local drawn = {}
    for _, fs in ipairs(shown(f.strings)) do
        drawn[#drawn + 1] = fs.text
    end
    table.sort(drawn)
    _G.C_Map.GetBestMapForUnit = function() return 1447 end
    _G.C_Map.GetPlayerMapPosition = function() return nil end
    local out = M.Probe()
    mock.mapID = 100
    return table.concat(drawn, ", "), out, #shown(f.lines)
end

test("map: the baked map assignment picks the zone; its subzones resolve to their root", function()
    local drawn, out, lines = zoneCase({ [1447] = 1600 })
    equal(drawn, "Deep Cove, Shore", "only the assigned zone's areas")
    equal(lines, 16, "two areas: four edges over four shadows each")
    equal(#out, 4, "probe stops at the missing position")
    equal(out[1], "map 1447 type 3", "map line")
    equal(out[2], "zone: 1600 Big Zone (assigned)", "assigned zone line")
    equal(out[3], "areas on this map: 2", "area count line")
    equal(out[4], "player position unavailable (C_Map.GetPlayerMapPosition)", "existing line follows")
    drawn, out = zoneCase({ [1447] = 1603 })
    equal(drawn, "Deep Cove, Shore", "an assigned subzone resolves to its root")
    equal(out[2], "zone: 1600 Big Zone (assigned)", "root named on the probe")
end)

test("map: without a usable assignment the 90% overlap rule picks the zone", function()
    for _, case in ipairs({ { nil, "nil" }, { "x", "non-table" }, { { [1448] = 1600 }, "map missing" },
        { { [1447] = "1600" }, "non-number value" } }) do
        local drawn, out = zoneCase(case[1])
        equal(drawn, "The Great Sea", case[2] .. ": only the foreign root fully inside")
        equal(out[2], "zone: 1700 The Great Sea (by overlap)", case[2] .. ": overlap zone line")
        equal(out[3], "areas on this map: 1", case[2] .. ": area count")
    end
end)

test("map: the probe names no zone when none is chosen or the map draws nothing", function()
    installMocks()
    local M = loadMap({ Settings = sns.Settings, Areas = sns.Areas, Borders = sns.Borders })
    _G.C_Map.GetBestMapForUnit = function() return 100 end
    _G.C_Map.GetPlayerMapPosition = function() return nil end
    local out = M.Probe()
    equal(out[2], "zone: none, every area meeting the map", "no Zones table")
    equal(out[3], "areas on this map: 3", "every area meeting the map, the neighbour's subzone included")
    _G.C_Map.GetBestMapForUnit = function() return 200 end
    out = M.Probe()
    equal(out[2], "zone: none, nothing is drawn on this map", "continent map")
    equal(out[3], "areas on this map: 0", "no areas on a continent map")
end)

-- Core and Options: Surveyor/Core.lua under a LibStub stand-in, Surveyor/Options.lua under a
-- recording Settings API (the shape of tests/witchcraft/options.lua).

local function settingsApi()
    local api = { proxies = {}, controls = {}, opened = {} }
    api.Settings = {
        VarType = { Boolean = "boolean", Number = "number", String = "string" },
        RegisterVerticalLayoutCategory = function(name) api.name = name; return { GetID = function() return 77 end }, {} end,
        RegisterProxySetting = function(_, variable, varType, label, default, get, set)
            local proxy = { variable = variable, varType = varType, label = label, default = default, get = get, set = set }
            api.proxies[#api.proxies + 1] = proxy; api.proxies[variable] = proxy
            return proxy
        end,
        CreateCheckbox = function(_, setting, tooltip) api.controls[#api.controls + 1] = { kind = "checkbox", setting = setting, tooltip = tooltip } end,
        CreateSlider = function(_, setting, options, tooltip)
            api.controls[#api.controls + 1] = { kind = "slider", setting = setting, options = options, tooltip = tooltip }
        end,
        CreateSliderOptions = function(min, max, step) return { min = min, max = max, step = step } end,
        CreateDropdown = function(_, setting, options, tooltip)
            api.controls[#api.controls + 1] = { kind = "dropdown", setting = setting, options = options, tooltip = tooltip }
        end,
        CreateControlTextContainer = function()
            local data = {}
            return { Add = function(_, value, label) data[#data + 1] = { value = value, label = label } end, GetData = function() return data end }
        end,
        RegisterAddOnCategory = function(category) api.registered = category end,
        OpenToCategory = function(id) api.opened[#api.opened + 1] = id end,
    }
    return api
end

local function copy(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = type(v) == "table" and copy(v) or v
    end
    return out
end

-- Loads Core.lua and Options.lua into a fresh namespace and runs OnInitialize with the
-- given global Settings table (nil for a client without the API).
local function loadCore(globalSettings)
    local cns = { revs = 0, refreshes = 0, printed = {} }
    local addon
    local savedStub, savedSettings = _G.LibStub, _G.Settings
    _G.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { NewAddon = function(_, name)
                addon = { name = name }
                function addon:RegisterChatCommand(cmd, method) self.command = { cmd, method } end
                function addon:Print(msg) cns.printed[#cns.printed + 1] = msg end
                function addon:Printf(fmt, ...) self:Print(string.format(fmt, ...)) end
                return addon
            end }
        end
        equal(major, "AceDB-3.0", "library requested")
        return { New = function(_, _, defaults) return { profile = copy(defaults.profile) } end }
    end
    _G.Settings = globalSettings
    local ok, err = pcall(function()
        assert(loadfile("Surveyor/Core.lua"))("Surveyor", cns)
        assert(loadfile("Surveyor/Options.lua"))("Surveyor", cns)
        cns.Map = { Invalidate = function() cns.revs = cns.revs + 1 end }
        cns.MinimapButton = { Refresh = function() cns.refreshes = cns.refreshes + 1 end }
        addon:OnInitialize()
    end)
    _G.LibStub, _G.Settings = savedStub, savedSettings
    assert(ok, err)
    return cns, addon
end

test("options: seven controls in order with their kinds, ranges and choices", function()
    local cns = loadCore(nil)
    local api = settingsApi()
    equal(cns.Options.Register(api), 77, "the page returns the category the panel opens to")
    equal(api.name, "Surveyor", "category name")
    assert(api.registered, "the category is registered as an addon page")
    local want = {
        { "SURVEYOR_ENABLED", "checkbox", "boolean", true },
        { "SURVEYOR_MODE", "dropdown", "string", "xp" },
        { "SURVEYOR_NAMES", "checkbox", "boolean", true },
        { "SURVEYOR_HIDEEXPLORED", "checkbox", "boolean", false },
        { "SURVEYOR_THICKNESS", "slider", "number", 2 },
        { "SURVEYOR_OPACITY", "slider", "number", 100 },
        { "SURVEYOR_MINIMAP", "checkbox", "boolean", true },
    }
    equal(#api.controls, #want, "controls")
    equal(#api.proxies, #want, "proxies")
    for i, w in ipairs(want) do
        local c = api.controls[i]
        equal(c.setting.variable, w[1], "control " .. i .. " variable")
        equal(c.kind, w[2], w[1] .. " kind")
        equal(c.setting.varType, w[3], w[1] .. " type")
        equal(c.setting.default, w[4], w[1] .. " default")
        assert(type(c.tooltip) == "string" and c.tooltip ~= "", w[1] .. " tooltip")
    end
    equal(api.controls[4].setting.label, "Hide explored areas", "hide explored label")
    local thickness, opacity = api.controls[5].options, api.controls[6].options
    equal(table.concat({ thickness.min, thickness.max, thickness.step }, ","), "1,6,1", "thickness range")
    equal(table.concat({ opacity.min, opacity.max, opacity.step }, ","), "10,100,5", "opacity range")
    local choices = api.controls[2].options()
    equal(#choices, 2, "mode choices")
    equal(choices[1].value, "xp", "first choice")
    equal(choices[1].label, "Areas that give XP", "first label")
    equal(choices[2].value, "all", "second choice")
    equal(choices[2].label, "Every area with a map bit", "second label")
end)

test("options: proxies read the profile and write through SetSetting", function()
    local cns = loadCore(nil)
    local api = settingsApi()
    cns.Options.Register(api)
    equal(cns.Settings.opacity, 100, "opacity default")
    api.proxies.SURVEYOR_OPACITY.set(50)
    equal(cns.Settings.opacity, 50, "setter writes the profile")
    equal(cns.revs, 1, "setter bumps the settings revision")
    equal(cns.refreshes, 1, "setter refreshes the minimap button")
    cns.Settings.thickness = 5
    equal(api.proxies.SURVEYOR_THICKNESS.get(), 5, "getter reads the profile")
    api.proxies.SURVEYOR_MODE.set("all")
    equal(api.proxies.SURVEYOR_MODE.get(), "all", "mode round trip")
    local minimap = api.proxies.SURVEYOR_MINIMAP
    equal(minimap.get(), true, "button shown by default")
    cns.Settings.minimap.angle = 135
    minimap.set(false)
    equal(cns.Settings.minimap.hide, true, "unchecking hides the button")
    equal(cns.Settings.minimap.angle, 135, "the angle is kept")
    equal(minimap.get(), false, "getter follows hide")
    equal(cns.revs, 3, "every write bumps the revision")
end)

test("options: /survey explored and the checkbox toggle hideExplored through SetSetting", function()
    local cns, addon = loadCore(nil)
    local api = settingsApi()
    cns.Options.Register(api)
    equal(cns.Settings.hideExplored, false, "off by default")
    addon:HandleSlash("explored")
    equal(cns.Settings.hideExplored, true, "slash turns it on")
    equal(cns.revs, 1, "slash bumps the revision")
    assert(cns.printed[#cns.printed]:find("hide explored on", 1, true), cns.printed[#cns.printed])
    equal(api.proxies.SURVEYOR_HIDEEXPLORED.get(), true, "the checkbox reads the profile")
    api.proxies.SURVEYOR_HIDEEXPLORED.set(false)
    equal(cns.Settings.hideExplored, false, "the checkbox writes the profile")
    equal(cns.revs, 2, "the checkbox bumps the revision")
    addon:HandleSlash("Explored")
    equal(cns.Settings.hideExplored, true, "the verb is case-insensitive")
    addon:HandleSlash("bogus")
    assert(cns.printed[#cns.printed]:find("| explored |", 1, true), "usage names the verb")
end)

test("options: no Settings API registers nothing and /survey config prints a note", function()
    local cns, addon = loadCore(nil)
    equal(cns.Options.Register({}), nil, "a client without the Settings API gets no page")
    equal(cns.Options.Register({ Settings = {} }), nil, "a Settings table without the layout call gets no page")
    addon:HandleSlash("config")
    equal(#cns.printed, 1, "one note")
    assert(cns.printed[1]:find("Settings API", 1, true), "the note names the missing API")
    addon:HandleSlash("off")
    equal(cns.Settings.enabled, false, "slash writes the profile")
    equal(cns.revs, 1, "slash bumps the revision through SetSetting")
end)

test("options: OnInitialize registers the page and /survey config opens it", function()
    local api = settingsApi()
    local cns, addon = loadCore(api.Settings)
    assert(api.registered, "registered at initialise")
    equal(addon.command[1], "survey", "slash command")
    _G.Settings = api.Settings
    local ok, err = pcall(addon.HandleSlash, addon, "config")
    _G.Settings = nil
    assert(ok, err)
    equal(#api.opened, 1, "panel opened once")
    equal(api.opened[1], 77, "opened to the category id")
    equal(#cns.printed, 0, "no note")
end)

for name, value in pairs(saved) do
    _G[name] = value
end

print(string.format("SURVEYOR: %d passed, %d failed (data, grid math and a mocked map paint under Lua 5.1; no client execution)", passed, failed))
assert(failed == 0, "Surveyor data tests failed")
