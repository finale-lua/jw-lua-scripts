local a,b,c,d=(function(e)local f={[{}]=true}local g;local h={}local require;local i={}g=function(j,k)if not h[j]then h[j]=k end end;require=function(j)local l=i[j]if l then if l==f then return nil end else if not h[j]then if not e then local m=type(j)=='string'and'\"'..j..'\"'or tostring(j)error('Tried to require '..m..', but no such module has been registered')else return e(j)end end;i[j]=f;l=h[j](require,i,g,h)i[j]=l end;return l end;return require,i,g,h end)(require)c("__root",function(require,n,c,d)function plugindef()finaleplugin.RequireSelection=true;finaleplugin.Author="Nick Mazuk"finaleplugin.Copyright="CC0 https://creativecommons.org/publicdomain/zero/1.0/"finaleplugin.Version="1.0"finaleplugin.Date="June 7, 2020"finaleplugin.CategoryTags="Pitch"finaleplugin.AuthorURL="https://nickmazuk.com"return"Chord Line - Delete Bottom Note","Chord Line - Delete Bottom Note","Deletes the bottom note of every chord"end;local o=require("library.note_entry")function pitch_entry_delete_bottom_note()for p in eachentrysaved(finenv.Region())do if p.Count>=2 then local q=p:CalcLowestNote(nil)o.delete_note(q)end end end;pitch_entry_delete_bottom_note()end)c("library.note_entry",function(require,n,c,d)local r={}function r.finale_version(s,t,u)local v=bit32.bor(bit32.lshift(math.floor(s),24),bit32.lshift(math.floor(t),20))if u then v=bit32.bor(v,math.floor(u))end;return v end;function r.group_overlaps_region(w,x)if x:IsFullDocumentSpan()then return true end;local y=false;local z=finale.FCSystemStaves()z:LoadAllForRegion(x)for A in each(z)do if w:ContainsStaff(A:GetStaff())then y=true;break end end;if not y then return false end;if w.StartMeasure>x.EndMeasure or w.EndMeasure<x.StartMeasure then return false end;return true end;function r.group_is_contained_in_region(w,x)if not x:IsStaffIncluded(w.StartStaff)then return false end;if not x:IsStaffIncluded(w.EndStaff)then return false end;return true end;function r.staff_group_is_multistaff_instrument(w)local B=finale.FCMultiStaffInstruments()B:LoadAll()for C in each(B)do if C:ContainsStaff(w.StartStaff)and C.GroupID==w:GetItemID()then return true end end;return false end;function r.get_selected_region_or_whole_doc()local D=finenv.Region()if D:IsEmpty()then D:SetFullDocument()end;return D end;function r.get_first_cell_on_or_after_page(E)local F=E;local G=finale.FCPage()local H=false;while G:Load(F)do if G:GetFirstSystem()>0 then H=true;break end;F=F+1 end;if H then local I=finale.FCStaffSystem()I:Load(G:GetFirstSystem())return finale.FCCell(I.FirstMeasure,I.TopStaff)end;local J=finale.FCMusicRegion()J:SetFullDocument()return finale.FCCell(J.EndMeasure,J.EndStaff)end;function r.get_top_left_visible_cell()if not finenv.UI():IsPageView()then local K=finale.FCMusicRegion()K:SetFullDocument()return finale.FCCell(finenv.UI():GetCurrentMeasure(),K.StartStaff)end;return r.get_first_cell_on_or_after_page(finenv.UI():GetCurrentPage())end;function r.get_top_left_selected_or_visible_cell()local D=finenv.Region()if not D:IsEmpty()then return finale.FCCell(D.StartMeasure,D.StartStaff)end;return r.get_top_left_visible_cell()end;function r.is_default_measure_number_visible_on_cell(L,M,N,O)local P=finale.FCCurrentStaffSpec()if not P:LoadForCell(M,0)then return false end;if L:GetShowOnTopStaff()and M.Staff==N.TopStaff then return true end;if L:GetShowOnBottomStaff()and M.Staff==N:CalcBottomStaff()then return true end;if P.ShowMeasureNumbers then return not L:GetExcludeOtherStaves(O)end;return false end;function r.is_default_number_visible_and_left_aligned(L,M,Q,O,R)if L.UseScoreInfoForParts then O=false end;if R and L:GetShowOnMultiMeasureRests(O)then if finale.MNALIGN_LEFT~=L:GetMultiMeasureAlignment(O)then return false end elseif M.Measure==Q.FirstMeasure then if not L:GetShowOnSystemStart()then return false end;if finale.MNALIGN_LEFT~=L:GetStartAlignment(O)then return false end else if not L:GetShowMultiples(O)then return false end;if finale.MNALIGN_LEFT~=L:GetMultipleAlignment(O)then return false end end;return r.is_default_measure_number_visible_on_cell(L,M,Q,O)end;function r.update_layout(S,T)S=S or 1;T=T or false;local U=finale.FCPage()if U:Load(S)then U:UpdateLayout(T)end end;function r.get_current_part()local V=finale.FCParts()V:LoadAll()return V:GetCurrent()end;function r.get_page_format_prefs()local W=r.get_current_part()local X=finale.FCPageFormatPrefs()local Y=false;if W:IsScore()then Y=X:LoadScore()else Y=X:LoadParts()end;return X,Y end;local Z=function(_)local a0=finenv.UI():IsOnWindows()local a1=function(a2,a3)if finenv.UI():IsOnWindows()then return a2 and os.getenv(a2)or""else return a3 and os.getenv(a3)or""end end;local a4=_ and a1("LOCALAPPDATA","HOME")or a1("COMMONPROGRAMFILES")if not a0 then a4=a4 .."/Library/Application Support"end;a4=a4 .."/SMuFL/Fonts/"return a4 end;function r.get_smufl_font_list()local a5={}local a6=function(_)local a4=Z(_)local a7=function()if finenv.UI():IsOnWindows()then return io.popen('dir "'..a4 ..'" /b /ad')else return io.popen('ls "'..a4 ..'"')end end;local a8=function(a9)local aa=finale.FCString()aa.LuaString=a9;return finenv.UI():IsFontAvailable(aa)end;for a9 in a7():lines()do if not a9:find("%.")then a9=a9:gsub(" Bold","")a9=a9:gsub(" Italic","")local aa=finale.FCString()aa.LuaString=a9;if a5[a9]or a8(a9)then a5[a9]=_ and"user"or"system"end end end end;a6(true)a6(false)return a5 end;function r.get_smufl_metadata_file(ab)if not ab then ab=finale.FCFontInfo()ab:LoadFontPrefs(finale.FONTPREF_MUSIC)end;local ac=function(ad,ab)local ae=ad..ab.Name.."/"..ab.Name..".json"return io.open(ae,"r")end;local af=ac(Z(true),ab)if af then return af end;return ac(Z(false),ab)end;function r.is_font_smufl_font(ab)if not ab then ab=finale.FCFontInfo()ab:LoadFontPrefs(finale.FONTPREF_MUSIC)end;if finenv.RawFinaleVersion>=r.finale_version(27,1)then if nil~=ab.IsSMuFLFont then return ab.IsSMuFLFont end end;local ag=r.get_smufl_metadata_file(ab)if nil~=ag then io.close(ag)return true end;return false end;function r.simple_input(ah,ai)local aj=finale.FCString()aj.LuaString=""local ak=finale.FCString()local al=160;function format_ctrl(am,an,ao,ap)am:SetHeight(an)am:SetWidth(ao)ak.LuaString=ap;am:SetText(ak)end;title_width=string.len(ah)*6+54;if title_width>al then al=title_width end;text_width=string.len(ai)*6;if text_width>al then al=text_width end;ak.LuaString=ah;local aq=finale.FCCustomLuaWindow()aq:SetTitle(ak)local ar=aq:CreateStatic(0,0)format_ctrl(ar,16,al,ai)local as=aq:CreateEdit(0,20)format_ctrl(as,20,al,"")aq:CreateOkButton()aq:CreateCancelButton()function callback(am)end;aq:RegisterHandleCommand(callback)if aq:ExecuteModal(nil)==finale.EXECMODAL_OK then aj.LuaString=as:GetText(aj)return aj.LuaString end end;function r.is_finale_object(at)return at and type(at)=="userdata"and at.ClassName and at.GetClassID and true or false end;function r.system_indent_set_to_prefs(Q,X)X=X or r.get_page_format_prefs()local au=finale.FCMeasure()local av=Q.FirstMeasure==1;if not av and au:Load(Q.FirstMeasure)then if au.ShowFullNames then av=true end end;if av and X.UseFirstSystemMargins then Q.LeftMargin=X.FirstSystemLeft else Q.LeftMargin=X.SystemLeft end;return Q:Save()end;function r.calc_script_name(aw)local ax=finale.FCString()if finenv.RunningLuaFilePath then ax.LuaString=finenv.RunningLuaFilePath()else ax:SetRunningLuaFilePath()end;local ay=finale.FCString()ax:SplitToPathAndFile(nil,ay)local v=ay.LuaString;if not aw then v=v:match("(.+)%..+")if not v or v==""then v=ay.LuaString end end;return v end;return r end)return a("__root")