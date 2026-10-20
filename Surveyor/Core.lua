local _, ns = ...
local Surveyor = LibStub("AceAddon-3.0"):NewAddon("Surveyor", "AceConsole-3.0")

local defaults = {
	profile = {
		enabled = true,
		mode = "xp", -- "xp": areas with ExplorationLevel > 0; "all": every area with a bit
		names = true,
		hideExplored = false,
		thickness = 2,
		opacity = 100,
		minimap = { hide = false, angle = 220 },
	},
}
ns.Defaults = defaults.profile

local optionsCategory

-- The one setter for the profile: the slash command, the options page and the
-- minimap button all write through it. Callers pass whole values.
function ns.SetSetting(key, value)
	ns.Settings[key] = value
	if ns.Map then
		ns.Map.Invalidate()
	end
	if ns.MinimapButton then
		ns.MinimapButton.Refresh()
	end
end

function ns.OpenOptions()
	if optionsCategory and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(optionsCategory)
	else
		ns.Print("the options panel needs the client's Settings API; use /survey on | off | names | explored | xp | all")
	end
end

function Surveyor:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("SurveyorDB", defaults, true)
	ns.Settings = self.db.profile
	ns.Print = function(msg)
		self:Print(msg)
	end
	optionsCategory = ns.Options and ns.Options.Register()
	self:RegisterChatCommand("survey", "HandleSlash")
end

function Surveyor:OnEnable()
	self.mapReady = ns.Map.Init()
	if ns.MinimapButton then
		ns.MinimapButton.Init()
	end
end

function Surveyor:PrintStatus()
	local s = self.db.profile
	self:Printf("borders %s, mode %s, names %s, hide explored %s, map layer %s",
		s.enabled and "on" or "off", s.mode, s.names and "on" or "off", s.hideExplored and "on" or "off",
		self.mapReady and "ready" or "unavailable")
end

function Surveyor:HandleSlash(input)
	local cmd = string.lower((input or ""):match("^%s*(%S*)"))
	local s = self.db.profile
	if cmd == "" or cmd == "status" then
		self:PrintStatus()
		return
	elseif cmd == "on" then
		ns.SetSetting("enabled", true)
	elseif cmd == "off" then
		ns.SetSetting("enabled", false)
	elseif cmd == "names" then
		ns.SetSetting("names", not s.names)
	elseif cmd == "explored" then
		ns.SetSetting("hideExplored", not s.hideExplored)
	elseif cmd == "xp" or cmd == "all" then
		ns.SetSetting("mode", cmd)
	elseif cmd == "config" then
		ns.OpenOptions()
		return
	elseif cmd == "probe" then
		for _, line in ipairs(ns.Map.Probe()) do
			self:Print(line)
		end
		return
	else
		self:Print("usage: /survey on | off | names | explored | xp | all | config | probe | status")
		return
	end
	self:PrintStatus()
end
