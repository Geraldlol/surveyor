-- Surveyor/Minimap.lua against a mock client under Lua 5.1: creation, edge
-- placement, square clamping, hide/show, clicks and a simulated drag.
-- This verifies logic only, not client loading or drawing.

local passed, failed = 0, 0

local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function near(actual, expected, tolerance, message)
    assert(type(actual) == "number" and math.abs(actual - expected) <= tolerance,
        (message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
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

local GLOBALS = { "CreateFrame", "Minimap", "GetCursorPosition", "GameTooltip", "GetMinimapShape", "SurveyorMinimapButton" }
local saved = {}
for _, name in ipairs(GLOBALS) do
    saved[name] = _G[name]
end

local created, cursor

local function newTexture(layer)
    local t = { layer = layer }
    function t:SetSize(w, h) self.w, self.h = w, h end
    function t:SetPoint(...) self.point = { ... } end
    function t:SetTexture(path) self.texture = path end
    function t:SetTexCoord(...) self.texCoord = { ... } end
    return t
end

local function newButton(kind, name, parent)
    local f = { kind = kind, name = name, parent = parent, scripts = {}, textures = {}, shown = true }
    function f:SetSize(w, h) self.w, self.h = w, h end
    function f:SetFrameLevel(level) self.level = level end
    function f:RegisterForClicks(...) self.clicks = { ... } end
    function f:RegisterForDrag(...) self.drag = { ... } end
    function f:SetMovable(v) self.movable = v end
    function f:SetHighlightTexture(path) self.highlight = path end
    function f:CreateTexture(_, layer)
        local t = newTexture(layer)
        self.textures[#self.textures + 1] = t
        return t
    end
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:ClearAllPoints() self.point = nil end
    function f:SetPoint(...) self.point = { ... } end
    function f:Show() self.shown = true end
    function f:Hide()
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    return f
end

local function installMocks(opts)
    opts = opts or {}
    created = {}
    cursor = { 0, 0 }
    _G.CreateFrame = function(kind, name, parent)
        local f = newButton(kind, name, parent)
        created[#created + 1] = f
        if name then _G[name] = f end
        return f
    end
    if opts.noMinimap then
        _G.Minimap = nil
    else
        _G.Minimap = {
            GetWidth = function() return 140 end,
            GetEffectiveScale = function() return 1 end,
            GetCenter = function() return 500, 500 end,
            GetFrameLevel = function() return 1 end,
        }
    end
    _G.GetCursorPosition = function() return cursor[1], cursor[2] end
    local tip = { lines = {} }
    function tip:SetOwner(owner) self.owner = owner end
    function tip:SetText(text) self.title = text end
    function tip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tip:Show() self.visible = true end
    function tip:Hide() self.visible = false end
    function tip:IsOwned(f) return self.owner == f end
    _G.GameTooltip = tip
    _G.GetMinimapShape = opts.shape and function() return opts.shape end or nil
    _G.SurveyorMinimapButton = nil
end

local function load(minimap)
    local ns = { Settings = { enabled = true, minimap = minimap or { hide = false, angle = 220 } }, calls = {} }
    ns.SetSetting = function(key, value)
        ns.calls[#ns.calls + 1] = { key, value }
        ns.Settings[key] = value
    end
    ns.Print = function(msg) ns.printed = msg end
    local chunk = assert(loadfile("Surveyor/Minimap.lua"))
    chunk("Surveyor", ns)
    return ns
end

local R = 140 / 2 + 5

test("minimap: Init without a Minimap creates nothing", function()
    installMocks({ noMinimap = true })
    local ns = load()
    equal(ns.MinimapButton.Init(), nil, "Init result")
    equal(#created, 0, "frames created")
    ns.MinimapButton.Refresh()
end)

test("minimap: Init creates one named button with its textures", function()
    installMocks()
    local ns = load()
    local b = ns.MinimapButton.Init()
    equal(ns.MinimapButton.Init(), b, "second Init returns the same button")
    equal(#created, 1, "frames created")
    equal(b.name, "SurveyorMinimapButton", "name")
    equal(_G.SurveyorMinimapButton, b, "global")
    equal(b.parent, _G.Minimap, "parent")
    equal(b.w, 31, "width")
    equal(b.level, 9, "frame level")
    equal(b.highlight, "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "highlight")
    equal(#b.textures, 3, "textures created")
    local byPath = {}
    for _, t in ipairs(b.textures) do byPath[t.texture] = t end
    local icon = byPath["Interface\\AddOns\\Surveyor\\Media\\icon"]
    assert(icon, "icon texture")
    equal(icon.w, 17, "icon size")
    equal(icon.texCoord[1], .05, "icon tex coord")
    equal(byPath["Interface\\Minimap\\UI-Minimap-Background"].w, 20, "background size")
    local border = byPath["Interface\\Minimap\\MiniMap-TrackingBorder"]
    equal(border.w, 53, "border size")
    equal(border.layer, "OVERLAY", "border layer")
    equal(table.concat(b.clicks, ","), "LeftButtonUp,RightButtonUp", "clicks")
    equal(b.drag[1], "LeftButton", "drag button")
    equal(b.movable, true, "movable")
end)

test("minimap: angle places the button on the round edge", function()
    installMocks()
    local ns = load({ hide = false, angle = 0 })
    local b = ns.MinimapButton.Init()
    equal(b.point[1], "CENTER", "point")
    equal(b.point[2], _G.Minimap, "relative to")
    near(b.point[4], R, 1e-9, "x at 0")
    near(b.point[5], 0, 1e-9, "y at 0")
    ns.Settings.minimap.angle = 90
    ns.MinimapButton.Refresh()
    near(b.point[4], 0, 1e-9, "x at 90")
    near(b.point[5], R, 1e-9, "y at 90")
end)

test("minimap: a zero width falls back to radius 80", function()
    installMocks()
    _G.Minimap.GetWidth = function() return 0 end
    local ns = load({ hide = false, angle = 0 })
    local b = ns.MinimapButton.Init()
    near(b.point[4], 80, 1e-9, "x")
end)

test("minimap: a square minimap clamps to its edge", function()
    installMocks({ shape = "SQUARE" })
    local ns = load({ hide = false, angle = 45 })
    local b = ns.MinimapButton.Init()
    near(b.point[4], R, 1e-9, "x at 45")
    near(b.point[5], R, 1e-9, "y at 45")
    ns.Settings.minimap.angle = 0
    ns.MinimapButton.Refresh()
    near(b.point[4], R, 1e-9, "x at 0")
    near(b.point[5], 0, 1e-9, "y at 0")
    ns.Settings.minimap.angle = 200
    ns.MinimapButton.Refresh()
    near(b.point[4], -R, 1e-9, "x at 200")
    assert(b.point[5] < 0 and b.point[5] > -R, "y at 200 stays inside the edge")
end)

test("minimap: hide and show follow the setting", function()
    installMocks()
    local ns = load({ hide = true, angle = 220 })
    local b = ns.MinimapButton.Init()
    equal(b.shown, false, "hidden")
    ns.Settings.minimap = { hide = false, angle = 220 }
    ns.MinimapButton.Refresh()
    equal(b.shown, true, "shown")
end)

test("minimap: Refresh before Init does nothing", function()
    installMocks()
    local ns = load()
    ns.MinimapButton.Refresh()
    equal(#created, 0, "frames created")
end)

test("minimap: left click toggles enabled, right click opens options", function()
    installMocks()
    local ns = load()
    local opened = 0
    ns.OpenOptions = function() opened = opened + 1 end
    local b = ns.MinimapButton.Init()
    b.scripts.OnMouseDown(b, "LeftButton")
    b.scripts.OnClick(b, "LeftButton")
    equal(#ns.calls, 1, "SetSetting calls")
    equal(ns.calls[1][1], "enabled", "key")
    equal(ns.calls[1][2], false, "value")
    equal(ns.printed ~= nil, true, "printed")
    b.scripts.OnClick(b, "LeftButton")
    equal(ns.Settings.enabled, true, "toggled back")
    b.scripts.OnClick(b, "RightButton")
    equal(opened, 1, "OpenOptions calls")
    equal(#ns.calls, 2, "right click sets nothing")
end)

test("minimap: tooltip text and hide on leave", function()
    installMocks()
    local ns = load()
    local b = ns.MinimapButton.Init()
    b.scripts.OnEnter(b)
    local tip = _G.GameTooltip
    equal(tip.title, "Surveyor", "title")
    equal(tip.lines[1], "Left-click: show or hide the outlines", "line 1")
    equal(tip.lines[2], "Right-click: options", "line 2")
    equal(tip.lines[3], "Drag: move the button", "line 3")
    equal(tip.visible, true, "visible")
    b.scripts.OnLeave(b)
    equal(tip.visible, false, "hidden on leave")
end)

test("minimap: a drag stores the cursor angle and does not click", function()
    installMocks()
    local ns = load({ hide = false, angle = 220 })
    local b = ns.MinimapButton.Init()
    b.scripts.OnMouseDown(b, "LeftButton")
    b.scripts.OnDragStart(b)
    assert(b.scripts.OnUpdate, "OnUpdate set")
    cursor = { 530, 530 }
    b.scripts.OnUpdate(b, 0.016)
    equal(ns.calls[1][1], "minimap", "key")
    near(ns.calls[1][2].angle, 45, 0.5, "angle")
    equal(ns.calls[1][2].hide, false, "hide kept")
    near(b.point[4], R * math.cos(math.rad(45)), 1e-6, "repositioned x")
    b.scripts.OnDragStop(b)
    equal(b.scripts.OnUpdate, nil, "OnUpdate cleared")
    b.scripts.OnClick(b, "LeftButton")
    equal(#ns.calls, 1, "release after drag does not toggle")
    equal(ns.Settings.enabled, true, "enabled unchanged")
    b.scripts.OnMouseDown(b, "LeftButton")
    b.scripts.OnClick(b, "LeftButton")
    equal(ns.Settings.enabled, false, "next click toggles")
end)

for _, name in ipairs(GLOBALS) do
    _G[name] = saved[name]
end

print(string.format("SURVEYOR MINIMAP: %d passed, %d failed (mocked minimap button under Lua 5.1; no client execution)", passed, failed))
assert(failed == 0, "Surveyor minimap tests failed")
