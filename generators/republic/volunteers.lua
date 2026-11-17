-- Republic_Volunteers.xml and RepublicVolunteers.lua: a member world's own people as a company the Republic can raise
-- there (the laws: the Charter of Sentient Rights for non-human worlds, a Tribal Moot for its own world). Each is
-- Thrawn's partisan squad of the world's native people (TEXT_PLANET_INFO_<PLANET>_POPULATION: "Native: ...") made
-- buildable by the Republic at that one world only, locked until a law opens it. RepublicVolunteers.lua: world ->
-- {type, people}.
local lib = gen.load("lib")

local DIR = "Scripts\\Library\\eawx-plugins\\new-republic\\"
-- peoples who would not take up arms for the Republic, or are no single people
local SKIP = {human = true, hutt = true, mixedurban = true, cultist = true, krath = true, massassi = true,
              rakatan = true, corellian = true, ailonnovaguard = true, mandalorian = true, tuskenraider = true,
              tuskenhunter = true, chiss = true, nightsister = true}
local COST, TIME, TRANSPORT = 260, 12, "Nova_Courier_Landing_Craft_Troops"

local function norm(s)
    return (s:lower():gsub("[^a-z]", ""))
end

local squads = {}
for _, path in ipairs(gen.list(0, "XML", "*.xml", "walk")) do
    for name in gen.read(0, path):gmatch('<GroundCompany Name="([^"]+)"') do
        local people = name:match("^[Pp]artisan_(.+)_[Ss]quad$")
        if people and not SKIP[norm(people)] and not squads[norm(people)] then
            squads[norm(people)] = name
        end
    end
end
if not next(squads) then
    error("republic volunteers: no partisan squads in Thrawn's Revenge")
end

-- every planet's own name (Required_Planets wants it as the XML has it)
local planets = {}
for _, path in ipairs(gen.list(0, "XML", "Planets*.xml", false)) do
    for name in gen.read(0, path):gmatch('<Planet%s+Name="([^"]+)"') do
        planets[name:upper()] = name
    end
end

local found = {}
for _, k in ipairs(gen.text_keys()) do
    local planet = k:match("^TEXT_PLANET_INFO_(.+)_POPULATION$")
    if planet and planets[planet:upper()] then
        local value = (gen.text(k) or ""):gsub("\\n", "\n")
        for raw in (value .. "\n"):gmatch("([^\n]*)\n") do
            local line = lib.strip(raw)
            if line:lower():sub(1, 7) == "native:" then
                for part in (line:sub(8) .. "|"):gmatch("([^|]*)|") do
                    local people = lib.strip((part:gsub("%(.-%)", "")))
                    local squad = squads[norm(people)]
                    if squad and not found[planet:upper()] and not people:lower():find("extinct", 1, true) then
                        found[planet:upper()] = {squad = squad, people = people}
                    end
                end
            end
        end
    end
end

local texts, xml = {}, {'<?xml version="1.0" encoding="utf-8"?>', "<Republic_Volunteers>"}
local lua = {"return {"}
for _, world in ipairs(lib.sorted_keys(found)) do
    local f = found[world]
    local name = "Republic_Volunteers_" .. world
    local text = "TEXT_REPUBLIC_VOLUNTEERS_" .. world
    texts[text] = f.people .. " Volunteers"
    xml[#xml + 1] = "\t<GroundCompany Name=\"" .. name .. "\">\n"
        .. "\t\t<Variant_Of_Existing_Type>" .. f.squad .. "</Variant_Of_Existing_Type>\n"
        .. "\t\t<Text_ID>" .. text .. "</Text_ID>\n"
        .. "\t\t<Affiliation>Rebel</Affiliation>\n"
        .. "\t\t<Build_Cost_Credits>" .. COST .. "</Build_Cost_Credits>\n"
        .. "\t\t<Build_Time_Seconds>" .. TIME .. "</Build_Time_Seconds>\n"
        .. "\t\t<Build_Tab_Land_Units>Yes</Build_Tab_Land_Units>\n"
        .. "\t\t<Build_Initially_Locked>Yes</Build_Initially_Locked>\n"
        .. "\t\t<Tech_Level>0</Tech_Level>\n"
        .. "\t\t<GUI_Row>1</GUI_Row>\n"
        .. "\t\t<Required_Ground_Base_Level>0</Required_Ground_Base_Level>\n"
        .. "\t\t<Required_Star_Base_Level>0</Required_Star_Base_Level>\n"
        .. "\t\t<Required_Special_Structures />\n"
        .. "\t\t<Required_Planets>" .. planets[world] .. "</Required_Planets>\n"
        .. "\t\t<Population_Value>1</Population_Value>\n"
        .. "\t\t<Score_Cost_Credits>40</Score_Cost_Credits>\n"
        .. "\t\t<Company_Transport_Unit>" .. TRANSPORT .. "</Company_Transport_Unit>\n"
        .. "\t</GroundCompany>"
    lua[#lua + 1] = string.format("    %s = {type = %q, people = %q},", world, name, f.people)
end
xml[#xml + 1] = "</Republic_Volunteers>"
lua[#lua + 1] = "}"

local count = 0
for _ in pairs(found) do
    count = count + 1
end

return {
    ["XML\\Republic_Volunteers.xml"] = lib.tidy_xml(lib.lines(xml)),
    [DIR .. "RepublicVolunteers.lua"] = lib.lines(lua),
    texts = texts, count = {count},
}
