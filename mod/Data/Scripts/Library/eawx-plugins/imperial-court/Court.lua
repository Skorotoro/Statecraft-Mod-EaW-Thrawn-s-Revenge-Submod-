require("eawx-util/ChangeOwnerUtilities")
local CONFIG = require("eawx-plugins/imperial-court/CourtConfig")
local M = require("eawx-plugins/imperial-court/CourtMath")
local GEO = require("eawx-plugins/imperial-court/CourtGeo")
local ROUTES = require("eawx-plugins/imperial-court/CourtRoutes")
local LORE = require("eawx-plugins/imperial-court/CourtLore")
local HAND = require("eawx-plugins/imperial-court/CourtSectorsData")

local Court = {}

local function log(text)
    if Engine_Log then
        Engine_Log("COURT " .. text)
    end
end
Court.log = log

local function warlord_data()
    local ok, data = pcall(require, "eawx-plugins/warlords/WarlordFactions")
    if ok and type(data) == "table" then
        return data
    end
    return nil
end
Court.warlord_data = warlord_data

function Court.faction_label(faction)
    faction = faction and string.upper(faction) or "?"
    if DIPLOMACY_DISPLAY_NAME then
        local ok, name = pcall(DIPLOMACY_DISPLAY_NAME, faction)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    local data = warlord_data()
    for _, w in ipairs(data and data.WARLORDS or {}) do
        if w.faction == faction then
            return w.display
        end
    end
    if IMPERIAL_COURT and IMPERIAL_COURT.used_slots and IMPERIAL_COURT.used_slots[faction] then
        return IMPERIAL_COURT.used_slots[faction].name
    end
    local text = string.lower(string.gsub(faction, "_", " "))
    return (string.gsub(text, "(%a)([%w']*)", function(a, b) return string.upper(a) .. b end))
end

local LANES = {}
function Court.lanes(name)
    local list = LANES[name]
    if not list then
        list = {}
        local raw = ROUTES[name]
        if raw then
            for other in string.gfind(raw, "%S+") do
                table.insert(list, other)
            end
        end
        LANES[name] = list
    end
    return list
end

function Court.player()
    return Find_Player(CONFIG.FACTION)
end

local function name_of(planet)
    return string.upper(planet.Get_Type().Get_Name())
end
Court.name_of = name_of

function Court.held(s)
    local out, owners = {}, {}
    local empire = Court.player()
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local owner = planet.Get_Owner()
        local name = name_of(planet)
        if not string.find(name, "REGIMEPICKER$") then
            owners[name] = string.upper(owner.Get_Faction_Name())
            if owner == empire then
                out[name] = true
            end
        end
    end
    if s then
        s.owners, s.held = owners, out
    end
    return out
end

function Court.owner_of(s, name)
    local owner = s and s.owners and s.owners[name]
    if owner then
        return owner
    end
    local planet = FindPlanet(name)
    return planet and string.upper(planet.Get_Owner().Get_Faction_Name()) or nil
end

local labels = {}
function Court.planet_label(name)
    if labels[name] then
        return labels[name]
    end
    local planet = not Court.no_lookups and FindPlanet(name)
    if planet and DIPLOMACY_PLANET_NAME then
        local ok, label = pcall(DIPLOMACY_PLANET_NAME, planet)
        if ok and label then
            labels[name] = label
            return label
        end
    end
    local text = string.lower(string.gsub(name, "_", " "))
    return (string.gsub(text, "(%a)([%w']*)", function(a, b) return string.upper(a) .. b end))
end

local function sorted_keys(t)
    local keys = {}
    for k, _ in pairs(t) do
        table.insert(keys, k)
    end
    table.sort(keys)
    return keys
end
Court.sorted_keys = sorted_keys

local LORE_BY_UNIT = {}
for i, c in ipairs(LORE.CHARACTERS) do
    for _, unit in ipairs(c.units) do
        LORE_BY_UNIT[unit] = i
    end
end
Court.LORE_BY_UNIT = LORE_BY_UNIT

function Court.lore_by_name(name)
    for i, def in ipairs(LORE.CHARACTERS) do
        if def.name == name then
            return i
        end
    end
    return nil
end

local function unit_on_map(lore_index)
    local c = LORE.CHARACTERS[lore_index]
    for _, unit in ipairs(c and c.units or {}) do
        if Find_Object_Type(unit) then
            local obj = Find_First_Object(unit)
            if obj and TestValid(obj) then
                return obj, string.upper(obj.Get_Owner().Get_Faction_Name())
            end
        end
    end
    return nil
end
Court.unit_on_map = unit_on_map

function Court.char(s, id)
    return id and s.chars[id] or nil
end

local function generated_name(s)
    for _ = 1, 40 do
        local name = M.pick(CONFIG.FIRST_NAMES) .. " " .. M.pick(CONFIG.SURNAMES)
        if not s.names[name] then
            s.names[name] = true
            return name
        end
    end
    s.next_id = s.next_id + 1
    return M.pick(CONFIG.FIRST_NAMES) .. " " .. M.pick(CONFIG.SURNAMES) .. " " .. s.next_id
end

local function random_traits(n)
    local traits, seen = {}, {}
    for _ = 1, 10 do
        if table.getn(traits) >= n then
            break
        end
        local t = M.pick(CONFIG.TRAIT_ODDS)
        if not seen[t] then
            seen[t] = true
            table.insert(traits, t)
        end
    end
    return traits
end

function Court.has_trait(c, key)
    for _, t in ipairs(c.traits) do
        if t == key then
            return true
        end
    end
    return false
end

function Court.new_char(s, lore, title)
    s.next_id = s.next_id + 1
    local c = {id = s.next_id, title = title or "courtier", loyalty = 50,
               temper = M.random(CONFIG.LOYALTY.START_MIN, CONFIG.LOYALTY.START_MAX),
               influence = M.random(5, 25), ambition = M.random(20, 80), skill = M.random(25, 80),
               traits = random_traits(M.random(1, 2)), opinion = {}, status = "serving", since = s.week}
    if lore then
        local def = LORE.CHARACTERS[lore]
        c.lore, c.name, c.portrait = lore, def.name, def.portrait
        c.kind = "lore"
        c.role = def.role
        c.skill = M.random(50, 90)
        if def.role == "navy" and not Court.has_trait(c, "navy") then
            table.insert(c.traits, "navy")
        elseif def.role == "army" and not Court.has_trait(c, "army") then
            table.insert(c.traits, "army")
        end
        local nature = CONFIG.LORE_TRAITS[def.name]
        if nature then
            c.traits = {}
            for _, t in ipairs(nature) do
                if CONFIG.TRAITS[t] then
                    table.insert(c.traits, t)
                end
            end
        end
        s.names[def.name] = true
        s.lore_used[lore] = c.id
    else
        c.name = generated_name(s)
        c.kind = "generated"
        c.gen = M.random(1, 6)
    end
    for _, t in ipairs(c.traits) do
        local def = CONFIG.TRAITS[t]
        c.ambition = M.clamp(c.ambition + (def.ambition or 0), 0, 100)
    end
    local successor = nil
    for _, t in ipairs(c.traits) do
        successor = successor or CONFIG.TRAIT_SUCCESSOR[t]
    end
    c.prefers = successor
    s.chars[c.id] = c
    table.insert(s.order, c.id)
    return c
end

function Court.portrait(c)
    if not c then
        return "dp_ip_vacant.tga"
    end
    if c.kind == "generated" then
        return "dp_ip_gen_1.tga"
    end
    return (c.portrait or "dp_ip_lore") .. ((c.kind == "unit") and "_g.tga" or "_s.tga")
end

function Court.own_ship(c)
    local def = c and c.lore and LORE.CHARACTERS[c.lore]
    return c ~= nil and c.kind == "unit" and def ~= nil and def.space == true and not c.ship_granted
end

function Court.kind_text(c)
    local role = c.lore and LORE.CHARACTERS[c.lore] and LORE.CHARACTERS[c.lore].rank or ""
    local traitor = c.traitor and " Branded a traitor." or ""
    if c.kind == "unit" then
        return ((role ~= "") and (role .. " in the field.") or "In the field.") .. traitor
    elseif c.kind == "lore" then
        return ((role ~= "") and (role .. ", known to history.") or "Known to history.") .. traitor
    end
    return "Raised from the ranks." .. traitor
end

function Court.profile()
    local storyline = GlobalValue.Get("STORYLINE")
    local profile = (type(storyline) == "string" and CONFIG.PROFILES[storyline]) or {}
    local fixed = GlobalValue.Get("PROGRESS_REGIME") == false
    return profile, fixed
end

function Court.is_station(name)
    local geo = GEO[name or ""]
    return geo and geo.station == true
end

function Court.title_name(c)
    if not c or c.title == "courtier" then
        return nil
    end
    if c.title == "moff" or c.title == "governor" then
        local def = c.lore and LORE.CHARACTERS[c.lore]
        if def and (CONFIG.LORD.classes[def.class or ""] or CONFIG.LORD.names[def.name]) then
            return CONFIG.LORD.name
        end
    end
    if c.title == "governor" and Court.is_station(c.holds) then
        return CONFIG.COMMANDER.name
    end
    local t = CONFIG.TITLES[c.title]
    return t and t.name
end

function Court.full_name(c)
    if not c then
        return "nobody"
    end
    local t = Court.title_name(c)
    if t then
        return t .. " " .. c.name
    end
    if c.fleet_rank and CONFIG.ADMIRALTY[c.fleet_rank] then
        return CONFIG.ADMIRALTY[c.fleet_rank].name .. " " .. c.name
    end
    return c.name
end

local SHIP_CLASS = {G = "an Imperial II Star Destroyer", M = "a Star Destroyer", V = "a cruiser"}
function Court.posts_text(s, c, no_fleet)
    local parts = {}
    local holdings = Court.holdings_text(s, c, 3)
    if holdings ~= "" then
        table.insert(parts, holdings)
    end
    local office = Court.office_of(s, c)
    if office then
        table.insert(parts, Court.office_def(s, office).name)
    end
    if c.fleet_rank and CONFIG.ADMIRALTY[c.fleet_rank] and not no_fleet then
        local _, _, pool = string.find(c.ship or "", "^COURT_SHIP_(%a)")
        table.insert(parts, CONFIG.ADMIRALTY[c.fleet_rank].name .. (pool and SHIP_CLASS[pool]
            and (" (flagship: " .. SHIP_CLASS[pool] .. ")") or ""))
    end
    return table.concat(parts, ", ")
end

function Court.titles(s)
    if not Engine_Set_Text or not LORE.CLASSES then
        return
    end
    local regime = Court.regime(s)
    local ruler = regime.figure and LORE_BY_UNIT[regime.figure]
    local done = {}
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        local def = c.lore and LORE.CHARACTERS[c.lore]
        if def then
            local fleet = c.status == "serving" and c.fleet_rank and CONFIG.ADMIRALTY[c.fleet_rank]
            local posts = (c.status == "serving") and Court.posts_text(s, c, fleet ~= nil) or ""
            for _, unit in ipairs(def.units) do
                local base = LORE.CLASSES[unit]
                if base and fleet then
                    base = fleet.name
                    local _, _, pool = string.find(c.ship or "", "^COURT_SHIP_(%a)")
                    if pool and SHIP_CLASS[pool] then
                        base = base .. " (flagship: " .. SHIP_CLASS[pool] .. ")"
                    end
                end
                if base then
                    local value = base .. ((posts ~= "") and (", " .. posts) or "")
                    if posts ~= "" and string.find(posts, base, 1, true) then
                        value = posts
                    end
                    pcall(Engine_Set_Text, "TEXT_COURT_CLASS_" .. unit, value)
                    done[unit] = true
                end
            end
        end
    end
    for i, def in ipairs(LORE.CHARACTERS) do
        for _, unit in ipairs(def.units) do
            local base = LORE.CLASSES[unit]
            if base and i == ruler then
                pcall(Engine_Set_Text, "TEXT_COURT_CLASS_" .. unit, regime.rank or base)
            elseif base and not done[unit] then
                pcall(Engine_Set_Text, "TEXT_COURT_CLASS_" .. unit, base)
            end
        end
    end
end

function Court.opinion(c, text, value, weeks)
    if weeks then
        weeks = M.min(weeks, CONFIG.FADE_MAX)
    end
    local found = nil
    for _, o in ipairs(c.opinion) do
        if o.text == text then
            found = o
        end
    end
    if found then
        found.value, found.weeks, found.total = value, weeks, weeks
    else
        table.insert(c.opinion, {text = text, value = value, weeks = weeks, total = weeks})
    end
    local s = IMPERIAL_COURT
    if type(s) == "table" and s.chars and s.chars[c.id] == c and c.mods then
        Court.update_loyalty(s, c)
    end
end

function Court.opinion_now(o)
    if not o.weeks then
        return o.value
    end
    local total = M.max(1, o.total or o.weeks)
    return o.value * M.clamp(o.weeks, 0, total) / total
end

function Court.opinion_total(c)
    local total = 0
    for _, o in ipairs(c.opinion) do
        total = total + Court.opinion_now(o)
    end
    return total
end

Court.ALERT = {request = {r = 255, g = 214, b = 120}, threat = {r = 255, g = 120, b = 100}}
function Court.alert(text, kind)
    local ok, human = pcall(function()
        return Court.player().Is_Human()
    end)
    if ok and human and StoryUtil then
        StoryUtil.ShowScreenText(text, 15, nil, Court.ALERT[kind or "request"] or Court.ALERT.request)
    end
end

function Court.news(s, text)
    table.insert(s.news, 1, "Week " .. s.week .. ": " .. text)
    while table.getn(s.news) > 14 do
        table.remove(s.news)
    end
    log(text)
end

local function planets_at(warlord, year)
    if warlord.start and year < warlord.start then
        return nil
    end
    if warlord.last and year > warlord.last then
        return nil
    end
    local best = nil
    for _, era in ipairs(warlord.eras or {}) do
        if year >= era.year and (best == nil or era.year > best.year) then
            best = era
        end
    end
    return best and best.planets
end

local function new_sector(s, key, name, extra)
    local sector = {key = key, name = name, worlds = {}}
    for k, v in pairs(extra or {}) do
        sector[k] = v
    end
    s.sectors[key] = sector
    return sector
end

function Court.index_worlds(s)
    for _, sector in pairs(s.sectors) do
        sector.worlds = {}
    end
    s.home = s.home or {}
    for _, name in ipairs(sorted_keys(s.world)) do
        local sector = s.sectors[s.world[name]]
        if sector then
            s.home[name] = sector.key
            table.insert(sector.worlds, name)
        else
            s.world[name] = nil
        end
    end
end

local function neighbour_sector(s, name, held)
    local counts, best, best_n = {}, nil, 0
    for _, other in ipairs(Court.lanes(name)) do
        local key = held[other] and s.world[other]
        if key and not s.sectors[key].crown then
            counts[key] = (counts[key] or 0) + 1
            if counts[key] > best_n or (counts[key] == best_n and key < best) then
                best, best_n = key, counts[key]
            end
        end
    end
    return best
end

function Court.static_sectors(s)
    if s.static_done then
        return
    end
    s.lore_sector = s.lore_sector or {}
    local G = CONFIG.SECTOR_GEO
    local names = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local name = name_of(planet)
        if not string.find(name, "REGIMEPICKER$") and GEO[name] then
            table.insert(names, name)
        end
    end
    table.sort(names)
    local function dist(a, b)
        local dx, dy = GEO[a].x - GEO[b].x, GEO[a].y - GEO[b].y
        return dx * dx + dy * dy
    end
    local function nearest(name, pool)
        local best, best_d = nil, nil
        for _, other in ipairs(pool) do
            local key = s.lore_sector[other]
            if other ~= name and key and s.sectors[key] and not s.sectors[key].crown then
                local d = dist(name, other)
                if not best_d or d < best_d or (d == best_d and key < best) then
                    best, best_d = key, d
                end
            end
        end
        return best, best_d
    end
    local function join(name, key)
        s.lore_sector[name] = key
        table.insert(s.sectors[key].members, name)
    end
    local lore = {}
    for _, name in ipairs(names) do
        if s.lore_sector[name] then
            table.insert(lore, name)
        end
    end
    local joins = {}
    for _, name in ipairs(names) do
        if not s.lore_sector[name] then
            local key, d = nearest(name, lore)
            if key and d <= G.JOIN * G.JOIN then
                joins[name] = key
            end
        end
    end
    for _, name in ipairs(names) do
        if joins[name] then
            join(name, joins[name])
        end
    end
    local left = {}
    for _, name in ipairs(names) do
        if not s.lore_sector[name] then
            table.insert(left, name)
        end
    end
    local seen = {}
    for _, name in ipairs(left) do
        if not seen[name] then
            local group, head = {name}, 1
            seen[name] = true
            while group[head] do
                for _, other in ipairs(left) do
                    if not seen[other] and dist(group[head], other) <= G.LINK * G.LINK then
                        seen[other] = true
                        table.insert(group, other)
                    end
                end
                head = head + 1
            end
            if table.getn(group) >= CONFIG.MIN_SECTOR_WORLDS then
                local cx, cy = 0, 0
                for _, w in ipairs(group) do
                    cx, cy = cx + GEO[w].x, cy + GEO[w].y
                end
                cx, cy = cx / table.getn(group), cy / table.getn(group)
                table.sort(group, function(a, b)
                    local da = (GEO[a].x - cx) * (GEO[a].x - cx) + (GEO[a].y - cy) * (GEO[a].y - cy)
                    local db = (GEO[b].x - cx) * (GEO[b].x - cx) + (GEO[b].y - cy) * (GEO[b].y - cy)
                    if da ~= db then
                        return da < db
                    end
                    return a < b
                end)
                local key = "S_" .. group[1]
                local sector = new_sector(s, key, Court.planet_label(group[1]) .. " Sector",
                                          {lore = true, members = {}, home_seat = group[1],
                                           region = GEO[group[1]].region or "Outer Rim"})
                for _, w in ipairs(group) do
                    join(w, key)
                end
            end
        end
    end
    local placed = {}
    for _, name in ipairs(names) do
        if s.lore_sector[name] then
            table.insert(placed, name)
        end
    end
    for _, name in ipairs(names) do
        if not s.lore_sector[name] then
            local key = nearest(name, placed)
            if key then
                join(name, key)
            end
        end
    end
    s.static_done = true
end

function Court.ensure_oversectors(s)
    local regions = {}
    for _, sector in pairs(s.sectors) do
        if not sector.region then
            local geo = GEO[sector.home_seat or sector.seat or ""]
            sector.region = geo and geo.region or "Outer Rim"
        end
        if not sector.crown and table.getn(sector.worlds) > 0 then
            regions[sector.region] = (regions[sector.region] or 0) + 1
        end
    end
    for region, n in pairs(regions) do
        if n >= CONFIG.MIN_OVERSECTOR and not s.oversectors[region] then
            s.oversectors[region] = {key = region, name = CONFIG.OVERSECTOR_NAMES[region] or (region .. " Oversector")}
            if s.ready then
                Court.news(s, "The Empire's hold on the " .. region .. " makes it an oversector: the "
                    .. s.oversectors[region].name .. " awaits a Grand Moff.")
            end
        end
    end
    for _, sector in pairs(s.sectors) do
        if not sector.crown and not sector.oversector and s.oversectors[sector.region] then
            sector.oversector = sector.region
        end
    end
end

function Court.place_world(s, name)
    s.held = s.held or {}
    s.held[name] = true
    if s.owners then
        s.owners[name] = CONFIG.FACTION
    end
    local key = s.lore_sector and s.lore_sector[name]
    if key and s.sectors[key] and not s.world[name] then
        s.world[name] = key
        Court.index_worlds(s)
        local sector = s.sectors[key]
        if not sector.seat or s.world[sector.seat] ~= key then
            sector.seat = name
        end
        Court.ensure_oversectors(s)
    end
end

local warlord_worlds = {}

local function build_sectors(s, held)
    warlord_worlds = {}
    local year = GlobalValue.Get("GALACTIC_YEAR") or 0
    local on_map = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        on_map[name_of(planet)] = true
    end
    s.lore_sector = {}
    local function join(sector, name)
        if not on_map[name] or s.lore_sector[name] then
            return
        end
        s.lore_sector[name] = sector.key
        table.insert(sector.members, name)
        if held[name] then
            s.world[name] = sector.key
        end
    end
    local by_name = {}
    for i, entry in ipairs(HAND) do
        local present = false
        for _, name in ipairs(entry.worlds) do
            present = present or (on_map[name] and not s.lore_sector[name])
        end
        if present then
            local key = by_name[entry.name] or ("H_" .. i)
            local sector = s.sectors[key] or new_sector(s, key, entry.name, {lore = true, crown = entry.crown,
                                                                            members = {}, region = entry.region})
            by_name[entry.name] = key
            for _, name in ipairs(entry.worlds) do
                join(sector, name)
            end
        end
    end
    for _, name in ipairs(sorted_keys(GEO)) do
        local geo = GEO[name]
        if geo.sector and on_map[name] and not s.lore_sector[name] then
            local key = by_name[geo.sector]
            if not key then
                key = "G_" .. string.upper(string.gsub(geo.sector, "[^%w]", "_"))
                new_sector(s, key, geo.sector, {lore = true, members = {}})
                by_name[geo.sector] = key
            end
            join(s.sectors[key], name)
        end
    end
    local data = warlord_data()
    for _, warlord in ipairs(data and data.WARLORDS or {}) do
        local imperial = false
        for _, f in ipairs(warlord.overrides or {}) do
            imperial = imperial or f == CONFIG.FACTION
        end
        local planets = planets_at(warlord, year)
        if imperial and not planets and warlord.start and warlord.start > year
                and warlord.start - year <= CONFIG.MOFF_BEFORE_BREAKAWAY then
            planets = planets_at(warlord, warlord.start)
        end
        local capital = nil
        for _, name in ipairs(planets or {}) do
            if held[name] and on_map[name] then
                capital = capital or name
                warlord_worlds[warlord.key] = warlord_worlds[warlord.key] or {}
                table.insert(warlord_worlds[warlord.key], name)
            end
        end
        local key = capital and s.lore_sector[capital]
        local sector = key and s.sectors[key]
        if capital and not sector then
            key = "W_" .. warlord.key
            sector = new_sector(s, key, Court.planet_label(capital) .. " Sector", {lore = true, members = {}})
            join(sector, capital)
        end
        if sector and not sector.warlord and not sector.crown then
            sector.warlord, sector.banner, sector.home_seat = warlord.key, warlord.display, capital
        end
    end
    Court.static_sectors(s)
    for _, name in ipairs(sorted_keys(held)) do
        if not s.world[name] and s.lore_sector[name] then
            s.world[name] = s.lore_sector[name]
        end
    end
    Court.index_worlds(s)
    for _, sector in pairs(s.sectors) do
        sector.home_seat = sector.home_seat or sector.members[1] or sector.worlds[1]
        sector.seat = nil
        if sector.warlord and s.world[sector.home_seat or ""] == sector.key then
            sector.seat = sector.home_seat
        end
        for _, name in ipairs(sector.members) do
            if not sector.seat and s.world[name] == sector.key then
                sector.seat = name
                break
            end
        end
        sector.seat = sector.seat or sector.worlds[1]
    end
    local regions = {}
    for key, sector in pairs(s.sectors) do
        local geo = GEO[sector.home_seat or ""]
        sector.region = sector.region or (geo and geo.region) or "Outer Rim"
        if not sector.crown and table.getn(sector.worlds) > 0 then
            regions[sector.region] = (regions[sector.region] or 0) + 1
        end
    end
    for region, n in pairs(regions) do
        if n >= CONFIG.MIN_OVERSECTOR then
            s.oversectors[region] = {key = region, name = CONFIG.OVERSECTOR_NAMES[region] or (region .. " Oversector")}
        end
    end
    for _, sector in pairs(s.sectors) do
        if not sector.crown and s.oversectors[sector.region] then
            sector.oversector = sector.region
        end
    end
end

function Court.sector_members(s, sector)
    local seen, out = {}, {}
    if sector.members then
        if sector.seat then
            table.insert(out, sector.seat)
            seen[sector.seat] = true
        end
        local rest = {}
        for _, list in ipairs({sector.members, sector.worlds}) do
            for _, name in ipairs(list) do
                if not seen[name] then
                    seen[name] = true
                    table.insert(rest, name)
                end
            end
        end
        table.sort(rest)
        for _, name in ipairs(rest) do
            table.insert(out, name)
        end
        return out
    end
    local function add(name)
        if name and not seen[name] and (s.world[name] or Court.owner_of(s, name)) then
            seen[name] = true
            table.insert(out, name)
        end
    end
    add(sector.seat)
    for _, name in ipairs(sector.worlds) do
        add(name)
    end
    local more = {}
    for name, key in pairs(s.home or {}) do
        if key == sector.key and not s.world[name] then
            table.insert(more, name)
        end
    end
    local names = {[sector.name] = true}
    if sector.banner then
        names[sector.banner] = true
    end
    for name, geo in pairs(GEO) do
        if geo.sector and names[geo.sector] and not s.world[name] then
            table.insert(more, name)
        end
    end
    table.sort(more)
    for _, name in ipairs(more) do
        add(name)
    end
    return out
end

function Court.sector_list(s)
    local list = {}
    for _, key in ipairs(sorted_keys(s.sectors)) do
        table.insert(list, s.sectors[key])
    end
    table.sort(list, function(a, b)
        if (a.crown or false) ~= (b.crown or false) then
            return a.crown == true
        end
        if table.getn(a.worlds) ~= table.getn(b.worlds) then
            return table.getn(a.worlds) > table.getn(b.worlds)
        end
        return a.name < b.name
    end)
    return list
end

function Court.direct_worlds(s, held)
    local out = {}
    for _, name in ipairs(sorted_keys(held or Court.held())) do
        if not s.world[name] then
            table.insert(out, name)
        end
    end
    return out
end

function Court.unsectored(s, held)
    return Court.direct_worlds(s, held)
end

local RANK = {grand_moff = 3, moff = 2, governor = 1}
Court.RANK = RANK
local hold_stamp, hold_memo = 0, {}

function Court.touch_holdings()
    hold_stamp = hold_stamp + 1
    hold_memo = {}
end

function Court.holdings(s, c)
    if not c then
        return {}
    end
    local memo = hold_memo[c]
    if memo and memo.stamp == hold_stamp and memo.s == s then
        return memo.list
    end
    local out = {}
    for key, over in pairs(s.oversectors or {}) do
        if over.holder == c.id then
            table.insert(out, {title = "grand_moff", key = key})
        end
    end
    for key, sector in pairs(s.sectors or {}) do
        if sector.holder == c.id then
            table.insert(out, {title = "moff", key = key})
        end
    end
    for name, id in pairs(s.governor or {}) do
        if id == c.id then
            table.insert(out, {title = "governor", key = name})
        end
    end
    local g = c.gained or {}
    table.sort(out, function(a, b)
        local x, y = g[a.title .. ":" .. a.key] or 0, g[b.title .. ":" .. b.key] or 0
        if x ~= y then
            return x < y
        end
        if a.title ~= b.title then
            return RANK[a.title] > RANK[b.title]
        end
        return a.key < b.key
    end)
    hold_memo[c] = {stamp = hold_stamp, s = s, list = out}
    return out
end

function Court.holding_place(s, h)
    local sector_key
    if h.title == "moff" then
        sector_key = h.key
    elseif h.title == "governor" then
        sector_key = s.world[h.key]
    end
    local sector = sector_key and s.sectors[sector_key]
    local over = (h.title == "grand_moff") and h.key or (sector and sector.oversector)
    return sector_key, over
end

function Court.capital_of(s, c)
    local best, best_v
    for _, h in ipairs(Court.holdings(s, c)) do
        if h.title == "moff" and s.sectors[h.key] and s.sectors[h.key].seat then
            return s.sectors[h.key].seat
        elseif h.title == "governor" then
            local v = (s.world_value and s.world_value[h.key]) or 1
            if not best or v > best_v then
                best, best_v = h.key, v
            end
        end
    end
    if best then
        return best
    end
    if c.title == "grand_moff" and c.holds then
        for _, key in ipairs(sorted_keys(s.sectors)) do
            local sector = s.sectors[key]
            if sector.oversector == c.holds and sector.seat then
                return sector.seat
            end
        end
    end
    return nil
end

function Court.sync_title(s, c)
    if not c then
        return
    end
    local best
    for _, h in ipairs(Court.holdings(s, c)) do
        if not best or RANK[h.title] > RANK[best.title] then
            best = h
        end
    end
    if best then
        c.title, c.holds = best.title, best.key
    elseif c.court_gm and c.status == "serving" then
        c.title, c.holds = "grand_moff", nil
    else
        c.title, c.holds = "courtier", nil
    end
end

function Court.sync_all(s)
    Court.touch_holdings()
    for _, id in ipairs(s.order) do
        Court.sync_title(s, s.chars[id])
    end
end

local function holding_words(s, h)
    if h.title == "grand_moff" and s.oversectors[h.key] then
        return "the " .. s.oversectors[h.key].name
    elseif h.title == "moff" and s.sectors[h.key] then
        return "the " .. s.sectors[h.key].name
    elseif h.title == "governor" then
        return Court.planet_label(h.key)
    end
    return nil
end

function Court.holding_name(s, c)
    if c.title == "grand_moff" and s.oversectors[c.holds or ""] then
        return "the " .. s.oversectors[c.holds].name
    elseif c.title == "moff" and s.sectors[c.holds or ""] then
        return "the " .. s.sectors[c.holds].name
    elseif c.title == "governor" and c.holds then
        return Court.planet_label(c.holds)
    end
    return nil
end

function Court.holdings_text(s, c, limit)
    local list = {}
    for _, h in ipairs(Court.holdings(s, c)) do
        table.insert(list, h)
    end
    table.sort(list, function(a, b)
        return RANK[a.title] > RANK[b.title]
    end)
    local parts = {}
    for i, h in ipairs(list) do
        if limit and i > limit then
            table.insert(parts, "and " .. (table.getn(list) - limit) .. " more")
            break
        end
        local words = holding_words(s, h)
        if words then
            local name = (h.title == "governor" and Court.is_station(h.key)) and CONFIG.COMMANDER.name
                or CONFIG.TITLES[h.title].name
            if h.title == c.title and (h.title ~= "governor" or not Court.is_station(h.key)) then
                name = Court.title_name(c) or name
            end
            table.insert(parts, name .. " of " .. words)
        end
    end
    return table.concat(parts, ", ")
end

function Court.worlds_of(s, c, followers)
    local out, seen = {}, {}
    local function add(name)
        if not seen[name] then
            seen[name] = true
            table.insert(out, name)
        end
    end
    local function sector_worlds(sector)
        for _, name in ipairs(sector.worlds) do
            local other = Court.char(s, s.governor[name])
            if not other or other == c or (other.title ~= "moff" and other.title ~= "grand_moff")
                    or (followers and followers[other.id]) then
                add(name)
            end
        end
    end
    for _, h in ipairs(Court.holdings(s, c)) do
        if h.title == "governor" then
            if s.world[h.key] ~= nil or (s.held and s.held[h.key]) then
                add(h.key)
            end
        elseif h.title == "moff" and s.sectors[h.key] then
            sector_worlds(s.sectors[h.key])
        elseif h.title == "grand_moff" and s.oversectors[h.key] then
            for _, key in ipairs(sorted_keys(s.sectors)) do
                local sector = s.sectors[key]
                if sector.oversector == h.key then
                    local moff = Court.char(s, sector.holder)
                    if not followers or not moff or moff == c or followers[moff.id] then
                        sector_worlds(sector)
                    end
                end
            end
        end
    end
    return out
end

function Court.liege(s, c)
    local liege
    if c.title == "governor" then
        local sector = s.sectors[s.world[c.holds or ""] or ""]
        if sector and sector.holder then
            liege = Court.char(s, sector.holder)
        elseif sector and sector.oversector and s.oversectors[sector.oversector] then
            liege = Court.char(s, s.oversectors[sector.oversector].holder)
        end
    elseif c.title == "moff" then
        local sector = s.sectors[c.holds or ""]
        if sector and sector.oversector and s.oversectors[sector.oversector] then
            liege = Court.char(s, s.oversectors[sector.oversector].holder)
        end
    end
    return (liege ~= c) and liege or nil
end

local function set_holder(s, title, key, id)
    if title == "grand_moff" and s.oversectors[key] then
        s.oversectors[key].holder = id
    elseif title == "moff" and s.sectors[key] then
        s.sectors[key].holder = id
    elseif title == "governor" then
        if not id and s.governor[key] and s.ready then
            s.calm = s.calm or {}
            if not s.calm[key] or s.calm[key] <= (s.week or 0) then
                s.calm[key] = (s.week or 0) + CONFIG.UNGOVERNED.AFTER_GOVERNOR
            end
        end
        s.governor[key] = id
    end
    Court.touch_holdings()
end

function Court.vacate(s, c, title, key)
    for _, h in ipairs(Court.holdings(s, c)) do
        if not title or (h.title == title and h.key == key) then
            set_holder(s, h.title, h.key, nil)
            if c.gained then
                c.gained[h.title .. ":" .. h.key] = nil
            end
        end
    end
    if not title then
        c.court_gm = nil
    end
    Court.touch_holdings()
    Court.sync_title(s, c)
end

function Court.give_holding(s, c, title, key)
    s.hold_seq = (s.hold_seq or 0) + 1
    set_holder(s, title, key, c.id)
    c.gained = c.gained or {}
    c.gained[title .. ":" .. key] = s.hold_seq
    if title == "grand_moff" and s.oversectors[key] then
        s.oversectors[key].since = s.hold_seq
    end
end

function Court.set_title(s, c, title, key)
    local old
    if title == "grand_moff" then
        old = Court.char(s, s.oversectors[key].holder)
    elseif title == "moff" then
        old = Court.char(s, s.sectors[key].holder)
    elseif title == "governor" then
        old = Court.char(s, s.governor[key])
    end
    if old == c then
        return old
    end
    for _, h in ipairs(Court.holdings(s, c)) do
        if (title == "governor" and h.title == "governor" and (c.title == "governor" or c.title == "courtier"))
                or (title == "grand_moff" and h.title == "grand_moff") then
            Court.vacate(s, c, h.title, h.key)
        end
    end
    if old then
        if old.gained then
            old.gained[title .. ":" .. key] = nil
        end
        set_holder(s, title, key, nil)
        Court.sync_title(s, old)
        Court.add_tie(old, c, "rivals")
    end
    Court.give_holding(s, c, title, key)
    c.court_gm = nil
    Court.sync_title(s, c)
    if s.ready then
        local ok, T = pcall(require, "eawx-plugins/imperial-court/CourtTerritory")
        if ok and T then
            local done, err = pcall(T.after_grant, s, c, title, key)
            if not done then
                log("territory error: " .. tostring(err))
            end
        end
    end
    return old
end

local function tie_list(c, kind)
    if not c[kind] then
        c[kind] = {}
        local old = (kind == "rivals") and c.rival or c.friend
        if old then
            table.insert(c[kind], old)
        end
        if kind == "rivals" then
            c.rival = nil
        else
            c.friend = nil
        end
    end
    return c[kind]
end

function Court.has_tie(c, id, kind)
    if not c or not id then
        return false
    end
    for _, v in ipairs(tie_list(c, kind)) do
        if v == id then
            return true
        end
    end
    return false
end

function Court.is_rival(c, id)
    return Court.has_tie(c, id, "rivals")
end

function Court.is_friend(c, id)
    return Court.has_tie(c, id, "friends")
end

local function cut_one(c, id, kind)
    local list = tie_list(c, kind)
    for i = table.getn(list), 1, -1 do
        if list[i] == id then
            table.remove(list, i)
        end
    end
end

function Court.add_tie(a, b, kind)
    if not a or not b or a == b or Court.has_tie(a, b.id, kind) then
        return false
    end
    local other = (kind == "rivals") and "friends" or "rivals"
    for _, pair in ipairs({{a, b}, {b, a}}) do
        local x, y = pair[1], pair[2]
        cut_one(x, y.id, other)
        local list = tie_list(x, kind)
        table.insert(list, y.id)
        while table.getn(list) > CONFIG.TIES.MAX do
            table.remove(list, 1)
        end
    end
    return true
end

function Court.ties(s, c, kind)
    local out = {}
    for _, id in ipairs(tie_list(c, kind)) do
        local v = s.chars[id]
        if v and v.status == "serving" then
            table.insert(out, v)
        end
    end
    return out
end

function Court.lore_ties(s)
    local by_name = {}
    for _, id in ipairs(s.order) do
        by_name[s.chars[id].name] = s.chars[id]
    end
    for _, pair in ipairs(CONFIG.TIES.LORE_RIVALS) do
        Court.add_tie(by_name[pair[1]], by_name[pair[2]], "rivals")
    end
    for _, pair in ipairs(CONFIG.TIES.LORE_FRIENDS) do
        Court.add_tie(by_name[pair[1]], by_name[pair[2]], "friends")
    end
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if table.getn(tie_list(c, "rivals")) == 0 and M.chance(CONFIG.TIES.START_RANDOM) then
            Court.add_tie(c, s.chars[M.pick(s.order)], "rivals")
        end
        if table.getn(tie_list(c, "friends")) == 0 and M.chance(CONFIG.TIES.START_RANDOM) then
            Court.add_tie(c, s.chars[M.pick(s.order)], "friends")
        end
    end
end

function Court.week_ties(s)
    local serving = {}
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if c.status == "serving" then
            table.insert(serving, c)
        end
    end
    local n = table.getn(serving)
    for _, c in ipairs(serving) do
        for _, kind in ipairs({"rivals", "friends"}) do
            local list = tie_list(c, kind)
            for i = table.getn(list), 1, -1 do
                local v = s.chars[list[i]]
                if not v or (v.status ~= "serving" and s.week - (v.left_week or s.week) > 26) then
                    table.remove(list, i)
                end
            end
        end
        if n > 1 and s.tie_news_week ~= s.week and M.chance(CONFIG.TIES.WEEKLY) then
            local other = serving[M.random(1, n)]
            if other ~= c then
                if c.faction_key and c.faction_key == other.faction_key and not Court.is_rival(c, other.id) then
                    if Court.add_tie(c, other, "friends") then
                        s.tie_news_week = s.week
                        Court.news(s, Court.full_name(c) .. " and " .. Court.full_name(other) .. " make common cause.")
                    end
                elseif c.title == other.title and c.title ~= "courtier" and c.ambition >= 55 and other.ambition >= 40
                        and not Court.is_friend(c, other.id) then
                    if Court.add_tie(c, other, "rivals") then
                        s.tie_news_week = s.week
                        Court.news(s, Court.full_name(c) .. " and " .. Court.full_name(other) .. " become rivals.")
                    end
                end
            end
        end
    end
end

function Court.office_of(s, c)
    for key, id in pairs(s.offices) do
        if id == c.id then
            return key
        end
    end
    return nil
end

local WANT_ORDER = {"SPEAKER", "FLEET", "ARMY", "INTEL", "VIZIER", "GUARD", "TREASURY", "COMPNOR"}
function Court.wants_office(s, c)
    local W = CONFIG.WANTS
    if not c or c.status ~= "serving" or c.heir or c.leads then
        return nil
    end
    local power = Court.power(s, c)
    local def_lore = c.lore and LORE.CHARACTERS[c.lore]
    for _, key in ipairs(WANT_ORDER) do
        local want = W.OFFICES[key]
        if want and power >= (want.min_power or W.MIN_POWER) then
            local yes = false
            if want.top_moff and (c.title == "moff" or c.title == "grand_moff") then
                yes = true
                for _, id in ipairs(s.order) do
                    local v = s.chars[id]
                    if v ~= c and v.status == "serving" and (v.title == "moff" or v.title == "grand_moff")
                            and not v.leads and Court.power(s, v) > power then
                        yes = false
                        break
                    end
                end
            end
            if want.fleet and c.fleet_rank == want.fleet then
                yes = true
            end
            for _, cls in ipairs(want.classes or {}) do
                yes = yes or (def_lore ~= nil and def_lore.class == cls)
            end
            for _, t in ipairs(want.traits or {}) do
                yes = yes or Court.has_trait(c, t)
            end
            if yes then
                return key
            end
        end
    end
    return nil
end

function Court.office_def(s, key)
    local def = CONFIG.OFFICES[key]
    if def and def.palpatine and s.regime == "PALPATINE" then
        return def.palpatine
    end
    return def
end

function Court.regime_name()
    local profile = Court.profile()
    if profile.regime and CONFIG.REGIMES[profile.regime] then
        return profile.regime
    end
    local name = GlobalValue.Get("IMPERIAL_REGIME_NAME")
    if type(name) == "string" and CONFIG.REGIMES[name] then
        return name
    end
    local index = GlobalValue.Get("REGIME_INDEX")
    return CONFIG.REGIME_INDEX[index or 0] or "EMPIRE"
end

function Court.regime(s)
    return CONFIG.REGIMES[s.regime] or CONFIG.REGIMES.EMPIRE
end

local present = {time = -100, set = {}}
function Court.present_factions()
    local now = GetCurrentTime and GetCurrentTime() or 0
    if now - present.time < 5 and now >= present.time then
        return present.set
    end
    local set = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local owner = planet.Get_Owner()
        if owner then
            set[string.upper(owner.Get_Faction_Name())] = true
        end
    end
    present.time, present.set = now, set
    return set
end

function Court.legitimacy()
    local gov = IMPERIAL_GOVERNMENT
    if type(gov) ~= "table" or type(gov.imperial_table) ~= "table" then
        return nil
    end
    local out, total = {}, 0
    local on_map = Court.present_factions()
    for faction, entry in pairs(gov.imperial_table) do
        if type(entry) == "table" and type(entry.legitimacy) == "number"
                and (on_map[string.upper(faction)] or string.upper(faction) == CONFIG.FACTION) then
            out[faction] = {legitimacy = entry.legitimacy}
            total = total + entry.legitimacy
        end
    end
    for _, entry in pairs(out) do
        entry.share = (total > 0) and (100 * entry.legitimacy / total) or 0
    end
    return out, gov
end

function Court.legitimacy_share(faction)
    local table_ = Court.legitimacy()
    local entry = table_ and table_[faction or CONFIG.FACTION]
    return entry and entry.share or 30
end

function Court.add_legitimacy(faction, amount)
    local _, gov = Court.legitimacy()
    if gov and gov.adjust_legitimacy and gov.imperial_table[faction] then
        pcall(gov.adjust_legitimacy, gov, faction, amount)
    end
end

function Court.new_state()
    return {ready = false, week = 0, next_week = 0, chars = {}, order = {}, next_id = 0, names = {}, lore_used = {},
            sectors = {}, oversectors = {}, world = {}, governor = {}, offices = {}, authority = CONFIG.AUTHORITY.START,
            stability = 50, regime = "EMPIRE", factions = {}, petitions = {}, news = {}, warnings = {},
            integration = {}, ops = {running = {}, reports = {}, counter_until = 0}, attitude = {}, awol = {},
            gained = 0, lost = 0, used_slots = {}, isolated = {}, depth = {}, vacant_since = {}, rebel_pending = {},
            raise_week = -100}
end

local function in_service(s)
    local out = {}
    for i, def in ipairs(LORE.CHARACTERS) do
        if not s.lore_used[i] and not CONFIG.NOT_COURTIERS[def.name] then
            local _, owner = unit_on_map(i)
            if owner == CONFIG.FACTION then
                table.insert(out, i)
            end
        end
    end
    return out
end

local function lore_char(s, lore, title)
    local c = Court.new_char(s, lore, title)
    local _, owner = unit_on_map(lore)
    c.kind = (owner == CONFIG.FACTION) and "unit" or "lore"
    return c
end
Court.lore_char = lore_char

local function hero_world(lore)
    local obj = unit_on_map(lore)
    if not obj then
        return nil
    end
    local ok, planet = pcall(obj.Get_Planet_Location)
    return ok and planet and name_of(planet) or nil
end

local function warlord_leader(warlord_key)
    local data = warlord_data()
    for _, warlord in ipairs(data and data.WARLORDS or {}) do
        if warlord.key == warlord_key then
            for _, unit in ipairs(warlord.leaders or {}) do
                if LORE_BY_UNIT[unit] then
                    return LORE_BY_UNIT[unit], warlord
                end
            end
            return nil, warlord
        end
    end
    return nil
end

function Court.is_seat(s, name)
    local sector = s.sectors[s.world[name or ""] or ""]
    return sector ~= nil and sector.seat == name
end

function Court.fleet_office_rank(s)
    local c = Court.char(s, s.offices and s.offices.FLEET)
    if c and c.fleet_rank then
        c.fleet_rank = nil
    end
end

function Court.lore_fleet_rank(lore)
    local def = LORE.CHARACTERS[lore or 0]
    local rank = def and def.role == "navy" and def.rank
    if rank == "Grand Admiral" then
        return "grand_admiral"
    elseif rank == "Admiral" then
        return "admiral"
    elseif rank == "Captain" then
        return "captain"
    end
    return nil
end

function Court.fleet_members(s, rank)
    local out = {}
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if c.status == "serving" and c.fleet_rank == rank then
            table.insert(out, c)
        end
    end
    return out
end

function Court.fleet_skill(s)
    local c = Court.char(s, s.offices and s.offices.FLEET)
    if not c or c.status ~= "serving" then
        return nil
    end
    local skill = c.skill or 0
    for _, t in ipairs(c.traits or {}) do
        local trait = CONFIG.TRAITS[t]
        skill = skill + ((trait and trait.skill and trait.skill.FLEET) or 0)
    end
    return M.clamp(skill, 0, 100)
end

function Court.fleet_seats(s, rank)
    local def = CONFIG.ADMIRALTY[rank]
    local seats = def.seats
    local skill = def.per_skill and Court.fleet_skill(s)
    if skill then
        seats = seats + M.floor(skill / def.per_skill)
    end
    return M.max(seats, table.getn(Court.fleet_members(s, rank)))
end

function Court.setup(s)
    local held = Court.held(s)
    local profile, fixed = Court.profile()
    s.regime = Court.regime_name()
    s.seen_regimes = {[s.regime] = true}
    s.stability = Court.regime(s).stability
    s.fixed_regime = fixed or profile.regime ~= nil
    s.no_succession = s.fixed_regime or profile.succession == false
    s.no_grand_moffs = profile.grand_moffs == false
    s.focus = profile.focus
    s.no_race = profile.legitimacy_race == false
    build_sectors(s, held)
    if s.no_grand_moffs then
        for _, sector in pairs(s.sectors) do
            sector.oversector = nil
        end
        s.oversectors = {}
    end
    local ruler = Court.regime(s).figure
    if ruler then
        local i = LORE_BY_UNIT[ruler]
        if i then
            s.lore_used[i] = -1
        end
    end
    for _, unit in ipairs(CONFIG.REGIME_DEATHS[s.regime] or {}) do
        local i = LORE_BY_UNIT[unit]
        if i then
            s.lore_used[i] = -1
        end
    end
    local early = (GlobalValue.Get("GALACTIC_YEAR") or 0) < CONFIG.EARLY_YEAR
    s.early = early
    for _, sector in ipairs(Court.sector_list(s)) do
        if sector.warlord and not sector.crown then
            local lore = warlord_leader(sector.warlord)
            local unit, owner = nil, nil
            if lore then
                unit, owner = unit_on_map(lore)
            end
            if owner and owner ~= CONFIG.FACTION and owner ~= "WARLORDS" then
                lore = nil
            end
            if lore and not s.lore_used[lore] then
                local c = lore_char(s, lore, "moff")
                Court.set_title(s, c, "moff", sector.key)
                local mine = {}
                for _, n in ipairs(warlord_worlds[sector.warlord] or {}) do
                    mine[n] = true
                end
                for _, name in ipairs(warlord_worlds[sector.warlord] or {}) do
                    local other = s.sectors[s.world[name] or ""]
                    if other and other ~= sector and not other.crown and not other.holder then
                        local all_theirs = true
                        for _, w in ipairs(other.worlds) do
                            all_theirs = all_theirs and mine[w] == true
                        end
                        if all_theirs then
                            Court.set_title(s, c, "moff", other.key)
                        elseif not s.governor[name] and not Court.is_seat(s, name) then
                            Court.set_title(s, c, "governor", name)
                        end
                    elseif not other and held[name] and not s.governor[name] then
                        Court.set_title(s, c, "governor", name)
                    end
                end
            end
        end
    end
    local pool = in_service(s)
    if not early then
        for _, key in ipairs(sorted_keys(s.oversectors)) do
            for _, i in ipairs(pool) do
                if not s.lore_used[i] and LORE.CHARACTERS[i].rank == "Grand Moff" then
                    Court.set_title(s, lore_char(s, i, "grand_moff"), "grand_moff", key)
                    break
                end
            end
        end
    end
    for _, i in ipairs(pool) do
        if not s.lore_used[i] and LORE.CHARACTERS[i].role == "moff" then
            local here = hero_world(i)
            local sector = here and s.sectors[s.world[here] or ""]
            if not sector or sector.crown or sector.holder then
                sector = nil
                for _, other in ipairs(Court.sector_list(s)) do
                    if not other.crown and not other.holder and table.getn(other.worlds) > 0 then
                        sector = other
                        break
                    end
                end
            end
            local c = lore_char(s, i, "courtier")
            if sector then
                Court.set_title(s, c, "moff", sector.key)
            end
        end
    end
    for _, i in ipairs(pool) do
        if not s.lore_used[i] and LORE.CHARACTERS[i].role == "governor" then
            local here = hero_world(i)
            local c = lore_char(s, i, "courtier")
            if here and held[here] and not s.governor[here] and not Court.is_seat(s, here) then
                Court.set_title(s, c, "governor", here)
            end
        end
    end
    for _, i in ipairs(pool) do
        if not s.lore_used[i] and LORE.CHARACTERS[i].role == "navy" then
            local c = lore_char(s, i, "courtier")
            c.fleet_rank = Court.lore_fleet_rank(i)
        end
    end
    for _, i in ipairs(pool) do
        if not s.lore_used[i] then
            lore_char(s, i, "courtier")
        end
    end
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        local fixed_rank = CONFIG.START_RANKS[c.name]
        if fixed_rank and fixed_rank.fleet then
            c.fleet_rank = fixed_rank.fleet
        end
    end
    for _, role in ipairs(CONFIG.START_ROLES[s.regime] or {}) do
        local i = Court.lore_by_name(role.name)
        local here = i and s.lore_used[i] and s.lore_used[i] > 0 and s.chars[s.lore_used[i]]
        if i and s.lore_used[i] ~= -1 and (here or not role.present) then
            local c = here or lore_char(s, i, "courtier")
            if role.title == "grand_moff" then
                Court.vacate(s, c)
                c.court_gm = true
                c.title, c.holds = "grand_moff", nil
            end
            if not role.keep_rank then
                c.fleet_rank = nil
            end
            c.heir, c.release = role.heir, role.release
            c.protected = role.protected and s.regime or nil
            if role.leads then
                c.leads, c.heir = true, nil
            end
            if role.office then
                s.offices[role.office] = c.id
            end
        end
    end
    for _, key in ipairs(CONFIG.OFFICE_ORDER) do
        local def = CONFIG.OFFICES[key]
        for _, unit in ipairs(def.lore or {}) do
            local i = LORE_BY_UNIT[unit]
            local c = i and s.lore_used[i] and s.lore_used[i] > 0 and s.chars[s.lore_used[i]]
            if c and not s.offices[key] and not Court.office_of(s, c) then
                s.offices[key] = c.id
            end
        end
    end
    for _, key in ipairs(CONFIG.OFFICE_ORDER) do
        for _, cls in ipairs(CONFIG.OFFICE_CLASSES[key] or {}) do
            if s.offices[key] then
                break
            end
            local best
            for _, id in ipairs(s.order) do
                local c = s.chars[id]
                local def = c.lore and LORE.CHARACTERS[c.lore]
                if def and def.class == cls and c.status == "serving" and not Court.office_of(s, c)
                        and (not best or c.skill > best.skill) then
                    best = c
                end
            end
            if best then
                s.offices[key] = best.id
            end
        end
    end
    Court.fleet_office_rank(s)
    for _, name in ipairs(sorted_keys(held)) do
        if not s.governor[name] and not Court.is_seat(s, name) then
            Court.set_title(s, Court.new_char(s, nil, "courtier"), "governor", name)
        end
    end
    Court.lore_ties(s)
    s.ready = true
    Court.refresh_map(s)
    Court.update_vacancies(s)
    Court.count_sectors(s, true)
    local shock = CONFIG.SHOCKS.PALPATINE_KILLED
    if not s.fixed_regime and (GlobalValue.Get("GALACTIC_YEAR") or 99) < shock.before_year then
        Court.add_shock(s, "PALPATINE_KILLED", shock.until_year * 12 + 1)
    end
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        Court.settle_loyalty(s, c)
        Court.opinion(c, "the old order still holds", CONFIG.OLD_ORDER, CONFIG.FADE_MAX)
    end
    pcall(require("eawx-plugins/imperial-court/CourtPolitics").update_factions, s)
    pcall(require("eawx-plugins/imperial-court/CourtFleet").week, s)
    pcall(Court.titles, s)
    local sectors = 0
    for _, _ in pairs(s.sectors) do
        sectors = sectors + 1
    end
    Court.news(s, "The court assembles: " .. sectors .. " sectors, " .. table.getn(s.order) .. " officers and lords.")
end

function Court.recruit(s)
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        local def = c.lore and LORE.CHARACTERS[c.lore]
        if def and CONFIG.NOT_COURTIERS[def.name] and c.status == "serving" and c.title == "courtier"
                and not Court.office_of(s, c) and not c.fleet_rank then
            Court.remove(s, c, "gone")
        end
    end
    for _, i in ipairs(in_service(s)) do
        local c = lore_char(s, i, "courtier")
        if c.role == "navy" then
            local rank = Court.lore_fleet_rank(i)
            if rank and table.getn(Court.fleet_members(s, rank)) < Court.fleet_seats(s, rank) then
                c.fleet_rank = rank
            end
        end
        Court.settle_loyalty(s, c)
        Court.news(s, c.name .. " enters Imperial service.")
    end
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if c.lore and (c.status == "defected" or c.status == "rebel") then
            local _, owner = unit_on_map(c.lore)
            if owner == CONFIG.FACTION then
                c.status, c.title, c.holds, c.faction = "serving", "courtier", nil, nil
                c.traitor, c.kind = true, "unit"
                Court.opinion(c, "back under suspicion", CONFIG.TRAITOR.LOYALTY, 30)
                Court.settle_loyalty(s, c)
                Court.news(s, Court.full_name(c) .. " returns to Imperial service, branded a traitor.")
            end
        end
    end
end

local function absorbed_sectors(s, held)
    for faction, worlds in pairs(s.taken or {}) do
        local rival = false
        for _, f in ipairs(CONFIG.RIVALS) do
            rival = rival or f == faction
        end
        local mine = {}
        for _, name in ipairs(worlds) do
            if held[name] and not s.world[name] and not (s.lore_sector and s.lore_sector[name]) then
                table.insert(mine, name)
            end
        end
        if rival and table.getn(mine) >= CONFIG.ABSORBED_SECTOR then
            s.absorbed = (s.absorbed or 0) + 1
            local key = "A_" .. s.absorbed
            local name = "Former " .. Court.faction_label(faction)
            s.sectors[key] = {key = key, name = name, worlds = {}, seat = mine[1], lore = true}
            for _, w in ipairs(mine) do
                s.world[w] = key
            end
            local GEO_ = GEO[mine[1]]
            s.sectors[key].region = GEO_ and GEO_.region or "Outer Rim"
            if s.oversectors[s.sectors[key].region] then
                s.sectors[key].oversector = s.sectors[key].region
            end
            Court.news(s, "The remnants of " .. Court.faction_label(faction) .. " join the Empire as the " .. name
                .. ". It awaits a Moff.")
        end
    end
    s.taken = {}
end

function Court.refresh_map(s)
    local held = Court.held(s)
    absorbed_sectors(s, held)
    for _, name in ipairs(sorted_keys(s.world)) do
        if not held[name] then
            s.world[name] = nil
        end
    end
    for _, name in ipairs(sorted_keys(s.governor)) do
        if not held[name] then
            local c = Court.char(s, s.governor[name])
            if c then
                Court.vacate(s, c, "governor", name)
                Court.opinion(c, "lost their world", -5, 8)
            end
            s.governor[name] = nil
        end
    end
    Court.static_sectors(s)
    for _, name in ipairs(sorted_keys(held)) do
        if not s.world[name] then
            local key = s.lore_sector and s.lore_sector[name]
            if key and s.sectors[key] then
                s.world[name] = key
            else
                s.world[name] = neighbour_sector(s, name, held)
            end
        end
    end
    Court.index_worlds(s)
    Court.ensure_oversectors(s)
    for _, sector in pairs(s.sectors) do
        if not (sector.seat and s.world[sector.seat] == sector.key) then
            sector.seat = nil
            for _, name in ipairs(sector.members or {}) do
                if s.world[name] == sector.key then
                    sector.seat = name
                    break
                end
            end
            sector.seat = sector.seat or sector.worlds[1]
        end
    end
    local capital = nil
    for _, sector in pairs(s.sectors) do
        if sector.crown and sector.seat then
            capital = sector.seat
        end
    end
    if not capital then
        local best = 0
        for name, _ in pairs(held) do
            local n = table.getn(Court.lanes(name))
            if n > best then
                capital, best = name, n
            end
        end
    end
    s.capital = capital
    local reached = {}
    s.depth = {}
    if capital then
        local queue, head = {capital}, 1
        reached[capital] = true
        s.depth[capital] = 0
        while queue[head] and head < 5000 do
            for _, other in ipairs(Court.lanes(queue[head])) do
                if held[other] and not reached[other] then
                    reached[other] = true
                    s.depth[other] = s.depth[queue[head]] + 1
                    table.insert(queue, other)
                end
            end
            head = head + 1
        end
    end
    s.isolated = {}
    for name, _ in pairs(held) do
        if not reached[name] then
            s.isolated[name] = true
        end
    end
    Court.sync_all(s)
    return held
end

function Court.isolation(s, c)
    local worlds = Court.worlds_of(s, c)
    if table.getn(worlds) == 0 then
        return 0
    end
    local seat = (c.title ~= "grand_moff" or Court.holdings(s, c)[2]) and Court.capital_of(s, c) or nil
    if seat and s.isolated[seat] then
        return 1
    end
    for _, name in ipairs(worlds) do
        if s.isolated[name] then
            return 0.5
        end
    end
    return 0
end

function Court.measure_worlds(s)
    local empire = Court.player()
    local strength, count = {}, {}
    local ok, objects = pcall(Find_All_Objects_Of_Type, empire, "Structure | SpaceStructure")
    if not ok or type(objects) ~= "table" then
        objects = Find_All_Objects_Of_Type(empire) or {}
    end
    for _, obj in pairs(objects) do
        if TestValid(obj) and (obj.Is_Category("Structure") or obj.Is_Category("SpaceStructure")) then
            local ok2, name, rating = pcall(function()
                local planet = obj.Get_Planet_Location()
                return planet and Court.name_of(planet), obj.Get_Type().Get_Combat_Rating()
            end)
            if ok2 and name then
                strength[name] = (strength[name] or 0) + M.max(0, tonumber(rating) or 0)
                count[name] = (count[name] or 0) + 1
            end
        end
    end
    local income, worlds = {}, {}
    local sum_income, sum_strength, n = 0, 0, 0
    for name, owner in pairs(s.world or {}) do
        local planet = FindPlanet(name)
        if planet and planet.Get_Owner() == empire then
            local ok3, value = pcall(EvaluatePerception, "PlanetBaseIncome", empire, planet)
            income[name] = M.clamp((ok3 and tonumber(value)) or 0, 0, 100000)
            sum_income = sum_income + income[name]
            sum_strength = sum_strength + (strength[name] or 0)
            n = n + 1
            table.insert(worlds, name)
        end
    end
    local avg_income = (n > 0 and sum_income > 0) and sum_income / n or nil
    local avg_strength = (n > 0 and sum_strength > 0) and sum_strength / n or nil
    local W = CONFIG.WORLD_VALUE
    s.world_value, s.world_influence = {}, {}
    s.world_income = income
    s.world_structures_old = s.world_structures
    s.world_structures = count
    for _, name in ipairs(worlds) do
        local a = avg_income and income[name] / avg_income or 1
        local b = avg_strength and (strength[name] or 0) / avg_strength or 1
        s.world_value[name] = M.clamp(a * W.INCOME + b * (1 - W.INCOME), W.MIN, W.MAX)
    end
    local service = IMPERIAL_COURT_INFLUENCE_SERVICE
    for _, entry in pairs(service and service.planets or {}) do
        local name = string.upper(entry.object_name or "")
        if s.world_value[name] and type(entry.ownerInfluence) == "number" then
            s.world_influence[name] = entry.ownerInfluence
        end
    end
end

function Court.world_influence(s, name)
    local service = IMPERIAL_COURT_INFLUENCE_SERVICE
    for _, entry in pairs(service and service.planets or {}) do
        if string.upper(entry.object_name or "") == name and type(entry.ownerInfluence) == "number" then
            return entry.ownerInfluence
        end
    end
    return s.world_influence and s.world_influence[name]
end

function Court.land_value(s, c)
    local total = 0
    for _, name in ipairs(Court.worlds_of(s, c)) do
        total = total + ((s.world_value and s.world_value[name]) or 1)
    end
    return total
end

function Court.update_hold(s)
    local H = CONFIG.HOLD
    local old = s.world_structures_old
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if c.status == "serving" and (c.title == "governor" or c.title == "moff" or c.title == "grand_moff") then
            local gained, unstable = 0, 0
            for _, name in ipairs(Court.worlds_of(s, c)) do
                local now = s.world_structures and s.world_structures[name] or 0
                local before = old and old[name]
                local inf = s.world_influence and s.world_influence[name]
                if before and now > before then
                    gained = gained + (now - before)
                end
                if inf and inf < CONFIG.REVOLT_BELOW then
                    unstable = unstable + 1
                end
            end
            local per = (c.title == "governor") and H.GOVERNOR or ((c.title == "moff") and H.MOFF or 0)
            c.hold = M.clamp((c.hold or 0) - H.FADE + gained * per, 0, H.CAP)
            if unstable > 0 then
                c.unrest_blame = M.max(H.UNREST_CAP, (c.unrest_blame or 0) - H.UNREST * M.min(3, unstable))
            else
                c.unrest_blame = M.min(0, (c.unrest_blame or 0) + H.RECOVER)
            end
        end
    end
end

function Court.power(s, c)
    if c.status ~= "serving" then
        return 0
    end
    local p = Court.land_value(s, c)
    local t = CONFIG.TITLES[c.title]
    p = p + (t and t.power_seat or 0)
    if c.title == "grand_moff" then
        p = p * 0.5 + 2
    end
    for _, trait in ipairs(c.traits) do
        p = p + (CONFIG.TRAITS[trait].power or 0)
    end
    if c.office then
        p = p + 2
    end
    if c.fleet_rank and CONFIG.ADMIRALTY[c.fleet_rank] then
        p = p + CONFIG.ADMIRALTY[c.fleet_rank].power
    end
    return p
end

function Court.fief_gap(c)
    local F = CONFIG.FIEF
    local want = F.WANT[c.fleet_rank or ""]
    if not want or c.status ~= "serving" then
        return 0
    end
    return M.max(0, want - (F.HELD[c.title] or 0))
end

function Court.fief_penalty(s, c)
    local F = CONFIG.FIEF
    local gap = Court.fief_gap(c)
    local waited = (c.fief_wait or 0) - F.GRACE
    if gap <= 0 or waited <= 0 then
        return 0, 0
    end
    local nature = 1
    for _, t in ipairs(c.traits) do
        nature = nature * (F.NATURE[t] or 1)
    end
    local ranks = (gap == 1) and "a rank" or (gap .. " ranks")
    return ranks, -gap * F.PER_RANK * M.min(1, waited / F.GROW) * nature
end

function Court.next_regime(s)
    local list = CONFIG.SUCCESSION
    for k, key in ipairs(list) do
        if key == s.regime then
            return list[k + 1]
        end
    end
    if s.regime == "CCOGM" then
        return "THRAWN"
    end
    for _, key in ipairs(list) do
        if not (s.seen_regimes and s.seen_regimes[key]) then
            return key
        end
    end
    return nil
end

function Court.partial_share(s, sector)
    return (s.partial and s.partial[sector.key]) or 0
end

function Court.underworld_on(s, c)
    if type(DIPLOMACY_UNDERWORLD_STRENGTH) ~= "function" then
        return 0
    end
    local best = 0
    for _, name in ipairs(Court.worlds_of(s, c)) do
        local ok, v = pcall(DIPLOMACY_UNDERWORLD_STRENGTH, name)
        if ok and type(v) == "number" and v > best then
            best = v
        end
    end
    return best
end

function Court.loyalty_parts(s, c)
    local L = CONFIG.LOYALTY
    local regime = Court.regime(s)
    local parts = {}
    local function add(value, text, rate)
        value = M.round(value)
        if value ~= 0 then
            table.insert(parts, {text = text, value = value, rate = rate})
        end
    end
    if (c.hold or 0) > 0 then
        add(c.hold, "the throne strengthens their hold")
    end
    if (c.unrest_blame or 0) < 0 then
        add(c.unrest_blame, "unrest left to fester on their worlds")
    end
    if (s.relief_weeks or 0) > 0 then
        add(CONFIG.RELIEF.LOYALTY, "the malcontents have made their move")
    end
    if c.temper and c.temper ~= 0 then
        add(c.temper, (c.temper > 0) and "a loyal temper" or "a restless temper", 1)
    end
    add(regime.loyalty or 0, "the regime: " .. regime.title)
    if c.title == "grand_moff" and regime.grand_moffs then
        add(regime.grand_moffs, "Grand Moffs under this regime")
    elseif c.title == "moff" and regime.moffs then
        add(regime.moffs, "Moffs under this regime")
    end
    if regime.loyalty_rise and s.regime_weeks then
        add(M.min(10, s.regime_weeks * regime.loyalty_rise), "years of steady rule")
    end
    for _, t in ipairs(c.traits) do
        local def = CONFIG.TRAITS[t]
        if def.loyalty then
            add(def.loyalty, def.name)
        end
        if def.likes and def.likes[s.regime] then
            add(def.likes[s.regime], def.name .. ": likes the regime")
        end
        if def.dislikes and def.dislikes[s.regime] then
            add(-def.dislikes[s.regime], def.name .. ": dislikes the regime")
        end
    end
    add((Court.legitimacy_share() - 30) * L.LEGITIMACY, "the Empire's legitimacy")
    add((s.stability - 50) * L.STABILITY, "Imperial stability", L.STABILITY_RATE)
    local iso = Court.isolation(s, c)
    if iso >= 1 then
        add(-L.ISOLATED, "cut off from the core")
    elseif iso > 0 then
        add(-L.ISOLATED_SOME, "some worlds cut off from the core")
    end
    local seat = Court.capital_of(s, c)
    local depth = seat and s.depth and s.depth[seat]
    local D = CONFIG.DISTANCE
    if depth and depth > D.FREE_JUMPS and iso < 1 then
        add(-M.min(D.CAP, (depth - D.FREE_JUMPS) * D.PER_JUMP), "far from the capital (" .. depth .. " jumps)")
    end
    if (c.title == "moff" or c.title == "grand_moff") and (s.vacancy or 0) > 0 then
        add(-M.min(1, s.vacancy / CONFIG.VACANT.FULL) * CONFIG.VACANT.LOYALTY_CAP, "worlds left without a lord")
    elseif c.title == "governor" and (s.vacancy or 0) > 0 then
        add(-M.min(1, s.vacancy / CONFIG.VACANT.FULL) * CONFIG.VACANT.LOYALTY_CAP / 2, "worlds left without a lord")
    end
    local short, fief_v = Court.fief_penalty(s, c)
    if fief_v < 0 then
        add(fief_v, "no lands to match their rank (" .. short .. " short)")
    end
    local sector = (c.title == "moff") and s.sectors[c.holds or ""]
    if sector and not sector.crown and (c.partial_weeks or 0) > 0 then
        local P = CONFIG.PARTIAL_SECTOR
        local v = Court.partial_share(s, sector) * P.PER_SHARE * M.min(1, c.partial_weeks / P.GROW)
        add(-M.min(P.CAP, v), "their sector is not whole")
    end
    if not Court.has_trait(c, "corrupt") then
        local crime = Court.underworld_on(s, c)
        if crime > 0 then
            add(-M.min(CONFIG.UNDERWORLD.CAP, crime * CONFIG.UNDERWORLD.PER_TIER), "Hutt crime on their worlds")
        end
    end
    local ok_t, T = pcall(require, "eawx-plugins/imperial-court/CourtTerritory")
    if ok_t and T then
        for _, part in ipairs(T.loyalty_parts(s, c)) do
            add(part[1], part[2])
        end
    end
    local traitors = 0
    for _, other in ipairs(Court.traitors_in_office(s)) do
        if other ~= c then
            traitors = traitors + 1
        end
    end
    if traitors > 0 then
        add(CONFIG.TRAITOR.OPINION * M.min(2, traitors), "traitors in high places")
    end
    if c.traitor then
        add(CONFIG.TRAITOR.LOYALTY / 2, "a traitor's welcome")
    end
    if c.ambition > 50 then
        add(-(c.ambition - 50) * L.AMBITION, "ambition")
    end
    local power = Court.power(s, c)
    if power > L.POWER_FROM then
        local nature = 1
        for _, t in ipairs(c.traits) do
            nature = nature * (L.POWER_NATURE[t] or 1)
        end
        add(-M.min(L.POWER_CAP, (power - L.POWER_FROM) * L.POWER_PER * nature), "power goes to their head")
    end
    if c.heir and not c.leads then
        add(CONFIG.HEIR_LOYALTY, "their claim to the throne")
        if Court.next_regime(s) == c.heir then
            add(CONFIG.NEXT_LOYALTY, "next in line")
        end
    end
    if c.minder and not Court.has_trait(c, "paranoid") then
        add(L.MINDER, "watched by a minder")
    end
    local compnor = s.office_power and s.office_power.COMPNOR or 0
    if compnor > 0 then
        add(compnor, "COMPNOR propaganda")
    end
    local speaker = s.office_power and s.office_power.SPEAKER or 0
    if speaker > 0 and (c.title == "moff" or c.title == "grand_moff" or s.regime == "PALPATINE") then
        add(speaker, Court.office_def(s, "SPEAKER").name)
    end
    if not Court.player().Is_Human() then
        add(CONFIG.AI.LOYALTY, "a steady hand at court")
    end
    return parts
end

function Court.settle_loyalty(s, c)
    c.mods = {}
    for _, p in ipairs(Court.loyalty_parts(s, c)) do
        c.mods[p.text] = p.value
    end
    Court.update_loyalty(s, c)
end

function Court.update_loyalty(s, c)
    if not c.mods then
        return Court.settle_loyalty(s, c)
    end
    local total = CONFIG.LOYALTY.BASE
    for _, v in pairs(c.mods) do
        total = total + v
    end
    total = total + Court.opinion_total(c)
    local regime = Court.regime(s)
    if regime.fear and total < regime.fear then
        total = regime.fear
    end
    if c.leads then
        total = 100
    end
    c.loyalty = M.clamp(total, 0, 100)
    return c.loyalty
end

function Court.tick_loyalty(s, c)
    local L = CONFIG.LOYALTY
    if not c.mods then
        Court.settle_loyalty(s, c)
    end
    local goals = {}
    for _, p in ipairs(Court.loyalty_parts(s, c)) do
        goals[p.text] = p
    end
    local keys = {}
    for text, _ in pairs(c.mods) do
        keys[text] = true
    end
    for text, _ in pairs(goals) do
        keys[text] = true
    end
    for text, _ in pairs(keys) do
        local now = c.mods[text] or 0
        local p = goals[text]
        local goal = p and p.value or 0
        local gap = goal - now
        local step = M.max(L.STEP, M.abs(gap) * ((p and p.rate) or L.RATE))
        if M.abs(gap) <= step then
            now = goal
        else
            now = now + ((gap > 0) and step or -step)
        end
        c.mods[text] = (now ~= 0) and now or nil
    end
    local keep = {}
    for _, o in ipairs(c.opinion) do
        if o.weeks then
            o.total = o.total or o.weeks
            o.weeks = o.weeks - 1
        end
        if not o.weeks or o.weeks > 0 then
            table.insert(keep, o)
        end
    end
    c.opinion = keep
    return Court.update_loyalty(s, c)
end

function Court.loyalty_target(s, c)
    local L = CONFIG.LOYALTY
    if not c.mods then
        Court.settle_loyalty(s, c)
    end
    local reasons, target, speed = {}, L.BASE, 0
    local seen = {}
    for _, p in ipairs(Court.loyalty_parts(s, c)) do
        seen[p.text] = true
        local now = c.mods[p.text] or 0
        target = target + p.value
        local gap = p.value - now
        local step = M.min(M.abs(gap), M.max(L.STEP, M.abs(gap) * (p.rate or L.RATE)))
        speed = speed + ((gap > 0) and step or -step)
        table.insert(reasons, {text = p.text, value = M.round(now), goal = p.value})
    end
    for text, now in pairs(c.mods) do
        if not seen[text] then
            local step = M.min(M.abs(now), M.max(L.STEP, M.abs(now) * L.RATE))
            speed = speed + ((now > 0) and -step or step)
            table.insert(reasons, {text = text .. " (fading)", value = M.round(now), goal = 0})
        end
    end
    for _, o in ipairs(c.opinion) do
        local now = Court.opinion_now(o)
        if o.weeks then
            speed = speed - o.value / M.max(1, o.total or o.weeks)
        else
            target = target + o.value
        end
        if M.round(now) ~= 0 then
            table.insert(reasons, {text = o.text, value = M.round(now), goal = o.weeks and 0 or o.value,
                                   weeks = o.weeks})
        end
    end
    local regime = Court.regime(s)
    if regime.fear and target < regime.fear then
        table.insert(reasons, {text = "fear of the Emperor (a floor)", value = 0, goal = regime.fear})
        target = regime.fear
    end
    if c.leads then
        target, speed = 100, 0
    end
    return M.clamp(target, 0, 100), reasons, speed
end

function Court.loyalty_word(v)
    if v >= 80 then
        return "Devoted"
    elseif v >= 60 then
        return "Loyal"
    elseif v >= 40 then
        return "Wavering"
    elseif v >= 20 then
        return "Disloyal"
    end
    return "Treacherous"
end

function Court.stability_word(v)
    for _, entry in ipairs(CONFIG.STABILITY.WORDS) do
        if v < entry[1] then
            return entry[2]
        end
    end
    return "Steady"
end

function Court.office_strength(s, key)
    local c = Court.char(s, s.offices[key])
    if not c or c.status ~= "serving" then
        return 0
    end
    local skill = c.skill
    local def = CONFIG.OFFICES[key]
    for _, t in ipairs(c.traits) do
        local trait = CONFIG.TRAITS[t]
        skill = skill + ((trait.skill and trait.skill[key]) or 0)
    end
    skill = M.clamp(skill, 0, 100) / 100
    local regime = Court.regime(s)
    local mult = (regime.offices or 1) * (regime.drained or 1)
    if c.loyalty < CONFIG.OFFICE_RISK then
        return -skill * (CONFIG.OFFICE_RISK - c.loyalty) / CONFIG.OFFICE_RISK
    end
    return skill * M.min(1, (c.loyalty - 20) / 40) * mult
end

local function apply_offices(s)
    local empire = Court.player()
    local power = {}
    for _, key in ipairs(CONFIG.OFFICE_ORDER) do
        local e = Court.office_strength(s, key)
        local value = CONFIG.OFFICE_VALUES[key] or 0
        power[key] = M.round(e * value)
    end
    s.office_power = power
    s.authority = M.clamp(s.authority + Court.regime(s).authority + M.max(0, power.VIZIER), 0, CONFIG.AUTHORITY.MAX)
    local credits = power.FLEET + power.TREASURY
    local income = Court.regime(s).income
    if income then
        credits = credits + income * 4000 * M.min(1, Court.world_count(s) / 60)
    end
    if credits ~= 0 and empire then
        empire.Give_Money(M.round(credits))
    end
    s.week_credits = M.round(credits)
end

function Court.world_count(s)
    local n = 0
    for _, _ in pairs(s.world) do
        n = n + 1
    end
    return n + table.getn(Court.direct_worlds(s))
end

function Court.month()
    return (GlobalValue.Get("GALACTIC_YEAR") or 0) * 12 + (GlobalValue.Get("GALACTIC_MONTH") or 1)
end

function Court.shock_now(shock)
    local now = Court.month()
    if now >= shock.to then
        return 0
    end
    local span = M.max(1, shock.to - shock.from)
    return shock.value * M.min(1, (shock.to - now) / span)
end

function Court.add_shock(s, key, to)
    local def = CONFIG.SHOCKS[key]
    s.shocks = s.shocks or {}
    for i = table.getn(s.shocks), 1, -1 do
        if s.shocks[i].key == key then
            table.remove(s.shocks, i)
        end
    end
    local now = Court.month()
    to = to or (now + (def.months or 6))
    if to > now then
        table.insert(s.shocks, {key = key, text = def.text, value = def.value, from = now, to = to})
    end
end

function Court.drop_shock(s, key)
    for i = table.getn(s.shocks or {}), 1, -1 do
        if s.shocks[i].key == key then
            table.remove(s.shocks, i)
        end
    end
end

function Court.count_sectors(s, quiet)
    s.partial, s.united = {}, s.united or {}
    for key, sector in pairs(s.sectors) do
        if not sector.crown then
            local members = Court.sector_members(s, sector)
            local total, held = table.getn(members), table.getn(sector.worlds)
            if total > 0 and held > 0 and held < total then
                s.partial[key] = (total - held) / total
            end
            if total >= 2 and held >= total and not s.united[key] then
                s.united[key] = true
                if not quiet then
                    Court.add_legitimacy(CONFIG.FACTION, CONFIG.LEGITIMACY_GAINS.SECTOR_UNITED)
                    Court.news(s, "The whole " .. sector.name .. " is under Imperial rule again: legitimacy rises.")
                end
            end
        end
    end
end

function Court.stability_target(s)
    local S = CONFIG.STABILITY
    local reasons = {}
    local regime = Court.regime(s)
    local target = regime.stability
    table.insert(reasons, {text = "the regime: " .. regime.title, value = regime.stability})
    local total, n = 0, 0
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if c.status == "serving" and c.title ~= "courtier" and not c.leads then
            total, n = total + c.loyalty, n + 1
        end
    end
    local avg = (n > 0) and total / n or 50
    local v = M.clamp(M.round((avg - 50) * S.LOYALTY), -S.LOYALTY_CAP, S.LOYALTY_CAP)
    target = target + v
    table.insert(reasons, {text = "the lords' loyalty", value = v})
    v = M.round((Court.legitimacy_share() - 30) * S.LEGITIMACY)
    target = target + v
    table.insert(reasons, {text = "legitimacy", value = v})
    local army = s.office_power and s.office_power.ARMY or 0
    local compnor = s.office_power and s.office_power.COMPNOR or 0
    if army ~= 0 then
        target = target + army
        table.insert(reasons, {text = "the Army's High Command", value = army})
    end
    if compnor ~= 0 then
        target = target + M.round(compnor / 2)
        table.insert(reasons, {text = "COMPNOR", value = M.round(compnor / 2)})
    end
    if (s.vacancy or 0) > 0 then
        v = -M.round(M.min(1, s.vacancy / CONFIG.VACANT.FULL) * CONFIG.VACANT.STABILITY_CAP)
        if v ~= 0 then
            target = target + v
            table.insert(reasons, {text = "worlds left without a lord", value = v})
        end
    end
    local fleet = 0
    for _, rank in ipairs(CONFIG.ADMIRALTY_ORDER) do
        for _, c in ipairs(Court.fleet_members(s, rank)) do
            fleet = fleet + ((c.loyalty >= 50) and CONFIG.ADMIRALTY[rank].stability or 0)
        end
    end
    if fleet > 0 then
        target = target + fleet
        table.insert(reasons, {text = "a loyal Admiralty", value = fleet})
    end
    local traitors = table.getn(Court.traitors_in_office(s))
    if traitors > 0 then
        v = -CONFIG.TRAITOR.STABILITY * traitors
        target = target + v
        table.insert(reasons, {text = "traitors in office", value = v})
    end
    local rival = Court.top_rival()
    local legit = Court.legitimacy()
    if rival and legit and legit[CONFIG.FACTION] and legit[rival] and legit[rival].legitimacy > legit[CONFIG.FACTION].legitimacy then
        target = target - CONFIG.LEGITIMACY.OUTPACED
        table.insert(reasons, {text = "outpaced by " .. Court.faction_label(rival), value = -CONFIG.LEGITIMACY.OUTPACED})
    end
    if not Court.player().Is_Human() then
        target = target + CONFIG.AI.STABILITY
        table.insert(reasons, {text = "a steady hand at court", value = CONFIG.AI.STABILITY})
    end
    for _, shock in ipairs(s.shocks or {}) do
        v = M.round(Court.shock_now(shock))
        if v ~= 0 then
            target = target + v
            table.insert(reasons, {text = string.lower(shock.text), value = v})
        end
    end
    local losses = M.min(S.LOSS_CAP, s.lost * S.WORLD_LOST) - s.gained * S.WORLD_GAINED
    if losses ~= 0 then
        target = target - losses
        table.insert(reasons, {text = "worlds lost and won lately", value = -losses})
    end
    return M.clamp(target, 0, 100), reasons, avg
end

local function apply_stability(s)
    local target = Court.stability_target(s)
    s.stability = M.clamp(s.stability + (target - s.stability) * CONFIG.STABILITY.DRIFT, 0, 100)
    local credits = M.round(CONFIG.STABILITY.TAX_PER_WORLD * Court.world_count(s) * (s.stability - 50) / 50)
    local empire = Court.player()
    if credits ~= 0 and empire then
        empire.Give_Money(credits)
    end
    s.week_taxes = credits
    local U = CONFIG.UNREST
    local old = s.unrest or 0
    if s.stability < U.BELOW then
        s.low_weeks = (s.low_weeks or 0) + 1
        s.unrest = M.min(U.CAP, 1 + M.floor((s.low_weeks - 1) / U.STEP) + ((s.stability < U.DEEP) and 1 or 0))
    else
        s.low_weeks, s.unrest = 0, 0
    end
    IMPERIAL_COURT_UNREST = s.unrest
    if s.unrest > old then
        local text = "Unrest spreads across the Empire: every world loses " .. s.unrest .. " influence until stability recovers."
        Court.news(s, text)
        Court.alert(text, "threat")
    elseif s.unrest == 0 and old > 0 then
        Court.news(s, "Stability returns: the worlds' unrest eases.")
    end
    s.lost = M.max(0, s.lost - 1)
    s.gained = M.max(0, s.gained - 1)
end

local function weekly_people(s)
    local regime = Court.regime(s)
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if c.status == "serving" then
            if Court.fief_gap(c) > 0 then
                c.fief_wait = (c.fief_wait or 0) + 1
            else
                c.fief_wait = nil
            end
            local sector = (c.title == "moff") and s.sectors[c.holds or ""]
            if sector and Court.partial_share(s, sector) > 0 then
                c.partial_weeks = (c.partial_weeks or 0) + 1
            else
                c.partial_weeks = nil
            end
            Court.tick_loyalty(s, c)
            local t = CONFIG.TITLES[c.title]
            local gain = (t and t.influence or 0) + (Court.office_of(s, c) and CONFIG.OFFICE_INFLUENCE or 0)
            for _, trait in ipairs(c.traits) do
                gain = gain + (CONFIG.TRAITS[trait].influence or 0)
            end
            c.influence = M.clamp(c.influence + gain, 0, 200)
            c.office = Court.office_of(s, c)
            if c.lore then
                local _, owner = unit_on_map(c.lore)
                c.kind = (owner == CONFIG.FACTION) and "unit" or "lore"
                if owner and owner ~= CONFIG.FACTION and owner ~= "WARLORDS" and c.status == "serving" then
                    Court.remove(s, c, "gone", "now serves " .. Court.faction_label(owner))
                end
            end
            if regime.tithe and c.title ~= "courtier" and M.chance(regime.tithe * 100) then
                Court.remove(s, c, "dead", "was summoned to Byss and never returned")
            end
        end
    end
end

function Court.remove(s, c, status, why)
    local full = Court.full_name(c)
    if status == "dead" and c.status == "serving" and (c.title ~= "courtier" or Court.office_of(s, c) or c.fleet_rank) then
        local D = CONFIG.DEATH
        local loss = M.min(D.STABILITY_CAP, D.STABILITY + Court.power(s, c) * D.PER_POWER)
        s.stability = M.max(0, s.stability - loss)
    end
    if status ~= "serving" and (status == "defected" or status == "rebel") then
        c.traitor = true
    end
    c.fleet_rank = nil
    Court.vacate(s, c)
    for key, id in pairs(s.offices) do
        if id == c.id then
            s.offices[key] = nil
        end
    end
    for _, f in pairs(s.factions or {}) do
        local ids, leader, best = {}, nil, -1
        for _, id in ipairs(f.members or {}) do
            local v = s.chars[id]
            if id ~= c.id and v and v.status == "serving" then
                table.insert(ids, id)
                local p = Court.power(s, v)
                if p > best then
                    leader, best = id, p
                end
            end
        end
        f.members = ids
        if f.leader == c.id or not s.chars[f.leader or -1] or s.chars[f.leader].status ~= "serving" then
            f.leader = leader
        end
    end
    c.faction_key, c.loyalist = nil, nil
    c.status = status
    c.left_week = s.week
    if why then
        Court.news(s, full .. " " .. why .. ".")
    end
end

local function planet_objects(names)
    local out = {}
    for _, name in ipairs(names) do
        local planet = FindPlanet(name)
        if planet then
            table.insert(out, planet)
        end
    end
    return out
end

local function free_slot(s)
    local data = warlord_data()
    for _, slot in ipairs(data and data.BREAKAWAY or {}) do
        local player = not s.used_slots[slot.faction] and Find_Player(slot.faction)
        if player then
            local owns = false
            for _, planet in pairs(FindPlanet.Get_All_Planets()) do
                if planet.Get_Owner() == player then
                    owns = true
                    break
                end
            end
            if not owns then
                return slot, player
            end
        end
    end
    return nil
end

local function name_faction(faction, text_id, display)
    if Engine_Set_Text and text_id then
        pcall(Engine_Set_Text, text_id, display)
    end
    local ok, constants = pcall(ModContentLoader.get, "GameConstants")
    if ok and type(constants) == "table" and constants.ALL_FACTION_NAMES then
        constants.ALL_FACTION_NAMES[faction] = display
    end
    if DIPLOMACY_RENAME then
        pcall(DIPLOMACY_RENAME, faction, display)
    end
end

local function followers_of(s, c)
    local out = {[c.id] = true}
    for _, id in ipairs(s.order) do
        local v = s.chars[id]
        if v.status == "serving" and v ~= c and Court.liege(s, v) == c and v.loyalty < CONFIG.FOLLOW_LOYALTY then
            out[v.id] = true
        end
    end
    return out
end

function Court.own_warlord(s, c)
    local def = c.lore and LORE.CHARACTERS[c.lore]
    local data = warlord_data()
    if not def or not data then
        return nil
    end
    local mine = {}
    for _, unit in ipairs(def.units or {}) do
        mine[string.upper(unit)] = true
    end
    for _, warlord in ipairs(data.WARLORDS or {}) do
        for _, unit in ipairs(warlord.leaders or {}) do
            if mine[string.upper(unit)] then
                return warlord
            end
        end
    end
    return nil
end

function Court.seat_of(s, c)
    return Court.capital_of(s, c)
end

function Court.transfer_worlds(s, planets, player)
    DIPLOMACY_REVOLTS = DIPLOMACY_REVOLTS or {}
    for _, planet in ipairs(planets) do
        DIPLOMACY_REVOLTS[string.upper(Court.name_of(planet))] = {kind = "LORD", time = GetCurrentTime()}
    end
    local empire = Court.player()
    local leaving = {}
    for _, planet in ipairs(planets) do
        leaving[Court.name_of(planet)] = planet
    end
    local ok_lists, station_lists = pcall(require, "StructureCategoryLists")
    local convert, retreat, doomed = {}, {}, {}
    local function where(obj)
        local ok, name = pcall(function()
            local at = obj.Get_Planet_Location()
            return at and TestValid(at) and Court.name_of(at) or nil
        end)
        return ok and name or nil
    end
    local function to_despawn(obj)
        for _, other in ipairs(doomed) do
            if other == obj then
                return false
            end
        end
        table.insert(doomed, obj)
        return true
    end
    local worlds = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        worlds[Court.name_of(planet)] = true
    end
    local function is_world(obj)
        local ok, yes = pcall(function()
            return worlds[string.upper(obj.Get_Type().Get_Name())]
        end)
        return not ok or yes
    end
    for _, obj in pairs(Find_All_Objects_Of_Type(empire) or {}) do
        local name = TestValid(obj) and not is_world(obj) and where(obj)
        if name and leaving[name] then
            do
                local hero = obj.Is_Category("SpaceHero") or obj.Is_Category("InfantryHero") or obj.Is_Category("VehicleHero")
                    or obj.Is_Category("NonCombatHero") or obj.Get_Type().Is_Hero()
                local structure = obj.Is_Category("Structure") or obj.Is_Category("SpaceStructure")
                local ground = obj.Is_Category("Infantry") or obj.Is_Category("Vehicle") or obj.Is_Category("AirGunship")
                    or obj.Is_Category("AirSpeeder")
                if structure and not hero then
                    local secondary = obj.Is_Category("Structure")
                        or (ok_lists and type(is_secondary_space_structure) == "function"
                            and is_secondary_space_structure(obj, station_lists))
                    if secondary and to_despawn(obj) then
                        convert[name] = convert[name] or {}
                        table.insert(convert[name], obj.Get_Type())
                    end
                elseif string.upper(obj.Get_Type().Get_Name()) ~= "GALACTIC_FLEET" then
                    local relevant = (type(get_relevant_object) == "function" and get_relevant_object(obj)) or obj
                    if TestValid(relevant) and not is_world(relevant) and to_despawn(relevant) then
                        if ground and not hero then
                            convert[name] = convert[name] or {}
                            table.insert(convert[name], relevant.Get_Type())
                        else
                            table.insert(retreat, relevant.Get_Type())
                        end
                    end
                end
            end
        end
    end
    for _, obj in pairs(Find_All_Objects_Of_Type(empire) or {}) do
        if TestValid(obj) and string.upper(obj.Get_Type().Get_Name()) == "GALACTIC_FLEET" then
            local name = where(obj)
            if name and leaving[name] then
                to_despawn(obj)
            end
        end
    end
    for _, obj in ipairs(doomed) do
        if TestValid(obj) then
            pcall(obj.Despawn)
        end
    end
    local ok_w, W = pcall(require, "eawx-plugins/warlords/Warlords")
    W = ok_w and type(Warlords) == "table" and Warlords or nil
    local levels = W and W.starbase_levels and W.starbase_levels(planets)
    for _, planet in ipairs(planets) do
        planet.Change_Owner(player)
    end
    if levels then
        pcall(W.restore_starbases, levels, player)
    end
    for name, types in pairs(convert) do
        for _, unit_type in ipairs(TestValid(leaving[name]) and types or {}) do
            pcall(Spawn_Unit, unit_type, leaving[name], player)
        end
    end
    if table.getn(retreat) > 0 then
        local capital = s.capital and FindPlanet(s.capital)
        if not capital or capital.Get_Owner() ~= empire then
            capital = StoryUtil and StoryUtil.FindFriendlyPlanet(empire, true)
        end
        if not TestValid(capital) then
            capital = nil
        end
        for _, unit_type in ipairs(capital and retreat or {}) do
            pcall(Spawn_Unit, unit_type, capital, empire)
        end
        if capital then
            Court.alert("Our forces at the breakaway worlds fall back to " .. Court.planet_label(Court.name_of(capital)) .. ".",
                "request")
        end
    end
end

local function arm_breakaway(faction, player, peaceful)
    local ok, constants = pcall(ModContentLoader.get, "GameConstants")
    if ok and type(constants) == "table" and constants.ALL_FACTIONS_AI then
        constants.ALL_FACTIONS_AI[faction] = CONFIG.BREAKAWAY_AI
    end
    if StoryUtil and StoryUtil.ChangeAIPlayer and not player.Is_Human() then
        pcall(StoryUtil.ChangeAIPlayer, faction, CONFIG.BREAKAWAY_AI)
    end
    local empire = Court.player()
    if peaceful then
        if DIPLOMACY_SET_RELATION then
            pcall(DIPLOMACY_SET_RELATION, faction, "CEASEFIRE")
        end
    else
        if DIPLOMACY_SET_RELATION then
            pcall(DIPLOMACY_SET_RELATION, faction, "WAR")
        end
        empire.Make_Enemy(player)
        player.Make_Enemy(empire)
    end
end

function Court.defer(s, kind, c, why, peaceful)
    if not IMPERIAL_COURT_IN_CLICK then
        return false
    end
    s.deferred = s.deferred or {}
    table.insert(s.deferred, {kind = kind, char = c.id, why = why, peaceful = peaceful})
    return true
end

function Court.run_deferred(s)
    local list = s.deferred
    s.deferred = nil
    for _, job in ipairs(list or {}) do
        local c = s.chars[job.char]
        if c and c.status == "serving" then
            local ok, err
            if job.kind == "break_away" then
                ok, err = pcall(Court.break_away, s, c, job.why, job.peaceful)
            else
                ok, err = pcall(Court.defect, s, c)
            end
            if not ok then
                log("deferred " .. job.kind .. " error: " .. tostring(err))
            end
        end
    end
end

function Court.break_away(s, c, why, peaceful)
    if c.heir or c.leads then
        return nil
    end
    if c.minder then
        return nil
    end
    if Court.defer(s, "break_away", c, why, peaceful) then
        return "PENDING"
    end
    local followers = followers_of(s, c)
    local empire = Court.player()
    local planets, worlds = {}, {}
    for _, planet in ipairs(planet_objects(Court.worlds_of(s, c, followers))) do
        if planet.Get_Owner() == empire then
            table.insert(planets, planet)
            table.insert(worlds, Court.name_of(planet))
        end
    end
    if table.getn(planets) == 0 then
        return Court.defect(s, c) and c.faction or nil
    end
    local faction, display, player
    local sector = (c.title == "moff") and s.sectors[c.holds or ""] or nil
    local warlord = Court.own_warlord(s, c)
    if not warlord and sector and sector.warlord then
        for _, w in ipairs((warlord_data() or {}).WARLORDS or {}) do
            if w.key == sector.warlord then
                warlord = w
            end
        end
    end
    player = warlord and Find_Player(warlord.faction)
    if player then
        faction, display = warlord.faction, warlord.display
    else
        warlord = nil
        local slot
        slot, player = free_slot(s)
        if not slot then
            Court.news(s, Court.full_name(c) .. " wanted to break away, but no banner was left to raise: they stay, seething.")
            Court.opinion(c, "could not break away", -10, 10)
            return nil
        end
        display = (Court.holding_name(s, c) or c.name)
        display = string.gsub(display, "^the ", "")
        name_faction(slot.faction, slot.text, display)
        s.used_slots[slot.faction] = {char = c.id, name = display}
        faction = slot.faction
    end
    for id, _ in pairs(followers) do
        local v = s.chars[id]
        if v then
            Court.take_unit(v, player)
        end
    end
    local seat = Court.capital_of(s, c)
    Court.transfer_worlds(s, planets, player)
    local home = seat and FindPlanet(seat)
    if not home or home.Get_Owner() ~= player then
        home = planets[1]
    end
    local ok_c, constants = pcall(ModContentLoader.get, "GameConstants")
    if ok_c and type(constants) == "table" and type(constants.ALL_FACTIONS_CAPITALS) == "table" then
        local entry = constants.ALL_FACTIONS_CAPITALS[faction]
        if not (entry and entry.STRUCTURE) then
            constants.ALL_FACTIONS_CAPITALS[faction] = {LOCATION = {Court.name_of(home)}}
        end
    end
    if warlord then
        pcall(require, "eawx-plugins/warlords/Warlords")
        if type(Warlords) == "table" and Warlords.raise then
            pcall(Warlords.raise, warlord.key, home, player, CONFIG.FACTION)
        end
    end
    arm_breakaway(faction, player, peaceful)
    if peaceful then
        s.attitude[faction] = (s.attitude[faction] or 0) + CONFIG.OPINION.RECOGNISED
    end
    s.attitude[faction] = (s.attitude[faction] or 0) + CONFIG.OPINION.LEAVING
    s.broke_away = s.broke_away or {}
    s.broke_away[faction] = true
    local full = Court.full_name(c)
    for id, _ in pairs(followers) do
        local v = s.chars[id]
        if v and v ~= c then
            Court.remove(s, v, "rebel")
            v.faction = faction
        end
    end
    Court.remove(s, c, "rebel")
    c.faction = faction
    s.breakaway_leader = s.breakaway_leader or {}
    s.breakaway_leader[string.upper(faction)] = c.id
    for _, id in ipairs(s.order) do
        local v = s.chars[id]
        if v.status == "serving" then
            if Court.is_friend(v, c.id) then
                Court.opinion(v, "their friend was driven out", CONFIG.OPINION.FRIEND_PUNISHED, 12)
            elseif v.loyalty >= 70 then
                Court.opinion(v, "closing ranks after a betrayal", 5, 8)
            end
        end
    end
    s.stability = M.max(0, s.stability - CONFIG.BREAKAWAY_STABILITY)
    Court.news(s, full .. " breaks away" .. (why and (" (" .. why .. ")") or "") .. ": " .. table.getn(worlds)
        .. ((table.getn(worlds) == 1) and " world" or " worlds") .. " under a new banner, " .. (display or faction) .. ".")
    Court.alert("Breakaway: " .. full .. " declares independence with " .. table.getn(worlds)
        .. ((table.getn(worlds) == 1) and " world." or " worlds."), "threat")
    if REPUBLIC_BREAKAWAY_NEWS then
        pcall(REPUBLIC_BREAKAWAY_NEWS, faction, display or faction, full, worlds)
    end
    return faction
end

function Court.relief(s)
    local R = CONFIG.RELIEF
    s.stability = M.min(100, s.stability + R.STABILITY)
    s.relief_weeks = R.WEEKS
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if c.status == "serving" and c.mods then
            Court.update_loyalty(s, c)
        end
    end
    Court.news(s, "With the malcontents gone, the court closes ranks: stability and loyalty rise for a while.")
end

function Court.top_rival()
    local legit = Court.legitimacy()
    local best, best_v = nil, 0
    for faction, entry in pairs(legit or {}) do
        if faction ~= CONFIG.FACTION and entry.legitimacy > best_v and Find_Player(faction) then
            best, best_v = faction, entry.legitimacy
        end
    end
    if best then
        return best
    end
    for _, faction in ipairs(CONFIG.DEFECT_TO) do
        local player = Find_Player(faction)
        if player then
            for _, planet in pairs(FindPlanet.Get_All_Planets()) do
                if planet.Get_Owner() == player then
                    return faction
                end
            end
        end
    end
    return nil
end

function Court.take_unit(c, player)
    local obj = c.lore and unit_on_map(c.lore)
    if obj and player and obj.Get_Owner() == Court.player() then
        pcall(obj.Change_Owner, player)
    end
end

function Court.traitors_in_office(s)
    local out = {}
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if c.traitor and c.status == "serving" and (c.title ~= "courtier" or Court.office_of(s, c) or c.fleet_rank) then
            table.insert(out, c)
        end
    end
    return out
end

function Court.hero_leaves(s, obj)
    local ok_type, type_name = pcall(function()
        return string.upper(obj.Get_Type().Get_Name())
    end)
    local regime_now = Court.regime_name()
    for _, unit in ipairs(ok_type and CONFIG.REGIME_DEATHS[regime_now] or {}) do
        if unit == type_name then
            local i = LORE_BY_UNIT[type_name]
            local id = i and s.lore_used[i]
            local c = id and id > 0 and s.chars[id]
            if c and c.status == "serving" then
                Court.remove(s, c, "dead", "is put to death by the new regime")
            elseif i then
                Court.news(s, LORE.CHARACTERS[i].name .. " is put to death by the new regime.")
            end
            return false
        end
    end
    local rival = Court.top_rival()
    local player = rival and Find_Player(rival)
    if not player or not TestValid(obj) then
        return false
    end
    local i = LORE_BY_UNIT[string.upper(obj.Get_Type().Get_Name())]
    local id = i and s.lore_used[i]
    local c = id and id > 0 and s.chars[id]
    local ok = pcall(obj.Change_Owner, player)
    if not ok then
        return false
    end
    if c and c.status == "serving" then
        Court.remove(s, c, "defected")
        c.faction = rival
        Court.news(s, Court.full_name(c) .. " will not serve the new regime and goes over to " .. Court.faction_label(rival) .. ".")
    end
    return true
end

function Court.update_vacancies(s)
    local V = CONFIG.VACANT
    local total, all, worlds, titles, seen = 0, 0, {}, 0, {}
    local function title(key, worth, scale, empty)
        local weight = (1 + worth / V.VALUE_STEP) * scale
        all = all + weight
        if empty then
            seen[key] = true
            titles = titles + 1
            s.vacant_since[key] = s.vacant_since[key] or s.week
            total = total + weight * M.min(s.week - s.vacant_since[key], V.WEEKS_CAP) / V.WEEKS_STEP
        end
    end
    for key, sector in pairs(s.sectors) do
        if not sector.crown and table.getn(sector.worlds) > 0 then
            local worth = 0
            local empty = not Court.char(s, sector.holder)
            for _, name in ipairs(sector.worlds) do
                worth = worth + (GEO[name] and GEO[name].value or 0)
                if empty then
                    table.insert(worlds, name)
                end
            end
            title("S_" .. key, worth, 1, empty)
        end
    end
    for _, name in ipairs(Court.unsectored(s, s.held)) do
        local empty = not s.governor[name]
        if empty then
            table.insert(worlds, name)
        end
        title("W_" .. name, GEO[name] and GEO[name].value or 0, 0.5, empty)
    end
    total = total / M.max(1, all)
    for key, _ in pairs(s.vacant_since) do
        if not seen[key] then
            s.vacant_since[key] = nil
        end
    end
    table.sort(worlds)
    s.vacancy, s.unmanaged, s.vacant_titles = total, worlds, titles
end

function Court.defect_target(s, c)
    local worlds = Court.worlds_of(s, c)
    if table.getn(worlds) == 0 then
        local rival = Court.top_rival()
        return rival, rival and Find_Player(rival)
    end
    local wanted = {}
    for _, f in ipairs(CONFIG.DEFECT_TO) do
        local player = Find_Player(f)
        if player then
            wanted[f] = player
        end
    end
    local seen, frontier = {}, {}
    for _, name in ipairs(worlds) do
        seen[name] = true
        table.insert(frontier, name)
    end
    for _ = 1, 3 do
        local next_ = {}
        for _, name in ipairs(frontier) do
            for _, other in ipairs(Court.lanes(name)) do
                if not seen[other] then
                    seen[other] = true
                    local owner = Court.owner_of(s, other)
                    if owner and wanted[owner] then
                        return owner, wanted[owner]
                    end
                    table.insert(next_, other)
                end
            end
        end
        frontier = next_
    end
    return nil
end

function Court.defect(s, c)
    if c.heir or c.leads or c.minder then
        return false
    end
    if Court.defer(s, "defect", c) then
        return true
    end
    local faction, player = Court.defect_target(s, c)
    if not faction then
        return false
    end
    local full = Court.full_name(c)
    local planets, worlds = {}, {}
    for _, planet in ipairs(planet_objects(Court.worlds_of(s, c))) do
        if planet.Get_Owner() == Court.player() then
            table.insert(planets, planet)
            table.insert(worlds, Court.name_of(planet))
        end
    end
    Court.take_unit(c, player)
    if table.getn(planets) > 0 then
        Court.transfer_worlds(s, planets, player)
    end
    Court.remove(s, c, "defected")
    c.faction = faction
    s.stability = M.max(0, s.stability - 3)
    if table.getn(worlds) > 0 then
        Court.relief(s)
    end
    local label = Court.faction_label(faction)
    Court.news(s, full .. " defects to " .. label .. " with " .. table.getn(worlds)
        .. ((table.getn(worlds) == 1) and " world." or " worlds."))
    if Court.player().Is_Human() then
        Court.alert("Defection: " .. full .. " goes over to " .. label .. ".", "threat")
    elseif player.Is_Human() and StoryUtil then
        StoryUtil.ShowScreenText(full .. " of the Empire defects to you with " .. table.getn(worlds)
            .. ((table.getn(worlds) == 1) and " world." or " worlds."), 20, nil, {r = 120, g = 220, b = 140})
    end
    return true
end

function Court.week_fraction(s)
    local now = GetCurrentTime and GetCurrentTime() or 0
    return M.clamp(1 - ((s.next_week or now) - now) / CONFIG.WEEK_SECONDS, 0, 1)
end

function Court.week(s)
    s.week = s.week + 1
    s.regime_weeks = (s.regime_weeks or 0) + 1
    Court.refresh_map(s)
    Court.count_sectors(s)
    pcall(Court.measure_worlds, s)
    Court.update_hold(s)
    if (s.relief_weeks or 0) > 0 then
        s.relief_weeks = s.relief_weeks - 1
    end
    Court.recruit(s)
    Court.update_vacancies(s)
    local _, gov = Court.legitimacy()
    local entry = gov and gov.imperial_table and gov.imperial_table[CONFIG.FACTION]
    local integrated = entry and entry.factions_integrated
    if type(integrated) == "number" then
        if s.integrated and integrated > s.integrated then
            Court.add_legitimacy(CONFIG.FACTION, CONFIG.LEGITIMACY.ABSORBED)
            s.stability = M.min(100, s.stability + 3)
            Court.news(s, "A rival Imperial power is absorbed into the Empire: legitimacy rises.")
        end
        s.integrated = integrated
    end
    local Politics = require("eawx-plugins/imperial-court/CourtPolitics")
    local Intel = require("eawx-plugins/imperial-court/CourtIntel")
    Politics.check_regime(s)
    Court.fleet_office_rank(s)
    apply_offices(s)
    weekly_people(s)
    apply_stability(s)
    local ok_r, Revenue = pcall(require, "eawx-plugins/imperial-court/CourtRevenue")
    if ok_r and Revenue then
        local ok_w, err_w = pcall(function()
            Revenue.find_palaces(s)
            Revenue.week(s)
            Revenue.week_risings(s)
        end)
        if not ok_w then
            log("revenue error: " .. tostring(err_w))
        end
    end
    Politics.week(s)
    Court.week_ties(s)
    local ok_t, err_t = pcall(require("eawx-plugins/imperial-court/CourtTerritory").week, s)
    if not ok_t then
        log("territory error: " .. tostring(err_t))
    end
    pcall(require("eawx-plugins/imperial-court/CourtLife").week, s)
    Intel.week(s)
    require("eawx-plugins/imperial-court/CourtFleet").week(s)
    pcall(Court.titles, s)
    for faction, value in pairs(s.attitude) do
        if value < 0 then
            s.attitude[faction] = M.min(0, value + CONFIG.ATTITUDE_FADE)
        elseif value > 0 then
            s.attitude[faction] = M.max(0, value - CONFIG.ATTITUDE_FADE)
        end
    end
end

function Court.on_owner_changed(s, planet_name, new_owner, old_owner)
    if s.owners then
        s.owners[planet_name] = new_owner
    end
    if new_owner == CONFIG.FACTION and s.ready then
        pcall(Court.place_world, s, planet_name)
    elseif old_owner == CONFIG.FACTION and s.held then
        s.held[planet_name] = nil
    end
    if new_owner == CONFIG.FACTION then
        s.calm = s.calm or {}
        s.calm[planet_name] = (s.week or 0) + CONFIG.UNGOVERNED.AFTER_CONQUEST
        s.gained = s.gained + 1
        s.taken = s.taken or {}
        s.taken[old_owner] = s.taken[old_owner] or {}
        table.insert(s.taken[old_owner], planet_name)
    elseif old_owner == CONFIG.FACTION then
        s.lost = s.lost + 1
        Court.world_lost(s, planet_name, new_owner)
    end
    if new_owner == CONFIG.FACTION and Court.regime(s).legitimacy then
        Court.add_legitimacy(CONFIG.FACTION, Court.regime(s).legitimacy)
    end
end

function Court.world_lost(s, name, new_owner)
    local C = CONFIG.CONQUERED
    s.stability = M.max(0, s.stability - C.STABILITY)
    local gov = Court.char(s, s.governor[name])
    if gov and gov.status == "serving" then
        Court.vacate(s, gov)
        Court.opinion(gov, "lost their world", C.TITLELESS, C.WEEKS)
    end
    local key = s.world[name]
    local sector = key and s.sectors[key]
    s.world[name] = nil
    if sector then
        Court.index_worlds(s)
        local moff = Court.char(s, sector.holder)
        if moff and moff.status == "serving" then
            if table.getn(sector.worlds) == 0 then
                Court.vacate(s, moff)
                Court.opinion(moff, "lost their whole sector", C.TITLELESS, C.WEEKS)
            elseif sector.seat == name then
                Court.opinion(moff, "lost their seat", C.HOLDER, C.WEEKS)
            else
                Court.opinion(moff, "lost a world of their sector", C.MOFF, C.WEEKS / 2)
            end
        end
    end
    local rose = s.rebel_pending[name] or new_owner == "INDEPENDENT_FORCES"
    s.rebel_pending[name] = nil
    if rose then
        local R = CONFIG.REBELLION
        s.stability = M.max(0, s.stability - R.STABILITY)
        Court.add_legitimacy(CONFIG.FACTION, R.LEGITIMACY)
        Court.news(s, Court.planet_label(name) .. " is lost to a rising: stability and legitimacy fall.")
    end
end

function Court.on_hero_killed(s, hero_type)
    if require("eawx-plugins/imperial-court/CourtFleet").on_killed(s, hero_type) then
        return
    end
    local i = LORE_BY_UNIT[string.upper(hero_type or "")]
    local id = i and s.lore_used[i]
    local c = id and id > 0 and s.chars[id]
    if c and c.status == "serving" then
        local obj = unit_on_map(i)
        if not obj then
            Court.remove(s, c, "dead", "fell in battle")
        end
    end
end

return Court
