-- DiplomacyRebellionData.lua for rebellion battles: planet -> land map (Thrawn's Planets*.xml), the map
-- marker types the rebels can rise at (reinforcement points of every kind), and which companies are vehicles.
local lib = gen.load("lib")

local maps = {}
for _, path in ipairs(gen.list(0, "XML", "Planets*.xml", false)) do
    for raw, body in gen.read(0, path):gmatch('<Planet%s+Name="([^"]+)"(.-)</Planet>') do
        local land = body:match("<Land_Tactical_Map>%s*([^<%s]+)%s*</Land_Tactical_Map>")
        local name = raw:upper()
        if land and name:find("^[A-Z_][A-Z0-9_]*$") and not maps[name] then
            maps[name] = land
        end
    end
end

local markers = {}
for _, path in ipairs(gen.list(0, "XML", "*.xml", false)) do
    for name in gen.read(0, path):gmatch('<Marker%s+Name="(Reinforcement_Point[^"]*)"') do
        markers[name] = true
    end
end

-- ground companies: "H" large vehicle or "V" other vehicle, by their Encyclopedia_Unit_Class
local HEAVY = {"HEAVY_", "MEDIUM_WALKER", "ARTILLERY"}
local VEHICLE = {"VEHICLE", "TANK", "WALKER", "SPEEDER", "GUNSHIP", "SKIFF", "TRANSPORT", "PROBE", "ARTILLERY"}
local function any_of(text, words)
    for _, word in ipairs(words) do
        if text:find(word, 1, true) then
            return true
        end
    end
end
local kinds = {}
local _, any = lib.objects()
for name, obj in pairs(any) do
    if obj[1] == "GroundCompany" and name:find("^[A-Z0-9_]+$") then
        local class = lib.inherited(name, "Encyclopedia_Unit_Class")
        if any_of(class, HEAVY) then
            kinds[name] = "H"
        elseif any_of(class, VEHICLE) then
            kinds[name] = "V"
        end
    end
end

local lines = {"return {", "    MAPS = {"}
for _, name in ipairs(lib.sorted_keys(maps)) do
    lines[#lines + 1] = string.format('        %s = "%s",', name, maps[name])
end
lines[#lines + 1] = "    },"
lines[#lines + 1] = "    MARKERS = {"
for _, name in ipairs(lib.sorted_keys(markers)) do
    lines[#lines + 1] = string.format('        "%s",', name)
end
lines[#lines + 1] = "    },"
lines[#lines + 1] = "    KINDS = {"
for _, name in ipairs(lib.sorted_keys(kinds)) do
    lines[#lines + 1] = string.format('        ["%s"] = "%s",', name, kinds[name])
end
lines[#lines + 1] = "    },"
lines[#lines + 1] = "}"

local maps_n, markers_n = 0, 0
for _ in pairs(maps) do maps_n = maps_n + 1 end
for _ in pairs(markers) do markers_n = markers_n + 1 end
return {["Scripts\\Library\\eawx-plugins\\diplomacy\\DiplomacyRebellionData.lua"] = lib.lines(lines),
        count = {maps_n, markers_n}}
