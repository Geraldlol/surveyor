local _, ns = ...
local MinimapButton = {}
ns.MinimapButton = MinimapButton

local DEFAULT_ANGLE = 220
local button

local function settings()
    return (ns.Settings and ns.Settings.minimap) or {}
end

local function hideTooltip()
    local tooltip = _G.GameTooltip
    if tooltip and tooltip:IsOwned(button) then tooltip:Hide() end
end

-- Angle in degrees, 0 = east, 90 = north, measured from the minimap centre.
local function position()
    local minimap = _G.Minimap
    local width = minimap:GetWidth()
    local r = (width and width > 0) and (width / 2 + 5) or 80
    local a = math.rad(tonumber(settings().angle) or DEFAULT_ANGLE)
    local x, y
    local getShape = _G.GetMinimapShape
    if getShape and getShape() == "SQUARE" then
        local d = r * math.sqrt(2)
        x = math.max(-r, math.min(r, math.cos(a) * d))
        y = math.max(-r, math.min(r, math.sin(a) * d))
    else
        x, y = math.cos(a) * r, math.sin(a) * r
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", minimap, "CENTER", x, y)
end

local function onDragUpdate()
    local minimap = _G.Minimap
    local scale = minimap:GetEffectiveScale()
    local cx, cy = _G.GetCursorPosition()
    local mx, my = minimap:GetCenter()
    local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
    ns.SetSetting("minimap", { hide = settings().hide, angle = angle })
    position()
end

function MinimapButton.Init()
    if button then return button end
    local minimap = _G.Minimap
    if not minimap or not CreateFrame then return end

    button = CreateFrame("Button", "SurveyorMinimapButton", minimap)
    button:SetSize(31, 31)
    button:SetFrameLevel(minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\AddOns\\Surveyor\\Media\\icon")
    icon:SetTexCoord(.05, .95, .05, .95)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- A press that turns into a drag must not also toggle on release.
    local dragged = false
    button:SetScript("OnMouseDown", function() dragged = false end)
    button:SetScript("OnDragStart", function(self)
        dragged = true
        hideTooltip()
        self:SetScript("OnUpdate", onDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        hideTooltip()
        if dragged then
            dragged = false
            return
        end
        if mouseButton == "RightButton" then
            if ns.OpenOptions then ns.OpenOptions() end
        else
            local enabled = not ns.Settings.enabled
            ns.SetSetting("enabled", enabled)
            if ns.Print then ns.Print(enabled and "outlines shown" or "outlines hidden") end
        end
    end)
    button:SetScript("OnEnter", function()
        local tooltip = _G.GameTooltip
        if not tooltip then return end
        tooltip:SetOwner(button, "ANCHOR_LEFT")
        tooltip:SetText("Surveyor", 1, 1, 1)
        tooltip:AddLine("Left-click: show or hide the outlines", .8, .8, .8)
        tooltip:AddLine("Right-click: options", .8, .8, .8)
        tooltip:AddLine("Drag: move the button", .8, .8, .8)
        tooltip:Show()
    end)
    button:SetScript("OnLeave", hideTooltip)
    button:SetScript("OnHide", hideTooltip)

    MinimapButton.Refresh()
    return button
end

function MinimapButton.Refresh()
    if not button then return end
    position()
    if settings().hide then button:Hide() else button:Show() end
end
