local a,b,c,d=(function(e)local f={[{}]=true}local g;local h={}local require;local i={}g=function(j,k)if not h[j]then h[j]=k end end;require=function(j)local l=i[j]if l then if l==f then return nil end else if not h[j]then if not e then local m=type(j)=='string'and'\"'..j..'\"'or tostring(j)error('Tried to require '..m..', but no such module has been registered')else return e(j)end end;i[j]=f;l=h[j](require,i,g,h)i[j]=l end;return l end;return require,i,g,h end)(require)c("__root",function(require,n,c,d)function plugindef()finaleplugin.RequireSelection=false;finaleplugin.HandlesUndo=true;finaleplugin.Author="Robert Patterson"finaleplugin.Copyright="CC0 https://creativecommons.org/publicdomain/zero/1.0/"finaleplugin.Version="1.1"finaleplugin.Date="January 20, 2022"finaleplugin.CategoryTags="Pitch"finaleplugin.Notes=[[
        This script transposes the selected region by a chromatic interval. It works correctly even with
        microtone scales defined by custom key signatures.

        Normally the script opens a modeless window. However, if you invoke the plugin with a shift, option, or
        alt key pressed, it skips opening a window and uses the last settings you entered into the window.
        (This works with RGP Lua version 0.60 and higher.)

        If you are using custom key signatures with JW Lua or an early version of RGP Lua, you must create
        a custom_key_sig.config.txt file in a folder called `script_settings` within the same folder as the script.
        It should contains the following two lines that define the custom key signature you are using. Unfortunately,
        the JW Lua and early versions of RGP Lua do not allow scripts to read this information from the Finale document.

        (This example is for 31-EDO.)

        ```
        number_of_steps = 31
        diatonic_steps = {0, 5, 10, 13, 18, 23, 28}
        ```

        Later versions of RGP Lua (0.58 or higher) ignore this configuration file (if it exists) and read the correct
        information from the Finale document.
    ]]return"Transpose Chromatic...","Transpose Chromatic","Chromatic transposition of selected region (supports microtone systems)."end;if not finenv.RetainLuaState then interval_names={"Perfect Unison","Augmented Unison","Diminished Second","Minor Second","Major Second","Augmented Second","Diminished Third","Minor Third","Major Third","Augmented Third","Diminished Fourth","Perfect Fourth","Augmented Fourth","Diminished Fifth","Perfect Fifth","Augmented Fifth","Diminished Sixth","Minor Sixth","Major Sixth","Augmented Sixth","Diminished Seventh","Minor Seventh","Major Seventh","Augmented Seventh","Diminished Octave","Perfect Octave"}interval_disp_alts={{0,0},{0,1},{1,-2},{1,-1},{1,0},{1,1},{2,-2},{2,-1},{2,0},{2,1},{3,-1},{3,0},{3,1},{4,-1},{4,0},{4,1},{5,-2},{5,-1},{5,0},{5,1},{6,-2},{6,-1},{6,0},{6,1},{7,-1},{7,0}}context={direction=nil,interval_index=nil,simplify=nil,plus_octaves=nil,preserve_originals=nil,window_pos_x=nil,window_pos_y=nil}end;direction_choice=nil;interval_choice=nil;do_simplify=nil;plus_octaves=nil;do_preserve=nil;global_dialog=nil;local o=false;if not finenv.IsRGPLua then local p=finale.FCString()p:SetRunningLuaFolderPath()package.path=package.path..";"..p.LuaString.."?.lua"end;local q=require("library.transposition")local r=require("library.note_entry")function add_strings_to_control(s,t)local u=finale.FCString()for v,w in pairs(t)do u.LuaString=w;s:AddString(u)end end;function create_dialog_box()local u=finale.FCString()local x=finale.FCCustomLuaWindow()u.LuaString="Transpose Chromatic"x:SetTitle(u)local y=0;local z=26;local A=85;local B=x:CreateStatic(0,y+2)u.LuaString="Direction:"B:SetText(u)direction_choice=x:CreatePopup(A,y)add_strings_to_control(direction_choice,{"Up","Down"})direction_choice:SetWidth(A)if context.direction and context.direction<0 then direction_choice:SetSelectedItem(1)end;y=y+z;B=x:CreateStatic(0,y+2)u.LuaString="Interval:"B:SetText(u)interval_choice=x:CreatePopup(A,y)add_strings_to_control(interval_choice,interval_names)interval_choice:SetWidth(140)if context.interval_index then interval_choice:SetSelectedItem(context.interval_index-1)end;y=y+z;do_simplify=x:CreateCheckbox(0,y+2)u.LuaString="Simplify Spelling"do_simplify:SetText(u)do_simplify:SetWidth(140)if context.simplify then do_simplify:SetCheck(1)end;y=y+z;B=x:CreateStatic(0,y+2)u.LuaString="Plus Octaves:"B:SetText(u)local C=A;if finenv.UI():IsOnMac()then C=C+4 end;plus_octaves=x:CreateEdit(C,y)if context.plus_octaves and 0~=context.plus_octaves then u.LuaString=""u:AppendInteger(context.plus_octaves)plus_octaves:SetText(u)end;y=y+z;do_preserve=x:CreateCheckbox(0,y+2)u.LuaString="Preserve Existing Notes"do_preserve:SetText(u)do_preserve:SetWidth(140)if context.preserve_originals then do_preserve:SetCheck(1)end;y=y+z;x:CreateOkButton()x:CreateCancelButton()if x.OkButtonCanClose then x.OkButtonCanClose=o end;return x end;function do_transpose_chromatic(D,E,F,plus_octaves,G)if finenv.Region():IsEmpty()then return end;local H=D*interval_disp_alts[E][1]local I=D*interval_disp_alts[E][2]plus_octaves=D*plus_octaves;local J="Transpose Chromatic "..tostring(finenv.Region().StartMeasure)if finenv.Region().StartMeasure~=finenv.Region().EndMeasure then J=J.." - "..tostring(finenv.Region().EndMeasure)end;finenv.StartNewUndoBlock(J,false)local K=true;for L in eachentrysaved(finenv.Region())do local M=L.Count;local N=0;for O in each(L)do if G then N=N+1;if N>M then break end;local P=r.duplicate_note(O)if nil~=P then O=P end end;if not q.chromatic_transpose(O,H,I,F)then K=false end;q.change_octave(O,plus_octaves)end end;if finenv.EndUndoBlock then finenv.EndUndoBlock(true)finenv.Region():Redraw()else finenv.StartNewUndoBlock(J,true)end;if not K then finenv.UI():AlertError("Finale is unable to represent some of the transposed pitches. These pitches were left at their original value.","Transposition Error")end;return K end;function get_values_from_dialog()local D=1;if direction_choice:GetSelectedItem()>0 then D=-1 end;return D,1+interval_choice:GetSelectedItem(),0~=do_simplify:GetCheck(),plus_octaves:GetInteger(),0~=do_preserve:GetCheck()end;function on_ok()local D,E,F,plus_octaves,G=get_values_from_dialog()do_transpose_chromatic(D,E,F,plus_octaves,G)end;function on_close()if global_dialog:QueryLastCommandModifierKeys(finale.CMDMODKEY_ALT)or global_dialog:QueryLastCommandModifierKeys(finale.CMDMODKEY_SHIFT)then finenv.RetainLuaState=false else context.direction,context.interval_index,context.simplify,context.plus_octaves,context.preserve_originals=get_values_from_dialog()global_dialog:StorePosition()context.window_pos_x=global_dialog.StoredX;context.window_pos_y=global_dialog.StoredY end end;function transpose_chromatic()o=finenv.QueryInvokedModifierKeys and(finenv.QueryInvokedModifierKeys(finale.CMDMODKEY_ALT)or finenv.QueryInvokedModifierKeys(finale.CMDMODKEY_SHIFT))if o and nil~=context.interval_index then do_transpose_chromatic(context.direction,context.interval_index,context.simplify,context.plus_octaves,context.preserve_originals)return end;global_dialog=create_dialog_box()if nil~=context.window_pos_x and nil~=context.window_pos_y then global_dialog:StorePosition()global_dialog:SetRestorePositionOnlyData(context.window_pos_x,context.window_pos_y)global_dialog:RestorePosition()end;global_dialog:RegisterHandleOkButtonPressed(on_ok)if global_dialog.RegisterCloseWindow then global_dialog:RegisterCloseWindow(on_close)end;if finenv.IsRGPLua then if nil~=finenv.RetainLuaState then finenv.RetainLuaState=true end;finenv.RegisterModelessDialog(global_dialog)global_dialog:ShowModeless()else if finenv.Region():IsEmpty()then finenv.UI():AlertInfo("Please select a music region before running this script.","Selection Required")return end;global_dialog:ExecuteModal(nil)end end;transpose_chromatic()end)c("library.note_entry",function(require,n,c,d)local Q={}function Q.finale_version(R,S,T)local U=bit32.bor(bit32.lshift(math.floor(R),24),bit32.lshift(math.floor(S),20))if T then U=bit32.bor(U,math.floor(T))end;return U end;function Q.group_overlaps_region(V,W)if W:IsFullDocumentSpan()then return true end;local X=false;local Y=finale.FCSystemStaves()Y:LoadAllForRegion(W)for Z in each(Y)do if V:ContainsStaff(Z:GetStaff())then X=true;break end end;if not X then return false end;if V.StartMeasure>W.EndMeasure or V.EndMeasure<W.StartMeasure then return false end;return true end;function Q.group_is_contained_in_region(V,W)if not W:IsStaffIncluded(V.StartStaff)then return false end;if not W:IsStaffIncluded(V.EndStaff)then return false end;return true end;function Q.staff_group_is_multistaff_instrument(V)local _=finale.FCMultiStaffInstruments()_:LoadAll()for a0 in each(_)do if a0:ContainsStaff(V.StartStaff)and a0.GroupID==V:GetItemID()then return true end end;return false end;function Q.get_selected_region_or_whole_doc()local a1=finenv.Region()if a1:IsEmpty()then a1:SetFullDocument()end;return a1 end;function Q.get_first_cell_on_or_after_page(a2)local a3=a2;local a4=finale.FCPage()local a5=false;while a4:Load(a3)do if a4:GetFirstSystem()>0 then a5=true;break end;a3=a3+1 end;if a5 then local a6=finale.FCStaffSystem()a6:Load(a4:GetFirstSystem())return finale.FCCell(a6.FirstMeasure,a6.TopStaff)end;local a7=finale.FCMusicRegion()a7:SetFullDocument()return finale.FCCell(a7.EndMeasure,a7.EndStaff)end;function Q.get_top_left_visible_cell()if not finenv.UI():IsPageView()then local a8=finale.FCMusicRegion()a8:SetFullDocument()return finale.FCCell(finenv.UI():GetCurrentMeasure(),a8.StartStaff)end;return Q.get_first_cell_on_or_after_page(finenv.UI():GetCurrentPage())end;function Q.get_top_left_selected_or_visible_cell()local a1=finenv.Region()if not a1:IsEmpty()then return finale.FCCell(a1.StartMeasure,a1.StartStaff)end;return Q.get_top_left_visible_cell()end;function Q.is_default_measure_number_visible_on_cell(a9,aa,ab,ac)local ad=finale.FCCurrentStaffSpec()if not ad:LoadForCell(aa,0)then return false end;if a9:GetShowOnTopStaff()and aa.Staff==ab.TopStaff then return true end;if a9:GetShowOnBottomStaff()and aa.Staff==ab:CalcBottomStaff()then return true end;if ad.ShowMeasureNumbers then return not a9:GetExcludeOtherStaves(ac)end;return false end;function Q.is_default_number_visible_and_left_aligned(a9,aa,ae,ac,af)if a9.UseScoreInfoForParts then ac=false end;if af and a9:GetShowOnMultiMeasureRests(ac)then if finale.MNALIGN_LEFT~=a9:GetMultiMeasureAlignment(ac)then return false end elseif aa.Measure==ae.FirstMeasure then if not a9:GetShowOnSystemStart()then return false end;if finale.MNALIGN_LEFT~=a9:GetStartAlignment(ac)then return false end else if not a9:GetShowMultiples(ac)then return false end;if finale.MNALIGN_LEFT~=a9:GetMultipleAlignment(ac)then return false end end;return Q.is_default_measure_number_visible_on_cell(a9,aa,ae,ac)end;function Q.update_layout(ag,ah)ag=ag or 1;ah=ah or false;local ai=finale.FCPage()if ai:Load(ag)then ai:UpdateLayout(ah)end end;function Q.get_current_part()local aj=finale.FCParts()aj:LoadAll()return aj:GetCurrent()end;function Q.get_page_format_prefs()local ak=Q.get_current_part()local al=finale.FCPageFormatPrefs()local K=false;if ak:IsScore()then K=al:LoadScore()else K=al:LoadParts()end;return al,K end;function Q.get_smufl_metadata_file(am)if not am then am=finale.FCFontInfo()am:LoadFontPrefs(finale.FONTPREF_MUSIC)end;local an=function(ao,am)local ap=ao.."/SMuFL/Fonts/"..am.Name.."/"..am.Name..".json"return io.open(ap,"r")end;local aq=""if finenv.UI():IsOnWindows()then aq=os.getenv("LOCALAPPDATA")else aq=os.getenv("HOME").."/Library/Application Support"end;local ar=an(aq,am)if nil~=ar then return ar end;local as="/Library/Application Support"if finenv.UI():IsOnWindows()then as=os.getenv("COMMONPROGRAMFILES")end;return an(as,am)end;function Q.is_font_smufl_font(am)if not am then am=finale.FCFontInfo()am:LoadFontPrefs(finale.FONTPREF_MUSIC)end;if finenv.RawFinaleVersion>=Q.finale_version(27,1)then if nil~=am.IsSMuFLFont then return am.IsSMuFLFont end end;local at=Q.get_smufl_metadata_file(am)if nil~=at then io.close(at)return true end;return false end;function Q.simple_input(au,av)local aw=finale.FCString()aw.LuaString=""local u=finale.FCString()local ax=160;function format_ctrl(ay,az,aA,aB)ay:SetHeight(az)ay:SetWidth(aA)u.LuaString=aB;ay:SetText(u)end;title_width=string.len(au)*6+54;if title_width>ax then ax=title_width end;text_width=string.len(av)*6;if text_width>ax then ax=text_width end;u.LuaString=au;local x=finale.FCCustomLuaWindow()x:SetTitle(u)local aC=x:CreateStatic(0,0)format_ctrl(aC,16,ax,av)local aD=x:CreateEdit(0,20)format_ctrl(aD,20,ax,"")x:CreateOkButton()x:CreateCancelButton()function callback(ay)end;x:RegisterHandleCommand(callback)if x:ExecuteModal(nil)==finale.EXECMODAL_OK then aw.LuaString=aD:GetText(aw)return aw.LuaString end end;function Q.is_finale_object(aE)return aE and type(aE)=="userdata"and aE.ClassName and aE.GetClassID and true or false end;function Q.system_indent_set_to_prefs(ae,al)al=al or Q.get_page_format_prefs()local aF=finale.FCMeasure()local aG=ae.FirstMeasure==1;if not aG and aF:Load(ae.FirstMeasure)then if aF.ShowFullNames then aG=true end end;if aG and al.UseFirstSystemMargins then ae.LeftMargin=al.FirstSystemLeft else ae.LeftMargin=al.SystemLeft end;return ae:Save()end;return Q end)c("library.transposition",function(require,n,c,d)local Q={}function Q.finale_version(R,S,T)local U=bit32.bor(bit32.lshift(math.floor(R),24),bit32.lshift(math.floor(S),20))if T then U=bit32.bor(U,math.floor(T))end;return U end;function Q.group_overlaps_region(V,W)if W:IsFullDocumentSpan()then return true end;local X=false;local Y=finale.FCSystemStaves()Y:LoadAllForRegion(W)for Z in each(Y)do if V:ContainsStaff(Z:GetStaff())then X=true;break end end;if not X then return false end;if V.StartMeasure>W.EndMeasure or V.EndMeasure<W.StartMeasure then return false end;return true end;function Q.group_is_contained_in_region(V,W)if not W:IsStaffIncluded(V.StartStaff)then return false end;if not W:IsStaffIncluded(V.EndStaff)then return false end;return true end;function Q.staff_group_is_multistaff_instrument(V)local _=finale.FCMultiStaffInstruments()_:LoadAll()for a0 in each(_)do if a0:ContainsStaff(V.StartStaff)and a0.GroupID==V:GetItemID()then return true end end;return false end;function Q.get_selected_region_or_whole_doc()local a1=finenv.Region()if a1:IsEmpty()then a1:SetFullDocument()end;return a1 end;function Q.get_first_cell_on_or_after_page(a2)local a3=a2;local a4=finale.FCPage()local a5=false;while a4:Load(a3)do if a4:GetFirstSystem()>0 then a5=true;break end;a3=a3+1 end;if a5 then local a6=finale.FCStaffSystem()a6:Load(a4:GetFirstSystem())return finale.FCCell(a6.FirstMeasure,a6.TopStaff)end;local a7=finale.FCMusicRegion()a7:SetFullDocument()return finale.FCCell(a7.EndMeasure,a7.EndStaff)end;function Q.get_top_left_visible_cell()if not finenv.UI():IsPageView()then local a8=finale.FCMusicRegion()a8:SetFullDocument()return finale.FCCell(finenv.UI():GetCurrentMeasure(),a8.StartStaff)end;return Q.get_first_cell_on_or_after_page(finenv.UI():GetCurrentPage())end;function Q.get_top_left_selected_or_visible_cell()local a1=finenv.Region()if not a1:IsEmpty()then return finale.FCCell(a1.StartMeasure,a1.StartStaff)end;return Q.get_top_left_visible_cell()end;function Q.is_default_measure_number_visible_on_cell(a9,aa,ab,ac)local ad=finale.FCCurrentStaffSpec()if not ad:LoadForCell(aa,0)then return false end;if a9:GetShowOnTopStaff()and aa.Staff==ab.TopStaff then return true end;if a9:GetShowOnBottomStaff()and aa.Staff==ab:CalcBottomStaff()then return true end;if ad.ShowMeasureNumbers then return not a9:GetExcludeOtherStaves(ac)end;return false end;function Q.is_default_number_visible_and_left_aligned(a9,aa,ae,ac,af)if a9.UseScoreInfoForParts then ac=false end;if af and a9:GetShowOnMultiMeasureRests(ac)then if finale.MNALIGN_LEFT~=a9:GetMultiMeasureAlignment(ac)then return false end elseif aa.Measure==ae.FirstMeasure then if not a9:GetShowOnSystemStart()then return false end;if finale.MNALIGN_LEFT~=a9:GetStartAlignment(ac)then return false end else if not a9:GetShowMultiples(ac)then return false end;if finale.MNALIGN_LEFT~=a9:GetMultipleAlignment(ac)then return false end end;return Q.is_default_measure_number_visible_on_cell(a9,aa,ae,ac)end;function Q.update_layout(ag,ah)ag=ag or 1;ah=ah or false;local ai=finale.FCPage()if ai:Load(ag)then ai:UpdateLayout(ah)end end;function Q.get_current_part()local aj=finale.FCParts()aj:LoadAll()return aj:GetCurrent()end;function Q.get_page_format_prefs()local ak=Q.get_current_part()local al=finale.FCPageFormatPrefs()local K=false;if ak:IsScore()then K=al:LoadScore()else K=al:LoadParts()end;return al,K end;function Q.get_smufl_metadata_file(am)if not am then am=finale.FCFontInfo()am:LoadFontPrefs(finale.FONTPREF_MUSIC)end;local an=function(ao,am)local ap=ao.."/SMuFL/Fonts/"..am.Name.."/"..am.Name..".json"return io.open(ap,"r")end;local aq=""if finenv.UI():IsOnWindows()then aq=os.getenv("LOCALAPPDATA")else aq=os.getenv("HOME").."/Library/Application Support"end;local ar=an(aq,am)if nil~=ar then return ar end;local as="/Library/Application Support"if finenv.UI():IsOnWindows()then as=os.getenv("COMMONPROGRAMFILES")end;return an(as,am)end;function Q.is_font_smufl_font(am)if not am then am=finale.FCFontInfo()am:LoadFontPrefs(finale.FONTPREF_MUSIC)end;if finenv.RawFinaleVersion>=Q.finale_version(27,1)then if nil~=am.IsSMuFLFont then return am.IsSMuFLFont end end;local at=Q.get_smufl_metadata_file(am)if nil~=at then io.close(at)return true end;return false end;function Q.simple_input(au,av)local aw=finale.FCString()aw.LuaString=""local u=finale.FCString()local ax=160;function format_ctrl(ay,az,aA,aB)ay:SetHeight(az)ay:SetWidth(aA)u.LuaString=aB;ay:SetText(u)end;title_width=string.len(au)*6+54;if title_width>ax then ax=title_width end;text_width=string.len(av)*6;if text_width>ax then ax=text_width end;u.LuaString=au;local x=finale.FCCustomLuaWindow()x:SetTitle(u)local aC=x:CreateStatic(0,0)format_ctrl(aC,16,ax,av)local aD=x:CreateEdit(0,20)format_ctrl(aD,20,ax,"")x:CreateOkButton()x:CreateCancelButton()function callback(ay)end;x:RegisterHandleCommand(callback)if x:ExecuteModal(nil)==finale.EXECMODAL_OK then aw.LuaString=aD:GetText(aw)return aw.LuaString end end;function Q.is_finale_object(aE)return aE and type(aE)=="userdata"and aE.ClassName and aE.GetClassID and true or false end;function Q.system_indent_set_to_prefs(ae,al)al=al or Q.get_page_format_prefs()local aF=finale.FCMeasure()local aG=ae.FirstMeasure==1;if not aG and aF:Load(ae.FirstMeasure)then if aF.ShowFullNames then aG=true end end;if aG and al.UseFirstSystemMargins then ae.LeftMargin=al.FirstSystemLeft else ae.LeftMargin=al.SystemLeft end;return ae:Save()end;return Q end)return a("__root")