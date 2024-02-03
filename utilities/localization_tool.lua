function plugindef()
    finaleplugin.RequireDocument = false
    finaleplugin.RequireSelection = false
    finaleplugin.NoStore = true
    finaleplugin.ExecuteHttpsCalls = true
    finaleplugin.Author = "Robert Patterson"
    finaleplugin.Version = "1.0"
    finaleplugin.Date = "February 3, 2024"
    finaleplugin.MinJWLuaVersion = "0.71"
    finaleplugin.Notes = [[
        This script provides a set of localization services for developers of scripts to make localization
        as simple as possible. It uses calls to OpenAI to automatically translate words and phrases. However,
        such translations should always be checked with fluent speakers before presenting them to users.

        Functions include:

        - Automatically create a table of all quoted strings in the library. The user can then edit this
            down to the user-facing strings that need to be localized.
        - Given a table of strings, creates a localization file for a specified language.
        - Create a localized `plugindef` function for a script.
        
        Users of this script will get the best results if they use it in tandem with an indegrated development
        environment such as Visual Studio Code or with a text editor.
    ]]
    return "Localization Tool...", "Localization Tool", "Automates the process of localizing scripts in the Finale Lua repository."
end
--[[
$module Localization for Developers

This library provides a set of localization services for developers of scripts to make localization
as simple as possible. It uses calls to OpenAI to automatically translate words and phrases.
]]

-- luacheck: ignore 11./global_dialog

local client = require("library.client")
local library = require("library.general_library")
local openai = require("library.openai")
local mixin = require("library.mixin")
local utils = require("library.utils")

local tab_str = "    "
local src_directory = (function()
    local curr_path = library.calc_script_filepath()
    local path_name = finale.FCString()
    finale.FCString(curr_path):SplitToPathAndFile(path_name, nil)
    return path_name.LuaString .. "../src/"
end)()

--[[
% create_localized_base_table

Creates and returns a table of localizable strings by searching the top-level script for
quoted strings. While this may be useful at user-runtime, the primary use case it targets
is as a developer tool to aid in the creation of a table to be embedded in the script.

The returned table is in this form:

```
{
    ["<found string>"] = "found-string",
    ... -- for every string found in the script
}

Only the top-level script is searched. This is the script at the path specified by finenv.Running

: (table) a table containing the found strings
]]
local function create_localized_base_table(file_path)
    local retval = {}
    file_path = client.encode_with_client_codepage(file_path)
    local file = io.open(file_path, "r")
    if file then
        local function extract_strings(file_content)
            local i = 1
            local length = #file_content
            return function()
                while i <= length do
                    local char = string.sub(file_content, i, i)
                    if char == "'" or char == '"' then
                        local quote = char
                        local str = quote
                        i = i + 1
                        while i <= length do
                            char = string.sub(file_content, i, i)
                            local escaped = false
                            if char == '\\' then
                                i = i + 1
                                char = string.sub(file_content, i, i)
                                if char == "n" then char = "\n" end
                                if char == "r" then char = "\r" end
                                if char == "t" then char = "\t" end
                                -- may need to add more escape codes here
                                escaped = true
                            end
                            str = str .. char
                            -- Check for the end of the quoted string
                            if not escaped and char == quote then
                                break
                            end
                            i = i + 1
                        end
                        i = i + 1
                        return str:sub(2, -2)
                    end
                    i = i + 1
                end
                -- End of file, return nil to terminate the loop
                return nil
            end
        end
        for line in file:lines() do
            if not string.match(line, "^%s*%-%-") then
                for found_string in extract_strings(line) do
                    retval[found_string] = found_string
                end
            end
        end
        file:close()
    end
    return retval
end

local function make_flat_table_string(file_path, lang, t)
    local file_name = finale.FCString()
    finale.FCString(file_path):SplitToPathAndFile(nil, file_name)
    local concat = {}
    table.insert(concat, "--\n")
    table.insert(concat, "-- Localization " .. lang .. ".lua for " .. file_name.LuaString .. "\n")
    table.insert(concat, "--\n")
    table.insert(concat, "loc = {\n")
    for k, v in pairsbykeys(t) do
        table.insert(concat, "    [\"" .. tostring(k) .. "\"] = \"" .. tostring(v) .. "\",\n")
    end
    table.insert(concat, "}\n\nreturn loc\n")
    return table.concat(concat)
end

local function set_edit_text(edit_text)
    global_dialog:GetControl("editor"):SetText(edit_text)
end

--[[
% create_localized_base_table_string

Creates and displays a string representing a lua table of localizable strings by searching the specified script for
quoted strings. It then copies this string to the editor. The user can then edit it to include only user-facing
string and then create translations from that.

The base table is the table that defines the keys for all other languages. For each item in the base table, the
key is always equal to the value. The base table can be in any language. The base table does not need to be saved
as a localization.

@ file_path (string) the file_path to search for strings.
]]
local function create_localized_base_table_string(file_path)
    local t = create_localized_base_table(file_path)
    local locale = mixin.UI():GetUserLocaleName()
    set_edit_text(make_flat_table_string(file_path, locale:sub(1, 2), t))
    -- finenv.UI():AlertInfo("localization_base table copied to clipboard", "")
end

local function translate_localized_table_string(source_table, source_lang, target_lang) -- luacheck: ignore
    local table_string = make_flat_table_string(source_lang, source_table)
    local prompt = [[
        I am working on localizing text for a program that prints and plays music. There may be musical
        terminology among the words and phrases that I would like you to translate, as follows.\n
    ]] .. "Here is a lua table of keys and values:\n\n```\n" .. table_string .. "\n```\n" ..
        [[
                    Provide a string that is Lua source code of a table definition of a table that has the same keys
                    but with the values translated to locale specified by the code
                ]] .. target_lang .. ". The table name should be `localization." .. target_lang .. "`.\n" ..
        [[
                    Return only the Lua code without any commentary. There may or may not be musical terms
                    in the provided text. This information is provided for context if needed.
                ]]

    local success, result = openai.create_completion("gpt-4", prompt, 0.2, 30)
    if success then
        local retval = string.gsub(result.choices[1].message.content, "```", "")
        finenv.UI():TextToClipboard(retval)
        finenv.UI():AlertInfo("localization." .. target_lang .. " table copied to clipboard", "")
    else
        finenv.UI():AlertError(result, "OpenAI Error")
    end
end

local on_open -- luacheck: ignore
local function on_generate(control)
    local popup = global_dialog:GetControl("file_list")
    if popup:GetCount() <= 0 then
        on_open(control)
    end
    if popup:GetCount() > 0 then
        local sel_item = popup:GetSelectedItem()
        create_localized_base_table_string(popup:GetItemText(sel_item))
    end
end

local function on_open(control) -- luacheck: ignore
    local file_open_dlg = finale.FCFileOpenDialog(global_dialog:CreateChildUI())
    file_open_dlg:AddFilter(finale.FCString("*.lua"), finale.FCString("Lua source files"))
    file_open_dlg:SetInitFolder(finale.FCString(src_directory))
    file_open_dlg:SetWindowTitle(finale.FCString("Open Lua Source File"))
    if file_open_dlg:Execute() then
        local fc_name = finale.FCString()
        file_open_dlg:GetFileName(fc_name)
        local popup = global_dialog:GetControl("file_list")
        -- ToDo: search for and select if it already exists 
        popup:AddString(fc_name.LuaString)
        popup:SetSelectedItem(popup:GetCount() - 1)
        on_generate(control)
    end
end

local function on_translate(_control)
end

local function on_plugindef(_control)
end

local function create_dialog()
    local dlg = mixin.FCXCustomLuaWindow()
        :SetTitle("Localization Helper")
    local editor_width = 700
    local editor_height = 300
    local y_separator = 10
    local x_separator = 7
    local button_height = 20
    --script selection
    local curr_y = 0
    dlg:CreatePopup(0, curr_y, "file_list")
        :SetWidth((2 * editor_width) / 3)
    curr_y = curr_y + button_height
    --editor
    curr_y = curr_y + y_separator
    local font = finale.FCFontInfo(utils.win_mac("Consolas", "Menlo"), utils.win_mac(9, 11))
    dlg:CreateTextEditor(0, curr_y, "editor")
        :SetWidth(editor_width)
        :SetHeight(editor_height)
        :SetUseRichText(false)
        :SetAutomaticEditing(false)
        :SetFont(font)
        :SetConvertTabsToSpaces(#tab_str)
        :SetAutomaticallyIndent(true)
    curr_y = curr_y + editor_height
    -- command buttons
    curr_y = curr_y + y_separator
    dlg:CreateButton(0, curr_y, "open")
        :SetText("Open Script")
        :DoAutoResizeWidth()
        :AddHandleCommand(on_open)
    dlg:CreateButton(0, curr_y, "generate")
        :SetText("Generate Table")
        :DoAutoResizeWidth()
        :AssureNoHorizontalOverlap(dlg:GetControl("open"), x_separator)
        :AddHandleCommand(on_generate)
    dlg:CreateButton(0, curr_y, "translate")
        :SetText("Translate Table")
        :DoAutoResizeWidth()
        :AssureNoHorizontalOverlap(dlg:GetControl("generate"), x_separator)
        :AddHandleCommand(on_translate)
    dlg:CreateButton(0, curr_y, "plugindef")
        :SetText("Localize Plugindef")
        :DoAutoResizeWidth()
        :AssureNoHorizontalOverlap(dlg:GetControl("translate"), x_separator)
        :AddHandleCommand(on_plugindef)
    dlg:CreateCloseButton(0, curr_y)
        :HorizontallyAlignRightWith(dlg:GetControl("editor"))
    -- registrations
    -- return
    return dlg
end

local function localization_tool()
    global_dialog = global_dialog or create_dialog()
    global_dialog:RunModeless()
end

localization_tool()
