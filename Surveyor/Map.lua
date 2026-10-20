-- Surveyor world map layer: outlines exploration areas on the world map canvas.
-- Reads ns.Borders, ns.Zones and ns.Areas (generated), ns.Grid, and ns.Settings
-- (a plain table Core points at the profile). No Ace calls, so tests can load it.
local _, ns = ...

local Grid = ns.Grid
local Map = {}
ns.Map = Map

local MAX_LINES = 8000
local THROTTLE = 0.1
local MAP_CONTINENT, MAP_ZONE = 2, 3 -- Enum.UIMapType.Continent, Enum.UIMapType.Zone
local UNEXPLORED = { 1, 0.82, 0.2, 0.9 }
local EXPLORED = { 0.4, 0.75, 0.45, 0.55 }
local ZONE = { 0.9, 0.9, 0.9, 0.7 }
local EVENTS = { "MAP_EXPLORATION_UPDATED", "FOG_OF_WAR_UPDATED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }

local frame, canvas
local lines, linesUsed, drawnLines = {}, 0, 0
local labels, labelsUsed, drawnLabels = {}, 0, 0
local maps = {} -- [uiMapID] = prepared map, or false when nothing is drawn there
local names = {} -- [areaId] = display name
local capNoticed = false
local settingsRev, exploredRev = 0, 0
local keyMap, keyW, keyH, keyScale, keySettings, keyExplored
local sinceCheck = 0

local function notify(msg)
	if ns.Print then
		ns.Print(msg)
	end
end

local function canvasScale()
	local scale = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()
	if type(scale) ~= "number" or scale <= 0 then
		return 1
	end
	return scale
end

-- Per-map preparation: world rect, source table, the ids whose box meets the rect,
-- and empty vertex caches. Computed once per uiMapID.
local function prepare(mapID)
	local info = C_Map.GetMapInfo(mapID)
	local mapType = info and info.mapType
	if mapType ~= MAP_CONTINENT and mapType ~= MAP_ZONE then
		return false
	end
	local c, a = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
	local c2, b = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
	if not (a and b and a.x and a.y and b.x and b.y) or c ~= c2 or (c ~= 0 and c ~= 1) then
		return false
	end
	local isZone = mapType == MAP_ZONE
	local set = isZone and ns.Borders or ns.Zones
	local source = set and set[c]
	if not source then
		return false
	end
	local minX, maxX = math.min(a.x, b.x), math.max(a.x, b.x)
	local minY, maxY = math.min(a.y, b.y), math.max(a.y, b.y)
	local ids = {}
	for id, e in pairs(source) do
		if Grid.RectsMeet(minX, maxX, minY, maxY, Grid.BoxToWorld(e)) then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	return {
		id = mapID, continent = c, zone = isZone, source = source, ids = ids,
		x00 = a.x, y00 = a.y, x11 = b.x, y11 = b.y,
		nx = {}, ny = {}, px = {}, py = {},
	}
end

local function toMap(m, gx, gy)
	local wx, wy = Grid.ToWorld(gx, gy)
	local get = C_Map.GetMapPosFromWorldPos
	if get then
		local _, v = get(m.continent, CreateVector2D(wx, wy), m.id)
		if v and v.x and v.y then
			return v.x, v.y
		end
	end
	return Grid.WorldToMapLinear(wx, wy, m.x00, m.y00, m.x11, m.y11)
end

-- Cached normalised position of an integer chunk corner on map m.
local function vertex(m, gx, gy)
	local k = gx * 1025 + gy
	local nx = m.nx[k]
	if nx then
		return nx, m.ny[k]
	end
	local ny
	nx, ny = toMap(m, gx, gy)
	m.nx[k], m.ny[k] = nx, ny
	return nx, ny
end

-- Cached normalised position of the centre of the entry's interior chunk.
local function probe(m, id, e)
	local px = m.px[id]
	if px then
		return px, m.py[id]
	end
	local py
	px, py = toMap(m, e[5] + 0.5, e[6] + 0.5)
	m.px[id], m.py[id] = px, py
	return px, py
end

local function inside(nx, ny)
	return nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1
end

local function isExplored(m, id, nx, ny)
	local api = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition
	if not api or not inside(nx, ny) then
		return false
	end
	local found = api(m.id, CreateVector2D(nx, ny))
	if type(found) ~= "table" or #found == 0 then
		return false
	end
	local known = false
	for i = 1, #found do
		if found[i] == id then
			return true
		end
		if m.source[found[i]] then
			known = true
		end
	end
	-- Non-empty but naming no area this data knows: the client may report another
	-- granularity, so count it as explored. In-game validation decides.
	return not known
end

local function nameOf(id, row)
	local name = names[id]
	if not name then
		name = C_Map.GetAreaInfo and C_Map.GetAreaInfo(id)
		if type(name) ~= "string" or name == "" then
			name = row and row[1] or tostring(id)
		end
		names[id] = name
	end
	return name
end

local function addLine(ax, ay, bx, by, color, thickness)
	if drawnLines >= MAX_LINES then
		if not capNoticed then
			capNoticed = true
			notify("line limit (" .. MAX_LINES .. ") reached on this map; some borders are not drawn.")
		end
		return false
	end
	drawnLines = drawnLines + 1
	local l = lines[drawnLines]
	if not l then
		l = frame:CreateLine(nil, "ARTWORK")
		l:SetColorTexture(1, 1, 1, 1)
		lines[drawnLines] = l
	end
	l:SetStartPoint("TOPLEFT", frame, ax, -ay)
	l:SetEndPoint("TOPLEFT", frame, bx, -by)
	l:SetThickness(thickness)
	l:SetVertexColor(color[1], color[2], color[3])
	l:SetAlpha(color[4])
	l:Show()
	return true
end

local function addLabel(text, x, y, color)
	drawnLabels = drawnLabels + 1
	local fs = labels[drawnLabels]
	if not fs then
		fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		labels[drawnLabels] = fs
	end
	fs:SetText(text)
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetAlpha(color[4])
	fs:ClearAllPoints()
	fs:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
	fs:Show()
end

-- Draws every edge of an entry's loops; false once the line cap is hit.
local function drawLoops(m, loops, color, w, h, thickness)
	for li = 1, #loops do
		for _, ax, ay, bx, by in Grid.Edges(loops[li]) do
			local x1, y1 = vertex(m, ax, ay)
			local x2, y2 = vertex(m, bx, by)
			if not Grid.EdgeOutside(x1, y1, x2, y2) then
				if not addLine(x1 * w, y1 * h, x2 * w, y2 * h, color, thickness) then
					return false
				end
			end
		end
	end
	return true
end

local function draw(m, s, w, h, thickness)
	for i = 1, #m.ids do
		local id = m.ids[i]
		local e = m.source[id]
		local row = ns.Areas and ns.Areas[id]
		if not m.zone or Grid.Passes(s.mode, row) then
			local px, py = probe(m, id, e)
			local color = ZONE
			if m.zone then
				color = isExplored(m, id, px, py) and EXPLORED or UNEXPLORED
			end
			if not drawLoops(m, e[8], color, w, h, thickness) then
				return
			end
			if s.names and inside(px, py) then
				addLabel(nameOf(id, row), px * w, py * h, color)
			end
		end
	end
end

-- Repaints the layer for the shown map and records the paint key.
function Map.Paint()
	if not frame then
		return
	end
	local s = ns.Settings
	local mapID = WorldMapFrame:GetMapID()
	local w, h = canvas:GetWidth(), canvas:GetHeight()
	local scale = canvasScale()
	keyMap, keyW, keyH, keyScale, keySettings, keyExplored = mapID, w, h, scale, settingsRev, exploredRev
	drawnLines, drawnLabels = 0, 0
	if s and s.enabled and mapID and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
		local m = maps[mapID]
		if m == nil then
			m = prepare(mapID)
			maps[mapID] = m
		end
		if m then
			frame:SetSize(w, h)
			draw(m, s, w, h, (tonumber(s.thickness) or 2) / scale)
		end
	end
	for i = drawnLines + 1, linesUsed do
		lines[i]:Hide()
	end
	for i = drawnLabels + 1, labelsUsed do
		labels[i]:Hide()
	end
	linesUsed, labelsUsed = drawnLines, drawnLabels
end

local function onUpdate(_, elapsed)
	sinceCheck = sinceCheck + (elapsed or 0)
	if sinceCheck < THROTTLE then
		return
	end
	sinceCheck = 0
	if WorldMapFrame:GetMapID() ~= keyMap or canvas:GetWidth() ~= keyW or canvas:GetHeight() ~= keyH
		or canvasScale() ~= keyScale or settingsRev ~= keySettings or exploredRev ~= keyExplored then
		Map.Paint()
	end
end

-- Settings changed: repaint on the next check.
function Map.Invalidate()
	settingsRev = settingsRev + 1
end

function Map.IsActive()
	return frame ~= nil
end

-- Frame level for the layer: the map's highlight pin level, the last one the
-- world map registers after exploration, fog and the quest/scenario blobs and
-- before dig sites, dungeon entrances, flight points and POIs. A plain canvas
-- child would sit below the exploration pin, which paints over it.
local function layerLevel(wmf)
	if wmf.GetPinFrameLevelsManager then
		local ok, level = pcall(function()
			local levels = wmf:GetPinFrameLevelsManager()
			return levels and levels.GetValidFrameLevel and levels:GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_HIGHLIGHT")
		end)
		if ok and type(level) == "number" then
			return level
		end
	end
	local base = canvas.GetFrameLevel and canvas:GetFrameLevel()
	return type(base) == "number" and base + 1 or nil
end

-- Attaches the layer to the world map canvas. Returns false, leaving the feature
-- off, when any client API it needs is missing.
function Map.Init()
	if frame then
		return true
	end
	local wmf = WorldMapFrame
	if not (Grid and wmf and wmf.GetCanvas and wmf.GetMapID and CreateFrame and CreateVector2D
		and C_Map and C_Map.GetMapInfo and C_Map.GetWorldPosFromMapPos) then
		return false
	end
	canvas = wmf:GetCanvas()
	if not canvas then
		return false
	end
	frame = CreateFrame("Frame", nil, canvas)
	frame:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
	frame:EnableMouse(false)
	local strata = canvas.GetFrameStrata and canvas:GetFrameStrata()
	if strata and frame.SetFrameStrata then
		frame:SetFrameStrata(strata)
	end
	local level = layerLevel(wmf)
	if level and frame.SetFrameLevel then
		frame:SetFrameLevel(level)
	end
	for i = 1, #EVENTS do
		pcall(frame.RegisterEvent, frame, EVENTS[i])
	end
	frame:SetScript("OnEvent", function()
		exploredRev = exploredRev + 1
	end)
	frame:SetScript("OnUpdate", onUpdate)
	return true
end
