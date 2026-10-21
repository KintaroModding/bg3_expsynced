-- Values and helpers shared by the server and client contexts.

local Common = {}

--- Returns the version of this mod from its meta.lsx, for example "1.0.0.0".
function Common.ModVersion()
    local ok, version = pcall(function() return Ext.Mod.GetMod(ModuleUUID).Info.ModVersion end)
    if not ok or version == nil then
        return "?"
    end
    return table.concat({ tostring(version[1]), tostring(version[2]), tostring(version[3]), tostring(version[4]) }, ".")
end

-- The buttons of the Mod Configuration Menu page: the ids of the event_button settings in MCM_blueprint.json. The
-- tests check that both lists match.
Common.Buttons = { "sync_now" }

Common.Channels = {
    -- Client -> server request: carry out a button ({ Button = id }).
    -- Reply: { Ok = bool, Message = text, Type = feedback type or nil } for the button's feedback.
    Sync = Ext.Net.CreateChannel(ModuleUUID, "Sync"),
}

return Common
