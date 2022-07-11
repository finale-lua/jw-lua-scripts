function plugindef()finaleplugin.RequireSelection=false;finaleplugin.Author="The JWs: Jacob Winkler & Jari Williamsson"finaleplugin.Version="2.0"finaleplugin.Date="2/2/2022"finaleplugin.CategoryTags="Layout, Measure, Rest"finaleplugin.Notes=[[
   This script takes a region and creates a multimeasure rest with the text 'TACET'
   above as an expression. The font settings for the expression are taken from the 'Tempo' category.
   If the region includes the last measure of the file but NOT the first measure, it will instead
   create an expression that says 'tacet al fine'.

   If you are using RGP Lua 0.6 or above, you can override the default text settings by including
   appropriate values for `tacet_text` and/or `al_fine_text` in the optional field in the RGP Lua
   configuration dialog. The default values are:

   ```
   tacet_text = "TACET"
   al_fine_text = "tacet al fine"
   ```
   ]]return"TACET","Create Tacet","Creates a mm-rest and TACET expression"end;tacet_text=tacet_text or"TACET"local a="TACET for Multimeasure Rests"al_fine_text=al_fine_text or"tacet al fine"local b="'tacet al fine' for Multimeasure Rests"local c=-24;function tacet_mm()local d=false;local e=finenv.Region()if e.StartMeasure>1 and e:IsLastEndMeasure()then d=true end;local f=finale.FCMultiMeasureRestPrefs()f:Load(1)local g=finenv.UI()local h=false;local i=0;if e.StartMeasure==0 then i=g:AlertYesNo("There is no active selection. Would you like to process the current part?","No Selection:")if i==3 then return elseif i==2 then e:SetFullDocument()end end;if f.AutoUpdate then h=g:AlertYesNo("Automatic Update is ON in the multimeasure preferences. Would you like to turn it OFF and proceed?","Unable to create tacet:")if h==3 then return elseif h==2 then f.AutoUpdate=false;f:Save()end end;local j=finale.FCMultiMeasureRests()j:LoadAll()for k in each(j)do if e:IsMeasureIncluded(k.StartMeasure)or e:IsMeasureIncluded(k.EndMeasure)then k:DeleteData()end end;local k=finale.FCMultiMeasureRest()k.StartMeasure=e.StartMeasure;k.EndMeasure=e.EndMeasure;k.NumberHorizontalAdjust=f.NumberHorizontalAdjust;k.NumberVerticalAdjust=f.NumberVerticalAdjust;k.ShapeEndAdjust=f.ShapeEndAdjust;k.ShapeID=f.ShapeID;k.ShapeStartAdjust=f.ShapeStartAdjust;k.StartNumberingAt=20000;k.SymbolSpace=f.SymbolSpace;k.UseSymbols=f.UseSymbols;k.UseSymbolsLessThan=f.UseSymbolsLessThan;k.Width=f.Width;k:Save()finale.FCStaffSystems.UpdateFullLayout()tacet_expr(d)end;function tacet_expr(d)local e=finenv.Region()local l=finale.FCCategoryDef()l:Load(0)local m=finale.DEFAULTCATID_TEMPOMARKS;local n=finale.FCCategoryDef()local o=finale.FCCategoryDef()local p=finale.FCCategoryDefs()local q=finale.FCFontInfo()p:LoadAll()local r=0;local s=finale.FCString()for t in eachbackwards(p)do s.LuaString=string.lower(t:CreateName().LuaString)if s.LuaString=="tacet"then r=t.ID;n=t end end;local u=finale.FCTextExpressionDefs()u:LoadAll()local v=0;local w=finale.FCString()local x=finale.FCString()if d==true then w.LuaString=b else w.LuaString=a end;print(w.LuaString)for y in each(u)do if y:CreateDescription().LuaString==w.LuaString then print("Tacet found at",y.ItemNo)v=y.ItemNo end end;if v==0 then local z=finale.FCTextExpressionDef()local A=""if r==0 then z:AssignToCategory(l)o:Load(m)q=o:CreateTextFontInfo()A="^fontTxt"..q:CreateEnigmaString(finale.FCString()).LuaString;z.HorizontalJustification=1;z.HorizontalAlignmentPoint=5;z.HorizontalOffset=c;z.VerticalAlignmentPoint=3;z.VerticalBaselineOffset=18 else z:AssignToCategory(n)o:Load(r)q=o:CreateTextFontInfo()A="^fontTxt"..q:CreateEnigmaString(finale.FCString()).LuaString end;if d==true then x.LuaString=A..al_fine_text else x.LuaString=A..tacet_text end;z:SetDescription(w)z:SaveNewTextBlock(x)z:SaveNew()v=z.ItemNo;print("New TACET created at",v)end;local B=false;local C=finale.FCExpressions()C:LoadAllForRegion(e)for D in each(C)do local E=D:CreateTextExpressionDef()if E.ItemNo==v then B=true;print("tacet_assigned = ",B)end end;if B==false then local F=finale.FCSystemStaves()F:LoadScrollView()local G=1;for H in each(F)do local I=H.Staff;if G==1 then e:SetStartStaff(H.Staff)G=0 end end;local J=finale.FCSystemStaff()local K=e.StartMeasure;local L=e.StartMeasurePos;local M=finale.FCExpression()local I=e.StartStaff;M:SetStaff(I)M:SetMeasurePos(L)M:SetID(v)local N=finale.FCCell(K,I)M:SaveNewToCell(N)end end;tacet_mm()