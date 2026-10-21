-- MCM_blueprint.json holds only buttons (event_button), the same ones as Common.Buttons. The runner reads the blueprint
-- into MCM_BLUEPRINT.

local Common = Ext.Require("Shared/Common.lua")

--- Returns every setting of the blueprint: at the root, in tabs and in sections.
local function BlueprintSettings()
    local found = {}
    local function Add(list)
        for _, setting in ipairs(list or {}) do
            found[#found + 1] = setting
        end
    end
    Add(MCM_BLUEPRINT.Settings)
    for _, tab in ipairs(MCM_BLUEPRINT.Tabs or {}) do
        Add(tab.Settings)
        for _, section in ipairs(tab.Sections or {}) do
            Add(section.Settings)
        end
    end
    return found
end

Test("the blueprint exists and has settings", function()
    AssertTrue(MCM_BLUEPRINT ~= nil, "MCM_blueprint.json next to meta.lsx")
    AssertEq(MCM_BLUEPRINT.SchemaVersion, 1, "SchemaVersion")
    AssertTrue(#BlueprintSettings() > 0, "at least one setting")
end)

Test("every setting id in the blueprint is unique", function()
    local seen = {}
    for _, setting in ipairs(BlueprintSettings()) do
        AssertTrue(type(setting.Id) == "string" and setting.Id ~= "", "every setting has an Id")
        AssertTrue(not seen[setting.Id], "the id " .. setting.Id .. " is used twice")
        seen[setting.Id] = true
    end
end)

Test("every setting is a button with a name, a label and a description", function()
    for _, setting in ipairs(BlueprintSettings()) do
        AssertEq(setting.Type, "event_button", setting.Id .. " type")
        AssertEq(setting.Default, nil, setting.Id .. ": a button has no Default")
        AssertTrue(type(setting.Name) == "string" and setting.Name ~= "", setting.Id .. " Name")
        AssertTrue(type(setting.Description) == "string" and setting.Description ~= "", setting.Id .. " Description")
        AssertTrue(setting.Options and type(setting.Options.Label) == "string", setting.Id .. " Options.Label")
    end
end)

Test("the blueprint buttons and Common.Buttons are the same", function()
    local inBlueprint = {}
    for _, setting in ipairs(BlueprintSettings()) do
        inBlueprint[setting.Id] = true
    end
    local inCode = {}
    for _, button in ipairs(Common.Buttons) do
        inCode[button] = true
        AssertTrue(inBlueprint[button], button .. " is in Common.Buttons but not in MCM_blueprint.json")
    end
    for id in pairs(inBlueprint) do
        AssertTrue(inCode[id], id .. " is in MCM_blueprint.json but not in Common.Buttons")
    end
end)
