-- ReinforcementsData.lua: the population value of every space unit (its own or that of the type it is a variant
-- of) and each faction's unit cap in space battles, for the reinforcement timers (a player's ships over the cap
-- stay in the reinforcement pool); the units with an interdiction ability; and the structures (starbases, special structures), which count as forces
-- still in the fight as the units with a population value do.
local lib = gen.load("lib")

local SPACE = {SpaceUnit = true, UniqueUnit = true, Squadron = true, HeroUnit = true, SpaceStructure = true}

local by_tag = lib.objects()
local population = {}
for tag in pairs(SPACE) do
    for name in pairs(by_tag[tag] or {}) do
        local value = tonumber(lib.inherited(name, "Population_Value"))
        if value and value > 0 then
            population[name] = value
        end
    end
end

local structures = {}
for _, tag in ipairs({"StarBase", "SpecialStructure"}) do
    for name in pairs(by_tag[tag] or {}) do
        structures[name] = true
    end
end

-- the units with an interdiction ability (it keeps enemy fleets from retreating, and holds their reinforcements)
local interdictors = {}
for tag in pairs(SPACE) do
    for name, body in pairs(by_tag[tag] or {}) do
        if body:find("<Type>%s*INTERDICT%s*</Type>") then
            interdictors[name] = true
        end
    end
end

-- each space unit's command bar icon, for lists that show a fleet by its biggest ship (Diplomacy's escort chooser)
local icons = {}
for tag in pairs(SPACE) do
    for name in pairs(by_tag[tag] or {}) do
        local icon = lib.inherited(name, "Icon_Name")
        if icon and icon ~= "" and population[name] then
            icons[name] = string.lower(icon)
        end
    end
end

local caps = {}
for name, body in pairs(by_tag.Faction or {}) do
    local cap = tonumber(lib.field(body, "Space_Tactical_Unit_Cap"))
    if cap then
        caps[name] = cap
    end
end

local lines = {"return {", "    POPULATION = {"}
for _, name in ipairs(lib.sorted_keys(population)) do
    lines[#lines + 1] = string.format('        ["%s"] = %d,', name, population[name])
end
lines[#lines + 1] = "    },"
lines[#lines + 1] = "    STRUCTURES = {"
for _, name in ipairs(lib.sorted_keys(structures)) do
    lines[#lines + 1] = string.format('        ["%s"] = true,', name)
end
lines[#lines + 1] = "    },"
lines[#lines + 1] = "    INTERDICTORS = {"
for _, name in ipairs(lib.sorted_keys(interdictors)) do
    lines[#lines + 1] = string.format('        ["%s"] = true,', name)
end
lines[#lines + 1] = "    },"
lines[#lines + 1] = "    CAP = {"
for _, name in ipairs(lib.sorted_keys(caps)) do
    lines[#lines + 1] = string.format('        ["%s"] = %d,', name, caps[name])
end
lines[#lines + 1] = "    },"
lines[#lines + 1] = "}"

local icon_lines = {"return {"}
for _, name in ipairs(lib.sorted_keys(icons)) do
    icon_lines[#icon_lines + 1] = string.format('    ["%s"] = {"%s", %d},', name, icons[name], population[name])
end
icon_lines[#icon_lines + 1] = "}"

return {["Scripts\\Library\\eawx-plugins-gamescoring\\diplomacy-reinforcements\\ReinforcementsData.lua"] = lib.lines(lines),
        ["Scripts\\Library\\eawx-plugins\\diplomacy\\DiplomacyUnitIcons.lua"] = lib.lines(icon_lines),
        count = {#lib.sorted_keys(population), #lib.sorted_keys(caps)}}
