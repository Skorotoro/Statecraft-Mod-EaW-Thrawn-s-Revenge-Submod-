require("eawx-util/ChangeOwnerUtilities")
require("eawx-util/PopulatePlanetUtilities")
local CONFIG = require("eawx-plugins/imperial-court/CourtConfig")
local M = require("eawx-plugins/imperial-court/CourtMath")
local Court = require("eawx-plugins/imperial-court/Court")

local Politics = {}

local function serving(s, titled)
    local out = {}
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if c.status == "serving" and (not titled or c.title ~= "courtier") then
            table.insert(out, c)
        end
    end
    return out
end
Politics.serving = serving

local function is_human()
    local empire = Court.player()
    return empire and empire.Is_Human()
end
Politics.is_human = is_human

function Politics.check_regime(s)
    local name = Court.regime_name()
    if name == s.regime then
        return
    end
    local old = s.regime
    s.regime = name
    s.regime_weeks = 0
    s.seen_regimes = s.seen_regimes or {}
    s.seen_regimes[old or "EMPIRE"] = true
    s.seen_regimes[name] = true
    local regime = Court.regime(s)
    local LORE_BY_UNIT = Court.LORE_BY_UNIT
    for i, id in pairs(s.lore_used) do
        if id == -1 then
            s.lore_used[i] = nil
        end
    end
    local ruler = regime.figure and LORE_BY_UNIT[regime.figure]
    local leader = regime.leader_figure and LORE_BY_UNIT[regime.leader_figure]
    for _, c in ipairs(serving(s)) do
        c.leads, c.protected = nil, nil
        if c.lore and c.lore == ruler then
            Court.remove(s, c, "throne", "takes the throne")
        elseif c.lore and c.lore == leader then
            c.leads, c.heir = true, nil
        elseif c.heir then
            for _, r in ipairs(c.release or {}) do
                if r == name then
                    c.heir, c.release = nil, nil
                end
            end
            if c.heir == name then
                c.heir = nil
            end
        end
    end
    if ruler then
        s.lore_used[ruler] = -1
    end
    for _, c in ipairs(serving(s)) do
        local fresh = (c.since or 0) >= s.week
        local soft = 1
        for _, t in ipairs(c.traits) do
            soft = soft * (CONFIG.TRAITS[t].regime_change or 1)
        end
        if not fresh and not c.leads then
            Court.opinion(c, "a new master: " .. regime.title, M.round(CONFIG.OPINION.NEW_MASTER * soft), 8)
            if c.prefers == name then
                Court.opinion(c, "backed " .. regime.title, CONFIG.OPINION.BACKED_WINNER, 10)
            elseif c.prefers then
                Court.opinion(c, "a regime they opposed", M.round(CONFIG.OPINION.OPPOSED_REGIME * soft), 10)
            end
            local shock = CONFIG.FALL_SHOCK[old]
            if shock then
                Court.opinion(c, (old == "PALPATINE") and "the Emperor is dead" or "Thrawn is dead", shock.opinion, 10)
            end
            local F = CONFIG.LOYALIST_FLIP
            if c.loyalist and M.chance(Court.has_trait(c, "loyalist") and F.FLIP_TRUE or F.FLIP) then
                c.loyalist, c.faction_key = nil, nil
                Court.opinion(c, "the old order is gone", F.FLIP_OPINION, F.FLIP_WEEKS)
                Court.news(s, Court.full_name(c) .. " will not serve the new regime gladly and leaves the Loyalists.")
            end
        end
    end
    if CONFIG.FALL_SHOCK[old] then
        s.stability = M.max(0, s.stability - CONFIG.FALL_SHOCK[old].stability)
    end
    s.stability = (s.stability + regime.stability) / 2
    s.regime_shock = 3
    Court.drop_shock(s, "PALPATINE_KILLED")
    Court.add_shock(s, "SUCCESSION")
    local placed = {}
    for key, units in pairs(CONFIG.REGIME_OFFICES[name] or {}) do
        for _, unit in ipairs(units) do
            local i = LORE_BY_UNIT[unit]
            if i and s.lore_used[i] ~= -1 then
                local c = s.lore_used[i] and s.chars[s.lore_used[i]]
                if not c then
                    c = Court.lore_char(s, i, "courtier")
                    Court.settle_loyalty(s, c)
                end
                if c.status == "serving" then
                    local old_holder = Court.char(s, s.offices[key])
                    if old_holder and old_holder ~= c then
                        Court.opinion(old_holder, "replaced by the new regime's man", CONFIG.OPINION.REPLACED, 8)
                    end
                    for other, id in pairs(s.offices) do
                        if id == c.id then
                            s.offices[other] = nil
                        end
                    end
                    s.offices[key] = c.id
                    Court.fleet_office_rank(s)
                    c.posted = (type(c.posted) == "table") and c.posted or {}
                    c.posted.office = s.week
                    placed[key] = true
                    break
                end
            end
        end
    end
    for _, key in ipairs(CONFIG.OFFICE_ORDER) do
        for _, unit in ipairs(not placed[key] and CONFIG.OFFICES[key].lore or {}) do
            local i = LORE_BY_UNIT[unit]
            if i and s.lore_used[i] ~= -1 then
                local _, owner = Court.unit_on_map(i)
                if owner == CONFIG.FACTION then
                    local c = s.lore_used[i] and s.chars[s.lore_used[i]]
                    if not c then
                        c = Court.new_char(s, i, "courtier")
                        c.kind = "unit"
                        Court.settle_loyalty(s, c)
                    end
                    if c.status == "serving" and s.offices[key] ~= c.id and not Court.office_of(s, c) then
                        s.offices[key] = c.id
                        Court.fleet_office_rank(s)
                    end
                    break
                end
            end
        end
    end
    Court.add_legitimacy(CONFIG.FACTION, CONFIG.LEGITIMACY.REGIME_CHANGE)
    Court.news(s, "A new regime: " .. regime.title .. " (" .. regime.leader .. "). Legitimacy suffers; the lords weigh "
        .. "their loyalty.")
end

local function political(s)
    local out = {}
    for _, c in ipairs(serving(s)) do
        if c.title ~= "courtier" or Court.office_of(s, c) or c.fleet_rank or c.heir then
            table.insert(out, c)
        end
    end
    return out
end
Politics.political = political

local function total_power(s)
    local total = 0
    for _, c in ipairs(political(s)) do
        if not c.leads then
            total = total + Court.power(s, c) + (c.influence or 0) * CONFIG.INFLUENCE.FACTION_WEIGHT
        end
    end
    return M.max(1, total)
end

function Politics.interest(s, c)
    local out = {}
    local worlds = table.getn(Court.worlds_of(s, c))
    local regime = Court.regime(s)
    local weak = (100 - s.stability) / 100
    local disloyal = M.max(0, 60 - c.loyalty) / 60
    local ambition = M.max(0, c.ambition - 50) / 50
    local might = M.min(1, Court.power(s, c) / 10)
    local sector = (c.title == "moff") and s.sectors[c.holds or ""] or nil
    local own_domain = sector and sector.warlord and true or false
    if worlds > 0 then
        local want = disloyal * 0.9 + ambition * 0.3 * (0.3 + disloyal) + (c.minder and 0.2 or 0)
        out.autonomy = M.clamp(want, 0, 1.2) * (0.4 + might * 0.6) * (0.5 + weak) * 100
    end
    if (c.title == "moff" or c.title == "grand_moff") and worlds > 0 then
        local want = disloyal * (1 + (own_domain and 0.6 or 0) + Court.isolation(s, c) * 0.4 + ambition * 0.3)
        out.independence = M.clamp(want, 0, 1.6) * (0.2 + might * 1.1) * (0.4 + weak) * (regime.breakaway or 1) * 100
    end
    local target = Court.defect_target(s, c)
    if target then
        local legit = Court.legitimacy() or {}
        local theirs = legit[target] and legit[target].share or 20
        local want = M.max(0, 40 - c.loyalty) / 40
        if Court.has_trait(c, "xenophobe") and s.regime == "THRAWN" then
            want = want + 0.3 * disloyal
        end
        if own_domain then
            want = want * 0.4
        end
        out.defection = M.clamp(want, 0, 1.3) * M.clamp(0.4 + (theirs - Court.legitimacy_share()) / 50, 0.2, 1.4)
            * (regime.defect or 1) * (1.3 - might * 0.6) * 100
    end
    if not s.no_succession and c.prefers and c.prefers ~= s.regime then
        out.succession = (0.2 + ambition * 0.3 + disloyal * 0.6) * (1.1 - might * 0.5) * 100
    end
    if c.heir and not s.no_succession then
        out.succession = M.max(out.succession or 0, 100)
    end
    for key, value in pairs(out) do
        out[key] = M.round(value)
    end
    return out
end

function Politics.members(s)
    local out = {}
    for _, key in ipairs(CONFIG.FACTION_ORDER) do
        out[key] = {}
    end
    local L = CONFIG.LOYALISTS
    local I = CONFIG.INFLUENCE
    local drawn = {}
    for _, h in ipairs(serving(s)) do
        if h.heir and not h.leads and not s.no_succession then
            local pull = CONFIG.HEIR_PULL * M.max(0.5, (h.influence or 0) / I.PULL_FROM)
            local list = Court.ties(s, h, "friends")
            for _, id in ipairs(s.order) do
                local v = s.chars[id]
                if v.status == "serving" and Court.liege(s, v) == h then
                    table.insert(list, v)
                end
            end
            for _, v in ipairs(list) do
                if v ~= h and not v.heir then
                    drawn[v.id] = drawn[v.id] or {}
                    table.insert(drawn[v.id], {regime = h.heir, value = pull})
                end
            end
        end
    end
    for _, c in ipairs(political(s)) do
        if c.leads then
            c.loyalist, c.faction_key, c.interest = nil, nil, nil
        elseif not c.heir and (c.loyalty >= L.JOIN or (c.loyalist and c.loyalty >= L.LEAVE)) then
            c.loyalist, c.faction_key, c.interest = true, "loyalists", nil
            table.insert(out.loyalists, c)
        else
            c.loyalist = nil
            for _, d in ipairs(drawn[c.id] or {}) do
                if not c.prefers or c.prefers == s.regime then
                    c.prefers = d.regime
                end
            end
            c.interest = Politics.interest(s, c)
            for _, d in ipairs(drawn[c.id] or {}) do
                if c.prefers == d.regime and c.interest.succession then
                    c.interest.succession = c.interest.succession + d.value
                end
            end
            local T = CONFIG.FACTION_TIES
            for _, kind in ipairs({"friends", "rivals"}) do
                for _, v in ipairs(Court.ties(s, c, kind)) do
                    local key = v.faction_key
                    local weight = M.clamp((v.influence or 0) / I.PULL_FROM, 0.4, 2.5)
                    if key and key ~= "loyalists" and c.interest[key] then
                        c.interest[key] = c.interest[key] + ((kind == "friends") and T.FRIEND or -T.RIVAL) * weight
                    end
                end
            end
            local liege = Court.liege(s, c)
            if liege and liege.status == "serving" then
                local pull = CONFIG.LIEGE_PULL * M.clamp((liege.influence or 0) / I.PULL_FROM, 0.4, 2.5)
                if liege.faction_key == "loyalists" then
                    for key, v in pairs(c.interest) do
                        c.interest[key] = v - pull / 2
                    end
                elseif liege.faction_key and c.interest[liege.faction_key] then
                    c.interest[liege.faction_key] = c.interest[liege.faction_key] + pull
                elseif liege.faction_key then
                    c.interest[liege.faction_key] = pull
                end
            end
            if c.sway and c.sway.key and c.interest[c.sway.key] then
                c.interest[c.sway.key] = c.interest[c.sway.key] + c.sway.value
            end
            local best, best_v = nil, CONFIG.INTEREST - 1
            for _, key in ipairs(CONFIG.FACTION_ORDER) do
                local v = c.interest[key]
                if v and v > best_v then
                    best, best_v = key, v
                end
            end
            if best and c.minder and not (s.factions[best] and s.factions[best].leader == c.id) then
                best = nil
            end
            c.faction_key = best
            if best then
                table.insert(out[best], c)
            end
        end
    end
    return out
end

local function plot_speed(s)
    local speed = Court.regime(s).plots or 1
    local power = s.office_power or {}
    if (power.VIZIER or 0) < 0 then
        speed = speed * 1.5
    end
    local guard = Court.office_strength(s, "GUARD")
    speed = speed * (1 - 0.3 * guard)
    if s.ops.counter_until and s.week <= s.ops.counter_until then
        speed = speed * 0.5
    end
    if Court.regime(s).fear then
        speed = speed * 0.3
    end
    return M.max(0.1, speed)
end

function Politics.update_factions(s)
    local members = Politics.members(s)
    local total = total_power(s)
    local speed = plot_speed(s)
    local intel = Court.office_strength(s, "INTEL")
    for _, key in ipairs(CONFIG.FACTION_ORDER) do
        local def = CONFIG.FACTIONS[key]
        local f = s.factions[key] or {progress = 0}
        s.factions[key] = f
        local power, leader, best = 0, nil, -1
        local ids = {}
        for _, c in ipairs(members[key]) do
            local p = Court.power(s, c) + (c.influence or 0) * CONFIG.INFLUENCE.FACTION_WEIGHT
            power = power + p
            table.insert(ids, c.id)
            for _, t in ipairs(c.traits) do
                if t == "schemer" then
                    p = p * 1.5
                end
            end
            if p > best then
                leader, best = c.id, p
            end
        end
        f.members, f.leader = ids, leader
        f.strength = M.round(100 * power / total)
        if Court.regime(s).fear then
            f.strength = M.round(f.strength * 0.3)
        end
        if def.threshold then
            local threshold = def.threshold
            if (s.regime_shock or 0) > 0 then
                threshold = threshold / 2
            end
            if key == "independence" and intel < 0 then
                threshold = threshold * 0.7
            end
            if f.strength >= threshold and table.getn(ids) > 0 then
                f.progress = M.min(100, f.progress + (f.strength - threshold + 5) * CONFIG.FACTION_PROGRESS * speed)
            else
                f.progress = M.max(0, f.progress - CONFIG.FACTION_DECAY)
            end
            local watched = leader and s.chars[leader] and s.chars[leader].minder
            if f.progress >= 100 and not Politics.pending(s, "ultimatum", key) and leader and not watched then
                Politics.add_petition(s, {char = leader, kind = "ultimatum", target = key,
                                           weeks = CONFIG.ULTIMATUM_WEEKS})
            end
        end
    end
    s.regime_shock = M.max(0, (s.regime_shock or 0) - 1)
    return members
end

function Politics.heir_of(s, key)
    for _, c in ipairs(serving(s)) do
        if c.heir == key then
            return c
        end
    end
    return nil
end

function Politics.succession_ready(s, key)
    local def = CONFIG.SUCCESSION_EVENTS[key]
    if not def then
        return false, "This succession comes by events, not by choice."
    end
    if not (s.offered and s.offered[def.object]) then
        return false, "Not yet: history has not offered this succession (watch for their message)."
    end
    local disloyal = 0
    for _, fkey in ipairs(CONFIG.DISLOYAL_FACTIONS) do
        disloyal = disloyal + ((s.factions[fkey] and s.factions[fkey].strength) or 0)
    end
    local succ = (s.factions.succession and s.factions.succession.strength) or 0
    local needs = {}
    if disloyal < def.disloyal then
        table.insert(needs, "the disloyal factions together at " .. def.disloyal .. "% (now " .. disloyal .. "%)")
    end
    if succ < def.succession then
        table.insert(needs, "the Succession faction at " .. def.succession .. "% (now " .. succ .. "%)")
    end
    local heir = Politics.heir_of(s, key)
    if heir and heir.faction_key ~= "succession" then
        table.insert(needs, heir.name .. " in the Succession faction")
    end
    if table.getn(needs) > 0 then
        return false, "Needs " .. table.concat(needs, ", ") .. "."
    end
    return true, "Ready: click to set the succession in motion."
end

function Politics.fire_succession(s, key)
    local ok, why = Politics.succession_ready(s, key)
    if not ok then
        return false, why
    end
    local def = CONFIG.SUCCESSION_EVENTS[key]
    local seat = nil
    for _, sector in pairs(s.sectors) do
        if sector.crown and sector.seat then
            seat = sector.seat
        end
    end
    seat = seat or Court.direct_worlds(s)[1]
    for name, _ in pairs(s.world) do
        seat = seat or name
    end
    if not (seat and crossplot) then
        return false, "The succession cannot be set in motion now."
    end
    s.offered[def.object] = nil
    crossplot:publish("PRODUCTION_FINISHED", seat, def.object)
    Court.news(s, "The succession is set in motion: " .. CONFIG.REGIMES[key].leader .. " moves to take power.")
    return true, CONFIG.REGIMES[key].leader .. " moves to take power."
end

function Politics.defect_chance(s, c)
    local chance = (CONFIG.DEFECT_BELOW - c.loyalty) * CONFIG.DEFECT_CHANCE * (Court.regime(s).defect or 1)
    if Court.isolation(s, c) > 0 then
        chance = chance * 1.5
    end
    if c.minder then
        chance = chance * 0.5
    end
    return M.max(0, chance)
end

local function defections(s, members)
    local intel = Court.office_strength(s, "INTEL")
    local warning = CONFIG.DEFECT_WARNING + ((intel > 0.4) and 1 or 0)
    for _, c in ipairs(members.defection) do
        if not c.heir and M.chance(Politics.defect_chance(s, c)) then
            if not c.defect_warned then
                c.defect_warned = s.week
                local target = Court.defect_target(s, c)
                local label = target and Court.faction_label(target) or "a rival"
                if intel >= 0 then
                    Court.news(s, "Intelligence: " .. Court.full_name(c) .. " is talking to " .. label .. ".")
                    Court.alert("Intelligence: " .. Court.full_name(c) .. " is talking to " .. label .. " (Internal Affairs).",
                        "threat")
                end
            elseif s.week >= c.defect_warned + warning then
                Court.defect(s, c)
            end
        end
    end
    for _, c in ipairs(serving(s)) do
        if c.defect_warned and c.loyalty >= 40 then
            c.defect_warned = nil
        end
    end
end

function Politics.risks(s)
    local out = {}
    local intel = Court.office_strength(s, "INTEL")
    local clear = intel > 0.3 or (s.ops.counter_until and s.week <= s.ops.counter_until)
    for _, c in ipairs(political(s)) do
        local level, text, short = 0, nil, nil
        if c.heir then
            local regime = CONFIG.REGIMES[c.heir]
            level = 70 + M.max(0, 40 - c.loyalty) / 2
            text = "plots to take the throne (" .. (regime and regime.title or "?") .. ")"
            short = "claims the throne"
        elseif c.defect_warned then
            level = 90
            local target = Court.defect_target(s, c)
            text = "in contact with " .. (target and Court.faction_label(target) or "a rival")
            short = "in contact!"
        elseif c.loyalty < CONFIG.DEFECT_BELOW and Court.defect_target(s, c) then
            level = 60 + (CONFIG.DEFECT_BELOW - c.loyalty)
            local chance = M.round(Politics.defect_chance(s, c))
            text = clear and ("may defect: " .. chance .. "% a week") or "may defect"
            short = clear and ("defect " .. chance .. "%") or "may defect"
        elseif c.loyalty < 30 and (c.title == "moff" or c.title == "grand_moff") then
            level = 50 + (30 - c.loyalty)
            text, short = "talks of independence", "independence"
        elseif c.loyalty < 40 then
            level = 30 + (40 - c.loyalty)
            text = "disloyal"
        end
        for key, weeks in pairs(s.awol) do
            if c.title == "moff" and c.holds == key then
                level, text, short = 95, "not answering: breaks away in " .. M.weeks(weeks), "AWOL " .. M.weeks(weeks)
            end
        end
        if text then
            table.insert(out, {char = c, text = text, short = short, level = M.min(100, level)})
        end
    end
    table.sort(out, function(a, b)
        if a.level ~= b.level then
            return a.level > b.level
        end
        return a.char.id < b.char.id
    end)
    return out
end

function Politics.pending(s, kind, target)
    for _, p in ipairs(s.petitions) do
        if p.kind == kind and p.target == target then
            return p
        end
    end
    return nil
end

function Politics.add_petition(s, p)
    p.expires = s.week + (p.weeks or CONFIG.PETITION_WEEKS)
    p.weeks = nil
    s.next_petition = (s.next_petition or 0) + 1
    p.id = s.next_petition
    table.insert(s.petitions, p)
    local c = Court.char(s, p.char)
    if c then
        c.petition = p.id
    end
    local who = c and Court.full_name(c) or "A lord"
    local left = M.weeks(M.round(p.expires - s.week))
    if p.kind == "ultimatum" then
        Court.alert("Ultimatum: the " .. CONFIG.FACTIONS[p.target].name .. " faction makes its demands. Answer within "
            .. left .. " (Internal Affairs).", "threat")
    elseif p.kind == "denounce" then
        local target = Court.char(s, p.target)
        Court.alert("Denunciation: " .. table.getn(p.backers or {}) .. " lords demand that "
            .. (target and Court.full_name(target) or "a lord") .. " be stripped and branded a traitor (Internal "
            .. "Affairs).", "threat")
    elseif p.kind == "awol" then
        Court.alert("Crisis: the " .. (s.sectors[p.target] and s.sectors[p.target].name or "a sector")
            .. " stops answering the throne (Internal Affairs).", "threat")
    else
        Court.alert("Petition: " .. who .. " asks the throne for a favour. Answer within " .. left .. " (Internal Affairs).")
    end
end

function Politics.petition_text(s, p)
    local c = Court.char(s, p.char)
    local who = Court.full_name(c)
    if p.kind == "title" then
        local what
        if p.title == "moff" then
            what = "the Moffship of the " .. (s.sectors[p.target] and s.sectors[p.target].name or "?")
        elseif p.title == "grand_moff" then
            what = "the " .. (s.oversectors[p.target] and s.oversectors[p.target].name or "?")
        else
            what = "the governorship of " .. Court.planet_label(p.target)
        end
        return who .. " " .. string.format(CONFIG.PETITIONS.title, what)
    elseif p.kind == "office" then
        return who .. " " .. string.format(CONFIG.PETITIONS.office, Court.office_def(s, p.target).name)
    elseif p.kind == "troops" then
        return who .. " " .. string.format(CONFIG.PETITIONS.troops, CONFIG.TROOPS_CREDITS)
    elseif p.kind == "taxes" then
        return who .. " " .. CONFIG.PETITIONS.taxes
    elseif p.kind == "rival" then
        return who .. " " .. string.format(CONFIG.PETITIONS.rival, Court.full_name(Court.char(s, p.target)))
    elseif p.kind == "dispute" then
        local other = Court.char(s, p.target)
        return who .. " " .. string.format(CONFIG.PETITIONS.dispute, other and Court.full_name(other) or "a rival",
            p.topic or "a petty matter")
    elseif p.kind == "denounce" then
        local target = Court.char(s, p.target)
        local names = {}
        for _, id in ipairs(p.backers or {}) do
            local b = Court.char(s, id)
            if b and b ~= c then
                table.insert(names, b.name)
            end
        end
        local with = (table.getn(names) > 0) and (" and " .. table.concat(names, ", ")) or ""
        return who .. with .. ((with ~= "") and " denounce " or " denounces ") .. (target and Court.full_name(target) or "a lord") .. ": they demand "
            .. "that the throne strip them of power and brand them a traitor."
    elseif p.kind == "ultimatum" then
        return "ULTIMATUM from the " .. CONFIG.FACTIONS[p.target].name .. " faction, led by " .. who .. ": "
            .. CONFIG.FACTIONS[p.target].ultimatum
    elseif p.kind == "awol" then
        return "The " .. (s.sectors[p.target] and s.sectors[p.target].name or "sector") .. " has stopped answering. "
            .. who .. " sends no taxes and ignores your orders."
    end
    return who .. " petitions the throne."
end

function Politics.petition_answers(s, p)
    if p.kind == "ultimatum" then
        if p.target == "independence" then
            return "Concede", "Refuse", "Their sectors leave peacefully as independent states.",
                "Refuse: the faction's lords below " .. CONFIG.BREAKAWAY_LOYALTY .. " loyalty rise in revolt."
        end
        return "Concede", "Refuse", "Members +" .. CONFIG.OPINION.CONCESSION .. " opinion; authority -20, stability -5, "
            .. "minders recalled.", "Refuse: the faction's most disloyal lords may break away."
    elseif p.kind == "dispute" then
        local c, other = Court.char(s, p.char), Court.char(s, p.target)
        local a, b = c and c.name or "them", other and other.name or "the other"
        local function back(name)
            local _, _, last = string.find(name, "(%S+)%s*$")
            return string.sub("Back " .. (last or name), 1, 16)
        end
        return back(a), back(b),
            a .. " +" .. CONFIG.DISPUTE.WON .. " opinion, " .. b .. " " .. CONFIG.DISPUTE.LOST .. ".",
            b .. " +" .. CONFIG.DISPUTE.WON .. " opinion, " .. a .. " " .. CONFIG.DISPUTE.LOST .. "."
    elseif p.kind == "denounce" then
        local X = CONFIG.TERRITORY.DENOUNCE
        return "Investigate", "Dismiss", "The charges stand " .. M.weeks(X.INVESTIGATE) .. ": accusing them of treason "
            .. "is easier (+" .. X.TREASON_BONUS .. "%), treason and arrest need no loyal Director. Backers +" .. X.BACKED
            .. " opinion, the accused " .. X.ACCUSED .. ".", "Backers " .. X.DISMISSED .. " opinion; the charges are dropped."
    elseif p.kind == "awol" then
        return "Bribe", "Threaten", "Pay " .. CONFIG.CRISIS.AWOL_BRIBE .. " credits: they answer again.",
            "Send the fleet's regards: they may come back to heel, or break away at once."
    elseif p.kind == "troops" then
        return "Grant", "Refuse", "Costs " .. CONFIG.TROOPS_CREDITS .. " credits; +" .. CONFIG.OPINION.PETITION_GRANTED
            .. " opinion.", "Refusal: " .. CONFIG.OPINION.REFUSED .. " opinion."
    elseif p.kind == "taxes" then
        return "Grant", "Refuse", "+" .. CONFIG.OPINION.PETITION_GRANTED .. " opinion; stability -3.",
            "Refusal: " .. CONFIG.OPINION.REFUSED .. " opinion."
    end
    return "Grant", "Refuse", "+" .. CONFIG.OPINION.PETITION_GRANTED .. " opinion; rivals resent it.",
        "Refusal: " .. CONFIG.OPINION.REFUSED .. " opinion."
end

local function drop_petition(s, p)
    for i, other in ipairs(s.petitions) do
        if other == p then
            table.remove(s.petitions, i)
            break
        end
    end
    local c = Court.char(s, p.char)
    if c and c.petition == p.id then
        c.petition = nil
    end
end

local function revolt(s, key)
    local f = s.factions[key]
    local rose = 0
    for _, id in ipairs(f and f.members or {}) do
        local c = s.chars[id]
        if c and c.status == "serving" and c.loyalty < CONFIG.BREAKAWAY_LOYALTY then
            if (c.title == "moff" or c.title == "grand_moff" or c.title == "governor") and Court.break_away(s, c, "the "
                    .. CONFIG.FACTIONS[key].name .. " faction's revolt") then
                rose = rose + 1
            end
        end
    end
    if rose == 0 then
        Court.news(s, "The " .. CONFIG.FACTIONS[key].name .. " faction backs down: no lord dares to rise.")
    else
        Court.relief(s)
    end
    f.progress = 20
end

function Politics.answer(s, p, grant, done)
    local c = Court.char(s, p.char)
    if not c or c.status ~= "serving" then
        drop_petition(s, p)
        return true, "The petitioner is gone."
    end
    local O = CONFIG.OPINION
    local empire = Court.player()
    local message
    if p.kind == "ultimatum" then
        local f = s.factions[p.target]
        if grant then
            if p.target == "independence" then
                local n = 0
                for _, id in ipairs(f.members or {}) do
                    local m = s.chars[id]
                    if m and m.status == "serving" and Court.break_away(s, m, "recognised by the throne", true) then
                        n = n + 1
                        m.peaceful = true
                    end
                end
                if n > 0 then
                    Court.relief(s)
                end
                message = n .. " lords leave as independent rulers."
            else
                for _, id in ipairs(f.members or {}) do
                    local m = s.chars[id]
                    if m and m.status == "serving" then
                        Court.opinion(m, "concessions from the throne", O.CONCESSION, 20)
                        m.minder = nil
                    end
                end
                s.authority = M.max(0, s.authority - 20)
                s.stability = M.max(0, s.stability - 5)
                message = "The Moffs have their concessions."
            end
            f.progress = 0
        else
            revolt(s, p.target)
            message = "The ultimatum is refused."
        end
    elseif p.kind == "dispute" then
        local other = Court.char(s, p.target)
        local D = CONFIG.DISPUTE
        local winner, loser = c, other
        if not grant then
            winner, loser = other, c
        end
        if winner and winner.status == "serving" then
            Court.opinion(winner, "the throne took their side against " .. (loser and loser.name or "a rival"), D.WON, D.WEEKS)
        end
        if loser and loser.status == "serving" then
            Court.opinion(loser, "the throne sided with " .. (winner and winner.name or "a rival"), D.LOST, D.WEEKS)
        end
        if winner and loser and M.chance(D.RIVALS) and not Court.is_rival(winner, loser.id) then
            Court.add_tie(loser, winner, "rivals")
        end
        message = "The throne rules for " .. ((winner and winner.name) or "one of them") .. "."
        drop_petition(s, p)
        return true, message
    elseif p.kind == "denounce" then
        local X = CONFIG.TERRITORY.DENOUNCE
        local target = Court.char(s, p.target)
        for _, id in ipairs(p.backers or {}) do
            local b = Court.char(s, id)
            if b and b.status == "serving" then
                if grant then
                    Court.opinion(b, "the throne heard their charges", X.BACKED, 12)
                else
                    Court.opinion(b, "the throne dismissed their charges", X.DISMISSED, 12)
                end
            end
        end
        if grant and target and target.status == "serving" then
            s.denounced = s.denounced or {}
            s.denounced[target.id] = {until_week = s.week + X.INVESTIGATE}
            Court.opinion(target, "denounced before the court", X.ACCUSED, 12)
            message = "The throne looks into the charges against " .. target.name .. "."
        else
            message = "The charges are dismissed."
        end
        drop_petition(s, p)
        return true, message
    elseif p.kind == "awol" then
        local sector = s.sectors[p.target]
        if grant then
            if empire.Get_Credits() < CONFIG.CRISIS.AWOL_BRIBE then
                return false, "Not enough credits."
            end
            empire.Give_Money(-CONFIG.CRISIS.AWOL_BRIBE)
            s.awol[p.target] = nil
            Court.opinion(c, "bought back", 10, 10)
            message = Court.full_name(c) .. " answers again."
        else
            if M.chance(c.loyalty + 30) then
                s.awol[p.target] = nil
                Court.opinion(c, "threatened by the throne", -10, 12)
                message = Court.full_name(c) .. " comes back to heel."
            else
                s.awol[p.target] = nil
                Court.break_away(s, c, "threatened, they rose instead")
                message = "The threat backfires."
            end
        end
    elseif grant then
        if done then
        elseif p.kind == "title" then
            local holder_ok = (p.title == "moff" and s.sectors[p.target]) or (p.title == "grand_moff" and s.oversectors[p.target])
                or (p.title == "governor" and s.world[p.target] ~= nil)
            if not holder_ok then
                drop_petition(s, p)
                return false, "That title no longer exists."
            end
            local old = Court.set_title(s, c, p.title, p.target)
            if old and old ~= c then
                Court.opinion(old, "replaced by " .. c.name, O.FIRED, 16)
            end
        elseif p.kind == "office" then
            local old = Court.char(s, s.offices[p.target])
            for other, id in pairs(s.offices) do
                if id == c.id then
                    s.offices[other] = nil
                end
            end
            s.offices[p.target] = c.id
            local posts = c.posted
            if type(posts) ~= "table" then
                posts = {}
                c.posted = posts
            end
            posts.office = s.week
            if old and old ~= c then
                Court.opinion(old, "lost their office to " .. c.name, O.FIRED, 16)
            end
        elseif p.kind == "troops" then
            if empire.Get_Credits() < CONFIG.TROOPS_CREDITS then
                return false, "Not enough credits."
            end
            empire.Give_Money(-CONFIG.TROOPS_CREDITS)
        elseif p.kind == "taxes" then
            s.stability = M.max(0, s.stability - 3)
        elseif p.kind == "rival" then
            local rival = Court.char(s, p.target)
            if rival and rival.status == "serving" then
                Court.vacate(s, rival)
                for key, id in pairs(s.offices) do
                    if id == rival.id then
                        s.offices[key] = nil
                    end
                end
                Court.opinion(rival, "dismissed at " .. c.name .. "'s demand", O.REVOKED, 30)
            end
        end
        Court.opinion(c, "their petition was granted", O.PETITION_GRANTED, 16)
        for _, other in ipairs(done and {} or serving(s)) do
            if Court.is_rival(other, c.id) then
                Court.opinion(other, "their rival " .. c.name .. " was favoured", O.RIVAL_REWARDED, 12)
            end
        end
        message = "Granted."
    else
        Court.opinion(c, "their petition was refused", O.REFUSED, 12)
        message = "Refused."
    end
    drop_petition(s, p)
    return true, message
end

function Politics.settle_by_appointment(s, kind, title, key, c)
    for _, p in ipairs({unpack(s.petitions)}) do
        local same = (kind == "office" and p.kind == "office" and p.target == key)
            or (kind == "title" and p.kind == "title" and p.title == title and p.target == key)
        if same then
            if c and p.char == c.id then
                Politics.answer(s, p, true, true)
            else
                Politics.answer(s, p, false)
            end
        end
    end
end

local function petitions(s)
    for _, p in ipairs({unpack(s.petitions)}) do
        if s.week > p.expires then
            local c = Court.char(s, p.char)
            if p.kind == "awol" then
                drop_petition(s, p)
            elseif p.kind == "ultimatum" then
                Court.news(s, "The " .. CONFIG.FACTIONS[p.target].name .. " faction's ultimatum went unanswered: it is refused.")
                Court.alert("Ultimatum ignored: the " .. CONFIG.FACTIONS[p.target].name .. " faction takes it as a refusal.",
                    "threat")
                Politics.answer(s, p, false)
            elseif p.kind == "dispute" then
                local other = Court.char(s, p.target)
                for _, v in ipairs({c, other}) do
                    if v and v.status == "serving" then
                        Court.opinion(v, "the throne would not settle their quarrel", CONFIG.DISPUTE.IGNORED, 8)
                    end
                end
                Court.news(s, "The quarrel over " .. (p.topic or "a petty matter") .. " goes unsettled; both lords are piqued.")
                drop_petition(s, p)
            elseif c and c.status == "serving" then
                Court.news(s, Court.full_name(c) .. "'s petition went unanswered: they take it as a refusal.")
                Politics.answer(s, p, false)
            else
                drop_petition(s, p)
            end
        end
    end
    if Court.regime(s).fear then
        return
    end
    local budget, roll = 1, M.random(1, 100)
    for n, share in ipairs(CONFIG.PETITION_COUNT) do
        roll = roll - share
        if roll <= 0 then
            budget = n
            break
        end
    end
    local added = 0
    for _, c in ipairs(serving(s)) do
        if table.getn(s.petitions) >= CONFIG.PETITION_MAX or added >= budget then
            break
        end
        if not c.petition and not c.heir and not c.leads and c.influence >= CONFIG.PETITION_COST
                and M.chance(CONFIG.PETITION_CHANCE * c.ambition / 50) then
            local options = {}
            local others = {}
            for _, v in ipairs(serving(s)) do
                if v ~= c and not v.leads and (v.title ~= "courtier" or Court.office_of(s, v) or v.fleet_rank) then
                    local w = (Court.is_rival(c, v.id) and 4 or 1) * ((v.title == c.title) and 2 or 1)
                    table.insert(others, {v = v, w = w})
                end
            end
            if table.getn(others) > 0 then
                local total = 0
                for _, o in ipairs(others) do
                    total = total + o.w
                end
                local roll = M.random(1, 10000) / 10000 * total
                for _, o in ipairs(others) do
                    roll = roll - o.w
                    if roll <= 0 then
                        table.insert(options, {kind = "dispute", target = o.v.id, topic = M.pick(CONFIG.DISPUTES)})
                        break
                    end
                end
            end
            if c.title == "courtier" or c.title == "governor" then
                for _, sector in ipairs(Court.sector_list(s)) do
                    if not sector.holder and not sector.crown and table.getn(sector.worlds) > 0 then
                        table.insert(options, {kind = "title", title = "moff", target = sector.key})
                    end
                end
                if c.title == "courtier" then
                    for name, key in pairs(s.world) do
                        if not s.governor[name] and s.sectors[key] and s.sectors[key].seat ~= name then
                            table.insert(options, {kind = "title", title = "governor", target = name})
                            break
                        end
                    end
                end
            elseif c.title == "moff" then
                for key, over in pairs(s.oversectors) do
                    if not over.holder then
                        table.insert(options, {kind = "title", title = "grand_moff", target = key})
                    end
                end
            end
            for _, key in ipairs(CONFIG.OFFICE_ORDER) do
                local holder = Court.char(s, s.offices[key])
                if not Court.office_of(s, c) and (not holder or (Court.is_rival(c, holder.id) and not holder.heir
                        and not holder.leads)) then
                    table.insert(options, {kind = "office", target = key})
                end
            end
            if table.getn(Court.worlds_of(s, c)) > 0 then
                table.insert(options, {kind = "troops"})
                if c.title == "moff" or c.title == "grand_moff" then
                    table.insert(options, {kind = "taxes"})
                end
            end
            for _, r in ipairs(Court.ties(s, c, "rivals")) do
                if r.status == "serving" and not r.heir and not r.leads then
                    for _, h in ipairs(Court.holdings(s, r)) do
                        if Court.RANK[h.title] >= (Court.RANK[c.title] or 0)
                                and (h.title ~= "grand_moff" or c.title == "moff") then
                            table.insert(options, {kind = "title", title = h.title, target = h.key})
                        end
                    end
                end
            end
            local rival = Court.ties(s, c, "rivals")[1]
            if rival and c.ambition > 60 and not c.loyalist and not rival.heir and not rival.leads
                    and (rival.title ~= "courtier" or Court.office_of(s, rival)) then
                table.insert(options, {kind = "rival", target = rival.id})
            end
            local kinds, total = {}, 0
            for _, o in ipairs(options) do
                if not kinds[o.kind] then
                    kinds[o.kind] = {}
                    total = total + (CONFIG.PETITION_WEIGHTS[o.kind] or 1)
                end
                table.insert(kinds[o.kind], o)
            end
            local choice = nil
            local roll = M.random(1, 10000) / 10000 * total
            for kind, list in pairs(kinds) do
                if not choice then
                    roll = roll - (CONFIG.PETITION_WEIGHTS[kind] or 1)
                    if roll <= 0 then
                        choice = M.pick(list)
                    end
                end
            end
            if choice then
                choice.char = c.id
                c.influence = c.influence - CONFIG.PETITION_COST
                Politics.add_petition(s, choice)
                added = added + 1
            end
        end
    end
end

local function border_world(s, enemy)
    for name, _ in pairs(s.world) do
        for _, other in ipairs(Court.lanes(name)) do
            if Court.owner_of(s, other) == enemy then
                return name, other
            end
        end
    end
    return nil
end

local function crisis(s)
    if (s.crisis_cd or 0) > 0 then
        s.crisis_cd = s.crisis_cd - 1
        return
    end
    local chance = M.max(0, 60 - s.stability) * CONFIG.CRISIS.CHANCE * (Court.regime(s).crisis or 1)
    if not M.chance(chance) then
        return
    end
    s.crisis_cd = CONFIG.CRISIS.COOLDOWN
    local roll = M.random(1, 5)
    if roll == 1 or roll == 5 then
        local worst
        for _, c in ipairs(serving(s, true)) do
            if c.title == "moff" and not c.loyalist and not s.awol[c.holds] and c.loyalty < 50
                    and (not worst or c.loyalty < worst.loyalty) then
                worst = c
            end
        end
        if worst then
            s.awol[worst.holds] = CONFIG.CRISIS.AWOL_WEEKS
            Politics.add_petition(s, {char = worst.id, kind = "awol", target = worst.holds, weeks = CONFIG.CRISIS.AWOL_WEEKS})
            Court.news(s, "Crisis: the " .. s.sectors[worst.holds].name .. " stops answering the throne.")
            return
        end
    end
    if roll == 2 then
        local candidates = {}
        for name, _ in pairs(s.isolated) do
            table.insert(candidates, name)
        end
        if table.getn(candidates) == 0 then
            for _, c in ipairs(serving(s, true)) do
                if c.loyalty < 40 then
                    for _, name in ipairs(Court.worlds_of(s, c)) do
                        if name ~= s.capital then
                            table.insert(candidates, name)
                        end
                    end
                end
            end
        end
        local unstable = {}
        for _, w in ipairs(candidates) do
            local inf = Court.world_influence(s, w)
            if inf and inf < CONFIG.REVOLT_BELOW and (not DIPLOMACY_CAN_RISE or DIPLOMACY_CAN_RISE(w)) then
                table.insert(unstable, w)
            end
        end
        local name = M.pick(unstable)
        local planet = name and FindPlanet(name)
        if planet then
            s.rebel_pending[name] = true
            DIPLOMACY_REVOLTS = DIPLOMACY_REVOLTS or {}
            DIPLOMACY_REVOLTS[string.upper(name)] = {kind = "REVOLT", time = GetCurrentTime()}
            if DIPLOMACY_REBELLION and is_human() then
                pcall(DIPLOMACY_REBELLION, planet)
            else
                (DIPLOMACY_REVOLT_POPULATE or ChangePlanetOwnerAndPopulate)(planet,
                    require("eawx-plugins/imperial-court/CourtIntel").rising_owner(name), 3000)
            end
            Court.news(s, "Crisis: " .. Court.planet_label(name) .. " rises against Imperial rule.")
            Court.alert("Crisis: " .. Court.planet_label(name) .. " rises against Imperial rule.", "threat")
            return
        end
    end
    if roll == 3 then
        local mine, theirs = border_world(s, "REBEL")
        if mine then
            local sector = s.sectors[s.world[mine] or ""]
            local lord = sector and Court.char(s, sector.holder)
            if lord then
                Court.opinion(lord, "left exposed to the New Republic", -5, 8)
            end
            Court.news(s, "Crisis: Intelligence warns of New Republic fleets gathering at " .. Court.planet_label(theirs)
                .. ", facing " .. Court.planet_label(mine) .. ".")
            Court.alert("Intelligence: New Republic fleets gather near " .. Court.planet_label(mine) .. ".", "threat")
            return
        end
    end
    if roll == 4 or s.stability < CONFIG.CRISIS.PROCLAIM_BELOW then
        if s.stability < CONFIG.CRISIS.PROCLAIM_BELOW then
            local best, best_p = nil, 0
            for _, c in ipairs(serving(s, true)) do
                local p = Court.power(s, c)
                if (c.title == "moff" or c.title == "grand_moff") and c.loyalty < 35 and p > best_p then
                    best, best_p = c, p
                end
            end
            if best then
                Court.break_away(s, best, "proclaimed themselves a warlord")
                return
            end
        end
        local worst
        for _, c in ipairs(serving(s, true)) do
            if not c.loyalist and c.loyalty < 50 and (not worst or c.loyalty < worst.loyalty) and Court.defect_target(s, c) then
                worst = c
            end
        end
        if worst then
            Court.opinion(worst, "courted by a rival power", -10, 8)
            Court.news(s, "Crisis: a rival power courts " .. Court.full_name(worst) .. ".")
        end
    end
end

local function regime_event(s)
    local event = CONFIG.REGIME_EVENTS[s.regime]
    if not event or not M.chance(event.chance) then
        return
    end
    local lords = {}
    for _, c in ipairs(serving(s, true)) do
        if not c.loyalist and not c.leads and not c.heir then
            table.insert(lords, c)
        end
    end
    if table.getn(lords) == 0 then
        return
    end
    table.sort(lords, function(a, b)
        return a.loyalty < b.loyalty
    end)
    if event.kind == "purge" then
        local victim = lords[1]
        if victim.loyalty < 45 then
            Court.remove(s, victim, "dead", "vanished in Isard's purges")
            for _, c in ipairs(serving(s, true)) do
                Court.opinion(c, "the purges", -3, 10)
            end
        end
    elseif event.kind == "infighting" then
        local a, b = M.pick(lords), M.pick(lords)
        if a and b and a ~= b then
            Court.add_tie(a, b, "rivals")
            Court.opinion(a, "feuding with " .. b.name, -6, 10)
            Court.opinion(b, "feuding with " .. a.name, -6, 10)
            Court.news(s, Court.full_name(a) .. " and " .. Court.full_name(b) .. " fall out over the spoils of power.")
        end
    elseif event.kind == "old_guard" then
        for _, c in ipairs(lords) do
            if Court.has_trait(c, "xenophobe") then
                Court.opinion(c, "an alien on the throne", -6, 10)
            end
        end
        Court.news(s, "The old guard mutters against an alien Grand Admiral.")
    elseif event.kind == "guard_dissent" then
        local guard = Court.char(s, s.offices.GUARD)
        if guard then
            Court.opinion(guard, "Royal Guard dissent", -10, 10)
        end
        local target = M.pick(lords)
        if target and M.chance(30) then
            Court.remove(s, target, "dead", "was cut down by a vengeful Royal Guardsman")
        else
            Court.news(s, "Royal Guardsmen whisper that Jax betrayed the Emperor.")
        end
    elseif event.kind == "coup" then
        local total, n = 0, 0
        for _, c in ipairs(lords) do
            if c.title == "moff" then
                total, n = total + c.loyalty, n + 1
            end
        end
        if n > 0 and total / n < 40 then
            for _, c in ipairs(lords) do
                if c.title == "moff" and c.loyalty < 30 then
                    Court.break_away(s, c, "a Moff coup against Daala")
                    break
                end
            end
        else
            Court.news(s, "The Moffs plot against Daala, but none dares to strike.")
        end
    elseif event.kind == "council_intrigue" then
        local target = M.pick(lords)
        if target and target.title == "moff" then
            Court.opinion(target, "Moff Council intrigue", -8, 10)
            Court.news(s, "Intrigue on Bastion: " .. Court.full_name(target) .. " is drawn into the Moff Council's schemes.")
        end
    end
end

local function awol_countdown(s)
    for key, weeks in pairs(s.awol) do
        local sector = s.sectors[key]
        local c = sector and Court.char(s, sector.holder)
        if not c or c.status ~= "serving" then
            s.awol[key] = nil
        elseif weeks <= 1 then
            s.awol[key] = nil
            local p = Politics.pending(s, "awol", key)
            if p then
                drop_petition(s, p)
            end
            Court.break_away(s, c, "never answered the throne again")
        else
            s.awol[key] = weeks - 1
        end
    end
end

function Politics.warlords(s)
    local data = Court.warlord_data()
    if not data then
        return {}
    end
    local by_faction = {}
    for _, warlord in ipairs(data.WARLORDS) do
        by_faction[warlord.faction] = warlord
    end
    local out, seen = {}, {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local owner = string.upper(planet.Get_Owner().Get_Faction_Name())
        local warlord = by_faction[owner]
        if warlord then
            if not seen[owner] then
                seen[owner] = {faction = owner, key = warlord.key, display = warlord.display, worlds = {},
                               leaders = warlord.leaders}
                table.insert(out, seen[owner])
            end
            table.insert(seen[owner].worlds, Court.name_of(planet))
        end
    end
    table.sort(out, function(a, b)
        return a.display < b.display
    end)
    return out
end

function Politics.bar(w)
    return CONFIG.INTEGRATION.BAR_BASE + CONFIG.INTEGRATION.BAR_PER_WORLD * table.getn(w.worlds)
end

local function borders(w, faction, s)
    for _, name in ipairs(w.worlds) do
        for _, other in ipairs(Court.lanes(name)) do
            if Court.owner_of(s or IMPERIAL_COURT, other) == faction then
                return true
            end
        end
    end
    return false
end
Politics.borders = borders

local function integrate(s, w, faction)
    local player = Find_Player(faction)
    local planets = {}
    for _, name in ipairs(w.worlds) do
        local planet = FindPlanet(name)
        if planet then
            table.insert(planets, planet)
        end
    end
    ChangePlanetOwnerAndReplace(planets, player, 3)
    s.integration[w.faction] = nil
    return table.getn(planets)
end

local function race(s)
    local I = CONFIG.INTEGRATION
    local legit = Court.legitimacy() or {}
    local mult = Court.regime(s).integration or 1
    for _, w in ipairs(Politics.warlords(s)) do
        local rec = s.integration[w.faction] or {empire = 0, rivals = {}}
        s.integration[w.faction] = rec
        local share = legit[CONFIG.FACTION] and legit[CONFIG.FACTION].share or 0
        local gain = I.WEEK_BASE + share / 10 + (borders(w, CONFIG.FACTION, s) and I.BORDER or 0)
        rec.empire = M.min(100, rec.empire + gain * mult)
        for _, rival in ipairs(CONFIG.RIVALS) do
            local entry = legit[rival]
            if entry and Find_Player(rival) then
                local g = (I.WEEK_BASE + entry.share / 10 + (borders(w, rival, s) and I.BORDER or 0)) * I.RIVAL_RATE
                rec.rivals[rival] = M.min(100, (rec.rivals[rival] or 0) + g)
                if rec.rivals[rival] >= 100 and entry.share >= Politics.bar(w) then
                    local n = integrate(s, w, rival)
                    local label = Court.faction_label(rival)
                    Court.news(s, w.display .. " swears fealty to " .. label .. " (" .. n .. " worlds). The race is lost.")
                    break
                end
            end
        end
        if not is_human() and s.integration[w.faction] and rec.empire >= I.FEALTY_AT and share >= Politics.bar(w) then
            Politics.fealty(s, w.faction, true)
        end
    end
end

function Politics.fealty(s, faction, free)
    local w
    for _, entry in ipairs(Politics.warlords(s)) do
        if entry.faction == faction then
            w = entry
        end
    end
    if not w then
        return false, "That warlord holds no worlds."
    end
    local rec = s.integration[faction] or {empire = 0}
    local share = Court.legitimacy_share()
    if rec.empire < CONFIG.INTEGRATION.FEALTY_AT then
        return false, "Influence " .. M.round(rec.empire) .. "%: needs " .. CONFIG.INTEGRATION.FEALTY_AT .. "%."
    end
    if share < Politics.bar(w) then
        return false, "Legitimacy " .. M.round(share) .. "%: needs " .. Politics.bar(w) .. "%."
    end
    if not free then
        if s.authority < CONFIG.ACTIONS.FEALTY then
            return false, "Needs " .. CONFIG.ACTIONS.FEALTY .. " authority."
        end
        s.authority = s.authority - CONFIG.ACTIONS.FEALTY
    end
    local worlds = {}
    for _, name in ipairs(w.worlds) do
        table.insert(worlds, name)
    end
    local n = integrate(s, w, CONFIG.FACTION)
    local key = "W_" .. w.key
    s.sectors[key] = s.sectors[key] or {key = key, name = w.display, worlds = {}, warlord = w.key, lore = true}
    s.sectors[key].seat = worlds[1]
    for _, name in ipairs(worlds) do
        s.world[name] = key
    end
    Court.index_worlds(s)
    local lore
    for _, unit in ipairs(w.leaders or {}) do
        lore = lore or Court.LORE_BY_UNIT[unit]
    end
    local c
    if lore and s.lore_used[lore] and s.chars[s.lore_used[lore]] then
        c = s.chars[s.lore_used[lore]]
        c.status = "serving"
    else
        c = Court.new_char(s, (lore and not s.lore_used[lore]) and lore or nil, "moff")
    end
    table.insert(c.traits, "integrated")
    Court.set_title(s, c, "moff", key)
    Court.settle_loyalty(s, c)
    Court.add_legitimacy(CONFIG.FACTION, CONFIG.LEGITIMACY.FEALTY)
    Court.news(s, w.display .. " swears fealty to the Empire: " .. n .. " worlds and " .. Court.full_name(c) .. " join the court.")
    if is_human() and StoryUtil then
        StoryUtil.ShowScreenText(w.display .. " swears fealty to the Empire.", 15, nil, {r = 255, g = 220, b = 120})
    end
    return true, w.display .. " joins the Empire."
end

local function ai_court(s)
    for _, p in ipairs({unpack(s.petitions)}) do
        local c = Court.char(s, p.char)
        local f = (p.kind == "ultimatum") and s.factions[p.target]
        local grant
        if p.kind == "ultimatum" then
            grant = p.target ~= "independence" and (f.strength or 0) > 30
        elseif p.kind == "awol" then
            grant = Court.player().Get_Credits() >= CONFIG.CRISIS.AWOL_BRIBE
        else
            grant = c and c.loyalty < CONFIG.AI.GRANT_BELOW and p.kind ~= "rival"
        end
        Politics.answer(s, p, grant)
    end
    local Actions = require("eawx-plugins/imperial-court/CourtActions")
    local lords = serving(s, true)
    table.sort(lords, function(a, b)
        return a.loyalty < b.loyalty
    end)
    local empire = Court.player()
    for _, c in ipairs(lords) do
        if c.loyalty >= CONFIG.AI.HONOUR_BELOW then
            break
        end
        if s.authority >= Actions.cost(s, CONFIG.ACTIONS.HONOUR) + 10 then
            Actions.honour(s, c)
        end
        if c.loyalty < CONFIG.AI.BRIBE_BELOW and empire.Get_Credits() > CONFIG.AI.BRIBE_CREDITS_ABOVE then
            Actions.bribe(s, c)
        end
        if c.defect_warned and not c.minder and s.authority >= CONFIG.ACTIONS.MINDER + 10 then
            Actions.minder(s, c)
        end
    end
    for _, sector in ipairs(Court.sector_list(s)) do
        if not sector.holder and not sector.crown and table.getn(sector.worlds) > 0 then
            local best
            for _, c in ipairs(serving(s)) do
                if c.title == "courtier" and not Court.office_of(s, c) and not c.traitor
                        and (not best or c.loyalty > best.loyalty) then
                    best = c
                end
            end
            if not best and not Actions.raise_blocked(s) then
                local _, _, raised = Actions.raise_officer(s)
                best = raised
            end
            if best then
                Court.set_title(s, best, "moff", sector.key)
            end
        end
    end
    for _, key in ipairs(CONFIG.OFFICE_ORDER) do
        if not s.offices[key] then
            for _, c in ipairs(serving(s)) do
                if c.title == "courtier" and not Court.office_of(s, c) and not c.traitor and c.loyalty >= 50 then
                    s.offices[key] = c.id
                    Court.fleet_office_rank(s)
                    break
                end
            end
        end
    end
end

function Politics.week(s)
    local members = Politics.update_factions(s)
    defections(s, members)
    awol_countdown(s)
    petitions(s)
    crisis(s)
    regime_event(s)
    if not s.no_race then
        race(s)
    end
    if not is_human() then
        ai_court(s)
    end
end

return Politics
