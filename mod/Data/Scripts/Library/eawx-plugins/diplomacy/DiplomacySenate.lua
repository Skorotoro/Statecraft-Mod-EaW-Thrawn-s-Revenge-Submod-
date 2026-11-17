local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
require("eawx-plugins/diplomacy/DiplomacyAI")

local Senate = {}
local POPULATIONS = require("eawx-plugins/diplomacy/DiplomacyPopulations")
local FACTIONS = require("eawx-plugins/diplomacy/DiplomacyFactions")
local Goals = require("eawx-plugins/diplomacy/DiplomacyGoals")
local Missions = require("eawx-plugins/diplomacy/DiplomacyMissions")
local Republic = require("eawx-plugins/new-republic/Republic")
Republic.senate = Senate

local OFFICE = "REBEL_OFFICE"
local COLOR = {r = 170, g = 200, b = 255}
local WARN = {r = 255, g = 190, b = 90}

local function rules()
    return CONFIG.SENATE
end

local function the_name(d, faction)
    local name = d.display_name(faction)
    if string.find(name, "'s ") or string.find(name, "^The ") then
        return name
    end
    return "the " .. name
end
Senate.the_name = the_name

local function weeks(n)
    return n * CONFIG.WEEK_SECONDS
end

local function council_part()
    return Republic.part("council")
end

function Senate.profile(d)
    local storyline = GlobalValue.Get("STORYLINE") or "DEFAULT"
    local profile = rules().PROFILES[storyline] or rules().PROFILES.DEFAULT
    local council = false
    if d and d.republic then
        council = Republic.council(d)
    elseif d and d.senate then
        council = d.senate.council
    end
    return {
        storyline = storyline,
        council = council,
        name = council and "Provisional Council" or "Senate",
        offmap = council and 0 or profile.offmap,
        offmap_stance = profile.stance,
        military = 0,
        override_cost = council and rules().COUNCIL_OVERRIDE_COST or rules().OVERRIDE_COST,
    }
end

local enemy_within_now
local THREAT_SECONDS = 10
local threat_cache = {}

local function enemy_within(d, ctx, planet, jumps)
    local key = planet.Get_Type().Get_Name() .. "|" .. jumps
    local cached = threat_cache[key]
    if cached and GetCurrentTime() - cached.time < THREAT_SECONDS and GetCurrentTime() >= cached.time then
        return cached.faction or nil
    end
    local found = enemy_within_now(d, ctx, planet, jumps)
    threat_cache[key] = {faction = found or false, time = GetCurrentTime()}
    return found
end

enemy_within_now = function(d, ctx, planet, jumps)
    local C = ModContentLoader.get("GameConstants")
    for _, faction in pairs(C.ALL_FACTIONS_NOT_NEUTRAL) do
        local other = Find_Player(faction)
        if other and other ~= d.human and d.human.Is_Enemy(other) then
            local n = DiplomacyAI.jumps_to(ctx, other, planet)
            if n and n <= jumps then
                return faction
            end
        end
    end
    return nil
end

local function opinion_entry(d, name)
    local o = d.senate.opinion[name]
    if not o then
        o = {value = 0, events = {}}
        d.senate.opinion[name] = o
    end
    return o
end

local PARTY_SHARE = 0.4

local function ruling_name(d, name)
    local Parties = Republic.part and Republic.part("parties")
    local ok, party = false, nil
    if Parties and Parties.ruling_party then
        ok, party = pcall(Parties.ruling_party, d, name)
    end
    return ok and party and party.name or nil
end

function Senate.sway(d, name, amount, reason)
    local Laws = Republic.part("laws")
    if amount < 0 and Laws and Laws.no_fall(d, name) then
        return
    end
    local o = opinion_entry(d, name)
    local party = ruling_name(d, name)
    if party then
        o.party = o.party or {}
        o.party[party] = M.max(-100, M.min(100, (o.party[party] or 0) + amount * PARTY_SHARE))
    end
    o.value = M.max(-100, M.min(100, o.value + amount))
    table.insert(o.events, 1, (amount > 0 and "+" or "") .. amount .. " " .. reason)
    if table.getn(o.events) > 4 then
        table.remove(o.events)
    end
end

function Senate.party_changed(d, name, old_party, new_party)
    local o = d.senate and d.senate.opinion[name]
    if not o or not o.party then
        return
    end
    local swing = (o.party[new_party] or 0) - (o.party[old_party] or 0)
    local Laws = Republic.part("laws")
    if Laws and Laws.term_limits(d, name) then
        swing = swing * 2
    end
    if M.round(swing) ~= 0 then
        o.value = M.max(-100, M.min(100, o.value + swing))
        table.insert(o.events, 1, ((swing > 0) and "+" or "") .. M.round(swing) .. " a new party in power")
        if table.getn(o.events) > 4 then
            table.remove(o.events)
        end
    end
end

local function bloc_of(d, ctx, planet, name)
    local Blocs = not Republic.council(d) and Republic.part("blocs")
    if Blocs then
        local threat = enemy_within(d, ctx, planet, 1)
        return Blocs.of(d, name, threat), threat
    end
    local joined = d.integrated and d.integrated[name]
    if d.occupation and d.occupation[name] then
        return "Resentful"
    elseif joined and GetCurrentTime() - joined < weeks(rules().NEW_MEMBER_WEEKS) then
        return "New member"
    end
    local threat = enemy_within(d, ctx, planet, 1)
    if threat then
        return "Frontier", threat
    end
    return "Heartland"
end

local function seated_planets(d)
    local planets = {}
    for _, office in pairs(Find_All_Objects_Of_Type(OFFICE) or {}) do
        if TestValid(office) and office.Get_Owner() == d.human then
            local planet = office.Get_Planet_Location()
            local name = planet and string.upper(planet.Get_Type().Get_Name())
            if name and POPULATIONS[name] then
                planets[name] = planet
            end
        end
    end
    return planets
end

local function unrepresented_penalty(weeks_waited, name)
    local cap = rules().UNREPRESENTED_CAP[POPULATIONS[name] or 1]
    return M.min(weeks_waited * rules().UNREPRESENTED_PER_WEEK, cap)
end

function Senate.seats(d)
    if Republic.council(d) then
        return {}
    end
    local seats = {}
    local ctx = DiplomacyAI.context(d.display_name)
    local penalties = {}
    for name, entry in pairs(d.senate.unrepresented) do
        penalties[entry.bloc] = (penalties[entry.bloc] or 0) + unrepresented_penalty(entry.weeks, name)
    end
    for name, planet in pairs(seated_planets(d)) do
        local bloc, threat = bloc_of(d, ctx, planet, name)
        local base = opinion_entry(d, name).value
        local penalty = M.min(penalties[bloc] or 0, rules().UNREPRESENTED_BLOC_CAP)
        local bonus = Republic.opinion_bonus(d, name, bloc)
        local Laws = Republic.part("laws")
        local cap = Laws and Laws.opinion_cap(d, name)
        seats[name] = {planet = planet, name = name, bloc = bloc, threat = threat, base_opinion = base,
                       unrepresented = penalty, founding = Republic.is_founding(d, name), founding_bonus = bonus,
                       weight = Republic.vote_weight(d, name),
                       opinion = M.max(-100, M.min(cap or 100, base + bonus - penalty))}
    end
    return seats
end

local function update_unrepresented(d)
    if Republic.council(d) then
        d.senate.unrepresented = {}
        return
    end
    local ctx = DiplomacyAI.context(d.display_name)
    local seated = seated_planets(d)
    local still = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local name = string.upper(planet.Get_Type().Get_Name())
        if planet.Get_Owner() == d.human and POPULATIONS[name] and not seated[name] then
            local entry = d.senate.unrepresented[name] or {weeks = 0}
            entry.weeks = entry.weeks + 1
            entry.bloc = bloc_of(d, ctx, planet, name)
            still[name] = entry
            if entry.weeks == rules().UNREPRESENTED_WARN_WEEKS then
                d.show("Senate: the people of " .. d:planet_name(planet) .. " have no voice in the "
                    .. Senate.profile(d).name .. ". The " .. entry.bloc .. " bloc takes up their grievance. "
                    .. "Build a Senator's Office there.", nil, WARN)
            end
        end
    end
    d.senate.unrepresented = still
end
Senate.update_unrepresented = update_unrepresented

local function seat_vote(seat, motion, stability)
    if seat.opinion >= rules().LOYAL_OPINION then
        return 1
    elseif seat.opinion <= rules().HOSTILE_OPINION then
        return -1
    end
    if motion.kind == "ACT" then
        if motion.act == "FRONTIER_FUND" then
            return ((seat.bloc == "Frontier" or seat.bloc == "New member") and 1) or (seat.bloc == "Resentful" and -1)
                or ((seat.opinion >= 15) and 1 or -1)
        end
        return (seat.bloc == "Resentful") and -1 or ((seat.opinion >= -10) and 1 or 0)
    end
    if motion.kind == "ADMIT_ASSOCIATE" then
        return (seat.bloc == "Resentful") and -1 or 1
    elseif motion.kind == "ADMIT_MEMBER" then
        if seat.bloc == "Resentful" then
            return -1
        elseif seat.bloc == "Heartland" then
            return (seat.opinion >= rules().MEMBER_HEARTLAND_OPINION) and 1 or -1
        end
        return 1
    end
    local vote
    if seat.bloc == "Resentful" then
        vote = -1
    elseif seat.bloc == "New member" then
        vote = 1
    elseif seat.bloc == "Frontier" then
        if motion.kind == "WAR" then
            vote = (seat.threat == motion.target) and 1 or 0
        else
            vote = (seat.threat == motion.target) and -1 or 1
        end
    else
        vote = (motion.kind == "TREATY") and 1 or -1
    end
    if vote == 0 and stability < rules().UNREST_STABILITY then
        vote = -1
    end
    return vote
end

local function offmap_vote(profile, motion)
    if motion.kind == "ACT" then
        return (motion.act == "UNITY") and 1 or 0
    end
    if motion.kind == "ADMIT_ASSOCIATE" then
        return (profile.offmap_stance == "distant") and 0 or 1
    elseif motion.kind == "ADMIT_MEMBER" then
        return 0
    end
    if profile.offmap_stance == "distant" then
        return (motion.kind == "TREATY") and 1 or -1
    end
    return (motion.kind == "TREATY") and 1 or 0
end

local function undecided_vote(d, seat, motion)
    local Blocs = Republic.part("blocs")
    if Republic.must_abstain(d, seat) or (Blocs and Blocs.vote(d, seat, motion) ~= 0) then
        return 0
    end
    local S = Republic.CONFIG.SENATE
    local tilt = seat.opinion * S.UNDECIDED_OPINION
    local roll = GameRandom.Free_Random(1, 100)
    if roll <= S.UNDECIDED_BASE + tilt then
        return 1
    elseif roll > 100 - (S.UNDECIDED_BASE - tilt) then
        return -1
    end
    return 0
end

function Senate.tally(d, motion, final)
    if Republic.council(d) then
        return council_part().tally(d, motion)
    end
    local profile = Senate.profile(d)
    local result = {yes = 0, no = 0, abstain = 0, blocs = {}, worlds = {}, weighed_yes = 0, weighed_no = 0}
    local function count(bloc, vote, n, weight)
        if vote > 0 then
            result.weighed_yes = result.weighed_yes + n * (weight or 1)
        elseif vote < 0 then
            result.weighed_no = result.weighed_no + n * (weight or 1)
        end
        result.blocs[bloc] = result.blocs[bloc] or {yes = 0, no = 0, abstain = 0}
        local key = (vote > 0 and "yes") or (vote < 0 and "no") or "abstain"
        result.blocs[bloc][key] = result.blocs[bloc][key] + n
        result[key] = result[key] + n
    end
    for name, seat in pairs(Senate.seats(d)) do
        local vote = Senate.vote_of(d, seat, motion)
        if final and vote == 0 then
            vote = undecided_vote(d, seat, motion)
        end
        result.worlds[name] = vote
        count(seat.bloc, vote, 1, seat.weight)
    end
    if profile.offmap > 0 then
        count("Worlds beyond this region", offmap_vote(profile, motion), profile.offmap)
    end
    if profile.military > 0 then
        count("Military", (motion.kind == "WAR") and 1 or 0, profile.military)
    end
    result.passed = result.weighed_yes > result.weighed_no
    result.passed = Republic.pass_rule(d, motion, result)
    return result
end

function Senate.describe(result)
    local text = "For " .. result.yes .. ", against " .. result.no
    if result.abstain > 0 then
        text = text .. ", abstaining " .. result.abstain
    end
    local main, most = nil, 0
    for bloc, votes in pairs(result.blocs) do
        if votes.no > most then
            main, most = bloc, votes.no
        end
    end
    if main and not result.passed then
        text = text .. ". Main opposition: " .. main .. " (" .. most .. ")"
    end
    return text
end

local MOTION_TEXTS = {
    HEADER = "TEXT_DIPLOMACY_SENATE_MOTION_HEADER", BODY = "TEXT_DIPLOMACY_SENATE_MOTION_BODY",
    BODY_TIP = "TEXT_DIPLOMACY_SENATE_MOTION_BODY_TIP", PROCEED = "TEXT_DIPLOMACY_SENATE_MOTION_PROCEED",
    PROCEED_TIP = "TEXT_DIPLOMACY_SENATE_MOTION_PROCEED_TIP", OVERRIDE = "TEXT_DIPLOMACY_SENATE_MOTION_OVERRIDE",
    OVERRIDE_TIP = "TEXT_DIPLOMACY_SENATE_MOTION_OVERRIDE_TIP", WITHDRAW = "TEXT_DIPLOMACY_SENATE_MOTION_WITHDRAW",
    WITHDRAW_TIP = "TEXT_DIPLOMACY_SENATE_MOTION_WITHDRAW_TIP",
}

local MOTION_OBJECTS = {
    HEADER = "Senate_Motion_Header", BODY = "Senate_Motion_Body", BODY_TIP = "Senate_Motion_Body",
    PROCEED = "Senate_Motion_Proceed", PROCEED_TIP = "Senate_Motion_Proceed", OVERRIDE = "Senate_Motion_Override",
    OVERRIDE_TIP = "Senate_Motion_Override", WITHDRAW = "Senate_Motion_Withdraw", WITHDRAW_TIP = "Senate_Motion_Withdraw",
}

local function set_text(key, value)
    if string.find(key, "_TIP$") then
        if Engine_Set_Text then
            Engine_Set_Text(MOTION_TEXTS[key], value)
        end
    elseif Engine_Set_Object_Text then
        Engine_Set_Object_Text(MOTION_OBJECTS[key], MOTION_TEXTS[key], value)
    end
end

function Senate.motion_for(d, relation, target, world)
    if world and relation == "VASSAL" then
        return {kind = "ADMIT_ASSOCIATE", target = target, text = "take " .. world .. " under protection as an associate world"}
    elseif world and relation == "ADMIT" then
        return {kind = "ADMIT_MEMBER", target = target, text = "admit " .. world .. " as a member world with a seat"}
    elseif world and relation == "WAR" then
        return {kind = "WAR", target = target, text = "declare war on " .. world}
    elseif relation == "WAR" then
        return {kind = "WAR", target = target, text = "declare war on " .. d.display_name(target)}
    elseif relation == "CEASEFIRE" or relation == "ALLIANCE" or relation == "VASSAL" then
        local nouns = {CEASEFIRE = "agree a ceasefire with ", ALLIANCE = "ally with ", VASSAL = "take as a vassal "}
        return {kind = "TREATY", target = target, relation = relation, text = nouns[relation] .. d.display_name(target)}
    end
    return nil
end

function Senate.propose(d, motion, enact)
    if Senate.use_mandate(d, motion) then
        d.show(Senate.profile(d).name .. ": acting on the chamber's mandate to " .. motion.text .. ".", nil, COLOR)
        enact()
        return true
    end
    return Senate.open_debate(d, motion, enact)
end

function Senate.propose_popup(d, motion, enact)
    local profile = Senate.profile(d)
    local result = Senate.tally(d, motion)
    d.senate.pending = {motion = motion, result = result, enact = enact}
    local verdict = result.passed and "passed" or "failed"
    local summary = "the motion to " .. motion.text .. " " .. verdict .. ". " .. Senate.describe(result) .. "."
    d.show(profile.name .. ": " .. summary, nil, COLOR, 25)

    local tip = ""
    for bloc, votes in pairs(result.blocs) do
        tip = tip .. bloc .. ": " .. votes.yes .. " for, " .. votes.no .. " against, " .. votes.abstain .. " abstain. "
    end
    set_text("HEADER", "Motion before the " .. profile.name)
    set_text("BODY", "To " .. motion.text .. ": " .. verdict .. " (" .. result.yes .. " for, " .. result.no .. " against)")
    set_text("BODY_TIP", tip)
    set_text("PROCEED", "Put the motion into effect")
    set_text("PROCEED_TIP", "The " .. profile.name .. " approved it.")
    set_text("OVERRIDE", "Override the " .. profile.name .. " (cohesion -" .. profile.override_cost .. ")")
    set_text("OVERRIDE_TIP", "Act anyway. Cohesion falls and the senators who opposed it think less of the government.")
    set_text("WITHDRAW", "Withdraw the motion")
    set_text("WITHDRAW_TIP", "Nothing happens.")

    local options
    if result.passed then
        options = {"PROCEED", "WITHDRAW"}
    else
        options = {"OVERRIDE", "WITHDRAW"}
    end
    local ok, err = pcall(GenericPopup, "SENATE_MOTION", options, "SENATE_MOTION_OPTION")
    if not ok then
        d.report_error("SENATE POPUP", err)
        Senate.on_choice(d, result.passed and "PROCEED" or "WITHDRAW")
    end
end

function Senate.on_choice(d, option)
    local pending = d.senate.pending
    d.senate.pending = nil
    if not pending or not option then
        return
    end
    local profile = Senate.profile(d)
    option = string.upper(option)
    if string.find(option, "PROCEED") then
        if pending.motion.kind == "WAR" then
            d.senate.approved[pending.motion.target] = true
        end
        pending.enact()
    elseif string.find(option, "OVERRIDE") then
        Senate.override(d, pending)
        if pending.motion.kind == "WAR" then
            d.senate.approved[pending.motion.target] = true
        end
        pending.enact()
    else
        d.show(profile.name .. ": the motion to " .. pending.motion.text .. " was withdrawn.", nil, COLOR)
    end
end

function Senate.override(d, pending)
    local profile = Senate.profile(d)
    local cost = profile.override_cost
    if pending.motion and pending.motion.kind == "WAR" then
        cost = cost * 2
    end
    if not profile.council then
        d.senate.stability = M.max(0, d.senate.stability - cost)
    end
    d.senate.overrides = d.senate.overrides + 1
    if pending.motion and pending.motion.kind == "WAR" then
        Republic.change_mandate(d, -Republic.CONFIG.OVERRIDE_WAR_MANDATE)
    end
    for name, vote in pairs(pending.result.worlds or {}) do
        if vote < 0 then
            Senate.sway(d, name, -rules().OVERRIDE_OPINION, "the government overrode its vote")
        end
    end
    d.show(profile.name .. ": the government acted against the vote to " .. pending.motion.text
        .. (profile.council and ". The Councillors who opposed it won't forget." or (". Cohesion " .. d.senate.stability
        .. "%.")), nil, WARN)
end

function Senate.on_conquest(d, planet_name, old_owner, key)
    local profile = Senate.profile(d)
    if key then
        Republic.on_conquest(d, key, planet_name, old_owner)
    end
    if profile.council or not old_owner or d.senate.approved[old_owner] or old_owner == "INDEPENDENT_FORCES"
        or old_owner == "NEUTRAL" or string.find(old_owner, "^DIPLOMACY_VASSALS") then
        return
    end
    d.senate.stability = M.max(0, d.senate.stability - rules().UNAPPROVED_CONQUEST_COST)
    d.show(profile.name .. ": the invasion of " .. planet_name .. " was never approved. Cohesion "
        .. d.senate.stability .. "%. Declare war through the " .. profile.name .. " to make it a war target.",
        nil, WARN)
end

function Senate.watch(d)
    if GetCurrentTime() < (d.senate.next_watch or 0) then
        return
    end
    d.senate.next_watch = GetCurrentTime() + rules().WATCH_SECONDS
    local now = GetCurrentTime()
    for name, seat in pairs(Senate.seats(d)) do
        local o = opinion_entry(d, name)
        local ok, blockaded = pcall(EvaluatePerception, "Blockaded", d.human, seat.planet)
        local attacked = ok and type(blockaded) == "number" and blockaded > 0
        if attacked and not o.under_attack then
            local recent = 0
            o.attacks = o.attacks or {}
            for _, time in pairs(o.attacks) do
                if now - time < weeks(rules().ATTACK_MEMORY_WEEKS) then
                    recent = recent + 1
                end
            end
            table.insert(o.attacks, now)
            Senate.sway(d, name, -(rules().ATTACK_OPINION + recent * rules().REPEATED_ATTACK_OPINION),
                recent > 0 and "attacked again" or "came under attack")
        elseif not attacked and o.under_attack then
            Senate.sway(d, name, rules().DEFENDED_OPINION, "the attack was beaten off")
            if o.invaded then
                Senate.sway(d, name, rules().INVASION_REPELLED_OPINION, "the invasion was repelled")
                Republic.change_mandate(d, Republic.CONFIG.REPELLED_MANDATE)
            end
            o.invaded = nil
        end
        o.under_attack = attacked
    end
end

function Senate.on_battle_end(d, mode_name)
    if Engine_Log then Engine_Log("SENATE battle ended: " .. tostring(mode_name)) end
    if not mode_name or not string.find(string.upper(tostring(mode_name)), "LAND") then
        return
    end
    for name, o in pairs(d.senate.opinion) do
        if o.under_attack and not o.invaded then
            o.invaded = true
            Senate.sway(d, name, -rules().INVASION_OPINION, "enemy troops landed")
        end
    end
end

function Senate.on_world_lost(d, planet_name, readable)
    local name = string.upper(planet_name)
    local seated = d.senate.opinion[name] or (d.republic and d.republic.senators and d.republic.senators[name])
    Republic.on_world_lost(d, name)
    if not seated then
        return
    end
    d.senate.opinion[name] = nil
    d.senate.lobbying[name] = nil
    local why = "the Republic lost " .. readable
    local seats = Senate.seats(d)
    for _, seat in pairs(seats) do
        opinion_entry(d, seat.name)
    end
    for other, _ in pairs(d.senate.opinion) do
        Senate.sway(d, other, -rules().WORLD_LOST_OPINION, why)
        if seats[other] and Republic.cares_for_defence(d, seats[other]) then
            Senate.sway(d, other, -Republic.CONFIG.SENATE.LOST_WORLD_DEFENCE, why .. ": its defence is in doubt")
        end
    end
end

local Grants = require("eawx-plugins/diplomacy/DiplomacyGrants")

local function strip_world(d, planet, destination)
    local kept, moved = {}, 0
    for _, unit in pairs(Find_All_Objects_Of_Type(d.human) or {}) do
        if TestValid(unit) then
            local at = unit.Get_Planet_Location()
            if at and at == planet then
                local relevant = get_relevant_object(unit)
                if TestValid(relevant) then
                    local hero = unit.Is_Category("SpaceHero") or unit.Is_Category("InfantryHero")
                        or unit.Is_Category("VehicleHero") or unit.Is_Category("NonCombatHero")
                        or string.upper(unit.Get_Type().Get_Name()) == "DIPLOMACY_ENVOY"
                    local ship = unit.Is_Category("Fighter") or unit.Is_Category("Bomber") or unit.Is_Category("Corvette")
                        or unit.Is_Category("Frigate") or unit.Is_Category("Capital") or unit.Is_Category("SuperCapital")
                        or unit.Is_Category("SpaceHero")
                    local structure = unit.Is_Category("Structure") or unit.Is_Category("SpaceStructure")
                    if hero or ship then
                        if destination then
                            local unit_type = relevant.Get_Type()
                            relevant.Despawn()
                            Spawn_Unit(unit_type, destination, d.human)
                            moved = moved + 1
                        end
                    elseif structure or is_valid_category(unit) then
                        table.insert(kept, relevant.Get_Type())
                        relevant.Despawn()
                    end
                end
            end
        end
    end
    return kept, moved
end

local function secede(d, names)
    local independent = Find_Player("INDEPENDENT_FORCES")
    if not independent then
        return
    end
    local readable = {}
    for _, name in ipairs(names) do
        local planet = FindPlanet(name)
        if planet and planet.Get_Owner() == d.human then
            table.insert(readable, d:planet_name(planet))
            local destination, best = nil, nil
            for _, other in pairs(FindPlanet.Get_All_Planets()) do
                local other_name = string.upper(other.Get_Type().Get_Name())
                if other.Get_Owner() == d.human and not d.senate.seceding[other_name] then
                    local distance = planet.Get_Distance(other)
                    if not best or distance < best then
                        destination, best = other, distance
                    end
                end
            end
            local kept = strip_world(d, planet, destination)
            d.own_transfers[name] = true
            planet.Change_Owner(independent)
            for _, unit_type in ipairs(kept) do
                pcall(Spawn_Unit, unit_type, planet, independent)
            end
            for _, unit_type in ipairs(Grants.for_world(name)) do
                pcall(Spawn_Unit, unit_type, planet, independent)
            end
            d.senate.opinion[name] = nil
            d.senate.lobbying[name] = nil
            d.senate.anger[name] = nil
            Republic.on_world_lost(d, name)
        end
    end
    if table.getn(readable) == 0 then
        return
    end
    local list = readable[1]
    for i = 2, table.getn(readable) do
        list = list .. (i == table.getn(readable) and " and " or ", ") .. readable[i]
    end
    d.senate.stability = M.max(0, d.senate.stability - rules().SECESSION_STABILITY * table.getn(readable))
    Republic.change_mandate(d, -Republic.CONFIG.SECESSION_MANDATE)
    d.show("SECESSION: the senators of " .. list .. " rise together and walk out of the " .. Senate.profile(d).name
        .. ". Their worlds declare themselves free of the New Republic, and the garrisons there go with them.",
        nil, {r = 255, g = 110, b = 90}, 40)
    d.show("Your ships and commanders there have been ordered home. The Republic is diminished: cohesion "
        .. d.senate.stability .. "%.", nil, WARN, 30)
    for other, _ in pairs(d.senate.opinion) do
        Senate.sway(d, other, -rules().SECESSION_OPINION_SHOCK, "worlds left the Republic")
    end
end

local function check_secession(d)
    if Republic.watching(d) or Republic.council(d) then
        return
    end
    local profile = Senate.profile(d)
    local threshold = profile.council and rules().SECESSION_OPINION_COUNCIL or rules().SECESSION_OPINION
    local needed = profile.council and rules().SECESSION_WEEKS_COUNCIL or rules().SECESSION_WEEKS
    local trigger = false
    local Laws = Republic.part("laws")
    for name, seat in pairs(Senate.seats(d)) do
        local anger = d.senate.anger[name] or 0
        local own_threshold, own_needed = Republic.secession_rules(d, name, threshold, needed)
        if Laws and Laws.no_secession(d, name) then
            anger = 0
        elseif seat.opinion <= own_threshold then
            anger = anger + 1
            if anger == rules().SECESSION_WARN_WEEKS then
                d.show("Senate: separatist rallies fill the streets of " .. d:planet_name(seat.planet)
                    .. ". Its senator speaks openly of leaving the Republic.", nil, WARN, 25)
            end
            if anger >= own_needed then
                trigger = true
            end
        else
            anger = M.max(0, anger - 1)
        end
        d.senate.anger[name] = (anger > 0) and anger or nil
    end
    if trigger then
        local leaving = {}
        d.senate.seceding = {}
        for name, anger in pairs(d.senate.anger) do
            if anger >= rules().SECESSION_JOIN_WEEKS then
                table.insert(leaving, name)
                d.senate.seceding[name] = true
            end
        end
        secede(d, leaving)
        d.senate.seceding = {}
    end
end

Senate.check_secession = check_secession

local LOBBY_TEXT = {
    PROTECT = "wants warships stationed in orbit for %d weeks",
    VISIT = "wants a Delegate or a hero in orbit for %d weeks",
}

function Senate.lobby(d, planet)
    local name = string.upper(planet.Get_Type().Get_Name())
    local seats = Senate.seats(d)
    local display = d:planet_name(planet)
    if not seats[name] then
        d.human.Give_Money(rules().LOBBY_COST)
        d.show("Senate: " .. display .. " has no Senator's Office, so it has no senator to lobby. Credits returned.", nil, WARN)
        return
    end
    if d.senate.lobbying[name] then
        d.human.Give_Money(rules().LOBBY_COST)
        d.show("Senate: the senator of " .. display .. " is still waiting on its last request. Credits returned.", nil, WARN)
        return
    end
    Senate.sway(d, name, rules().LOBBY_OPINION, "you lobbied its senator")
    local kinds = {"PROTECT", "VISIT"}
    local kind = kinds[GameRandom.Free_Random(1, 2)]
    d.senate.lobbying[name] = {kind = kind, progress = 0, expires = GetCurrentTime() + weeks(rules().LOBBY_WEEKS)}
    d.show("Senate: the senator of " .. display .. " " .. string.format(LOBBY_TEXT[kind], rules().LOBBY_TASK_WEEKS)
        .. " to back the government.", nil, COLOR, 25)
end

local function hero_or_diplomat_at(d, planet)
    for _, unit in pairs(Find_All_Objects_Of_Type(d.human) or {}) do
        if TestValid(unit) then
            local at = unit.Get_Planet_Location()
            if at and at == planet then
                if string.upper(unit.Get_Type().Get_Name()) == "DIPLOMACY_ENVOY" or unit.Is_Category("SpaceHero")
                    or unit.Is_Category("NonCombatHero") or unit.Is_Category("InfantryHero")
                    or unit.Is_Category("VehicleHero") then
                    return true
                end
            end
        end
    end
    return false
end

local function check_lobbying(d)
    for name, task in pairs(d.senate.lobbying) do
        local planet = FindPlanet(name)
        if not planet or planet.Get_Owner() ~= d.human then
            d.senate.lobbying[name] = nil
        else
            local display = d:planet_name(planet)
            if task.kind == "PROTECT" and DiplomacyAI.strength_at(d.human, planet) > 0 then
                task.progress = task.progress + 1
            elseif task.kind == "VISIT" and hero_or_diplomat_at(d, planet) then
                task.progress = task.progress + 1
            end
            if task.progress >= rules().LOBBY_TASK_WEEKS then
                d.senate.lobbying[name] = nil
                Senate.sway(d, name, rules().LOBBY_DONE_OPINION, "you kept your word to its senator")
                d.show("Senate: the senator of " .. display .. " is satisfied and now backs the government more.", nil, COLOR)
            elseif GetCurrentTime() >= task.expires then
                d.senate.lobbying[name] = nil
                Senate.sway(d, name, -rules().LOBBY_FAILED_OPINION, "you ignored its senator's request")
                d.show("Senate: the senator of " .. display .. " feels ignored.", nil, WARN)
            end
        end
    end
end

local function notify(d, text, color, time)
    if not d.senate_window_open then
        d.show(text, nil, color or COLOR, time)
    end
end

local WISH_TEXT = {
    NO_PEACE = "no peace with %s while they threaten its border",
    NO_WAR = "no new wars for %d weeks",
}

function Senate.wish(d, seat)
    if (seat.bloc == "Frontier" or seat.bloc == "Frontier Defence Caucus") and seat.threat then
        return {kind = "NO_PEACE", target = seat.threat,
                text = string.format(WISH_TEXT.NO_PEACE, the_name(d, seat.threat))}
    end
    local w = (seat.bloc == "Heartland" or seat.bloc == "Core Moderates") and rules().PROMISE_WEEKS
        or rules().PROMISE_WEEKS_SHORT
    return {kind = "NO_WAR", weeks = w, text = string.format(WISH_TEXT.NO_WAR, w)}
end

function Senate.vote_of(d, seat, motion)
    if seat.councillor then
        return council_part().vote(d, seat.name, motion)
    end
    local debate = d.senate.debate
    if debate and debate.motion == motion and debate.pressured[seat.name] then
        return 1
    end
    local Blocs = Republic.part("blocs")
    local vote
    if Blocs then
        vote = Blocs.vote(d, seat, motion)
    else
        vote = Republic.seat_vote(d, seat, motion)
        if vote == nil then
            vote = seat_vote(seat, motion, d.senate.stability)
        end
    end
    return Republic.adjust_vote(d, seat, motion, vote)
end

function Senate.can_propose(d)
    local name = Senate.profile(d).name
    local debate = d.senate.debate
    if debate or d.senate.bloc_pending then
        return false, "Another motion is on the " .. name .. " floor."
    end
    if d.senate.recess then
        return false, "The " .. name .. " is in recess until next week."
    end
    return true
end

function Senate.open_debate(d, motion, enact)
    local ok, reason = Senate.can_propose(d)
    if not ok then
        return false, reason
    end
    local profile = Senate.profile(d)
    if profile.council then
        local paid, why = council_part().pay_vote(d)
        if not paid then
            return false, why
        end
    end
    d.senate.debate = {motion = motion, enact = enact, pressured = {}, opened = GetCurrentTime()}
    local result = Senate.tally(d, motion)
    notify(d, profile.name .. ": the motion to " .. motion.text .. " is before the chamber. It votes at the start "
        .. "of next week; as things stand, it would " .. (result.passed and "pass" or "fail") .. " (" .. result.yes
        .. " for, " .. result.no .. " against).", COLOR, 25)
    return true
end

local function close_debate(d)
    d.senate.debate = nil
end

function Senate.open_bloc_debate(d, motion)
    local ok = Senate.can_propose(d)
    if not ok then
        return false
    end
    local Blocs = Republic.part("blocs")
    d.senate.debate = {motion = motion, enact = Blocs and Blocs.enactor(d, motion), pressured = {}, opened = GetCurrentTime()}
    local result = Senate.tally(d, motion)
    local bloc = Blocs and Blocs.name_of(motion.bloc) or "bloc"
    notify(d, "Senate: the " .. bloc .. " puts a motion to " .. motion.text
        .. " before the chamber. It votes at the start of next week; as things stand, it would "
        .. (result.passed and "pass" or "fail") .. " (" .. result.yes .. " for, " .. result.no .. " against).", COLOR, 25)
    if not d.senate_window_open then
        pcall(M.show_document, {
            "The " .. bloc .. " rises in the chamber and puts a motion of its own: to " .. motion.text .. ".",
            "",
            "The Senate votes at the start of next week. As things stand, it would " .. (result.passed and "pass" or "fail")
                .. ": " .. result.yes .. " for, " .. result.no .. " against.",
            "",
            "The government cannot withdraw a bloc's motion. Only a veto from the Senate chamber stops it, and every "
                .. "senator who stands for it will think less of the government.",
        }, "A Bloc's Motion", "The " .. bloc .. " puts a motion to the Senate.")
    end
    return true
end

function Senate.resolve_vote(d)
    local debate = d.senate.debate
    if not debate or debate.failed then
        return nil
    end
    local profile = Senate.profile(d)
    local result = Senate.tally(d, debate.motion, true)
    debate.result = result
    d.senate.recess = not profile.council
    d.senate.last_vote = {text = debate.motion.text, passed = result.passed, yes = result.yes, no = result.no,
                          abstain = result.abstain}
    if result.passed and debate.motion.bloc then
        close_debate(d)
        d.senate.bloc_pending = debate
        d.show(profile.name .. ": the motion to " .. debate.motion.text .. " passed. " .. Senate.describe(result)
            .. ". It takes effect next week unless you veto it.", nil, COLOR, 25)
    elseif result.passed then
        close_debate(d)
        d.show(profile.name .. ": the motion to " .. debate.motion.text .. " passed. " .. Senate.describe(result)
            .. (profile.council and "." or ". The chamber is in recess until next week."), nil, COLOR, 25)
        local Blocs = (not profile.council) and Republic.part("blocs")
        if Blocs and Blocs.on_passed then
            pcall(Blocs.on_passed, d, debate.motion, result)
        end
        Senate.enact(d, debate)
    elseif debate.motion.bloc or debate.motion.senate then
        close_debate(d)
        d.show(profile.name .. ": the motion to " .. debate.motion.text .. " failed. " .. Senate.describe(result) .. ".",
            nil, COLOR, 25)
    else
        debate.failed = true
        d.show(profile.name .. ": the motion to " .. debate.motion.text .. " failed. " .. Senate.describe(result)
            .. (profile.council and ". You may override the Council until next week."
                or ". You may override the chamber until its recess ends next week."), nil, WARN, 25)
    end
    return result
end

function Senate.enact(d, debate)
    local motion = debate.motion
    if motion.kind == "WAR" then
        d.senate.approved[motion.target] = true
    elseif motion.kind == "ADMIT_ASSOCIATE" or motion.kind == "ADMIT_MEMBER" then
        Republic.change_mandate(d, Republic.CONFIG.ADMIT_MANDATE + Republic.admission_bonus(d))
    end
    if motion.mandate then
        d.senate.mandates[motion.target] = motion.relation
        Senate.start_mandate_mission(d, motion, debate.result)
    end
    if debate.enact then
        debate.enact()
    end
end

function Senate.override_debate(d)
    local debate = d.senate.debate
    if not debate or not debate.failed then
        return false
    end
    close_debate(d)
    Senate.override(d, {motion = debate.motion, result = debate.result})
    Senate.enact(d, debate)
    return true
end

function Senate.veto(d)
    local debate = d.senate.bloc_pending
    if not debate then
        return false, "Nothing to veto."
    end
    d.senate.bloc_pending = nil
    local cost = Senate.profile(d).override_cost
    d.senate.stability = M.max(0, d.senate.stability - cost)
    d.senate.overrides = d.senate.overrides + 1
    local Blocs = Republic.part("blocs")
    if Blocs then
        Blocs.sway_bloc(d, debate.motion.bloc, Senate.seats(d), -Republic.CONFIG.SENATE.VETO_OPINION,
            "you vetoed its bloc's motion")
    end
    d.show("Senate: you veto the motion to " .. debate.motion.text .. ". Cohesion " .. d.senate.stability .. "%; the "
        .. (Blocs and Blocs.name_of(debate.motion.bloc) or "bloc") .. " will not forget it.", nil, WARN, 25)
    return true, "Vetoed."
end

function Senate.veto_debate(d)
    local debate = d.senate.debate
    if not (debate and (debate.motion.bloc or debate.motion.senate) and not debate.failed) then
        return false, "Nothing to veto."
    end
    local angry = 0
    for name, seat in pairs(Senate.seats(d)) do
        if Senate.vote_of(d, seat, debate.motion) == 1 then
            Senate.sway(d, name, -Republic.CONFIG.SENATE.VETO_OPINION, "you vetoed a motion it stood for")
            angry = angry + 1
        end
    end
    close_debate(d)
    local Blocs = Republic.part("blocs")
    d.show("Senate: you veto the " .. (debate.motion.senate and "chamber" or (Blocs and Blocs.name_of(debate.motion.bloc) or "bloc")) .. "'s motion to "
        .. debate.motion.text .. ". The " .. angry .. " senators who stood for it will not forget it.", nil, WARN, 25)
    return true, "Vetoed: " .. angry .. " senators resent it."
end

function Senate.withdraw(d)
    local debate = d.senate.debate
    if debate and (debate.motion.bloc or debate.motion.senate) and not debate.failed then
        return false
    end
    if debate then
        close_debate(d)
        notify(d, Senate.profile(d).name .. ": the motion to " .. debate.motion.text .. " was withdrawn.")
    end
end

function Senate.week_tick(d)
    local pending = d.senate.bloc_pending
    if pending then
        d.senate.bloc_pending = nil
        Senate.enact(d, pending)
    end
    if d.senate.recess then
        d.senate.recess = false
        local debate = d.senate.debate
        if debate and debate.failed then
            close_debate(d)
        end
        return
    end
    local debate = d.senate.debate
    if debate and debate.failed then
        close_debate(d)
    elseif debate and GetCurrentTime() - (debate.opened or 0) > 1 then
        Senate.resolve_vote(d)
    end
end

local NOUNS_OFFER = {CEASEFIRE = "a ceasefire", ALLIANCE = "an alliance"}

local function capital_words(text)
    return (string.gsub(text, "(%a)(%a*)", function(a, b) return string.upper(a) .. b end))
end

function Senate.start_mandate_mission(d, motion, result)
    local supporters = {}
    for name, vote in pairs((result and result.worlds) or {}) do
        if vote > 0 then
            table.insert(supporters, name)
        end
    end
    local mission = {target = motion.target, relation = motion.relation, supporters = supporters,
                     deadline = GetCurrentTime() + weeks(rules().MANDATE_WEEKS)}
    d.senate.mandate_missions[motion.target] = mission
    local title_offer = (motion.relation == "ALLIANCE") and "an Alliance" or "a Ceasefire"
    mission.goal = Goals.add(d, "Senate Mandate: Offer " .. title_offer .. " to "
        .. the_name(d, motion.target), {
            "The " .. Senate.profile(d).name .. " authorised you to offer " .. NOUNS_OFFER[motion.relation] .. " to "
                .. the_name(d, motion.target) .. ".",
            "Make the offer in the Diplomacy window within " .. rules().MANDATE_WEEKS .. " weeks.",
            "They need not accept: the offer itself satisfies the chamber.",
            "If you ignore the mandate, cohesion falls, its supporters lose faith and the mandate lapses.",
        }, mission.deadline)
end

function Senate.on_offer(d, target, relation)
    local mission = d.senate.mandate_missions[target]
    if mission and (relation == mission.relation or (relation == "ALLIANCE" and mission.relation == "CEASEFIRE")) then
        d.senate.mandate_missions[target] = nil
        Goals.remove(d, mission.goal)
        d.show(Senate.profile(d).name .. ": you carried out the mandate to offer " .. NOUNS_OFFER[mission.relation]
            .. " to " .. the_name(d, target) .. ".", nil, COLOR)
    end
end

local function check_mandate_missions(d)
    for target, mission in pairs(d.senate.mandate_missions) do
        if GetCurrentTime() >= mission.deadline then
            d.senate.mandate_missions[target] = nil
            d.senate.mandates[target] = nil
            Goals.remove(d, mission.goal)
            if not Republic.council(d) then
                d.senate.stability = M.max(0, d.senate.stability - rules().MANDATE_FAILED_STABILITY)
            end
            for _, name in ipairs(mission.supporters) do
                Senate.sway(d, name, -rules().MANDATE_FAILED_OPINION, "you ignored the chamber's mandate")
            end
            d.show(Senate.profile(d).name .. ": you never offered " .. NOUNS_OFFER[mission.relation] .. " to "
                .. the_name(d, target) .. ". The mandate lapses, and those who backed it feel betrayed.", nil, WARN, 25)
        end
    end
end

function Senate.use_mandate(d, motion)
    if motion.kind ~= "TREATY" or not motion.relation then
        return false
    end
    local granted = d.senate.mandates[motion.target]
    local order = {CEASEFIRE = 1, ALLIANCE = 2, VASSAL = 3}
    if granted and (order[granted] or 0) >= (order[motion.relation] or 9) then
        d.senate.mandates[motion.target] = nil
        return true
    end
    return false
end

local ACTS = {
    FRONTIER_FUND = {
        text = "pass the Frontier Defence Act",
        label = "Frontier Defence Act",
        tip = "Funds the defence of the border worlds. Frontier senators support it; the Heartland pays for it.",
        cost = function() return rules().FRONTIER_FUND_COST end,
        enact = function(d)
            for name, seat in pairs(Senate.seats(d)) do
                if seat.bloc == "Frontier" or seat.bloc == "Frontier Defence Caucus" then
                    Senate.sway(d, name, rules().ACT_OPINION, "the Frontier Defence Act")
                elseif seat.bloc == "Heartland" or seat.bloc == "Core Moderates"
                        or seat.bloc == "Trade and Industry Coalition" then
                    Senate.sway(d, name, -rules().ACT_OPINION_COST, "paying for the Frontier Defence Act")
                end
            end
        end,
    },
    UNITY = {
        text = "hold a Unity Address before the chamber",
        label = "Unity Address",
        tip = "The Chancellor speaks for the whole Republic: cohesion rises a little, everyone's opinion too.",
        cost = function() return rules().UNITY_COST end,
        enact = function(d)
            d.senate.unity_at = GetCurrentTime()
            d.senate.stability = M.min(100, d.senate.stability + rules().UNITY_STABILITY)
            for name, _ in pairs(Senate.seats(d)) do
                Senate.sway(d, name, rules().UNITY_OPINION, "the Unity Address")
            end
        end,
    },
}
Senate.ACTS = ACTS

function Senate.available_motions(d)
    local motions = {}
    local council = Republic.council(d)
    if council then
        if council_part().choosing(d) then
            return motions
        end
        for _, m in ipairs(council_part().motions(d)) do
            table.insert(motions, m)
        end
    else
        for key, act in pairs(ACTS) do
            local wait = (key == "UNITY") and d.senate.unity_at
                and (Republic.CONFIG.SENATE.UNITY_WEEKS - M.floor((GetCurrentTime() - d.senate.unity_at) / weeks(1)))
            local resting = wait and wait > 0
            table.insert(motions, {kind = "ACT", act = key, text = act.text, label = act.label, cost = act.cost(),
                                   disabled = resting or nil,
                                   tip = act.tip .. " Costs " .. act.cost() .. " credits if passed."
                                       .. (resting and (" It can be held again in " .. wait .. " week"
                                       .. ((wait == 1) and "" or "s") .. ".") or "")})
        end
        local Council = council_part()
        if Council and Council.intel_ready(d) then
            local C = Council.CONFIG
            local poor = d.human.Get_Credits() < C.INTEL_CREDITS
            table.insert(motions, {kind = "INTEL", text = "fund intelligence operations",
                label = "Fund Intelligence", disabled = poor or nil,
                tip = "Republic Intelligence gets one more agent place (" .. Council.intel_places(d) .. " of "
                    .. C.INTEL_MAX .. " funded so far). Costs " .. C.INTEL_CREDITS .. " credits. Once in "
                    .. C.INTEL_WEEKS .. " weeks." .. (poor and (" The treasury can't pay for it now ("
                    .. C.INTEL_CREDITS .. " credits).") or "")})
        end
        for _, m in ipairs(Republic.motions(d)) do
            table.insert(motions, m)
        end
    end
    for _, world in ipairs(Missions.integration_requests(d)) do
        local planet = FindPlanet(world)
        local name = planet and d:planet_name(planet) or world
        table.insert(motions, {kind = "ADMIT_MEMBER", world = world, target = "INDEPENDENT_FORCES", group = "ADMIT",
            text = "admit " .. name .. " as a member world", label = name,
            tip = name .. " has completed its integration missions and is content. If the motion passes, it becomes "
                .. "a full member world with a seat in the chamber."})
    end
    local powers = {}
    for faction, _ in pairs(FACTIONS.PLAYABLE) do
        powers[faction] = true
    end
    for faction, _ in pairs(FACTIONS.MINOR or {}) do
        powers[faction] = true
    end
    for faction, _ in pairs(powers) do
        local other = Find_Player(faction)
        local talks = faction ~= "IMPERIAL_PROTEUS"
        if other and other ~= d.human and Senate.owns_worlds(other) then
            local relation = d:relation(faction)
            local name = d.display_name(faction)
            local the = the_name(d, faction)
            if relation == "WAR" then
                if talks and not d.senate.mandates[faction] then
                    table.insert(motions, {kind = "TREATY", target = faction, relation = "CEASEFIRE", mandate = true,
                        text = "authorise peace talks with " .. the, label = name, group = "PEACE",
                        tip = "If it passes, you may agree a ceasefire with " .. the .. " without another "
                            .. "vote, and must offer one within " .. rules().MANDATE_WEEKS .. " weeks."})
                end
            elseif relation == "CEASEFIRE" then
                table.insert(motions, {kind = "WAR", target = faction, text = "declare war on " .. the,
                    label = name, group = "WAR",
                    tip = "If it passes, the Republic declares war on " .. the .. " at once."})
                if talks and d.senate.mandates[faction] ~= "ALLIANCE" then
                    table.insert(motions, {kind = "TREATY", target = faction, relation = "ALLIANCE", mandate = true,
                        text = "authorise an alliance with " .. the, label = name, group = "ALLIANCE",
                        tip = "If it passes, you may offer " .. the .. " an alliance without another "
                            .. "vote, and must do so within " .. rules().MANDATE_WEEKS .. " weeks."})
                end
            end
        end
    end
    for _, m in ipairs(Senate.authority_motions(d)) do
        table.insert(motions, m)
    end
    return motions
end

local function authority(d, which)
    d.senate[which] = d.senate[which] or {}
    return d.senate[which]
end

function Senate.protect_key(target)
    local Worlds = require("eawx-plugins/diplomacy/DiplomacyWorlds")
    local planet = Worlds.is_slot(target) and Worlds.world_of(Find_Player(target))
    return planet and string.upper(planet.Get_Type().Get_Name()) or string.upper(target or "")
end

function Senate.authorised(d, which, key)
    local t = d.senate and d.senate[which]
    return (t and t[key] and t[key] > GetCurrentTime()) == true
end

function Senate.authority_motions(d)
    local out = {}
    if not d.republic then
        return out
    end
    local weeks = Republic.CONFIG.SENATE.AUTHORITY_WEEKS
    local okp, P = pcall(require, "eawx-plugins/new-republic/RepublicProtectorates")
    local Worlds = require("eawx-plugins/diplomacy/DiplomacyWorlds")
    if okp and P then
        local powers = {}
        for faction, _ in pairs(FACTIONS.MINOR or {}) do
            table.insert(powers, faction)
        end
        for faction, _ in pairs(FACTIONS.PLAYABLE) do
            table.insert(powers, faction)
        end
        for _, faction in ipairs(Worlds.names()) do
            table.insert(powers, faction)
        end
        for _, faction in ipairs(powers) do
            local other = Find_Player(faction)
            local key = Senate.protect_key(faction)
            if other and other ~= d.human and Senate.owns_worlds(other) and d:relation(faction) ~= "PROTECTORATE"
                    and d:relation(faction) ~= "WAR" and P.eligible(d, faction)
                    and not Senate.authorised(d, "protect_ok", key) then
                local name = d.display_name(faction)
                table.insert(out, {kind = "PROTECT_AUTH", target = faction, world = key, group = "PROTECT",
                    text = "authorise protection for " .. name, label = name,
                    tip = "If it passes, you may offer " .. name .. " the Republic's protection without another vote "
                        .. "for " .. weeks .. " weeks."})
            end
        end
    end
    local capital = nil
    local okd, Deals = pcall(require, "eawx-plugins/diplomacy/DiplomacyDeals")
    if okd and Deals and Deals.capital then
        capital = Deals.capital(d, d.human)
    end
    local seats = Senate.seats(d)
    local worlds = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local key = string.upper(planet.Get_Type().Get_Name())
        if planet.Get_Owner() == d.human and planet ~= capital and not Senate.authorised(d, "cede_ok", key) then
            table.insert(worlds, {planet = planet, key = key, name = d:planet_name(planet)})
        end
    end
    table.sort(worlds, function(a, b) return a.name < b.name end)
    for _, w in ipairs(worlds) do
        local member = seats[w.key] ~= nil
        table.insert(out, {kind = "CEDE_AUTH", target = "INDEPENDENT_FORCES", world = w.key, group = "CEDE",
            text = "permit " .. w.name .. " to be offered in negotiations", label = w.name,
            tip = "If it passes, " .. w.name .. " may be offered in any deal for " .. weeks .. " weeks. "
                .. (member and ("Its own senator and its bloc will fight it hardest; the pragmatic Trade and Bothan "
                    .. "blocs mind least.") or "A territory without a seat: the chamber minds less.")})
    end
    return out
end

function Senate.grant_authority(d, motion)
    local weeks = Republic.CONFIG.SENATE.AUTHORITY_WEEKS
    local until_time = GetCurrentTime() + weeks * CONFIG.WEEK_SECONDS
    if motion.kind == "PROTECT_AUTH" then
        authority(d, "protect_ok")[motion.world] = until_time
        d.show(Senate.profile(d).name .. ": you may offer " .. d.display_name(motion.target) .. " the Republic's "
            .. "protection for " .. weeks .. " weeks.", nil, COLOR, 20)
    else
        authority(d, "cede_ok")[motion.world] = until_time
        local planet = FindPlanet(motion.world)
        d.show(Senate.profile(d).name .. ": " .. (planet and d:planet_name(planet) or motion.world) .. " may be "
            .. "offered in negotiations for " .. weeks .. " weeks.", nil, COLOR, 20)
    end
end

function Senate.enactor(d, motion)
    local enact = nil
    if motion.kind == "ADMIT_MEMBER" then
        enact = function() Missions.integrate(d, motion.world) end
    elseif motion.kind == "PROTECT_AUTH" or motion.kind == "CEDE_AUTH" then
        enact = function() Senate.grant_authority(d, motion) end
    elseif motion.kind == "WAR" then
        enact = function() d:set_relation(motion.target, "WAR") end
    elseif motion.kind == "LEVY" or motion.kind == "FOUND" or motion.kind == "INTEL" or motion.kind == "APPEAL"
            or motion.kind == "INVADE" then
        enact = function() council_part().enact(d, motion) end
    elseif Republic.enacts(motion) then
        enact = function() Republic.enact_motion(d, motion) end
    elseif motion.kind == "ACT" then
        enact = function()
            local act = ACTS[motion.act]
            local cost = act.cost()
            if d.human.Get_Credits() < cost then
                d.show("Senate: the treasury cannot pay for the act (" .. cost .. " credits). It lapses.", nil, WARN)
                return
            end
            d.human.Give_Money(-cost)
            act.enact(d)
            d.show("Senate: the act takes effect.", nil, COLOR)
        end
    end
    return enact
end

function Senate.propose_from_window(d, motion)
    local council = Republic.council(d)
    local price = (not council) and (motion.capital or Republic.CONFIG.SENATE.MOTION_CAPITAL) or 0
    if price > 0 then
        local can, reason = Senate.can_propose(d)
        if not can then
            return false, reason
        end
        if Republic.capital(d) < price then
            return false, "Not enough political capital (" .. price .. ")."
        end
    end
    local ok, reason = Senate.open_debate(d, motion, Senate.enactor(d, motion))
    if ok and price > 0 then
        Republic.spend(d, price)
        local Blocs = Republic.part("blocs")
        if Blocs then
            Blocs.break_promises(d, motion, Senate.seats(d))
        end
    end
    return ok, reason
end

local function seat_named(d, name)
    if Republic.council(d) then
        return council_part().seats(d)[name]
    end
    return Senate.seats(d)[name]
end

function Senate.lobby_seat(d, name)
    if Republic.council(d) then
        return council_part().lobby(d, name)
    end
    local seat = seat_named(d, name)
    if not seat then
        return false, "That world has no seat."
    end
    local now = GetCurrentTime()
    local last = d.senate.lobbied[name]
    if last and now - last < weeks(rules().LOBBY_SEAT_WEEKS) then
        return false, "Its senator was lobbied recently."
    end
    if not Republic.spend(d, Republic.CONFIG.LOBBY_CAPITAL) then
        return false, "Not enough political capital (" .. Republic.CONFIG.LOBBY_CAPITAL .. ")."
    end
    d.senate.lobbied[name] = now
    Senate.sway(d, name, rules().LOBBY_SEAT_OPINION, "you lobbied its senator")
    return true, "Lobbied: opinion +" .. rules().LOBBY_SEAT_OPINION .. "."
end

function Senate.promise(d, name)
    local seat = seat_named(d, name)
    if not seat then
        return false, "That world has no seat."
    end
    if d.senate.promises[name] then
        return false, "You already gave its senator your word."
    end
    local wish = Senate.wish(d, seat)
    wish.made = GetCurrentTime()
    if wish.weeks then
        wish.ends = GetCurrentTime() + weeks(wish.weeks)
    end
    d.senate.promises[name] = wish
    Senate.sway(d, name, rules().PROMISE_OPINION, "you promised " .. wish.text)
    return true, "Promised " .. wish.text .. ": opinion +" .. rules().PROMISE_OPINION .. "."
end

function Senate.pressure(d, name)
    local debate = d.senate.debate
    if not debate then
        return false, "There is no motion to vote on."
    end
    if not seat_named(d, name) then
        return false, "That world has no seat."
    end
    if debate.pressured[name] then
        return false, "Its senator is already under pressure."
    end
    debate.pressured[name] = true
    if Republic.council(d) then
        Senate.sway(d, name, -rules().PRESSURE_OPINION, "you pressured them")
        return true, "They will vote for the motion (opinion -" .. rules().PRESSURE_OPINION .. ")."
    end
    Senate.sway(d, name, -rules().PRESSURE_OPINION, "you pressured its senator")
    d.senate.stability = M.max(0, d.senate.stability - rules().PRESSURE_STABILITY)
    return true, "Its senator will vote for the motion (opinion -" .. rules().PRESSURE_OPINION .. ", cohesion -"
        .. rules().PRESSURE_STABILITY .. ")."
end

function Senate.appeal(d, bloc)
    local names = {}
    for name, seat in pairs(Senate.seats(d)) do
        if seat.bloc == bloc then
            table.insert(names, name)
        end
    end
    local n = table.getn(names)
    if n == 0 then
        return false, "No seats in that bloc."
    end
    local last = d.senate.appealed[bloc]
    if last and GetCurrentTime() - last < weeks(rules().APPEAL_BLOC_WEEKS) then
        return false, "The bloc heard an appeal recently."
    end
    local cost = n * Republic.CONFIG.APPEAL_CAPITAL_PER_SEAT
    if not Republic.spend(d, cost) then
        return false, "Not enough political capital (" .. cost .. ")."
    end
    d.senate.appealed[bloc] = GetCurrentTime()
    for _, name in ipairs(names) do
        Senate.sway(d, name, rules().APPEAL_BLOC_OPINION, "an appeal to the " .. bloc .. " bloc")
    end
    return true, "Appealed to the " .. bloc .. " bloc: opinion +" .. rules().APPEAL_BLOC_OPINION .. " on " .. n .. " seats."
end

function Senate.on_relation(d, faction, relation)
    Republic.on_relation(d, faction, relation)
    for name, wish in pairs(d.senate.promises) do
        local broken = (wish.kind == "NO_PEACE" and wish.target == faction and relation ~= "WAR")
            or (wish.kind == "NO_WAR" and relation == "WAR" and GetCurrentTime() < (wish.ends or 0))
        if broken then
            d.senate.promises[name] = nil
            Senate.sway(d, name, -rules().PROMISE_BROKEN_OPINION, "you broke your promise of " .. wish.text)
            d.senate.stability = M.max(0, d.senate.stability - rules().PROMISE_BROKEN_STABILITY)
            local planet = FindPlanet(name)
            d.show("Senate: you broke your word to the senator of " .. (planet and d:planet_name(planet) or name)
                .. " (" .. wish.text .. "). The chamber remembers.", nil, WARN)
        end
    end
end

local function check_promises(d)
    for name, wish in pairs(d.senate.promises) do
        if wish.ends and GetCurrentTime() >= wish.ends then
            d.senate.promises[name] = nil
            Senate.sway(d, name, rules().PROMISE_KEPT_OPINION, "you kept your promise of " .. wish.text)
        end
    end
end

local function lean(d, seat)
    if seat.opinion >= rules().LOYAL_OPINION then
        return "backs the government on everything"
    elseif seat.opinion <= rules().HOSTILE_OPINION then
        return "opposes the government on everything"
    elseif seat.bloc == "Resentful" then
        return "opposes the government (resents the occupation)"
    elseif seat.bloc == "New member" then
        return "backs the government (newly joined)"
    elseif seat.bloc == "Frontier" then
        local enemy = the_name(d, seat.threat)
        return "wants war on " .. enemy .. " and no peace with them; neutral on other wars"
    end
    local Blocs = Republic.part("blocs")
    local def = Blocs and Blocs.def(Blocs.key_of(seat.bloc))
    if def then
        local text = string.gsub(def.text, "%.$", "")
        return "follows the " .. def.name .. " (" .. string.lower(string.sub(text, 1, 1)) .. string.sub(text, 2) .. ")"
    end
    return "against new wars, for treaties"
end

Senate.lean_text = lean

function Senate.vote_breakdown(d, seat, motion)
    if seat.councillor then
        return council_part().vote_lines(d, seat.name, motion)
    end
    local Blocs = Republic.part("blocs")
    if Blocs and motion then
        local debate = d.senate.debate
        if debate and debate.motion == motion and debate.pressured[seat.name] then
            return {"Under pressure: votes for."}
        end
        local score, lines, verdict = Blocs.vote_lines(d, seat, motion)
        table.insert(lines, 1, capital_words(verdict) .. " (" .. ((score > 0) and "+" or "") .. score .. "; +"
            .. Republic.CONFIG.SENATE.VOTE_FOR .. " or more for, -" .. Republic.CONFIG.SENATE.VOTE_FOR
            .. " or less against):")
        return lines
    end
    local o = opinion_entry(d, seat.name)
    local lines = {"Opinion of the government: " .. seat.opinion .. "."}
    local own = 0
    for _, event in ipairs(o.events) do
        table.insert(lines, "  " .. event .. ".")
    end
    if seat.unrepresented > 0 then
        table.insert(lines, "  -" .. seat.unrepresented .. " for the " .. seat.bloc .. " bloc's unrepresented worlds.")
    end
    if seat.founding then
        table.insert(lines, "  +" .. seat.founding_bonus .. " as a founding member (its vote counts "
            .. Republic.CONFIG.FOUNDING_WEIGHT .. " times).")
    end
    table.insert(lines, "Votes with the government at " .. rules().LOYAL_OPINION .. " or more; against it at "
        .. rules().HOSTILE_OPINION .. " or less.")
    if motion then
        local debate = d.senate.debate
        if debate and debate.motion == motion and debate.pressured[seat.name] then
            table.insert(lines, "Under pressure: votes for.")
        elseif seat.opinion >= rules().LOYAL_OPINION then
            table.insert(lines, "Loyal: votes for.")
        elseif seat.opinion <= rules().HOSTILE_OPINION then
            table.insert(lines, "Hostile: votes against.")
        else
            local vote = seat_vote(seat, motion, d.senate.stability)
            table.insert(lines, "Otherwise its bloc decides: " .. seat.bloc .. " " .. ((vote > 0 and "votes for")
                or (vote < 0 and "votes against") or "abstains") .. ".")
            if seat.threat then
                table.insert(lines, "Its border enemy: " .. the_name(d, seat.threat) .. ".")
            end
            if d.senate.stability < rules().UNREST_STABILITY then
                table.insert(lines, "Cohesion below " .. rules().UNREST_STABILITY .. "%: undecided senators vote against.")
            end
        end
    end
    return lines
end

function Senate.world_lines(d, seat)
    local o = opinion_entry(d, seat.name)
    local senator = Republic.senator(d, seat.name)
    local lines = {d:planet_name(seat.planet) .. (senator and (" (Senator " .. senator .. ")") or "")
        .. (seat.founding and ", founding member" or "") .. " - " .. seat.bloc .. ", opinion " .. seat.opinion .. ": " .. lean(d, seat) .. "."}
    if seat.unrepresented > 0 then
        table.insert(lines, "   Its bloc resents unrepresented worlds: -" .. seat.unrepresented .. ".")
    end
    if d.senate.anger[seat.name] then
        table.insert(lines, "   Separatist sentiment: " .. d.senate.anger[seat.name] .. " week(s).")
    end
    if table.getn(o.events) > 0 then
        local reasons = ""
        for i, text in ipairs(o.events) do
            reasons = reasons .. (i > 1 and "; " or "") .. text
        end
        table.insert(lines, "   Recently: " .. reasons .. ".")
    end
    local task = d.senate.lobbying[seat.name]
    if task then
        table.insert(lines, "   Request: " .. string.format(LOBBY_TEXT[task.kind], rules().LOBBY_TASK_WEEKS)
            .. " (" .. task.progress .. " done).")
    end
    return lines
end

function Senate.overview(d)
    local profile = Senate.profile(d)
    local seats = Senate.seats(d)
    local lines = {"=== " .. (profile.council and "The Provisional Council" or "The Senate") .. " ==="}
    local counts, total = {}, 0
    for _, seat in pairs(seats) do
        counts[seat.bloc] = (counts[seat.bloc] or 0) + 1
        total = total + 1
    end
    table.insert(lines, "Cohesion: " .. d.senate.stability .. "% (settles towards " .. Republic.cohesion_target(d, total)
        .. "%; lower as the Republic grows and for every war it declared). Mandate: " .. Republic.mandate(d)
        .. ". Political capital: " .. Republic.capital(d) .. " (+" .. M.round(Republic.capital_income(d, total))
        .. " a week).")
    table.insert(lines, "Seats from your worlds (Senator's Offices): " .. total .. ".")
    local occupied, territories = Republic.counts(d, seated_planets(d))
    table.insert(lines, "Occupied worlds (invaded, no Senator's Office yet): " .. occupied .. ". Territories (bases, "
        .. "stations, empty worlds; no politics): " .. territories .. ".")
    local blocs = ""
    for _, bloc in ipairs({"Heartland", "Frontier", "New member", "Resentful"}) do
        if counts[bloc] then
            blocs = blocs .. (blocs ~= "" and ", " or "") .. bloc .. " " .. counts[bloc]
        end
    end
    if blocs ~= "" then
        table.insert(lines, "Blocs: " .. blocs .. ".")
    end
    if profile.offmap > 0 then
        local stance = (profile.offmap_stance == "distant") and "this front is not their main concern"
            or "they follow the government's lead"
        table.insert(lines, "Seats from worlds beyond this region: " .. profile.offmap .. " (" .. stance .. ").")
    end
    if profile.military > 0 then
        table.insert(lines, "Military seats: " .. profile.military .. " (back wars).")
    end
    local unrepresented = {}
    for name, entry in pairs(d.senate.unrepresented) do
        local planet = FindPlanet(name)
        if planet then
            table.insert(unrepresented, "Unrepresented population of " .. d:planet_name(planet) .. ": -"
                .. unrepresented_penalty(entry.weeks, name) .. " (" .. entry.bloc .. ")")
        end
    end
    if table.getn(unrepresented) > 0 then
        table.insert(lines, "Worlds without a Senator's Office (their bloc grows resentful):")
        local shown = M.min(table.getn(unrepresented), 6)
        for i = 1, shown do
            table.insert(lines, "   " .. unrepresented[i])
        end
        if table.getn(unrepresented) > shown then
            table.insert(lines, "   ...and " .. (table.getn(unrepresented) - shown) .. " more worlds.")
        end
    end
    local targets = ""
    for faction, _ in pairs(d.senate.approved) do
        targets = targets .. (targets ~= "" and ", " or "") .. d.display_name(faction)
    end
    table.insert(lines, "Approved war targets: " .. (targets ~= "" and targets or "none") .. ".")
    return lines, seats
end

function Senate.wrap(text, width)
    local parts = {}
    while string.len(text) > width do
        local cut = width
        for i = width, M.floor(width / 2), -1 do
            if string.sub(text, i, i) == " " then
                cut = i
                break
            end
        end
        table.insert(parts, string.sub(text, 1, cut))
        text = "   " .. string.sub(text, cut + 1)
    end
    table.insert(parts, text)
    return parts
end

function Senate.report(d, planet)
    local lines, seats = Senate.overview(d)

    local here = planet and seats[string.upper(planet.Get_Type().Get_Name())]
    table.insert(lines, "")
    if here then
        table.insert(lines, "--- This world ---")
        for _, line in ipairs(Senate.world_lines(d, here)) do
            table.insert(lines, line)
        end
        table.insert(lines, "")
    end
    table.insert(lines, "--- Every seat ---")
    for _, seat in pairs(seats) do
        for _, line in ipairs(Senate.world_lines(d, seat)) do
            table.insert(lines, line)
        end
    end
    local title = string.gsub(table.remove(lines, 1), "^=+ *(.-) *=+$", "%1")
    M.show_document(lines, title, "Seats, blocs and the mood of the chamber.")

    if here then
        d.show("Senate: " .. Senate.world_lines(d, here)[1], nil, COLOR, 20)
    end
end

function Senate.owns_worlds(player)
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == player then
            return true
        end
    end
    return false
end

function Senate.update(d)
    if not d.senate then
        d.senate = {stability = rules().NORMAL_STABILITY, overrides = 0, opinion = {}, approved = {},
                    lobbying = {}, unrepresented = {}, anger = {}, seceding = {}}
        local C = ModContentLoader.get("GameConstants")
        for _, faction in pairs(C.ALL_FACTIONS_NOT_NEUTRAL) do
            local other = Find_Player(faction)
            if other and other ~= d.human and d.human.Is_Enemy(other) and Senate.owns_worlds(other) then
                d.senate.approved[faction] = true
            end
        end
    end
    for _, key in ipairs({"mandates", "promises", "lobbied", "appealed", "mandate_missions"}) do
        d.senate[key] = d.senate[key] or {}
    end
    Republic.setup(d)
    d.senate.council = Republic.council(d)
    local Council = council_part()
    if Council then
        Council.update(d)
    end
    Senate.watch(d)
    if GetCurrentTime() >= (d.senate.next_week or weeks(1)) then
        d.senate.next_week = M.next_week(weeks(1))
        local seated = Republic.council(d) and {} or seated_planets(d)
        Republic.week(d, seated)
        if not Republic.council(d) then
            local seats = Senate.seats(d)
            for _, key in ipairs({"desires", "blocs"}) do
                local mod = Republic.part(key)
                if mod then
                    local ok, err
                    if key == "desires" then
                        ok, err = pcall(mod.week, d, seated, seats)
                    else
                        ok, err = pcall(mod.week, d, seats)
                    end
                    if not ok and Engine_Log then
                        Engine_Log("SENATE " .. key .. ".week: " .. tostring(err))
                    end
                end
            end
        end
        check_lobbying(d)
        check_promises(d)
        check_mandate_missions(d)
        Senate.week_tick(d)
        update_unrepresented(d)
        check_secession(d)
    end
end

return Senate
