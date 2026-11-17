-- Warlord_Residences.xml: a warlord leader who escapes to the capital when the flagship falls over it rules from the
-- surface as a hero that is not a unit (Thrawn's Non_Combat_Hero_Template, as Sate Pestage), one type per leader
-- with the leader's name and portrait; and WarlordResidences.lua: leader unit type -> residence type
-- (DiplomacyWarlordDeath). The major warlords' leaders, then every lore minor warlord's (LeaderTable).
local lib = gen.load("lib")

local _, objects = lib.objects()
if not objects["NON_COMBAT_HERO_TEMPLATE"] then
    error("warlord residences: Non_Combat_Hero_Template is not a Thrawn's Revenge object")
end

local MAJOR = {
    {"ERIADU_AUTHORITY", {"DELVARDUS_BRILLIANT", "DELVARDUS_THALASSA", "DELVARDUS_NIGHT_HAMMER"}},
    {"GREATER_MALDROOD", {"TREUTEN_13X", "TREUTEN_CRIMSON_SUNRISE"}},
    {"GREATER_MALDROOD", {"KOSH_LANCET"}},
    {"ZSINJ_EMPIRE", {"ZSINJ_IRON_FIST_VSD", "ZSINJ_IRON_FIST_EXECUTOR"}},
}
local groups = {}
for _, m in ipairs(MAJOR) do
    groups[#groups + 1] = {faction = m[1], types = m[2]}
end
for _, e in ipairs(gen.load("warlords/factions").entries) do
    if e.leaders and e.leaders[1] then
        groups[#groups + 1] = {faction = "WARLORD_" .. e.key, types = e.leaders}
    end
end

local function name_of(obj)
    local name = gen.text(lib.inherited(obj, "Text_ID"):upper())
    if not name or lib.strip(name) == "" then
        name = (obj:gsub("_", " "))
    end
    return (lib.strip(name):gsub("%s+", " "):gsub('"', "'"))
end

local xml = {'<?xml version="1.0" encoding="utf-8"?>', "<Warlord_Residences>"}
local lua = {"return {"}
local texts = {TEXT_WARLORD_RESIDENCE_DESC = "Escaped to the capital when the flagship fell over it, the warlord "
    .. "rules from the surface now. If the capital falls, so do they."}
local by_leader = {}                    -- one residence per leader's name (shared by their several ships)
local count = 0
for _, g in ipairs(groups) do
    local first = nil
    for _, obj in ipairs(g.types) do
        if objects[obj:upper()] then
            first = first or obj:upper()
        end
    end
    if first then
        local name = name_of(first)
        local key = g.faction .. "|" .. name
        local residence = by_leader[key]
        if not residence then
            count = count + 1
            residence = "Warlord_Residence_" .. count
            by_leader[key] = residence
            local text_id = "TEXT_WARLORD_RESIDENCE_" .. count
            texts[text_id] = name
            xml[#xml + 1] = "\t<HeroUnit Name=\"" .. residence .. "\">\n"
                .. "\t\t<Variant_Of_Existing_Type>Non_Combat_Hero_Template</Variant_Of_Existing_Type>\n"
                .. "\t\t<Text_ID>" .. text_id .. "</Text_ID>\n"
                .. "\t\t<Encyclopedia_Text>TEXT_WARLORD_RESIDENCE_DESC</Encyclopedia_Text>\n"
                .. "\t\t<Icon_Name>" .. lib.inherited(first, "Icon_Name") .. "</Icon_Name>\n"
                .. "\t\t<Affiliation>" .. g.faction .. "</Affiliation>\n"
                .. "\t\t<Build_Cost_Credits>0</Build_Cost_Credits>\n"
                .. "\t\t<Build_Initially_Locked>Yes</Build_Initially_Locked>\n"
                .. "\t</HeroUnit>"
        end
        for _, obj in ipairs(g.types) do
            if obj:upper():find("^[A-Z_][A-Z0-9_]*$") then
                lua[#lua + 1] = "    " .. obj:upper() .. ' = "' .. residence:upper() .. '",'
            end
        end
    end
end
xml[#xml + 1] = "</Warlord_Residences>"
lua[#lua + 1] = "}"

return {
    ["XML\\Warlord_Residences.xml"] = lib.tidy_xml(lib.lines(xml)),
    ["Scripts\\Library\\eawx-plugins\\warlords\\WarlordResidences.lua"] = (lib.lines(lua):gsub("[\128-\255]", "?")),
    texts = texts, count = count,
}
