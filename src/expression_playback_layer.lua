function plugindef()
	finaleplugin.RequireSelection = false
    finaleplugin.Author = "Carl Vine"
    finaleplugin.AuthorURL = "http://carlvine.com/lua/"
    finaleplugin.Copyright = "https://creativecommons.org/licenses/by/4.0/"
    finaleplugin.Version = "0.03"
    finaleplugin.Date = "2024/07/25"
    finaleplugin.Notes = [[
        Change the assigned playback layer for all expressions in the current selection. 
        Layer "0" is interpreted as "Current Layer". 
        Hold down _Shift_ when starting the script to repeat the same action 
        as last time without a confirmation dialog.
    ]]
    return "Expression Playback Layer...",
        "Expression Playback Layer",
        "Change the assigned playback layer for all expressions in the current selection"
end

local c = { -- user config values
    layer = 0,
    window_pos_x = false,
    window_pos_y = false,
}
local configuration = require("library.configuration")
local mixin = require("library.mixin")
local library = require("library.general_library")
local layer = require("library.layer")
local script_name = library.calc_script_name()

local function dialog_set_position(dialog)
    if c.window_pos_x and c.window_pos_y then
        dialog:StorePosition()
        dialog:SetRestorePositionOnlyData(c.window_pos_x, c.window_pos_y)
        dialog:RestorePosition()
    end
end

local function dialog_save_position(dialog)
    dialog:StorePosition()
    c.window_pos_x = dialog.StoredX
    c.window_pos_y = dialog.StoredY
    configuration.save_user_settings(script_name, c)
end

local function user_dialog()
    local y = 0
    local y_off = finenv.UI():IsOnMac() and 3 or 0
    local save = c.layer
    local dialog = mixin.FCXCustomLuaWindow():SetTitle("Playback Layer")
    dialog:CreateStatic(0, y):SetWidth(190):SetText("Assign Playback of All Expressions")
    y = y + 22
    dialog:CreateStatic(0, y):SetWidth(50):SetText("to Layer:")
    local layer_num = dialog:CreateEdit(55, y - y_off):SetInteger(save):SetWidth(20)
        :AddHandleCommand(function(self)
            local val = self:GetText():lower()
            if not val:find("[^0-" .. layer.max_layers() .. "]") then
                save = tonumber(val:sub(-1)) or 0
            end
            self:SetInteger(save):SetKeyboardFocus()
        end)
    -- all ready
    dialog:CreateOkButton()
    dialog:CreateCancelButton()
    dialog_set_position(dialog)
    dialog:RegisterHandleOkButtonPressed(function() c.layer = layer_num:GetInteger() end)
    dialog:RegisterCloseWindow(function(self) dialog_save_position(self) end)
    return (dialog:ExecuteModal() == finale.EXECMODAL_OK)
end

local function playback_layer()
    configuration.get_user_settings(script_name, c, true)
    local qim = finenv.QueryInvokedModifierKeys
    local mod_key = qim and (qim(finale.CMDMODKEY_ALT) or qim(finale.CMDMODKEY_SHIFT))

    if mod_key or user_dialog() then
        if finenv.Region():IsEmpty() then
            finenv.UI():AlertError(
                "Please select some music\nbefore running this script",
                "Playback Layer")
            return
        else
            local expressions = finale.FCExpressions()
            expressions:LoadAllForRegion(finenv.Region())
            for exp in each(expressions) do
                if exp.StaffGroupID == 0 then -- exclude "Staff List" expressions
                    exp.PlaybackLayerAssignment = c.layer
                    exp:Save()
                end
            end
        end
    end
end

playback_layer()
