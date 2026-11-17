-- From each planet's population text (Thrawn's TEXT_PLANET_INFO_<PLANET>_POPULATION) matched to Thrawn's ground
-- companies:
--   DiplomacyNatives.lua: planet -> native ground units. A species' own Partisan squad is preferred; other
--   matching companies are used only when there is none (at most 2). Elite and hero units are excluded.
--   DiplomacyRebels.lua: planet -> weighted rebel infantry for rebellion battles (a name repeated = more likely):
--   the world's native species most of all (one native species: nearly all of them), its immigrant species,
--   humans and mixed urban partisans. Tuskens never join; Jawas and Ewoks rarely. Only Partisan squads.
local lib = gen.load("lib")

local DIR = "Scripts\\Library\\eawx-plugins\\diplomacy\\"
local ELITE = {"elite", "royal", "honor", "bodyguard", "assassin", "influence", "commander", "hero", "dummy", "skirmish"}
local NOT_NATIVE = {other = true, others = true, various = true, none = true, unknown = true, human = true,
                    humans = true, ["near-human"] = true}
local NOT_SPECIES = {other = true, others = true, various = true, none = true, unknown = true}
local NEVER_REBEL = {"tusken"}
local RARELY_REBEL = {"jawa", "ewok"}

local function has_any(s, words)
    for _, w in ipairs(words) do
        if s:find(w, 1, true) then return true end
    end
    return false
end

local function letters(s)
    return (s:lower():gsub("[^a-z]", ""))
end

local seen, companies = {}, {}
for _, path in ipairs(gen.list(0, "XML", "*.xml", "walk")) do
    for name in gen.read(0, path):gmatch('<GroundCompany Name="([^"]+)"') do
        if not seen[name] then
            seen[name] = true
            companies[#companies + 1] = name
        end
    end
end
table.sort(companies)

-- the species after "Native:" / "Demonym:" / "Immigrated:" on the text's lines (a literal backslash-n
-- separates them), notes in brackets dropped
local function species_of(text, labels, skip)
    local found = {}
    for _, l in ipairs(labels) do found[l] = {} end
    text = text:gsub("\\n", "\n")
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        local line = lib.strip(raw)
        local low = line:lower()
        for _, label in ipairs(labels) do
            if low:sub(1, #label) == label then
                for part in (line:sub(#label + 1) .. "|"):gmatch("([^|]*)|") do
                    local sp = lib.strip((part:gsub("%(.-%)", "")))
                    if sp ~= "" and not skip[sp:lower()] then
                        local list = found[label]
                        list[#list + 1] = sp
                    end
                end
            end
        end
    end
    return found
end

local plain = {}
for _, c in ipairs(companies) do
    if not has_any(c:lower(), ELITE) then
        plain[#plain + 1] = {c, letters(c)}
    end
end
local partisans = {}
for _, c in ipairs(plain) do
    if c[1]:lower():sub(1, 9) == "partisan_" then
        partisans[#partisans + 1] = c
    end
end

local function key(species)
    local k = letters(species)
    return #k > 6 and k:sub(1, 6) or k
end

local function squad(species)
    local k = key(species)
    if #k < 4 or has_any(k, NEVER_REBEL) then
        return nil
    end
    for _, c in ipairs(partisans) do
        if c[2]:find(k, 1, true) then return c[1] end
    end
    return nil
end

local natives, rebels = {}, {}
for _, k in ipairs(gen.text_keys()) do
    local planet = k:match("^TEXT_PLANET_INFO_(.+)_POPULATION$")
    if planet then
        planet = planet:upper()
        local value = gen.text(k) or ""
        -- native units
        local units, have = {}, {}
        for _, species in ipairs(species_of(value, {"native:"}, NOT_NATIVE)["native:"]) do
            local sk = key(species)
            if #sk >= 4 then
                local found, from_partisans = {}, {}
                for _, c in ipairs(plain) do
                    if c[2]:find(sk, 1, true) then
                        found[#found + 1] = c[1]
                        if c[1]:lower():sub(1, 9) == "partisan_" then
                            from_partisans[#from_partisans + 1] = c[1]
                        end
                    end
                end
                local pick = #from_partisans > 0 and from_partisans or {found[1], found[2]}
                for _, c in ipairs(pick) do
                    if c and not have[c] then
                        have[c] = true
                        units[#units + 1] = c
                    end
                end
            end
        end
        if #units > 0 then natives[planet] = units end
        -- rebels
        local s = species_of(value, {"native:", "demonym:", "immigrated:"}, NOT_SPECIES)
        -- natives and demonyms in the order their lines come
        local native_list = {}
        for line in (value:gsub("\\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
            local low = lib.strip(line):lower()
            for _, label in ipairs({"native:", "demonym:"}) do
                if low:sub(1, #label) == label then
                    for _, sp in ipairs(species_of(line, {label}, NOT_SPECIES)[label]) do
                        native_list[#native_list + 1] = sp
                    end
                end
            end
        end
        local list = {}
        local native_squads, distinct, distinct_n = {}, {}, 0
        for _, sp in ipairs(native_list) do
            local q = squad(sp)
            if q then
                native_squads[#native_squads + 1] = q
                if not distinct[q] then distinct[q] = true distinct_n = distinct_n + 1 end
            end
        end
        local native_weight = distinct_n == 1 and 8 or 4
        for _, q in ipairs(native_squads) do
            for _ = 1, has_any(q:lower(), RARELY_REBEL) and 1 or native_weight do list[#list + 1] = q end
        end
        for _, sp in ipairs(s["immigrated:"]) do
            local q = squad(sp)
            if q then
                for _ = 1, has_any(q:lower(), RARELY_REBEL) and 1 or 2 do list[#list + 1] = q end
            end
        end
        local humans = false
        for _, sp in ipairs(native_list) do
            if sp:lower():sub(1, 5) == "human" then humans = true end
        end
        for _, sp in ipairs(s["immigrated:"]) do
            if sp:lower():sub(1, 5) == "human" then humans = true end
        end
        if humans or #native_squads == 0 then
            for _, q in ipairs({"Partisan_Human_Squad", "Partisan_Human_Squad", "Partisan_Mixed_Urban_Squad",
                                "Partisan_Mixed_Urban_Squad"}) do
                list[#list + 1] = q
            end
        end
        if #list > 0 then rebels[planet] = list end
    end
end

local function quoted(units)
    local q = {}
    for i, u in ipairs(units) do q[i] = '"' .. u .. '"' end
    return table.concat(q, ", ")
end

local lines = {"return {"}
for _, planet in ipairs(lib.sorted_keys(natives)) do
    lines[#lines + 1] = "    " .. planet .. " = {" .. quoted(natives[planet]) .. "},"
end
lines[#lines + 1] = "}"
local rebel_lines = {"return {"}
for _, planet in ipairs(lib.sorted_keys(rebels)) do
    if planet:find("^[A-Z_][A-Z0-9_]*$") then
        rebel_lines[#rebel_lines + 1] = "    " .. planet .. " = {" .. quoted(rebels[planet]) .. "},"
    end
end
rebel_lines[#rebel_lines + 1] = "}"

local function ascii(s)
    return (s:gsub("[\128-\255]+", function(run)
        local n = 0
        for _ in utf8.codes(run, true) do n = n + 1 end
        return string.rep("?", n)
    end))
end

local count_natives, count_rebels = 0, 0
for _ in pairs(natives) do count_natives = count_natives + 1 end
for _ in pairs(rebels) do count_rebels = count_rebels + 1 end
return {
    [DIR .. "DiplomacyNatives.lua"] = ascii(lib.lines(lines)),
    [DIR .. "DiplomacyRebels.lua"] = ascii(lib.lines(rebel_lines)),
    count = {count_natives, count_rebels},
}
