local Worlds = {}

local SLOTS = {}
do
    local ok, data = pcall(require, "eawx-plugins/diplomacy/DiplomacyWorldFactions")
    if ok and type(data) == "table" then
        SLOTS = data
    end
end
local BY_NAME = {}
for _, slot in ipairs(SLOTS) do
    BY_NAME[slot.faction] = slot
end

function Worlds.is_slot(faction_name)
    return BY_NAME[string.upper(faction_name or "")] ~= nil
end

function Worlds.names()
    local out = {}
    for _, slot in ipairs(SLOTS) do
        table.insert(out, slot.faction)
    end
    return out
end

function Worlds.register()
    local C = ModContentLoader.get("GameConstants")
    local copied = {"ALL_FACTIONS_CAPITALS", "ALL_FACTIONS_BASIC_STRUCTURES", "ALL_FACTIONS_AI",
                    "ALL_FACTIONS_CRUEL_AI", "TRANSPORTS", "PARTICLES", "ALL_FACTION_ABBREVIATIONS",
                    "FACTION_COLORS"}
    for _, slot in ipairs(SLOTS) do
        if C.ALL_FACTION_NAMES then C.ALL_FACTION_NAMES[slot.faction] = "Independent World" end
        if C.ALL_FACTION_TEXTS then C.ALL_FACTION_TEXTS[slot.faction] = slot.text end
        for _, table_name in ipairs(copied) do
            local t = C[table_name]
            if type(t) == "table" and t[slot.faction] == nil then
                t[slot.faction] = t["INDEPENDENT_FORCES"]
            end
        end
    end
end

local function planets_of(player)
    local out = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == player then
            table.insert(out, planet)
        end
    end
    return out
end

function Worlds.world_of(player)
    return planets_of(player)[1]
end

local function name_slot(slot, label)
    local C = ModContentLoader.get("GameConstants")
    if C.ALL_FACTION_NAMES then C.ALL_FACTION_NAMES[slot.faction] = label end
    if C.ALL_FACTION_TEXTS then C.ALL_FACTION_TEXTS[slot.faction] = label end
    if Engine_Set_Text then
        pcall(Engine_Set_Text, slot.text, label)
    end
    if Diplomacy and Diplomacy.rename then
        Diplomacy.rename(slot.faction, label)
    end
end

function Worlds.open(d, planet, sail)
    local owner = planet.Get_Owner().Get_Faction_Name()
    if BY_NAME[owner] then
        return owner
    end
    if owner ~= "INDEPENDENT_FORCES" then
        return nil, "It is no longer independent."
    end
    for _, slot in ipairs(SLOTS) do
        local player = Find_Player(slot.faction)
        if player and table.getn(planets_of(player)) == 0 then
            local independent = Find_Player("INDEPENDENT_FORCES")
            local at_peace = independent and not d.human.Is_Enemy(independent)
            name_slot(slot, d:planet_name(planet))
            d:transfer_world(planet, player, false, nil, sail)
            if at_peace then
                d:set_relation(slot.faction, "CEASEFIRE", nil, true)
            end
            return slot.faction
        end
    end
    return nil, "Too many independent worlds are in talks already."
end

local function bound(d, faction)
    local relation = d.relations and d.relations[faction]
    local independent = Find_Player("INDEPENDENT_FORCES")
    local usual = (independent and not d.human.Is_Enemy(independent)) and "CEASEFIRE" or nil
    if relation ~= nil and relation ~= usual then
        return true
    end
    for _, w in pairs(d.vassal_worlds or {}) do
        if w.slot == faction then
            return true
        end
    end
    if (d.open_borders and d.open_borders[faction]) or (d.pacts and d.pacts[faction]) then
        return true
    end
    local ok, Trade = pcall(require, "eawx-plugins/diplomacy/DiplomacyTrade")
    return ok and type(Trade) == "table" and Trade.partner ~= nil and Trade.partner(d, faction) == true
end

function Worlds.release(d, faction)
    faction = string.upper(faction or "")
    local player = BY_NAME[faction] and Find_Player(faction)
    local independent = Find_Player("INDEPENDENT_FORCES")
    if not player or not independent or bound(d, faction) then
        return false
    end
    local worlds = planets_of(player)
    for _, world in ipairs(worlds) do
        d:transfer_world(world, independent, false)
    end
    if d.relations then
        d.relations[faction] = nil
    end
    return worlds[1] ~= nil
end

function Worlds.capacity(d)
    local used = 0
    for _, slot in ipairs(SLOTS) do
        local player = Find_Player(slot.faction)
        if player and planets_of(player)[1] and bound(d, slot.faction) then
            used = used + 1
        end
    end
    return used, table.getn(SLOTS)
end

return Worlds
