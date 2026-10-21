-- The Sync now button: a click on the client asks the server, the server raises every party member to the highest
-- total, and the reply shows as the button's feedback. Both bootstrap files run in one Lua state, as on the host.

Harness.Mods[ModuleUUID] = { Info = { ModVersion = { 1, 0, 0, 0 } } }
Harness.InstallMCM()

local TAV = "11111111-1111-1111-1111-111111111111"
local GALE = "22222222-2222-2222-2222-222222222222"
local WYLL = "33333333-3333-3333-3333-333333333333"
local WOLF = "44444444-4444-4444-4444-444444444444"
local KARLACH = "55555555-5555-5555-5555-555555555555"
local PEER = 65536

--- Adds a character with this total experience (options as Harness.AddObject).
local function AddCharacter(uuid, name, total, options)
    options = options or {}
    options.Components = { Experience = { TotalExperience = total } }
    return Harness.AddObject(uuid, "character", name, options)
end

AddCharacter(TAV, "Tav", 6500, { Player = true, Party = true })
AddCharacter(GALE, "Gale", 2600, { Player = true, Party = true })
AddCharacter(WYLL, "Wyll", 5300, { Player = true, Party = true })
-- A summon of the party: DB_Players lists it, the sync skips it.
AddCharacter(WOLF, "Wolf", 0, { Player = true, Party = true, Summon = true })
-- A companion in camp: not in DB_Players.
AddCharacter(KARLACH, "Karlach", 100, {})

Ext.Require("BootstrapServer.lua")
Ext.Require("BootstrapClient.lua")
local Common = Ext.Require("Shared/Common.lua")
local Sync = Ext.Require("Server/Sync.lua")

--- Clicks Sync now, delivers the request to the server, and returns the new feedback.
local function Click()
    local count = #Harness.Feedback
    Harness.ButtonCallbacks.sync_now()
    Harness.DeliverRequests(PEER)
    AssertEq(#Harness.Feedback, count + 1, "one feedback")
    return Harness.Feedback[#Harness.Feedback]
end

local function ServerLog()
    Harness.RunTimers()
    return Harness.Files["bg3_expsynced/server.log"] or ""
end

local function Total(uuid)
    return Harness.Objects[uuid].Components.Experience.TotalExperience
end

local function SetTotal(uuid, total)
    Harness.Objects[uuid].Components.Experience.TotalExperience = total
end

-- The game adds the experience of AddExplorationExperience a moment after the call: ArriveGains does that for every
-- call that has not arrived yet.
local arrived = 0
local function ArriveGains()
    for i = arrived + 1, #Harness.ExperienceGains do
        local gain = Harness.ExperienceGains[i]
        SetTotal(gain.Character, Total(gain.Character) + gain.Amount)
    end
    arrived = #Harness.ExperienceGains
end

--- Replaces DB_Players with these rows for the duration of fn.
local function WithPlayers(rows, fn)
    local original = rawget(Osi, "DB_Players")
    rawset(Osi, "DB_Players", { Get = function() return rows end })
    local ok, err = pcall(fn)
    rawset(Osi, "DB_Players", original)
    assert(ok, err)
end

Test("the button has a callback, and the client log says that it is ready", function()
    for _, button in ipairs(Common.Buttons) do
        AssertEq(type(Harness.ButtonCallbacks[button]), "function", button)
    end
    Ext.Events.SessionLoaded:Fire()
    Harness.RunTimers()
    AssertTrue(string.find(Harness.Files["bg3_expsynced/client.log"] or "", "MCM buttons: ready.", 1, true),
        "client.log")
end)

Test("Sync now raises every party member below the highest to it", function()
    local feedback = Click()
    AssertEq(#Harness.ExperienceGains, 2, "two calls")
    AssertEq(Harness.ExperienceGains[1].Character, GALE, "first: Gale")
    AssertEq(Harness.ExperienceGains[1].Amount, 3900, "Gale's raise")
    AssertEq(Harness.ExperienceGains[2].Character, WYLL, "second: Wyll")
    AssertEq(Harness.ExperienceGains[2].Amount, 1200, "Wyll's raise")
    AssertEq(feedback.Type, "success", "feedback type")
    AssertEq(feedback.Message, "Raised Gale and Wyll to 6,500 XP.", "feedback")
    AssertTrue(string.find(ServerLog(), "Sync by peer 65536: highest 6500 (Tav). Gale 2600 -> 6500 (+3900), "
        .. "Wyll 5300 -> 6500 (+1200).", 1, true), "server.log line")
end)

Test("a second click before the raises arrived raises nobody", function()
    Harness.RunTicks(3)
    local feedback = Click()
    AssertEq(#Harness.ExperienceGains, 2, "no new call")
    AssertEq(feedback.Type, "warning", "feedback type")
    AssertEq(feedback.Message, "Still syncing. Try again in a moment.", "feedback")
end)

Test("when the raises arrive, the next tick ends the sync", function()
    ArriveGains()
    Harness.RunTick()
    AssertTrue(string.find(ServerLog(), "Sync arrived after 4 tick(s): Gale 6500, Wyll 6500.", 1, true),
        "server.log line")
    local feedback = Click()
    AssertEq(#Harness.ExperienceGains, 2, "no new call")
    AssertEq(feedback.Type, "info", "feedback type")
    AssertEq(feedback.Message, "Everyone already has 6,500 XP.", "feedback")
end)

Test("the summon and the companion in camp keep their experience", function()
    AssertEq(Total(WOLF), 0, "summon")
    AssertEq(Total(KARLACH), 100, "camp companion")
    for _, gain in ipairs(Harness.ExperienceGains) do
        AssertTrue(gain.Character ~= WOLF and gain.Character ~= KARLACH, "no call for them")
    end
end)

Test("raises that do not arrive free the button after WaitTicks ticks", function()
    SetTotal(TAV, 8000)
    local feedback = Click()
    AssertEq(feedback.Message, "Raised Gale and Wyll to 8,000 XP.", "feedback")
    Harness.RunTicks(Sync.WaitTicks - 1)
    AssertEq(Click().Type, "warning", "still waiting one tick before the end")
    Harness.RunTick()
    AssertTrue(string.find(ServerLog(), "Sync: no raise for Gale and Wyll after " .. Sync.WaitTicks
        .. " ticks: Gale 6500, Wyll 6500.", 1, true), "server.log line")
    ArriveGains()
    AssertEq(Click().Message, "Everyone already has 8,000 XP.", "free again")
end)

Test("a character listed twice counts once, and one without experience is skipped", function()
    Harness.AddObject("66666666-6666-6666-6666-666666666666", "character", "Prop", { Player = true })
    WithPlayers({ { Harness.GuidString(GALE) }, { Harness.GuidString(GALE) },
        { Harness.GuidString("66666666-6666-6666-6666-666666666666") } }, function()
        local party = Sync.Party()
        AssertEq(#party, 1, "one member")
        AssertEq(party[1].Name, "Gale", "Gale")
        AssertEq(party[1].Total, 8000, "Gale's total")
    end)
    Harness.RemoveObject("66666666-6666-6666-6666-666666666666")
end)

Test("without party members the button shows an error", function()
    WithPlayers({}, function()
        local feedback = Click()
        AssertEq(feedback.Type, "error", "feedback type")
        AssertEq(feedback.Message, "No party members found.", "feedback")
    end)
    AssertTrue(string.find(ServerLog(), "ERROR Sync by peer 65536: no party members found.", 1, true), "log")
end)

Test("a failed raise names the character, and the others are still raised", function()
    SetTotal(TAV, 9000)
    local original = rawget(Osi, "AddExplorationExperience")
    rawset(Osi, "AddExplorationExperience", function(guid, amount)
        if string.find(guid, GALE, 1, true) then
            error("no experience for Gale")
        end
        original(guid, amount)
    end)
    local ok, err = pcall(function()
        local calls = #Harness.ExperienceGains
        local feedback = Click()
        AssertEq(#Harness.ExperienceGains, calls + 1, "Wyll only")
        AssertEq(Harness.ExperienceGains[#Harness.ExperienceGains].Character, WYLL, "Wyll")
        AssertEq(feedback.Type, "error", "feedback type")
        AssertEq(feedback.Message, "Failed for Gale, see server.log.", "feedback")
        AssertTrue(string.find(ServerLog(), "Gale 8000: failed (", 1, true), "log names the failure")
    end)
    rawset(Osi, "AddExplorationExperience", original)
    assert(ok, err)
    ArriveGains()
    Harness.RunTick()
    AssertEq(Click().Message, "Raised Gale to 9,000 XP.", "Gale on the next click")
    ArriveGains()
    Harness.RunTick()
end)

Test("in the main menu a click sends nothing and asks for a savegame", function()
    Harness.GameState = "Menu"
    local sent = #Harness.Channels.Sync.Sent
    Harness.ButtonCallbacks.sync_now()
    Harness.GameState = "Running"
    AssertEq(#Harness.Channels.Sync.Sent, sent, "no request")
    local feedback = Harness.Feedback[#Harness.Feedback]
    AssertEq(feedback.Type, "warning", "feedback type")
    AssertEq(feedback.Message, "Load a savegame first.", "feedback")
end)

Test("the server refuses an unknown button", function()
    local calls = #Harness.ExperienceGains
    SetTotal(TAV, 10000)
    local reply = Harness.Channels.Sync.RequestHandler({ Button = "no_such_button" }, PEER)
    AssertEq(reply.Ok, false, "refused")
    reply = Harness.Channels.Sync.RequestHandler("not a table", PEER)
    AssertEq(reply.Ok, false, "refused without a table")
    AssertEq(#Harness.ExperienceGains, calls, "nothing given")
    SetTotal(TAV, 9000)
end)

Test("numbers get commas between thousands, and names join as in a sentence", function()
    AssertEq(Sync.Format(0), "0", "0")
    AssertEq(Sync.Format(999), "999", "999")
    AssertEq(Sync.Format(6500), "6,500", "6500")
    AssertEq(Sync.Format(100000), "100,000", "100000")
    AssertEq(Sync.Format(1234567), "1,234,567", "1234567")
    AssertEq(Sync.JoinNames({}), "", "none")
    AssertEq(Sync.JoinNames({ "Gale" }), "Gale", "one")
    AssertEq(Sync.JoinNames({ "Gale", "Wyll" }), "Gale and Wyll", "two")
    AssertEq(Sync.JoinNames({ "Gale", "Tav", "Wyll" }), "Gale, Tav and Wyll", "three")
end)
