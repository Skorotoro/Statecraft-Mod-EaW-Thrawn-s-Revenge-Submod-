local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")

local Parties = {}
local P = R.PARTIES
local COLOR = {r = 170, g = 200, b = 255}
local WARN = {r = 255, g = 190, b = 90}
local KIND_NAMES = {ELECTED = "Elected", COUNCIL = "Council", OLIGARCHY = "Oligarchy", MONARCHY = "Monarchy",
                    MILITARY = "Military", THEOCRACY = "Theocracy", TRIBAL = "Tribal", CORPORATE = "Corporate"}

local function Republic()
    return require("eawx-plugins/new-republic/Republic")
end

local function state(d)
    local r = d.republic
    if not r then
        return nil
    end
    r.parties = r.parties or {}
    return r.parties
end

local function sentence_case(text)
    return (string.gsub(text, "^%l", string.upper))
end

local function mod(h, n)
    return h - M.floor(h / n) * n
end

local function pick(list, h)
    return list[mod(h, table.getn(list)) + 1]
end

local function kind_of(gov)
    for _, rule in ipairs(P.KINDS) do
        if string.find(gov, rule[1], 1, true) then
            return rule[2]
        end
    end
    return "ELECTED"
end

local function term_of(kind, gov)
    if kind == "ELECTED" then
        for _, rule in ipairs(P.ELECTED_TERMS) do
            if string.find(gov, rule[1], 1, true) then
                return rule[2]
            end
        end
    end
    return P.TERMS[kind]
end

function Parties.bloc_name(bloc)
    if bloc == "INDEPENDENCE" then
        return "Independence"
    end
    for _, def in ipairs(R.BLOCS) do
        if def.key == bloc then
            return def.name
        end
    end
    return bloc
end

function Parties.bloc_short(bloc)
    return P.SHORT[bloc] or Parties.bloc_name(bloc)
end

function Parties.dot(bloc)
    if bloc == "INDEPENDENCE" then
        return "dp_dot_independence.tga"
    end
    for _, def in ipairs(R.BLOCS) do
        if def.key == bloc then
            return "dp_dot_" .. def.dot .. ".tga"
        end
    end
    return "dp_dot_military.tga"
end

function Parties.the(name)
    if string.find(name, "^Clan ") or string.find(name, "^House ") or string.find(name, "^Sovereign ")
            or string.find(name, " First$") or string.find(name, " Remembered$") or string.find(name, "^Free ") then
        return name
    end
    return "the " .. name
end

local function leader_name(d, key, species, salt, taken)
    local pool = R.NAMES[species] or R.NAMES.Human
    local person = nil
    for try = 0, 12 do
        local h = U.hash(key .. "%" .. salt .. "/" .. try)
        if pool.single then
            person = pick(pool.single, h)
        else
            person = pick(pool.first, h) .. " " .. pick(pool.last, U.hash(key .. "&" .. salt .. "/" .. try))
        end
        if not taken[person] then
            break
        end
    end
    taken[person] = true
    return person
end

local function party_name(key, world, species, kind, bloc, salt)
    local list = P.NAMES[bloc] or P.NAMES.CORE
    local h = U.hash(key .. bloc .. salt)
    local name = pick(list, h)
    local people = (species == "Human" or species == "Alien") and "Charter" or species
    name = string.gsub(name, "%%W", world)
    name = string.gsub(name, "%%S", people)
    name = string.gsub(name, "%%N", pick(P.NOUNS[kind], U.hash(key .. "n" .. salt)))
    return name
end

local function leanings(d, key)
    local Blocs = Republic().part("blocs")
    local out, seen = {}, {}
    local current = Blocs and d.senate and Blocs.key_of(Blocs.of(d, key) or "")
    if current then
        table.insert(out, current)
        seen[current] = true
    end
    local scores = Blocs and Blocs.fits and Blocs.fits(d, key) or {}
    local sorted = {}
    for bloc, score in pairs(scores) do
        table.insert(sorted, {bloc, score})
    end
    table.sort(sorted, function(a, b) return a[2] > b[2] end)
    for _, s in ipairs(sorted) do
        if not seen[s[1]] and s[1] ~= "AGGRIEVED" and s[1] ~= "LOYALIST" and (s[1] ~= "BOTHAN" or current == "BOTHAN") then
            table.insert(out, s[1])
            seen[s[1]] = true
        end
    end
    return out
end

local function make(d, key, planet)
    local Members = Republic().part("members")
    local species = Members and Members.species(key) or "Human"
    local gov = Parties.government(key)
    local kind = kind_of(gov)
    local world = planet and d:planet_name(planet) or key
    local h = U.hash(key .. "parties")
    local range = P.COUNT[kind]
    local count = range[1] + mod(h, range[2] - range[1] + 1)
    local senator = Republic().senator(d, key)
    local lore_senator = false
    for _, entry in ipairs(R.LORE_SENATORS[key] or {}) do
        lore_senator = lore_senator or entry[1] == senator
    end
    local list = {}
    local taken = {[senator or ""] = true}
    local lore = P.LORE[key]
    if lore then
        for _, entry in ipairs(lore) do
            table.insert(list, {name = entry[1], bloc = entry[2]})
        end
    else
        local blocs = leanings(d, key)
        local independence = mod(h, 100) < ((blocs[1] == "AUTONOMY") and 80 or P.INDEPENDENCE_PCT)
        local wanted = independence and (count - 1) or count
        for k = 1, M.min(wanted, table.getn(blocs)) do
            table.insert(list, {name = party_name(key, world, species, kind, blocs[k], k), bloc = blocs[k]})
        end
        if independence or table.getn(list) == 0 then
            table.insert(list, {name = party_name(key, world, species, kind, "INDEPENDENCE", 0), bloc = "INDEPENDENCE"})
        end
    end
    local n = table.getn(list)
    local first = P.RULING_CLOUT + mod(h, 9)
    local rest, weights = 100 - first, 0
    for k = 2, n do
        weights = weights + (n - k + 2)
    end
    for k, party in ipairs(list) do
        party.clout = (k == 1) and first or (rest * (n - k + 2) / M.max(1, weights))
        party.leader = (k == 1 and senator) or leader_name(d, key, species, k, taken)
    end
    if n == 1 then
        list[1].clout = 100
    end
    list[1].entrenched = lore_senator or nil
    local term = term_of(kind, gov)
    local w = {kind = kind, gov = gov, term = term, ruling = 1, list = list,
               since = GetCurrentTime() - U.weeks(mod(h, P.FATIGUE_WEEKS + 8))}
    if term then
        w.next = GetCurrentTime() + U.weeks(1 + mod(U.hash(key .. "term"), term))
    end
    return w
end

local function titles(w, key)
    local list = P.GOV_TITLES[w.gov] or P.TITLES[w.kind] or {"Delegate"}
    for k, party in ipairs(w.list) do
        party.title = pick(list, U.hash(key .. "t" .. k))
    end
end

function Parties.government(key)
    local n = table.getn(R.GOVERNMENT_TYPES)
    return R.GOVERNMENTS[key] or (Republic().is_territory(key) and "Military Administration")
        or R.GOVERNMENT_TYPES[mod(U.hash(key), n) + 1]
end

function Parties.of(d, key)
    local s = state(d)
    if not s or (d.republic.seated and not d.republic.seated[key]) then
        return nil
    end
    if not s[key] then
        local planet = FindPlanet(key)
        if not planet then
            return nil
        end
        s[key] = make(d, key, planet)
    end
    titles(s[key], key)
    return s[key]
end

function Parties.ruling_bloc(d, key)
    local s = state(d)
    local w = s and s[key]
    local party = w and w.list[w.ruling]
    return party and party.bloc
end

local function shift(w, idx, amount)
    local others = 0
    for k, party in ipairs(w.list) do
        if k ~= idx then
            others = others + M.max(0, party.clout - P.FLOOR)
        end
    end
    amount = M.min(amount, others)
    if amount <= 0 then
        return 0
    end
    for k, party in ipairs(w.list) do
        if k ~= idx then
            local loss = amount * M.max(0, party.clout - P.FLOOR) / others
            if party.entrenched then
                loss = loss * P.ENTRENCHED_LOSS
            end
            party.clout = party.clout - loss
        end
    end
    local total = 0
    for k, party in ipairs(w.list) do
        if k ~= idx then
            total = total + party.clout
        end
    end
    w.list[idx].clout = 100 - total
    return amount
end

local function at_war_with_empire(d)
    for _, faction in pairs(ModContentLoader.get("GameConstants").ALL_FACTIONS_NOT_NEUTRAL or {}) do
        local kind = U.category(faction)
        if kind == "IMPERIAL" or kind == "WARLORD" then
            local other = Find_Player(faction)
            if other and other ~= d.human and d.human.Is_Enemy(other) and U.count(U.worlds_of(other)) > 0 then
                return true
            end
        end
    end
    return false
end

local function favours(d, key, seat, ctx)
    local f = {}
    local function add(bloc, n)
        f[bloc] = (f[bloc] or 0) + n
    end
    if seat.threat then
        add("FRONTIER", 2)
    end
    if ctx.wars > 0 then
        add("PEACE", 1)
    else
        add("CORE", 1)
        add("TRADE", 1)
    end
    if ctx.empire_war then
        add("LIBERATION", 1)
    end
    local S = Republic().part("sectors")
    local level = S and S.level(d, U.sector_of(key) or "") or R.TAX_NORMAL
    if level > R.TAX_NORMAL then
        add("AUTONOMY", 1)
        add("INDEPENDENCE", 1)
    elseif level < R.TAX_NORMAL then
        add("TRADE", 1)
    end
    local members = d.republic.members
    if members and (members.drift[key] or 0) > 0 then
        add("AUTONOMY", 1)
        add("INDEPENDENCE", 1)
    end
    local a = P.ACTION
    if ctx.taken then
        add("FRONTIER", a)
    end
    if ctx.freed then
        add("LIBERATION", a)
    end
    if ctx.invaded then
        add("PEACE", a)
        add("AUTONOMY", a)
    end
    if ctx.lost then
        add("FRONTIER", a)
    end
    if ctx.admitted then
        add("CORE", a)
    end
    local Focus = Republic().part("focus")
    local Laws = Republic().part("laws")
    if not (Laws and Laws.no_focus(d, key)) then
        for bloc, v in pairs((Focus and Focus.favours(d)) or {}) do
            add(bloc, v)
        end
    end
    for bloc, v in pairs((Laws and Laws.favours(d, key)) or {}) do
        add(bloc, v)
    end
    if seat.opinion <= P.RESENTFUL then
        add("INDEPENDENCE", 2)
        add("AGGRIEVED", 2)
    elseif seat.opinion >= P.CONTENT then
        add("CORE", 1)
    end
    return f
end

local function incumbency(w, sooner)
    local weeks = M.floor((GetCurrentTime() - (w.since or GetCurrentTime())) / U.weeks(1))
    local fatigue = M.max(1, P.FATIGUE_WEEKS - (sooner or 0))
    if weeks < fatigue then
        return P.INCUMBENT
    end
    return -M.min(P.FATIGUE_MAX, P.FATIGUE_RATE * (weeks - fatigue + 1))
end

local function drift(d, key, w, seat, ctx)
    local f = favours(d, key, seat, ctx)
    local Laws = Republic().part("laws")
    local speed = Laws and Laws.clout_speed(d, key) or 1
    local sooner = Laws and Laws.fatigue_weeks(d, key, w.term) or 0
    for k, party in ipairs(w.list) do
        local gain = ((f[party.bloc] or 0) * P.FAVOUR + ((k == w.ruling) and incumbency(w, sooner) or 0)) * speed
        if party.clout > P.DOMINANT then
            gain = gain - (party.clout - P.DOMINANT) * P.DOMINANT_RATE
        end
        if gain > 0 then
            shift(w, k, gain)
        elseif gain < 0 then
            Parties.adjust(d, key, k, gain)
        end
    end
    return f
end

local function news(d)
    d.republic.party_news = d.republic.party_news or {}
    return d.republic.party_news
end

function Parties.news(d)
    return (d.republic and d.republic.party_news) or {}
end

function Parties.acknowledge(d, id)
    local kept = {}
    for _, n in ipairs(news(d)) do
        if n.id ~= id then
            table.insert(kept, n)
        end
    end
    d.republic.party_news = kept
end

local function event(d, key, w, f)
    local leading = 1
    for k, party in ipairs(w.list) do
        if party.clout > w.list[leading].clout then
            leading = k
        end
    end
    local idx, lines, amount = nil, nil, GameRandom.Free_Random(P.EVENT_CLOUT[1], P.EVENT_CLOUT[2])
    if U.chance(P.EVENT_FALL) and table.getn(w.list) > 1 then
        idx, lines, amount = leading, P.EVENTS.fall, -amount
    else
        local favoured = {}
        for k, party in ipairs(w.list) do
            if k ~= leading and (f[party.bloc] or 0) > 0 and P.EVENTS[party.bloc] then
                table.insert(favoured, k)
            end
        end
        idx = U.pick(favoured)
        if idx then
            lines = P.EVENTS[w.list[idx].bloc]
        else
            local others = {}
            for k in ipairs(w.list) do
                if k ~= leading then
                    table.insert(others, k)
                end
            end
            idx, lines = U.pick(others) or leading, P.EVENTS.rise
        end
    end
    local party = w.list[idx]
    local done = Parties.adjust(d, key, idx, amount)
    if M.abs(done) < 1 then
        return
    end
    local planet = FindPlanet(key)
    local text = U.pick(lines)
    text = string.gsub(text, "{party}", Parties.the(party.name))
    text = string.gsub(text, "{world}", planet and d:planet_name(planet) or key)
    text = string.gsub(text, "{leader}", ((idx == w.ruling) and "Senator " or (party.title .. " ")) .. party.leader)
    text = string.gsub(text, "^%l", string.upper)
    local list = news(d)
    d.republic.news_id = (d.republic.news_id or 0) + 1
    table.insert(list, 1, {id = d.republic.news_id, world = key, text = text,
        text2 = party.name .. ": clout " .. ((done > 0) and "+" or "") .. M.round(done) .. ", now " .. M.round(party.clout)
            .. "%. " .. ((idx == w.ruling) and "It holds the seat." or "")})
    while table.getn(list) > P.NEWS_KEPT do
        table.remove(list)
    end
end

local function leader_of(w)
    if w.rigged and w.list[w.rigged] then
        return w.rigged, false
    end
    local best, second = nil, nil
    for k, party in ipairs(w.list) do
        if not best or party.clout > w.list[best].clout then
            best, second = k, best
        elseif not second or party.clout > w.list[second].clout then
            second = k
        end
    end
    local margin = second and (w.list[best].clout - w.list[second].clout) or 100
    if best ~= w.ruling and w.list[w.ruling] then
        local gap = w.list[best].clout - w.list[w.ruling].clout
        if gap <= P.INCUMBENT_EDGE or (w.list[w.ruling].entrenched and gap <= P.ENTRENCHED_EDGE) then
            return w.ruling, true
        end
    end
    return best, margin <= P.TOO_CLOSE
end

local function seat_to(d, key, w, idx, how)
    local planet = FindPlanet(key)
    local world = planet and d:planet_name(planet) or key
    local party = w.list[idx]
    local changed = idx ~= w.ruling
    local before = w.list[w.ruling]
    w.ruling = idx
    if changed and Republic().senate and Republic().senate.party_changed then
        pcall(Republic().senate.party_changed, d, key, before and before.name, party.name)
    end
    if changed then
        w.since = GetCurrentTime()
    end
    if not changed then
        d.show("Senate: " .. world .. " " .. ((how == "elect") and "re-elects" or "keeps") .. " Senator " .. party.leader
            .. " of " .. Parties.the(party.name) .. ".", nil, COLOR, 10)
        return
    end
    local Members = Republic().part("members")
    d.republic.senators[key] = {name = party.leader, species = Members and Members.species(key) or "Human"}
    local friendly = Parties.agenda_score(d, party.bloc)
    local Laws = Republic().part("laws")
    local swing = P.SENATOR_SWING * ((Laws and Laws.term_limits(d, key)) and 2 or 1)
    if Republic().senate and friendly ~= 0 then
        Republic().senate.sway(d, key, (friendly > 0) and swing or -swing,
            (friendly > 0) and "a senator friendly to the government's agenda" or "a senator opposed to the government's agenda")
    end
    if friendly > 0 then
        d.republic.capital = M.min(R.CAPITAL_MAX, (d.republic.capital or 0) + P.FRIENDLY_CAPITAL)
    end
    local Blocs = Republic().part("blocs")
    local b = d.senate and d.senate.blocs
    if b and party.bloc ~= "INDEPENDENCE" and not b.gone[party.bloc] then
        b.of[key] = party.bloc
    end
    d.show("Senate: " .. world .. ((how == "elect") and " elects " or "'s ruler names ") .. party.title .. " "
        .. party.leader .. " of " .. Parties.the(party.name) .. " its senator (" .. Parties.bloc_name(party.bloc) .. ").", nil,
        (party.bloc == "INDEPENDENCE") and WARN or COLOR, 15)
    if party.bloc == "INDEPENDENCE" and Republic().senate then
        Republic().senate.sway(d, key, -P.INDEPENDENCE_OPINION, "a separatist senator took the seat")
    end
end

local function appoint(w)
    local total = 0
    for _, party in ipairs(w.list) do
        total = total + party.clout + P.APPOINT_FAVOUR
    end
    local roll = GameRandom.Free_Random(1, M.max(1, M.floor(total)))
    for k, party in ipairs(w.list) do
        roll = roll - (party.clout + P.APPOINT_FAVOUR)
        if roll <= 0 then
            return k
        end
    end
    return w.ruling
end

function Parties.view(d, key)
    local w = Parties.of(d, key)
    if not w then
        return nil
    end
    local out = {kind = KIND_NAMES[w.kind], gov = w.gov, term = w.term, parties = {}}
    local winner, close = leader_of(w)
    if w.rigged and w.list[w.rigged] then
        out.arranged = w.list[w.rigged].name
    end
    if w.term then
        local left = M.max(0, M.ceil((w.next - GetCurrentTime()) / U.weeks(1)))
        out.election = (left <= 0) and "Election this week" or ("Election in " .. left .. ((left == 1) and " week" or " weeks"))
        out.expected = (out.arranged and ("Arranged: " .. out.arranged)) or (close and "Too close to call")
            or ("Expected: " .. w.list[winner].name)
        out.election_tip = "A " .. string.lower(KIND_NAMES[w.kind]) .. " government: the senator is chosen every "
            .. w.term .. " weeks, by the party with the most clout."
    else
        out.election = "No fixed term"
        out.expected = "Ruler's choice: " .. w.list[w.ruling].name
        out.election_tip = "A " .. string.lower(KIND_NAMES[w.kind]) .. " government: the ruler appoints the senator "
            .. "and may name another at any time, by favour more than clout."
    end
    local order = {}
    for k in ipairs(w.list) do
        table.insert(order, k)
    end
    table.sort(order, function(a, b) return w.list[a].clout > w.list[b].clout end)
    for _, k in ipairs(order) do
        local party = w.list[k]
        table.insert(out.parties, {idx = k, name = party.name, bloc = party.bloc, short = Parties.bloc_short(party.bloc),
            bloc_name = Parties.bloc_name(party.bloc), dot = Parties.dot(party.bloc),
            leader = ((k == w.ruling) and "Senator" or party.title) .. " " .. party.leader,
            clout = M.round(party.clout), ruling = k == w.ruling, entrenched = party.entrenched})
    end
    return out
end

local function cohesion_drift(d, key, w, ctx)
    local c = ctx.cohesion
    if not c then
        return
    end
    w.low_gain = w.low_gain or {}
    local function is(bloc, list)
        for _, b in ipairs(list) do
            if b == bloc then
                return true
            end
        end
        return false
    end
    for k, party in ipairs(w.list) do
        if c < P.COHESION_MID and is(party.bloc, P.COHESION_LOW_BLOCS) then
            local gained = shift(w, k, (P.COHESION_MID - c) / P.COHESION_SCALE * P.FAVOUR)
            w.low_gain[party.name] = (w.low_gain[party.name] or 0) + gained
        elseif c >= P.COHESION_MID and (w.low_gain[party.name] or 0) > 0 then
            local drain = M.max(P.COHESION_DRAIN_MIN, (c - P.COHESION_MID) / P.COHESION_SCALE) * P.FAVOUR
            local lost = -Parties.adjust(d, key, k, -M.min(drain, w.low_gain[party.name]))
            w.low_gain[party.name] = w.low_gain[party.name] - M.max(lost, M.min(drain, w.low_gain[party.name]))
            if w.low_gain[party.name] <= 0.01 then
                w.low_gain[party.name] = nil
            end
        end
        if c >= P.COHESION_HIGH and is(party.bloc, P.COHESION_HIGH_BLOCS) then
            shift(w, k, (c - P.COHESION_HIGH) / P.COHESION_HIGH_SCALE * P.FAVOUR)
        end
    end
end

local function remove_party(w, idx)
    local party = table.remove(w.list, idx)
    local total = 0
    for _, p in ipairs(w.list) do
        total = total + p.clout
    end
    for _, p in ipairs(w.list) do
        p.clout = p.clout + party.clout * ((total > 0) and (p.clout / total) or (1 / table.getn(w.list)))
    end
    if w.ruling > idx then
        w.ruling = w.ruling - 1
    end
    if w.rigged then
        w.rigged = (w.rigged ~= idx) and ((w.rigged > idx) and (w.rigged - 1) or w.rigged) or nil
    end
    if w.low_gain then
        w.low_gain[party.name] = nil
    end
end

local function post(d, key, text, text2)
    local list = news(d)
    d.republic.news_id = (d.republic.news_id or 0) + 1
    table.insert(list, 1, {id = d.republic.news_id, world = key, text = text, text2 = text2})
    while table.getn(list) > P.NEWS_KEPT do
        table.remove(list)
    end
end

local function loyalists(d, key, w, seat, ctx)
    local c = ctx.cohesion or 50
    local idx = nil
    for k, party in ipairs(w.list) do
        if party.bloc == "LOYALIST" then
            idx = k
        end
    end
    if not idx then
        if c >= P.COHESION_HIGH and seat.opinion >= P.LOYALIST_OPINION and table.getn(w.list) < P.LOYALIST_MAX_PARTIES
                and U.chance(P.LOYALIST_RISE) then
            local Members = Republic().part("members")
            local species = Members and Members.species(key) or "Human"
            local planet = FindPlanet(key)
            local world = planet and d:planet_name(planet) or key
            local taken = {}
            for _, p in ipairs(w.list) do
                taken[p.leader or ""] = true
            end
            local party = {name = party_name(key, world, species, w.kind, "LOYALIST", GetCurrentTime()), bloc = "LOYALIST",
                           clout = 0, leader = leader_name(d, key, species, "loyal" .. GetCurrentTime(), taken)}
            table.insert(w.list, party)
            titles(w, key)
            shift(w, table.getn(w.list), P.LOYALIST_START)
            post(d, key, "On " .. world .. ", " .. Parties.the(party.name) .. " is founded, led by " .. party.leader
                .. ": its people stand by the Republic.", party.name .. ": clout " .. M.round(party.clout) .. "%.")
        end
        return
    end
    local change = 0
    if c >= P.COHESION_HIGH then
        change = (c - P.COHESION_HIGH) / P.LOYALIST_HIGH_SCALE * P.FAVOUR
    else
        change = -M.max(P.COHESION_DRAIN_MIN, (P.COHESION_HIGH - c) / P.LOYALIST_FALL_SCALE) * P.FAVOUR
    end
    if seat.opinion < 0 then
        change = change - (-seat.opinion / P.LOYALIST_OPINION_SCALE) * P.FAVOUR
    end
    if change > 0 then
        shift(w, idx, change)
    elseif change < 0 then
        Parties.adjust(d, key, idx, change)
        if idx ~= w.ruling and w.list[idx].clout <= P.FLOOR + P.LOYALIST_GONE and table.getn(w.list) > 1 then
            local planet = FindPlanet(key)
            local gone = w.list[idx]
            remove_party(w, idx)
            post(d, key, "On " .. (planet and d:planet_name(planet) or key) .. ", " .. Parties.the(gone.name)
                .. " has lost its last supporters and disbands.", "Its clout passes to the other parties.")
        end
    end
end

function Parties.ruling(d, key)
    local w = Parties.of(d, key)
    return w and w.list[w.ruling]
end

function Parties.law_bloc(d, key, bloc)
    if bloc ~= "LOYALIST" then
        return bloc
    end
    local w = Parties.of(d, key)
    for _, b in ipairs(P.MODERATION) do
        for _, party in ipairs((w and w.list) or {}) do
            if party.bloc == b then
                return b
            end
        end
    end
    return "CORE"
end

function Parties.can_lobby(d, key)
    local w = Parties.of(d, key)
    if not w then
        return "No parties to lobby."
    end
    if w.lobbied and GetCurrentTime() - w.lobbied < U.weeks(P.LOBBY_WEEKS) then
        local left = M.ceil((U.weeks(P.LOBBY_WEEKS) - (GetCurrentTime() - w.lobbied)) / U.weeks(1))
        return "This world was lobbied lately: again in " .. left .. ((left == 1) and " week." or " weeks.")
    end
    if (d.republic.capital or 0) < P.LOBBY_CAPITAL then
        return "Not enough political capital (" .. P.LOBBY_CAPITAL .. " needed)."
    end
    return nil
end

function Parties.lobby(d, key, idx)
    local why = Parties.can_lobby(d, key)
    if why then
        return false, why
    end
    local w = Parties.of(d, key)
    local party = w.list[idx]
    if not party then
        return false, "No such party."
    end
    local gained = shift(w, idx, P.LOBBY_CLOUT)
    if gained <= 0 then
        return false, sentence_case(Parties.the(party.name)) .. " can gain no more here."
    end
    d.republic.capital = d.republic.capital - P.LOBBY_CAPITAL
    w.lobbied = GetCurrentTime()
    return true, sentence_case(Parties.the(party.name)) .. " gains clout (+" .. M.round(gained) .. ")."
end

function Parties.adjust(d, key, idx, delta)
    local w = Parties.of(d, key)
    if not w or not w.list[idx] then
        return 0
    end
    if delta >= 0 then
        return shift(w, idx, delta)
    end
    local party = w.list[idx]
    local loss = M.min(-delta, M.max(0, party.clout - P.FLOOR))
    local others = 0
    for k, p in ipairs(w.list) do
        if k ~= idx then
            others = others + p.clout
        end
    end
    if loss <= 0 or others <= 0 then
        return 0
    end
    for k, p in ipairs(w.list) do
        if k ~= idx then
            p.clout = p.clout + loss * p.clout / others
        end
    end
    party.clout = party.clout - loss
    return -loss
end

function Parties.rig(d, key, idx)
    local w = Parties.of(d, key)
    local Laws = Republic().part("laws")
    if Laws and Laws.no_rig(d, key) then
        return false
    end
    if w and w.term and w.list[idx] then
        w.rigged = idx
        return true
    end
    return false
end

function Parties.reappoint(d, key, idx, favour)
    local w = Parties.of(d, key)
    if not w or w.term or not w.list[idx] then
        return false
    end
    w.list[idx].clout = w.list[idx].clout + favour
    local pick_idx = appoint(w)
    w.list[idx].clout = w.list[idx].clout - favour
    if pick_idx ~= w.ruling then
        seat_to(d, key, w, pick_idx, "appoint")
        return true
    end
    return false
end

function Parties.party(d, key, idx)
    local w = Parties.of(d, key)
    return w and w.list[idx]
end

function Parties.elected(d, key)
    local w = Parties.of(d, key)
    return w ~= nil and w.term ~= nil
end

function Parties.agenda_score(d, bloc)
    local Gov = Republic().part("gov")
    local agenda = Gov and Gov.agenda(d)
    local table_ = agenda and P.AGENDA[agenda]
    return (table_ and table_[bloc]) or 0
end

function Parties.opinion(d, key)
    local party = Parties.ruling_party(d, key)
    if not party then
        return 0, {}
    end
    local parts = {}
    local agenda = Parties.agenda_score(d, party.bloc)
    if party.bloc == "INDEPENDENCE" then
        table.insert(parts, {"a separatist senator", P.INDEPENDENT_OPINION})
    elseif agenda ~= 0 then
        table.insert(parts, {(agenda > 0) and "its party likes the Chancellor's agenda"
            or "its party dislikes the Chancellor's agenda", agenda})
    end
    local jedi = d.republic and d.republic.jedi
    if jedi and jedi.roster and next(jedi.roster) and (jedi.trust or 50) > 50 then
        local v = M.round(P.JEDI_OPINION * ((jedi.trust or 50) - 50) / 50)
        if v ~= 0 and P.JEDI_LIKE[party.bloc] then
            table.insert(parts, {"its party trusts the Jedi", v})
        elseif v ~= 0 and P.JEDI_WARY[party.bloc] then
            table.insert(parts, {"its party resents the Jedi's influence", -v})
        end
    end
    local value = 0
    for _, p in ipairs(parts) do
        value = value + p[2]
    end
    return value, parts
end

function Parties.ruling_party(d, key)
    local s = state(d)
    local w = s and s[key]
    return w and w.list[w.ruling]
end

function Parties.week(d, seated)
    local s = state(d)
    if not s then
        return
    end
    for key in pairs(s) do
        if not seated[key] then
            s[key] = nil
        end
    end
    local Senate = Republic().senate
    local seats = Senate and Senate.seats(d) or {}
    local ctx = {wars = U.count(d.republic.declared), empire_war = at_war_with_empire(d),
                 cohesion = d.senate and d.senate.stability}
    local recent = d.republic.politics or {}
    for _, what in ipairs({"taken", "freed", "invaded", "lost"}) do
        ctx[what] = recent[what] and GetCurrentTime() - recent[what] < U.weeks(P.RECENT_WEEKS) or nil
    end
    local seat_count = U.count(seated)
    if d.republic.last_seats and seat_count > d.republic.last_seats then
        recent.admitted = GetCurrentTime()
        d.republic.politics = recent
    end
    d.republic.last_seats = seat_count
    ctx.admitted = recent.admitted and GetCurrentTime() - recent.admitted < U.weeks(P.RECENT_WEEKS) or nil
    for key, planet in pairs(seated) do
        local w = Parties.of(d, key)
        local seat = seats[key]
        if w and seat then
            local f = drift(d, key, w, seat, ctx)
            cohesion_drift(d, key, w, ctx)
            loyalists(d, key, w, seat, ctx)
            local Laws = Republic().part("laws")
            if Laws then
                Laws.party_week(d, key, w)
            end
            if U.chance(P.EVENT_CHANCE) then
                event(d, key, w, f)
            end
            if w.term and GetCurrentTime() >= w.next then
                w.next = w.next + U.weeks(w.term)
                local winner = leader_of(w)
                if Laws and Laws.term_limits(d, key) and winner == w.ruling and table.getn(w.list) > 1 then
                    local best = nil
                    for k, p in ipairs(w.list) do
                        if k ~= w.ruling and (not best or p.clout > w.list[best].clout) then
                            best = k
                        end
                    end
                    winner = best or winner
                end
                w.rigged = nil
                seat_to(d, key, w, winner, "elect")
                local extra = Laws and Laws.incumbent_clout(d, key) or 0
                if extra > 0 then
                    Parties.adjust(d, key, w.ruling, extra)
                end
            elseif not w.term and not (Laws and Laws.no_replace(d, key)) then
                local chance = P.REPLACE_CHANCE + ((w.list[w.ruling].clout < P.REPLACE_LOW_CLOUT) and P.REPLACE_LOW or 0)
                if U.chance(chance) then
                    local pick_idx = appoint(w)
                    if pick_idx ~= w.ruling then
                        seat_to(d, key, w, pick_idx, "appoint")
                    end
                end
            end
        end
    end
end

return Parties
