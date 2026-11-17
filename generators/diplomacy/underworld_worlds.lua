-- DiplomacyUnderworldWorlds.lua: planet -> why no underworld can form there ("space", "empty" or "base").
-- Space-only regions (no land map), worlds whose population is None/Unknown or extinct, and military bases.
local lib = gen.load("lib")

-- worlds with ground and people that still can't hold an underworld (lore: no civilians to corrupt)
local BASES = {LEVIAN = "base", VALC = "base", REGNANT = "base"}
-- worlds with no population figure that are inhabited in lore
local INHABITED = {DATAR = true, GYMELO = true, MIMBAN = true, QIILURA = true}

local land, every = {}, {}
for _, path in ipairs(gen.list(0, "XML", "Planets*.xml", false)) do
    for raw, body in gen.read(0, path):gmatch('<Planet%s+Name="([^"]+)"(.-)</Planet>') do
        local name = raw:upper()
        every[name] = true
        if body:find("<Land_Tactical_Map>%s*[^<%s]+%s*</Land_Tactical_Map>") then
            land[name] = true
        end
    end
end

local function empty(text)
    text = text:gsub("\\n", "\n")
    local low = lib.strip(text):lower()
    if low == "none" or low == "unknown" or low == "" then
        return true
    end
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local after = line:match("^[^:]*:(.*)$")
        if after then
            for part in (after .. "|"):gmatch("([^|]*)|") do
                local species = lib.strip(part)
                if species ~= "" and not species:lower():find("extinct", 1, true) then
                    return false
                end
            end
        end
    end
    return not text:find("%d")
end

local out, count = {}, 0
for name in pairs(every) do
    local pop = name:find("^[A-Z0-9_]+$") and gen.text("TEXT_PLANET_INFO_" .. name .. "_POPULATION")
    if not land[name] then
        out[name] = "space"
    elseif BASES[name] then
        out[name] = BASES[name]
    elseif pop and not INHABITED[name] and empty(pop) then
        out[name] = "empty"
    end
    if out[name] and out[name] ~= "space" then
        count = count + 1
    end
end

local rows = {"return {"}
for _, name in ipairs(lib.sorted_keys(out)) do
    if name:find("^[A-Z_][A-Z0-9_]*$") then
        rows[#rows + 1] = string.format('    %s = "%s",', name, out[name])
    end
end
rows[#rows + 1] = "}"

return {["Scripts\\Library\\eawx-plugins\\diplomacy\\DiplomacyUnderworldWorlds.lua"] = lib.lines(rows), count = count}
