-- UnitNames.lua: unit type -> in-game name, from each unit's <Text_ID> in Thrawn's XML (following
-- Variant_Of_Existing_Type) and the English text. Used in messages about units.
local lib = gen.load("lib")

local TAGS = {GroundCompany = true, SpaceUnit = true, UniqueUnit = true, Squadron = true, HeroCompany = true,
              GroundInfantry = true, GroundVehicle = true, HeroUnit = true, TransportUnit = true}

-- Python's str.title() on ASCII
local function title(s)
    local prev_letter = false
    return (s:gsub(".", function(c)
        local letter = c:find("%a") ~= nil
        local out = letter and (prev_letter and c:lower() or c:upper()) or c
        prev_letter = letter
        return out
    end))
end

local objects = {}
for _, path in ipairs(gen.list(0, "XML", "*.xml", "walk")) do
    lib.each_object(gen.read(0, path), function(_, name, body)
        local text_id = body:match("<Text_ID>%s*([^<%s]+)%s*</Text_ID>")
        local parent = body:match("<Variant_Of_Existing_Type>%s*([^<%s]+)%s*</Variant_Of_Existing_Type>")
        objects[name] = {text_id and text_id:upper(), parent and parent:upper()}
    end, TAGS)
end

local names = {}
for name in pairs(objects) do
    local current, seen = name, {}
    while objects[current] and not seen[current] do
        seen[current] = true
        local text_id, parent = objects[current][1], objects[current][2]
        local text = text_id and gen.text(text_id)
        if text and text ~= "" then
            local value = lib.strip(text:match("^[^\n]*"))
            if name:sub(1, 9) == "PARTISAN_" and value:lower():find("partisan", 1, true) then   -- all "Partisan Band"
                local species = name:sub(10):gsub("_SQUAD", ""):gsub("_", " ")
                value = title(species) .. " " .. value
            end
            names[name] = value
            break
        end
        current = parent
    end
end

local lines = {"return {"}
for _, name in ipairs(lib.sorted_keys(names)) do
    local value = names[name]:gsub("\\", ""):gsub('"', "'")
    if value ~= "" and not value:find("[^\32-\126]") then
        lines[#lines + 1] = string.format('    ["%s"] = "%s",', name, value)
    end
end
lines[#lines + 1] = "}"

return {["Scripts\\Library\\eawx-plugins\\diplomacy\\UnitNames.lua"] = lib.lines(lines), count = #lines - 3}
