local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local Worlds = require("eawx-plugins/diplomacy/DiplomacyWorlds")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")

local P = {}
local COLOR = {r = 170, g = 200, b = 255}
local WARN = {r = 255, g = 190, b = 90}

local function state(d)
    local r = d.republic
    if not r then
        return nil
    end
    r.prot = r.prot or {calls = {}}
    return r.prot
end

function P.eligible(d, faction)
    if not d.human or d.human.Get_Faction_Name() ~= "REBEL" then
        return false
    end
    faction = string.upper(faction or "")
    if R.PROTECTORATE.NEVER[faction] or (d.is_vassal_faction and d:is_vassal_faction(faction)) then
        return false
    end
    local kind = U.category(faction)
    return kind == "FREE" or kind == "INDEPENDENT"
end

function P.is(d, faction)
    return d.relations and d.relations[faction] == "PROTECTORATE"
end

function P.protect_world(d, planet, world, sail)
    local slot, why = Worlds.open(d, planet, sail)
    if not slot then
        d.show("Diplomacy: " .. world .. " cannot take the Republic's protection now. " .. (why or ""), nil, WARN)
        return false
    end
    d:set_relation(slot, "PROTECTORATE", nil, true)
    local key = string.upper(planet.Get_Type().Get_Name())
    d.vassal_worlds[key] = {since = GetCurrentTime(), stage = "protectorate", slot = slot}
    d.show("Diplomacy: " .. world .. " accepts the Republic's protection. It keeps its own government; attack it, "
        .. "and the Republic answers.", nil, COLOR, 20)
    local ok_m, Missions = pcall(require, "eawx-plugins/diplomacy/DiplomacyMissions")
    if ok_m and Missions.answer_appeal(d, key) then
        local Council = require("eawx-plugins/new-republic/RepublicCouncil")
        if Council.active(d) then
            require("eawx-plugins/new-republic/Republic").change_mandate(d, R.COUNCIL.APPEAL_MANDATE)
            d.show("Council: " .. world .. "'s petition is answered. The galaxy sees the Alliance keep its word. "
                .. "Mandate " .. require("eawx-plugins/new-republic/Republic").mandate(d) .. ".", nil, COLOR, 20)
        end
    end
    return true
end

local function slot_world(d, faction)
    for world, w in pairs(d.vassal_worlds or {}) do
        if w.slot == faction then
            return world
        end
    end
    return nil
end

function P.list(d)
    local out = {}
    for faction, relation in pairs(d.relations or {}) do
        if relation == "PROTECTORATE" and not slot_world(d, faction) then
            table.insert(out, {kind = "faction", key = faction, name = d.display_name(faction)})
        end
    end
    for world, w in pairs(d.vassal_worlds or {}) do
        local planet = FindPlanet(world)
        if planet and (w.stage == "protectorate" or w.stage == "associate") then
            table.insert(out, {kind = "world", key = world, name = d:planet_name(planet), stage = w.stage, state = w})
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function worlds_of(d, key, kind)
    if kind == "world" then
        local planet = FindPlanet(key)
        return planet and {{key = key, planet = planet}} or {}
    end
    return U.worlds_of(Find_Player(key))
end

function P.withdraw(d, faction)
    if not P.is(d, faction) then
        return false, "They are not under the Republic's protection."
    end
    local s = state(d)
    local world = slot_world(d, faction)
    if s then
        s.calls[faction] = nil
        if world then
            s.calls[world] = nil
        end
    end
    if world then
        d.vassal_worlds[world] = nil
    end
    d:set_relation(faction, "CEASEFIRE", nil, true)
    d.memory.ended_alliance = d.memory.ended_alliance or {}
    d.memory.ended_alliance[faction] = GetCurrentTime()
    if d.reputation_drop then
        d:reputation_drop(d.human.Get_Faction_Name(), 1, "abandoned its protectorate, " .. d.display_name(faction))
    end
    local Republic = require("eawx-plugins/new-republic/Republic")
    Republic.change_mandate(d, -R.PROTECTORATE.END_MANDATE)
    for _, w in pairs(d.vassal_worlds or {}) do
        if w.stage then
            w.content = M.max(0, (w.content or 50) - 10)
        end
    end
    if DIPLOMACY_OPINION_ADD then
        pcall(DIPLOMACY_OPINION_ADD, faction, d.human.Get_Faction_Name(), -30, 20, "the Republic abandoned them")
    end
    d.show("Republic: the Republic withdraws its protection from " .. d.display_name(faction) .. ". The galaxy notices "
        .. "(mandate " .. Republic.mandate(d) .. ").", nil, WARN, 20)
    return true, "Protection withdrawn."
end

local function open_call(d, prot, kind, name, attacker, world)
    local s = state(d)
    if not s or not attacker or attacker == d.human.Get_Faction_Name() then
        return
    end
    local call = s.calls[prot]
    if call then
        if world then
            call.worlds[world] = true
        end
        return
    end
    if U.count(s.calls) >= R.PROTECTORATE.CALL_MAX then
        return
    end
    local far = 0
    for _, w in ipairs(worlds_of(d, prot, kind)) do
        local n = U.jumps(d, d.human, w.planet)
        if n and n > far then
            far = n
        end
    end
    local weeks = R.PROTECTORATE.CALL_WEEKS + M.floor(far / R.PROTECTORATE.CALL_JUMPS_PER_WEEK)
    call = {kind = kind, name = name, attacker = attacker, worlds = {}, opened = GetCurrentTime(),
            deadline = GetCurrentTime() + U.weeks(weeks)}
    if world then
        call.worlds[world] = true
    end
    s.calls[prot] = call
    if d.senate and d.senate.approved then
        d.senate.approved[attacker] = true
    end
    d.show("Call to Action: " .. d.display_name(attacker) .. " attacks " .. name .. ", under the Republic's "
        .. "protection. The Senate approves war on them. Defend it within " .. weeks .. " weeks.", nil, WARN, 30)
end

function P.on_owner_changed(d, key, new_owner, old_owner)
    if not d.republic or d.human.Get_Faction_Name() ~= "REBEL" then
        return
    end
    local new = string.upper(new_owner or "")
    local old = string.upper(old_owner or "")
    local w = d.vassal_worlds and d.vassal_worlds[key]
    if w and (w.stage == "protectorate" or w.stage == "associate") and new ~= d.human.Get_Faction_Name() then
        local planet = FindPlanet(key)
        open_call(d, key, "world", planet and d:planet_name(planet) or key, new, key)
        local s = state(d)
        if s and s.calls[key] then
            s.calls[key].lost_world = {stage = w.stage, content = w.content, integration = w.integration}
        end
        if w.slot and d.relations[w.slot] == "PROTECTORATE" then
            d.relations[w.slot] = nil
        end
    elseif P.is(d, old) and new ~= d.human.Get_Faction_Name() then
        open_call(d, old, "faction", d.display_name(old), new, key)
    end
end

function P.reclaimed(d, key)
    local s = state(d)
    if not s then
        return nil
    end
    for prot, call in pairs(s.calls) do
        if call.worlds[key] then
            return prot, call
        end
    end
    return nil
end

function P.hand_back(d, key)
    local prot, call = P.reclaimed(d, key)
    local planet = FindPlanet(key)
    if not (prot and planet) then
        return false
    end
    call.worlds[key] = nil
    if call.kind == "world" then
        local lost = call.lost_world or {}
        local independent = Find_Player("INDEPENDENT_FORCES")
        if lost.stage == "associate" or not independent then
            local vassals = d:vassal_player()
            if vassals then
                d.own_transfers[key] = true
                d:transfer_world(planet, vassals, false)
            end
            d.vassal_worlds[key] = {since = GetCurrentTime(), stage = "associate", content = lost.content,
                                    integration = lost.integration, associate_since = GetCurrentTime()}
            d:mark_vassal_world(planet)
        else
            d.own_transfers[key] = true
            d:transfer_world(planet, independent, false)
            if P.protect_world(d, planet, d:planet_name(planet)) then
                d.vassal_worlds[key].content = lost.content
                d.vassal_worlds[key].integration = lost.integration
            end
        end
    else
        local owner = Find_Player(prot)
        if owner then
            d.own_transfers[key] = true
            d:transfer_world(planet, owner, false)
        end
    end
    d.show("Republic: " .. d:planet_name(planet) .. " is free again and returned to " .. call.name .. ".", nil, COLOR, 20)
    return true
end

local function hostile_in_orbit(d, prot, kind)
    local owner
    if kind == "world" then
        local planet = FindPlanet(prot)
        owner = planet and planet.Get_Owner()
    else
        owner = Find_Player(prot)
    end
    if not owner then
        return nil
    end
    local C = ModContentLoader.get("GameConstants")
    for _, w in ipairs(worlds_of(d, prot, kind)) do
        for _, faction in pairs(C.ALL_FACTIONS_NOT_NEUTRAL or {}) do
            local other = Find_Player(faction)
            if other and other ~= d.human and other ~= owner and owner.Is_Enemy(other)
                    and U.strength_at(other, w.planet) > 0 then
                return faction, w.key
            end
        end
    end
    return nil
end

local function call_done(d, prot, call)
    for key, _ in pairs(call.worlds) do
        local planet = FindPlanet(key)
        if planet and planet.Get_Owner().Get_Faction_Name() == call.attacker then
            return false
        end
    end
    return hostile_in_orbit(d, prot, call.kind) == nil
end

local function leave(d, prot, call)
    if call.kind == "faction" then
        if P.is(d, prot) then
            d:set_relation(prot, "CEASEFIRE", nil, true)
        end
        if DIPLOMACY_OPINION_ADD then
            pcall(DIPLOMACY_OPINION_ADD, prot, d.human.Get_Faction_Name(), R.PROTECTORATE.CALL_BREAK_OPINION, 30,
                "the Republic left them to their fate")
        end
    else
        local w = d.vassal_worlds and d.vassal_worlds[prot]
        local planet = FindPlanet(prot)
        local independent = Find_Player("INDEPENDENT_FORCES")
        if w and w.slot then
            d.vassal_worlds[prot] = nil
            if d.relations[w.slot] == "PROTECTORATE" then
                d:set_relation(w.slot, "CEASEFIRE", nil, true)
            end
        elseif w and planet and independent then
            d.vassal_worlds[prot] = nil
            d.own_transfers[prot] = true
            d:transfer_world(planet, independent, false)
        end
    end
    if d.reputation_drop then
        d:reputation_drop(d.human.Get_Faction_Name(), 1, "let its protectorate " .. call.name .. " fall")
    end
    d.show("Republic: " .. call.name .. " gives up on the Republic's protection and leaves. The Republic's word "
        .. "counts for less.", nil, WARN, 25)
end

local function check_hostile(d)
    local Republic = require("eawx-plugins/new-republic/Republic")
    local Sym = Republic.part("sym")
    if not Sym then
        return
    end
    for world, w in pairs(d.vassal_worlds or {}) do
        local v = w.stage == "protectorate" and Sym.value(d, world)
        if v and v < R.SYMPATHY_HOSTILE then
            w.hostile = (w.hostile or 0) + 1
            if w.hostile >= R.PROTECTORATE.HOSTILE_WEEKS then
                local planet = FindPlanet(world)
                local name = planet and d:planet_name(planet) or world
                d.vassal_worlds[world] = nil
                if w.slot and d.relations[w.slot] == "PROTECTORATE" then
                    d:set_relation(w.slot, "CEASEFIRE", nil, true)
                end
                d.show("Diplomacy: " .. name .. " renounces the " .. d.display_name("REBEL") .. "'s protection. Its "
                    .. "people never wanted it.", nil, WARN, 25)
                pcall(M.show_document, {
                    "The government of " .. name .. " has ended the treaty of protection.",
                    "",
                    "For weeks its people have marched against the " .. d.display_name("REBEL") .. "'s flag on their "
                        .. "world. No government can stand against its own streets for long.",
                    "",
                    "A protectorate needs a Sympathetic people. Win them over first: Delegates, broadcasts and aid.",
                }, "Protection Renounced", name .. " is free of the treaty.")
            end
        elseif w.hostile then
            w.hostile = nil
        end
    end
end

function P.week(d)
    local s = state(d)
    if not s then
        return
    end
    pcall(check_hostile, d)
    local Republic = require("eawx-plugins/new-republic/Republic")
    for world, w in pairs(d.vassal_worlds or {}) do
        if w.slot and d.relations[w.slot] ~= "PROTECTORATE" and not s.calls[world] then
            d.vassal_worlds[world] = nil
        end
    end
    for _, p in ipairs(P.list(d)) do
        if not s.calls[p.key] then
            local attacker, at = hostile_in_orbit(d, p.key, p.kind)
            if attacker then
                open_call(d, p.key, p.kind, p.name, attacker, nil)
            end
        end
    end
    for prot, call in pairs(s.calls) do
        local now = GetCurrentTime()
        if call_done(d, prot, call) then
            s.calls[prot] = nil
            Republic.change_mandate(d, R.PROTECTORATE.CALL_DONE_MANDATE)
            if call.kind == "faction" and DIPLOMACY_OPINION_ADD then
                pcall(DIPLOMACY_OPINION_ADD, prot, d.human.Get_Faction_Name(), R.PROTECTORATE.CALL_DONE_OPINION, 20,
                    "the Republic came to their defence")
            elseif call.kind == "world" and d.vassal_worlds[prot] then
                local w = d.vassal_worlds[prot]
                w.content = M.min(100, (w.content or 50) + R.PROTECTORATE.CALL_DONE_OPINION)
            end
            d.show("Republic: the call to defend " .. call.name .. " is answered. Mandate " .. Republic.mandate(d)
                .. ".", nil, COLOR, 20)
        elseif now > call.deadline then
            local span = call.deadline - call.opened
            if now >= call.deadline + span then
                s.calls[prot] = nil
                leave(d, prot, call)
            else
                if d.senate then
                    d.senate.stability = M.max(0, d.senate.stability - R.PROTECTORATE.CALL_LATE_COHESION)
                end
                if Republic.senate then
                    for name, _ in pairs(Republic.senate.seats(d)) do
                        Republic.senate.sway(d, name, -R.PROTECTORATE.CALL_LATE_OPINION,
                            "the Republic left " .. call.name .. " undefended")
                    end
                end
            end
        end
    end
end

function P.calls(d)
    local s = state(d)
    local out = {}
    for prot, call in pairs((s and s.calls) or {}) do
        table.insert(out, {key = prot, name = call.name, attacker = call.attacker,
                           left = M.floor((call.deadline - GetCurrentTime()) / U.weeks(1)), lost = U.count(call.worlds)})
    end
    table.sort(out, function(a, b) return a.left < b.left end)
    return out
end

function P.call_of(d, prot)
    local s = state(d)
    return s and s.calls[prot]
end

function P.petitions(d)
    local out = {}
    for world, w in pairs(d.vassal_worlds or {}) do
        if w.stage == "protectorate" and w.petitions and FindPlanet(world) then
            table.insert(out, world)
        end
    end
    table.sort(out)
    return out
end

function P.make_associate(d, world)
    local w = d.vassal_worlds and d.vassal_worlds[world]
    local planet = FindPlanet(world)
    if planet and not w and P.eligible(d, planet.Get_Owner().Get_Faction_Name()) then
        d.vassal_worlds = d.vassal_worlds or {}
        if P.protect_world(d, planet, d:planet_name(planet)) then
            w = d.vassal_worlds[world]
        end
    end
    if not (w and planet) then
        return
    end
    w.stage, w.petitions, w.associate_since = "associate", nil, GetCurrentTime()
    local slot = w.slot
    w.slot = nil
    local vassals = d:vassal_player()
    if vassals then
        d:transfer_world(planet, vassals, false)
    end
    if slot then
        d.relations[slot] = nil
    end
    d:mark_vassal_world(planet)
    local name = d:planet_name(planet)
    d.show("Republic: " .. name .. " becomes an associate world of the Republic. It pays its share and sends "
        .. "ships; one day it may ask for a seat.", nil, COLOR, 25)
    local ok, Grants = pcall(require, "eawx-plugins/diplomacy/DiplomacyGrants")
    if ok and Grants then
        local home = d:nearest_friendly_planet(d.human, planet) or planet
        d:grant_units(Grants.for_world, world, home, d.human, name)
    end
end

function P.check_associates(d)
    for world, w in pairs(d.vassal_worlds or {}) do
        if w.stage == "associate" and not w.requests and (w.content or 0) >= R.ASSOCIATE_CONTENT
                and GetCurrentTime() - (w.associate_since or GetCurrentTime()) >= U.weeks(R.ASSOCIATE_WEEKS) then
            w.requests = true
            local planet = FindPlanet(world)
            d.show("Republic: the associate world " .. (planet and d:planet_name(planet) or world) .. " files its own "
                .. "motion to join the Republic as a member. Put it to the chamber.", nil, COLOR, 25)
        end
    end
end

return P
