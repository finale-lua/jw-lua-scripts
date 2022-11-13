__imports = __imports or {}
__import_results = __import_results or {}

function require(item)
    if not __imports[item] then
        error("module '" .. item .. "' not found")
    end

    if __import_results[item] == nil then
        __import_results[item] = __imports[item]()
        if __import_results[item] == nil then
            __import_results[item] = true
        end
    end

    return __import_results[item]
end

__imports["library.layer"] = __imports["library.layer"] or function()
    --[[
    $module Layer
    ]] --
    local layer = {}
    
    --[[
    % copy
    
    Duplicates the notes from the source layer to the destination. The source layer remains untouched.
    
    @ region (FCMusicRegion) the region to be copied
    @ source_layer (number) the number (1-4) of the layer to duplicate
    @ destination_layer (number) the number (1-4) of the layer to be copied to
    ]]
    function layer.copy(region, source_layer, destination_layer)
        local start = region.StartMeasure
        local stop = region.EndMeasure
        local sysstaves = finale.FCSystemStaves()
        sysstaves:LoadAllForRegion(region)
        source_layer = source_layer - 1
        destination_layer = destination_layer - 1
        for sysstaff in each(sysstaves) do
            staffNum = sysstaff.Staff
            local noteentry_source_layer = finale.FCNoteEntryLayer(source_layer, staffNum, start, stop)
            noteentry_source_layer:SetUseVisibleLayer(false)
            noteentry_source_layer:Load()
            local noteentry_destination_layer = noteentry_source_layer:CreateCloneEntries(
                destination_layer, staffNum, start)
            noteentry_destination_layer:Save()
            noteentry_destination_layer:CloneTuplets(noteentry_source_layer)
            noteentry_destination_layer:Save()
        end
    end -- function layer_copy
    
    --[[
    % clear
    
    Clears all entries from a given layer.
    
    @ region (FCMusicRegion) the region to be cleared
    @ layer_to_clear (number) the number (1-4) of the layer to clear
    ]]
    function layer.clear(region, layer_to_clear)
        layer_to_clear = layer_to_clear - 1 -- Turn 1 based layer to 0 based layer
        local start = region.StartMeasure
        local stop = region.EndMeasure
        local sysstaves = finale.FCSystemStaves()
        sysstaves:LoadAllForRegion(region)
        for sysstaff in each(sysstaves) do
            staffNum = sysstaff.Staff
            local  noteentry_layer = finale.FCNoteEntryLayer(layer_to_clear, staffNum, start, stop)
            noteentry_layer:SetUseVisibleLayer(false)
            noteentry_layer:Load()
            noteentry_layer:ClearAllEntries()
        end
    end
    
    --[[
    % swap
    
    Swaps the entries from two different layers (e.g. 1-->2 and 2-->1).
    
    @ region (FCMusicRegion) the region to be swapped
    @ swap_a (number) the number (1-4) of the first layer to be swapped
    @ swap_b (number) the number (1-4) of the second layer to be swapped
    ]]
    function layer.swap(region, swap_a, swap_b)
        -- Set layers for 0 based
        swap_a = swap_a - 1
        swap_b = swap_b - 1
        for measure, staff_number in eachcell(region) do
            local cell_frame_hold = finale.FCCellFrameHold()    
            cell_frame_hold:ConnectCell(finale.FCCell(measure, staff_number))
            local loaded = cell_frame_hold:Load()
            local cell_clef_changes = loaded and cell_frame_hold.IsClefList and cell_frame_hold:CreateCellClefChanges() or nil
            local  noteentry_layer_one = finale.FCNoteEntryLayer(swap_a, staff_number, measure, measure)
            noteentry_layer_one:SetUseVisibleLayer(false)
            noteentry_layer_one:Load()
            noteentry_layer_one.LayerIndex = swap_b
            --
            local  noteentry_layer_two = finale.FCNoteEntryLayer(swap_b, staff_number, measure, measure)
            noteentry_layer_two:SetUseVisibleLayer(false)
            noteentry_layer_two:Load()
            noteentry_layer_two.LayerIndex = swap_a
            noteentry_layer_one:Save()
            noteentry_layer_two:Save()
            if loaded then
                local new_cell_frame_hold = finale.FCCellFrameHold()
                new_cell_frame_hold:ConnectCell(finale.FCCell(measure, staff_number))
                if new_cell_frame_hold:Load() then
                    if cell_frame_hold.IsClefList then
                        if new_cell_frame_hold.SetCellClefChanges then
                            new_cell_frame_hold:SetCellClefChanges(cell_clef_changes)
                        end
                        -- No remedy here in JW Lua. The clef list can be changed by a layer swap.
                    else
                        new_cell_frame_hold.ClefIndex = cell_frame_hold.ClefIndex
                    end
                    new_cell_frame_hold:Save()
                end
            end
        end
    end
    
    
    --[[
    % max_layers
    
    Return the maximum number of layers available in the current document.
    
    : (number) maximum number of available layers
    ]]
    function layer.max_layers()
        return finale.FCLayerPrefs.GetMaxLayers and finale.FCLayerPrefs.GetMaxLayers() or 4
    end
    
    return layer

end

__imports["mixin.FCMControl"] = __imports["mixin.FCMControl"] or function()
    --  Author: Edward Koltun
    --  Date: March 3, 2022
    --[[
    $module FCMControl

    Summary of modifications:
    - Setters that accept `FCString` now also accept Lua `string` and `number`.
    - In getters with an `FCString` parameter, the parameter is now optional and a Lua `string` is returned. 
    - Ported `GetParent` from PDK to allow the parent window to be accessed from a control.
    - Handlers for the `Command` event can now be set on a control.
    - Added methods for storing and restoring control state, which allows controls to correctly maintain their values across multiple script executions
    ]] --
    local mixin = require("library.mixin")
    local mixin_helper = require("library.mixin_helper")

    -- So as not to prevent the window (and by extension the controls) from being garbage collected in the normal way, use weak keys and values for storing the parent window
    local parent = setmetatable({}, {__mode = "kv"})
    local private = setmetatable({}, {__mode = "k"})
    local props = {}

    local temp_str = finale.FCString()

    --[[
    % Init

    **[Internal]**

    @ self (FCMControl)
    ]]
    function props:Init()
        private[self] = private[self] or {}
    end

    --[[
    % GetParent

    **[PDK Port]**
    Returns the control's parent window.
    Do not override or disable this method.

    @ self (FCMControl)
    : (FCMCustomWindow)
    ]]
    function props:GetParent()
        return parent[self]
    end

    --[[
    % RegisterParent

    **[Fluid] [Internal]**
    Used to register the parent window when the control is created.
    Do not disable this method.

    @ self (FCMControl)
    @ window (FCMCustomWindow)
    ]]
    function props:RegisterParent(window)
        mixin.assert_argument(window, {"FCMCustomWindow", "FCMCustomLuaWindow"}, 2)

        if parent[self] then
            error("This method is for internal use only.", 2)
        end

        parent[self] = window
    end

    --[[
    % GetEnable

    **[Override]**
    Hooks into control state restoration.

    @ self (FCMControl)
    : (boolean)
    ]]

    --[[
    % SetEnable

    **[Fluid] [Override]**
    Hooks into control state restoration.

    @ self (FCMControl)
    @ enable (boolean)
    ]]

    --[[
    % GetVisible

    **[Override]**
    Hooks into control state restoration.

    @ self (FCMControl)
    : (boolean)
    ]]

    --[[
    % SetVisible

    **[Fluid] [Override]**
    Hooks into control state restoration.

    @ self (FCMControl)
    @ visible (boolean)
    ]]

    --[[
    % GetLeft

    **[Override]**
    Hooks into control state restoration.

    @ self (FCMControl)
    : (number)
    ]]

    --[[
    % SetLeft

    **[Fluid] [Override]**
    Hooks into control state restoration.

    @ self (FCMControl)
    @ left (number)
    ]]

    --[[
    % GetTop

    **[Override]**
    Hooks into control state restoration.

    @ self (FCMControl)
    : (number)
    ]]

    --[[
    % SetTop

    **[Fluid] [Override]**
    Hooks into control state restoration.

    @ self (FCMControl)
    @ top (number)
    ]]

    --[[
    % GetHeight

    **[Override]**
    Hooks into control state restoration.

    @ self (FCMControl)
    : (number)
    ]]

    --[[
    % SetHeight

    **[Fluid] [Override]**
    Hooks into control state restoration.

    @ self (FCMControl)
    @ height (number)
    ]]

    --[[
    % GetWidth

    **[Override]**
    Hooks into control state restoration.

    @ self (FCMControl)
    : (number)
    ]]

    --[[
    % SetWidth

    **[Fluid] [Override]**
    Hooks into control state restoration.

    @ self (FCMControl)
    @ width (number)
    ]]
    for method, valid_types in pairs({
        Enable = {"boolean", "nil"},
        Visible = {"boolean", "nil"},
        Left = "number",
        Top = "number",
        Height = "number",
        Width = "number",
    }) do
        props["Get" .. method] = function(self)
            if mixin.FCMControl.UseStoredState(self) then
                return private[self][method]
            end

            return self["Get" .. method .. "_"](self)
        end

        props["Set" .. method] = function(self, value)
            mixin.assert_argument(value, valid_types, 2)

            if mixin.FCMControl.UseStoredState(self) then
                private[self][method] = value
            else
                -- Fix bug with text box content being cleared on Mac when Enabled or Visible state is changed
                if (method == "Enable" or method == "Visible") and finenv.UI():IsOnMac() and finenv.MajorVersion == 0 and finenv.MinorVersion < 63 then
                    self:GetText_(temp_str)
                    self:SetText_(temp_str)
                end

                self["Set" .. method .. "_"](self, value)
            end
        end
    end


    --[[
    % GetText

    **[Override]**
    Returns a Lua `string` and makes passing an `FCString` optional.
    Also hooks into control state restoration.

    @ self (FCMControl)
    @ [str] (FCString)
    : (string)
    ]]
    function props:GetText(str)
        mixin.assert_argument(str, {"nil", "FCString"}, 2)

        if not str then
            str = temp_str
        end

        if mixin.FCMControl.UseStoredState(self) then
            str.LuaString = private[self].Text
        else
            self:GetText_(str)
        end

        return str.LuaString
    end

    --[[
    % SetText

    **[Fluid] [Override]**
    Accepts Lua `string` and `number` in addition to `FCString`.
    Also hooks into control state restoration.

    @ self (FCMControl)
    @ str (FCString|string|number)
    ]]
    function props:SetText(str)
        mixin.assert_argument(str, {"string", "number", "FCString"}, 2)

        if type(str) ~= "userdata" then
            temp_str.LuaString = tostring(str)
            str = temp_str
        end

        if mixin.FCMControl.UseStoredState(self) then
            private[self].Text = str.LuaString
        else
            self:SetText_(str)
        end
    end

    --[[
    % UseStoredState

    **[Internal]**
    Checks if this control should use its stored state instead of the live state from the control.
    Do not override or disable this method.

    @ self (FCMControl)
    : (boolean)
    ]]
    function props:UseStoredState()
        local parent = self:GetParent()
        return mixin.is_instance_of(parent, "FCMCustomLuaWindow") and parent:GetRestoreControlState() and not parent:WindowExists() and parent:HasBeenShown()
    end

    --[[
    % StoreState

    **[Fluid] [Internal]**
    Stores the control's current state.
    Do not disable this method. Override as needed but call the parent first.

    @ self (FCMControl)
    ]]
    function props:StoreState()
        self:GetText_(temp_str)
        private[self].Text = temp_str.LuaString
        private[self].Enable = self:GetEnable_()
        private[self].Visible = self:GetVisible_()
        private[self].Left = self:GetLeft_()
        private[self].Top = self:GetTop_()
        private[self].Height = self:GetHeight_()
        private[self].Width = self:GetWidth_()
    end

    --[[
    % RestoreState

    **[Fluid] [Internal]**
    Restores the control's stored state.
    Do not disable this method. Override as needed but call the parent first.

    @ self (FCMControl)
    ]]
    function props:RestoreState()
        self:SetEnable_(private[self].Enable)
        self:SetVisible_(private[self].Visible)
        self:SetLeft_(private[self].Left)
        self:SetTop_(private[self].Top)
        self:SetHeight_(private[self].Height)
        self:SetWidth_(private[self].Width)

        -- Call SetText last to work around the Mac text box issue described above
        temp_str.LuaString = private[self].Text
        self:SetText_(temp_str)
    end

    --[[
    % AddHandleCommand

    **[Fluid]**
    Adds a handler for command events.

    @ self (FCMControl)
    @ callback (function) See `FCCustomLuaWindow.HandleCommand` in the PDK for callback signature.
    ]]

    --[[
    % RemoveHandleCommand

    **[Fluid]**
    Removes a handler added with `AddHandleCommand`.

    @ self (FCMControl)
    @ callback (function)
    ]]
    props.AddHandleCommand, props.RemoveHandleCommand = mixin_helper.create_standard_control_event("HandleCommand")

    return props

end

__imports["mixin.FCMCtrlButton"] = __imports["mixin.FCMCtrlButton"] or function()
    --  Author: Edward Koltun
    --  Date: April 3, 2022
    --[[
    $module FCMCtrlButton

    The following methods have been disabled from `FCMCtrlCheckbox`:
    - `AddHandleCheckChange`
    - `RemoveHandleCheckChange`

    To handle button presses, use `AddHandleCommand` inherited from `FCMControl`.
    ]] --
    local mixin_helper = require("library.mixin_helper")

    local props = {}

    mixin_helper.disable_methods(props, "AddHandleCheckChange", "RemoveHandleCheckChange")

    return props

end

__imports["mixin.FCMCtrlCheckbox"] = __imports["mixin.FCMCtrlCheckbox"] or function()
    --  Author: Edward Koltun
    --  Date: April 2, 2022
    --[[
    $module FCMCtrlCheckbox

    Summary of modifications:
    - Added `CheckChange` custom control event.
    ]] --
    local mixin = require("library.mixin")
    local mixin_helper = require("library.mixin_helper")

    local props = {}

    local trigger_check_change
    local each_last_check_change

    --[[
    % SetCheck

    **[Fluid] [Override]**
    Ensures that `CheckChange` event is triggered.

    @ self (FCMCtrlCheckbox)
    @ checked (number)
    ]]
    function props:SetCheck(checked)
        mixin.assert_argument(checked, "number", 2)

        self:SetCheck_(checked)

        trigger_check_change(self)
    end

    --[[
    % HandleCheckChange

    **[Callback Template]**

    @ control (FCMCtrlCheckbox) The control that was changed.
    @ last_check (string) The previous value of the control's check state..
    ]]

    --[[
    % AddHandleChange

    **[Fluid]**
    Adds a handler for when the value of the control's check state changes.
    The even will fire when:
    - The window is created (if the check state is not `0`)
    - The control is checked/unchecked by the user
    - The control's check state is changed programmatically (if the check state is changed within a handler, that *same* handler will not be called again for that change.)

    @ self (FCMCtrlCheckbox)
    @ callback (function) See `HandleCheckChange` for callback signature.
    ]]

    --[[
    % RemoveHandleCheckChange

    **[Fluid]**
    Removes a handler added with `AddHandleCheckChange`.

    @ self (FCMCtrlCheckbox)
    @ callback (function)
    ]]
    props.AddHandleCheckChange, props.RemoveHandleCheckChange, trigger_check_change, each_last_check_change =
        mixin_helper.create_custom_control_change_event(
            -- initial could be set to -1 to force the event to fire on InitWindow, but unlike other controls, -1 is not a valid checkstate.
            -- If it becomes necessary to force this event to fire when the window is created, change to -1
            {name = "last_check", get = "GetCheck_", initial = 0})

    return props

end

__imports["mixin.FCMCtrlDataList"] = __imports["mixin.FCMCtrlDataList"] or function()
    --  Author: Edward Koltun
    --  Date: March 3, 2022
    --[[
    $module FCMCtrlDataList

    Summary of modifications:
    - Setters that accept `FCString` now also accept Lua `string` and `number`.
    - Handlers for the `DataListCheck` and `DataListSelect` events can now be set on a control.
    ]] --
    local mixin = require("library.mixin")
    local mixin_helper = require("library.mixin_helper")

    local props = {}

    local temp_str = finale.FCString()

    --[[
    % AddColumn

    **[Fluid] [Override]**
    Accepts Lua `string` and `number` in addition to `FCString`.

    @ self (FCMCtrlDataList)
    @ title (FCString|string|number)
    @ columnwidth (number)
    ]]
    function props:AddColumn(title, columnwidth)
        mixin.assert_argument(title, {"string", "number", "FCString"}, 2)
        mixin.assert_argument(columnwidth, "number", 3)

        if type(title) ~= "userdata" then
            temp_str.LuaString = tostring(title)
            title = temp_str
        end

        self:AddColumn_(title, columnwidth)
    end

    --[[
    % SetColumnTitle

    **[Fluid] [Override]**
    Accepts Lua `string` and `number` in addition to `FCString`.

    @ self (FCMCtrlDataList)
    @ columnindex (number)
    @ title (FCString|string|number)
    ]]
    function props:SetColumnTitle(columnindex, title)
        mixin.assert_argument(columnindex, "number", 2)
        mixin.assert_argument(title, {"string", "number", "FCString"}, 3)

        if type(title) ~= "userdata" then
            temp_str.LuaString = tostring(title)
            title = temp_str
        end

        self:SetColumnTitle_(columnindex, title)
    end

    --[[
    % AddHandleCheck

    **[Fluid]**
    Adds a handler for DataListCheck events.

    @ self (FCMCtrlDataList)
    @ callback (function) See `FCCustomLuaWindow.HandleDataListCheck` in the PDK for callback signature.
    ]]

    --[[
    % RemoveHandleCheck

    **[Fluid]**
    Removes a handler added with `AddHandleCheck`.

    @ self (FCMCtrlDataList)
    @ callback (function)
    ]]
    props.AddHandleCheck, props.RemoveHandleCheck = mixin_helper.create_standard_control_event("HandleDataListCheck")

    --[[
    % AddHandleSelect

    **[Fluid]**
    Adds a handler for DataListSelect events.

    @ self (FCMControl)
    @ callback (function) See `FCCustomLuaWindow.HandleDataListSelect` in the PDK for callback signature.
    ]]

    --[[
    % RemoveHandleSelect

    **[Fluid]**
    Removes a handler added with `AddHandleSelect`.

    @ self (FCMControl)
    @ callback (function)
    ]]
    props.AddHandleSelect, props.RemoveHandleSelect = mixin_helper.create_standard_control_event("HandleDataListSelect")

    return props

end

__imports["mixin.FCMCtrlEdit"] = __imports["mixin.FCMCtrlEdit"] or function()
    --  Author: Edward Koltun
    --  Date: March 3, 2022
    --[[
    $module FCMCtrlEdit

    Summary of modifications:
    - Added `Change` custom control event.
    - Added hooks for restoring control state
    ]] --
    local mixin = require("library.mixin")
    local mixin_helper = require("library.mixin_helper")
    local utils = require("library.utils")

    local props = {}

    local trigger_change
    local each_last_change
    local temp_str = mixin.FCMString()

    --[[
    % SetText

    **[Fluid] [Override]**
    Ensures that `Change` event is triggered.

    @ self (FCMCtrlEdit)
    @ str (FCString|string|number)
    ]]
    function props:SetText(str)
        mixin.assert_argument(str, {"string", "number", "FCString"}, 2)

        mixin.FCMControl.SetText(self, str)
        trigger_change(self)
    end

    --[[
    % GetInteger

    **[Override]**
    Hooks into control state restoration.

    @ self (FCMCtrlEdit)
    : (number)
    ]]

    --[[
    % SetInteger

    **[Fluid] [Override]**
    Ensures that `Change` event is triggered.
    Also hooks into control state restoration.

    @ self (FCMCtrlEdit)
    @ anint (number)
    ]]

    --[[
    % GetFloat

    **[Override]**
    Hooks into control state restoration.

    @ self (FCMCtrlEdit)
    : (number)
    ]]

    --[[
    % SetFloat

    **[Fluid] [Override]**
    Ensures that `Change` event is triggered.
    Also hooks into control state restoration.

    @ self (FCMCtrlEdit)
    @ value (number)
    ]]
    for method, valid_types in pairs({
        Integer = "number",
        Float = "number",
    }) do
        props["Get" .. method] = function(self)
            -- This is the long way around, but it ensures that the correct control value is used
            mixin.FCMControl.GetText(self, temp_str)
            return temp_str["Get" .. method](temp_str, 0)
        end

        props["Set" .. method] = function(self, value)
            mixin.assert_argument(value, valid_types, 2)

            temp_str["Set" .. method](temp_str, value)
            mixin.FCMControl.SetText(self, temp_str)
            trigger_change(self)
        end
    end

    --[[
    % GetMeasurement

    **[Override]**
    Hooks into control state restoration.

    @ self (FCMCtrlEdit)
    @ measurementunit (number) Any of the finale.MEASUREMENTUNIT_* constants.
    : (number)
    ]]

    --[[
    % SetMeasurement

    **[Fluid] [Override]**
    Ensures that `Change` event is triggered.
    Also hooks into control state restoration.

    @ self (FCMCtrlEdit)
    @ value (number)
    @ measurementunit (number)
    ]]

    --[[
    % GetMeasurementEfix

    **[Override]**
    Hooks into control state restoration.

    @ self (FCMCtrlEdit)
    @ measurementunit (number) Any of the finale.MEASUREMENTUNIT_* constants.
    : (number)
    ]]

    --[[
    % SetMeasurementEfix

    **[Fluid] [Override]**
    Ensures that `Change` event is triggered.
    Also hooks into control state restoration.

    @ self (FCMCtrlEdit)
    @ value (number)
    @ measurementunit (number)
    ]]

    --[[
    % GetMeasurementInteger

    **[Override]**
    Hooks into control state restoration.

    @ self (FCMCtrlEdit)
    @ measurementunit (number) Any of the finale.MEASUREMENTUNIT_* constants.
    : (number)
    ]]

    --[[
    % SetMeasurementInteger

    **[Fluid] [Override]**
    Ensures that `Change` event is triggered.
    Also hooks into control state restoration.

    @ self (FCMCtrlEdit)
    @ value (number)
    @ measurementunit (number)
    ]]
    for method, valid_types in pairs({
        Measurement = "number",
        MeasurementEfix = "number",
        MeasurementInteger = "number",
    }) do
        props["Get" .. method] = function(self, measurementunit)
            mixin.assert_argument(measurementunit, "number", 2)

            mixin.FCMControl.GetText(self, temp_str)
            return temp_str["Get" .. method](temp_str, measurementunit)
        end

        props["Set" .. method] = function(self, value, measurementunit)
            mixin.assert_argument(value, valid_types, 2)
            mixin.assert_argument(measurementunit, "number", 3)

            temp_str["Set" .. method](temp_str, value, measurementunit)
            mixin.FCMControl.SetText(self, temp_str)
            trigger_change(self)
        end
    end

    --[[
    % GetRangeInteger

    **[Override]**
    Hooks into control state restoration.

    @ self (FCMCtrlEdit)
    @ minimum (number)
    @ maximum (number)
    : (number)
    ]]
    function props:GetRangeInteger(minimum, maximum)
        mixin.assert_argument(minimum, "number", 2)
        mixin.assert_argument(maximum, "number", 3)

        return utils.clamp(mixin.FCMCtrlEdit.GetInteger(self), math.floor(minimum), math.floor(maximum))
    end

    --[[
    % GetRangeMeasurement

    **[Override]**
    Hooks into control state restoration.

    @ self (FCMCtrlEdit)
    @ measurementunit (number) Any of the finale.MEASUREMENTUNIT_* constants.
    @ minimum (number)
    @ maximum (number)
    : (number)
    ]]
    function props:GetRangeMeasurement(measurementunit, minimum, maximum)
        mixin.assert_argument(measurementunit, "number", 2)
        mixin.assert_argument(minimum, "number", 3)
        mixin.assert_argument(maximum, "number", 4)

        return utils.clamp(mixin.FCMCtrlEdit.GetMeasurement(self, measurementunit), minimum, maximum)
    end

    --[[
    % GetRangeMeasurementEfix

    **[Override]**
    Hooks into control state restoration.

    @ self (FCMCtrlEdit)
    @ measurementunit (number) Any of the finale.MEASUREMENTUNIT_* constants.
    @ minimum (number)
    @ maximum (number)
    : (number)
    ]]
    function props:GetRangeMeasurementEfix(measurementunit, minimum, maximum)
        mixin.assert_argument(measurementunit, "number", 2)
        mixin.assert_argument(minimum, "number", 3)
        mixin.assert_argument(maximum, "number", 4)

        return utils.clamp(mixin.FCMCtrlEdit.GetMeasurementEfix(self, measurementunit), minimum, maximum)
    end

    --[[
    % GetRangeMeasurementInteger

    **[Override]**
    Hooks into control state restoration.

    @ self (FCMCtrlEdit)
    @ measurementunit (number) Any of the finale.MEASUREMENTUNIT_* constants.
    @ minimum (number)
    @ maximum (number)
    : (number)
    ]]
    function props:GetRangeMeasurementInteger(measurementunit, minimum, maximum)
        mixin.assert_argument(measurementunit, "number", 2)
        mixin.assert_argument(minimum, "number", 3)
        mixin.assert_argument(maximum, "number", 4)

        return utils.clamp(mixin.FCMCtrlEdit.GetMeasurementInteger(self, measurementunit), math.floor(minimum), math.floor(maximum))
    end

    --[[
    % HandleChange

    **[Callback Template]**

    @ control (FCMCtrlEdit) The control that was changed.
    @ last_value (string) The previous value of the control.
    ]]

    --[[
    % AddHandleChange

    **[Fluid]**
    Adds a handler for when the value of the control changes.
    The even will fire when:
    - The window is created (if the value of the control is not an empty string)
    - The value of the control is changed by the user
    - The value of the control is changed programmatically (if the value of the control is changed within a handler, that *same* handler will not be called again for that change.)

    @ self (FCMCtrlEdit)
    @ callback (function) See `HandleChange` for callback signature.
    ]]

    --[[
    % RemoveHandleChange

    **[Fluid]**
    Removes a handler added with `AddHandleChange`.

    @ self (FCMCtrlEdit)
    @ callback (function)
    ]]
    props.AddHandleChange, props.RemoveHandleChange, trigger_change, each_last_change = mixin_helper.create_custom_control_change_event(
        {
            name = "last_value",
            get = mixin.FCMControl.GetText,
            initial = ""
        }
    )

    return props

end

__imports["mixin.FCMCtrlListBox"] = __imports["mixin.FCMCtrlListBox"] or function()
    --  Author: Edward Koltun
    --  Date: April 4, 2022
    --[[
    $module FCMCtrlListBox

    Summary of modifications:
    - Setters that accept `FCString` now also accept Lua `string` and `number`.
    - In getters with an `FCString` parameter, the parameter is now optional and a Lua `string` is returned. 
    - Setters that accept `FCStrings` now also accept multiple arguments of `FCString`, Lua `string`, or `number`.
    - Numerous additional methods for accessing and modifying listbox items.
    - Added `SelectionChange` custom control event.
    ]] --
    local mixin = require("library.mixin")
    local mixin_helper = require("library.mixin_helper")
    local library = require("library.general_library")
    local utils = require("library.utils")

    local private = setmetatable({}, {__mode = "k"})
    local props = {}

    local trigger_selection_change
    local each_last_selection_change
    local temp_str = finale.FCString()

    --[[
    % Init

    **[Internal]**

    @ self (FCMCtrlListBox)
    ]]
    function props:Init()
        private[self] = private[self] or {}
    end

    --[[
    % Clear

    **[Fluid] [Override]**

    @ self (FCMCtrlListBox)
    ]]
    function props:Clear()
        self:Clear_()
        private[self] = {}

        for v in each_last_selection_change(self) do
            if v.last_item >= 0 then
                v.is_deleted = true
            end
        end

        trigger_selection_change(self)
    end

    --[[
    % SetSelectedItem

    **[Fluid] [Override]**
    Ensures that `SelectionChange` is triggered.

    @ self (FCMCtrlListBox)
    @ index (number)
    ]]
    function props:SetSelectedItem(index)
        mixin.assert_argument(index, "number", 2)

        self:SetSelectedItem_(index)

        trigger_selection_change(self)
    end

    --[[
    % SetSelectedLast

    **[Override]**
    Ensures that `SelectionChange` is triggered.

    @ self (FCMCtrlListBox)
    : (boolean) `true` if a selection was possible.
    ]]
    function props:SetSelectedLast()
        trigger_selection_change(self)
        return self:SetSelectedLast_()
    end

    --[[
    % AddString

    **[Fluid] [Override]**

    Accepts Lua `string` and `number` in addition to `FCString`.

    @ self (FCMCtrlListBox)
    @ str (FCString|string|number)
    ]]
    function props:AddString(str)
        mixin.assert_argument(str, {"string", "number", "FCString"}, 2)

        if type(str) ~= "userdata" then
            temp_str.LuaString = tostring(str)
            str = temp_str
        end

        self:AddString_(str)

        -- Since we've made it here without errors, str must be an FCString
        table.insert(private[self], str.LuaString)
    end

    --[[
    % AddStrings

    **[Fluid]**
    Adds multiple strings to the list box.

    @ self (FCMCtrlListBox)
    @ ... (FCStrings|FCString|string|number)
    ]]
    function props:AddStrings(...)
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            mixin.assert_argument(v, {"string", "number", "FCString", "FCStrings"}, i + 1)

            if type(v) == "userdata" and v:ClassName() == "FCStrings" then
                for str in each(v) do
                    mixin.FCMCtrlListBox.AddString(self, str)
                end
            else
                mixin.FCMCtrlListBox.AddString(self, v)
            end
        end
    end

    --[[
    % GetStrings

    Returns a copy of all strings in the list box.

    @ self (FCMCtrlListBox)
    @ [strs] (FCStrings) An optional `FCStrings` object to populate with strings.
    : (table) A table of strings (1-indexed - beware if accessing keys!).
    ]]
    function props:GetStrings(strs)
        mixin.assert_argument(strs, {"nil", "FCStrings"}, 2)

        if strs then
            strs:ClearAll()
            for _, v in ipairs(private[self]) do
                temp_str.LuaString = v
                strs:AddCopy(temp_str)
            end
        end

        return utils.copy_table(private[self])
    end

    --[[
    % SetStrings

    **[Fluid] [Override]**
    Accepts multiple arguments.

    @ self (FCMCtrlListBox)
    @ ... (FCStrings|FCString|string|number) `number`s will be automatically cast to `string`
    ]]
    function props:SetStrings(...)
        -- No argument validation in this method for now...
        local strs = select(1, ...)
        if select("#", ...) ~= 1 or not library.is_finale_object(strs) or strs:ClassName() ~= "FCStrings" then
            strs = mixin.FCMStrings()
            strs:CopyFrom(...)
        end

        self:SetStrings_(strs)

        private[self] = {}
        for str in each(strs) do
            table.insert(private[self], str.LuaString)
        end

        for v in each_last_selection_change(self) do
            if v.last_item >= 0 then
                v.is_deleted = true
            end
        end

        trigger_selection_change(self)
    end

    --[[
    % GetItemText

    Returns the text for an item in the list box.
    This method works in all JW/RGP Lua versions and irrespective of whether `InitWindow` has been called.

    @ self (FCMCtrlListBox)
    @ index (number) 0-based index of item.
    @ [str] (FCString) Optional `FCString` object to populate with text.
    : (string)
    ]]
    function props:GetItemText(index, str)
        mixin.assert_argument(index, "number", 2)
        mixin.assert_argument(str, {"nil", "FCString"}, 3)

        if not private[self][index + 1] then
            error("No item at index " .. tostring(index), 2)
        end

        if str then
            str.LuaString = private[self][index + 1]
        end

        return private[self][index + 1]
    end

    --[[
    % SetItemText

    **[Fluid] [PDK Port]**
    Sets the text for an item.

    @ self (FCMCtrlListBox)
    @ index (number) 0-based index of item.
    @ str (FCString|string|number)
    ]]
    function props:SetItemText(index, str)
        mixin.assert_argument(index, "number", 2)
        mixin.assert_argument(str, {"string", "number", "FCString"}, 3)

        if not private[self][index + 1] then
            error("No item at index " .. tostring(index), 2)
        end

        private[self][index + 1] = type(str) == "userdata" and str.LuaString or tostring(str)

        -- SetItemText was added to RGPLua in v0.56 and only works once the window has been created
        if self:GetParent():WindowExists_() and self.SetItemText_ then
            temp_str.LuaString = private[self][index + 1]
            self:SetItemText_(index, temp_str)

            -- Otherwise, use a polyfill
        else
            local strs = finale.FCStrings()
            for _, v in ipairs(private[self]) do
                temp_str.LuaString = v
                strs:AddCopy(temp_str)
            end

            local curr_item = self:GetSelectedItem_()
            self:SetStrings_(strs)
            self:SetSelectedItem_(curr_item)
        end
    end

    --[[
    % GetSelectedString

    Returns the text for the item that is currently selected.

    @ self (FCMCtrlListBox)
    @ [str] (FCString) Optional `FCString` object to populate with text. If no item is currently selected, it will be populated with an empty string.
    : (string|nil) `nil` if no item is currently selected.
    ]]
    function props:GetSelectedString(str)
        mixin.assert_argument(str, {"nil", "FCString"}, 2)

        local index = self:GetSelectedItem_()

        if index ~= -1 then
            if str then
                str.LuaString = private[self][index + 1]
            end

            return private[self][index + 1]
        else
            if str then
                str.LuaString = ""
            end

            return nil
        end
    end

    --[[
    % SetSelectedString

    **[Fluid]**
    Sets the currently selected item to the first item with a matching text value.

    If no match is found, the current selected item will remain selected.

    @ self (FCMCtrlListBox)
    @ str (FCString|string|number)
    ]]
    function props:SetSelectedString(str)
        mixin.assert_argument(str, {"string", "number", "FCString"}, 2)

        str = type(str) == "userdata" and str.LuaString or tostring(str)

        for k, v in ipairs(private[self]) do
            if str == v then
                self:SetSelectedItem_(k - 1)
                trigger_selection_change(self)
                return
            end
        end
    end

    --[[
    % InsertItem

    **[Fluid] [PDKPort]**
    Inserts a string at the specified index.
    If index is <= 0, will insert at the start.
    If index is >= Count, will insert at the end.

    @ self (FCMCtrlListBox)
    @ index (number) 0-based index to insert new item.
    @ str (FCString|string|number) The value to insert.
    ]]
    function props:InsertItem(index, str)
        mixin.assert_argument(index, "number", 2)
        mixin.assert_argument(str, {"string", "number", "FCString"}, 3)

        if index < 0 then
            index = 0
        elseif index >= #private[self] then
            self:AddString(str)
            return
        end

        table.insert(private[self], index + 1, type(str) == "userdata" and str.LuaString or tostring(str))

        local strs = finale.FCStrings()
        for _, v in ipairs(private[self]) do
            temp_str.LuaString = v
            strs:AddCopy(temp_str)
        end

        local curr_item = self:GetSelectedItem()
        self:SetStrings_(strs)

        if curr_item >= index then
            self:SetSelectedItem_(curr_item + 1)
        else
            self:SetSelectedItem_(curr_item)
        end

        for v in each_last_selection_change(self) do
            if v.last_item >= index then
                v.last_item = v.last_item + 1
            end
        end
    end

    --[[
    % DeleteItem

    **[Fluid] [PDK Port]**
    Deletes an item from the list box.
    If the currently selected item is deleted, items will be deselected (ie set to -1)

    @ self (FCMCtrlListBox)
    @ index (number) 0-based index of item to delete.
    ]]
    function props:DeleteItem(index)
        mixin.assert_argument(index, "number", 2)

        if index < 0 or index >= #private[self] then
            return
        end

        table.remove(private[self], index + 1)

        local strs = finale.FCStrings()
        for _, v in ipairs(private[self]) do
            temp_str.LuaString = v
            strs:AddCopy(temp_str)
        end

        local curr_item = self:GetSelectedItem()
        self:SetStrings_(strs)

        if curr_item > index then
            self:SetSelectedItem_(curr_item - 1)
        elseif curr_item == index then
            self:SetSelectedItem_(-1)
        else
            self:SetSelectedItem_(curr_item)
        end

        for v in each_last_selection_change(self) do
            if v.last_item == index then
                v.is_deleted = true
            elseif v.last_item > index then
                v.last_item = v.last_item - 1
            end
        end

        -- Only need to trigger event if the current selection was deleted
        if curr_item == index then
            trigger_selection_change(self)
        end
    end

    --[[
    % HandleSelectionChange

    **[Callback Template]**

    @ control (FCMCtrlListBox)
    @ last_item (number) The 0-based index of the previously selected item. If no item was selected, the value will be `-1`.
    @ last_item_text (string) The text value of the previously selected item.
    @ is_deleted (boolean) `true` if the previously selected item is no longer in the control.
    ]]

    --[[
    % AddHandleSelectionChange

    **[Fluid]**
    Adds a handler for SelectionChange events.
    If the selected item is changed by a handler, that same handler will not be called again for that change.

    The event will fire in the following cases:
    - When the window is created (if an item is selected)
    - Change in selected item by user or programatically (inserting an item before or after will not trigger the event)
    - Changing the text value of the currently selected item
    - Deleting the currently selected item
    - Clearing the control (including calling `Clear` and `SetStrings`)

    @ self (FCMCtrlListBox)
    @ callback (function) See `HandleSelectionChange` for callback signature.
    ]]

    --[[
    % RemoveHandleSelectionChange

    **[Fluid]**
    Removes a handler added with `AddHandleSelectionChange`.

    @ self (FCMCtrlListBox)
    @ callback (function) Handler to remove.
    ]]
    props.AddHandleSelectionChange, props.RemoveHandleSelectionChange, trigger_selection_change, each_last_selection_change =
        mixin_helper.create_custom_control_change_event(
            {name = "last_item", get = "GetSelectedItem_", initial = -1}, {
                name = "last_item_text",
                get = function(ctrl)
                    return mixin.FCMCtrlListBox.GetSelectedString(ctrl) or ""
                end,
                initial = "",
            }, {
                name = "is_deleted",
                get = function()
                    return false
                end,
                initial = false,
            })

    return props

end

__imports["mixin.FCMCtrlPopup"] = __imports["mixin.FCMCtrlPopup"] or function()
    --  Author: Edward Koltun
    --  Date: March 3, 2022
    --[[
    $module FCMCtrlPopup

    Summary of modifications:
    - Setters that accept `FCString` now also accept Lua `string` and `number`.
    - In getters with an `FCString` parameter, the parameter is now optional and a Lua `string` is returned. 
    - Setters that accept `FCStrings` now also accept multiple arguments of `FCString`, Lua `string`, or `number`.
    - Numerous additional methods for accessing and modifying popup items.
    - Added `SelectionChange` custom control event.
    ]] --
    local mixin = require("library.mixin")
    local mixin_helper = require("library.mixin_helper")
    local library = require("library.general_library")
    local utils = require("library.utils")

    local private = setmetatable({}, {__mode = "k"})
    local props = {}

    local trigger_selection_change
    local each_last_selection_change
    local temp_str = finale.FCString()

    --[[
    % Init

    **[Internal]**

    @ self (FCMCtrlPopup)
    ]]
    function props:Init()
        private[self] = private[self] or {}
    end

    --[[
    % Clear

    **[Fluid] [Override]**

    @ self (FCMCtrlPopup)
    ]]
    function props:Clear()
        self:Clear_()
        private[self] = {}

        for v in each_last_selection_change(self) do
            if v.last_item >= 0 then
                v.is_deleted = true
            end
        end

        -- Clearing doesn't trigger a Command event (which in turn triggers SelectionChange), so we need to trigger it manually
        trigger_selection_change(self)
    end

    --[[
    % SetSelectedItem

    **[Fluid] [Override]**
    Ensures that SelectionChange is triggered.

    @ self (FCMCtrlPopup)
    @ index (number)
    ]]
    function props:SetSelectedItem(index)
        mixin.assert_argument(index, "number", 2)

        self:SetSelectedItem_(index)

        trigger_selection_change(self)
    end

    --[[
    % SetSelectedLast

    **[Fluid]**
    Selects the last item in the popup.

    @ self (FCMCtrlPopup)
    ]]
    function props:SetSelectedLast()
        if self:GetCount() ~= 0 then
            self:SetSelectedItem(self:GetCount() - 1)
        end
    end

    --[[
    % IsItemSelected

    Checks if the popup has a selection. If the parent window does not exist (ie `WindowExists() == false`), this result is theoretical.

    @ self (FCMCtrlPopup)
    : (boolean) `true` if something is selected, `false` if no selection.
    ]]
    function props:IsItemSelected()
        return self:GetSelectedItem_() >= 0
    end

    --[[
    % ItemExists

    Checks if there is an item at the specified index.

    @ self (FCMCtrlPopup)
    @ index (number)
    : (boolean) `true` if the item exists, `false` if it does not exist.
    ]]
    function props:ItemExists(index)
        mixin.assert_argument(index, "number", 2)

        return index <= self:GetCount_() - 1
    end

    --[[
    % AddString

    **[Fluid] [Override]**

    Accepts Lua `string` and `number` in addition to `FCString`.

    @ self (FCMCtrlPopup)
    @ str (FCString|string|number)
    ]]
    function props:AddString(str)
        mixin.assert_argument(str, {"string", "number", "FCString"}, 2)

        if type(str) ~= "userdata" then
            temp_str.LuaString = tostring(str)
            str = temp_str
        end

        self:AddString_(str)

        -- Since we've made it here without errors, str must be an FCString
        table.insert(private[self], str.LuaString)
    end

    --[[
    % AddStrings

    **[Fluid]**
    Adds multiple strings to the popup.

    @ self (FCMCtrlPopup)
    @ ... (FCStrings|FCString|string|number)
    ]]
    function props:AddStrings(...)
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            mixin.assert_argument(v, {"string", "number", "FCString", "FCStrings"}, i + 1)

            if type(v) == "userdata" and v:ClassName() == "FCStrings" then
                for str in each(v) do
                    mixin.FCMCtrlPopup.AddString(self, str)
                end
            else
                mixin.FCMCtrlPopup.AddString(self, v)
            end
        end
    end

    --[[
    % GetStrings

    Returns a copy of all strings in the popup.

    @ self (FCMCtrlPopup)
    @ [strs] (FCStrings) An optional `FCStrings` object to populate with strings.
    : (table) A table of strings (1-indexed - beware if accessing keys!).
    ]]
    function props:GetStrings(strs)
        mixin.assert_argument(strs, {"nil", "FCStrings"}, 2)

        if strs then
            strs:ClearAll()
            for _, v in ipairs(private[self]) do
                temp_str.LuaString = v
                strs:AddCopy(temp_str)
            end
        end

        return utils.copy_table(private[self])
    end

    --[[
    % SetStrings

    **[Fluid] [Override]**
    Accepts multiple arguments.

    @ self (FCMCtrlPopup)
    @ ... (FCStrings|FCString|string|number) `number`s will be automatically cast to `string`
    ]]
    function props:SetStrings(...)
        -- No argument validation in this method for now...
        local strs = select(1, ...)
        if select("#", ...) ~= 1 or not library.is_finale_object(strs) or strs:ClassName() ~= "FCStrings" then
            strs = mixin.FCMStrings()
            strs:CopyFrom(...)
        end

        self:SetStrings_(strs)

        private[self] = {}
        for str in each(strs) do
            table.insert(private[self], str.LuaString)
        end

        for v in each_last_selection_change(self) do
            if v.last_item >= 0 then
                v.is_deleted = true
            end
        end

        trigger_selection_change(self)
    end

    --[[
    % GetItemText

    Returns the text for an item in the popup.

    @ self (FCMCtrlPopup)
    @ index (number) 0-based index of item.
    @ [str] (FCString) Optional `FCString` object to populate with text.
    : (string|nil) `nil` if the item doesn't exist
    ]]
    function props:GetItemText(index, str)
        mixin.assert_argument(index, "number", 2)
        mixin.assert_argument(str, {"nil", "FCString"}, 3)

        if not private[self][index + 1] then
            error("No item at index " .. tostring(index), 2)
        end

        if str then
            str.LuaString = private[self][index + 1]
        end

        return private[self][index + 1]
    end

    --[[
    % SetItemText

    **[Fluid] [PDK Port]**
    Sets the text for an item.

    @ self (FCMCtrlPopup)
    @ index (number) 0-based index of item.
    @ str (FCString|string|number)
    ]]
    function props:SetItemText(index, str)
        mixin.assert_argument(index, "number", 2)
        mixin.assert_argument(str, {"string", "number", "FCString"}, 3)

        if not private[self][index + 1] then
            error("No item at index " .. tostring(index), 2)
        end

        str = type(str) == "userdata" and str.LuaString or tostring(str)

        -- If the text is the same, then there is nothing to do
        if private[self][index + 1] == str then
            return
        end

        private[self][index + 1] = type(str) == "userdata" and str.LuaString or tostring(str)

        local strs = finale.FCStrings()
        for _, v in ipairs(private[self]) do
            temp_str.LuaString = v
            strs:AddCopy(temp_str)
        end

        local curr_item = self:GetSelectedItem_()
        self:SetStrings_(strs)
        self:SetSelectedItem_(curr_item)
    end

    --[[
    % GetSelectedString

    Returns the text for the item that is currently selected.

    @ self (FCMCtrlPopup)
    @ [str] (FCString) Optional `FCString` object to populate with text. If no item is currently selected, it will be populated with an empty string.
    : (string|nil) `nil` if no item is currently selected.
    ]]
    function props:GetSelectedString(str)
        mixin.assert_argument(str, {"nil", "FCString"}, 2)

        local index = self:GetSelectedItem_()

        if index ~= -1 then
            if str then
                str.LuaString = private[self][index + 1]
            end

            return private[self][index + 1]
        else
            if str then
                str.LuaString = ""
            end

            return nil
        end
    end

    --[[
    % SetSelectedString

    **[Fluid]**
    Sets the currently selected item to the first item with a matching text value.

    If no match is found, the current selected item will remain selected.

    @ self (FCMCtrlPopup)
    @ str (FCString|string|number)
    ]]
    function props:SetSelectedString(str)
        mixin.assert_argument(str, {"string", "number", "FCString"}, 2)

        str = type(str) == "userdata" and str.LuaString or tostring(str)

        for k, v in ipairs(private[self]) do
            if str == v then
                self:SetSelectedItem_(k - 1)
                trigger_selection_change(self)
                return
            end
        end
    end

    --[[
    % InsertString

    **[Fluid] [PDKPort]**
    Inserts a string at the specified index.
    If index is <= 0, will insert at the start.
    If index is >= Count, will insert at the end.

    @ self (FCMCtrlPopup)
    @ index (number) 0-based index to insert new item.
    @ str (FCString|string|number) The value to insert.
    ]]
    function props:InsertString(index, str)
        mixin.assert_argument(index, "number", 2)
        mixin.assert_argument(str, {"string", "number", "FCString"}, 3)

        if index < 0 then
            index = 0
        elseif index >= #private[self] then
            self:AddString(str)
            return
        end

        table.insert(private[self], index + 1, type(str) == "userdata" and str.LuaString or tostring(str))

        local strs = finale.FCStrings()
        for _, v in ipairs(private[self]) do
            temp_str.LuaString = v
            strs:AddCopy(temp_str)
        end

        local curr_item = self:GetSelectedItem()
        self:SetStrings_(strs)

        if curr_item >= index then
            self:SetSelectedItem_(curr_item + 1)
        else
            self:SetSelectedItem_(curr_item)
        end

        for v in each_last_selection_change(self) do
            if v.last_item >= index then
                v.last_item = v.last_item + 1
            end
        end
    end

    --[[
    % DeleteItem

    **[Fluid] [PDK Port]**
    Deletes an item from the popup.
    If the currently selected item is deleted, items will be deselected (ie set to -1)

    @ self (FCMCtrlPopup)
    @ index (number) 0-based index of item to delete.
    ]]
    function props:DeleteItem(index)
        mixin.assert_argument(index, "number", 2)

        if index < 0 or index >= #private[self] then
            return
        end

        table.remove(private[self], index + 1)

        local strs = finale.FCStrings()
        for _, v in ipairs(private[self]) do
            temp_str.LuaString = v
            strs:AddCopy(temp_str)
        end

        local curr_item = self:GetSelectedItem()
        self:SetStrings_(strs)

        if curr_item > index then
            self:SetSelectedItem_(curr_item - 1)
        elseif curr_item == index then
            self:SetSelectedItem_(-1)
        else
            self:SetSelectedItem_(curr_item)
        end

        for v in each_last_selection_change(self) do
            if v.last_item == index then
                v.is_deleted = true
            elseif v.last_item > index then
                v.last_item = v.last_item - 1
            end
        end

        -- Only need to trigger event if the current selection was deleted
        if curr_item == index then
            trigger_selection_change(self)
        end
    end

    --[[
    % HandleSelectionChange

    **[Callback Template]**

    @ control (FCMCtrlPopup)
    @ last_item (number) The 0-based index of the previously selected item. If no item was selected, the value will be `-1`.
    @ last_item_text (string) The text value of the previously selected item.
    @ is_deleted (boolean) `true` if the previously selected item is no longer in the control.
    ]]

    --[[
    % AddHandleSelectionChange

    **[Fluid]**
    Adds a handler for SelectionChange events.
    If the selected item is changed by a handler, that same handler will not be called again for that change.

    The event will fire in the following cases:
    - When the window is created (if an item is selected)
    - Change in selected item by user or programatically (inserting an item before or after will not trigger the event)
    - Changing the text value of the currently selected item
    - Deleting the currently selected item
    - Clearing the control (including calling `Clear` and `SetStrings`)

    @ self (FCMCtrlPopup)
    @ callback (function) See `HandleSelectionChange` for callback signature.
    ]]

    --[[
    % RemoveHandleSelectionChange

    **[Fluid]**
    Removes a handler added with `AddHandleSelectionChange`.

    @ self (FCMCtrlPopup)
    @ callback (function) Handler to remove.
    ]]
    props.AddHandleSelectionChange, props.RemoveHandleSelectionChange, trigger_selection_change, each_last_selection_change =
        mixin_helper.create_custom_control_change_event(
            {name = "last_item", get = "GetSelectedItem_", initial = -1}, {
                name = "last_item_text",
                get = function(ctrl)
                    return mixin.FCMCtrlPopup.GetSelectedString(ctrl) or ""
                end,
                initial = "",
            }, {
                name = "is_deleted",
                get = function()
                    return false
                end,
                initial = false,
            })

    return props

end

__imports["mixin.FCMCtrlSlider"] = __imports["mixin.FCMCtrlSlider"] or function()
    --  Author: Edward Koltun
    --  Date: April 3, 2022
    --[[
    $module FCMCtrlSlider

    Summary of modifications:
    - Added `ThumbPositionChange` custom control event *(see note)*.

    **Note on `ThumbPositionChange` event:**
    Command events do not fire for `FCCtrlSlider` controls, so a workaround is used to make the `ThumbPositionChange` events work.
    If using JW/RGPLua version 0.55 or lower, then the event dispatcher will run with the next Command event for a different control. In these versions the event is unreliable as the user will need to interact with another control for the change in thumb position to be registered.
    If using version 0.56 or later, then the dispatcher will run every 1 second. This is more reliable than in earlier versions but it still will not fire immediately.
    ]] --
    local mixin = require("library.mixin")
    local mixin_helper = require("library.mixin_helper")

    local windows = setmetatable({}, {__mode = "k"})
    local props = {}

    local trigger_thumb_position_change
    local each_last_thumb_position_change

    local using_timer_fix = false

    local function bootstrap_command()
        -- Since we're piggybacking off a handler, we don't need to trigger immediately
        trigger_thumb_position_change(true)
    end

    local function bootstrap_timer(timerid, window)
        -- We're in the root of an event handler, so it is safe to trigger immediately
        trigger_thumb_position_change(true, true)
    end

    local bootstrap_timer_first

    -- Timers may not work, so only remove the command handler once the timer has fired once
    bootstrap_timer_first = function(timerid, window)
        window:RemoveHandleCommand(bootstrap_command)
        window:RemoveHandleTimer(timerid, bootstrap_timer_first)
        window:AddHandleTimer(timerid, bootstrap_timer)

        bootstrap_timer(timerid, window)
    end

    --[[
    % RegisterParent

    **[Internal] [Override]**

    @ self (FCMCtrlSlider)
    @ window (FCMCustomLuaWindow)
    ]]
    function props:RegisterParent(window)
        mixin.FCMControl.RegisterParent(self, window)

        if not windows[window] then
            -- Bootstrap to command events for every other control
            window:AddHandleCommand(bootstrap_command)

            if window.SetTimer_ then
                -- Trigger dispatches every second
                window:AddHandleTimer(window:SetNextTimer(1000), bootstrap_timer_first)
            end

            windows[window] = true
        end
    end

    --[[
    % SetThumbPosition

    **[Fluid] [Override]**
    Ensures that `ThumbPositionChange` event is triggered.

    @ self (FCMCtrlSlider)
    @ position (number)
    ]]
    function props:SetThumbPosition(position)
        mixin.assert_argument(position, "number", 2)

        self:SetThumbPosition_(position)

        trigger_thumb_position_change(self)
    end

    --[[
    % SetMinValue

    **[Fluid] [Override]**
    Ensures that `ThumbPositionChange` is triggered.

    @ self (FCMCtrlSlider)
    @ minvalue (number)
    ]]
    function props:SetMinValue(minvalue)
        mixin.assert_argument(minvalue, "number", 2)

        self:SetMinValue_(minvalue)

        trigger_thumb_position_change(self)
    end

    --[[
    % SetMaxValue

    **[Fluid] [Override]**
    Ensures that `ThumbPositionChange` is triggered.

    @ self (FCMCtrlSlider)
    @ maxvalue (number)
    ]]
    function props:SetMaxValue(maxvalue)
        mixin.assert_argument(maxvalue, "number", 2)

        self:SetMaxValue_(maxvalue)

        trigger_thumb_position_change(self)
    end

    --[[
    % HandleThumbPositionChange

    **[Callback Template]**

    @ control (FCMCtrlSlider) The slider that was moved.
    @ last_position (string) The previous value of the control's thumb position.
    ]]

    --[[
    % AddHandleChange

    **[Fluid]**
    Adds a handler for when the slider's thumb position changes.
    The even will fire when:
    - The window is created
    - The slider is moved by the user
    - The slider's postion is changed programmatically (if the thumb position is changed within a handler, that *same* handler will not be called again for that change.)

    @ self (FCMCtrlSlider)
    @ callback (function) See `HandleThumbPositionChange` for callback signature.
    ]]

    --[[
    % RemoveHandleThumbPositionChange

    **[Fluid]**
    Removes a handler added with `AddHandleThumbPositionChange`.

    @ self (FCMCtrlSlider)
    @ callback (function)
    ]]
    props.AddHandleThumbPositionChange, props.RemoveHandleThumbPositionChange, trigger_thumb_position_change, each_last_thumb_position_change =
        mixin_helper.create_custom_control_change_event(
            {name = "last_position", get = "GetThumbPosition_", initial = -1})

    return props

end

__imports["mixin.FCMCtrlStatic"] = __imports["mixin.FCMCtrlStatic"] or function()
    --  Author: Edward Koltun
    --  Date: September 18, 2022
    --[[
    $module FCMCtrlStatic

    Summary of modifications:
    - Added hooks for control state restoration
    - SetTextColor updates visible color immediately if window is showing
    ]] --
    local mixin = require("library.mixin")
    local utils = require("library.utils")

    local private = setmetatable({}, {__mode = "k"})
    local props = {}
    local temp_str = finale.FCString()

    --[[
    % Init

    **[Internal]**

    @ self (FCMCtrlStatic)
    ]]
    function props:Init()
        private[self] = private[self] or {}
    end

    --[[
    % SetTextColor

    **[Fluid] [Override]**
    Displays the new text color immediately.
    Also hooks into control state restoration.

    @ self (FCMCtrlStatic)
    @ red (number)
    @ green (number)
    @ blue (number)
    ]]
    function props:SetTextColor(red, green, blue)
        mixin.assert_argument(red, "number", 2)
        mixin.assert_argument(green, "number", 3)
        mixin.assert_argument(blue, "number", 4)

        private[self].TextColor = {red, green, blue}

        if not mixin.FCMControl.UseStoredState(self) then
            self:SetTextColor_(red, green, blue)

            -- If a new text color is set after the window has been shown, the visible color will not change until new text is set
            -- Getting and setting the text makes the new text color visible immediately
            mixin.FCMControl.SetText(self, mixin.FCMControl.GetText(self))
        end
    end

    --[[
    % RestoreState

    **[Fluid] [Internal]**
    Restores the control's stored state.
    Do not disable this method. Override as needed but call the parent first.

    @ self (FCMCtrlStatic)
    ]]
    function props:RestoreState()
        mixin.FCMControl.RestoreState(self)

        if private[self].TextColor then
            mixin.FCMCtrlStatic.SetTextColor(self, private[self].TextColor[1], private[self].TextColor[2], private[self].TextColor[3])
        end
    end

    return props

end

__imports["mixin.FCMCtrlSwitcher"] = __imports["mixin.FCMCtrlSwitcher"] or function()
    --  Author: Edward Koltun
    --  Date: March 3, 2022
    --[[
    $module FCMCtrlSwitcher

    Summary of modifications:
    - Setters that accept `FCString` now also accept Lua `string` and `number`.
    - Additional methods for accessing and adding pages and page titles.
    - Added `PageChange` custom control event.
    ]] --
    local mixin = require("library.mixin")
    local mixin_helper = require("library.mixin_helper")
    local library = require("library.general_library")

    local private = setmetatable({}, {__mode = "k"})
    local props = {}

    local trigger_page_change
    local each_last_page_change
    local temp_str = finale.FCString()

    --[[
    % Init

    **[Internal]**

    @ self (FCMCtrlSwitcher)
    ]]
    function props:Init()
        private[self] = private[self] or {Index = {}}
    end

    --[[
    % AddPage

    **[Fluid] [Override]**
    Accepts Lua `string` and `number` in addition to `FCString`.

    @ self (FCMCtrlSwitcher)
    @ title (FCString|string|number)
    ]]
    function props:AddPage(title)
        mixin.assert_argument(title, {"string", "number", "FCString"}, 2)

        if type(title) ~= "userdata" then
            temp_str.LuaString = tostring(title)
            title = temp_str
        end

        self:AddPage_(title)
        table.insert(private[self].Index, title.LuaString)
    end

    --[[
    % AddPages

    **[Fluid]**
    Adds multiple pages, one page for each argument.

    @ self (FCMCtrlSwitcher)
    @ ... (FCString|string|number)
    ]]
    function props:AddPages(...)
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            mixin.assert_argument(v, {"string", "number", "FCString"}, i + 1)
            mixin.FCMCtrlSwitcher.AddPage(self, v)
        end
    end

    --[[
    % AttachControlByTitle

    Attaches a control to a page.

    @ self (FCMCtrlSwitcher)
    @ control (FCMControl) The control to attach.
    @ title (FCString|string|number) The title of the page. Must be an exact match.
    : (boolean)
    ]]
    function props:AttachControlByTitle(control, title)
        -- Given the number of possibilities, control argument is not asserted for now
        mixin.assert_argument(title, {"string", "number", "FCString"}, 3)

        title = type(title) == "userdata" and title.LuaString or tostring(title)

        local index = -1
        for k, v in ipairs(private[self].Index) do
            if v == title then
                index = k - 1
            end
        end

        mixin.force_assert(index ~= -1, "No page titled '" .. title .. "'")

        return self:AttachControl_(control, index)
    end

    --[[
    % SetSelectedPage

    **[Fluid] [Override]**

    @ self (FCMCtrlSwitcher)
    @ index (number)
    ]]
    function props:SetSelectedPage(index)
        mixin.assert_argument(index, "number", 2)

        self:SetSelectedPage_(index)

        trigger_page_change(self)
    end

    --[[
    % SetSelectedPageByTitle

    **[Fluid]**
    Set the selected page by its title. If the page is not found, an error will be thrown.

    @ self (FCMCtrlSwitcher)
    @ title (FCString|string|number) Title of page to select. Must be an exact match.
    ]]
    function props:SetSelectedPageByTitle(title)
        mixin.assert_argument(title, {"string", "number", "FCString"}, 2)

        title = type(title) == "userdata" and title.LuaString or tostring(title)

        for k, v in ipairs(private[self].Index) do
            if v == title then
                mixin.FCMCtrlSwitcher.SetSelectedPage(self, k - 1)
                return
            end
        end

        error("No page titled '" .. title .. "'", 2)
    end

    --[[
    % GetSelectedPageTitle

    Returns the title of the currently selected page.

    @ self (FCMCtrlSwitcher)
    @ [title] (FCString) Optional `FCString` object to populate.
    : (string|nil) Nil if no page is selected
    ]]
    function props:GetSelectedPageTitle(title)
        mixin.assert_argument(title, {"nil", "FCString"}, 2)

        local index = self:GetSelectedPage_()
        if index == -1 then
            if title then
                title.LuaString = ""
            end

            return nil
        else
            local text = private[self].Index[self:GetSelectedPage_() + 1]

            if title then
                title.LuaString = text
            end

            return text
        end
    end

    --[[
    % GetPageTitle

    Returns the title of a page.

    @ self (FCMCtrlSwitcher)
    @ index (number) The 0-based index of the page.
    @ [str] (FCString) An optional `FCString` object to populate.
    : (string)
    ]]
    function props:GetPageTitle(index, str)
        mixin.assert_argument(index, "number", 2)
        mixin.assert_argument(str, {"nil", "FCString"}, 2)

        local text = private[self].Index[index + 1]
        mixin.force_assert(text, "No page at index " .. tostring(index))

        if str then
            str.LuaString = text
        end

        return text
    end

    --[[
    % HandlePageChange

    **[Callback Template]**

    @ control (FCMCtrlSwitcher) The control on which the event occurred.
    @ last_page (number) The 0-based index of the previously selected page. If no page was previously selected, this will be `-1` (eg when the window is created).
    @ last_page_title (string) The title of the previously selected page.
    ]]

    --[[
    % AddHandlePageChange

    **[Fluid]**
    Adds an event listener for PageChange events.
    The event fires when:
    - The window is created (if pages have been added)
    - The user switches page
    - The selected page is changed programmatically (if the selected page is changed within a handler, that *same* handler will not be called for that change)

    @ self (FCMCtrlSwitcher)
    @ callback (function) See `HandlePageChange` for callback signature.
    ]]

    --[[
    % RemoveHandlePageChange

    **[Fluid]**
    Removes a handler added with `AddHandlePageChange`.

    @ self (FCMCtrlSwitcher)
    @ callback (function)
    ]]
    props.AddHandlePageChange, props.RemoveHandlePageChange, trigger_page_change, each_last_page_change =
        mixin_helper.create_custom_control_change_event(
            {name = "last_page", get = "GetSelectedPage_", initial = -1}, {
                name = "last_page_title",
                get = function(ctrl)
                    return mixin.FCMCtrlSwitcher.GetSelectedPageTitle(ctrl)
                end,
                initial = "",
            } -- Wrap get in function to prevent infinite recursion
        )

    return props

end

__imports["mixin.FCMCtrlTree"] = __imports["mixin.FCMCtrlTree"] or function()
    --  Author: Edward Koltun
    --  Date: April 6, 2022
    --[[
    $module FCMCtrlTree

    Summary of modifications:
    - Methods that accept `FCString` now also accept Lua `string` and `number`.
    ]] --
    local mixin = require("library.mixin")

    local props = {}

    local temp_str = finale.FCString()

    --[[
    % AddNode

    **[Override]**
    Accepts Lua `string` and `number` in addition to `FCString`.

    @ self (FCMCtrlTree)
    @ parentnode (FCTreeNode|nil)
    @ iscontainer (boolean)
    @ text (FCString|string|number)
    : (FCMTreeNode)
    ]]
    function props:AddNode(parentnode, iscontainer, text)
        mixin.assert_argument(parentnode, {"nil", "FCTreeNode"}, 2)
        mixin.assert_argument(iscontainer, "boolean", 3)
        mixin.assert_argument(text, {"string", "number", "FCString"}, 4)

        if not text.ClassName then
            temp_str.LuaString = tostring(text)
            text = temp_str
        end

        return self:AddNode_(parentnode, iscontainer, text)
    end

    return props

end

__imports["mixin.FCMCtrlUpDown"] = __imports["mixin.FCMCtrlUpDown"] or function()
    --  Author: Edward Koltun
    --  Date: March 3, 2022
    --[[
    $module FCMCtrlUpDown

    Summary of modifications:
    - `GetConnectedEdit` returns the original control object.
    - Handlers for the `UpDownPressed` event can now be set on a control.
    ]] --
    local mixin = require("library.mixin")
    local mixin_helper = require("library.mixin_helper")

    local private = setmetatable({}, {__mode = "k"})
    local props = {}

    --[[
    % Init

    **[Internal]**

    @ self (FCMCtrlUpDown)
    ]]
    function props:Init()
        private[self] = private[self] or {}
    end

    --[[
    % GetConnectedEdit

    **[Override]**
    Ensures that original edit control is returned.

    @ self (FCMCtrlUpDown)
    : (FCMCtrlEdit|nil) `nil` if there is no edit connected.
    ]]
    function props:GetConnectedEdit()
        return private[self].ConnectedEdit
    end

    --[[
    % ConnectIntegerEdit

    **[Override]**

    @ self (FCMCtrlUpDown)
    @ control (FCCtrlEdit)
    @ minvalue (number)
    @ maxvalue (number)
    : (boolean) `true` on success
    ]]
    function props:ConnectIntegerEdit(control, minvalue, maxvalue)
        mixin.assert_argument(control, "FCMCtrlEdit", 2)
        mixin.assert_argument(minvalue, "number", 3)
        mixin.assert_argument(maxvalue, "number", 4)

        local ret = self:ConnectIntegerEdit_(control, minvalue, maxvalue)

        if ret then
            private[self].ConnectedEdit = control
        end

        return ret
    end

    --[[
    % ConnectMeasurementEdit

    **[Override]**

    @ self (FCMCtrlUpDown)
    @ control (FCCtrlEdit)
    @ minvalue (number)
    @ maxvalue (number)
    : (boolean) `true` on success
    ]]
    function props:ConnectMeasurementEdit(control, minvalue, maxvalue)
        mixin.assert_argument(control, "FCMCtrlEdit", 2)
        mixin.assert_argument(minvalue, "number", 3)
        mixin.assert_argument(maxvalue, "number", 4)

        local ret = self:ConnectMeasurementEdit_(control, minvalue, maxvalue)

        if ret then
            private[self].ConnectedEdit = control
        end

        return ret
    end

    --[[
    % AddHandlePress

    **[Fluid]**
    Adds a handler for UpDownPressed events.

    @ self (FCMCtrlUpDown)
    @ callback (function) See `FCCustomLuaWindow.HandleUpDownPressed` in the PDK for callback signature.
    ]]

    --[[
    % RemoveHandlePress

    **[Fluid]**
    Removes a handler added with `AddHandlePress`.

    @ self (FCMCtrlUpDown)
    @ callback (function)
    ]]
    props.AddHandlePress, props.RemoveHandlePress = mixin_helper.create_standard_control_event("HandleUpDownPressed")

    return props

end

__imports["mixin.FCMCustomLuaWindow"] = __imports["mixin.FCMCustomLuaWindow"] or function()
    --  Author: Edward Koltun
    --  Date: March 3, 2022
    --[[
    $module FCMCustomLuaWindow

    Summary of modifications:
    - All `Register*` methods (apart from `RegisterHandleControlEvent` and `RegisterHandleTimer`) have accompanying `Add*` and `Remove*` methods to enable multiple handlers to be added per event.
    - Handlers for non-control events can receive the window object as an optional additional parameter.
    - Control handlers are passed original object to preserve mixin data.
    - Added custom callback queue which can be used by custom events to add dispatchers that will run with the next control event.
    - Added `HasBeenShown` method for checking if the window has been shown
    - Added methods for the automatic restoration of previous window position when showing (RGPLua > 0.60) for use with `finenv.RetainLuaState` and modeless windows.
    - Added DebugClose option to assist with debugging (if ALT or SHIFT key is pressed when window is closed and debug mode is enabled, finenv.RetainLuaState will be set to false)
    ]] --
    local mixin = require("library.mixin")
    local utils = require("library.utils")

    local private = setmetatable({}, {__mode = "k"})
    local props = {}

    local control_handlers = {"HandleCommand", "HandleDataListCheck", "HandleDataListSelect", "HandleUpDownPressed"}
    local other_handlers = {"HandleCancelButtonPressed", "HandleOkButtonPressed", "InitWindow", "CloseWindow"}

    local function flush_custom_queue(self)
        local queue = private[self].HandleCustomQueue
        private[self].HandleCustomQueue = {}

        for _, cb in ipairs(queue) do
            cb()
        end
    end

    local function restore_position(window)
        if private[window].HasBeenShown and private[window].AutoRestorePosition and window.StorePosition then
            window:StorePosition(false)
            window:SetRestorePositionOnlyData_(private[window].StoredX, private[window].StoredY)
            window:RestorePosition()
        end
    end

    --[[
    % Init

    **[Internal]**

    @ self (FCMCustomLuaWindow)
    ]]
    function props:Init()
        private[self] = private[self] or {
            HandleCustomQueue = {},
            HasBeenShown = false,
            EnableDebugClose = false,
            RestoreControlState = false,
            AutoRestorePosition = false,
            StoredX = nil,
            StoredY = nil,
        }

        -- Registers proxy functions up front to ensure that the handlers are passed the original object along with its mixin data
        for _, f in ipairs(control_handlers) do
            private[self][f] = {Added = {}}

            -- Handlers sometimes run twice, the second while the first is still running, so this flag prevents race conditions and concurrency issues.
            local is_running = false
            if self["Register" .. f .. "_"] then
                self["Register" .. f .. "_"](
                    self, function(control, ...)
                        if is_running then
                            return
                        end

                        is_running = true
                        local handlers = private[self][f]

                        -- Flush custom queue once
                        flush_custom_queue(self)

                        -- Execute handlers for main control
                        local temp = self:FindControl(control:GetControlID())

                        if not temp then
                            error("Control with ID #" .. tostring(control:GetControlID()) .. " not found in '" .. f .. "'")
                        end

                        control = temp

                        -- Call registered handler
                        if handlers.Registered then
                            handlers.Registered(control, ...)
                        end

                        -- Call added handlers
                        for _, cb in ipairs(handlers.Added) do
                            cb(control, ...)
                        end

                        -- Flush custom queue until empty
                        while #private[self].HandleCustomQueue > 0 do
                            flush_custom_queue(self)
                        end

                        is_running = false
                    end)
            end
        end

        -- Register proxies for other handlers
        for _, f in ipairs(other_handlers) do
            private[self][f] = {Added = {}}

            if self["Register" .. f .. "_"] then
                local function cb()
                    local handlers = private[self][f]
                    if handlers.Registered then
                        handlers.Registered(self)
                    end

                    for _, v in ipairs(handlers.Added) do
                        v(self)
                    end
                end

                if f == "InitWindow" then
                    self["Register" .. f .. "_"](self, function()
                        if private[self].HasBeenShown and private[self].RestoreControlState then
                            for control in each(self) do
                                control:RestoreState()
                            end
                        end

                        cb()
                    end)
                elseif f == "CloseWindow" then
                    self["Register" .. f .. "_"](self, function()
                        if private[self].EnableDebugClose and finenv.RetainLuaState ~= nil then
                            if finenv.DebugEnabled and (self:QueryLastCommandModifierKeys(finale.CMDMODKEY_ALT) or self:QueryLastCommandModifierKeys(finale.CMDMODKEY_SHIFT)) then
                                finenv.RetainLuaState = false
                            end
                        end

                        -- Catch any errors so they don't disrupt storing window position and control state
                        local is_error, error_msg = pcall(cb)

                        if self.StorePosition then
                            self:StorePosition(false)
                            private[self].StoredX = self.StoredX
                            private[self].StoredY = self.StoredY
                        end

                        if private[self].RestoreControlState then
                            for control in each(self) do
                                control:StoreState()
                            end
                        end

                        private[self].HasBeenShown = true

                        if is_error then
                            error(error_msg, 0)
                        end
                    end)
                else
                    self["Register" .. f .. "_"](self, cb)
                end
            end
        end
    end

    --[[
    % RegisterHandleCommand

    **[Override]**
    Ensures that the handler is passed the original control object.

    @ self (FCMCustomLuaWindow)
    @ callback (function) See `FCCustomLuaWindow.HandleCommand` in the PDK for callback signature.
    : (boolean) `true` on success
    ]]

    --[[
    % RegisterHandleDataListCheck

    **[Override]**
    Ensures that the handler is passed the original control object.

    @ self (FCMCustomLuaWindow)
    @ callback (function) See `FCCustomLuaWindow.HandleDataListCheck` in the PDK for callback signature.
    : (boolean) `true` on success
    ]]

    --[[
    % RegisterHandleDataListSelect

    **[Override]**
    Ensures that the handler is passed the original control object.

    @ self (FCMCustomLuaWindow)
    @ callback (function) See `FCCustomLuaWindow.HandleDataListSelect` in the PDK for callback signature.
    : (boolean) `true` on success
    ]]

    --[[
    % RegisterHandleUpDownPressed

    **[Override]**
    Ensures that the handler is passed the original control object.

    @ self (FCMCustomLuaWindow)
    @ callback (function) See `FCCustomLuaWindow.HandleUpDownPressed` in the PDK for callback signature.
    : (boolean) `true` on success
    ]]
    for _, f in ipairs(control_handlers) do
        props["Register" .. f] = function(self, callback)
            mixin.assert_argument(callback, "function", 2)

            private[self][f].Registered = callback
            return true
        end
    end

    --[[
    % CancelButtonPressed

    **[Callback Template] [Override]**
    Can optionally receive the window object.

    @ [window] (FCMCustomLuaWindow)
    ]]

    --[[
    % RegisterHandleCancelButtonPressed

    **[Override]**

    @ self (FCMCustomLuaWindow)
    @ callback (function) See `CancelButtonPressed` for callback signature.
    : (boolean) `true` on success
    ]]

    --[[
    % OkButtonPressed

    **[Callback Template] [Override]**
    Can optionally receive the window object.

    @ [window] (FCMCustomLuaWindow)
    ]]

    --[[
    % RegisterHandleOkButtonPressed

    **[Override]**

    @ self (FCMCustomLuaWindow)
    @ callback (function)  See `OkButtonPressed` for callback signature.
    : (boolean) `true` on success
    ]]

    --[[
    % InitWindow

    **[Callback Template] [Override]**
    Can optionally receive the window object.

    @ [window] (FCMCustomLuaWindow)
    ]]

    --[[
    % RegisterInitWindow

    **[Override]**

    @ self (FCMCustomLuaWindow)
    @ callback (function) See `InitWindow` for callback signature.
    : (boolean) `true` on success
    ]]

    --[[
    % CloseWindow

    **[Callback Template] [Override]**
    Can optionally receive the window object.

    @ [window] (FCMCustomLuaWindow)
    ]]

    --[[
    % RegisterCloseWindow

    **[Override]**

    @ self (FCMCustomLuaWindow)
    @ callback (function) See `CloseWindow` for callback signature.
    : (boolean) `true` on success
    ]]
    for _, f in ipairs(other_handlers) do
        props["Register" .. f] = function(self, callback)
            mixin.assert_argument(callback, "function", 2)

            private[self][f].Registered = callback
            return true
        end
    end

    --[[
    % AddHandleCommand

    **[Fluid]**
    Adds a handler. Similar to the equivalent `RegisterHandleCommand` except there is no limit to the number of handlers that can be added.
    Added handlers are called in the order they are added after the registered handler, if there is one.

    @ self (FCMCustomLuaWindow)
    @ callback (function) See `FCCustomLuaWindow.HandleCommand` in the PDK for callback signature.
    ]]

    --[[
    % AddHandleDataListCheck

    **[Fluid]**
    Adds a handler. Similar to the equivalent `RegisterHandleDataListCheck` except there is no limit to the number of handlers that can be added.
    Added handlers are called in the order they are added after the registered handler, if there is one.

    @ self (FCMCustomLuaWindow)
    @ callback (function) See `FCCustomLuaWindow.HandleDataListCheck` in the PDK for callback signature.
    ]]

    --[[
    % AddHandleDataListSelect

    **[Fluid]**
    Adds a handler. Similar to the equivalent `RegisterHandleDataListSelect` except there is no limit to the number of handlers that can be added.
    Added handlers are called in the order they are added after the registered handler, if there is one.

    @ self (FCMCustomLuaWindow)
    @ callback (function) See `FCCustomLuaWindow.HandleDataListSelect` in the PDK for callback signature.
    ]]

    --[[
    % AddHandleUpDownPressed

    **[Fluid]**
    Adds a handler. Similar to the equivalent `RegisterHandleUpDownPressed` except there is no limit to the number of handlers that can be added.
    Added handlers are called in the order they are added after the registered handler, if there is one.

    @ self (FCMCustomLuaWindow)
    @ callback (function) See `FCCustomLuaWindow.HandleUpDownPressed` in the PDK for callback signature.
    ]]
    for _, f in ipairs(control_handlers) do
        props["Add" .. f] = function(self, callback)
            mixin.assert_argument(callback, "function", 2)

            table.insert(private[self][f].Added, callback)
        end
    end

    --[[
    % AddHandleCancelButtonPressed

    **[Fluid]**
    Adds a handler. Similar to the equivalent `RegisterCancelButtonPressed` except there is no limit to the number of handlers that can be added.
    Added handlers are called in the order they are added after the registered handler, if there is one.

    @ self (FCMCustomLuaWindow)
    @ callback (function) See `CancelButtonPressed` for callback signature.
    ]]

    --[[
    % AddHandleOkButtonPressed

    **[Fluid]**
    Adds a handler. Similar to the equivalent `RegisterOkButtonPressed` except there is no limit to the number of handlers that can be added.
    Added handlers are called in the order they are added after the registered handler, if there is one.

    @ self (FCMCustomLuaWindow)
    @ callback (function) See `OkButtonPressed` for callback signature.
    ]]

    --[[
    % AddInitWindow

    **[Fluid]**
    Adds a handler. Similar to the equivalent `RegisterInitWindow` except there is no limit to the number of handlers that can be added.
    Added handlers are called in the order they are added after the registered handler, if there is one.

    @ self (FCMCustomLuaWindow)
    @ callback (function) See `InitWindow` for callback signature.
    ]]

    --[[
    % AddCloseWindow

    **[Fluid]**
    Adds a handler. Similar to the equivalent `RegisterCloseWindow` except there is no limit to the number of handlers that can be added.
    Added handlers are called in the order they are added after the registered handler, if there is one.

    @ self (FCMCustomLuaWindow)
    @ callback (function) See `CloseWindow` for callback signature.
    ]]
    for _, f in ipairs(other_handlers) do
        props["Add" .. f] = function(self, callback)
            mixin.assert_argument(callback, "function", 2)

            table.insert(private[self][f].Added, callback)
        end
    end

    --[[
    % RemoveHandleCommand

    **[Fluid]**
    Removes a handler added by `AddHandleCommand`.

    @ self (FCMCustomLuaWindow)
    @ callback (function)
    ]]

    --[[
    % RemoveHandleDataListCheck

    **[Fluid]**
    Removes a handler added by `AddHandleDataListCheck`.

    @ self (FCMCustomLuaWindow)
    @ callback (function)
    ]]

    --[[
    % RemoveHandleDataListSelect

    **[Fluid]**
    Removes a handler added by `AddHandleDataListSelect`.

    @ self (FCMCustomLuaWindow)
    @ callback (function)
    ]]

    --[[
    % RemoveHandleUpDownPressed

    **[Fluid]**
    Removes a handler added by `AddHandleUpDownPressed`.

    @ self (FCMCustomLuaWindow)
    @ callback (function)
    ]]
    for _, f in ipairs(control_handlers) do
        props["Remove" .. f] = function(self, callback)
            mixin.assert_argument(callback, "function", 2)

            utils.table_remove_first(private[self][f].Added, callback)
        end
    end

    --[[
    % RemoveHandleCancelButtonPressed

    **[Fluid]**
    Removes a handler added by `AddHandleCancelButtonPressed`.

    @ self (FCMCustomLuaWindow)
    @ callback (function)
    ]]

    --[[
    % RemoveHandleOkButtonPressed

    **[Fluid]**
    Removes a handler added by `AddHandleOkButtonPressed`.

    @ self (FCMCustomLuaWindow)
    @ callback (function)
    ]]

    --[[
    % RemoveInitWindow

    **[Fluid]**
    Removes a handler added by `AddInitWindow`.

    @ self (FCMCustomLuaWindow)
    @ callback (function)
    ]]

    --[[
    % RemoveCloseWindow

    **[Fluid]**
    Removes a handler added by `AddCloseWindow`.

    @ self (FCMCustomLuaWindow)
    @ callback (function)
    ]]
    for _, f in ipairs(other_handlers) do
        props["Remove" .. f] = function(self, callback)
            mixin.assert_argument(callback, "function", 2)

            utils.table_remove_first(private[self][f].Added, callback)
        end
    end

    --[[
    % QueueHandleCustom

    **[Fluid] [Internal]**
    Adds a function to the queue which will be executed in the same context as an event handler at the next available opportunity.
    Once called, the callback will be removed from tbe queue (i.e. it will only be called once). For multiple calls, the callback will need to be added to the queue again.
    The callback will not be passed any arguments.

    @ self (FCMCustomLuaWindow)
    @ callback (function)
    ]]
    function props:QueueHandleCustom(callback)
        mixin.assert_argument(callback, "function", 2)

        table.insert(private[self].HandleCustomQueue, callback)
    end

    if finenv.MajorVersion > 0 or finenv.MinorVersion >= 56 then

        --[[
    % RegisterHandleControlEvent

    **[>= v0.56] [Override]**
    Ensures that the handler is passed the original control object.

    @ self (FCMCustomLuaWindow)
    @ control (FCMControl)
    @ callback (function) See `FCCustomLuaWindow.HandleControlEvent` in the PDK for callback signature.
    : (boolean) `true` on success
    ]]
        function props:RegisterHandleControlEvent(control, callback)
            mixin.assert_argument(callback, "function", 3)

            return self:RegisterHandleControlEvent_(
                       control, function(ctrl)
                    callback(self.FindControl(ctrl:GetControlID()))
                end)
        end
    end

    --[[
    % HasBeenShown

    Checks if the window has been shown at least once prior, either as a modal or modeless.

    @ self (FCMCustomLuaWindow)
    : (boolean) `true` if it has been shown, `false` if not
    ]]
    function props:HasBeenShown()
        return private[self].HasBeenShown
    end

    if finenv.MajorVersion > 0 or finenv.MinorVersion >= 60 then
        --[[
    % SetAutoRestorePosition

    **[>= v0.60] [Fluid]**
    Enables/disables automatic restoration of the window's position on subsequent openings.
    This is disabled by default.

    @ self (FCMCustomLuaWindow)
    @ enabled (boolean)
    ]]
        function props:SetAutoRestorePosition(enabled)
            mixin.assert_argument(enabled, "boolean", 2)

            private[self].AutoRestorePosition = enabled
        end

        --[[
    % GetAutoRestorePosition

    **[>= v0.60]**
    Returns whether automatic restoration of window position is enabled.

    @ self (FCMCustomLuaWindow)
    : (boolean) `true` if enabled, `false` if disabled.
    ]]
        function props:GetAutoRestorePosition()
            return private[self].AutoRestorePosition
        end

        --[[
    % SetRestorePositionData

    **[>= v0.60] [Fluid] [Override]**
    If the position is changed while window is closed, ensures that the new position data will be used in auto restoration when window is shown.

    @ self (FCMCustomLuaWindow)
    @ x (number)
    @ y (number)
    @ width (number)
    @ height (number)
    ]]
        function props:SetRestorePositionData(x, y, width, height)
            mixin.assert_argument(x, "number", 2)
            mixin.assert_argument(y, "number", 3)
            mixin.assert_argument(width, "number", 4)
            mixin.assert_argument(height, "number", 5)

            self:SetRestorePositionOnlyData_(x, y, width, height)

            if private[self].HasBeenShown and not self:WindowExists() then
                private[self].StoredX = x
                private[self].StoredY = y
            end
        end

        --[[
    % SetRestorePositionOnlyData

    **[>= v0.60] [Fluid] [Override]**
    If the position is changed while window is closed, ensures that the new position data will be used in auto restoration when window is shown.

    @ self (FCMCustomLuaWindow)
    @ x (number)
    @ y (number)
    ]]
        function props:SetRestorePositionOnlyData(x, y)
            mixin.assert_argument(x, "number", 2)
            mixin.assert_argument(y, "number", 3)

            self:SetRestorePositionOnlyData_(x, y)

            if private[self].HasBeenShown and not self:WindowExists() then
                private[self].StoredX = x
                private[self].StoredY = y
            end
        end
    end

    --[[
    % SetEnableDebugClose

    **[Fluid]**
    If enabled and in debug mode, when the window is closed with either ALT or SHIFT key pressed, `finenv.RetainLuaState` will be set to `false`.
    This is done before CloseWindow handlers are called.
    Default state is disabled.

    @ self (FCMCustomLuaWindow)
    @ enabled (boolean)
    ]]
    function props:SetEnableDebugClose(enabled)
        mixin.assert_argument(enabled, "boolean", 2)

        private[self].EnableDebugClose = enabled and true or false
    end

    --[[
    % GetEnableDebugClose

    Returns the enabled state of the DebugClose option.

    @ self (FCMCustomLuaWindow)
    : (boolean) `true` if enabled, `false` if disabled.
    ]]
    function props:GetEnableDebugClose(enabled)
        return private[self].EnableDebugClose
    end

    --[[
    % SetRestoreControlState

    **[Fluid]**
    Enables or disables the automatic restoration of control state on subsequent showings of the window.
    This is disabled by default.

    @ self (FCMCustomLuaWindow)
    @ enabled (boolean) `true` to enable, `false` to disable.
    ]]
    function props:SetRestoreControlState(enabled)
        mixin.assert_argument(enabled, "boolean", 2)

        private[self].RestoreControlState = enabled and true or false
    end

    --[[
    % GetRestoreControlState

    Checks if control state restoration is enabled.

    @ self (FCMCustomLuaWindow)
    : (boolean) `true` if enabled, `false` if disabled.
    ]]
    function props:GetRestoreControlState()
        return private[self].RestoreControlState
    end

    --[[
    % ExecuteModal

    **[Override]**
    Restores the previous position if auto restore is on.

    @ self (FCMCustomLuaWindow)
    : (number)
    ]]
    function props:ExecuteModal(parent)
        restore_position(self)
        return mixin.FCMCustomWindow.ExecuteModal(self, parent)
    end

    --[[
    % ShowModeless

    **[Override]**
    Restores the previous position if auto restore is on.

    @ self (FCMCustomLuaWindow)
    : (boolean)
    ]]
    function props:ShowModeless()
        restore_position(self)
        return self:ShowModeless_()
    end

    return props

end

__imports["mixin.FCMCustomWindow"] = __imports["mixin.FCMCustomWindow"] or function()
    --  Author: Edward Koltun
    --  Date: March 3, 2022
    --[[
    $module FCMCustomWindow

    Summary of modifications:
    - `Create*` methods have an additional optional parameter for specifying a control name. Named controls can be retrieved via `GetControl`.
    - Cache original control objects to preserve mixin data and override control getters to return the original objects.
    - Added `Each` method for iterating over controls by class name.
    ]] --
    local mixin = require("library.mixin")

    local private = setmetatable({}, {__mode = "k"})
    local props = {}

    --[[
    % Init

    **[Internal]**

    @ self (FCMCustomWindow)
    ]]
    function props:Init()
        private[self] = private[self] or {
            Controls = {},
            NamedControls = {},
        }
    end

    --[[
    % CreateCancelButton

    **[Override]**
    Add optional `control_name` parameter.

    @ self (FCMCustomWindow)
    @ [control_name] (FCString|string) Optional name to allow access from `GetControl` method.
    : (FCMCtrlButton)
    ]]

    --[[
    % CreateOkButton

    **[Override]**
    Add optional `control_name` parameter.

    @ self (FCMCustomWindow)
    @ [control_name] (FCString|string) Optional name to allow access from `GetControl` method.
    : (FCMCtrlButton)
    ]]

    -- Override Create* methods to store a reference to the original created object and its control ID
    -- Also adds an optional parameter at the end for a control name
    for _, f in ipairs({"CancelButton", "OkButton"}) do
        props["Create" .. f] = function(self, control_name)
            mixin.assert_argument(control_name, {"string", "nil", "FCString"}, 2)

            local control = self["Create" .. f .. "_"](self)
            private[self].Controls[control:GetControlID()] = control
            control:RegisterParent(self)

            if control_name then
                control_name = type(control_name) == "userdata" and control_name.LuaString or control_name

                if private[self].NamedControls[control_name] then
                    error("A control is already registered with the name '" .. control_name .. "'", 2)
                end

                private[self].NamedControls[control_name] = control
            end

            return control
        end
    end

    --[[
    % CreateButton

    **[Override]**
    Add optional `control_name` parameter.

    @ self (FCMCustomWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (FCString|string) Optional name to allow access from `GetControl` method.
    : (FCMCtrlButton)
    ]]

    --[[
    % CreateCheckbox

    **[Override]**
    Add optional `control_name` parameter.

    @ self (FCMCustomWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (FCString|string) Optional name to allow access from `GetControl` method.
    : (FCMCtrlCheckbox)
    ]]

    --[[
    % CreateDataList

    **[Override]**
    Add optional `control_name` parameter.

    @ self (FCMCustomWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (FCString|string) Optional name to allow access from `GetControl` method.
    : (FCMCtrlDataList)
    ]]

    --[[
    % CreateEdit

    **[Override]**
    Add optional `control_name` parameter.

    @ self (FCMCustomWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (FCString|string) Optional name to allow access from `GetControl` method.
    : (FCMCtrlEdit)
    ]]

    --[[
    % CreateListBox

    **[Override]**
    Add optional `control_name` parameter.

    @ self (FCMCustomWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (FCString|string) Optional name to allow access from `GetControl` method.
    : (FCMCtrlListBox)
    ]]

    --[[
    % CreatePopup

    **[Override]**
    Add optional `control_name` parameter.

    @ self (FCMCustomWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (FCString|string) Optional name to allow access from `GetControl` method.
    : (FCMCtrlPopup)
    ]]

    --[[
    % CreateSlider

    **[Override]**
    Add optional `control_name` parameter.

    @ self (FCMCustomWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (FCString|string) Optional name to allow access from `GetControl` method.
    : (FCMCtrlSlider)
    ]]

    --[[
    % CreateStatic

    **[Override]**
    Add optional `control_name` parameter.

    @ self (FCMCustomWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (FCString|string) Optional name to allow access from `GetControl` method.
    : (FCMCtrlStatic)
    ]]

    --[[
    % CreateSwitcher

    **[Override]**
    Add optional `control_name` parameter.

    @ self (FCMCustomWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (FCString|string) Optional name to allow access from `GetControl` method.
    : (FCMCtrlSwitcher)
    ]]

    --[[
    % CreateTree

    **[Override]**
    Add optional `control_name` parameter.

    @ self (FCMCustomWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (FCString|string) Optional name to allow access from `GetControl` method.
    : (FCMCtrlTree)
    ]]

    --[[
    % CreateUpDown

    **[Override]**
    Add optional `control_name` parameter.

    @ self (FCMCustomWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (FCString|string) Optional name to allow access from `GetControl` method.
    : (FCMCtrlUpDown)
    ]]

    for _, f in ipairs(
                    {
            "Button", "Checkbox", "DataList", "Edit", "ListBox", "Popup", "Slider", "Static", "Switcher", "Tree", "UpDown",
        }) do
        props["Create" .. f] = function(self, x, y, control_name)
            mixin.assert_argument(x, "number", 2)
            mixin.assert_argument(y, "number", 3)
            mixin.assert_argument(control_name, {"string", "nil", "FCString"}, 4)

            local control = self["Create" .. f .. "_"](self, x, y)
            private[self].Controls[control:GetControlID()] = control
            control:RegisterParent(self)

            if control_name then
                control_name = type(control_name) == "userdata" and control_name.LuaString or control_name

                if private[self].NamedControls[control_name] then
                    error("A control is already registered with the name '" .. control_name .. "'", 2)
                end

                private[self].NamedControls[control_name] = control
            end

            return control
        end
    end

    --[[
    % CreateHorizontalLine

    **[Override]**
    Add optional `control_name` parameter.

    @ self (FCMCustomWindow)
    @ x (number)
    @ y (number)
    @ length (number)
    @ [control_name] (FCString|string) Optional name to allow access from `GetControl` method.
    : (FCMCtrlLine)
    ]]

    --[[
    % CreateVerticalLine

    **[Override]**
    Add optional `control_name` parameter.

    @ self (FCMCustomWindow)
    @ x (number)
    @ y (number)
    @ length (number)
    @ [control_name] (FCString|string) Optional name to allow access from `GetControl` method.
    : (FCMCtrlLine)
    ]]

    for _, f in ipairs({"HorizontalLine", "VerticalLine"}) do
        props["Create" .. f] = function(self, x, y, length, control_name)
            mixin.assert_argument(x, "number", 2)
            mixin.assert_argument(y, "number", 3)
            mixin.assert_argument(length, "number", 4)
            mixin.assert_argument(control_name, {"string", "nil", "FCString"}, 5)

            local control = self["Create" .. f .. "_"](self, x, y, length)
            private[self].Controls[control:GetControlID()] = control
            control:RegisterParent(self)

            if control_name then
                control_name = type(control_name) == "userdata" and control_name.LuaString or control_name

                if private[self].NamedControls[control_name] then
                    error("A control is already registered with the name '" .. control_name .. "'", 2)
                end

                private[self].NamedControls[control_name] = control
            end

            return control
        end
    end

    --[[
    % FindControl

    **[PDK Port]**
    Finds a control based on its ID.

    @ self (FCMCustomWindow)
    @ control_id (number)
    : (FCMControl|nil)
    ]]
    function props:FindControl(control_id)
        mixin.assert_argument(control_id, "number", 2)

        return private[self].Controls[control_id]
    end

    --[[
    % GetControl

    Finds a control based on its name.

    @ self (FCMCustomWindow)
    @ control_name (FCString|string)
    : (FCMControl|nil)
    ]]
    function props:GetControl(control_name)
        mixin.assert_argument(control_name, {"string", "FCString"}, 2)
        return private[self].NamedControls[control_name]
    end

    --[[
    % Each

    An iterator for controls that can filter by class.

    @ self (FCMCustomWindow)
    @ [class_filter] (string) A class name, can be a parent class. See documentation `mixin.is_instance_of` for details on class filtering.
    : (function) An iterator function.
    ]]
    function props:Each(class_filter)
        local i = -1
        local v
        local iterator = function()
            repeat
                i = i + 1
                v = mixin.FCMCustomWindow.GetItemAt(self, i)
            until not v or not class_filter or mixin.is_instance_of(v, class_filter)

            return v
        end

        return iterator
    end

    --[[
    % GetItemAt

    **[Override]**
    Ensures that the original control object is returned.

    @ self (FCMCustomWindow)
    @ index (number)
    : (FCMControl)
    ]]
    function props:GetItemAt(index)
        local item = self:GetItemAt_(index)
        return item and private[self].Controls[item:GetControlID()] or item
    end

    --[[
    % CreateCloseButton

    **[>= v0.56] [Override]**
    Add optional `control_name` parameter.

    @ self (FCMCustomWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (FCString|string) Optional name to allow access from `GetControl` method.
    : (FCMCtrlButton)
    ]]
    if finenv.MajorVersion > 0 or finenv.MinorVersion >= 56 then
        function props.CreateCloseButton(self, x, y, control_name)
            mixin.assert_argument(x, "number", 2)
            mixin.assert_argument(y, "number", 3)
            mixin.assert_argument(control_name, {"string", "nil", "FCString"}, 4)

            local control = self:CreateCloseButton_(x, y)
            private[self].Controls[control:GetControlID()] = control
            control:RegisterParent(self)

            if control_name then
                control_name = type(control_name) == "userdata" and control_name.LuaString or control_name

                if private[self].NamedControls[control_name] then
                    error("A control is already registered with the name '" .. control_name .. "'", 2)
                end

                private[self].NamedControls[control_name] = control
            end

            return control
        end
    end

    --[[
    % GetParent

    **[PDK Port]**
    Returns the parent window. The parent will only be available while the window is showing.

    @ self (FCMCustomWindow)
    : (FCMCustomWindow|nil) `nil` if no parent
    ]]
    function props:GetParent()
        return private[self].Parent
    end

    --[[
    % ExecuteModal

    **[Override]**
    Stores the parent window to make it available via `GetParent`.

    @ self (FCMCustomWindow)
    @ parent (FCCustomWindow|FCMCustomWindow|nil)
    : (number)
    ]]
    function props:ExecuteModal(parent)
        private[self].Parent = parent
        local ret = self:ExecuteModal_(parent)
        private[self].Parent = nil
        return ret
    end

    return props

end

__imports["mixin.FCMNoteEntry"] = __imports["mixin.FCMNoteEntry"] or function()
    -- Author: Edward Koltun
    -- Date: August 26, 2022
    --[[
    $module FCMNoteEntry

    Summary of modifications:
    - Added methods to keep parent collection in scope
    ]] --
    local mixin = require("library.mixin")

    local private = setmetatable({}, {__mode = "k"})
    local props = {}

    --[[
    % Init

    **[Internal]**

    @ self (FCMNoteEntry)
    ]]
    function props:Init()
        private[self] = private[self] or {}
    end

    --[[
    % RegisterParent

    **[Fluid]**
    Registers the collection to which this object belongs.

    @ self (FCMNoteEntry)
    @ parent (FCNoteEntryCell)
    ]]
    function props:RegisterParent(parent)
        mixin.assert_argument(parent, 'FCNoteEntryCell', 2)

        if not private[self].Parent then
            private[self].Parent = parent
        end
    end

    --[[
    % GetParent

    Returns the collection to which this object belongs.

    @ self (FCMNoteEntry)
    : (FCMNoteEntryCell|nil)
    ]]
    function props:GetParent()
        return private[self].Parent
    end

    return props

end

__imports["mixin.FCMNoteEntryCell"] = __imports["mixin.FCMNoteEntryCell"] or function()
    -- Author: Edward Koltun
    -- Date: August 26, 2022
    --[[
    $module FCMNoteEntryCell

    Summary of modifications:
    - Attach collection to child object before returning
    ]] --

    local mixin = require("library.mixin")

    local props = {}

    --[[
    % GetItemAt

    **[Override]**
    Registers this collection as the parent of the item before returning it.
    This allows the item to be used outside of a `mixin.eachentry` loop.

    @ self (FCMNoteEntryCell)
    @ index (number)
    : (FCMNoteEntry|nil)
    ]]
    function props:GetItemAt(index)
        mixin.assert_argument(index, "number", 2)

        local item = self:GetItemAt_(index)
        if item then
            item:RegisterParent(self)
        end

        return item
    end

    return props

end

__imports["mixin.FCMPage"] = __imports["mixin.FCMPage"] or function()
    --  Author: Edward Koltun
    --  Date: April 13, 2021
    --[[
    $module FCMPage

    Summary of modifications:
    - Added methods for getting and setting the page size by its name according to the `page_size` library.
    - Added method for checking if the page is blank.
    ]] --
    local mixin = require("library.mixin")
    local page_size = require("library.page_size")

    local props = {}

    --[[
    % GetSize

    Returns the size of the page.

    @ self (FCMPage)
    : (string|nil) The page size or `nil` if there is no defined size that matches the dimensions of this page.
    ]]
    function props:GetSize()
        return page_size.get_page_size(self)
    end

    --[[
    % SetSize

    **[Fluid]**
    Sets the dimensions of this page to match the given size. Page orientation will be preserved.

    @ self (FCMPage)
    @ size (string) A defined page size.
    ]]
    function props:SetSize(size)
        mixin.assert_argument(size, "string", 2)
        mixin.assert(page_size.is_size(size), "'" .. size .. "' is not a valid page size.")

        page_size.set_page_size(self, size)
    end

    --[[
    % IsBlank

    Checks if this is a blank page (ie it contains no systems).

    @ self (FCMPage)
    : (boolean) `true` if this is page is blank
    ]]
    function props:IsBlank()
        return self:GetFirstSystem() == -1
    end

    return props

end

__imports["mixin.FCMString"] = __imports["mixin.FCMString"] or function()
    --  Author: Edward Koltun
    --  Date: August 8, 2022
    --[[
    $module FCMString

    Summary of modifications:
    - Added `GetMeasurementInteger` and `SetMeasurementInteger` methods for parity with `FCCtrlEdit`
    ]] --
    local mixin = require("library.mixin")
    local utils = require("library.utils")

    local props = {}

    --[[
    % GetMeasurementInteger

    Returns the measurement in whole EVPUs.

    @ self (FCMString)
    @ measurementunit (number) Any of the `finale.MEASUREMENTUNIT*_` constants.
    : (number)
    ]]
    function props:GetMeasurementInteger(measurementunit)
        mixin.assert_argument(measurementunit, "number", 2)

        return utils.round(self:GetMeasurement_(measurementunit))
    end

    --[[
    % SetMeasurementInteger

    **[Fluid]**
    Sets a measurement in whole EVPUs.

    @ self (FCMString)
    @ value (number) The value in whole EVPUs.
    @ measurementunit (number) Any of the `finale.MEASUREMENTUNIT*_` constants.
    ]]
    function props:SetMeasurementInteger(value, measurementunit)
        mixin.assert_argument(value, "number", 2)
        mixin.assert_argument(measurementunit, "number", 3)

        self:SetMeasurement_(utils.round(value), measurementunit)
    end

    return props

end

__imports["library.client"] = __imports["library.client"] or function()
    --[[
    $module Client

    Get information about the current client. For the purposes of Finale Lua, the client is
    the Finale application that's running on someones machine. Therefore, the client has
    details about the user's setup, such as their Finale version, plugin version, and
    operating system.

    One of the main uses of using client details is to check its capabilities. As such,
    the bulk of this library is helper functions to determine what the client supports.
    ]] --
    local client = {}

    local function to_human_string(feature)
        return string.gsub(feature, "_", " ")
    end

    local function requires_later_plugin_version(feature)
        if feature then
            return "This script uses " .. to_human_string(feature) .. "which is only available in a later version of RGP Lua. Please update RGP Lua instead to use this script."
        end
        return "This script requires a later version of RGP Lua. Please update RGP Lua instead to use this script."
    end

    local function requires_rgp_lua(feature)
        if feature then
            return "This script uses " .. to_human_string(feature) .. " which is not available on JW Lua. Please use RGP Lua instead to use this script."
        end
        return "This script requires RGP Lua, the successor of JW Lua. Please use RGP Lua instead to use this script."
    end

    local function requires_plugin_version(version, feature)
        if tonumber(version) <= 0.54 then
            if feature then
                return "This script uses " .. to_human_string(feature) .. " which requires RGP Lua or JW Lua version " .. version ..
                           " or later. Please update your plugin to use this script."
            end
            return "This script requires RGP Lua or JW Lua version " .. version .. " or later. Please update your plugin to use this script."
        end
        if feature then
            return "This script uses " .. to_human_string(feature) .. " which requires RGP Lua version " .. version .. " or later. Please update your plugin to use this script."
        end
        return "This script requires RGP Lua version " .. version .. " or later. Please update your plugin to use this script."
    end

    local function requires_finale_version(version, feature)
        return "This script uses " .. to_human_string(feature) .. ", which is only available on Finale " .. version .. " or later"
    end

    --[[
    % get_raw_finale_version
    Returns a raw Finale version from major, minor, and (optional) build parameters. For 32-bit Finale
    this is the internal major Finale version, not the year.

    @ major (number) Major Finale version
    @ minor (number) Minor Finale version
    @ [build] (number) zero if omitted

    : (number)
    ]]
    function client.get_raw_finale_version(major, minor, build)
        local retval = bit32.bor(bit32.lshift(math.floor(major), 24), bit32.lshift(math.floor(minor), 20))
        if build then
            retval = bit32.bor(retval, math.floor(build))
        end
        return retval
    end

    --[[
    % get_lua_plugin_version
    Returns a number constructed from `finenv.MajorVersion` and `finenv.MinorVersion`. The reason not
    to use `finenv.StringVersion` is that `StringVersion` can contain letters if it is a pre-release
    version.

    : (number)
    ]]
    function client.get_lua_plugin_version()
        local num_string = tostring(finenv.MajorVersion) .. "." .. tostring(finenv.MinorVersion)
        return tonumber(num_string)
    end

    local features = {
        clef_change = {
            test = client.get_lua_plugin_version() >= 0.60,
            error = requires_plugin_version("0.58", "a clef change"),
        },
        ["FCKeySignature::CalcTotalChromaticSteps"] = {
            test = finenv.IsRGPLua and finale.FCKeySignature.__class.CalcTotalChromaticSteps,
            error = requires_later_plugin_version("a custom key signature"),
        },
        ["FCCategory::SaveWithNewType"] = {
            test = client.get_lua_plugin_version() >= 0.58,
            error = requires_plugin_version("0.58"),
        },
        ["finenv.QueryInvokedModifierKeys"] = {
            test = finenv.IsRGPLua and finenv.QueryInvokedModifierKeys,
            error = requires_later_plugin_version(),
        },
        ["FCCustomLuaWindow::ShowModeless"] = {
            test = finenv.IsRGPLua,
            error = requires_rgp_lua("a modeless dialog")
        },
        ["finenv.RetainLuaState"] = {
            test = finenv.IsRGPLua and finenv.RetainLuaState ~= nil,
            error = requires_later_plugin_version(),
        },
        smufl = {
            test = finenv.RawFinaleVersion >= client.get_raw_finale_version(27, 1),
            error = requires_finale_version("27.1", "a SMUFL font"),
        },
    }

    --[[
    % supports

    Checks the client supports a given feature. Returns true if the client
    supports the feature, false otherwise.

    To assert the client must support a feature, use `client.assert_supports`.

    For a list of valid features, see the [`features` table in the codebase](https://github.com/finale-lua/lua-scripts/blob/master/src/library/client.lua#L52).

    @ feature (string) The feature the client should support.
    : (boolean)
    ]]
    function client.supports(feature)
        if features[feature].test == nil then
            error("a test does not exist for feature " .. feature, 2)
        end
        return features[feature].test
    end

    --[[
    % assert_supports

    Asserts that the client supports a given feature. If the client doesn't
    support the feature, this function will throw an friendly error then
    exit the program.

    To simply check if a client supports a feature, use `client.supports`.

    For a list of valid features, see the [`features` table in the codebase](https://github.com/finale-lua/lua-scripts/blob/master/src/library/client.lua#L52).

    @ feature (string) The feature the client should support.
    : (boolean)
    ]]
    function client.assert_supports(feature)
        local error_level = finenv.DebugEnabled and 2 or 0
        if not client.supports(feature) then
            if features[feature].error then
                error(features[feature].error, error_level)
            end
            -- Generic error message
            error("Your Finale version does not support " .. to_human_string(feature), error_level)
        end
        return true
    end

    return client

end

__imports["library.general_library"] = __imports["library.general_library"] or function()
    --[[
    $module Library
    ]] --
    local library = {}

    local client = require("library.client")

    --[[
    % group_overlaps_region

    Returns true if the input staff group overlaps with the input music region, otherwise false.

    @ staff_group (FCGroup)
    @ region (FCMusicRegion)
    : (boolean)
    ]]
    function library.group_overlaps_region(staff_group, region)
        if region:IsFullDocumentSpan() then
            return true
        end
        local staff_exists = false
        local sys_staves = finale.FCSystemStaves()
        sys_staves:LoadAllForRegion(region)
        for sys_staff in each(sys_staves) do
            if staff_group:ContainsStaff(sys_staff:GetStaff()) then
                staff_exists = true
                break
            end
        end
        if not staff_exists then
            return false
        end
        if (staff_group.StartMeasure > region.EndMeasure) or (staff_group.EndMeasure < region.StartMeasure) then
            return false
        end
        return true
    end

    --[[
    % group_is_contained_in_region

    Returns true if the entire input staff group is contained within the input music region.
    If the start or end staff are not visible in the region, it returns false.

    @ staff_group (FCGroup)
    @ region (FCMusicRegion)
    : (boolean)
    ]]
    function library.group_is_contained_in_region(staff_group, region)
        if not region:IsStaffIncluded(staff_group.StartStaff) then
            return false
        end
        if not region:IsStaffIncluded(staff_group.EndStaff) then
            return false
        end
        return true
    end

    --[[
    % staff_group_is_multistaff_instrument

    Returns true if the entire input staff group is a multistaff instrument.

    @ staff_group (FCGroup)
    : (boolean)
    ]]
    function library.staff_group_is_multistaff_instrument(staff_group)
        local multistaff_instruments = finale.FCMultiStaffInstruments()
        multistaff_instruments:LoadAll()
        for inst in each(multistaff_instruments) do
            if inst:ContainsStaff(staff_group.StartStaff) and (inst.GroupID == staff_group:GetItemID()) then
                return true
            end
        end
        return false
    end

    --[[
    % get_selected_region_or_whole_doc

    Returns a region that contains the selected region if there is a selection or the whole document if there isn't.
    SIDE-EFFECT WARNING: If there is no selected region, this function also changes finenv.Region() to the whole document.

    : (FCMusicRegion)
    ]]
    function library.get_selected_region_or_whole_doc()
        local sel_region = finenv.Region()
        if sel_region:IsEmpty() then
            sel_region:SetFullDocument()
        end
        return sel_region
    end

    --[[
    % get_first_cell_on_or_after_page

    Returns the first FCCell at the top of the input page. If the page is blank, it returns the first cell after the input page.

    @ page_num (number)
    : (FCCell)
    ]]
    function library.get_first_cell_on_or_after_page(page_num)
        local curr_page_num = page_num
        local curr_page = finale.FCPage()
        local got1 = false
        -- skip over any blank pages
        while curr_page:Load(curr_page_num) do
            if curr_page:GetFirstSystem() > 0 then
                got1 = true
                break
            end
            curr_page_num = curr_page_num + 1
        end
        if got1 then
            local staff_sys = finale.FCStaffSystem()
            staff_sys:Load(curr_page:GetFirstSystem())
            return finale.FCCell(staff_sys.FirstMeasure, staff_sys.TopStaff)
        end
        -- if we got here there were nothing but blank pages left at the end
        local end_region = finale.FCMusicRegion()
        end_region:SetFullDocument()
        return finale.FCCell(end_region.EndMeasure, end_region.EndStaff)
    end

    --[[
    % get_top_left_visible_cell

    Returns the topmost, leftmost visible FCCell on the screen, or the closest possible estimate of it.

    : (FCCell)
    ]]
    function library.get_top_left_visible_cell()
        if not finenv.UI():IsPageView() then
            local all_region = finale.FCMusicRegion()
            all_region:SetFullDocument()
            return finale.FCCell(finenv.UI():GetCurrentMeasure(), all_region.StartStaff)
        end
        return library.get_first_cell_on_or_after_page(finenv.UI():GetCurrentPage())
    end

    --[[
    % get_top_left_selected_or_visible_cell

    If there is a selection, returns the topmost, leftmost cell in the selected region.
    Otherwise returns the best estimate for the topmost, leftmost currently visible cell.

    : (FCCell)
    ]]
    function library.get_top_left_selected_or_visible_cell()
        local sel_region = finenv.Region()
        if not sel_region:IsEmpty() then
            return finale.FCCell(sel_region.StartMeasure, sel_region.StartStaff)
        end
        return library.get_top_left_visible_cell()
    end

    --[[
    % is_default_measure_number_visible_on_cell

    Returns true if measure numbers for the input region are visible on the input cell for the staff system.

    @ meas_num_region (FCMeasureNumberRegion)
    @ cell (FCCell)
    @ staff_system (FCStaffSystem)
    @ current_is_part (boolean) true if the current view is a linked part, otherwise false
    : (boolean)
    ]]
    function library.is_default_measure_number_visible_on_cell(meas_num_region, cell, staff_system, current_is_part)
        local staff = finale.FCCurrentStaffSpec()
        if not staff:LoadForCell(cell, 0) then
            return false
        end
        if meas_num_region:GetShowOnTopStaff() and (cell.Staff == staff_system.TopStaff) then
            return true
        end
        if meas_num_region:GetShowOnBottomStaff() and (cell.Staff == staff_system:CalcBottomStaff()) then
            return true
        end
        if staff.ShowMeasureNumbers then
            return not meas_num_region:GetExcludeOtherStaves(current_is_part)
        end
        return false
    end

    --[[
    % calc_parts_boolean_for_measure_number_region

    Returns the correct boolean value to use when requesting information about a measure number region.

    @ meas_num_region (FCMeasureNumberRegion)
    @ [for_part] (boolean) true if requesting values for a linked part, otherwise false. If omitted, this value is calculated.
    : (boolean) the value to pass to FCMeasureNumberRegion methods with a parts boolean
    ]]
    function library.calc_parts_boolean_for_measure_number_region(meas_num_region, for_part)
        if meas_num_region.UseScoreInfoForParts then
            return false
        end
        if nil == for_part then
            return finenv.UI():IsPartView()
        end
        return for_part
    end

    --[[
    % is_default_number_visible_and_left_aligned

    Returns true if measure number for the input cell is visible and left-aligned.

    @ meas_num_region (FCMeasureNumberRegion)
    @ cell (FCCell)
    @ system (FCStaffSystem)
    @ current_is_part (boolean) true if the current view is a linked part, otherwise false
    @ is_for_multimeasure_rest (boolean) true if the current cell starts a multimeasure rest
    : (boolean)
    ]]
    function library.is_default_number_visible_and_left_aligned(meas_num_region, cell, system, current_is_part, is_for_multimeasure_rest)
        current_is_part = library.calc_parts_boolean_for_measure_number_region(meas_num_region, current_is_part)
        if is_for_multimeasure_rest and meas_num_region:GetShowOnMultiMeasureRests(current_is_part) then
            if (finale.MNALIGN_LEFT ~= meas_num_region:GetMultiMeasureAlignment(current_is_part)) then
                return false
            end
        elseif (cell.Measure == system.FirstMeasure) then
            if not meas_num_region:GetShowOnSystemStart() then
                return false
            end
            if (finale.MNALIGN_LEFT ~= meas_num_region:GetStartAlignment(current_is_part)) then
                return false
            end
        else
            if not meas_num_region:GetShowMultiples(current_is_part) then
                return false
            end
            if (finale.MNALIGN_LEFT ~= meas_num_region:GetMultipleAlignment(current_is_part)) then
                return false
            end
        end
        return library.is_default_measure_number_visible_on_cell(meas_num_region, cell, system, current_is_part)
    end

    --[[
    % update_layout

    Updates the page layout.

    @ [from_page] (number) page to update from, defaults to 1
    @ [unfreeze_measures] (boolean) defaults to false
    ]]
    function library.update_layout(from_page, unfreeze_measures)
        from_page = from_page or 1
        unfreeze_measures = unfreeze_measures or false
        local page = finale.FCPage()
        if page:Load(from_page) then
            page:UpdateLayout(unfreeze_measures)
        end
    end

    --[[
    % get_current_part

    Returns the currently selected part or score.

    : (FCPart)
    ]]
    function library.get_current_part()
        local part = finale.FCPart(finale.PARTID_CURRENT)
        part:Load(part.ID)
        return part
    end

    --[[
    % get_score

    Returns an `FCPart` instance that represents the score.

    : (FCPart)
    ]]
    function library.get_score()
        local part = finale.FCPart(finale.PARTID_SCORE)
        part:Load(part.ID)
        return part
    end

    --[[
    % get_page_format_prefs

    Returns the default page format prefs for score or parts based on which is currently selected.

    : (FCPageFormatPrefs)
    ]]
    function library.get_page_format_prefs()
        local current_part = library.get_current_part()
        local page_format_prefs = finale.FCPageFormatPrefs()
        local success = false
        if current_part:IsScore() then
            success = page_format_prefs:LoadScore()
        else
            success = page_format_prefs:LoadParts()
        end
        return page_format_prefs, success
    end

    local calc_smufl_directory = function(for_user)
        local is_on_windows = finenv.UI():IsOnWindows()
        local do_getenv = function(win_var, mac_var)
            if finenv.UI():IsOnWindows() then
                return win_var and os.getenv(win_var) or ""
            else
                return mac_var and os.getenv(mac_var) or ""
            end
        end
        local smufl_directory = for_user and do_getenv("LOCALAPPDATA", "HOME") or do_getenv("COMMONPROGRAMFILES")
        if not is_on_windows then
            smufl_directory = smufl_directory .. "/Library/Application Support"
        end
        smufl_directory = smufl_directory .. "/SMuFL/Fonts/"
        return smufl_directory
    end

    --[[
    % get_smufl_font_list

    Returns table of installed SMuFL font names by searching the directory that contains
    the .json files for each font. The table is in the format:

    ```lua
    <font-name> = "user" | "system"
    ```

    : (table) an table with SMuFL font names as keys and values "user" or "system"
    ]]

    function library.get_smufl_font_list()
        local font_names = {}
        local add_to_table = function(for_user)
            local smufl_directory = calc_smufl_directory(for_user)
            local get_dirs = function()
                if finenv.UI():IsOnWindows() then
                    return io.popen("dir \"" .. smufl_directory .. "\" /b /ad")
                else
                    return io.popen("ls \"" .. smufl_directory .. "\"")
                end
            end
            local is_font_available = function(dir)
                local fc_dir = finale.FCString()
                fc_dir.LuaString = dir
                return finenv.UI():IsFontAvailable(fc_dir)
            end
            for dir in get_dirs():lines() do
                if not dir:find("%.") then
                    dir = dir:gsub(" Bold", "")
                    dir = dir:gsub(" Italic", "")
                    local fc_dir = finale.FCString()
                    fc_dir.LuaString = dir
                    if font_names[dir] or is_font_available(dir) then
                        font_names[dir] = for_user and "user" or "system"
                    end
                end
            end
        end
        add_to_table(true)
        add_to_table(false)
        return font_names
    end

    --[[
    % get_smufl_metadata_file

    @ [font_info] (FCFontInfo) if non-nil, the font to search for; if nil, search for the Default Music Font
    : (file handle|nil)
    ]]
    function library.get_smufl_metadata_file(font_info)
        if not font_info then
            font_info = finale.FCFontInfo()
            font_info:LoadFontPrefs(finale.FONTPREF_MUSIC)
        end

        local try_prefix = function(prefix, font_info)
            local file_path = prefix .. font_info.Name .. "/" .. font_info.Name .. ".json"
            return io.open(file_path, "r")
        end

        local user_file = try_prefix(calc_smufl_directory(true), font_info)
        if user_file then
            return user_file
        end

        return try_prefix(calc_smufl_directory(false), font_info)
    end

    --[[
    % is_font_smufl_font

    @ [font_info] (FCFontInfo) if non-nil, the font to check; if nil, check the Default Music Font
    : (boolean)
    ]]
    function library.is_font_smufl_font(font_info)
        if not font_info then
            font_info = finale.FCFontInfo()
            font_info:LoadFontPrefs(finale.FONTPREF_MUSIC)
        end

        if client.supports("smufl") then
            if nil ~= font_info.IsSMuFLFont then -- if this version of the lua interpreter has the IsSMuFLFont property (i.e., RGP Lua 0.59+)
                return font_info.IsSMuFLFont
            end
        end

        local smufl_metadata_file = library.get_smufl_metadata_file(font_info)
        if nil ~= smufl_metadata_file then
            io.close(smufl_metadata_file)
            return true
        end
        return false
    end

    --[[
    % simple_input

    Creates a simple dialog box with a single 'edit' field for entering values into a script, similar to the old UserValueInput command. Will automatically resize the width to accomodate longer strings.

    @ [title] (string) the title of the input dialog box
    @ [text] (string) descriptive text above the edit field
    : string
    ]]
    function library.simple_input(title, text)
        local return_value = finale.FCString()
        return_value.LuaString = ""
        local str = finale.FCString()
        local min_width = 160
        --
        function format_ctrl(ctrl, h, w, st)
            ctrl:SetHeight(h)
            ctrl:SetWidth(w)
            str.LuaString = st
            ctrl:SetText(str)
        end -- function format_ctrl
        --
        title_width = string.len(title) * 6 + 54
        if title_width > min_width then
            min_width = title_width
        end
        text_width = string.len(text) * 6
        if text_width > min_width then
            min_width = text_width
        end
        --
        str.LuaString = title
        local dialog = finale.FCCustomLuaWindow()
        dialog:SetTitle(str)
        local descr = dialog:CreateStatic(0, 0)
        format_ctrl(descr, 16, min_width, text)
        local input = dialog:CreateEdit(0, 20)
        format_ctrl(input, 20, min_width, "") -- edit "" for defualt value
        dialog:CreateOkButton()
        dialog:CreateCancelButton()
        --
        function callback(ctrl)
        end -- callback
        --
        dialog:RegisterHandleCommand(callback)
        --
        if dialog:ExecuteModal(nil) == finale.EXECMODAL_OK then
            return_value.LuaString = input:GetText(return_value)
            -- print(return_value.LuaString)
            return return_value.LuaString
            -- OK button was pressed
        end
    end -- function simple_input

    --[[
    % is_finale_object

    Attempts to determine if an object is a Finale object through ducktyping

    @ object (__FCBase)
    : (bool)
    ]]
    function library.is_finale_object(object)
        -- All finale objects implement __FCBase, so just check for the existence of __FCBase methods
        return object and type(object) == "userdata" and object.ClassName and object.GetClassID and true or false
    end

    --[[
    % system_indent_set_to_prefs

    Sets the system to match the indentation in the page preferences currently in effect. (For score or part.)
    The page preferences may be provided optionally to avoid loading them for each call.

    @ system (FCStaffSystem)
    @ [page_format_prefs] (FCPageFormatPrefs) page format preferences to use, if supplied.
    : (boolean) `true` if the system was successfully updated.
    ]]
    function library.system_indent_set_to_prefs(system, page_format_prefs)
        page_format_prefs = page_format_prefs or library.get_page_format_prefs()
        local first_meas = finale.FCMeasure()
        local is_first_system = (system.FirstMeasure == 1)
        if (not is_first_system) and first_meas:Load(system.FirstMeasure) then
            if first_meas.ShowFullNames then
                is_first_system = true
            end
        end
        if is_first_system and page_format_prefs.UseFirstSystemMargins then
            system.LeftMargin = page_format_prefs.FirstSystemLeft
        else
            system.LeftMargin = page_format_prefs.SystemLeft
        end
        return system:Save()
    end

    --[[
    % calc_script_name

    Returns the running script name, with or without extension.

    @ [include_extension] (boolean) Whether to include the file extension in the return value: `false` if omitted
    : (string) The name of the current running script.
    ]]
    function library.calc_script_name(include_extension)
        local fc_string = finale.FCString()
        if finenv.RunningLuaFilePath then
            -- Use finenv.RunningLuaFilePath() if available because it doesn't ever get overwritten when retaining state.
            fc_string.LuaString = finenv.RunningLuaFilePath()
        else
            -- This code path is only taken by JW Lua (and very early versions of RGP Lua).
            -- SetRunningLuaFilePath is not reliable when retaining state, so later versions use finenv.RunningLuaFilePath.
            fc_string:SetRunningLuaFilePath()
        end
        local filename_string = finale.FCString()
        fc_string:SplitToPathAndFile(nil, filename_string)
        local retval = filename_string.LuaString
        if not include_extension then
            retval = retval:match("(.+)%..+")
            if not retval or retval == "" then
                retval = filename_string.LuaString
            end
        end
        return retval
    end

    --[[
    % get_default_music_font_name

    Fetches the default music font from document options and processes the name into a usable format.

    : (string) The name of the defalt music font.
    ]]
    function library.get_default_music_font_name()
        local fontinfo = finale.FCFontInfo()
        local default_music_font_name = finale.FCString()
        if fontinfo:LoadFontPrefs(finale.FONTPREF_MUSIC) then
            fontinfo:GetNameString(default_music_font_name)
            return default_music_font_name.LuaString
        end
    end

    return library

end

__imports["mixin.FCMStrings"] = __imports["mixin.FCMStrings"] or function()
    --  Author: Edward Koltun
    --  Date: March 3, 2022
    --[[
    $module FCMStrings

    Summary of modifications:
    - Methods that accept `FCString` now also accept Lua `string` and `number` (except for folder loading methods which do not accept `number`).
    - Setters that accept `FCStrings` now also accept multiple arguments of `FCString`, Lua `string`, or `number`.
    ]] --
    local mixin = require("library.mixin")
    local library = require("library.general_library")

    local props = {}

    local temp_str = finale.FCString()

    --[[
    % AddCopy

    **[Override]**
    Accepts Lua `string` and `number` in addition to `FCString`.

    @ self (FCMStrings)
    @ str (FCString|string|number)
    : (boolean) True on success.
    ]]
    function props:AddCopy(str)
        mixin.assert_argument(str, {"string", "number", "FCString"}, 2)

        if type(str) ~= "userdata" then
            temp_str.LuaString = tostring(str)
            str = temp_str
        end

        return self:AddCopy_(str)
    end

    --[[
    % AddCopies

    **[Override]**
    Same as `AddCopy`, but accepts multiple arguments so that multiple strings can be added at a time.

    @ self (FCMStrings)
    @ ... (FCStrings|FCString|string|number) `number`s will be cast to `string`
    : (boolean) `true` if successful
    ]]
    function props:AddCopies(...)
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            mixin.assert_argument(v, {"FCStrings", "FCString", "string", "number"}, i + 1)
            if type(v) == "userdata" and v:ClassName() == "FCStrings" then
                for str in each(v) do
                    v:AddCopy_(str)
                end
            else
                mixin.FCStrings.AddCopy(self, v)
            end
        end

        return true
    end

    --[[
    % CopyFrom

    **[Override]**
    Accepts multiple arguments.

    @ self (FCMStrings)
    @ ... (FCStrings|FCString|string|number) `number`s will be cast to `string`
    : (boolean) `true` if successful
    ]]
    function props:CopyFrom(...)
        local num_args = select("#", ...)
        local first = select(1, ...)
        mixin.assert_argument(first, {"FCStrings", "FCString", "string", "number"}, 2)

        if library.is_finale_object(first) and first:ClassName() == "FCStrings" then
            self:CopyFrom_(first)
        else
            self:ClearAll_()
            mixin.FCMStrings.AddCopy(self, first)
        end

        for i = 2, num_args do
            local v = select(i, ...)
            mixin.assert_argument(v, {"FCStrings", "FCString", "string", "number"}, i + 1)

            if type(v) == "userdata" then
                if v:ClassName() == "FCString" then
                    self:AddCopy_(v)
                elseif v:ClassName() == "FCStrings" then
                    for str in each(v) do
                        v:AddCopy_(str)
                    end
                end
            else
                temp_str.LuaString = tostring(v)
                self:AddCopy_(temp_str)
            end
        end

        return true
    end

    --[[
    % Find

    **[Override]**
    Accepts Lua `string` and `number` in addition to `FCString`.

    @ self (FCMStrings)
    @ str (FCString|string|number)
    : (FCMString|nil)
    ]]
    function props:Find(str)
        mixin.assert_argument(str, {"string", "number", "FCString"}, 2)

        if type(str) ~= "userdata" then
            temp_str.LuaString = tostring(str)
            str = temp_str
        end

        return self:Find_(str)
    end

    --[[
    % FindNocase

    **[Override]**
    Accepts Lua `string` and `number` in addition to `FCString`.

    @ self (FCMStrings)
    @ str (FCString|string|number)
    : (FCMString|nil)
    ]]
    function props:FindNocase(str)
        mixin.assert_argument(str, {"string", "number", "FCString"}, 2)

        if type(str) ~= "userdata" then
            temp_str.LuaString = tostring(str)
            str = temp_str
        end

        return self:FindNocase_(str)
    end

    --[[
    % LoadFolderFiles

    **[Override]**
    Accepts Lua `string` in addition to `FCString`.

    @ self (FCMStrings)
    @ folderstring (FCString|string)
    : (boolean) True on success.
    ]]
    function props:LoadFolderFiles(folderstring)
        mixin.assert_argument(folderstring, {"string", "FCString"}, 2)

        if type(folderstring) ~= "userdata" then
            temp_str.LuaString = tostring(folderstring)
            folderstring = temp_str
        end

        return self:LoadFolderFiles_(folderstring)
    end

    --[[
    % LoadSubfolders

    **[Override]**
    Accepts Lua `string` in addition to `FCString`.

    @ self (FCMStrings)
    @ folderstring (FCString|string)
    : (boolean) True on success.
    ]]
    function props:LoadSubfolders(folderstring)
        mixin.assert_argument(folderstring, {"string", "FCString"}, 2)

        if type(folderstring) ~= "userdata" then
            temp_str.LuaString = tostring(folderstring)
            folderstring = temp_str
        end

        return self:LoadSubfolders_(folderstring)
    end

    --[[
    % InsertStringAt

    **[>= v0.59] [Fluid] [Override]**
    Accepts Lua `string` and `number` in addition to `FCString`.

    @ self (FCMStrings)
    @ str (FCString|string|number)
    @ index (number)
    ]]
    if finenv.MajorVersion > 0 or finenv.MinorVersion >= 59 then
        function props:InsertStringAt(str, index)
            mixin.assert_argument(str, {"string", "number", "FCString"}, 2)
            mixin.assert_argument(index, "number", 3)

            if type(str) ~= "userdata" then
                temp_str.LuaString = tostring(str)
                str = temp_str
            end

            self:InsertStringAt_(str, index)
        end
    end

    return props

end

__imports["mixin.FCMTreeNode"] = __imports["mixin.FCMTreeNode"] or function()
    --  Author: Edward Koltun
    --  Date: April 6, 2022
    --[[
    $module FCMTreeNode

    Summary of modifications:
    - Setters that accept `FCString` now also accept Lua `string` and `number`.
    - In getters with an `FCString` parameter, the parameter is now optional and a Lua `string` is returned. 
    ]] --
    local mixin = require("library.mixin")

    local props = {}

    local temp_str = finale.FCString()

    --[[
    % GetText

    **[Override]**
    Returns a Lua `string` and makes passing an `FCString` optional.

    @ self (FCMTreeNode)
    @ [str] (FCString)
    : (string)
    ]]
    function props:GetText(str)
        mixin.assert_argument(str, {"nil", "FCString"}, 2)

        if not str then
            str = temp_str
        end

        self:GetText_(str)

        return str.LuaString
    end

    --[[
    % SetText

    **[Fluid] [Override]**
    Accepts Lua `string` and `number` in addition to `FCString`.

    @ self (FCMTreeNode)
    @ str (FCString|string|number)
    ]]
    function props:SetText(str)
        mixin.assert_argument(str, {"string", "number", "FCString"}, 2)

        if type(str) ~= "userdata" then
            temp_str.LuaString = tostring(str)
            str = temp_str
        end

        self:SetText_(str)
    end

    return props

end

__imports["mixin.FCMUI"] = __imports["mixin.FCMUI"] or function()
    --  Author: Edward Koltun
    --  Date: April 13, 2021
    --[[
    $module FCMUI

    Summary of modifications:
    - In getters with an `FCString` parameter, the parameter is now optional and a Lua `string` is returned. 
    ]] --
    local mixin = require("library.mixin")

    local props = {}

    local temp_str = finale.FCString()

    --[[
    % GetDecimalSeparator

    **[Override]**
    Returns a Lua `string` and makes passing an `FCString` optional.

    @ self (FCMUI)
    @ [str] (FCString)
    : (string)
    ]]
    function props:GetDecimalSeparator(str)
        mixin.assert_argument(str, {"nil", "FCString"}, 2)

        if not str then
            str = temp_str
        end

        self:GetDecimalSeparator_(str)

        return str.LuaString
    end

    return props

end

__imports["mixin.FCXCtrlMeasurementEdit"] = __imports["mixin.FCXCtrlMeasurementEdit"] or function()
    --  Author: Edward Koltun
    --  Date: April 11, 2022
    --[[
    $module FCXCtrlMeasurementEdit

    *Extends `FCMCtrlEdit`*

    Summary of modifications:
    - Parent window must be an instance of `FCXCustomLuaWindow`
    - Displayed measurement unit will be automatically updated with the parent window
    - Measurement edits can be set to one of three types which correspond to the `GetMeasurement*`, `SetMeasurement*` and *GetRangeMeasurement*` methods. The type affects which methods are used for changing measurement units, for events, and for interacting with an `FCXCtrlUpDown` control.
    - All measurement get and set methods no longer accept a measurement unit as this is taken from the parent window.
    - `Change` event has been overridden to pass a measurement.
    - Added hooks for restoring control state
    ]] --
    local mixin = require("library.mixin")
    local mixin_helper = require("library.mixin_helper")
    local utils = require("library.utils")

    local private = setmetatable({}, {__mode = "k"})
    local props = {MixinParent = "FCMCtrlEdit"}

    local trigger_change
    local each_last_change

    --[[
    % Init

    **[Internal]**

    @ self (FCXCtrlMeasurementEdit)
    ]]
    function props:Init()
        local parent = self:GetParent()
        mixin.assert(mixin.is_instance_of(parent, "FCXCustomLuaWindow"), "FCXCtrlMeasurementEdit must have a parent window that is an instance of FCXCustomLuaWindow")

        private[self] = private[self] or {
            Type = "MeasurementInteger",
            LastMeasurementUnit = parent:GetMeasurementUnit(),
        }
    end

    --[[
    % SetText

    **[Fluid] [Override]**
    Ensures that the overridden `Change` event is triggered.


    @ self (FCXCtrlMeasurementEdit)
    @ str (FCString|string|number)
    ]]

    --[[
    % SetInteger

    **[Fluid] [Override]**
    Ensures that the overridden `Change` event is triggered.

    @ self (FCXCtrlMeasurementEdit)
    @ anint (number)
    ]]

    --[[
    % SetFloat

    **[Fluid] [Override]**
    Ensures that the overridden `Change` event is triggered.

    @ self (FCXCtrlMeasurementEdit)
    @ value (number)
    ]]

    for method, valid_types in pairs({
        Text = {"string", "number", "FCString"},
        Integer = "number",
        Float = "number",
    }) do
        props["Set" .. method] = function(self, value)
            mixin.assert_argument(value, valid_types, 2)

            mixin.FCMCtrlEdit["Set" .. method](self, value)
            trigger_change(self)
        end
    end

    --[[
    % GetMeasurement

    **[Override]**
    Removes the measurement unit parameter, taking it instead from the parent window.

    @ self (FCXCtrlMeasurementEdit)
    : (number)
    ]]

    --[[
    % GetRangeMeasurement

    **[Override]**
    Removes the measurement unit parameter, taking it instead from the parent window.

    @ self (FCXCtrlMeasurementEdit)
    @ minimum (number)
    @ maximum (number)
    : (number)
    ]]

    --[[
    % SetMeasurement

    **[Fluid] [Override]**
    Removes the measurement unit parameter, taking it instead from the parent window.
    Also ensures that the overridden `Change` event is triggered.

    @ self (FCXCtrlMeasurementEdit)
    @ value (number)
    ]]

    --[[
    % GetMeasurementInteger

    **[Override]**
    Removes the measurement unit parameter, taking it instead from the parent window.

    @ self (FCXCtrlMeasurementEdit)
    : (number)
    ]]

    --[[
    % GetRangeMeasurementInteger

    **[Override]**
    Removes the measurement unit parameter, taking it instead from the parent window.

    @ self (FCXCtrlMeasurementEdit)
    @ minimum (number)
    @ maximum (number)
    : (number)
    ]]

    --[[
    % SetMeasurementInteger

    **[Fluid] [Override]**
    Removes the measurement unit parameter, taking it instead from the parent window.
    Also ensures that the overridden `Change` event is triggered.

    @ self (FCXCtrlMeasurementEdit)
    @ value (number)
    ]]

    --[[
    % GetMeasurementEfix

    **[Override]**
    Removes the measurement unit parameter, taking it instead from the parent window.

    @ self (FCXCtrlMeasurementEdit)
    : (number)
    ]]

    --[[
    % GetRangeMeasurementEfix

    **[Override]**
    Removes the measurement unit parameter, taking it instead from the parent window.

    @ self (FCXCtrlMeasurementEdit)
    @ minimum (number)
    @ maximum (number)
    : (number)
    ]]

    --[[
    % SetMeasurementEfix

    **[Fluid] [Override]**
    Removes the measurement unit parameter, taking it instead from the parent window.
    Also ensures that the overridden `Change` event is triggered.

    @ self (FCXCtrlMeasurementEdit)
    @ value (number)
    ]]

    for method, valid_types in pairs({
        Measurement = "number",
        MeasurementInteger = "number",
        MeasurementEfix = "number",
    }) do
        props["Get" .. method] = function(self)
            return mixin.FCMCtrlEdit["Get" .. method](self, private[self].LastMeasurementUnit)
        end

        props["GetRange" .. method] = function(self, minimum, maximum)
            mixin.assert_argument(minimum, "number", 2)
            mixin.assert_argument(maximum, "number", 3)

            return mixin.FCMCtrlEdit["GetRange" .. method](self, private[self].LastMeasurementUnit, minimum, maximum)
        end

        props["Set" .. method] = function (self, value)
            mixin.assert_argument(value, valid_types, 2)

            mixin.FCMCtrlEdit["Set" .. method](self, value, private[self].LastMeasurementUnit)
            trigger_change(self)
        end

        props["IsType" .. method] = function(self)
            return private[self].Type == method
        end
    end

    --[[
    % GetType

    Returns the measurement edit's type. Can also be appended to `"Get"`, `"GetRange"`, or `"Set"` to use type-specific methods.

    @ self (FCXCtrlMeasurementEdit)
    : (string) `"Measurement"`, `"MeasurementInteger"`, or `"MeasurementEfix"`
    ]]
    function props:GetType()
        return private[self].Type
    end

    --[[
    % IsTypeMeasurement

    Checks if the type is `"Measurement"`.

    @ self (FCXCtrlMeasurementEdit)
    : (boolean) 
    ]]

    --[[
    % IsTypeMeasurementInteger

    Checks if the type is `"MeasurementInteger"`.

    @ self (FCXCtrlMeasurementEdit)
    : (boolean) 
    ]]

    --[[
    % IsTypeMeasurementEfix

    Checks if the type is `"MeasurementEfix"`.

    @ self (FCXCtrlMeasurementEdit)
    : (boolean) 
    ]]

    --[[
    % SetTypeMeasurement

    **[Fluid]**
    Sets the type to `"Measurement"`.
    This means that the setters & getters used in events, measurement unit changes, and up down controls are `GetMeasurement`, `GetRangeMeasurement`, and `SetMeasurement`.

    @ self (FCXCtrlMeasurementEdit)
    ]]
    function props:SetTypeMeasurement()
        if private[self].Type == "Measurement" then
            return
        end

        if private[self].Type == "MeasurementEfix" then
            for v in each_last_change(self) do
                v.last_value = v.last_value / 64
            end
        end

        private[self].Type = "Measurement"
    end

    --[[
    % SetTypeMeasurementInteger

    **[Fluid]**
    Sets the type to `"MeasurementInteger"`. This is the default type.
    This means that the setters & getters used in events, measurement unit changes, and up down controls are `GetMeasurementInteger`, `GetRangeMeasurementInteger`, and `SetMeasurementInteger`.

    @ self (FCXCtrlMeasurementEdit)
    ]]
    function props:SetTypeMeasurementInteger()
        if private[self].Type == "MeasurementInteger" then
            return
        end

        if private[self].Type == "Measurement" then
            for v in each_last_change(self) do
                v.last_value = utils.round(v.last_value)
            end
        elseif private[self].Type == "MeasurementEfix" then
            for v in each_last_change(self) do
                v.last_value = utils.round(v.last_value / 64)
            end
        end

        private[self].Type = "MeasurementInteger"
    end

    --[[
    % SetTypeMeasurementEfix

    **[Fluid]**
    Sets the type to `"MeasurementEfix"`.
    This means that the setters & getters used in events, measurement unit changes, and up down controls are `GetMeasurementEfix`, `GetRangeMeasurementEfix`, and `SetMeasurementEfix`.

    @ self (FCXCtrlMeasurementEdit)
    ]]
    function props:SetTypeMeasurementEfix()
        if private[self].Type == "MeasurementEfix" then
            return
        end

        for v in each_last_change(self) do
            v.last_value = v.last_value * 64
        end

        private[self].Type = "MeasurementEfix"
    end

    --[[
    % UpdateMeasurementUnit

    **[Fluid] [Internal]**
    Checks the parent window for a change in measurement unit and updates the control if needed.

    @ self (FCXCtrlMeasurementEdit)
    ]]
    function props:UpdateMeasurementUnit()
        local new_unit = self:GetParent():GetMeasurementUnit()

        if private[self].LastMeasurementUnit ~= new_unit then
            local val = self["Get" .. private[self].Type](self)
            private[self].LastMeasurementUnit = new_unit
            self["Set" .. private[self].Type](self, val)
        end
    end

    --[[
    % HandleChange

    **[Callback Template] [Override]**
    The type and unit of `last_value` will change depending on the measurement edit's type. The possibilities are:
    - `"Measurement"` => EVPUs (with fractional part)
    - `"MeasurementInteger"` => whole EVPUs (without fractional part)
    - `"MeasurementEfix"` => EFIXes (1 EFIX is 1/64th of an EVPU)

    @ control (FCXCtrlMeasurementEdit) The control that was changed.
    @ last_value (number) The previous measurement value of the control.
    ]]

    --[[
    % AddHandleChange

    **[Fluid] [Override]**
    Adds a handler for when the value of the control changes.
    The even will fire when:
    - The window is created (if the value of the control is not an empty string)
    - The value of the control is changed by the user
    - The value of the control is changed programmatically (if the value of the control is changed within a handler, that *same* handler will not be called again for that change.)
    - A measurement unit change will only trigger the event if the underlying measurement value has changed.

    @ self (FCXCtrlMeasurementEdit)
    @ callback (function) See `HandleChange` for callback signature.
    ]]

    --[[
    % RemoveHandleChange

    **[Fluid] [Override]**
    Removes a handler added with `AddHandleChange`.

    @ self (FCXCtrlMeasurementEdit)
    @ callback (function)
    ]]
    props.AddHandleChange, props.RemoveHandleChange, trigger_change, each_last_change = mixin_helper.create_custom_control_change_event(
        {
            name = "last_value",
            get = function(ctrl)
                return mixin.FCXCtrlMeasurementEdit["Get" .. private[ctrl].Type](ctrl)
            end,
            initial = 0,
        }
    )

    return props

end

__imports["mixin.FCXCtrlMeasurementUnitPopup"] = __imports["mixin.FCXCtrlMeasurementUnitPopup"] or function()
    --  Author: Edward Koltun
    --  Date: April 5, 2022
    --[[
    $module FCXCtrlMeasurementUnitPopup

    *Extends `FCMCtrlPopup`.*

    This mixin defines a popup that can be used to change the window's measurement unit (eg like the one at the bottom of the settings dialog). It is largely internal, and other than setting the position and size, it runs automatically.
    Programmatic changes of measurement unit should be handled at the parent window, not the control.

    The following inherited methods have been disabled:
    - `Clear`
    - `AddString`
    - `AddStrings`
    - `SetStrings`
    - `GetSelectedItem`
    - `SetSelectedItem`
    - `SetSelectedLast`
    - `ItemExists`
    - `InsertString`
    - `DeleteItem`
    - `GetItemText`
    - `SetItemText`
    - `AddHandleSelectionChange`
    - `RemoveHandleSelectionChange`

    Event listeners for changes of measurement should be added to the parent window.
    ]] --
    local mixin = require("library.mixin")
    local mixin_helper = require("library.mixin_helper")
    local measurement = require("library.measurement")

    local props = {MixinParent = "FCMCtrlPopup"}
    local unit_order = {
        finale.MEASUREMENTUNIT_EVPUS, finale.MEASUREMENTUNIT_INCHES, finale.MEASUREMENTUNIT_CENTIMETERS,
        finale.MEASUREMENTUNIT_POINTS, finale.MEASUREMENTUNIT_PICAS, finale.MEASUREMENTUNIT_SPACES,
    }
    local reverse_unit_order = {}

    for k, v in ipairs(unit_order) do
        reverse_unit_order[v] = k
    end

    -- Disabled methods
    mixin_helper.disable_methods(
        props, "Clear", "AddString", "AddStrings", "SetStrings", "GetSelectedItem", "SetSelectedItem", "SetSelectedLast",
        "ItemExists", "InsertString", "DeleteItem", "GetItemText", "SetItemText", "AddHandleSelectionChange",
        "RemoveHandleSelectionChange")

    --[[
    % Init

    **[Internal]**

    @ self (FCXCtrlMeasurementUnitPopup)
    ]]
    function props:Init()
        mixin.assert(
            mixin.is_instance_of(self:GetParent(), "FCXCustomLuaWindow"),
            "FCXCtrlMeasurementUnitPopup must have a parent window that is an instance of FCXCustomLuaWindow")

        for _, v in ipairs(unit_order) do
            mixin.FCMCtrlPopup.AddString(self, measurement.get_unit_name(v))
        end

        self:UpdateMeasurementUnit()

        mixin.FCMCtrlPopup.AddHandleSelectionChange(
            self, function(control)
                control:GetParent():SetMeasurementUnit(unit_order[control:GetSelectedItem_() + 1])
            end)
    end

    --[[
    % UpdateMeasurementUnit

    **[Fluid] [Internal]**
    Checks the parent window's measurement unit and updates the selection if necessary.

    @ self (FCXCtrlMeasurementUnitPopup)
    ]]
    function props:UpdateMeasurementUnit()
        local unit = self:GetParent():GetMeasurementUnit()

        if unit == unit_order[self:GetSelectedItem_() + 1] then
            return
        end

        mixin.FCMCtrlPopup.SetSelectedItem(self, reverse_unit_order[unit] - 1)
    end

    return props

end

__imports["library.page_size"] = __imports["library.page_size"] or function()
    --  Author: Edward Koltun
    --  Date: April 13, 2021
    --[[
    $module Page Size

    A library for determining page sizes.
    ]] --
    local page_size = {}
    local utils = require("library.utils")

    -- Dimensions must be in EVPUs and in portrait (ie width is always the shorter side)
    local sizes = {}

    -- Finale's standard sizes
    sizes.A3 = {width = 3366, height = 4761}
    sizes.A4 = {width = 2381, height = 3368}
    sizes.A5 = {width = 1678, height = 2380}
    sizes.B4 = {width = 2920, height = 4127}
    sizes.B5 = {width = 1994, height = 2834}
    sizes.Concert = {width = 2592, height = 3456}
    sizes.Executive = {width = 2160, height = 2880}
    sizes.Folio = {width = 2448, height = 3744}
    sizes.Hymn = {width = 1656, height = 2376}
    sizes.Legal = {width = 2448, height = 4032}
    sizes.Letter = {width = 2448, height = 3168}
    sizes.Octavo = {width = 1944, height = 3024}
    sizes.Quarto = {width = 2448, height = 3110}
    sizes.Statement = {width = 1584, height = 2448}
    sizes.Tabloid = {width = 3168, height = 4896}

    -- Other sizes

    --[[
    % get_dimensions

    Returns the dimensions of the requested page size. Dimensions are in portrait.

    @ size (string) The page size.
    : (table) Has keys `width` and `height` which contain the dimensions in EVPUs.
    ]]
    function page_size.get_dimensions(size)
        return utils.copy_table(sizes[size])
    end

    --[[
    % is_size

    Checks if the given size is defined.

    @ size (string)
    : (boolean) `true` if defined, `false` if not
    ]]
    function page_size.is_size(size)
        return sizes[size] and true or false
    end

    --[[
    % get_size

    Determines the page size based on the given dimensions.

    @ width (number) Page width in EVPUs.
    @ height (number) Page height in EVPUs.
    : (string|nil) Page size, or `nil` if no match.
    ]]
    function page_size.get_size(width, height)
        -- If landscape, swap to portrait
        if height < width then
            local temp = height
            height = width
            width = temp
        end

        for size, dimensions in pairs(sizes) do
            if dimensions.width == width and dimensions.height == height then
                return size
            end
        end

        return nil
    end

    --[[
    % get_page_size

    Determines the page size of an `FCPage`.

    @ page (FCPage)
    : (string|nil) Page size, or `nil` if no match.
    ]]
    function page_size.get_page_size(page)
        return page_size.get_size(page.Width, page.Height)
    end

    --[[
    % set_page_size

    Sets the dimensions of an `FCPage` to the given size. The existing page orientation will be preserved.

    @ page (FCPage)
    @ size (string)
    ]]
    function page_size.set_page_size(page, size)
        if not sizes[size] then
            return
        end

        if page:IsPortrait() then
            page:SetWidth(sizes[size].width)
            page:SetHeight(sizes[size].height)
        else
            page:SetWidth(sizes[size].height)
            page:SetHeight(sizes[size].width)
        end
    end

    --[[
    % pairs

    Return an alphabetical order iterator that yields the following pairs:
    `(string) size`
    `(table) dimensions` => has keys `width` and `height` which contain the dimensions in EVPUs

    : (function)
    ]]
    local sizes_index
    function page_size.pairs()
        if not sizes_index then
            for size in pairs(sizes) do
                table.insert(sizes_index, size)
            end

            table.sort(sizes_index)
        end

        local i = 0
        local iterator = function()
            i = i + 1
            if sizes_index[i] == nil then
                return nil
            else
                return sizes_index[i], sizes[sizes_index[i]]
            end
        end

        return iterator
    end

    return page_size

end

__imports["mixin.FCXCtrlPageSizePopup"] = __imports["mixin.FCXCtrlPageSizePopup"] or function()
    --  Author: Edward Koltun
    --  Date: April 13, 2021
    --[[
    $module FCXCtrlPageSizePopup

    *Extends `FCMCtrlPopup`*

    A popup for selecting a defined page size. The dimensions in the current unit are displayed along side each page size in the same way as the Page Format dialog.

    Summary of modifications:
    - `SelectionChange` has been overridden to match the specialised functionality.
    - Setting and getting is now only done base on page size.

    The following inherited methods have been disabled:
    - `Clear`
    - `AddString`
    - `AddStrings`
    - `SetStrings`
    - `GetSelectedItem`
    - `SetSelectedItem`
    - `SetSelectedLast`
    - `ItemExists`
    - `InsertString`
    - `DeleteItem`
    - `GetItemText`
    - `SetItemText`
    - `AddHandleSelectionChange`
    - `RemoveHandleSelectionChange`
    ]] --
    local mixin = require("library.mixin")
    local mixin_helper = require("library.mixin_helper")
    local measurement = require("library.measurement")
    local page_size = require("library.page_size")

    local private = setmetatable({}, {__mode = "k"})
    local props = {}

    local trigger_page_size_change
    local each_last_page_size_change

    local temp_str = finale.FCString()

    -- Disabled methods
    mixin_helper.disable_methods(
        props, "Clear", "AddString", "AddStrings", "SetStrings", "GetSelectedItem", "SetSelectedItem", "SetSelectedLast",
        "ItemExists", "InsertString", "DeleteItem", "GetItemText", "SetItemText", "AddHandleSelectionChange",
        "RemoveHandleSelectionChange")

    local function repopulate(control)
        local unit = mixin.is_instance_of(control:GetParent(), "FCXCustomLuaWindow") and
                         control:GetParent():GetMeasurementUnit() or measurement.get_real_default_unit()

        if private[control].LastUnit == unit then
            return
        end

        local suffix = measurement.get_unit_abbreviation(unit)
        local selection = control:GetSelectedItem_()

        -- Use FCMCtrlPopup methods because `GetSelectedString` is needed in `GetSelectedPageSize`
        mixin.FCMCtrlPopup.Clear()

        for size, dimensions in page_size.pairs() do
            local str = size .. " ("
            temp_str:SetMeasurement(dimensions.width, unit)
            str = str .. temp_str.LuaString .. suffix .. " x "
            temp_str:SetMeasurement(dimensions.height, unit)
            str = str .. temp_str.LuaString .. suffix .. ")"

            mixin.FCMCtrlPopup.AddString(str)
        end

        control:SetSelectedItem_(selection)
        private[control].LastUnit = unit
    end

    --[[
    % Init

    **[Internal]**

    @ self (FCXCtrlPageSizePopup)
    ]]
    function props:Init()
        private[self] = private[self] or {}

        repopulate(self)
    end

    --[[
    % GetSelectedPageSize

    Returns the selected page size.

    @ self (FCXCtrlPageSizePopup)
    : (string|nil) The page size or `nil` if nothing is selected.
    ]]
    function props:GetSelectedPageSize()
        local str = mixin.FCMCtrlPopup.GetSelectedString()
        if not str then
            return nil
        end

        return str:match("(.+) %(")
    end

    --[[
    % SetSelectedPageSize

    **[Fluid]**
    Sets the selected page size. Must be a valid page size.

    @ self (FCXCtrlPageSizePopup)
    @ size (FCString|string)
    ]]
    function props:SetSelectedPageSize(size)
        mixin.assert_argument(size, {"string", "FCString"}, 2)
        size = type(size) == "userdata" and size.LuaString or tostring(size)
        mixin.assert(page_size.is_size(size), "'" .. size .. "' is not a valid page size.")

        local index = 0
        for s in page_size.pairs() do
            if size == s then
                if index ~= self:_GetSelectedItem() then
                    mixin.FCMCtrlPopup.SetSelectedItem(index)
                    trigger_page_size_change(self)
                end

                return
            end

            index = index + 1
        end
    end

    --[[
    % UpdateMeasurementUnit

    **[Fluid] [Internal]**
    Checks the parent window's measurement and updates the displayed page dimensions if necessary.

    @ self (FCXCtrlPageSizePopup)
    ]]
    function props:UpdateMeasurementUnit()
        repopulate(self)
    end

    --[[
    % HandlePageSizeChange

    **[Callback Template]**

    @ control (FCXCtrlPageSizePopup)
    @ last_page_size (string) The last page size that was selected. If no page size was previously selected, will be `false`.
    ]]

    --[[
    % AddHandlePageSizeChange

    **[Fluid]**
    Adds a handler for PageSizeChange events.
    If the selected item is changed by a handler, that same handler will not be called again for that change.

    The event will fire in the following cases:
    - When the window is created (if an item is selected)
    - Change in selected item by user or programatically (inserting an item before or after will not trigger the event)

    @ self (FCXCtrlPageSizePopup)
    @ callback (function) See `HandlePageSizeChange` for callback signature.
    ]]

    --[[
    % RemoveHandlePageSizeChange

    **[Fluid]**
    Removes a handler added with `AddHandlePageSizeChange`.

    @ self (FCXCtrlPageSizePopup)
    @ callback (function) Handler to remove.
    ]]
    props.AddHandlePageSizeChange, props.RemoveHandlePageSizeChange, trigger_page_size_change, each_last_page_size_change =
        mixin_helper.create_custom_control_change_event(
            {
                name = "last_page_size",
                get = function(ctrl)
                    return mixin.FCXCtrlPageSizePopup.GetSelectedPageSize(ctrl)
                end,
                initial = false,
            })

    return props

end

__imports["mixin.FCXCtrlStatic"] = __imports["mixin.FCXCtrlStatic"] or function()
    --  Author: Edward Koltun
    --  Date: April 15, 2022
    --[[
    $module FCXCtrlStatic

    *Extends `FCMCtrlStatic`*

    Summary of changes:
    - Parent window must be `FCXCustomLuaWindow`
    - Added methods for setting and displaying measurements
    ]] --
    local mixin = require("library.mixin")
    local measurement = require("library.measurement")
    local utils = require("library.utils")

    local private = setmetatable({}, {__mode = "k"})
    local props = {MixinParent = "FCMCtrlStatic"}

    local temp_str = finale.FCString()

    local function get_suffix(unit, suffix_type)
        if suffix_type == 1 then
            return measurement.get_unit_suffix(unit)
        elseif suffix_type == 2 then
            return measurement.get_unit_abbreviation(unit)
        elseif suffix_type == 3 then
            return " " .. string.lower(measurement.get_unit_name(unit))
        end
    end

    --[[
    % Init

    **[Internal]**

    @ self (FCXCtrlStatic)
    ]]
    function props:Init()
        mixin.assert(mixin.is_instance_of(self:GetParent(), "FCXCustomLuaWindow"), "FCXCtrlStatic must have a parent window that is an instance of FCXCustomLuaWindow")

        private[self] = private[self] or {
            ShowMeasurementSuffix = true,
            MeasurementSuffixType = 2,
        }
    end

    --[[
    % SetText

    **[Fluid] [Override]**
    Switches the control's measurement status off.

    @ self (FCXCtrlStatic)
    @ str (FCString|string|number)
    ]]
    function props:SetText(str)
        mixin.assert_argument(str, {"string", "number", "FCString"}, 2)

        mixin.FCMCtrlStatic.SetText(self, str)

        private[self].Measurement = nil
        private[self].MeasurementType = nil
    end

    --[[
    % SetMeasurement

    **[Fluid]**
    Sets a measurement in EVPUs which will be displayed in the parent window's current measurement unit. This will be automatically updated if the parent window's measurement unit changes.

    @ self (FCXCtrlStatic)
    @ value (number) Value in EVPUs
    ]]
    function props:SetMeasurement(value)
        mixin.assert_argument(value, "number", 2)

        local unit = self:GetParent():GetMeasurementUnit()
        temp_str:SetMeasurement(value, unit)
        temp_str:AppendLuaString(private[self].ShowMeasurementSuffix and get_suffix(unit, private[self].MeasurementSuffixType) or "")

        mixin.FCMCtrlStatic.SetText(self, temp_str)

        private[self].Measurement = value
        private[self].MeasurementType = "Measurement"
    end

    --[[
    % SetMeasurementInteger

    **[Fluid]**
    Sets a measurement in whole EVPUs which will be displayed in the parent window's current measurement unit. This will be automatically updated if the parent window's measurement unit changes.

    @ self (FCXCtrlStatic)
    @ value (number) Value in whole EVPUs (fractional part will be rounded to nearest integer)
    ]]
    function props:SetMeasurementInteger(value)
        mixin.assert_argument(value, "number", 2)

        value = utils.round(value)
        local unit = self:GetParent():GetMeasurementUnit()
        temp_str:SetMeasurement(value, unit)
        temp_str:AppendLuaString(private[self].ShowMeasurementSuffix and get_suffix(unit, private[self].MeasurementSuffixType) or "")

        mixin.FCMCtrlStatic.SetText(self, temp_str)

        private[self].Measurement = value
        private[self].MeasurementType = "MeasurementInteger"
    end

    --[[
    % SetMeasurementEfix

    **[Fluid]**
    Sets a measurement in EFIXes which will be displayed in the parent window's current measurement unit. This will be automatically updated if the parent window's measurement unit changes.

    @ self (FCXCtrlStatic)
    @ value (number) Value in EFIXes
    ]]
    function props:SetMeasurementEfix(value)
        mixin.assert_argument(value, "number", 2)

        local evpu = value / 64
        local unit = self:GetParent():GetMeasurementUnit()
        temp_str:SetMeasurement(evpu, unit)
        temp_str:AppendLuaString(private[self].ShowMeasurementSuffix and get_suffix(unit, private[self].MeasurementSuffixType) or "")

        mixin.FCMCtrlStatic.SetText(self, temp_str)

        private[self].Measurement = value
        private[self].MeasurementType = "MeasurementEfix"
    end

    --[[
    % SetShowMeasurementSuffix

    **[Fluid]**
    Sets whether to show a suffix at the end of a measurement (eg `cm` in `2.54cm`). This is on by default.

    @ self (FCXCtrlStatic)
    @ enabled (boolean)
    ]]
    function props:SetShowMeasurementSuffix(enabled)
        mixin.assert_argument(enabled, "boolean", 2)

        private[self].ShowMeasurementSuffix = enabled and true or false
        mixin.FCXCtrlStatic.UpdateMeasurementUnit(self)
    end

    --[[
    % SetMeasurementSuffixShort

    **[Fluid]**
    Sets the measurement suffix to the short style used by Finale's internals (eg `e`, `i`, `c`, etc)

    @ self (FCXCtrlStatic)
    ]]
    function props:SetMeasurementSuffixShort()
        private[self].MeasurementSuffixType = 1
        mixin.FCXCtrlStatic.UpdateMeasurementUnit(self)
    end

    --[[
    % SetMeasurementSuffixAbbreviated

    **[Fluid]**
    Sets the measurement suffix to commonly known abbrevations (eg `in`, `cm`, `pt`, etc).
    This is the default style.

    @ self (FCXCtrlStatic)
    ]]
    function props:SetMeasurementSuffixAbbreviated()
        private[self].MeasurementSuffixType = 2
        mixin.FCXCtrlStatic.UpdateMeasurementUnit(self)
    end

    --[[
    % SetMeasurementSuffixFull

    **[Fluid]**
    Sets the measurement suffix to the full unit name. (eg `inches`, `centimeters`, etc).

    @ self (FCXCtrlStatic)
    ]]
    function props:SetMeasurementSuffixFull()
        private[self].MeasurementSuffixType = 3
        mixin.FCXCtrlStatic.UpdateMeasurementUnit(self)
    end

    --[[
    % UpdateMeasurementUnit

    **[Fluid] [Internal]**
    Updates the displayed measurement unit in line with the parent window.

    @ self (FCXCtrlStatic)
    ]]
    function props:UpdateMeasurementUnit()
        if private[self].Measurement then
            mixin.FCXCtrlStatic["Set" .. private[self].MeasurementType](self, private[self].Measurement)
        end
    end

    return props

end

__imports["mixin.FCXCtrlUpDown"] = __imports["mixin.FCXCtrlUpDown"] or function()
    --  Author: Edward Koltun
    --  Date: April 10, 2022
    --[[
    $module FCXCtrlUpDown

    *Extends `FCMCtrlUpDown`*
    An up down control that is created by `FCXCustomLuaWindow`.

    Summary of modifications:
    - The ability to set the step size on a per-measurement unit basis.
    - Step size for integers can also be changed.
    - Added a setting for forcing alignment to the next step when moving up or down.
    - Connected edit must be an instance of `FCXCtrlEdit`
    - Measurement edits can be connected in two additional ways which affect the underlying methods used in `GetValue` and `SetValue`
    - Measurement EFIX edits have a different set of default step sizes.
    ]] --
    local mixin = require("library.mixin")
    local mixin_helper = require("library.mixin_helper")

    local private = setmetatable({}, {__mode = "k"})
    local props = {MixinParent = "FCMCtrlUpDown"}

    local temp_str = finale.FCString()

    -- Enumerates the edit type
    local function enum_edit_type(edit, edit_type)
        if edit_type == "Integer" then
            return 1
        else
            if edit:IsTypeMeasurement() then
                return 2
            elseif edit:IsTypeMeasurementInteger() then
                return 3
            elseif edit:IsTypeMeasurementEfix() then
                return 4
            end
        end
    end

    local default_measurement_steps = {
        [finale.MEASUREMENTUNIT_EVPUS] = {value = 1, is_evpus = true},
        [finale.MEASUREMENTUNIT_INCHES] = {value = 0.03125, is_evpus = false},
        [finale.MEASUREMENTUNIT_CENTIMETERS] = {value = 0.01, is_evpus = false},
        [finale.MEASUREMENTUNIT_POINTS] = {value = 0.25, is_evpus = false},
        [finale.MEASUREMENTUNIT_PICAS] = {value = 1, is_evpus = true},
        [finale.MEASUREMENTUNIT_SPACES] = {value = 0.125, is_evpus = false},
    }

    local default_efix_steps = {
        [finale.MEASUREMENTUNIT_EVPUS] = {value = 0.015625, is_evpus = true},
        [finale.MEASUREMENTUNIT_INCHES] = {value = 0.03125, is_evpus = false},
        [finale.MEASUREMENTUNIT_CENTIMETERS] = {value = 0.001, is_evpus = false},
        [finale.MEASUREMENTUNIT_POINTS] = {value = 0.03125, is_evpus = false},
        [finale.MEASUREMENTUNIT_PICAS] = {value = 0.015625, is_evpus = true},
        [finale.MEASUREMENTUNIT_SPACES] = {value = 0.03125, is_evpus = false},
    }

    --[[
    % Init

    **[Internal]**

    @ self (FCXCtrlUpDown)
    ]]
    function props:Init()
        mixin.assert(
            mixin.is_instance_of(self:GetParent(), "FCXCustomLuaWindow"),
            "FCXCtrlUpDown must have a parent window that is an instance of FCXCustomLuaWindow")
        private[self] = private[self] or {IntegerStepSize = 1, MeasurementSteps = {}, AlignWhenMoving = true}

        self:AddHandlePress(
            function(self, delta)
                if not private[self].ConnectedEdit then
                    return
                end

                local edit = private[self].ConnectedEdit
                local edit_type = enum_edit_type(edit, private[self].ConnectedEditType)
                local unit = self:GetParent():GetMeasurementUnit()
                local separator = mixin.UI():GetDecimalSeparator()
                local step_def

                if edit_type == 1 then
                    step_def = {value = private[self].IntegerStepSize}
                else
                    step_def = private[self].MeasurementSteps[unit] or (edit_type == 4 and default_efix_steps[unit]) or
                                   default_measurement_steps[unit]
                end

                -- Get real value
                local value
                if edit_type == 1 then
                    value = edit:GetText():match("^%-*[0-9%.%,%" .. separator .. "-]+")
                    value = value and tonumber(value) or 0
                else
                    if step_def.is_evpus then
                        value = edit:GetMeasurement()
                    else
                        -- Strings like '2.75i' allow the unit to be overridden, so doing this extra step guarantees that it's normalised to the current unit
                        temp_str:SetMeasurement(edit:GetMeasurement(), unit)
                        value = temp_str.LuaString:gsub("%" .. separator, ".")
                        value = tonumber(value)
                    end
                end

                -- Align to closest step if needed
                if private[self].AlignWhenMoving then
                    -- Casting back and forth works around floating point issues, such as 0.3/0.1 not being equal to 3 (even though 3 is displayed)
                    local num_steps = tonumber(tostring(value / step_def.value))

                    if num_steps ~= math.floor(num_steps) then
                        if delta > 0 then
                            value = math.ceil(num_steps) * step_def.value
                            delta = delta - 1
                        elseif delta < 0 then
                            value = math.floor(num_steps) * step_def.value
                            delta = delta + 1
                        end
                    end
                end

                -- Calculate new value
                local new_value = value + delta * step_def.value

                -- Set new value
                if edit_type == 1 then
                    self:SetValue(new_value)
                else
                    if step_def.is_evpus then
                        self:SetValue(edit_type == 4 and new_value * 64 or new_value)
                    else
                        -- If we're not in EVPUs, we need the EVPU value to determine whether clamping is required
                        temp_str.LuaString = tostring(new_value)
                        local new_evpus = temp_str:GetMeasurement(unit)
                        if new_evpus < private[self].Minimum or new_evpus > private[self].Maximum then
                            self:SetValue(edit_type == 4 and new_evpus * 64 or new_evpus)
                        else
                            edit:SetText(temp_str.LuaString:gsub("%.", separator))
                        end
                    end
                end

            end)
    end

    --[[
    % GetConnectedEdit

    **[Override]**
    Ensures that original edit control is returned.

    @ self (FCXCtrlUpDown)
    : (FCXCtrlEdit|nil) `nil` if there is no edit connected.
    ]]
    function props:GetConnectedEdit()
        return private[self].ConnectedEdit
    end

    --[[
    % ConnectIntegerEdit

    **[Fluid] [Override]**
    Connects an integer edit.
    The underlying methods used in `GetValue` and `SetValue` will be `GetRangeInteger` and `SetInteger` respectively.

    @ self (FCXCtrlUpDown)
    @ control (FCMCtrlEdit)
    @ minimum (number)
    @ maximum (maximum)
    ]]
    function props:ConnectIntegerEdit(control, minimum, maximum)
        mixin.assert_argument(control, "FCMCtrlEdit", 2)
        mixin.assert_argument(minimum, "number", 3)
        mixin.assert_argument(maximum, "number", 4)
        mixin.assert(
            not mixin.is_instance_of(control, "FCXCtrlMeasurementEdit"),
            "A measurement edit cannot be connected as an integer edit.")

        private[self].ConnectedEdit = control
        private[self].ConnectedEditType = "Integer"
        private[self].Minimum = minimum
        private[self].Maximum = maximum
    end

    --[[
    % ConnectMeasurementEdit

    **[Fluid] [Override]**
    Connects a measurement edit. The control will be automatically registered as a measurement edit if it isn't already.
    The underlying methods used in `GetValue` and `SetValue` will depend on the measurement edit's type.

    @ self (FCXCtrlUpDown)
    @ control (FCXCtrlMeasurementEdit)
    @ minimum (number)
    @ maximum (maximum)
    ]]
    function props:ConnectMeasurementEdit(control, minimum, maximum)
        mixin.assert_argument(control, "FCXCtrlMeasurementEdit", 2)
        mixin.assert_argument(minimum, "number", 3)
        mixin.assert_argument(maximum, "number", 4)

        private[self].ConnectedEdit = control
        private[self].ConnectedEditType = "Measurement"
        private[self].Minimum = minimum
        private[self].Maximum = maximum
    end

    --[[
    % SetIntegerStepSize

    **[Fluid]**
    Sets the step size for integer edits.

    @ self (FCXCtrlUpDown)
    @ value (number)
    ]]
    function props:SetIntegerStepSize(value)
        mixin.assert_argument(value, "number", 2)

        private[self].IntegerStepSize = value
    end

    --[[
    % SetEVPUsStepSize

    **[Fluid]**
    Sets the step size for measurement edits that are currently displaying in EVPUs.

    @ self (FCXCtrlUpDown)
    @ value (number)
    ]]
    function props:SetEVPUsStepSize(value)
        mixin.assert_argument(value, "number", 2)

        private[self].MeasurementSteps[finale.MEASUREMENTUNIT_EVPUS] = {value = value, is_evpus = true}
    end

    --[[
    % SetInchesStepSize

    **[Fluid]**
    Sets the step size for measurement edits that are currently displaying in Inches.

    @ self (FCXCtrlUpDown)
    @ value (number)
    @ [is_evpus] (boolean) If `true`, the value will be treated as an EVPU value. If `false` or omitted, the value will be treated in Inches.
    ]]
    function props:SetInchesStepSize(value, is_evpus)
        mixin.assert_argument(value, "number", 2)
        mixin.assert_argument(is_evpus, {"boolean", "nil"}, 3)

        private[self].MeasurementSteps[finale.MEASUREMENTUNIT_INCHES] = {
            value = value,
            is_evpus = is_evpus and true or false,
        }
    end

    --[[
    % SetCentimetersStepSize

    **[Fluid]**
    Sets the step size for measurement edits that are currently displaying in Centimeters.

    @ self (FCXCtrlUpDown)
    @ value (number)
    @ [is_evpus] (boolean) If `true`, the value will be treated as an EVPU value. If `false` or omitted, the value will be treated in Centimeters.
    ]]
    function props:SetCentimetersStepSize(value, is_evpus)
        mixin.assert_argument(value, "number", 2)
        mixin.assert_argument(is_evpus, {"boolean", "nil"}, 3)

        private[self].MeasurementSteps[finale.MEASUREMENTUNIT_CENTIMETERS] = {
            value = value,
            is_evpus = is_evpus and true or false,
        }
    end

    --[[
    % SetPointsStepSize

    **[Fluid]**
    Sets the step size for measurement edits that are currently displaying in Points.

    @ self (FCXCtrlUpDown)
    @ value (number)
    @ [is_evpus] (boolean) If `true`, the value will be treated as an EVPU value. If `false` or omitted, the value will be treated in Points.
    ]]
    function props:SetPointsStepSize(value, is_evpus)
        mixin.assert_argument(value, "number", 2)
        mixin.assert_argument(is_evpus, {"boolean", "nil"}, 3)

        private[self].MeasurementSteps[finale.MEASUREMENTUNIT_POINTS] = {
            value = value,
            is_evpus = is_evpus and true or false,
        }
    end

    --[[
    % SetPicasStepSize

    **[Fluid]**
    Sets the step size for measurement edits that are currently displaying in Picas.

    @ self (FCXCtrlUpDown)
    @ value (number|string)
    @ [is_evpus] (boolean) If `true`, the value will be treated as an EVPU value. If `false` or omitted, the value will be treated in Picas.
    ]]
    function props:SetPicasStepSize(value, is_evpus)
        mixin.assert_argument(value, {"number", "string"}, 2)

        if not is_evpus then
            temp_str:SetText(tostring(value))
            value = temp_str:GetMeasurement(finale.MEASUREMENTUNIT_PICAS)
        end

        private[self].MeasurementSteps[finale.MEASUREMENTUNIT_PICAS] = {value = value, is_evpus = true}
    end

    --[[
    % SetSpacesStepSize

    **[Fluid]**
    Sets the step size for measurement edits that are currently displaying in Spaces.

    @ self (FCXCtrlUpDown)
    @ value (number)
    @ [is_evpus] (boolean) If `true`, the value will be treated as an EVPU value. If `false` or omitted, the value will be treated in Spaces.
    ]]
    function props:SetSpacesStepSize(value, is_evpus)
        mixin.assert_argument(value, "number", 2)
        mixin.assert_argument(is_evpus, {"boolean", "nil"}, 3)

        private[self].MeasurementSteps[finale.MEASUREMENTUNIT_SPACES] = {
            value = value,
            is_evpus = is_evpus and true or false,
        }
    end

    --[[
    % AlignWSetAlignWhenMovinghenMoving

    **[Fluid]**
    Sets whether to align to the next multiple of a step when moving.

    @ self (FCXCtrlUpDown)
    @ on (boolean)
    ]]
    function props:SetAlignWhenMoving(on)
        mixin.assert_argument(on, "boolean", 2)

        private[self].AlignWhenMoving = on
    end

    --[[
    % GetValue

    **[Override]**
    Returns the value of the connected edit, clamped according to the set minimum and maximum.

    Different types of connected edits will return different types and use different methods to access the value of the edit. The methods are:
    - Integer edit => `GetRangeInteger`
    - Measurement edit ("Measurement") => `GetRangeMeasurement`
    - Measurement edit ("MeasurementInteger") => `GetRangeMeasurementInteger`
    - Measurement edit ("MeasurementEfix") => `GetRangeMeasurementEfix`

    @ self (FCXCtrlUpDown)
    : (number) An integer for an integer edit, EVPUs for a measurement edit, whole EVPUs for a measurement integer edit, or EFIXes for a measurement EFIX edit.
    ]]
    function props:GetValue()
        if not private[self].ConnectedEdit then
            return
        end

        local edit = private[self].ConnectedEdit

        if private[self].ConnectedEditType == "Measurement" then
            return edit["Get" .. edit:GetType()](edit, private[self].Minimum, private[self].Maximum)
        else
            return edit:GetRangeInteger(private[self].Minimum, private[self].Maximum)
        end
    end

    --[[
    % SetValue

    **[Fluid] [Override]**
    Sets the value of the attached control, clamped according to the set minimum and maximum.

    Different types of connected edits will accept different types and use different methods to set the value of the edit. The methods are:
    - Integer edit => `SetRangeInteger`
    - Measurement edit ("Measurement") => `SetRangeMeasurement`
    - Measurement edit ("MeasurementInteger") => `SetRangeMeasurementInteger`
    - Measurement edit ("MeasurementEfix") => `SetRangeMeasurementEfix`

    @ self (FCXCtrlUpDown)
    @ value (number) An integer for an integer edit, EVPUs for a measurement edit, whole EVPUs for a measurement integer edit, or EFIXes for a measurement EFIX edit.
    ]]
    function props:SetValue(value)
        mixin.assert_argument(value, "number", 2)
        mixin.assert(private[self].ConnectedEdit, "Unable to set value: no connected edit.")

        -- Clamp the value
        value = value < private[self].Minimum and private[self].Minimum or value
        value = value > private[self].Maximum and private[self].Maximum or value

        local edit = private[self].ConnectedEdit

        if private[self].ConnectedEditType == "Measurement" then
            edit["Set" .. edit:GetType()](edit, value)
        else
            edit:SetInteger(value)
        end
    end

    --[[
    % GetMinimum

    **[Override]**

    @ self (FCMCtrlUpDown)
    : (number) An integer for integer edits or EVPUs for measurement edits.
    ]]
    function props:GetMinimum()
        return private[self].Minimum
    end

    --[[
    % GetMaximum

    **[Override]**

    @ self (FCMCtrlUpDown)
    : (number) An integer for integer edits or EVPUs for measurement edits.
    ]]

    function props:GetMaximum()
        return private[self].Maximum
    end

    --[[
    % SetRange

    **[Fluid] [Override]**

    @ self (FCMCtrlUpDown)
    @ minimum (number) An integer for integer edits or EVPUs for measurement edits.
    @ maximum (number) An integer for integer edits or EVPUs for measurement edits.
    ]]
    function props:SetRange(minimum, maximum)
        mixin.assert_argument(minimum, "number", 2)
        mixin.assert_argument(maximum, "number", 3)

        private[self].Minimum = minimum
        private[self].Maximum = maximum
    end

    return props

end

__imports["library.utils"] = __imports["library.utils"] or function()
    --[[
    $module Utility Functions

    A library of general Lua utility functions.
    ]] --
    local utils = {}

    --[[
    % copy_table

    If a table is passed, returns a copy, otherwise returns the passed value.

    @ t (mixed)
    : (mixed)
    ]]
    function utils.copy_table(t)
        if type(t) == "table" then
            local new = {}
            for k, v in pairs(t) do
                new[utils.copy_table(k)] = utils.copy_table(v)
            end
            setmetatable(new, utils.copy_table(getmetatable(t)))
            return new
        else
            return t
        end
    end

    --[[
    % table_remove_first

    Removes the first occurrence of a value from an array table.

    @ t (table)
    @ value (mixed)
    ]]
    function utils.table_remove_first(t, value)
        for k = 1, #t do
            if t[k] == value then
                table.remove(t, k)
                return
            end
        end
    end

    --[[
    % iterate_keys

    Returns an unordered iterator for the keys in a table.

    @ t (table)
    : (function)
    ]]
    function utils.iterate_keys(t)
        local a, b, c = pairs(t)

        return function()
            c = a(b, c)
            return c
        end
    end

    --[[
    % round

    Rounds a number to the nearest whole integer.

    @ num (number)
    : (number)
    ]]
    function utils.round(num)
        return math.floor(num + 0.5)
    end

    --[[ 
    % calc_roman_numeral

    Calculates the roman numeral for the input number. Adapted from https://exercism.org/tracks/lua/exercises/roman-numerals/solutions/Nia11 on 2022-08-13

    @ num (number)
    : (string)
    ]]
    function utils.calc_roman_numeral(num)
        local thousands = {'M','MM','MMM'}
        local hundreds = {'C','CC','CCC','CD','D','DC','DCC','DCCC','CM'}
        local tens = {'X','XX','XXX','XL','L','LX','LXX','LXXX','XC'}	
        local ones = {'I','II','III','IV','V','VI','VII','VIII','IX'}
        local roman_numeral = ''
        if math.floor(num/1000)>0 then roman_numeral = roman_numeral..thousands[math.floor(num/1000)] end
        if math.floor((num%1000)/100)>0 then roman_numeral=roman_numeral..hundreds[math.floor((num%1000)/100)] end
        if math.floor((num%100)/10)>0 then roman_numeral=roman_numeral..tens[math.floor((num%100)/10)] end
        if num%10>0 then roman_numeral = roman_numeral..ones[num%10] end
        return roman_numeral
    end

    --[[ 
    % calc_ordinal

    Calculates the ordinal for the input number (e.g. 1st, 2nd, 3rd).

    @ num (number)
    : (string)
    ]]
    function utils.calc_ordinal(num)
        local units = num % 10
        local tens = num % 100
        if units == 1 and tens ~= 11 then
            return num .. "st"
        elseif units == 2 and tens ~= 12 then
            return num .. "nd"
        elseif units == 3 and tens ~= 13 then
            return num .. "rd"
        end

        return num .. "th"
    end

    --[[ 
    % calc_alphabet

    This returns one of the ways that Finale handles numbering things alphabetically, such as rehearsal marks or measure numbers.

    This function was written to emulate the way Finale numbers saves when Autonumber is set to A, B, C... When the end of the alphabet is reached it goes to A1, B1, C1, then presumably to A2, B2, C2. 

    @ num (number)
    : (string)
    ]]
    function utils.calc_alphabet(num)
        local letter = ((num - 1) % 26) + 1
        local n = math.floor((num - 1) / 26)

        return string.char(64 + letter) .. (n > 0 and n or "")
    end

    --[[
    % clamp

    Clamps a number between two values.

    @ num (number) The number to clamp.
    @ minimum (number) The minimum value.
    @ maximum (number) The maximum value.
    : (number)
    ]]
    function utils.clamp(num, minimum, maximum)
        return math.min(math.max(num, minimum), maximum)
    end

    return utils

end

__imports["library.mixin_helper"] = __imports["library.mixin_helper"] or function()
    --  Author: Edward Koltun
    --  Date: April 3, 2022
    --[[
    $module Mixin Helper

    A library of helper functions to improve code reuse in mixins.
    ]] local utils = require("library.utils")
    local mixin = require("library.mixin")

    local mixin_helper = {}

    local disabled_method = function()
        error("Attempt to call disabled method 'tryfunczzz'", 2)
    end

    --[[
    % disable_methods

    Disables mixin methods by setting an empty function that throws an error.

    @ props (table) The mixin's props table.
    @ ... (string) The names of the methods to replace
    ]]
    function mixin_helper.disable_methods(props, ...)
        for i = 1, select("#", ...) do
            props[select(i, ...)] = disabled_method
        end
    end

    --[[
    % create_standard_control_event

    A helper function for creating a standard control event. standard refers to the `Handle*` methods from `FCCustomLuaWindow` (not including `HandleControlEvent`).
    For example usage, refer to the source for the `FCMControl` mixin.

    @ name (string) The full event name (eg. `HandleCommand`, `HandleUpDownPressed`, etc)
    : (function) Returns two functions: a function for adding handlers and a function for removing handlers.
    ]]
    function mixin_helper.create_standard_control_event(name)
        local callbacks = setmetatable({}, {__mode = "k"})
        local windows = setmetatable({}, {__mode = "k"})

        local dispatcher = function(control, ...)
            if not callbacks[control] then
                return
            end

            for _, cb in ipairs(callbacks[control]) do
                cb(control, ...)
            end
        end

        local function init_window(window)
            if windows[window] then
                return
            end

            window["Add" .. name](window, dispatcher)

            windows[window] = true
        end

        local function add_func(control, callback)
            mixin.assert_argument(callback, "function", 3)
            local window = control:GetParent()
            mixin.assert(window, "Cannot add handler to control with no parent window.")
            mixin.assert(
                (window.MixinBase or window.MixinClass) == "FCMCustomLuaWindow",
                "Handlers can only be added if parent window is an instance of FCMCustomLuaWindow")

            init_window(window)
            callbacks[control] = callbacks[control] or {}
            table.insert(callbacks[control], callback)
        end

        local function remove_func(control, callback)
            mixin.assert_argument(callback, "function", 3)

            utils.table_remove_first(callbacks[control], callback)
        end

        return add_func, remove_func
    end

    -- Helper for create_custom_control_event
    local function unpack_arguments(values, ...)
        local args = {}
        for i = 1, select("#", ...) do
            table.insert(args, values[select(i, ...).name])
        end

        return table.unpack(args)
    end

    local function get_event_value(target, func)
        if type(func) == "string" then
            return target[func](target)
        else
            return func(target)
        end
    end

    local function create_change_event(...)
        local callbacks = setmetatable({}, {__mode = "k"})
        local params = {...} -- Store varargs in table so that it's accessible by inner functions

        local event = {}
        function event.dispatcher(target)
            if not callbacks[target] then
                return
            end

            -- Get current values for event handler parameters
            local current = {}
            for _, p in ipairs(params) do
                current[p.name] = get_event_value(target, p.get)
            end

            for _, cb in ipairs(callbacks[target].order) do
                -- If any of the last values are not equal to the current ones, call the handler
                local called = false
                for k, v in pairs(current) do
                    if current[k] ~= callbacks[target].history[cb][k] then
                        cb(target, unpack_arguments(callbacks[target].history[cb], table.unpack(params)))
                        called = true
                        goto continue
                    end
                end
                ::continue::

                -- Update current values in case they have changed
                for _, p in ipairs(params) do
                    current[p.name] = get_event_value(target, p.get)
                end

                -- Update the stored last value
                -- Doing this after the values are updated prevents the same handler being triggered for any changes within the handler, which also reduces the possibility of infinite handler loops
                if called then
                    callbacks[target].history[cb] = utils.copy_table(current)
                end
            end
        end

        function event.add(target, callback, initial)
            callbacks[target] = callbacks[target] or {order = {}, history = {}}

            local history = {}
            for _, p in ipairs(params) do
                if initial then
                    if type(p.initial) == "function" then
                        history[p.name] = p.initial(target)
                    else
                        history[p.name] = p.initial
                    end
                else
                    history[p.name] = get_event_value(target, p.get)
                end
            end

            callbacks[target].history[callback] = history
            table.insert(callbacks[target].order, callback)
        end

        function event.remove(target, callback)
            if not callbacks[target] then
                return
            end

            callbacks[target].history[callback] = nil
            table.insert(callbacks[target].order, callback)
        end

        function event.callback_exists(target, callback)
            return callbacks[target] and callbacks[target].history[callback] and true or false
        end

        function event.has_callbacks(target)
            return callbacks[target] and #callbacks[target].order > 0 or false
        end

        -- Function for iterating over history
        function event.history_iterator(control)
            local cb = callbacks[control]
            if not cb or #cb.order == 0 then
                return function()
                    return nil
                end
            end

            local i = 0
            local iterator = function()
                i = i + 1

                if not cb.order[i] then
                    return nil
                end

                return cb.history[cb.order[i]]
            end

            return iterator
        end

        function event.target_iterator()
            return utils.iterate_keys(callbacks)
        end

        return event
    end

    --[[
    % create_custom_control_change_event

    Helper function for creating a custom event for a control.
    Custom events are bootstrapped to InitWindow and HandleCommand, in addition be being able to be triggered manually.
    For example usage, refer to the source for the `FCMCtrlPopup` mixin.

    Parameters:
    This function accepts as multiple arguments, a table for each parameter that will be passed to event handlers. Each table should have the following properties:
    - `name`: The name of the parameter.
    - `get`: The function or the string name of a control method to get the current value of the parameter. It should accept one argument which is the control itself. (eg `mixin.FCMControl.GetText` or `"GetSelectedItem_"`)
    - `initial`: The initial value of the parameter (ie before the window has been created)

    This function returns 4 values which are all functions:
    1. Public method for adding a handler.
    2. Public method for removing a handler.
    3. Private static function for triggering the event on a control. Accepts one argument which is the control.
    4. Private static function for iterating over the sets of last values to enable modification if needed. Each iteration returns a table with event handler paramater names and values.

    @ ... (table)
    ]]
    function mixin_helper.create_custom_control_change_event(...)
        local event = create_change_event(...)
        local windows = setmetatable({}, {__mode = "k"})
        local queued = setmetatable({}, {__mode = "k"})

        local function init_window(window)
            if windows[window] then
                return
            end

            window:AddInitWindow(
                function()
                    -- This will go through the controls in random order but unless it becomes an issue, it's not worth doing anything about
                    for control in event.target_iterator() do
                        event.dispatcher(control)
                    end
                end)

            window:AddHandleCommand(event.dispatcher)
        end

        local function add_func(self, callback)
            mixin.assert_argument(callback, "function", 2)
            local window = self:GetParent()
            mixin.assert(window, "Cannot add handler to self with no parent window.")
            mixin.assert(
                (window.MixinBase or window.MixinClass) == "FCMCustomLuaWindow",
                "Handlers can only be added if parent window is an instance of FCMCustomLuaWindow")
            mixin.force_assert(
                not event.callback_exists(self, callback), "The callback has already been added as a handler.")

            init_window(window)
            event.add(self, callback, not window:WindowExists_())
        end

        local function remove_func(self, callback)
            mixin.assert_argument(callback, "function", 2)

            event.remove(self, callback)
        end

        local function trigger_helper(control)
            if not event.has_callbacks(control) or queued[control] then
                return
            end

            local window = control:GetParent()

            if window:WindowExists_() then
                window:QueueHandleCustom(
                    function()
                        queued[control] = nil
                        event.dispatcher(control)
                    end)

                queued[control] = true
            end
        end

        -- Function for triggering the custom event on a control
        -- If control is boolean true, then will trigger dispatcher for all controls.
        -- If immediate is true, will trigger dispatchers immediately. This can have unintended consequences, so use with caution.
        local function trigger_func(control, immediate)
            if type(control) == "boolean" and control then
                for ctrl in event.target_iterator() do
                    if immediate then
                        event.dispatcher(ctrl)
                    else
                        trigger_helper(ctrl)
                    end
                end
            else
                if immediate then
                    event.dispatcher(control)
                else
                    trigger_helper(control)
                end
            end
        end

        return add_func, remove_func, trigger_func, event.history_iterator
    end

    --[[
    % create_custom_window_change_event

    Creates a custom change event for a window class. For details, see the documentation for `create_custom_control_change_event`, which works in exactly the same way as this function except for controls.

    @ ... (table)
    ]]
    function mixin_helper.create_custom_window_change_event(...)
        local event = create_change_event(...)
        local queued = setmetatable({}, {__mode = "k"})

        local function add_func(self, callback)
            mixin.assert_argument(self, "FCMCustomLuaWindow", 1)
            mixin.assert_argument(callback, "function", 2)
            mixin.force_assert(
                not event.callback_exists(self, callback), "The callback has already been added as a handler.")

            event.add(self, callback)
        end

        local function remove_func(self, callback)
            mixin.assert_argument(callback, "function", 2)

            event.remove(self, callback)
        end

        local function trigger_helper(window)
            if not event.has_callbacks(window) or queued[window] or not window:WindowExists_() then
                return
            end

            window:QueueHandleCustom(
                function()
                    queued[window] = nil
                    event.dispatcher(window)
                end)

            queued[window] = true
        end

        local function trigger_func(window, immediate)
            if type(window) == "boolean" and window then
                for win in event.target_iterator() do
                    if immediate then
                        event.dispatcher(window)
                    else
                        trigger_helper(window)
                    end
                end
            else
                if immediate then
                    event.dispatcher(window)
                else
                    trigger_helper(window)
                end
            end
        end

        return add_func, remove_func, trigger_func, event.history_iterator
    end

    return mixin_helper

end

__imports["library.measurement"] = __imports["library.measurement"] or function()
    --[[
    $module measurement
    ]] --
    local measurement = {}

    local unit_names = {
        [finale.MEASUREMENTUNIT_EVPUS] = "EVPUs",
        [finale.MEASUREMENTUNIT_INCHES] = "Inches",
        [finale.MEASUREMENTUNIT_CENTIMETERS] = "Centimeters",
        [finale.MEASUREMENTUNIT_POINTS] = "Points",
        [finale.MEASUREMENTUNIT_PICAS] = "Picas",
        [finale.MEASUREMENTUNIT_SPACES] = "Spaces",
    }

    local unit_suffixes = {
        [finale.MEASUREMENTUNIT_EVPUS] = "e",
        [finale.MEASUREMENTUNIT_INCHES] = "i",
        [finale.MEASUREMENTUNIT_CENTIMETERS] = "c",
        [finale.MEASUREMENTUNIT_POINTS] = "pt",
        [finale.MEASUREMENTUNIT_PICAS] = "p",
        [finale.MEASUREMENTUNIT_SPACES] = "s",
    }

    local unit_abbreviations = {
        [finale.MEASUREMENTUNIT_EVPUS] = "ev",
        [finale.MEASUREMENTUNIT_INCHES] = "in",
        [finale.MEASUREMENTUNIT_CENTIMETERS] = "cm",
        [finale.MEASUREMENTUNIT_POINTS] = "pt",
        [finale.MEASUREMENTUNIT_PICAS] = "pc",
        [finale.MEASUREMENTUNIT_SPACES] = "sp",
    }

    --[[
    % convert_to_EVPUs

    Converts the specified string into EVPUs. Like text boxes in Finale, this supports
    the usage of units at the end of the string. The following are a few examples:

    - `12s` => 288 (12 spaces is 288 EVPUs)
    - `8.5i` => 2448 (8.5 inches is 2448 EVPUs)
    - `10cm` => 1133 (10 centimeters is 1133 EVPUs)
    - `10mm` => 113 (10 millimeters is 113 EVPUs)
    - `1pt` => 4 (1 point is 4 EVPUs)
    - `2.5p` => 120 (2.5 picas is 120 EVPUs)

    Read the [Finale User Manual](https://usermanuals.finalemusic.com/FinaleMac/Content/Finale/def-equivalents.htm#overriding-global-measurement-units)
    for more details about measurement units in Finale.

    @ text (string) the string to convert
    : (number) the converted number of EVPUs
    ]]
    function measurement.convert_to_EVPUs(text)
        local str = finale.FCString()
        str.LuaString = text
        return str:GetMeasurement(finale.MEASUREMENTUNIT_DEFAULT)
    end

    --[[
    % get_unit_name

    Returns the name of a measurement unit.

    @ unit (number) A finale MEASUREMENTUNIT constant.
    : (string)
    ]]
    function measurement.get_unit_name(unit)
        if unit == finale.MEASUREMENTUNIT_DEFAULT then
            unit = measurement.get_real_default_unit()
        end

        return unit_names[unit]
    end

    --[[
    % get_unit_suffix

    Returns the measurement unit's suffix. Suffixes can be used to force the text value (eg in `FCString` or `FCCtrlEdit`) to be treated as being from a particular measurement unit
    Note that although this method returns a "p" for Picas, the fractional part goes after the "p" (eg `1p6`), so in practice it may be that no suffix is needed.

    @ unit (number) A finale MEASUREMENTUNIT constant.
    : (string)
    ]]
    function measurement.get_unit_suffix(unit)
        if unit == finale.MEASUREMENTUNIT_DEFAULT then
            unit = measurement.get_real_default_unit()
        end

        return unit_suffixes[unit]
    end

    --[[
    % get_unit_abbreviation

    Returns measurement unit abbreviations that are more human-readable than Finale's internal suffixes.
    Abbreviations are also compatible with the internal ones because Finale discards everything after the first letter that isn't part of the suffix.

    For example:
    ```lua
    local str_internal = finale.FCString()
    str.LuaString = "2i"

    local str_display = finale.FCString()
    str.LuaString = "2in"

    print(str_internal:GetMeasurement(finale.MEASUREMENTUNIT_DEFAULT) == str_display:GetMeasurement(finale.MEASUREMENTUNIT_DEFAULT)) -- true
    ```

    @ unit (number) A finale MEASUREMENTUNIT constant.
    : (string)
    ]]
    function measurement.get_unit_abbreviation(unit)
        if unit == finale.MEASUREMENTUNIT_DEFAULT then
            unit = measurement.get_real_default_unit()
        end

        return unit_abbreviations[unit]
    end

    --[[
    % is_valid_unit

    Checks if a number is equal to one of the finale MEASUREMENTUNIT constants.

    @ unit (number) The unit to check.
    : (boolean) `true` if valid, `false` if not.
    ]]
    function measurement.is_valid_unit(unit)
        return unit_names[unit] and true or false
    end

    --[[
    % get_real_default_unit

    Resolves `finale.MEASUREMENTUNIT_DEFAULT` to the value of one of the other `MEASUREMENTUNIT` constants.

    : (number)
    ]]
    function measurement.get_real_default_unit()
        local str = finale.FCString()
        finenv.UI():GetDecimalSeparator(str)
        local separator = str.LuaString
        str:SetMeasurement(72, finale.MEASUREMENTUNIT_DEFAULT)

        if str.LuaString == "72" then
            return finale.MEASUREMENTUNIT_EVPUS
        elseif str.LuaString == "0" .. separator .. "25" then
            return finale.MEASUREMENTUNIT_INCHES
        elseif str.LuaString == "0" .. separator .. "635" then
            return finale.MEASUREMENTUNIT_CENTIMETERS
        elseif str.LuaString == "18" then
            return finale.MEASUREMENTUNIT_POINTS
        elseif str.LuaString == "1p6" then
            return finale.MEASUREMENTUNIT_PICAS
        elseif str.LuaString == "3" then
            return finale.MEASUREMENTUNIT_SPACES
        end
    end

    return measurement

end

__imports["mixin.FCXCustomLuaWindow"] = __imports["mixin.FCXCustomLuaWindow"] or function()
    --  Author: Edward Koltun
    --  Date: April 10, 2022
    --[[
    $module FCXCustomLuaWindow

    *Extends `FCMCustomLuaWindow`*

    Summary of modifications:
    - Changed argument order for timer handlers so that window is passed first, before `timerid` (enables handlers to be method of window).
    - Added `Add*` and `Remove*` handler methods for timers
    - Measurement unit can be set on the window or changed by the user through a `FCXCtrlMeasurementUnitPopup`.
    - Windows also have the option of inheriting the parent window's measurement unit when opening.
    - Introduced a `MeasurementUnitChange` event.
    - All controls with an `UpdateMeasurementUnit` method will have that method called upon a measurement unit change to allow them to immediately update their displayed values without needing to wait for a `MeasurementUnitChange` event.
    - Changed the default auto restoration behaviour for window position to enabled
    - finenv.RegisterModelessDialog is called automatically when ShowModeless is called
    - DebugClose is enabled by default
    ]] --
    local mixin = require("library.mixin")
    local utils = require("library.utils")
    local mixin_helper = require("library.mixin_helper")
    local measurement = require("library.measurement")

    local private = setmetatable({}, {__mode = "k"})
    local props = {MixinParent = "FCMCustomLuaWindow"}

    local trigger_measurement_unit_change
    local each_last_measurement_unit_change

    --[[
    % Init

    **[Internal]**

    @ self (FCXCustomLuaWindow)
    ]]
    function props:Init()
        private[self] = private[self] or {
            MeasurementUnit = measurement.get_real_default_unit(),
            UseParentMeasurementUnit = true,
            HandleTimer = {},
            RunModelessDefaultAction = nil,
        }

        if self.SetAutoRestorePosition then
            self:SetAutoRestorePosition(true)
        end

        self:SetRestoreControlState(true)
        self:SetEnableDebugClose(true)

        -- Register proxy for HandlerTimer if it's available in this RGPLua version.
        if self.RegisterHandleTimer_ then
            self:RegisterHandleTimer_(function(timerid)
                -- Call registered handler if there is one
                if private[self].HandleTimer.Registered then
                    -- Pass window as first parameter
                    private[self].HandleTimer.Registered(self, timerid)
                end

                -- Call any added handlers for this timer
                if private[self].HandleTimer[timerid] then
                    for _, cb in ipairs(private[self].HandleTimer[timerid]) do
                        -- Pass window as first parameter
                        cb(self, timerid)
                    end
                end
            end)
        end
    end

    --[[
    % GetMeasurementUnit

    Returns the window's current measurement unit.

    @ self (FCXCustomLuaWindow)
    : (number) The value of one of the finale MEASUREMENTUNIT constants.
    ]]
    function props:GetMeasurementUnit()
        return private[self].MeasurementUnit
    end

    --[[
    % SetMeasurementUnit

    **[Fluid]**
    Sets the window's current measurement unit. Millimeters are not supported.

    All controls that have an `UpdateMeasurementUnit` method will have that method called to allow them to immediately update their displayed measurement unit without needing to wait for a `MeasurementUnitChange` event.

    @ self (FCXCustomLuaWindow)
    @ unit (number) One of the finale MEASUREMENTUNIT constants.
    ]]
    function props:SetMeasurementUnit(unit)
        mixin.assert_argument(unit, "number", 2)

        if unit == private[self].MeasurementUnit then
            return
        end

        if unit == finale.MEASUREMENTUNIT_DEFAULT then
            unit = measurement.get_real_default_unit()
        end

        mixin.force_assert(measurement.is_valid_unit(unit), "Measurement unit is not valid.")

        private[self].MeasurementUnit = unit

        -- Update all measurement controls
        for ctrl in each(self) do
            local func = ctrl.UpdateMeasurementUnit
            if func then
                func(ctrl)
            end
        end

        trigger_measurement_unit_change(self)
    end

    --[[
    % GetMeasurementUnitName

    Returns the name of the window's current measurement unit.

    @ self (FCXCustomLuaWindow)
    : (string)
    ]]
    function props:GetMeasurementUnitName()
        return measurement.get_unit_name(private[self].MeasurementUnit)
    end

    --[[
    % UseParentMeasurementUnit

    **[Fluid]**
    Sets whether to use the parent window's measurement unit when opening this window. Defaults to `true`.

    @ self (FCXCustomLuaWindow)
    @ on (boolean)
    ]]
    function props:UseParentMeasurementUnit(on)
        mixin.assert_argument(on, "boolean", 2)

        private[self].UseParentMeasurementUnit = on
    end

    --[[
    % CreateMeasurementEdit

    Creates a `FCXCtrlMeasurementEdit` control.

    @ self (FCXCustomLuaWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (string)
    : (FCXCtrlMeasurementEdit)
    ]]
    function props:CreateMeasurementEdit(x, y, control_name)
        mixin.assert_argument(x, "number", 2)
        mixin.assert_argument(y, "number", 3)
        mixin.assert_argument(control_name, {"string", "nil"}, 4)

        local edit = mixin.FCMCustomWindow.CreateEdit(self, x, y, control_name)
        return mixin.subclass(edit, "FCXCtrlMeasurementEdit")
    end

    --[[
    % CreateMeasurementUnitPopup

    Creates a popup which allows the user to change the window's measurement unit.

    @ self (FCXCustomLuaWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (string)
    : (FCXCtrlMeasurementUnitPopup)
    ]]
    function props:CreateMeasurementUnitPopup(x, y, control_name)
        mixin.assert_argument(x, "number", 2)
        mixin.assert_argument(y, "number", 3)
        mixin.assert_argument(control_name, {"string", "nil"}, 4)

        local popup = mixin.FCMCustomWindow.CreatePopup(self, x, y, control_name)
        return mixin.subclass(popup, "FCXCtrlMeasurementUnitPopup")
    end

    --[[
    % CreatePageSizePopup

    Creates a popup which allows the user to select a page size.

    @ self (FCXCustomLuaWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (string)
    : (FCXCtrlPageSizePopup)
    ]]
    function props:CreatePageSizePopup(x, y, control_name)
        mixin.assert_argument(x, "number", 2)
        mixin.assert_argument(y, "number", 3)
        mixin.assert_argument(control_name, {"string", "nil"}, 4)

        local popup = mixin.FCMCustomWindow.CreatePopup(self, x, y, control_name)
        return mixin.subclass(popup, "FCXCtrlPageSizePopup")
    end

    --[[
    % CreateStatic

    **[Override]**
    Creates an `FCXCtrlStatic` control.

    @ self (FCXCustomLuaWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (string)
    : (FCXCtrlStatic)
    ]]
    function props:CreateStatic(x, y, control_name)
        mixin.assert_argument(x, "number", 2)
        mixin.assert_argument(y, "number", 3)
        mixin.assert_argument(control_name, {"string", "nil"}, 4)

        local popup = mixin.FCMCustomWindow.CreateStatic(self, x, y, control_name)
        return mixin.subclass(popup, "FCXCtrlStatic")
    end

    --[[
    % CreateUpDown

    **[Override]**
    Creates an `FCXCtrlUpDown` control.

    @ self (FCXCustomLuaWindow)
    @ x (number)
    @ y (number)
    @ [control_name] (string)
    : (FCXCtrlUpDown)
    ]]
    function props:CreateUpDown(x, y, control_name)
        mixin.assert_argument(x, "number", 2)
        mixin.assert_argument(y, "number", 3)
        mixin.assert_argument(control_name, {"string", "nil"}, 4)

        local updown = mixin.FCMCustomWindow.CreateUpDown(self, x, y, control_name)
        return mixin.subclass(updown, "FCXCtrlUpDown")
    end


    if finenv.MajorVersion > 0 or finenv.MinorVersion >= 56 then
        --[[
    % SetTimer

    **[>= v0.56] [Fluid] [Override]**

    @ self (FCCustomLuaWindow)
    @ timerid (number)
    @ msinterval (number)
    ]]
        function props:SetTimer(timerid, msinterval)
            mixin.assert_argument(timerid, "number", 2)
            mixin.assert_argument(msinterval, "number", 3)

            self:SetTimer_(timerid, msinterval)

            private[self].HandleTimer[timerid] = private[self].HandleTimer[timerid] or {}
        end

        --[[
    % GetNextTimerID

    **[>= v0.56]**
    Returns the next available timer ID.

    @ self (FCMCustomLuaWindow)
    : (number)
    ]]
        function props:GetNextTimerID()
            while private[self].HandleTimer[private[self].NextTimerID] do
                private[self].NextTimerID = private[self].NextTimerID + 1
            end

            return private[self].NextTimerID
        end

        --[[
    % SetNextTimer

    **[>= v0.56]**
    Sets a timer using the next available ID (according to `GetNextTimerID`) and returns the ID.

    @ self (FCMCustomLuaWindow)
    @ msinterval (number)
    : (number) The ID of the newly created timer.
    ]]
        function props:SetNextTimer(msinterval)
            mixin.assert_argument(msinterval, "number", 2)

            local timerid = self:GetNextTimerID()
            self:SetTimer(timerid, msinterval)

            return timerid
        end

        --[[
    % HandleTimer

    **[Callback Template] [Override]**
    Insert window object as first argument to handler.

    @ window (FCXCustomLuaWindow)
    @ timerid (number)
    ]]

        --[[
    % RegisterHandleTimer

    **[>= v0.56] [Override]**

    @ self (FCMCustomLuaWindow)
    @ callback (function) See `HandleTimer` for callback signature (note the change of arguments).
    : (boolean) `true` on success
    ]]
        function props:RegisterHandleTimer(callback)
            mixin.assert_argument(callback, "function", 2)

            private[self].HandleTimer.Registered = callback
            return true
        end

        --[[
    % AddHandleTimer

    **[>= v0.56] [Fluid]**
    Adds a handler for a timer. Handlers added by this method will be called after the registered handler, if there is one.
    If a handler is added for a timer that hasn't been set, the timer ID will be no longer be available to `GetNextTimerID` and `SetNextTimer`.

    @ self (FCMCustomLuaWindow)
    @ timerid (number)
    @ callback (function) See `CancelButtonPressed` for callback signature.
    ]]
        function props:AddHandleTimer(timerid, callback)
            mixin.assert_argument(timerid, "number", 2)
            mixin.assert_argument(callback, "function", 3)

            private[self].HandleTimer[timerid] = private[self].HandleTimer[timerid] or {}

            table.insert(private[self].HandleTimer[timerid], callback)
        end

        --[[
    % RemoveHandleTimer

    **[>= v0.56] [Fluid]**
    Removes a handler added with `AddHandleTimer`.

    @ self (FCMCustomLuaWindow)
    @ timerid (number)
    @ callback (function)
    ]]
        function props:RemoveHandleTimer(timerid, callback)
            mixin.assert_argument(timerid, "number", 2)
            mixin.assert_argument(callback, "function", 3)

            if not private[self].HandleTimer[timerid] then
                return
            end

            utils.table_remove_first(private[self].HandleTimer[timerid], callback)
        end
    end

    --[[
    % RegisterHandleOkButtonPressed

    **[Fluid] [Override]**
    Stores callback as default action for `RunModeless`.

    @ self (FCXCustomLuaWindow)
    @ callback (function) See documentation for `FCMCustomLuaWindow.OkButtonPressed` for callback signature.
    ]]
    function props:RegisterHandleOkButtonPressed(callback)
        mixin.assert_argument(callback, "function", 2)

        private[self].RunModelessDefaultAction = callback
        mixin.FCMCustomLuaWindow.RegisterHandleOkButtonPressed(self, callback)
    end

    --[[
    % ExecuteModal

    **[Override]**
    If a parent window is passed and the `UseParentMeasurementUnit` setting is on, the measurement unit is automatically changed to match the parent.

    @ self (FCXCustomLuaWindow)
    @ parent (FCCustomWindow|FCMCustomWindow|nil)
    : (number)
    ]]
    function props:ExecuteModal(parent)
        if mixin.is_instance_of(parent, "FCXCustomLuaWindow") and private[self].UseParentMeasurementUnit then
            self:SetMeasurementUnit(parent:GetMeasurementUnit())
        end

        return mixin.FCMCustomLuaWindow.ExecuteModal(self, parent)
    end

    --[[
    % ShowModeless

    **[Override]**
    Automatically registers the dialog with `finenv.RegisterModelessDialog`.

    @ self (FCXCustomLuaWindow)
    : (boolean)
    ]]
    function props:ShowModeless()
        finenv.RegisterModelessDialog(self)
        return mixin.FCMCustomLuaWindow.ShowModeless(self)
    end

    --[[
    % RunModeless

    **[Fluid]**
    Runs the window as a self-contained modeless plugin, performing the following steps:
    - The first time the plugin is run, if ALT or SHIFT keys are pressed, sets `OkButtonCanClose` to true
    - On subsequent runnings, if ALT or SHIFT keys are pressed the default action will be called without showing the window
    - The default action defaults to the function registered with `RegisterHandleOkButtonPressed`
    - If in JWLua, the window will be shown as a modal and it will check that a music region is currently selected

    @ self (FCXCustomLuaWindow)
    @ [no_selection_required] (boolean) If `true` and showing as a modal, will skip checking if a region is selected.
    @ [default_action_override] (boolean|function) If `false`, there will be no default action. If a `function`, overrides the registered `OkButtonPressed` handler as the default action.
    ]]
    function props:RunModeless(no_selection_required, default_action_override)
        local modifier_keys_on_invoke = finenv.QueryInvokedModifierKeys and (finenv.QueryInvokedModifierKeys(finale.CMDMODKEY_ALT) or finenv.QueryInvokedModifierKeys(finale.CMDMODKEY_SHIFT))
        local default_action = default_action_override == nil and private[self].RunModelessDefaultAction or default_action_override

        if modifier_keys_on_invoke and self:HasBeenShown() and default_action then
            default_action(self)
            return
        end

        if finenv.IsRGPLua then
            -- OkButtonCanClose will be nil before 0.56 and true (the default) after
            if self.OkButtonCanClose then
                self.OkButtonCanClose = modifier_keys_on_invoke
            end

            if self:ShowModeless() then
                finenv.RetainLuaState = true
            end
        else
            if not no_selection_required and finenv.Region():IsEmpty() then
                finenv.UI():AlertInfo("Please select a music region before running this script.", "Selection Required")
                return
            end

            self:ExecuteModal(nil)
        end
    end

    --[[
    % HandleMeasurementUnitChange

    **[Callback Template]**
    Template for MeasurementUnitChange handlers.

    @ window (FCXCustomLuaWindow) The window that triggered the event.
    @ last_unit (number) The window's previous measurement unit.
    ]]

    --[[
    % AddHandleMeasurementUnitChange

    **[Fluid]**
    Adds a handler for a change in the window's measurement unit.
    The even will fire when:
    - The window is created (if the measurement unit is not `finale.MEASUREMENTUNIT_DEFAULT`)
    - The measurement unit is changed by the user via a `FCXCtrlMeasurementUnitPopup`
    - The measurement unit is changed programmatically (if the measurement unit is changed within a handler, that *same* handler will not be called again for that change.)

    @ self (FCXCustomLuaWindow)
    @ callback (function) See `HandleMeasurementUnitChange` for callback signature.
    ]]

    --[[
    % RemoveHandleMeasurementUnitChange

    **[Fluid]**
    Removes a handler added with `AddHandleMeasurementUnitChange`.

    @ self (FCXCustomLuaWindow)
    @ callback (function)
    ]]
    props.AddHandleMeasurementUnitChange, props.RemoveHandleMeasurementUnitChange, trigger_measurement_unit_change, each_last_measurement_unit_change =
        mixin_helper.create_custom_window_change_event(
            {
                name = "last_unit",
                get = function(win)
                    return mixin.FCXCustomLuaWindow.GetMeasurementUnit(win)
                end,
                initial = measurement.get_real_default_unit(),
            })

    return props

end

__imports["mixin.__FCMUserWindow"] = __imports["mixin.__FCMUserWindow"] or function()
    --  Author: Edward Koltun
    --  Date: March 3, 2022
    --[[
    $module __FCMUserWindow

    Summary of modifications:
    - Setters that accept `FCString` now also accept Lua `string` and `number`.
    - In getters with an `FCString` parameter, the parameter is now optional and a Lua `string` is returned. 
    ]] --
    local mixin = require("library.mixin")

    local props = {}

    local temp_str = finale.FCString()

    --[[
    % GetTitle

    **[Override]**
    Returns a Lua `string` and makes passing an `FCString` optional.

    @ self (__FCMUserWindow)
    @ [title] (FCString)
    : (string)
    ]]
    function props:GetTitle(title)
        mixin.assert_argument(title, {"nil", "FCString"}, 2)

        if not title then
            title = temp_str
        end

        self:GetTitle_(title)

        return title.LuaString
    end

    --[[
    % SetTitle

    **[Fluid] [Override]**
    Accepts Lua `string` and `number` in addition to `FCString`.

    @ self (__FCMUserWindow)
    @ title (FCString|string|number)
    ]]
    function props:SetTitle(title)
        mixin.assert_argument(title, {"string", "number", "FCString"}, 2)

        if type(title) ~= "userdata" then
            temp_str.LuaString = tostring(title)
            title = temp_str
        end

        self:SetTitle_(title)
    end

    return props

end

__imports["library.mixin"] = __imports["library.mixin"] or function()
    --  Author: Edward Koltun
    --  Date: November 3, 2021
    
    --[[
    $module Fluid Mixins
    
    The Fluid Mixins library does the following:
    - Modifies Finale objects to allow methods to be overridden and new methods or properties to be added. In other words, the modified Finale objects function more like regular Lua tables.
    - Mixins can be used to address bugs, to introduce time-savers, or to provide custom functionality.
    - Introduces a new namespace for accessing the mixin-enabled Finale objects.
    - Also introduces two types of formally defined mixin: `FCM` and `FCX` classes
    - As an added convenience, all methods that return zero values have a fluid interface enabled (aka method chaining)
    
    
    ## mixin Namespace
    To utilise the new namespace, simply include the library, which also gives access to the helper functions:
    ```lua
    local mixin = require("library.mixin")
    ```
    
    All defined mixins can be accessed through the `mixin` namespace in the same way as the `finale` namespace. All constructors have the same signature as their `FC` originals.
    
    ```lua
    local fcstr = finale.FCString()
    
    -- Base mixin-enabled FCString object
    local fcmstr = mixin.FCMString()
    
    -- Customised mixin that extends FCMString
    local fcxstr = mixin.FCXString()
    
    -- Customised mixin that extends FCXString. Still has the same constructor signature as FCString
    local fcxcstr = mixin.FCXMyCustomString()
    ```
    For more information about naming conventions and the different types of mixins, see the 'FCM Mixins' and 'FCX Mixins' sections.
    
    
    Static copies of `FCM` and `FCX` methods and properties can also be accessed through the namespace like so:
    ```lua
    local func = mixin.FCXMyMixin.MyMethod
    ```
    Note that static access includes inherited methods and properties.
    
    
    ## Rules of the Game
    - New methods can be added or existing methods can be overridden.
    - New properties can be added but existing properties retain their original behaviour (ie if they are writable or read-only, and what types they can be)
    - The original method can always be accessed by appending a trailing underscore to the method name
    - In keeping with the above, method and property names cannot end in an underscore. Setting a method or property ending with an underscore will result in an error.
    - Returned `FC` objects from all mixin methods are automatically upgraded to a mixin-enabled `FCM` object.
    - All methods that return no values (returning `nil` counts as returning a value) will instead return `self`, enabling a fluid interface
    
    There are also some additional global mixin properties and methods that have special meaning:
    | Name | Description | FCM Accessible | FCM Definable | FCX Accessible | FCX Definable |
    | :--- | :---------- | :------------- | :------------ | :------------- | :------------ |
    | string `MixinClass` | The class name (FCM or FCX) of the mixin. | Yes | No | Yes | No |
    | string|nil `MixinParent` | The name of the mixin parent | Yes | No | Yes | Yes (required) |
    | string|nil `MixinBase` | The class name of the FCM base of an FCX class | No | No | Yes | No |
    | function `Init(self`) | An initialising function. This is not a constructor as it will be called after the object has been constructed. | Yes | Yes (optional) | Yes | Yes (optional) |
    
    
    ## FCM Mixins
    
    `FCM` classes are the base mixin-enabled Finale objects. These are modified Finale classes which, by default (that is, without any additional modifications), retain full backward compatibility with their original counterparts.
    
    The name of an `FCM` class corresponds to its underlying 'FC' class, with the addition of an 'M' after the 'FC'.
    For example, the following will create a mixin-enabled `FCCustomLuaWindow` object:
    ```lua
    local mixin = require("library.mixin")
    
    local dialog = mixin.FCMCustomLuaWindow()
    ```
    
    In addition to creating a mixin-enabled finale object, `FCM` objects also automatically load any `FCM` mixins that apply to the class or its parents. These may contain additional methods or overrides for existing methods (eg allowing a method that expects an `FCString` object to accept a regular Lua string as an alternative). The usual principles of inheritance apply (children override parents, etc).
    
    To see if any additional methods are available, or which methods have been modified, look for a file named after the class (eg `FCMCtrlStatic.lua`) in the `mixin` directory. Also check for parent classes, as `FCM` mixins are inherited and can be set at any level in the class hierarchy.
    
    
    ## Defining an FCM Mixin
    The following is an example of how to define an `FCM` mixin for `FCMControl`.
    `src/mixin/FCMControl.lua`
    ```lua
    -- Include the mixin namespace and helper functions
    local library = require("library.general_library")
    local mixin = require("library.mixin")
    
    local props = {
    
        -- An optional initialising method
        Init = function(self)
            print("Initialising...")
        end,
    
        -- This method is an override for the SetText method 
        -- It allows the method to accept a regular Lua string, which means that plugin authors don't need to worry anout creating an FCString objectq
        SetText = function(self, str)
            mixin.assert_argument(str, {"string", "number", "FCString"}, 2)
    
            -- Check if the argument is a finale object. If not, turn it into an FCString
            if not library.is_finale_object(str)
                local tmp = str
    
                -- Use a mixin object so that we can take advantage of the fluid interface
                str = mixin.FCMString():SetLuaString(tostring(str))
            end
    
            -- Use a trailing underscore to reference the original method from FCControl
            self:SetText_(str)
    
            -- By maintaining the original method's behaviour and not returning anything, the fluid interface can be applied.
        end
    }
    
    return props
    ```
    Since the underlying class `FCControl` has a number of child classes, the `FCMControl` mixin will also be inherited by all child classes, unless overridden.
    
    
    An example of utilizing the above mixin:
    ```lua
    local mixin = require("library.mixin")
    
    local dialog = mixin.FCMCustomLuaWindow()
    
    -- Fluid interface means that self is returned from SetText instead of nothing
    local label = dialog:CreateStatic(10, 10):SetText("Hello World")
    
    dialog:ExecuteModal(nil)
    ```
    
    
    
    ## FCX Mixins
    `FCX` mixins are extensions of `FCM` mixins. They are intended for defining extended functionality with no requirement for backwards compatability with the underlying `FC` object.
    
    While `FCM` class names are directly tied to their underlying `FC` object, their is no such requirement for an `FCX` mixin. As long as it the class name is prefixed with `FCX` and is immediately followed with another uppercase letter, they can be named anything. If an `FCX` mixin is not defined, the namespace will return `nil`.
    
    When constructing an `FCX` mixin (eg `local dialog = mixin.FCXMyDialog()`, the library first creates the underlying `FCM` object and then adds each parent (if any) `FCX` mixin until arriving at the requested class.
    
    
    Here is an example `FCX` mixin definition:
    
    `src/mixin/FCXMyStaticCounter.lua`
    ```lua
    -- Include the mixin namespace and helper functions
    local mixin = require("library.mixin")
    
    -- Since mixins can't have private properties, we can store them in a table
    local private = {}
    setmetatable(private, {__mode = "k"}) -- Use weak keys so that properties are automatically garbage collected along with the objects they are tied to
    
    local props = {
    
        -- All FCX mixins must declare their parent. It can be an FCM class or another FCX class
        MixinParent = "FCMCtrlStatic",
    
        -- Initialiser
        Init = function(self)
            -- Set up private storage for the counter value
            if not private[self] then
                private[self] = 0
                mixin.FCMControl.SetText(self, tostring(private[self]))
            end
        end,
    
        -- This custom control doesn't allow manual setting of text, so we override it with an empty function
        SetText = function()
        end,
    
        -- Incrementing counter method
        Increment = function(self)
            private[self] = private[self] + 1
    
            -- We need the SetText method, but we've already overridden it! Fortunately we can take a static copy from the mixin namespace
            mixin.FCMControl.SetText(self, tostring(private[self]))
        end
    }
    
    return props
    ```
    
    `src/mixin/FCXMyCustomDialog.lua`
    ```lua
    -- Include the mixin namespace and helper functions
    local mixin = require("library.mixin")
    
    local props = {
        MixinParent = "FCMCustomLuaWindow",
    
        CreateStaticCounter = function(self, x, y)
            -- Create an FCMCtrlStatic and then use the subclass function to apply the FCX mixin
            return mixin_private.subclass(self:CreateStatic(x, y), "FCXMyStaticCounter")
        end
    }
    
    return props
    ```
    
    
    Example usage:
    ```lua
    local mixin = require("library.mixin")
    
    local dialog = mixin.FCXMyCustomDialog()
    
    local counter = dialog:CreateStaticCounter(10, 10)
    
    counter:Increment():Increment()
    
    -- Counter should display 2
    dialog:ExecuteModal(nil)
    ```
    ]]
    
    local utils = require("library.utils")
    local library = require("library.general_library")
    
    -- Public methods and mixin constructors, stored separately to keep the mixin namespace read-only.
    local mixin_public = {}
    -- Private methods
    local mixin_private = {}
    -- Fully resolved FCM and FCX mixin class definitions
    local mixin_classes = {}
    -- Weak table for mixin instance properties / methods
    local mixin_props = setmetatable({}, {__mode = "k"})
    
    -- Create a new namespace for mixins
    local mixin = setmetatable({}, {
        __newindex = function(t, k, v) end,
        __index = function(t, k)
            if mixin_public[k] then return mixin_public[k] end
    
            mixin_private.load_mixin_class(k)
            if not mixin_classes[k] then return nil end
    
            -- Cache the class tables
            mixin_public[k] = setmetatable({}, {
                __newindex = function(tt, kk, vv) end,
                __index = function(tt, kk)
                    local val = utils.copy_table(mixin_classes[k].props[kk])
                    if type(val) == "function" then
                        val = mixin_private.create_fluid_proxy(val, kk)
                    end
                    return val
                end,
                __call = function(_, ...)
                    if mixin_private.is_fcm_class_name(k) then
                        return mixin_private.create_fcm(k, ...)
                    else
                        return mixin_private.create_fcx(k, ...)
                    end
                end
            })
    
            return mixin_public[k]
        end
    })
    
    -- Reserved properties (cannot be set on an object)
    -- 0 = cannot be set in the mixin definition
    -- 1 = can be set in the mixin definition
    local reserved_props = {
        IsMixinReady = 0,
        MixinClass = 0,
        MixinParent = 1,
        MixinBase = 0,
        Init = 1,
    }
    
    function mixin_private.is_fcm_class_name(class_name)
        return type(class_name) == "string" and (class_name:match("^FCM%u") or class_name:match("^__FCM%u")) and true or false
    end
    
    function mixin_private.is_fcx_class_name(class_name)
        return type(class_name) == "string" and class_name:match("^FCX%u") and true or false
    end
    
    function mixin_private.fcm_to_fc_class_name(class_name)
        return string.gsub(class_name, "FCM", "FC", 1)
    end
    
    function mixin_private.fc_to_fcm_class_name(class_name)
        return string.gsub(class_name, "FC", "FCM", 1)
    end
    
    -- Gets the real class name of a Finale object
    -- Some classes have incorrect class names, so this function attempts to resolve them with ducktyping
    -- Does not check if the object is a Finale object
    function mixin_private.get_class_name(object)
        -- If we're dealing with mixin objects, methods may have been added, so we need the originals
        local suffix = object.MixinClass and "_" or ""
        local class_name = object["ClassName" .. suffix](object)
    
        if class_name == "__FCCollection" and object["ExecuteModal" ..suffix] then
            return object["RegisterHandleCommand" .. suffix] and "FCCustomLuaWindow" or "FCCustomWindow"
        elseif class_name == "FCControl" then
            if object["GetCheck" .. suffix] then
                return "FCCtrlCheckbox"
            elseif object["GetThumbPosition" .. suffix] then
                return "FCCtrlSlider"
            elseif object["AddPage" .. suffix] then
                return "FCCtrlSwitcher"
            else
                return "FCCtrlButton"
            end
        elseif class_name == "FCCtrlButton" and object["GetThumbPosition" .. suffix] then
            return "FCCtrlSlider"
        end
    
        return class_name
    end
    
    -- Returns the name of the parent class
    -- This function should only be called for classnames that start with "FC" or "__FC"
    function mixin_private.get_parent_class(classname)
        local class = finale[classname]
        if type(class) ~= "table" then return nil end
        if not finenv.IsRGPLua then -- old jw lua
            classt = class.__class
            if classt and classname ~= "__FCBase" then
                classtp = classt.__parent -- this line crashes Finale (in jw lua 0.54) if "__parent" doesn't exist, so we excluded "__FCBase" above, the only class without a parent
                if classtp and type(classtp) == "table" then
                    for k, v in pairs(finale) do
                        if type(v) == "table" then
                            if v.__class and v.__class == classtp then
                                return tostring(k)
                            end
                        end
                    end
                end
            end
        else
            for k, _ in pairs(class.__parent) do
                return tostring(k)  -- in RGP Lua the v is just a dummy value, and the key is the classname of the parent
            end
        end
        return nil
    end
    
    -- Attempts to load a module
    function mixin_private.try_load_module(name)
        local success, result = pcall(function(c) return require(c) end, name)
    
        -- If the reason it failed to load was anything other than module not found, display the error
        if not success and not result:match("module '[^']-' not found") then
            error(result, 0)
        end
    
        return success, result
    end
    
    -- Loads an FCM or FCX mixin class
    function mixin_private.load_mixin_class(class_name)
        if mixin_classes[class_name] then return end
    
        local is_fcm = mixin_private.is_fcm_class_name(class_name)
        local is_fcx = mixin_private.is_fcx_class_name(class_name)
    
        -- Try personal mixins first (allows the library's mixin to be overridden if desired)
        local success, result = mixin_private.try_load_module("personal_mixin." .. class_name)
    
        if not success then
            success, result = mixin_private.try_load_module("mixin." .. class_name)
        end
    
        if not success then
            -- FCM classes are optional, so if it's valid and not found, start with a blank slate
            if is_fcm and finale[mixin_private.fcm_to_fc_class_name(class_name)] then
                result = {}
            else
                return
            end
        end
    
        -- Mixins must be a table
        if type(result) ~= "table" then
            error("Mixin '" .. class_name .. "' is not a table.", 0)
        end
    
        local class = {props = result}
    
        -- Check for trailing underscores
        for k, _ in pairs(class.props) do
            if type(k) == "string" and k:sub(-1) == "_" then
                error("Mixin methods and properties cannot end in an underscore (" .. class_name .. "." .. k .. ")", 0)
            end
        end
    
        -- Check for reserved properties
        for k, v in pairs(reserved_props) do
            if v == 0 and type(class.props[k]) ~= "nil" then
                error("Mixin '" .. class_name .. "' contains reserved property '" .. k .. "'", 0)
            end
        end
    
        -- Ensure that Init is a function
        if class.props.Init and type(class.props.Init) ~= "function" then
            error("Mixin '" .. class_name .. "' method 'Init' must be a function.", 0)
        end
    
        -- FCM specific
        if is_fcm then
            class.props.MixinParent = mixin_private.get_parent_class(mixin_private.fcm_to_fc_class_name(class_name))
    
            if class.props.MixinParent then
                class.props.MixinParent = mixin_private.fc_to_fcm_class_name(class.props.MixinParent)
    
                mixin_private.load_mixin_class(class.props.MixinParent)
    
                -- Collect init functions
                class.init = mixin_classes[class.props.MixinParent].init and utils.copy_table(mixin_classes[class.props.MixinParent].init) or {}
    
                if class.props.Init then
                    table.insert(class.init, class.props.Init)
                end
    
                -- Collect parent methods/properties if not overridden
                -- This prevents having to traverse the whole tree every time a method or property is accessed
                for k, v in pairs(mixin_classes[class.props.MixinParent].props) do
                    if type(class.props[k]) == "nil" then
                        class.props[k] = utils.copy_table(v)
                    end
                end
            end
    
        -- FCX specific
        else
            -- FCX classes must specify a parent
            if not class.props.MixinParent then
                error("Mixin '" .. class_name .. "' does not have a 'MixinParent' property defined.", 0)
            end
    
            mixin_private.load_mixin_class(class.props.MixinParent)
    
            -- Check if FCX parent is missing
            if not mixin_classes[class.props.MixinParent] then
                error("Unable to load mixin '" .. class.props.MixinParent .. "' as parent of '" .. class_name .. "'", 0)
            end
    
            -- Get the base FCM class (all FCX classes must eventually arrive at an FCM parent)
            class.props.MixinBase = mixin_private.is_fcm_class_name(class.props.MixinParent) and class.props.MixinParent or mixin_classes[class.props.MixinParent].props.MixinBase
        end
    
        -- Add class info to properties
        class.props.MixinClass = class_name
    
        mixin_classes[class_name] = class
    end
    
    -- Catches an error and throws it at the specified level (relative to where this function was called)
    -- First argument is called tryfunczzz for uniqueness
    -- Tail calls aren't counted as levels in the call stack. Adding an additional return value (in this case, 1) forces this level to be included, which enables the error to be accurately captured
    local pcall_line = debug.getinfo(1, "l").currentline + 2 -- This MUST refer to the pcall 2 lines below
    local function catch_and_rethrow(tryfunczzz, levels, ...)
        return mixin_private.pcall_wrapper(levels, pcall(function(...) return 1, tryfunczzz(...) end, ...))
    end
    
    -- Get the name of this file.
    local mixin_file_name = debug.getinfo(1, "S").source
    mixin_file_name = mixin_file_name:sub(1, 1) == "@" and mixin_file_name:sub(2) or nil
    
    -- Processes the results from the pcall in catch_and_rethrow
    function mixin_private.pcall_wrapper(levels, success, result, ...)
        if not success then
            local file
            local line
            local msg
            file, line, msg = result:match("([a-zA-Z]-:?[^:]+):([0-9]+): (.+)")
            msg = msg or result
    
            local file_is_truncated = file and file:sub(1, 3) == "..."
            file = file_is_truncated and file:sub(4) or file
    
            -- Conditions for rethrowing at a higher level:
            -- Ignore errors thrown with no level info (ie. level = 0), as we can't make any assumptions
            -- Both the file and line number indicate that it was thrown at this level
            if file
                and line
                and mixin_file_name
                and (file_is_truncated and mixin_file_name:sub(-1 * file:len()) == file or file == mixin_file_name)
                and tonumber(line) == pcall_line
            then
                local d = debug.getinfo(levels, "n")
    
                -- Replace the method name with the correct one, for bad argument errors etc
                msg = msg:gsub("'tryfunczzz'", "'" .. (d.name or "") .. "'")
    
                -- Shift argument numbers down by one for colon function calls
                if d.namewhat == "method" then
                    local arg = msg:match("^bad argument #(%d+)")
    
                    if arg then
                        msg = msg:gsub("#" .. arg, "#" .. tostring(tonumber(arg) - 1), 1)
                    end
                end
    
                error(msg, levels + 1)
    
            -- Otherwise, it's either an internal function error or we couldn't be certain that it isn't
            -- So, rethrow with original file and line number to be 'safe'
            else
                error(result, 0)
            end
        end
    
        return ...
    end
    
    -- Proxy function for all mixin method calls
    -- Handles the fluid interface and automatic promotion of all returned Finale objects to mixin objects
    local function proxy(t, ...)
        local n = select("#", ...)
        -- If no return values, then apply the fluid interface
        if n == 0 then
            return t
        end
    
        -- Apply mixin foundation to all returned finale objects
        for i = 1, n do
            mixin_private.enable_mixin(select(i, ...))
        end
        return ...
    end
    
    -- Returns a function that handles the fluid interface, mixin enabling, and error re-throwing
    function mixin_private.create_fluid_proxy(func, func_name)
        return function(t, ...)
            return proxy(t, catch_and_rethrow(func, 2, t, ...))
        end
    end
    
    -- Takes an FC object and enables the mixin
    function mixin_private.enable_mixin(object, fcm_class_name)
        if not library.is_finale_object(object) or mixin_props[object] then return object end
    
        mixin_private.apply_mixin_foundation(object)
        fcm_class_name = fcm_class_name or mixin_private.fc_to_fcm_class_name(mixin_private.get_class_name(object))
        mixin_props[object] = {}
    
        mixin_private.load_mixin_class(fcm_class_name)
    
        if mixin_classes[fcm_class_name].init then
            for _, v in pairs(mixin_classes[fcm_class_name].init) do
                v(object)
            end
        end
    
        return object
    end
    
    -- Modifies an FC class to allow adding mixins to any instance of that class.
    -- Needs an instance in order to gain access to the metatable
    function mixin_private.apply_mixin_foundation(object)
        if not object or not library.is_finale_object(object) or object.IsMixinReady then return end
    
        -- Metatables are shared across all instances, so this only needs to be done once per class
        local meta = getmetatable(object)
    
        -- We need to retain a reference to the originals for later
        local original_index = meta.__index 
        local original_newindex = meta.__newindex
    
        local fcm_class_name = mixin_private.fc_to_fcm_class_name(mixin_private.get_class_name(object))
    
        meta.__index = function(t, k)
            -- Return a flag that this class has been modified
            -- Adding a property to the metatable would be preferable, but that would entail going down the rabbit hole of modifying metatables of metatables
            if k == "IsMixinReady" then return true end
    
            -- If the object doesn't have an associated mixin (ie from finale namespace), let's pretend that nothing has changed and return early
            if not mixin_props[t] then return original_index(t, k) end
    
            local prop
    
            -- If there's a trailing underscore in the key, then return the original property, whether it exists or not
            if type(k) == "string" and k:sub(-1) == "_" then
                -- Strip trailing underscore
                prop = original_index(t, k:sub(1, -2))
    
            -- Check if it's a custom or FCX property/method
            elseif type(mixin_props[t][k]) ~= "nil" then
                prop = mixin_props[t][k]
    
            -- Check if it's an FCM property/method
            elseif type(mixin_classes[fcm_class_name].props[k]) ~= "nil" then
                prop = mixin_classes[fcm_class_name].props[k]
    
                -- If it's a table, copy it to allow instance-level editing
                if type(prop) == "table" then
                    mixin_props[t][k] = utils.copy_table(prop)
                    prop = mixin[t][k]
                end
    
            -- Otherwise, use the underlying object
            else
                prop = original_index(t, k)
            end
    
            if type(prop) == "function" then
                return mixin_private.create_fluid_proxy(prop, k)
            else
                return prop
            end
        end
    
        -- This will cause certain things (eg misspelling a property) to fail silently as the misspelled property will be stored on the mixin instead of triggering an error
        -- Using methods instead of properties will avoid this
        meta.__newindex = function(t, k, v)
            -- Return early if this is not mixin-enabled
            if not mixin_props[t] then return catch_and_rethrow(original_newindex, 2, t, k, v) end
    
            -- Trailing underscores are reserved for accessing original methods
            if type(k) == "string" and k:sub(-1) == "_" then
                error("Mixin methods and properties cannot end in an underscore.", 2)
            end
    
            -- Setting a reserved property is not allowed
            if reserved_props[k] then
                error("Cannot set reserved property '" .. k .. "'", 2)
            end
    
            local type_v_original = type(original_index(t, k))
    
            -- If it's a method, or a property that doesn't exist on the original object, store it
            if type_v_original == "nil" then
                local type_v_mixin = type(mixin_props[t][k])
                local type_v = type(v)
    
                -- Technically, a property could still be erased by setting it to nil and then replacing it with a method afterwards
                -- But handling that case would mean either storing a list of all properties ever created, or preventing properties from being set to nil.
                if type_v_mixin ~= "nil" then
                    if type_v == "function" and type_v_mixin ~= "function" then
                        error("A mixin method cannot be overridden with a property.", 2)
                    elseif type_v_mixin == "function" and type_v ~= "function" then
                        error("A mixin property cannot be overridden with a method.", 2)
                    end
                end
    
                mixin_props[t][k] = v
    
            -- If it's a method, we can override it but only with another method
            elseif type_v_original == "function" then
                if type(v) ~= "function" then
                    error("A mixin method cannot be overridden with a property.", 2)
                end
    
                mixin_props[t][k] = v
    
            -- Otherwise, try and store it on the original property. If it's read-only, it will fail and we show the error
            else
                catch_and_rethrow(original_newindex, 2, t, k, v)
            end
        end
    end
    
    -- See the doc block for mixin_public.subclass for information
    function mixin_private.subclass(object, class_name)
        if not library.is_finale_object(object) then
            error("Object is not a finale object.", 2)
        end
    
        if not catch_and_rethrow(mixin_private.subclass_helper, 2, object, class_name) then
            error(class_name .. " is not a subclass of " .. object.MixinClass, 2)
        end
    
        return object
    end
    
    -- Returns true on success, false if class_name is not a subclass of the object, and throws errors for everything else
    -- Returns false because we only want the originally requested class name for the error message, which is then handled by mixin_private.subclass
    function mixin_private.subclass_helper(object, class_name, suppress_errors)
        if not object.MixinClass then
            if suppress_errors then
                return false
            end
    
            error("Object is not mixin-enabled.", 2)
        end
    
        if not mixin_private.is_fcx_class_name(class_name) then
            if suppress_errors then
                return false
            end
    
            error("Mixins can only be subclassed with an FCX class.", 2)
        end
    
        if object.MixinClass == class_name then return true end
    
        mixin_private.load_mixin_class(class_name)
    
        if not mixin_classes[class_name] then
            if suppress_errors then
                return false
            end
    
            error("Mixin '" .. class_name .. "' not found.", 2)
        end
    
        -- If we've reached the top of the FCX inheritance tree and the class names don't match, then class_name is not a subclass
        if mixin_private.is_fcm_class_name(mixin_classes[class_name].props.MixinParent) and mixin_classes[class_name].props.MixinParent ~= object.MixinClass then
            return false
        end
    
        -- If loading the parent of class_name fails, then it's not a subclass of the object
        if mixin_classes[class_name].props.MixinParent ~= object.MixinClass then
            if not catch_and_rethrow(mixin_private.subclass_helper, 2, object, mixin_classes[class_name].props.MixinParent) then
                return false
            end
        end
    
        -- Copy the methods and properties over
        local props = mixin_props[object]
        for k, v in pairs(mixin_classes[class_name].props) do
            props[k] = utils.copy_table(v)
        end
    
        -- Run initialiser, if there is one
        if mixin_classes[class_name].props.Init then
            catch_and_rethrow(object.Init, 2, object)
        end
    
        return true
    end
    
    -- Silently returns nil on failure
    function mixin_private.create_fcm(class_name, ...)
        mixin_private.load_mixin_class(class_name)
        if not mixin_classes[class_name] then return nil end
    
        return mixin_private.enable_mixin(catch_and_rethrow(finale[mixin_private.fcm_to_fc_class_name(class_name)], 2, ...))
    end
    
    -- Silently returns nil on failure
    function mixin_private.create_fcx(class_name, ...)
        mixin_private.load_mixin_class(class_name)
        if not mixin_classes[class_name] then return nil end
    
        local object = mixin_private.create_fcm(mixin_classes[class_name].props.MixinBase, ...)
    
        if not object then return nil end
    
        if not catch_and_rethrow(mixin_private.subclass_helper, 2, object, class_name, false) then
            return nil
        end
    
        return object
    end
    
    --[[
    % subclass
    
    Takes a mixin-enabled finale object and migrates it to an `FCX` subclass. Any conflicting property or method names will be overwritten.
    
    If the object is not mixin-enabled or the current `MixinClass` is not a parent of `class_name`, then an error will be thrown.
    If the current `MixinClass` is the same as `class_name`, this function will do nothing.
    
    @ object (__FCMBase)
    @ class_name (string) FCX class name.
    : (__FCMBase|nil) The object that was passed with mixin applied.
    ]]
    mixin_public.subclass = mixin_private.subclass
    
    --[[
    % is_instance_of
    
    Checks if an object is an instance of a class.
    Conditions:
    - Parent cannot be instance of child.
    - `FC` object cannot be an instance of an `FCM` or `FCX` class
    - `FCM` object cannot be an instance of an `FCX` class
    - `FCX` object cannot be an instance of an `FC` class
    
    @ object (__FCBase) Any finale object, including mixin enabled objects.
    @ class_name (string) An `FC`, `FCM`, or `FCX` class name. Can be the name of a parent class.
    : (boolean)
    ]]
    function mixin_public.is_instance_of(object, class_name)
        if not library.is_finale_object(object) then
            return false
        end
    
        -- 0 = FC
        -- 1 = FCM
        -- 2 = FCX
        local object_type = (mixin_private.is_fcx_class_name(object.MixinClass) and 2) or (mixin_private.is_fcm_class_name(object.MixinClass) and 1) or 0
        local class_type = (mixin_private.is_fcx_class_name(class_name) and 2) or (mixin_private.is_fcm_class_name(class_name) and 1) or 0
    
        -- See doc block for explanation of conditions
        if (object_type == 0 and class_type == 1) or (object_type == 0 and class_type == 2) or (object_type == 1 and class_type == 2) or (object_type == 2 and class_type == 0) then
            return false
        end
    
        local parent = object_type == 0 and mixin_private.get_class_name(object) or object.MixinClass
    
        -- Traverse FCX hierarchy until we get to an FCM base
        if object_type == 2 then
            repeat
                if parent == class_name then
                    return true
                end
    
                -- We can assume that since we have an object, all parent classes have been loaded
                parent = mixin_classes[parent].props.MixinParent
            until mixin_private.is_fcm_class_name(parent)
        end
    
        -- Since FCM classes follow the same hierarchy as FC classes, convert to FC
        if object_type > 0 then
            parent = mixin_private.fcm_to_fc_class_name(parent)
        end
    
        if class_type > 0 then
            class_name = mixin_private.fcm_to_fc_class_name(class_name)
        end
    
        -- Traverse FC hierarchy
        repeat
            if parent == class_name then
                return true
            end
    
            parent = mixin_private.get_parent_class(parent)
        until not parent
    
        -- Nothing found
        return false
    end
    
    --[[
    % assert_argument
    
    Asserts that an argument to a mixin method is the expected type(s). This should only be used within mixin methods as the function name will be inserted automatically.
    
    NOTE: For performance reasons, this function will only assert if in debug mode (ie `finenv.DebugEnabled == true`). If assertions are always required, use `force_assert_argument` instead.
    
    If not a valid type, will throw a bad argument error at the level above where this function is called.
    Types can be Lua types (eg `string`, `number`, `bool`, etc), finale class (eg `FCString`, `FCMeasure`, etc), or mixin class (eg `FCMString`, `FCMMeasure`, etc)
    Parent classes cannot be specified as this function does not examine the class hierarchy.
    
    Note that mixin classes may satisfy the condition for the underlying `FC` class.
    For example, if the expected type is `FCString`, an `FCMString` object will pass the test, but an `FCXString` object will not.
    If the expected type is `FCMString`, an `FCXString` object will pass the test but an `FCString` object will not.
    
    @ value (mixed) The value to test.
    @ expected_type (string|table) If there are multiple valid types, pass a table of strings.
    @ argument_number (number) The REAL argument number for the error message (self counts as #1).
    ]]
    function mixin_public.assert_argument(value, expected_type, argument_number)
        local t, tt
    
        if library.is_finale_object(value) then
            t = value.MixinClass
            tt = mixin_private.is_fcx_class_name(t) and value.MixinBase or mixin_private.get_class_name(value)
        else
            t = type(value)
        end
    
        if type(expected_type) == "table" then
            for _, v in ipairs(expected_type) do
                if t == v or tt == v then
                    return
                end
            end
    
            expected_type = table.concat(expected_type, " or ")
        else
            if t == expected_type or tt == expected_type then
                return
            end
        end
    
        error("bad argument #" .. tostring(argument_number) .. " to 'tryfunczzz' (" .. expected_type .. " expected, got " .. (t or tt) .. ")", 3)
    end
    
    --[[
    % force_assert_argument
    
    The same as `assert_argument` except this function always asserts, regardless of whether debug mode is enabled.
    
    @ value (mixed) The value to test.
    @ expected_type (string|table) If there are multiple valid types, pass a table of strings.
    @ argument_number (number) The REAL argument number for the error message (self counts as #1).
    ]]
    mixin_public.force_assert_argument = mixin_public.assert_argument
    
    --[[
    % assert
    
    Asserts a condition in a mixin method. If the condition is false, an error is thrown one level above where this function is called.
    Only asserts when in debug mode. If assertion is required on all executions, use `force_assert` instead
    
    @ condition (any) Can be any value or expression.
    @ message (string) The error message.
    @ [no_level] (boolean) If true, error will be thrown with no level (ie level 0)
    ]]
    function mixin_public.assert(condition, message, no_level)
        if not condition then
            error(message, no_level and 0 or 3)
        end
    end
    
    --[[
    % force_assert
    
    The same as `assert` except this function always asserts, regardless of whether debug mode is enabled.
    
    @ condition (any) Can be any value or expression.
    @ message (string) The error message.
    @ [no_level] (boolean) If true, error will be thrown with no level (ie level 0)
    ]]
    mixin_public.force_assert = mixin_public.assert
    
    -- Replace assert functions with dummy function when not in debug mode
    if finenv.IsRGPLua and not finenv.DebugEnabled then
        mixin_public.assert_argument = function() end
        mixin_public.assert = mixin_public.assert_argument
    end
    
    --[[
    % UI
    
    Returns a mixin enabled UI object from `finenv.UI`
    
    : (FCMUI)
    ]]
    function mixin_public.UI()
        return mixin_private.enable_mixin(finenv.UI(), "FCMUI")
    end
    
    --[[
    % eachentry
    
    A modified version of the JW/RGPLua `eachentry` function that allows items to be stored and used outside of a loop.
    
    @ region (FCMusicRegion)
    @ [layer] (number)
    : (function) A generator which returns `FCMNoteEntry`s
    ]]
    function mixin_public.eachentry(region, layer)
        local measure = region.StartMeasure
        local slotno = region:GetStartSlot()
        local i = 0
        local layertouse = 0
        if layer ~= nil then layertouse = layer end
        local c = mixin.FCMNoteEntryCell(measure, region:CalcStaffNumber(slotno))
        c:SetLoadLayerMode(layertouse)
        c:Load()
        return function ()
            while true do
                i = i + 1;
                local returnvalue = c:GetItemAt(i - 1)
                if returnvalue ~= nil then
                    if (region:IsEntryPosWithin(returnvalue)) then return returnvalue end
                else
                    measure = measure + 1
                    if measure > region.EndMeasure then
                        measure = region.StartMeasure
                        slotno = slotno + 1
                        if (slotno > region:GetEndSlot()) then return nil end
                        c = mixin.FCMNoteEntryCell(measure, region:CalcStaffNumber(slotno))
                        c:SetLoadLayerMode(layertouse)
                        c:Load()
                        i = 0
                    else
                        c = mixin.FCMNoteEntryCell(measure, region:CalcStaffNumber(slotno))
                        c:SetLoadLayerMode(layertouse)
                        c:Load()
                        i = 0
                    end
                end
            end
        end
    end
    
    return mixin

end

function plugindef()
    finaleplugin.RequireSelection = true
    finaleplugin.Author = "Carl Vine"
    finaleplugin.AuthorURL = "http://carlvine.com/lua/"
    finaleplugin.Copyright = "CC0 https://creativecommons.org/publicdomain/zero/1.0/"
    finaleplugin.Version = "v0.56"
    finaleplugin.Date = "2022/08/07"
    finaleplugin.Notes = [[
        Swaps notes in the selected region between two chosen layers
    ]]
    return "Swap Layers Selective", "Swap Layers Selective", "Swaps notes in the selected region between two chosen layers"
end

-- RetainLuaState retains one global:
config = config or { layer_a = 1, layer_b = 2, pos_x = false, pos_y = false }
local layer = require("library.layer")
local mixin = require("library.mixin")

function any_errors()
    local error_message = ""
    if config.layer_a < 1 or  config.layer_a > 4 or config.layer_b < 1 or config.layer_b > 4  then 
        error_message = "Layer numbers must both\nbe integers between 1 and 4"
    elseif config.layer_a == config.layer_b  then 
        error_message = "Please choose two\ndifferent layer numbers"
    end
    if error_message ~= "" then  -- error dialog and exit
        finenv.UI():AlertNeutral("(script: " .. plugindef() .. ")", error_message)
        return true
    end
    return false
end

function swap_layers()
    if finenv.RetainLuaState ~= nil then
        finenv.RetainLuaState = true
    end
    finenv.StartNewUndoBlock("Swap Layers Selective", false)
    layer.swap(finenv.Region(), config.layer_a, config.layer_b)
    if finenv.EndUndoBlock then
        finenv.EndUndoBlock(true)
        finenv.Region():Redraw()
    else
        finenv.StartNewUndoBlock("Swap Layers Selective", true)
    end
end

function create_dialog_box()
    local dialog = mixin.FCXCustomLuaWindow():SetTitle("Swap Layers Selective")
    local mac_offset = finenv.UI():IsOnMac() and 3 or 0 -- extra horizontal offset for Mac edit box
    local offset_x = 105
    local offset_y = 22

    dialog:CreateStatic(0, mac_offset):SetText("swap layer# (1-4):"):SetWidth(offset_x)
    dialog:CreateEdit(offset_x, 0, "edit_a"):SetInteger(config.layer_a or 1)

    dialog:CreateStatic(5, offset_y + mac_offset):SetText("with layer# (1-4):"):SetWidth(offset_x)
    dialog:CreateEdit(offset_x, offset_y, "edit_b"):SetInteger(config.layer_b or 2)

    dialog:CreateOkButton()
    dialog:CreateCancelButton()
    dialog:RegisterHandleOkButtonPressed(function(self)
        config.layer_a = self:GetControl("edit_a"):GetInteger()
        config.layer_b = self:GetControl("edit_b"):GetInteger()
    end)
    dialog:RegisterCloseWindow(function()
        dialog:StorePosition()
        config.pos_x = dialog.StoredX
        config.pos_y = dialog.StoredY
    end)

    return dialog
end

function layers_swap_selective()
    local dialog = create_dialog_box()
    if config.pos_x and config.pos_y then
        dialog:StorePosition()
        dialog:SetRestorePositionOnlyData(config.pos_x, config.pos_y)
        dialog:RestorePosition()
    end
    if dialog:ExecuteModal(nil) ~= finale.EXECMODAL_OK then
        return -- user cancelled
    end
    if any_errors() then
        return
    end
    swap_layers()
end

layers_swap_selective()
