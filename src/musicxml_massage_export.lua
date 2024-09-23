function plugindef()
    finaleplugin.RequireDocument = false
    finaleplugin.RequireSelection = false
    finaleplugin.NoStore = true
    finaleplugin.Author = "Robert Patterson"
    finaleplugin.Copyright = "CC0 https://creativecommons.org/publicdomain/zero/1.0/"
    finaleplugin.Version = "1.0"
    finaleplugin.Date = "September 24, 2024"
    finaleplugin.CategoryTags = "Document"
    finaleplugin.MinJWLuaVersion = 0.74
    finaleplugin.Notes = [[
        This script reads a musicxml file exported from Finale and makes modifies it to
        improve the importing into Dorico or MuseScore. The best process is as follows:

        1. Export your document as uncompressed MusicXML.
        2. Run this plugin on the output *.musicxml document.
        3. The massaged file name has " massaged" appended to the file name.
        3. Import the massaged *.musicxml into Dorico or MuseScore.

        Here is a list of some of the changes the script makes:

        - 8va/8vb and 15ma/15mb symbols are extended to include the last note and extended left to include leading grace notes.

        Due to a limitation in the xml parser, all xml processing instructions are removed. These are metadata that neither
        Dorico nor MuseScore use, so their removal should not affect importing into those programs.
    ]]
    return "Massage MusicXML...", "", "Massages the MusicXML for the current open document."
end

local text_extension = ".musicxml"

local function remove_processing_instructions(file_path)
    -- Open the original file for reading
    local input_file <close> = io.open(file_path, "r")
    if not input_file then
        error("Cannot open file: " .. file_path)
    end
    -- Read the contents of the file
    local lines = {}
    for line in input_file:lines() do
        -- Keep the XML declaration (<?xml ... ?>), remove other processing instructions (<?...?>)
        if line:match("^%s*<%?xml") or not line:match("^%s*<%?.*%?>") then
            table.insert(lines, line)
        end
    end
    -- Close the input file
    input_file:close()
    -- Open the file for writing (overwrite the original file)
    local output_file <close> = io.open(file_path, "w")
    if not output_file then
        error("Cannot open file for writing: " .. file_path)
    end
    -- Write the cleaned lines to the file
    for _, line in ipairs(lines) do
        output_file:write(line .. "\n")
    end
    -- Close the output file
    output_file:close()
end

function do_open_dialog(document)
    local path_name = finale.FCString()
    local file_name = finale.FCString()
    local file_path = finale.FCString()
    if document then
        document:GetPath(file_path)
        file_path:SplitToPathAndFile(path_name, file_name)
    end
    local full_file_name = file_name.LuaString
    local extension = finale.FCString(file_name.LuaString)
    extension:ExtractFileExtension()
    if extension.Length > 0 then
        file_name:TruncateAt(file_name:FindLast("." .. extension.LuaString))
    end
    file_name:AppendLuaString(text_extension)
    local open_dialog = finale.FCFileOpenDialog(finenv.UI())
    open_dialog:SetWindowTitle(finale.FCString("Open MusicXML for " .. full_file_name))
    open_dialog:AddFilter(finale.FCString("*" .. text_extension), finale.FCString("MusicXML File"))
    open_dialog:SetInitFolder(path_name)
    open_dialog:SetFileName(file_name)
    open_dialog:AssureFileExtension(text_extension)
    if not open_dialog:Execute() then
        return nil
    end
    local selected_file_name = finale.FCString()
    open_dialog:GetFileName(selected_file_name)
    return selected_file_name.LuaString
end

function fix_octave_shift(xml_measure)
    for xml_direction in xmlelements(xml_measure, "direction") do
        local xml_direction_type = xml_direction:FirstChildElement("direction-type")
        if xml_direction_type then
            local octave_shift = xml_direction_type:FirstChildElement("octave-shift")
            if octave_shift then
                local direction_copy = xml_direction:DeepClone(xml_direction:GetDocument())
                local shift_type = octave_shift:Attribute("type")
                if shift_type == "stop" then
                    local next_note = xml_direction:NextSiblingElement("note")
                    if next_note and not next_note:FirstChildElement("rest") then
                        xml_measure:DeleteChild(xml_direction)
                        xml_measure:InsertAfterChild(next_note, direction_copy)
                    end
                elseif shift_type == "up" or shift_type == "down" then
                    local sign = shift_type == "down" and 1 or -1 -- direction to transpose grace notes
                    local octaves = (octave_shift:IntAttribute("size", 8) - 1) / 7
                    local prev_grace_note
                    local prev_note = xml_direction:PreviousSiblingElement("note")
                    while prev_note do
                        if not prev_note:FirstChildElement("rest") and prev_note:FirstChildElement("grace") then
                            prev_grace_note = prev_note
                            local pitch = prev_note:FirstChildElement("pitch")
                            local octave = pitch and pitch:FirstChildElement("octave")
                            if octave then
                                octave:SetIntText(octave:IntText() + sign*octaves)
                            end
                        else
                            break
                        end
                        prev_note = prev_note:PreviousSiblingElement("note")
                    end
                    if prev_grace_note then
                        xml_measure:DeleteChild(xml_direction)
                        local prev_element = prev_grace_note:PreviousSiblingElement()
                        if prev_element then
                            xml_measure:InsertAfterChild(prev_element, direction_copy)
                        else
                            xml_measure:InsertFirstChild(direction_copy)
                        end
                    end
                end
            end
        end
    end
end

function process_xml(score_partwise)
    for xml_part in xmlelements(score_partwise, "part") do
        for xml_measure in xmlelements(xml_part, "measure") do
            fix_octave_shift(xml_measure)
        end
    end
end

function append_massaged_to_filename(filepath)
    -- Extract the path, filename, and extension
    local path, filename, extension = filepath:match("^(.-)([^\\/]-)%.([^\\/%.]+)$")

    -- Check if the path extraction was successful
    if not path or not filename or not extension then
        error("Invalid file path format")
    end

    -- Construct the new file path with " massaged" appended to the filename
    local new_filepath = path .. filename .. " massaged." .. extension
    return new_filepath
end

function music_xml_massage_export()
    local documents = finale.FCDocuments()
    documents:LoadAll()
    local document = documents:FindCurrent()
    local xml_file = do_open_dialog(document)
    if not xml_file then
        return
    end
    -- tinyxml2 can't parse processing instructions, so remove them
    remove_processing_instructions(xml_file) -- hopefully not necessary forever
    local musicxml = tinyxml2.XMLDocument()
    local result = musicxml:LoadFile(xml_file)
    if result ~= tinyxml2.XML_SUCCESS then
        error("Unable to process " .. xml_file .. ". " .. musicxml:ErrorStr())
        return
    end
    local score_partwise = musicxml:FirstChildElement("score-partwise")
    if not score_partwise then
        error("File " .. xml_file .. " does not appear to be a Finale-exported MusicXML file.")
    end
    process_xml(score_partwise)
    local output_name = append_massaged_to_filename(xml_file)
    musicxml:SaveFile(output_name)
    finenv.UI():AlertInfo("Processed to " .. output_name .. ".", "Processed File")
end

music_xml_massage_export()
