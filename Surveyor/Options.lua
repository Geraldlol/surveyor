local ADDON, ns = ...
local Options = {}
ns.Options = Options

-- Surveyor's page in the client's Esc > Options > AddOns. Every control is a proxy setting: it
-- reads ns.Settings and writes through ns.SetSetting, the setter the slash command uses, so the
-- values live only in SurveyorDB.

local PAGE = {
	{ key = "enabled", label = "Enabled", tooltip = "Draw area borders on zone maps." },
	{ key = "mode", label = "Mode", kind = "choice", tooltip = "Which areas get a border.",
	  choices = { { "xp", "Areas that give XP" }, { "all", "Every area with a map bit" } } },
	{ key = "names", label = "Show area names", tooltip = "Write each area's name inside its border." },
	{ key = "hideExplored", label = "Hide explored areas", tooltip = "Draw no border or name for areas you have already explored." },
	{ key = "thickness", label = "Line thickness", kind = "slider", min = 1, max = 6, step = 1,
	  tooltip = "The width of the border lines in pixels." },
	{ key = "opacity", label = "Line opacity", kind = "slider", min = 10, max = 100, step = 5,
	  tooltip = "The opacity of the border lines and area names in percent." },
	{ key = "minimap", label = "Show minimap button", tooltip = "Show the Surveyor button at the edge of the minimap." },
}
Options.PAGE = PAGE

-- Getter, setter and default for a row; the minimap row maps the checkbox onto minimap.hide.
local function accessors(key)
	if key == "minimap" then
		return function() return not ns.Settings.minimap.hide end,
			function(value) ns.SetSetting("minimap", { hide = not value, angle = ns.Settings.minimap.angle }) end,
			not ns.Defaults.minimap.hide
	end
	return function() return ns.Settings[key] end, function(value) ns.SetSetting(key, value) end, ns.Defaults[key]
end

-- Returns the category ID Settings.OpenToCategory takes, or nil on a client without the Settings API.
function Options.Register(api)
	api = api or _G
	local settings = api.Settings
	if type(settings) ~= "table" or type(settings.RegisterVerticalLayoutCategory) ~= "function" then
		return nil
	end
	local category = settings.RegisterVerticalLayoutCategory(ADDON)
	local types = settings.VarType or { Boolean = "boolean", Number = "number", String = "string" }
	for _, row in ipairs(PAGE) do
		local get, set, default = accessors(row.key)
		local varType = type(default) == "number" and types.Number or type(default) == "string" and types.String or types.Boolean
		local setting = settings.RegisterProxySetting(category, "SURVEYOR_" .. row.key:upper(), varType, row.label, default, get, set)
		if row.kind == "slider" then
			settings.CreateSlider(category, setting, settings.CreateSliderOptions(row.min, row.max, row.step), row.tooltip)
		elseif row.kind == "choice" then
			local choices = row.choices
			settings.CreateDropdown(category, setting, function()
				local container = settings.CreateControlTextContainer()
				for _, choice in ipairs(choices) do
					container:Add(choice[1], choice[2])
				end
				return container:GetData()
			end, row.tooltip)
		else
			settings.CreateCheckbox(category, setting, row.tooltip)
		end
	end
	settings.RegisterAddOnCategory(category)
	return category.GetID and category:GetID() or category.ID
end
