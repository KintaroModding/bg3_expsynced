local Common = Ext.Require("Shared/Common.lua")
local ServerLog = Ext.Require("Server/ServerLog.lua")
local Sync = Ext.Require("Server/Sync.lua")

Sync.Init()

Ext.Events.SessionLoaded:Subscribe(function()
    ServerLog.Add("EXP Synced " .. Common.ModVersion() .. " loaded.")
end)
