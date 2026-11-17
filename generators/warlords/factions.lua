-- The lore minor warlords as factions of their own: WarlordFactions.lua (from Thrawn's
-- ProteusWarlordLibrary.lua) and, for the faction registry, one faction block per warlord (Warlord_<KEY>)
-- plus BREAKAWAY_SLOTS blank ones (Breakaway_<n>, named in game when a Moff breaks away), copied from
-- Thrawn's Warlords faction. Also gives the warlords' data to other generators (entries).
local lib = gen.load("lib")

local SKIP = {ZSINJ_REMNANTS = true}     -- Thrawn turns Zsinj's own faction into the remnants
local KEEP_IMPERIAL = {HAMMERS = true}   -- "Imperial" is part of the name, not the realm's
local BREAKAWAY_SLOTS = 6               -- spare factions for Moffs who break away mid-campaign

local function strings(text)
    local out = {}
    for s in text:gmatch('"([^"]*)"') do
        out[#out + 1] = s
    end
    return out
end

local function upper_all(list)
    for i = 1, #list do
        list[i] = list[i]:upper()
    end
    return list
end

-- a field "Name = value" of a warlord's table, up to the next field or the table's end
local function field(body, name)
    local _, e = body:find("\n%s*" .. name .. "%s*=%s*")
    if not e then
        return nil
    end
    local start = e + 1
    local p = start
    while true do
        local nl = body:find("\n", p, true)
        if not nl then
            return nil
        end
        local after = body:match("^%s*()", nl + 1)
        if body:find("^[A-Z][A-Za-z0-9]*%s*=", after) or body:sub(after, after) == "}" then
            return body:sub(start, nl - 1)
        end
        p = nl + 1
    end
end

local function year(body, name)
    local v = body:match(name .. "%s*=%s*(%-?[%d%.]+)")
    return v and tonumber(v)
end

-- [(first start year, NAMES)] of a year-indexed field, read like Thrawn's get_value_per_era
local function by_era(body, name)
    local text = field(body, name)
    if not text then
        return {}
    end
    text = lib.strip(text)
    if not text:find("^{%s*{") then
        return {{0, upper_all(strings(text))}}
    end
    local eras = {{0, upper_all(strings(text:match("^{%s*{([^}]*)}")))}}
    for y, part in text:gmatch("%[(%-?[%d%.]+)%]%s*=%s*{([^}]*)}") do
        eras[#eras + 1] = {tonumber(y), upper_all(strings(part))}
    end
    return eras
end

local library = gen.read(0, "Scripts\\Library\\ProteusWarlordLibrary.lua")
local starts = {}
for s, key, e in library:gmatch('()\n\t\t%["([A-Z_0-9]+)"%]%s*=%s*{()') do
    starts[#starts + 1] = {s, key, e}
end
local entries = {}
for i, st in ipairs(starts) do
    local key = st[2]
    local body = library:sub(st[3], starts[i + 1] and starts[i + 1][1] - 1 or #library)
    if not SKIP[key] then
        local eras = by_era(body, "Planets")
        local planets, seen = {}, {}
        for _, era in ipairs(eras) do
            for _, p in ipairs(era[2]) do
                if not seen[p] then
                    seen[p] = true
                    planets[#planets + 1] = p
                end
            end
        end
        local overrides = {}
        for o in body:gmatch('FactionOverride%d?%s*=%s*"([^"]+)"') do
            overrides[#overrides + 1] = o:upper()
        end
        local leaders = field(body, "LeaderTable")
        local ending = field(body, "LeaderEndingNames")
        local particle = body:match('PlanetParticle%s*=%s*"([^"]+)"')
        entries[#entries + 1] = {
            key = key,
            -- an independent Imperial remnant is a warlord's realm, not "Imperial": Imperial Kashyyyk -> Warlord Kashyyyk
            -- (a name that isn't a place keeps its "Imperial": Imperial Hammers -> Warlord Imperial Hammers)
            display = KEEP_IMPERIAL[key] and "Warlord " .. body:match('FriendlyName%s*=%s*"([^"]+)"')
                or body:match('FriendlyName%s*=%s*"([^"]+)"'):gsub("^Imperial ", "Warlord "),
            planets = planets, eras = eras, heroes = by_era(body, "HeroList"), overrides = overrides,
            start = year(body, "StartYear"), last = year(body, "LastYear"),
            leaders = leaders and upper_all(strings(leaders)) or {},
            title = ending and (strings(ending)[1] or "") or "",
            particle = particle and particle:lower(),
        }
    end
end

-- Python's colorsys.hls_to_rgb
local function hls_to_rgb(h, l, s)
    local function v(m1, m2, hue)
        hue = hue % 1.0
        if hue < 1.0 / 6.0 then
            return m1 + (m2 - m1) * hue * 6.0
        elseif hue < 0.5 then
            return m2
        elseif hue < 2.0 / 3.0 then
            return m1 + (m2 - m1) * (2.0 / 3.0 - hue) * 6.0
        end
        return m1
    end
    local m2 = l <= 0.5 and l * (1.0 + s) or l + s - (l * s)
    local m1 = 2.0 * l - m2
    return v(m1, m2, h + 1.0 / 3.0), v(m1, m2, h), v(m1, m2, h - 1.0 / 3.0)
end

-- evenly spread, fairly muted hues, so the warlords stand apart from each other and from Thrawn's main factions
local function color(index)
    local hue = (index * 0.618034) % 1.0
    local light = ({0.50, 0.60, 0.42})[index % 3 + 1]
    local r, g, b = hls_to_rgb(hue, light, 0.45)
    return {lib.round(r * 255), lib.round(g * 255), lib.round(b * 255)}
end

local factions_xml = gen.read(0, "XML\\Factions.xml")
local template = factions_xml:match('\t<Faction Name="Warlords">.-</Faction>')
local COLOR_TAGS = {"Color", "No_Colorization_Color", "Display_Font_Color", "Selection_Blob_RGBA"}

local function block(name, text_id, c)
    local b = template:gsub('Name="Warlords"', 'Name="' .. name .. '"', 1):gsub("TEXT_FACTION_WARLORDS", text_id)
    local rgba = string.format("%d, %d, %d, 255", c[1], c[2], c[3])
    for _, tag in ipairs(COLOR_TAGS) do
        b = b:gsub("<" .. tag .. ">[^<]*</" .. tag .. ">", function()
            return "<" .. tag .. "> " .. rgba .. " </" .. tag .. ">"
        end)
    end
    return b
end

local function fmt_year(v)
    return v == nil and "nil" or string.format("%g", v)
end

local function quote(items)
    local q = {}
    for i, item in ipairs(items) do
        q[i] = '"' .. item .. '"'
    end
    return "{" .. table.concat(q, ", ") .. "}"
end

local blocks, listed, texts = {}, {}, {}
local lua = {"return {", "    WARLORDS = {"}
for i, e in ipairs(entries) do
    local name, text_id, c = "Warlord_" .. e.key, "TEXT_FACTION_WARLORD_" .. e.key, color(i - 1)
    blocks[#blocks + 1] = block(name, text_id, c)
    listed[#listed + 1] = {name, text_id, e.display, c}
    texts[text_id] = e.display
    local eras, heroes = {}, {}
    for k, era in ipairs(e.eras) do
        eras[k] = string.format("{year = %s, planets = %s}", fmt_year(era[1]), quote(era[2]))
    end
    for k, era in ipairs(e.heroes) do
        heroes[k] = string.format("{year = %s, units = %s}", fmt_year(era[1]), quote(era[2]))
    end
    lua[#lua + 1] = string.format('        {key = "%s", faction = "%s", text = "%s", display = "%s", title = "%s", '
        .. "color = {r = %d, g = %d, b = %d}, start = %s, last = %s, eras = {%s}, heroes = {%s}, overrides = %s, "
        .. "leaders = %s},", e.key, name:upper(), text_id, e.display, e.title, c[1], c[2], c[3], fmt_year(e.start),
        fmt_year(e.last), table.concat(eras, ", "), table.concat(heroes, ", "), quote(e.overrides), quote(e.leaders))
end
lua[#lua + 1] = "    },"
lua[#lua + 1] = "    BREAKAWAY = {"
for n = 1, BREAKAWAY_SLOTS do
    local name, text_id = "Breakaway_" .. n, "TEXT_FACTION_BREAKAWAY_" .. n
    local c = color(#entries + n)
    blocks[#blocks + 1] = block(name, text_id, c)
    listed[#listed + 1] = {name, text_id, "Breakaway Sector", c}
    texts[text_id] = "Breakaway Sector"
    lua[#lua + 1] = string.format('        {faction = "%s", text = "%s"},', name:upper(), text_id)
end
lua[#lua + 1] = "    },"
lua[#lua + 1] = "}"

-- non-ASCII as "?", like the build's ascii encoding
local out = lib.lines(lua):gsub("[\128-\255]", "?")
return {
    ["Scripts\\Library\\eawx-plugins\\warlords\\WarlordFactions.lua"] = out,
    entries = entries, blocks = blocks, listed = listed, texts = texts, breakaway_slots = BREAKAWAY_SLOTS,
}
