local a,b,c,d=(function(e)local f={[{}]=true}local g;local h={}local require;local i={}g=function(j,k)if not h[j]then h[j]=k end end;require=function(j)local l=i[j]if l then if l==f then return nil end else if not h[j]then if not e then local m=type(j)=='string'and'\"'..j..'\"'or tostring(j)error('Tried to require '..m..', but no such module has been registered')else return e(j)end end;i[j]=f;l=h[j](require,i,g,h)i[j]=l end;return l end;return require,i,g,h end)(require)c("__root",function(require,n,c,d)function plugindef()finaleplugin.RequireSelection=true;finaleplugin.Author="Carl Vine and Robert Patterson"finaleplugin.Copyright="CC0 https://creativecommons.org/publicdomain/zero/1.0/"finaleplugin.Version="v0.75"finaleplugin.Date="2022/06/06"finaleplugin.AdditionalMenuOptions=[[ Untie Notes ]]finaleplugin.AdditionalUndoText=[[ Untie Notes ]]finaleplugin.AdditionalPrefixes=[[ untie_notes = true ]]finaleplugin.AdditionalDescriptions=[[ Untie all notes in the selected region ]]finaleplugin.MinJWLuaVersion=0.62;finaleplugin.Notes=[[ 
    Ties notes in adjacent entries if matching pitches are available. 
    RGPLua (0.62 and above) creates a companion menu item, UNTIE Notes.
    ]]return"Tie Notes","Tie Notes","Tie suitable notes in the selected region, with matching Untie option"end;untie_notes=untie_notes or false;local o=require("library.tie")local function p()local q=finenv.Region()for r=q.StartSlot,q.EndSlot do local s=q:CalcStaffNumber(r)for t=0,3 do local u=finale.FCNoteEntryLayer(t,s,q.StartMeasure,q.EndMeasure)u:Load()for v in each(u)do if v:IsNote()and q:IsEntryPosWithin(v)then for w in each(v)do if untie_notes then if w.TieBackwards then local x,y=o.calc_tie_span(w,true)if not y or q:IsEntryPosWithin(y.Entry)or not y.Tie then w.TieBackwards=false;finale.FCTieMod(finale.TIEMODTYPE_TIEEND):EraseAt(w)end end;if w.Tie then local z,A,B=o.calc_tie_span(w,false)if not B or q:IsEntryPosWithin(B.Entry)or not B.TieBackwards then w.Tie=false;finale.FCTieMod(finale.TIEMODTYPE_TIESTART):EraseAt(w)end end else local C=o.calc_tied_to(w)if C and q:IsEntryPosWithin(C.Entry)then w.Tie=true;C.TieBackwards=true end end end end end;u:Save()end end end;p()end)c("library.tie",function(require,n,c,d)local D={}function D.finale_version(E,F,G)local H=bit32.bor(bit32.lshift(math.floor(E),24),bit32.lshift(math.floor(F),20))if G then H=bit32.bor(H,math.floor(G))end;return H end;function D.group_overlaps_region(I,q)if q:IsFullDocumentSpan()then return true end;local J=false;local K=finale.FCSystemStaves()K:LoadAllForRegion(q)for L in each(K)do if I:ContainsStaff(L:GetStaff())then J=true;break end end;if not J then return false end;if I.StartMeasure>q.EndMeasure or I.EndMeasure<q.StartMeasure then return false end;return true end;function D.group_is_contained_in_region(I,q)if not q:IsStaffIncluded(I.StartStaff)then return false end;if not q:IsStaffIncluded(I.EndStaff)then return false end;return true end;function D.staff_group_is_multistaff_instrument(I)local M=finale.FCMultiStaffInstruments()M:LoadAll()for N in each(M)do if N:ContainsStaff(I.StartStaff)and N.GroupID==I:GetItemID()then return true end end;return false end;function D.get_selected_region_or_whole_doc()local O=finenv.Region()if O:IsEmpty()then O:SetFullDocument()end;return O end;function D.get_first_cell_on_or_after_page(P)local Q=P;local R=finale.FCPage()local S=false;while R:Load(Q)do if R:GetFirstSystem()>0 then S=true;break end;Q=Q+1 end;if S then local T=finale.FCStaffSystem()T:Load(R:GetFirstSystem())return finale.FCCell(T.FirstMeasure,T.TopStaff)end;local U=finale.FCMusicRegion()U:SetFullDocument()return finale.FCCell(U.EndMeasure,U.EndStaff)end;function D.get_top_left_visible_cell()if not finenv.UI():IsPageView()then local V=finale.FCMusicRegion()V:SetFullDocument()return finale.FCCell(finenv.UI():GetCurrentMeasure(),V.StartStaff)end;return D.get_first_cell_on_or_after_page(finenv.UI():GetCurrentPage())end;function D.get_top_left_selected_or_visible_cell()local O=finenv.Region()if not O:IsEmpty()then return finale.FCCell(O.StartMeasure,O.StartStaff)end;return D.get_top_left_visible_cell()end;function D.is_default_measure_number_visible_on_cell(W,X,Y,Z)local _=finale.FCCurrentStaffSpec()if not _:LoadForCell(X,0)then return false end;if W:GetShowOnTopStaff()and X.Staff==Y.TopStaff then return true end;if W:GetShowOnBottomStaff()and X.Staff==Y:CalcBottomStaff()then return true end;if _.ShowMeasureNumbers then return not W:GetExcludeOtherStaves(Z)end;return false end;function D.is_default_number_visible_and_left_aligned(W,X,a0,Z,a1)if W.UseScoreInfoForParts then Z=false end;if a1 and W:GetShowOnMultiMeasureRests(Z)then if finale.MNALIGN_LEFT~=W:GetMultiMeasureAlignment(Z)then return false end elseif X.Measure==a0.FirstMeasure then if not W:GetShowOnSystemStart()then return false end;if finale.MNALIGN_LEFT~=W:GetStartAlignment(Z)then return false end else if not W:GetShowMultiples(Z)then return false end;if finale.MNALIGN_LEFT~=W:GetMultipleAlignment(Z)then return false end end;return D.is_default_measure_number_visible_on_cell(W,X,a0,Z)end;function D.update_layout(a2,a3)a2=a2 or 1;a3=a3 or false;local a4=finale.FCPage()if a4:Load(a2)then a4:UpdateLayout(a3)end end;function D.get_current_part()local a5=finale.FCParts()a5:LoadAll()return a5:GetCurrent()end;function D.get_page_format_prefs()local a6=D.get_current_part()local a7=finale.FCPageFormatPrefs()local a8=false;if a6:IsScore()then a8=a7:LoadScore()else a8=a7:LoadParts()end;return a7,a8 end;local a9=function(aa)local ab=finenv.UI():IsOnWindows()local ac=function(ad,ae)if finenv.UI():IsOnWindows()then return ad and os.getenv(ad)or""else return ae and os.getenv(ae)or""end end;local af=aa and ac("LOCALAPPDATA","HOME")or ac("COMMONPROGRAMFILES")if not ab then af=af.."/Library/Application Support"end;af=af.."/SMuFL/Fonts/"return af end;function D.get_smufl_font_list()local ag={}local ah=function(aa)local af=a9(aa)local ai=function()if finenv.UI():IsOnWindows()then return io.popen('dir "'..af..'" /b /ad')else return io.popen('ls "'..af..'"')end end;local aj=function(ak)local al=finale.FCString()al.LuaString=ak;return finenv.UI():IsFontAvailable(al)end;for ak in ai():lines()do if not ak:find("%.")then ak=ak:gsub(" Bold","")ak=ak:gsub(" Italic","")local al=finale.FCString()al.LuaString=ak;if ag[ak]or aj(ak)then ag[ak]=aa and"user"or"system"end end end end;ah(true)ah(false)return ag end;function D.get_smufl_metadata_file(am)if not am then am=finale.FCFontInfo()am:LoadFontPrefs(finale.FONTPREF_MUSIC)end;local an=function(ao,am)local ap=ao..am.Name.."/"..am.Name..".json"return io.open(ap,"r")end;local aq=an(a9(true),am)if aq then return aq end;return an(a9(false),am)end;function D.is_font_smufl_font(am)if not am then am=finale.FCFontInfo()am:LoadFontPrefs(finale.FONTPREF_MUSIC)end;if finenv.RawFinaleVersion>=D.finale_version(27,1)then if nil~=am.IsSMuFLFont then return am.IsSMuFLFont end end;local ar=D.get_smufl_metadata_file(am)if nil~=ar then io.close(ar)return true end;return false end;function D.simple_input(as,at)local au=finale.FCString()au.LuaString=""local av=finale.FCString()local aw=160;function format_ctrl(ax,ay,az,aA)ax:SetHeight(ay)ax:SetWidth(az)av.LuaString=aA;ax:SetText(av)end;title_width=string.len(as)*6+54;if title_width>aw then aw=title_width end;text_width=string.len(at)*6;if text_width>aw then aw=text_width end;av.LuaString=as;local aB=finale.FCCustomLuaWindow()aB:SetTitle(av)local aC=aB:CreateStatic(0,0)format_ctrl(aC,16,aw,at)local aD=aB:CreateEdit(0,20)format_ctrl(aD,20,aw,"")aB:CreateOkButton()aB:CreateCancelButton()function callback(ax)end;aB:RegisterHandleCommand(callback)if aB:ExecuteModal(nil)==finale.EXECMODAL_OK then au.LuaString=aD:GetText(au)return au.LuaString end end;function D.is_finale_object(aE)return aE and type(aE)=="userdata"and aE.ClassName and aE.GetClassID and true or false end;function D.system_indent_set_to_prefs(a0,a7)a7=a7 or D.get_page_format_prefs()local aF=finale.FCMeasure()local aG=a0.FirstMeasure==1;if not aG and aF:Load(a0.FirstMeasure)then if aF.ShowFullNames then aG=true end end;if aG and a7.UseFirstSystemMargins then a0.LeftMargin=a7.FirstSystemLeft else a0.LeftMargin=a7.SystemLeft end;return a0:Save()end;function D.calc_script_name(aH)local aI=finale.FCString()if finenv.RunningLuaFilePath then aI.LuaString=finenv.RunningLuaFilePath()else aI:SetRunningLuaFilePath()end;local aJ=finale.FCString()aI:SplitToPathAndFile(nil,aJ)local H=aJ.LuaString;if not aH then H=H:match("(.+)%..+")if not H or H==""then H=aJ.LuaString end end;return H end;return D end)return a("__root")