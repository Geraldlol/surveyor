-- Surveyor grid math: pure functions over the generated chunk-corner data.
-- No WoW API here, so the pure-Lua tests can load this file directly.
local _, ns = ...

local Grid = {}
ns.Grid = Grid

-- One ADT tile is 1600/3 yards and holds 16x16 chunks; the world grid is 64x64 tiles.
local ORIGIN = 51200 / 3 -- 17066.6667 yards from the world centre to the grid edge
local CHUNK = 100 / 3 -- 33.3333 yards per chunk
Grid.ORIGIN, Grid.CHUNK = ORIGIN, CHUNK

-- Chunk-corner units (gx, gy) to world yards (wx north, wy west).
function Grid.ToWorld(gx, gy)
	return ORIGIN - gy * CHUNK, ORIGIN - gx * CHUNK
end

-- An entry's bounding box { x0, y0, x1, y1, ... } as a world rect: minX, maxX, minY, maxY.
function Grid.BoxToWorld(e)
	local maxX, maxY = Grid.ToWorld(e[1], e[2])
	local minX, minY = Grid.ToWorld(e[3], e[4])
	return minX, maxX, minY, maxY
end

-- True when two rects (minX, maxX, minY, maxY) overlap; touching edges do not count.
function Grid.RectsMeet(aMinX, aMaxX, aMinY, aMaxY, bMinX, bMaxX, bMinY, bMaxY)
	return aMinX < bMaxX and bMinX < aMaxX and aMinY < bMaxY and bMinY < aMaxY
end

-- World yards to normalised map position, linear between the world positions
-- of the map's (0, 0) and (1, 1) corners. Map x runs along world y, map y along world x.
function Grid.WorldToMapLinear(wx, wy, x00, y00, x11, y11)
	return (wy - y00) / (y11 - y00), (wx - x00) / (x11 - x00)
end

-- True when both ends of a normalised edge lie outside 0..1 on the same side.
function Grid.EdgeOutside(ax, ay, bx, by)
	return (ax < 0 and bx < 0) or (ax > 1 and bx > 1) or (ay < 0 and by < 0) or (ay > 1 and by > 1)
end

local function nextEdge(loop, i)
	i = i + 2
	local n = #loop
	if i > n then
		return nil
	end
	local j = i + 2
	if j > n then
		j = 1
	end
	return i, loop[i], loop[i + 1], loop[j], loop[j + 1]
end

-- Iterates a closed loop { gx1, gy1, gx2, gy2, ... }: yields i, ax, ay, bx, by per edge,
-- the last edge joining the last vertex to the first.
function Grid.Edges(loop)
	return nextEdge, loop, -1
end

-- Mode filter for zone maps. row is ns.Areas[id]; "all" keeps every known area,
-- "xp" (the default) only areas with ExplorationLevel > 0.
function Grid.Passes(mode, row)
	if not row then
		return false
	end
	return mode == "all" or (row[3] or 0) > 0
end

-- World yards back to chunk-corner units (fractional): the inverse of ToWorld.
function Grid.FromWorld(wx, wy)
	return (ORIGIN - wy) / CHUNK, (ORIGIN - wx) / CHUNK
end

-- Fraction of rect b's area inside rect a, both as minX, maxX, minY, maxY.
-- The ratio is the same in chunk-corner units and in world yards.
function Grid.OverlapRatio(aMinX, aMaxX, aMinY, aMaxY, bMinX, bMaxX, bMinY, bMaxY)
	local area = (bMaxX - bMinX) * (bMaxY - bMinY)
	if area <= 0 then
		return 0
	end
	local w = math.min(aMaxX, bMaxX) - math.max(aMinX, bMinX)
	local h = math.min(aMaxY, bMaxY) - math.max(aMinY, bMinY)
	if w <= 0 or h <= 0 then
		return 0
	end
	return w * h / area
end

-- Top-level zone of an area: follows ParentAreaID (row[2]) to 0, at most 8 hops.
-- Nil for an unknown id or a longer chain (a cycle).
function Grid.RootOf(areas, id)
	for _ = 0, 8 do
		local row = areas[id]
		if not row then
			return nil
		end
		local parent = row[2]
		if not parent or parent == 0 then
			return id
		end
		id = parent
	end
	return nil
end

-- True when the point (gx, gy), fractional chunk-corner units, lies in the entry:
-- bounding box prefilter, then an even-odd crossing test over all its loops.
function Grid.Contains(e, gx, gy)
	if gx < e[1] or gx >= e[3] or gy < e[2] or gy >= e[4] then
		return false
	end
	local inside = false
	local loops = e[8]
	for li = 1, #loops do
		for _, ax, ay, bx, by in Grid.Edges(loops[li]) do
			if (ay > gy) ~= (by > gy) and gx < ax + (gy - ay) * (bx - ax) / (by - ay) then
				inside = not inside
			end
		end
	end
	return inside
end
