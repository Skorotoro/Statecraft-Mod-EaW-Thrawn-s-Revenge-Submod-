-- DiplomacyLandWorlds.lua (every world with a land map) and DiplomacyPopulations.lua (populated world ->
-- population tier: 1 small, 2 millions, 3 billions or more; used for Senate representation). Military bases
-- (no people, or fewer than BASE_POPULATION) are left out: they are territories.
local lib = gen.load("lib")

local DIR = "Scripts\\Library\\eawx-plugins\\diplomacy\\"

-- space-only regions (no land map: no ground, no Senator's Office) are not populated worlds
local land = {}
for _, path in ipairs(gen.list(0, "XML", "Planets*.xml", false)) do
    local text = gen.read(0, path)
    for name, body in text:gmatch('<Planet%s+Name="([^"]+)"(.-)</Planet>') do
        if body:find("<Land_Tactical_Map>%s*[^<%s]+%s*</Land_Tactical_Map>") then
            land[name:upper()] = true
        end
    end
end

local function lua_name(name)
    return name:find("^[A-Z_][A-Z0-9_]*$") ~= nil
end

-- worlds of a few thousand souls (a garrison: Talay's 1 000) are military bases, not populated worlds; from ten
-- thousand (New Alderaan's 60 000 refugees) a world has people of its own
local BASE_POPULATION = 10000

-- the population figure on the text's last line ("2.5 Billion", "1 000"), or nil
local function head_count(value)
    local last = lib.strip((value:gsub("\\n", "\n")):match("([^\n]*)$") or "")
    local low = last:lower()
    if low:find("billion", 1, true) or low:find("trillion", 1, true) or low:find("million", 1, true) then
        return math.huge
    end
    local digits = last:gsub("[%s,%.]", "")
    return digits:find("^%d+$") and tonumber(digits) or nil
end

local tiers = {}
for name in pairs(land) do
    local value = name:find("^[A-Z0-9_]+$") and gen.text("TEXT_PLANET_INFO_" .. name .. "_POPULATION")
    if value then
        local low = lib.strip(value):lower()
        local count = head_count(value)
        if low ~= "none" and low ~= "" and not (count and count < BASE_POPULATION) then
            low = value:lower()
            tiers[name] = (low:find("billion", 1, true) or low:find("trillion", 1, true)) and 3
                          or low:find("million", 1, true) and 2 or 1
        end
    end
end

-- worlds over that figure that lore makes no home: mines, bases, prisons and ruins with no settled people of their own
-- (Kessel's spice mines, Mustafar's mining works, Zsinj's Vergesso yards, the Cron Drift hideouts, Dromund Kaas
-- abandoned, Despayre the destroyed prison world, Levian Two the Imperial garrison world, Sarm, Dagobah's empty
-- swamps)
for _, name in ipairs({"KESSEL", "MUSTAFAR", "VERGESSO", "CRON_DRIFT", "DROMUND", "DESPAYRE", "LEVIAN", "SARM", "DAGOBAH"}) do
    tiers[name] = nil
end

-- worlds the population text leaves out that still count as peopled for the Empire's and the Republic's
-- mechanics (farmers and settlers in lore)
for _, name in ipairs({"DANTOOINE", "GENERIS"}) do
    tiers[name] = tiers[name] or 1
end

-- every world with ground (the Hutt underworld needs land, not a population figure: Hypori has none)
local rows = {"return {"}
for _, name in ipairs(lib.sorted_keys(land)) do
    if lua_name(name) then
        rows[#rows + 1] = "    " .. name .. " = true,"
    end
end
rows[#rows + 1] = "}"

local lines = {"return {"}
local count = 0
for _, name in ipairs(lib.sorted_keys(tiers)) do
    count = count + 1
    if lua_name(name) then
        lines[#lines + 1] = string.format("    %s = %d,", name, tiers[name])
    end
end
lines[#lines + 1] = "}"

return {
    [DIR .. "DiplomacyLandWorlds.lua"] = lib.lines(rows),
    [DIR .. "DiplomacyPopulations.lua"] = lib.lines(lines),
    count = count,
}
