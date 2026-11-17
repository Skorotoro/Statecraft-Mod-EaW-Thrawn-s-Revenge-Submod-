-- The Diplomacy factions, made from Thrawn's faction definitions:
--   FactionNames.lua        faction -> in-game name (Thrawn's ALL_FACTION_TEXTS, else a tidied ID)
--   DiplomacyFactions.lua   playable factions and the minor ones that rule worlds in some campaigns
--   Diplomacy_Factions.xml  vassal factions (one per playable faction, a faded copy of its colour), the
--                           insurgents of rebellion battles, the independent world slots and the minor
--                           warlords' factions (gen/warlords/factions), copied from Thrawn's Independent
--                           Forces / Warlords definitions
--   DiplomacyVassals.lua, DiplomacyInsurgents.lua, DiplomacyWorldFactions.lua
-- Build options (the working build only): player_vassals, single_vassal, extra_factions.
local lib = gen.load("lib")

local DIR = "Scripts\\Library\\eawx-plugins\\diplomacy\\"
local VASSAL_COLOR = "165, 170, 150, 255"
local INSURGENT_COLOR = "205, 95, 60, 255"      -- rust red: the rebels in rebellion battles
local WORLD_SLOTS = 10                          -- independent worlds negotiated with at once (each its own faction)
local COLOR_TAGS = {"Color", "No_Colorization_Color", "Display_Font_Color", "Selection_Blob_RGBA"}

local function ascii(s)
    if not s:find("[\128-\255]") then
        return s
    end
    local out = {}
    for _, c in utf8.codes(s, true) do
        out[#out + 1] = c < 128 and string.char(c) or "?"
    end
    return table.concat(out)
end

-- Python's str.title() on ASCII
local function title(s)
    local prev = false
    return (s:gsub(".", function(c)
        local letter = c:find("%a") ~= nil
        local out = letter and (prev and c:lower() or c:upper()) or c
        prev = letter
        return out
    end))
end

local constants = gen.read(0, "Scripts\\Library\\eawx-mod-icw\\GameConstants.lua")
local factions = {}
for f in constants:match("ALL_FACTIONS_NOT_NEUTRAL%s*=%s*{(.-)}"):gmatch('"([A-Z_]+)"') do
    factions[#factions + 1] = f
end
local known = {}
for f, t in constants:match("ALL_FACTION_TEXTS%s*=%s*{(.-)}"):gmatch('([A-Z_]+)%s*=%s*"([A-Z0-9_]+)"') do
    local value = gen.text(t)
    if value then
        known[f] = value
    end
end
local names = {}
local lines = {"return {"}
for _, f in ipairs(factions) do
    names[f] = known[f] or title(f:gsub("_", " "))
    lines[#lines + 1] = string.format('    %s = "%s",', f, ascii(names[f]):gsub("\\", "\\\\"):gsub('"', '\\"'))
end
lines[#lines + 1] = "}"
local outputs = {[DIR .. "FactionNames.lua"] = lib.lines(lines)}

-- playable factions (the ones the engine's victory rule counts), and the factions no player can choose but
-- that rule worlds in some campaigns (Corellians, Chiss...): the Diplomacy window lists them when they hold worlds
local xml_text = gen.read(0, "XML\\Factions.xml")
local playable, is_playable = {}, {}
for name, body in xml_text:gmatch('<Faction Name="([^"]+)">(.-)</Faction>') do
    if body:lower():find("<is_playable>%s*true%s*</is_playable>") then
        playable[#playable + 1] = name:upper()
        is_playable[name:upper()] = true
    end
end
lines = {"return {", "    PLAYABLE = {"}
for _, f in ipairs(playable) do
    lines[#lines + 1] = "        " .. f .. " = true,"
end
lines[#lines + 1] = "    },"
lines[#lines + 1] = "    MINOR = {"
local NOT_MINOR = {NEUTRAL = true, HOSTILE = true, INDEPENDENT_FORCES = true, WARLORDS = true}
for raw in xml_text:gmatch('<Faction Name="([^"]+)">') do
    local name = raw:upper()
    if not is_playable[name] and not NOT_MINOR[name] then
        lines[#lines + 1] = "        " .. name .. " = true,"
    end
end
lines[#lines + 1] = "    },"
lines[#lines + 1] = "}"
outputs[DIR .. "DiplomacyFactions.lua"] = lib.lines(lines)

local function rgb(color)
    local r, g, b = color:match("^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
    return tonumber(r), tonumber(g), tonumber(b)
end

local function faction_list_lua(list)
    local rows = {"return {"}
    for _, v in ipairs(list) do
        local r, g, b = rgb(v[4])
        rows[#rows + 1] = string.format('    {name = "%s", text = "%s", display = "%s", color = {r = %d, g = %d, b = %d}},',
                                        v[1]:upper(), v[2], v[3], r, g, b)
    end
    rows[#rows + 1] = "}"
    return ascii(lib.lines(rows))
end

if gen.option("player_vassals") then
    -- the old behaviour: vassal worlds become the player's
    outputs[DIR .. "DiplomacyVassals.lua"] = faction_list_lua({})
    outputs.names = names
    return outputs
end

-- Desaturate an "r, g, b, a" colour toward its own grey, a little lighter
local function faded(color)
    local r, g, b, a = color:match("^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
    r, g, b, a = tonumber(r), tonumber(g), tonumber(b), tonumber(a)
    local grey = 0.30 * r + 0.59 * g + 0.11 * b
    local function mix(c)
        return math.max(0, math.min(255, lib.round(c * 0.45 + grey * 0.55 + 20)))
    end
    return string.format("%d, %d, %d, %d", mix(r), mix(g), mix(b), a)
end

local template = xml_text:match('\t<Faction Name="Independent_Forces">.-</Faction>')

local function plain(s)
    return (s:gsub("%%", "%%%%"))
end

local function set_colors(block, color)
    for _, tag in ipairs(COLOR_TAGS) do
        block = block:gsub("<" .. tag .. ">[^<]*</" .. tag .. ">", plain("<" .. tag .. "> " .. color .. " </" .. tag .. ">"))
    end
    return block
end

local function vassal_block(name, text_id, color)
    local block = template:gsub('Name="Independent_Forces"', plain('Name="' .. name .. '"'))
    block = block:gsub("TEXT_FACTION_INDEPENDENT_FORCES", plain(text_id))
    block = block:gsub("<Allies>[^\n]-</Allies>", "<Allies>Neutral</Allies>")
    return set_colors(block, color)
end

local blocks = {vassal_block("Diplomacy_Vassals", "TEXT_FACTION_DIPLOMACY_VASSALS", VASSAL_COLOR)}
local texts = {TEXT_FACTION_DIPLOMACY_VASSALS = "Vassal Worlds"}
local listed = {{"Diplomacy_Vassals", "TEXT_FACTION_DIPLOMACY_VASSALS", "Vassal Worlds", VASSAL_COLOR}}
if not gen.option("single_vassal") then
    for _, f in ipairs(playable) do
        local source
        local low = xml_text:lower()
        local s = low:find('<faction name="' .. f:lower() .. '"', 1, true)
        if s then
            local e = select(2, xml_text:find("</Faction>", s, true))
            source = xml_text:sub(s, e)
        end
        local color = lib.strip(source:match("<Color>([^<]*)</Color>"))
        local text_id = "TEXT_FACTION_DIPLOMACY_VASSALS_" .. f
        -- the Republic's are its associate worlds
        local display = (names[f] or title(f)) .. ((f == "REBEL") and " Associate Worlds" or " Vassals")
        blocks[#blocks + 1] = vassal_block("Diplomacy_Vassals_" .. f, text_id, faded(color))
        texts[text_id] = display
        listed[#listed + 1] = {"Diplomacy_Vassals_" .. f, text_id, display, faded(color)}
    end
end
outputs[DIR .. "DiplomacyVassals.lua"] = faction_list_lua(listed)

-- Rebellion battles: the rebels fight as their own faction, at war with everyone
blocks[#blocks + 1] = vassal_block("Diplomacy_Insurgents", "TEXT_FACTION_DIPLOMACY_INSURGENTS", INSURGENT_COLOR)
local spares = {}
for i = 1, tonumber(gen.option("extra_factions") or 0) do
    -- blank factions, to measure how many factions the engine loads
    spares[#spares + 1] = {string.format("W%03d", i), string.format("TEXT_FACTION_DIPLOMACY_SPARE_%03d", i),
                           "Spare Faction " .. i, VASSAL_COLOR}
    blocks[#blocks + 1] = vassal_block(spares[#spares][1], spares[#spares][2], VASSAL_COLOR)
    texts[spares[#spares][2]] = spares[#spares][3]
end

-- the minor warlords' factions, and the independent world slots: an independent world the player opens
-- negotiations with becomes one (named after the world in game), so every treaty works with it
local warlords = gen.load("warlords/factions")
for _, b in ipairs(warlords.blocks) do
    blocks[#blocks + 1] = b
end
for _, v in ipairs(warlords.listed) do
    spares[#spares + 1] = v
end
for k, v in pairs(warlords.texts) do
    texts[k] = v
end
-- the Pirates (gen/pirates/faction), when that feature is in the build
local has_pirates, pirates = pcall(gen.load, "pirates/faction")
if has_pirates then
    for _, b in ipairs(pirates.blocks) do
        blocks[#blocks + 1] = b
    end
    for _, v in ipairs(pirates.listed) do
        spares[#spares + 1] = v
    end
    for k, v in pairs(pirates.texts) do
        texts[k] = v
    end
end
local world_color = template:match("<Color>%s*([^<]-)%s*</Color>")
local world_lua = {"return {"}
for n = 1, WORLD_SLOTS do
    local name, text_id = "Independent_World_" .. n, "TEXT_FACTION_INDEPENDENT_WORLD_" .. n
    blocks[#blocks + 1] = template:gsub('Name="Independent_Forces"', plain('Name="' .. name .. '"'))
                                  :gsub("TEXT_FACTION_INDEPENDENT_FORCES", plain(text_id))
    spares[#spares + 1] = {name, text_id, "Independent World", world_color}
    texts[text_id] = "Independent World"
    world_lua[#world_lua + 1] = string.format('    {faction = "%s", text = "%s"},', name:upper(), text_id)
end
world_lua[#world_lua + 1] = "}"
outputs[DIR .. "DiplomacyWorldFactions.lua"] = lib.lines(world_lua)

-- every Diplomacy faction names every other one and Independent_Forces: relations the XML leaves undefined
-- ("undefined feelings" in the engine log) stall the scripts that run into them
local own = {}
for _, v in ipairs(listed) do own[#own + 1] = v[1] end
own[#own + 1] = "Diplomacy_Insurgents"
for _, v in ipairs(spares) do own[#own + 1] = v[1] end
for i, block in ipairs(blocks) do
    local others = {}
    for _, n in ipairs(own) do
        if not block:find('Name="' .. n .. '"', 1, true) then
            others[#others + 1] = n
        end
    end
    others[#others + 1] = "Independent_Forces"
    local add = table.concat(others, ", ")
    blocks[i] = block:gsub("(<Enemies>)([^<]*)(</Enemies>)", function(a, list, c)
        list = list:gsub("%s+$", ""):gsub(",+$", "")
        return a .. list .. ", " .. add .. " " .. c
    end)
end
texts.TEXT_FACTION_DIPLOMACY_INSURGENTS = "Insurgents"
local r, g, b = rgb(INSURGENT_COLOR)
outputs[DIR .. "DiplomacyInsurgents.lua"] = string.format(
    'return {name = "DIPLOMACY_INSURGENTS", text = "TEXT_FACTION_DIPLOMACY_INSURGENTS", display = "Insurgents", '
    .. "color = {r = %d, g = %d, b = %d}}\r\n", r, g, b)
outputs["XML\\Diplomacy_Factions.xml"] = lib.tidy_xml('<?xml version="1.0" ?>\r\n<Factions>\r\n'
    .. table.concat(blocks, "\r\n\r\n") .. "\r\n</Factions>\r\n")

-- every faction the registry gains (for the campaigns' AI controllers)
local all = {}
for _, v in ipairs(listed) do all[#all + 1] = v[1] end
all[#all + 1] = "Diplomacy_Insurgents"
for _, v in ipairs(spares) do all[#all + 1] = v[1] end
outputs.names, outputs.texts, outputs.all = names, texts, all
outputs.counts = {#listed, #warlords.listed - warlords.breakaway_slots, warlords.breakaway_slots, WORLD_SLOTS}
return outputs
