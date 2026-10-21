local Common = Ext.Require("Shared/Common.lua")
local ClientLog = Ext.Require("Client/ClientLog.lua")
local Buttons = Ext.Require("Client/Buttons.lua")

-- MCM puts its MCM table into this mod before this file runs, when MCM loads first (the dependency in meta.lsx).
local registered = Buttons.Init()

Ext.Events.SessionLoaded:Subscribe(function()
    ClientLog.Add("EXP Synced " .. Common.ModVersion() .. " loaded. MCM buttons: "
        .. (registered and "ready" or "missing") .. ".")
end)
