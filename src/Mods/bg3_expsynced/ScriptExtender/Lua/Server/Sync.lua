-- Carries out the Sync now button of the Mod Configuration Menu: raises the experience of every party member to the
-- highest total in the party. Nobody loses experience. The party is DB_Players without summons, each character once:
-- the active party, with the characters of every player in multiplayer; companions in camp are not in it.
--
-- Osi.AddExplorationExperience gives only to the character it names, and the game adds it a moment later
-- (bg3_levelunlocked game tests, playbook knowledge\experience.md). A second click in between would read the old
-- totals and raise again, so the server refuses a new sync until the raises arrived, or WaitTicks ticks passed.

local Common = Ext.Require("Shared/Common.lua")
local ServerLog = Ext.Require("Server/ServerLog.lua")

local Sync = {}

-- Server ticks to wait for the raises; then the mod gives up on them, logs it and allows the next sync.
Sync.WaitTicks = 150

-- The sync on its way: { Targets = { { Member, Total }, ... }, Ticks = n } (ticks counted since the sync); nil when
-- none waits.
local pending = nil

local function Try(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil
end

--- The UUID part of an Osiris GUID string (the last 36 characters).
local function Uuid(guid)
    return string.sub(guid, -36)
end

--- Returns the total experience of a character, or nil when it has none.
function Sync.TotalExperience(character)
    local total = Try(function()
        return Ext.Entity.Get(Uuid(character)).Experience.TotalExperience
    end)
    if type(total) ~= "number" then
        return nil
    end
    return total
end

--- Returns the name the game shows for a character, or its id when it has none.
local function NameOf(character)
    local handle = Try(function() return Osi.GetDisplayName(character) end)
    if type(handle) ~= "string" or handle == "" then
        return tostring(character)
    end
    -- GetDisplayName can return the handle with its version ("h...;1"); the text lookup needs the handle alone.
    handle = string.gsub(handle, ";%d+$", "")
    local name = Try(Ext.Loca.GetTranslatedString, handle)
    if type(name) ~= "string" or name == "" or name == handle then
        return tostring(character)
    end
    return name
end

--- Returns a number with a comma between thousands: 6500 -> "6,500".
function Sync.Format(number)
    local text = tostring(math.floor(number))
    local grouped = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
    return (string.gsub(grouped, "^(%-?),", "%1"))
end

--- Returns "Gale", "Gale and Wyll" or "Gale, Wyll and Karlach".
function Sync.JoinNames(names)
    if #names <= 1 then
        return names[1] or ""
    end
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

--- Returns the party members that have experience, sorted by name:
--- { { Character = guid string, Name = text, Total = n }, ... }.
function Sync.Party()
    local party, seen = {}, {}
    for _, row in ipairs(Try(function() return Osi.DB_Players:Get(nil) end) or {}) do
        local character = row[1]
        if type(character) == "string" and not seen[Uuid(character)] then
            seen[Uuid(character)] = true
            if Try(function() return Osi.IsSummon(character) end) ~= 1 then
                local total = Sync.TotalExperience(character)
                if total ~= nil then
                    party[#party + 1] = { Character = character, Name = NameOf(character), Total = total }
                end
            end
        end
    end
    table.sort(party, function(a, b)
        if a.Name ~= b.Name then
            return a.Name < b.Name
        end
        return a.Character < b.Character
    end)
    return party
end

--- Raises every party member below the highest total to it. Returns the reply for the client.
function Sync.Run(peerId)
    if pending ~= nil then
        return { Ok = false, Message = "Still syncing. Try again in a moment.", Type = "warning" }
    end
    local party = Sync.Party()
    if #party == 0 then
        ServerLog.Add("ERROR Sync by peer " .. tostring(peerId) .. ": no party members found.")
        return { Ok = false, Message = "No party members found." }
    end

    local highest, leader = -1, nil
    for _, member in ipairs(party) do
        if member.Total > highest then
            highest, leader = member.Total, member
        end
    end

    local raised, failed, parts, targets = {}, {}, {}, {}
    for _, member in ipairs(party) do
        if member.Total < highest then
            local amount = highest - member.Total
            local ok, err = pcall(function() Osi.AddExplorationExperience(member.Character, amount) end)
            if ok then
                raised[#raised + 1] = member.Name
                targets[#targets + 1] = { Member = member, Total = highest }
                parts[#parts + 1] = string.format("%s %d -> %d (+%d)", member.Name, member.Total, highest, amount)
            else
                failed[#failed + 1] = member.Name
                parts[#parts + 1] = string.format("%s %d: failed (%s)", member.Name, member.Total, tostring(err))
            end
        end
    end

    local head = string.format("Sync by peer %s: highest %d (%s).", tostring(peerId), highest, leader.Name)
    if #parts == 0 then
        ServerLog.Add(head .. " Everyone already has it.")
        return { Ok = true, Message = "Everyone already has " .. Sync.Format(highest) .. " XP.", Type = "info" }
    end
    ServerLog.Add(head .. " " .. table.concat(parts, ", ") .. ".")
    if #targets > 0 then
        pending = { Targets = targets, Ticks = 0 }
    end
    if #failed > 0 then
        return { Ok = false, Message = "Failed for " .. Sync.JoinNames(failed) .. ", see server.log." }
    end
    return { Ok = true, Message = "Raised " .. Sync.JoinNames(raised) .. " to " .. Sync.Format(highest) .. " XP." }
end

--- Once per tick while a sync waits: ends it when every raise arrived, or after WaitTicks ticks.
local function CheckPending()
    pending.Ticks = pending.Ticks + 1
    local missing, totals = {}, {}
    for _, target in ipairs(pending.Targets) do
        local total = Sync.TotalExperience(target.Member.Character)
        totals[#totals + 1] = target.Member.Name .. " " .. tostring(total)
        if total == nil or total < target.Total then
            missing[#missing + 1] = target.Member.Name
        end
    end
    if #missing == 0 then
        ServerLog.Add(string.format("Sync arrived after %d tick(s): %s.", pending.Ticks, table.concat(totals, ", ")))
        pending = nil
    elseif pending.Ticks >= Sync.WaitTicks then
        ServerLog.Add(string.format("Sync: no raise for %s after %d ticks: %s.", Sync.JoinNames(missing),
            pending.Ticks, table.concat(totals, ", ")))
        pending = nil
    end
end

function Sync.Init()
    Common.Channels.Sync:SetRequestHandler(function(data, peerId)
        local button = type(data) == "table" and data.Button or nil
        if button ~= "sync_now" then
            ServerLog.Add("ERROR Unknown button " .. tostring(button) .. " from peer " .. tostring(peerId))
            return { Ok = false, Message = "Unknown button." }
        end
        local ok, reply = pcall(Sync.Run, peerId)
        if not ok then
            ServerLog.Add("ERROR Sync by peer " .. tostring(peerId) .. ": " .. tostring(reply))
            return { Ok = false, Message = "Failed, see server.log." }
        end
        return reply
    end)
    local reported = {}
    Ext.Events.Tick:Subscribe(function()
        if pending == nil then
            return
        end
        local ok, err = pcall(CheckPending)
        if not ok then
            -- The tick runs every frame: report each error once, and do not block the button.
            pending = nil
            if not reported[tostring(err)] then
                reported[tostring(err)] = true
                ServerLog.Add("ERROR Sync check: " .. tostring(err))
            end
        end
    end)
end

return Sync
