-- The Imperial Court's map data from Thrawn's planets: CourtGeo.lua (position, region, lore sector,
-- credit value, station) and CourtRoutes.lua (hyperlanes).
local lib = gen.load("lib")

local DIR = "Scripts\\Library\\eawx-plugins\\imperial-court\\"

-- worlds that are military bases rather than settled worlds
local MILITARY_BASES = {ORD_PARDRON = true, ORD_VAUG = true, LEVIAN = true, SHADREN = true, DESPAYRE = true,
                        THRAGO = true, TALASEA = true, QAT_CHRYSTAC = true, QUELL = true, REGNANT = true,
                        DOLLA = true, RHEN_VAR = true, HAD_ABBADON = true}
-- regions by the words in a planet's history, in order
local REGIONS = {{"Deep Core", "Deep Core"}, {"Core World", "Core Worlds"}, {"Colonies", "Colonies"},
                 {"Inner Rim", "Inner Rim"}, {"Expansion Region", "Expansion Region"}, {"Mid Rim", "Mid Rim"},
                 {"Outer Rim", "Outer Rim"}, {"Unknown Regions", "Unknown Regions"}, {"Hutt Space", "Hutt Space"}}
-- sector names from the histories: possessive region prefixes dropped, variants joined
local SECTOR_PREFIXES = {"Outer Rim", "Mid Rim", "Inner Rim", "Expansion Region", "Core Worlds", "Kashyyyk Region"}
local SECTOR_SKIP = {["Wild Space"] = true, Spinward = true}
local SECTOR_JOIN = {["Tion Hegemony"] = "Tion", ["Allied Tion"] = "Tion"}

local is_space, is_word, strip = lib.is_space, lib.is_word, lib.strip

local function sector_name(raw)
    raw = strip(raw)
    for _, prefix in ipairs(SECTOR_PREFIXES) do
        if raw:sub(1, #prefix) == prefix then
            local rest = raw:sub(#prefix + 1)
            local first = rest ~= "" and utf8.codepoint(rest, 1) or nil
            local cut = rest:match("^'s?()") or (is_space(first) and #utf8.char(first) + 1)
            if cut then
                raw = strip(rest:sub(cut) .. "x"):sub(1, -2)     -- leading spaces only
                break
            end
        end
    end
    raw = SECTOR_JOIN[raw] or raw
    if SECTOR_SKIP[raw] or raw == "" then
        return nil
    end
    if raw == "Bothan" then
        return "Bothan Space"
    end
    if raw == "Corporate" then
        return "Corporate Sector"
    end
    if raw == "Tion" then
        return "Tion Cluster"
    end
    for _, ending in ipairs({"Reach", "Space", "Centrality", "Territories", "Tion"}) do
        if raw:sub(-#ending) == ending then
            return raw
        end
    end
    return raw .. " Sector"
end

-- "... in / of / within / part of the <one to three capitalised words> Sector": the words, or nil.
-- h is the history as code points.
local function words_then_sector(h, p)
    local ends = {}
    for _ = 1, 3 do
        if not (h[p] and h[p] >= 65 and h[p] <= 90) then
            break
        end
        local q = p + 1
        while is_word(h[q]) or h[q] == 39 or h[q] == 45 do
            q = q + 1
        end
        if q == p + 1 or not is_space(h[q]) then
            break
        end
        p = q + 1
        ends[#ends + 1] = p
    end
    for k = #ends, 1, -1 do
        local at = ends[k]
        if (h[at] == 83 or h[at] == 115) and h[at + 1] == 101 and h[at + 2] == 99 and h[at + 3] == 116
            and h[at + 4] == 111 and h[at + 5] == 114 and not is_word(h[at + 6]) then
            return at
        end
    end
end

local KEYWORDS = {{105, 110}, {111, 102}, {119, 105, 116, 104, 105, 110}, {112, 97, 114, 116, 32, 111, 102}}

local function history_sector(text)
    local h = {}
    for _, c in utf8.codes(text, true) do
        h[#h + 1] = c
    end
    for pos = 1, #h do
        if not is_word(h[pos - 1]) then
            for _, key in ipairs(KEYWORDS) do
                local p = pos
                for i = 1, #key do
                    if h[p] ~= key[i] then
                        p = nil
                        break
                    end
                    p = p + 1
                end
                if p and is_space(h[p]) then
                    while is_space(h[p]) do
                        p = p + 1
                    end
                    if h[p] == 116 and h[p + 1] == 104 and h[p + 2] == 101 and is_space(h[p + 3]) then
                        p = p + 3
                        while is_space(h[p]) do
                            p = p + 1
                        end
                        local stop = words_then_sector(h, p)
                        if stop then
                            return sector_name(utf8.char(table.unpack(h, p, stop - 1)))
                        end
                    end
                end
            end
        end
    end
end

local lanes = lib.lanes()
local planets = lib.objects().Planet or {}
local geo, regions = {}, {}
for name, body in pairs(planets) do
    local x, y = body:match("<Galactic_Position>%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)")
    if x then
        local history = gen.text("TEXT_PLANET_INFO_" .. name .. "_HISTORY") or ""
        for _, region in ipairs(REGIONS) do
            if history:find(region[1], 1, true) then
                regions[name] = region[2]
                break
            end
        end
        local credits = body:match("<Planet_Credit_Value>%s*(%d+)")
        local surface = body:match("<Planet_Surface_Accessible>%s*([%w_]+)")
        surface = surface and surface:lower()
        geo[name] = {x = lib.round(tonumber(x)), y = lib.round(tonumber(y)), sector = history_sector(history),
                     value = credits and math.tointeger(tonumber(credits)) or 0,
                     station = surface == "no" or surface == "false" or MILITARY_BASES[name] == true}
    end
end

-- worlds without a region in their history take the most common one among their neighbours, a tie going
-- to the nearest neighbour's; each round uses only the regions known before it, so the order doesn't matter
local names = lib.sorted_keys(geo)
for _ = 1, 6 do
    local found = {}
    for _, name in ipairs(names) do
        if not regions[name] then
            local count, nearest = {}, {}
            local g = geo[name]
            for _, near in ipairs(lib.sorted_keys(lanes[name] or {})) do
                local region, other = regions[near], geo[near]
                if region then
                    count[region] = (count[region] or 0) + 1
                    local d = other and (other.x - g.x) ^ 2 + (other.y - g.y) ^ 2 or math.huge
                    if not nearest[region] or d < nearest[region] then
                        nearest[region] = d
                    end
                end
            end
            local best
            for _, region in ipairs(REGIONS) do
                local r = region[2]
                if count[r] and (not best or count[r] > count[best]
                                 or (count[r] == count[best] and nearest[r] < nearest[best])) then
                    best = r
                end
            end
            found[name] = best
        end
    end
    for name, region in pairs(found) do
        regions[name] = region
    end
end

local lua = {"return {"}
local named = 0
for _, name in ipairs(names) do
    local g = geo[name]
    if g.sector then
        named = named + 1
    end
    lua[#lua + 1] = string.format('    %s = {x = %d, y = %d, region = "%s", value = %d', name, g.x, g.y,
                                  regions[name] or "Outer Rim", g.value)
        .. (g.sector and string.format(', sector = "%s"', g.sector) or "") .. (g.station and ", station = true" or "")
        .. "},"
end
lua[#lua + 1] = "}"

local routes = {"return {"}
for _, name in ipairs(lib.sorted_keys(lanes)) do
    routes[#routes + 1] = string.format('    %s = "%s",', name, table.concat(lib.sorted_keys(lanes[name]), " "))
end
routes[#routes + 1] = "}"

return {
    [DIR .. "CourtGeo.lua"] = lib.latin1(lib.lines(lua)),
    [DIR .. "CourtRoutes.lua"] = lib.lines(routes),
    count = {#names, named},
}
