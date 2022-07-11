function plugindef()finaleplugin.Author="Robert Patterson"finaleplugin.Copyright="CC0 https://creativecommons.org/publicdomain/zero/1.0/"finaleplugin.Version="1.0"finaleplugin.Date="February 28, 2020"finaleplugin.CategoryTags="Articulation"finaleplugin.MinFinaleVersionRaw=0x1a000000;finaleplugin.MinJWLuaVersion=0.58;finaleplugin.Notes=[[
This script resets all selected articulations to their default positions. Due to complications arising from
how Finale stored articulation positions before Finale 26, it requires Finale 26 or higher. Due to issues around
maintaining the context for automatic stacking, it must be run under RGP Lua. JW Lua does not have the necessary
logic to manage the stacking context.
    ]]return"Reset Articulation Positions","Reset Articulation Positions","Resets the position of all selected articulations."end;function articulation_reset_positioning()for a in eachentry(finenv.Region())do local b=a:CreateArticulations()for c in each(b)do local d=c:CreateArticulationDef()c:ResetPos(d)c:Save()end end end;articulation_reset_positioning()