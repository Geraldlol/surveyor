local _, ns = ...
local Surveyor = LibStub("AceAddon-3.0"):NewAddon("Surveyor", "AceConsole-3.0")

local defaults = {
	profile = {
		enabled = true,
		mode = "xp", -- "xp": areas with ExplorationLevel > 0; "all": every area with a bit
		names = true,
		thickness = 2,
	},
}

function Surveyor:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("SurveyorDB", defaults, true)
	ns.Settings = self.db.profile
	ns.Print = function(msg)
		self:Print(msg)
	end
	self:RegisterChatCommand("survey", "HandleSlash")
end

function Surveyor:OnEnable()
	self.mapReady = ns.Map.Init()
end

function Surveyor:PrintStatus()
	local s = self.db.profile
	self:Printf("borders %s, mode %s, names %s, map layer %s",
		s.enabled and "on" or "off", s.mode, s.names and "on" or "off",
		self.mapReady and "ready" or "unavailable")
end

function Surveyor:HandleSlash(input)
	local cmd = string.lower((input or ""):match("^%s*(%S*)"))
	local s = self.db.profile
	if cmd == "" or cmd == "status" then
		self:PrintStatus()
		return
	elseif cmd == "on" then
		s.enabled = true
	elseif cmd == "off" then
		s.enabled = false
	elseif cmd == "names" then
		s.names = not s.names
	elseif cmd == "xp" or cmd == "all" then
		s.mode = cmd
	else
		self:Print("usage: /survey on | off | names | xp | all | status")
		return
	end
	ns.Map.Invalidate()
	self:PrintStatus()
end
