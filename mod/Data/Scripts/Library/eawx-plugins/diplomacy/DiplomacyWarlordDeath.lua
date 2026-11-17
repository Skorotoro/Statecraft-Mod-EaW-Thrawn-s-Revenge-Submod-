local LEADERS = require("eawx-plugins/diplomacy/DiplomacyLeaders")
local Rebellion = require("eawx-plugins/diplomacy/DiplomacyRebellion")

local Death = {}

local GOLD = {r = 255, g = 220, b = 120}
local INDEPENDENT = "INDEPENDENT_FORCES"
local MAJOR = {ERIADU_AUTHORITY = true, GREATER_MALDROOD = true, ZSINJ_EMPIRE = true, IMPERIAL_PROTEUS = true}
local WAIT = 4
local GROUND = {"_TEAM", "WALKER", "AT_TE", "_SKIFF"}

local RESIDENCES = {}
do
    local ok, data = pcall(require, "eawx-plugins/warlords/WarlordResidences")
    if ok and type(data) == "table" then
        RESIDENCES = data
    end
end

local TEXT = {
    ERIADU_AUTHORITY = "Sander Delvardus is dead, and the Eriadu Authority dies with him. Without the Supreme Warlord "
        .. "to bind them, the Seswenna's worlds go their own ways.",
    GREATER_MALDROOD = "The last of the Teradoc brothers is dead. Greater Maldrood, held together by family ambition "
        .. "and crimson paint, comes apart world by world.",
    ZSINJ_EMPIRE = "Warlord Zsinj is dead. His empire was his alone: its worlds, its fleets and its debts scatter with "
        .. "him, and the Quelii sector breathes again.",
    IMPERIAL_PROTEUS = "{leader} is dead, and {name} with them. No heir steps forward; the worlds that knelt go their "
        .. "own way.",
    WARLORD_LAMBDA = "Par Lankin is dead. The Lambda Sector's crown has no head to sit on, and Rintonne's court breaks "
        .. "up overnight.",
    WARLORD_ZERO_COMMAND = "Blitzer Harrsk is dead. Zero Command was his fortress and his alone; its garrisons look "
        .. "for new masters.",
    WARLORD_ELROOD = "Villis Andal is dead. The Elrood Sector's little realm forgets him within the week.",
    WARLORD_ANTEMERIDIAS = "Tol Getelles is dead. The Antemeridian Sector's worlds cast off his rule the moment the "
        .. "news arrives.",
    WARLORD_WILD_SPACE = "Delurin is dead. The Dragon of Wild Space leaves no one to claim his hoard of worlds.",
    WARLORD_PRENTIOCH = "Utoxx Prentioch is dead. His Dominion was a web of oaths sworn to him, and they die with him.",
    WARLORD_SECTOR_5 = "Malfkla Yzu is dead. Sector 5's captains part ways, each sure he deserved the command.",
    WARLORD_PRAKITH = "Foga Brill is dead. Prakith's people tear down the Inquisitor's statues before his body is cold.",
    WARLORD_JARDEEN = "Iolan Gendarr is dead. The Reliance's crews scatter, and Jardeen's worlds answer to no one.",
    WARLORD_CIUTRIC_HEGEMONY = "Delak Krennel is dead. The Ciutric Hegemony was built on his fear and his fleet; with "
        .. "him gone, neither holds.",
    WARLORD_KAMINO = "The Dark Apprentice is dead. The clones of Kamino wake to find no one giving orders.",
    WARLORD_NABOO = "Quarsh Panaka is dead. Naboo and its neighbours return to their own governments.",
    WARLORD_RADAMA = "Ellor Orgraal is dead. Ord Radama's garrisons pack up and go home.",
    WARLORD_TAPANI = "Bal Jaset is dead. The Tapani noble houses he cowed fall back to their old feuds.",
    WARLORD_GAROS = "Zakar is dead. The worlds he squeezed for tribute stop paying at once.",
    WARLORD_MAELSTROM = "Torpin is dead. Maelstrom Command breaks into squabbling squadrons.",
    WARLORD_SHADOWSPAWN = "Cronal is dead. The Shadow Realm's acolytes find their master's visions were all that held "
        .. "them.",
    WARLORD_PROPHETS = "Kadann is dead. The Prophets of the Dark Side argue over what he foresaw, and their worlds "
        .. "stop listening.",
    WARLORD_TAGGE = "Ulric Tagge is dead. The House of Tagge's holdings go to whoever can seize them.",
    WARLORD_TIERFON = "Tzenkens is dead. The Tierfon Sector's command dissolves.",
    WARLORD_BAKURA = "Wilek Nereus is dead. Bakura's people take back their world, and its neighbours follow.",
    WARLORD_BRAK = "Lesan Ramier is dead. The Brak Sector shrugs off his rule.",
    WARLORD_TAMARIN = "Lobax Resuun is dead. The Retribution's crew mutinies, and the Tamarin Sector goes its own way.",
    WARLORD_ISECTOR = "Bliss Shargael is dead. The I-sector's garrisons have no one left to fear.",
    WARLORD_IMPERIAL_LIANNA = "Phillip Santhe is dead. Lianna's shipyards and the worlds around them choose new "
        .. "masters.",
    WARLORD_QUINTAD = "Thalassa Tarkin is dead. The Quintad's claim to the Tarkin name dies with her.",
    WARLORD_DASTA = "Ragez D'Asta is dead. His raiders turn on each other over the spoils.",
    WARLORD_HAMMERS = "Zel Johans is dead. The Imperial Hammers break ranks.",
    WARLORD_KASHYYYK = "Hindane Darcc is dead. The Wookiees rise, and his garrisons on Kashyyyk and beyond fall.",
    WARLORD_LUMIYA = "Lumiya is dead. Her Sith scatter into the dark; her worlds wake from a long nightmare.",
    WARLORD_ARDA = "Vorrel is dead. Arda's walkers fall silent, and the world is free.",
    WARLORD_SELLASAS = "Jedselk is dead. Dolla and Sellasas cast off his rule.",
    WARLORD_PROTECTORATE = "Adalric Brandl is dead. The Protectorate he ruled as a prophet falls into schism.",
    WARLORD_ZAARIN_REMNANTS = "Raveen is dead. The last of Zaarin's loyalists lose the last of their cause.",
    WARLORD_RAYTER = "Nile Owen is dead. The Rayter Sector's worlds go their own way.",
    WARLORD_VOGEL = "Lynch Hauser is dead. The Dustig Oversector's Moffs quarrel over his seat, and its worlds slip "
        .. "away.",
    WARLORD_WESSEX = "Denn Wessex is dead. The Relgim Oversector comes apart.",
    WARLORD_CATO_NEIMOIDIA = "Erron Irbian is dead. The Neimoidian purse worlds buy their freedom from his officers.",
    WARLORD_KUAT = "Thichis Kuras is dead. Kuat's shipwrights and the worlds around them look for a new patron.",
    WARLORD_KAARENTH_DISSENSION = "Ennix Devian is dead. The Kaarenth Dissension loses its reason to dissent.",
    WARLORD_RESTORED_EMPIRE = "Ennix Devian is dead. The Restored Empire has nothing left to restore.",
    WARLORD_PRAJI = "Nahdonnis Praji is dead. Kaikielius and its neighbours go their own way.",
    WARLORD_GRUNGER = "Josef Grunger is dead. The warlord who defied Zsinj and Teradoc alike leaves nothing behind "
        .. "him.",
    WARLORD_THORN = "Daymon Thorn is dead. Thorn's Empire was a name and a man; both are gone.",
}
local BREAKAWAY = "{leader}, the Moff who led {name} out of the Empire, is dead. Without them the breakaway sector "
    .. "has no reason to hold together."
local ESCAPE = "{leader}'s flagship breaks apart over {world}, but a shuttle streaks down to the surface. {leader} has "
    .. "escaped to the capital: while {world} holds, so does {name}."

local function state(d)
    d.memory.warlord_death = d.memory.warlord_death or {pending = {}, residence = {}, collapsed = {}, space = {}}
    return d.memory.warlord_death
end

local function fill(text, values)
    for k, v in pairs(values) do
        text = string.gsub(text, "{" .. k .. "}", (string.gsub(v, "%%", "%%%%")))
    end
    return text
end

local function breakaway(faction)
    if not IMPERIAL_COURT_BREAKAWAY then
        return nil
    end
    local ok, lord = pcall(IMPERIAL_COURT_BREAKAWAY, faction)
    return ok and lord or nil
end

local function warlord(d, faction)
    if faction == string.upper(d.human.Get_Faction_Name()) then
        return false
    end
    if MAJOR[faction] or breakaway(faction) then
        return true
    end
    local warlords = Diplomacy.warlord_factions and Diplomacy.warlord_factions() or {}
    return warlords[faction] == true
end

local function leader_types(d, faction)
    local list = LEADERS[faction]
    if faction == "IMPERIAL_PROTEUS" or not list then
        list = LEADERS.WARLORDS and LEADERS.WARLORDS[d.display_name(faction)] or list
    end
    local out = {}
    for _, entry in ipairs(list or {}) do
        out[string.upper(entry.type)] = entry.name
    end
    return out
end

local function leader_alive(faction, types)
    local player = Find_Player(faction)
    for type_name in pairs(types) do
        local obj = Find_Object_Type(type_name) and Find_First_Object(type_name)
        if TestValid(obj) and obj.Get_Owner() == player then
            return true
        end
    end
    return false
end

local function is_space(s, type_name)
    if s.space[type_name] ~= nil then
        return s.space[type_name]
    end
    for _, mark in ipairs(GROUND) do
        if string.find(type_name, mark, 1, true) then
            return false
        end
    end
    return true
end

local function capital(d, player)
    local ok_d, Deals = pcall(require, "eawx-plugins/diplomacy/DiplomacyDeals")
    local ok, planet = false, nil
    if ok_d then
        ok, planet = pcall(Deals.capital, d, player)
    end
    return ok and planet or nil
end

local function worlds_of(player)
    local out = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == player then
            table.insert(out, planet)
        end
    end
    return out
end

local function collapse(d, faction, leader_name)
    local s = state(d)
    if s.collapsed[faction] then
        return
    end
    local player = Find_Player(faction)
    if not player then
        return
    end
    s.collapsed[faction] = true
    s.residence[faction] = nil
    d.memory.fallen = d.memory.fallen or {}
    d.memory.fallen[faction] = true
    local name = d.display_name(faction)
    local text = TEXT[faction] or (breakaway(faction) and BREAKAWAY) or TEXT.IMPERIAL_PROTEUS
    d.show(fill(text, {leader = leader_name or "Its warlord", name = name}), nil, GOLD, 40)
    local worlds = worlds_of(player)
    local target = {}
    for _, planet in ipairs(worlds) do
        local key = string.upper(planet.Get_Type().Get_Name())
        local wants = Rebellion.preferred(d, key)
        local joins = wants and wants ~= faction and not s.collapsed[wants] and Find_Player(wants)
        target[planet] = joins or Find_Player(INDEPENDENT)
    end
    local home = capital(d, player) or worlds[1]
    for _, obj in pairs(Find_All_Objects_Of_Type(player) or {}) do
        if TestValid(obj) and not obj.Is_Category("Structure") and not obj.Is_Category("SpaceStructure") then
            local ok, at = pcall(obj.Get_Planet_Location)
            local joins = (ok and at and target[at]) or nil
            if not joins and ok and at then
                local best, distance = nil, nil
                for _, planet in ipairs(worlds) do
                    local dist = at.Get_Distance(planet)
                    if not distance or dist < distance then
                        best, distance = planet, dist
                    end
                end
                joins = best and target[best]
            end
            joins = joins or (home and target[home]) or Find_Player(INDEPENDENT)
            pcall(obj.Change_Owner, joins)
        end
    end
    for _, planet in ipairs(worlds) do
        local joins = target[planet]
        if joins == d.human then
            d.own_transfers[string.upper(planet.Get_Type().Get_Name())] = true
        end
        pcall(DIPLOMACY_REVOLT_POPULATE, planet, joins)
    end
    if Engine_Log then
        Engine_Log("WARLORD DEATH: " .. faction .. " falls apart (" .. table.getn(worlds) .. " worlds)")
    end
end

local function building_stands(faction, player, planet)
    local constants = ModContentLoader.get("GameConstants")
    local entry = MAJOR[faction] and constants and constants.ALL_FACTIONS_CAPITALS
        and constants.ALL_FACTIONS_CAPITALS[faction]
    if not (entry and entry.STRUCTURE and Find_Object_Type(entry.STRUCTURE)) then
        return true
    end
    for _, obj in pairs(Find_All_Objects_Of_Type(entry.STRUCTURE) or {}) do
        if TestValid(obj) and obj.Get_Owner() == player and obj.Get_Planet_Location() == planet then
            return true
        end
    end
    return false
end

local function escape(d, faction, type_name, leader_name, planet)
    local s = state(d)
    local world = string.upper(planet.Get_Type().Get_Name())
    local residence = RESIDENCES[type_name]
    if residence and Find_Object_Type(residence) then
        pcall(Spawn_Unit, Find_Object_Type(residence), planet, Find_Player(faction))
    end
    s.residence[faction] = {world = world, type = residence, name = leader_name,
                            building = building_stands(faction, Find_Player(faction), planet)}
    d.show(fill(ESCAPE, {leader = leader_name, world = d:planet_name(planet), name = d.display_name(faction)}), nil,
        GOLD, 30)
end

function Death.on_hero_killed(d, hero_name, owner_name)
    local faction = owner_name and string.upper(owner_name)
    local type_name = hero_name and string.upper(hero_name)
    if not faction or not type_name or not warlord(d, faction) or breakaway(faction) then
        return
    end
    local types = leader_types(d, faction)
    if not types[type_name] then
        return
    end
    local world = Engine_Battle_Planet and Engine_Battle_Planet()
    table.insert(state(d).pending, {faction = faction, type = type_name, name = types[type_name],
                                   world = world and string.upper(world), at = GetCurrentTime() + WAIT})
end

local function settle(d, p)
    local s = state(d)
    if s.collapsed[p.faction] or s.residence[p.faction] then
        return
    end
    local player = Find_Player(p.faction)
    if not player or not worlds_of(player)[1] then
        return
    end
    if leader_alive(p.faction, leader_types(d, p.faction)) then
        return
    end
    local home = capital(d, player)
    if home and p.world and string.upper(home.Get_Type().Get_Name()) == p.world and is_space(s, p.type) then
        escape(d, p.faction, p.type, p.name, home)
        return
    end
    collapse(d, p.faction, p.name)
end

local function residence_lost(d, faction, r)
    local player = Find_Player(faction)
    local capital_world = FindPlanet(r.world)
    if not player then
        return true, capital_world
    end
    local residence = nil
    if r.type and Find_Object_Type(r.type) then
        for _, obj in pairs(Find_All_Objects_Of_Type(r.type) or {}) do
            if TestValid(obj) then
                residence = obj
            end
        end
        if residence then
            r.seen = true
        elseif r.seen then
            return true, capital_world
        end
    end
    local at = residence and residence.Get_Planet_Location() or capital_world
    if not at then
        return false
    end
    if at.Get_Owner() ~= player or (r.building and not building_stands(faction, player, at)) then
        return true, at
    end
    return false
end

function Death.update(d)
    if GetCurrentTime() < (Death.next_at or 0) then
        return
    end
    Death.next_at = GetCurrentTime() + 2
    if GetCurrentTime() >= (Death.next_week or 0) then
        Death.next_week = GetCurrentTime() + 40
        pcall(Death.week, d)
    end
    local s = state(d)
    local left = {}
    for _, p in ipairs(s.pending) do
        if GetCurrentTime() < p.at then
            table.insert(left, p)
        else
            local ok, err = pcall(settle, d, p)
            if not ok and Engine_Log then
                Engine_Log("WARLORD DEATH: " .. tostring(err))
            end
        end
    end
    s.pending = left
    for faction, r in pairs(s.residence) do
        local lost, planet = residence_lost(d, faction, r)
        if lost then
            if r.type then
                for _, obj in pairs(Find_All_Objects_Of_Type(r.type) or {}) do
                    if TestValid(obj) then
                        pcall(obj.Despawn)
                    end
                end
            end
            s.residence[faction] = nil
            pcall(collapse, d, faction, r.name)
        end
    end
    if IMPERIAL_COURT_BREAKAWAYS then
        local ok, list = pcall(IMPERIAL_COURT_BREAKAWAYS)
        for faction, lord in pairs(ok and list or {}) do
            if lord.dead and not s.collapsed[faction] and Find_Player(faction) and worlds_of(Find_Player(faction))[1] then
                pcall(collapse, d, faction, lord.name)
            end
        end
    end
end

function Death.week(d)
    local s = state(d)
    for faction in pairs(MAJOR) do
        for type_name in pairs(leader_types(d, faction)) do
            if s.space[type_name] == nil and Find_Object_Type(type_name) then
                local obj = Find_First_Object(type_name)
                if TestValid(obj) then
                    s.space[type_name] = obj.Is_Category("SpaceHero") or obj.Is_Category("Capital")
                        or obj.Is_Category("SuperCapital") or obj.Is_Category("Frigate")
                        or obj.Is_Category("Corvette") or false
                end
            end
        end
    end
end

return Death
