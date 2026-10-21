-- The buttons of the Mod Configuration Menu page (event_button settings in MCM_blueprint.json). A click asks the server
-- to carry out the button; the reply shows next to the button.

local Common = Ext.Require("Shared/Common.lua")
local ClientLog = Ext.Require("Client/ClientLog.lua")

local Buttons = {}

--- True while the client shows the main menu: then no game runs that could carry out a button.
local function InMainMenu()
    local ok, inMenu = pcall(function()
        return Ext.Utils.GetGameState() == Ext.Enums.ClientGameState["Menu"]
    end)
    return ok and inMenu == true
end

local function Feedback(button, message, feedbackType)
    local ok, err = pcall(MCM.EventButton.ShowFeedback, button, message, feedbackType)
    if not ok then
        ClientLog.Add("ERROR ShowFeedback(" .. button .. "): " .. tostring(err))
    end
end

local function OnClick(button)
    if InMainMenu() then
        Feedback(button, "Load a savegame first.", "warning")
        return
    end
    Common.Channels.Sync:RequestToServer({ Button = button }, function(reply)
        if type(reply) ~= "table" or type(reply.Message) ~= "string" then
            Feedback(button, "No answer from the server.", "error")
            return
        end
        Feedback(button, reply.Message, reply.Type or (reply.Ok and "success" or "error"))
    end)
end

--- Registers the callback of every button. Returns false when the MCM table is missing (MCM not installed, or loaded
--- after this mod): then the buttons do nothing.
function Buttons.Init()
    if MCM == nil or MCM.EventButton == nil then
        ClientLog.Add("ERROR The Mod Configuration Menu is missing or loaded after this mod: the buttons do nothing.")
        return false
    end
    local registered = true
    for _, button in ipairs(Common.Buttons) do
        local ok, result = pcall(MCM.EventButton.RegisterCallback, button, function()
            OnClick(button)
        end)
        if not ok or result == false then
            ClientLog.Add("ERROR RegisterCallback(" .. button .. ") failed: " .. tostring(result))
            registered = false
        end
    end
    return registered
end

return Buttons
