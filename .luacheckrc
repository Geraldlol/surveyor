std = "lua51"
max_line_length = 160
unused_args = false

exclude_files = {
  ".release/**",
  "**/Libs/**",
  "docs/**",
}

globals = {
  -- Witchcraft: generated chunk addons call this entry point
  "Witchcraft_ReceiveChunk",
}

read_globals = {
  -- Libraries
  "LibStub",
  -- WoW API (extend as needed)
  "CreateFrame", "UIParent", "GetTime", "C_Timer", "C_AddOns",
  "IsAddOnLoadOnDemand", "LoadAddOn", "ReloadUI", "InCombatLockdown", "GetPhysicalScreenSize", "debugprofilestop",
  "GetBindingAction", "SetBinding", "SaveBindings", "GetCurrentBindingSet",
  "UnitName", "UnitClass", "UnitRace", "UnitLevel", "GetRealmName", "GetLocale",
  "UnitExists", "UnitIsPlayer", "UnitCanAttack",
  "SlashCmdList", "DEFAULT_CHAT_FRAME", "hooksecurefunc",
  "GetAddOnMetadata", "IsAddOnLoaded",
  "C_Map", "C_MapExplorationInfo", "CreateVector2D", "WorldMapFrame", "C_GossipInfo", "C_NamePlate", "issecretvalue", "canaccessvalue", "canaccesstable",
  "C_QuestLog", "GetZoneText", "GetSubZoneText",
  "GetMoney", "UnitXP", "UnitXPMax", "GetXPExhaustion", "IsInInstance", "GetInstanceInfo",
  "GetNumGroupMembers", "UnitGroupRolesAssigned", "UnitIsDeadOrGhost", "UnitIsGhost", "UnitAffectingCombat",
  "C_CooldownViewer", "C_EncodingUtil", "Enum", "GetBuildInfo", "GetTimePreciseSec",
  "issecure", "issecurevariable", "Settings",
  -- Lua extensions WoW provides
  "wipe", "strsplit", "strjoin", "strtrim", "format", "tinsert", "tremove",
  "date", "time", "debugstack", "geterrorhandler",
}
