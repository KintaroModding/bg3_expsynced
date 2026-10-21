-- Without the Mod Configuration Menu (missing, or loaded after this mod): nothing fails, and the client log says that
-- the buttons do nothing.

Harness.Mods[ModuleUUID] = { Info = { ModVersion = { 1, 0, 0, 0 } } }

Ext.Require("BootstrapServer.lua")
Ext.Require("BootstrapClient.lua")

Test("without MCM the client loads and logs that the buttons are missing", function()
    AssertEq(MCM, nil, "no MCM table")
    Ext.Events.SessionLoaded:Fire()
    Harness.RunTimers()
    local log = Harness.Files["bg3_expsynced/client.log"] or ""
    AssertTrue(string.find(log, "the buttons do nothing", 1, true), "error line")
    AssertTrue(string.find(log, "MCM buttons: missing.", 1, true), "load line")
end)
