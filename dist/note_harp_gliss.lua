local a,b,c,d=(function(e)local f={[{}]=true}local g;local h={}local require;local i={}g=function(j,k)if not h[j]then h[j]=k end end;require=function(j)local l=i[j]if l then if l==f then return nil end else if not h[j]then if not e then local m=type(j)=='string'and'\"'..j..'\"'or tostring(j)error('Tried to require '..m..', but no such module has been registered')else return e(j)end end;i[j]=f;l=h[j](require,i,g,h)i[j]=l end;return l end;return require,i,g,h end)(require)c("__root",function(require,n,c,d)function plugindef()finaleplugin.RequireSelection=true;finaleplugin.MinFinaleVersion="2012"finaleplugin.Author="Jari Williamsson"finaleplugin.Version="0.01"finaleplugin.Notes=[[
        This script will only process 7-tuplets that appears on staves that has been defined as "Harp" in the Score Manager.
    ]]finaleplugin.CategoryTags="Idiomatic, Note, Plucked Strings, Region, Tuplet, Woodwinds"return"Harp gliss","Harp gliss","Transforms 7-tuplets to harp gliss notation."end;local o=require("library.configuration")local p={stem_length=84,small_note_size=70}o.get_parameters("harp_gliss.config.txt",p)function change_beam_info(q,r)local s=r:CalcStemLength()q.Thickness=0;if r:CalcStemUp()then q.LeftVerticalOffset=q.LeftVerticalOffset+p.stem_length-s else q.LeftVerticalOffset=q.LeftVerticalOffset-p.stem_length+s end end;function change_primary_beam(r)local t=finale.FCPrimaryBeamMods(r)t:LoadAll()if t.Count>0 then local q=t:GetItemAt(0)change_beam_info(q,r)q:Save()else local q=finale.FCBeamMod(false)q:SetNoteEntry(r)change_beam_info(q,r)q:SaveNew()end end;function verify_entries(r,u)local v=finale.FCCurrentStaffSpec()v:LoadForEntry(r)if v.InstrumentUUID~=finale.FFUUID_HARP then return false end;local w=0;local x=r;for y=0,6 do if r==nil then return false end;if r:IsRest()then return false end;if r.Duration>=finale.QUARTER_NOTE then return false end;if r.Staff~=x.Staff then return false end;if r.Layer~=x.Layer then return false end;if r:CalcDots()>0 then return false end;w=w+r.Duration;r=r:Next()end;return w==u:CalcFullSymbolicDuration()end;function get_matching_tuplet(r)local z=r:CreateTuplets()for u in each(z)do if u.SymbolicNumber==7 and verify_entries(r,u)then return u end end;return nil end;function hide_tuplet(u)u.ShapeStyle=finale.TUPLETSHAPE_NONE;u.NumberStyle=finale.TUPLETNUMBER_NONE;u.Visible=false;u:Save()end;function hide_stems(r,u)local A=u:CalcFullReferenceDuration()>=finale.WHOLE_NOTE;for B=0,6 do if B>0 or A then local C=finale.FCCustomStemMod()C:SetNoteEntry(r)C:UseUpStemData(r:CalcStemUp())if C:LoadFirst()then C.ShapeID=0;C:Save()else C.ShapeID=0;C:SaveNew()end end;r=r:Next()end end;function set_noteheads(r,u)for B=0,6 do for D in each(r)do local E=finale.FCNoteheadMod()if B==0 then local F=u:CalcFullReferenceDuration()if F>=finale.WHOLE_NOTE then E.CustomChar=119 elseif F>=finale.HALF_NOTE then E.CustomChar=250 end else E.Resize=p.small_note_size end;E:SaveAt(D)end;r=r:Next()end end;function change_dotted_first_entry(r,u)local F=u:CalcFullReferenceDuration()local G=finale.FCNoteEntry.CalcDotsForDuration(F)local H=r:CalcDots()if G==0 then return end;if G>3 then return end;if H>0 then return end;local I=r:Next()local J=I.Duration/2;for y=1,G do r.Duration=r.Duration+J;I.Duration=I.Duration-J;J=J/2 end end;function harp_gliss()local K=false;for r in eachentrysaved(finenv.Region())do local L=get_matching_tuplet(r)if L then K=true;for B=1,6 do r=r:Next()r.BeamBeat=false end end end;if not K then return end;finale.FCNoteEntry.MarkEntryMetricsForUpdate()for r in eachentrysaved(finenv.Region())do local L=get_matching_tuplet(r)if L then change_dotted_first_entry(r,L)change_primary_beam(r)hide_tuplet(L)hide_stems(r,L)set_noteheads(r,L)end end end;harp_gliss()end)c("library.configuration",function(require,n,c,d)local M={}function M.finale_version(N,O,P)local Q=bit32.bor(bit32.lshift(math.floor(N),24),bit32.lshift(math.floor(O),20))if P then Q=bit32.bor(Q,math.floor(P))end;return Q end;function M.group_overlaps_region(R,S)if S:IsFullDocumentSpan()then return true end;local T=false;local U=finale.FCSystemStaves()U:LoadAllForRegion(S)for V in each(U)do if R:ContainsStaff(V:GetStaff())then T=true;break end end;if not T then return false end;if R.StartMeasure>S.EndMeasure or R.EndMeasure<S.StartMeasure then return false end;return true end;function M.group_is_contained_in_region(R,S)if not S:IsStaffIncluded(R.StartStaff)then return false end;if not S:IsStaffIncluded(R.EndStaff)then return false end;return true end;function M.staff_group_is_multistaff_instrument(R)local W=finale.FCMultiStaffInstruments()W:LoadAll()for X in each(W)do if X:ContainsStaff(R.StartStaff)and X.GroupID==R:GetItemID()then return true end end;return false end;function M.get_selected_region_or_whole_doc()local Y=finenv.Region()if Y:IsEmpty()then Y:SetFullDocument()end;return Y end;function M.get_first_cell_on_or_after_page(Z)local _=Z;local a0=finale.FCPage()local a1=false;while a0:Load(_)do if a0:GetFirstSystem()>0 then a1=true;break end;_=_+1 end;if a1 then local a2=finale.FCStaffSystem()a2:Load(a0:GetFirstSystem())return finale.FCCell(a2.FirstMeasure,a2.TopStaff)end;local a3=finale.FCMusicRegion()a3:SetFullDocument()return finale.FCCell(a3.EndMeasure,a3.EndStaff)end;function M.get_top_left_visible_cell()if not finenv.UI():IsPageView()then local a4=finale.FCMusicRegion()a4:SetFullDocument()return finale.FCCell(finenv.UI():GetCurrentMeasure(),a4.StartStaff)end;return M.get_first_cell_on_or_after_page(finenv.UI():GetCurrentPage())end;function M.get_top_left_selected_or_visible_cell()local Y=finenv.Region()if not Y:IsEmpty()then return finale.FCCell(Y.StartMeasure,Y.StartStaff)end;return M.get_top_left_visible_cell()end;function M.is_default_measure_number_visible_on_cell(a5,a6,a7,a8)local a9=finale.FCCurrentStaffSpec()if not a9:LoadForCell(a6,0)then return false end;if a5:GetShowOnTopStaff()and a6.Staff==a7.TopStaff then return true end;if a5:GetShowOnBottomStaff()and a6.Staff==a7:CalcBottomStaff()then return true end;if a9.ShowMeasureNumbers then return not a5:GetExcludeOtherStaves(a8)end;return false end;function M.is_default_number_visible_and_left_aligned(a5,a6,aa,a8,ab)if a5.UseScoreInfoForParts then a8=false end;if ab and a5:GetShowOnMultiMeasureRests(a8)then if finale.MNALIGN_LEFT~=a5:GetMultiMeasureAlignment(a8)then return false end elseif a6.Measure==aa.FirstMeasure then if not a5:GetShowOnSystemStart()then return false end;if finale.MNALIGN_LEFT~=a5:GetStartAlignment(a8)then return false end else if not a5:GetShowMultiples(a8)then return false end;if finale.MNALIGN_LEFT~=a5:GetMultipleAlignment(a8)then return false end end;return M.is_default_measure_number_visible_on_cell(a5,a6,aa,a8)end;function M.update_layout(ac,ad)ac=ac or 1;ad=ad or false;local ae=finale.FCPage()if ae:Load(ac)then ae:UpdateLayout(ad)end end;function M.get_current_part()local af=finale.FCParts()af:LoadAll()return af:GetCurrent()end;function M.get_page_format_prefs()local ag=M.get_current_part()local ah=finale.FCPageFormatPrefs()local ai=false;if ag:IsScore()then ai=ah:LoadScore()else ai=ah:LoadParts()end;return ah,ai end;local aj=function(ak)local al=finenv.UI():IsOnWindows()local am=function(an,ao)if finenv.UI():IsOnWindows()then return an and os.getenv(an)or""else return ao and os.getenv(ao)or""end end;local ap=ak and am("LOCALAPPDATA","HOME")or am("COMMONPROGRAMFILES")if not al then ap=ap.."/Library/Application Support"end;ap=ap.."/SMuFL/Fonts/"return ap end;function M.get_smufl_font_list()local aq={}local ar=function(ak)local ap=aj(ak)local as=function()if finenv.UI():IsOnWindows()then return io.popen('dir "'..ap..'" /b /ad')else return io.popen('ls "'..ap..'"')end end;local at=function(au)local av=finale.FCString()av.LuaString=au;return finenv.UI():IsFontAvailable(av)end;for au in as():lines()do if not au:find("%.")then au=au:gsub(" Bold","")au=au:gsub(" Italic","")local av=finale.FCString()av.LuaString=au;if aq[au]or at(au)then aq[au]=ak and"user"or"system"end end end end;ar(true)ar(false)return aq end;function M.get_smufl_metadata_file(aw)if not aw then aw=finale.FCFontInfo()aw:LoadFontPrefs(finale.FONTPREF_MUSIC)end;local ax=function(ay,aw)local az=ay..aw.Name.."/"..aw.Name..".json"return io.open(az,"r")end;local aA=ax(aj(true),aw)if aA then return aA end;return ax(aj(false),aw)end;function M.is_font_smufl_font(aw)if not aw then aw=finale.FCFontInfo()aw:LoadFontPrefs(finale.FONTPREF_MUSIC)end;if finenv.RawFinaleVersion>=M.finale_version(27,1)then if nil~=aw.IsSMuFLFont then return aw.IsSMuFLFont end end;local aB=M.get_smufl_metadata_file(aw)if nil~=aB then io.close(aB)return true end;return false end;function M.simple_input(aC,aD)local aE=finale.FCString()aE.LuaString=""local aF=finale.FCString()local aG=160;function format_ctrl(aH,aI,aJ,aK)aH:SetHeight(aI)aH:SetWidth(aJ)aF.LuaString=aK;aH:SetText(aF)end;title_width=string.len(aC)*6+54;if title_width>aG then aG=title_width end;text_width=string.len(aD)*6;if text_width>aG then aG=text_width end;aF.LuaString=aC;local aL=finale.FCCustomLuaWindow()aL:SetTitle(aF)local aM=aL:CreateStatic(0,0)format_ctrl(aM,16,aG,aD)local aN=aL:CreateEdit(0,20)format_ctrl(aN,20,aG,"")aL:CreateOkButton()aL:CreateCancelButton()function callback(aH)end;aL:RegisterHandleCommand(callback)if aL:ExecuteModal(nil)==finale.EXECMODAL_OK then aE.LuaString=aN:GetText(aE)return aE.LuaString end end;function M.is_finale_object(aO)return aO and type(aO)=="userdata"and aO.ClassName and aO.GetClassID and true or false end;function M.system_indent_set_to_prefs(aa,ah)ah=ah or M.get_page_format_prefs()local aP=finale.FCMeasure()local aQ=aa.FirstMeasure==1;if not aQ and aP:Load(aa.FirstMeasure)then if aP.ShowFullNames then aQ=true end end;if aQ and ah.UseFirstSystemMargins then aa.LeftMargin=ah.FirstSystemLeft else aa.LeftMargin=ah.SystemLeft end;return aa:Save()end;function M.calc_script_name(aR)local aS=finale.FCString()if finenv.RunningLuaFilePath then aS.LuaString=finenv.RunningLuaFilePath()else aS:SetRunningLuaFilePath()end;local aT=finale.FCString()aS:SplitToPathAndFile(nil,aT)local Q=aT.LuaString;if not aR then Q=Q:match("(.+)%..+")if not Q or Q==""then Q=aT.LuaString end end;return Q end;return M end)return a("__root")