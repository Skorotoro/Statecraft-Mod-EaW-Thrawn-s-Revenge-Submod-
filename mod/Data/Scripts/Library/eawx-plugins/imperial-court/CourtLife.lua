local CONFIG = require("eawx-plugins/imperial-court/CourtConfig")
local M = require("eawx-plugins/imperial-court/CourtMath")
local Court = require("eawx-plugins/imperial-court/Court")

local Life = {}

local EVENTS = {
    rivals = {
        peer = {
            "{a} accuses {b} of hoarding garrison troops {place}.",
            "{a} and {b} quarrel over who escorts the tithe convoys {place}.",
            "{a} mocks {b}'s provincial manners at a reception {place}.",
            "{a} lures away {b}'s best tax collectors with better pay.",
            "{a} reports {b}'s smuggling contacts to Imperial Intelligence.",
            "{a} and {b} both claim the same shipyard contracts {place}.",
            "{a} blames {b} for the pirates raiding the trade lanes {place}.",
            "A duel of insults between {a} and {b} becomes the gossip of the court.",
            "{a} blocks {b}'s request for new TIE squadrons in committee.",
            "{a} seizes a freighter bound for {b}'s world, citing irregular papers.",
            "{a} and {b} each claim credit for crushing the same insurgent cell.",
            "{a} snubs {b} at the Empire Day parade {place}.",
        },
        down = {
            "{a} publicly rebukes {b} for missing their quotas {place}.",
            "{a} raises the levies on {b}'s world and keeps the difference.",
            "{a} hands {b}'s garrison to a favourite without a word.",
            "{a} sends an auditor to go through {b}'s ledgers line by line.",
            "{a} passes over {b} for the command of the sector fleet.",
            "{a} has {b}'s aide arrested for sedition, without proof.",
        },
        up = {
            "{a} complains to the court that {b} cannot keep order {place}.",
            "{a} withholds a share of the tithe from {b}, pleading poor harvests.",
            "{a} is caught writing to the throne behind {b}'s back.",
            "{a} ignores {b}'s summons to the sector capital.",
            "{a} courts {b}'s officers, as if they were already in charge {place}.",
            "{a} lets {b}'s inspectors wait a week at the spaceport.",
        },
    },
    friends = {
        peer = {
            "{a} and {b} share intelligence on the rebels {place} and corner a cell together.",
            "{a} lends {b} a garrison battalion through a hard winter.",
            "{a} and {b} sign a trade compact between their worlds.",
            "{a} stands by {b} when their loyalty is questioned at court.",
            "{a} and {b} spend a long evening over Corellian brandy and old war stories.",
            "{a} warns {b} of an Intelligence inquiry in time.",
            "{a} and {b} arrange a marriage between their families.",
            "{a} covers {b}'s shortfall in the sector tithe.",
        },
        down = {
            "{a} praises {b}'s administration in a report to the throne.",
            "{a} grants {b} a share of the captured spoils {place}.",
            "{a} sends {b} a squadron of TIE fighters to hold the line.",
            "{a} names {b} to the honour guard at the sector's Empire Day review.",
            "{a} shields {b} from a corruption inquiry.",
        },
        up = {
            "{a} delivers the tithe early and in full to {b}.",
            "{a} uncovers a plot against {b} and foils it.",
            "{a} hosts {b} lavishly on their tour of inspection {place}.",
            "{a} backs {b}'s plans {place} before the court.",
            "{a} sends troops to put down a riot on {b}'s seat.",
        },
    },
    warmer = {
        "{a} reminds {b} what the Empire has given them both.",
        "{a} talks {b} out of a rash letter to the warlords.",
        "{a} persuades {b} that the throne still rewards its faithful.",
    },
    colder = {
        "{a} tells {b} the throne will discard them both when it suits it.",
        "{a} shows {b} proof of the court's broken promises.",
        "{a} convinces {b} that the throne cannot protect them for long.",
    },
    faction = {
        "{a} brings {b} into the {faction} faction over a private dinner.",
        "{a} wins {b} over to the {faction} cause.",
        "{a} persuades {b} that the {faction} faction is their best hope.",
        "{a} shows {b} the {faction} faction's letters, and {b} signs.",
        "{a} promises {b} a place among the {faction} faction's leaders.",
    },
    introduce = {
        "{a} introduces {b} to {c}; the two become fast friends.",
        "{a} brings {b} and {c} together over a hunt {place}.",
        "{a} vouches for {c} to {b}, and the two strike up a friendship.",
        "{a} seats {b} beside {c} at a state dinner; they leave as friends.",
        "{a} persuades {b} that {c} is a lord worth knowing.",
    },
    turn = {
        "{a} turns {b} against {c} with a well-placed rumour.",
        "{a} convinces {b} that {c} is plotting against them.",
        "{a} shows {b} proof that {c} spoke ill of them at court.",
        "{a} whispers to {b} that {c} covets their post.",
        "{a} sets {b} and {c} at each other's throats over a shipyard contract.",
    },
}
Life.EVENTS = EVENTS

local function fill(text, s, a, b, place, faction, c)
    text = string.gsub(text, "{a}", Court.full_name(a))
    text = string.gsub(text, "{b}", Court.full_name(b))
    if c then
        text = string.gsub(text, "{c}", Court.full_name(c))
    end
    text = string.gsub(text, "{place}", place and ("in the " .. place) or "at court")
    text = string.gsub(text, "{faction}", faction or "")
    text = string.gsub(text, "in the the ", "in the ")
    return text
end

local function sector_of(s, c)
    if c.title == "moff" then
        return s.sectors[c.holds or ""]
    elseif c.title == "governor" then
        return s.sectors[s.world[c.holds or ""] or ""]
    end
    return nil
end

local function partners(s, c, serving)
    local L = CONFIG.LIFE
    local list, total = {}, 0
    local mine = sector_of(s, c)
    local liege = Court.liege(s, c)
    for _, v in ipairs(serving) do
        if v ~= c then
            local w = L.OTHER
            local rel = "peer"
            if liege == v then
                w, rel = L.LIEGE, "up"
            elseif Court.liege(s, v) == c then
                w, rel = L.LIEGE, "down"
            elseif c.title == "governor" and v.title == "governor" and mine and sector_of(s, v) == mine then
                w = L.SECTOR
            elseif c.title == v.title and c.title ~= "courtier" then
                w = L.PEER
            end
            total = total + w
            table.insert(list, {char = v, weight = w, rel = rel})
        end
    end
    return list, total
end

local function pick_partner(s, c, serving)
    local list, total = partners(s, c, serving)
    if total <= 0 then
        return nil
    end
    local roll = M.random(1, 1000) / 1000 * total
    for _, p in ipairs(list) do
        roll = roll - p.weight
        if roll <= 0 then
            return p
        end
    end
    return list[table.getn(list)]
end

local KIND_ORDER = {"faction", "introduce", "turn", "sway", "friends", "rivals"}

local function choose_kind(s, a, b)
    local w = {}
    for kind, value in pairs(CONFIG.LIFE.KINDS) do
        w[kind] = value
    end
    if Court.is_friend(a, b.id) then
        w.sway, w.friends, w.rivals = w.sway * 2, w.friends * 1.5, w.rivals * 0.3
    elseif Court.is_rival(a, b.id) then
        w.rivals, w.friends, w.introduce, w.faction = w.rivals * 2, w.friends * 0.4, w.introduce * 0.3, w.faction * 0.3
    end
    for _, c in ipairs({a, b}) do
        if Court.has_trait(c, "ambitious") or Court.has_trait(c, "schemer") then
            w.rivals, w.turn = w.rivals * 1.2, w.turn * 1.3
        end
        if Court.has_trait(c, "loyalist") or Court.has_trait(c, "administrator") then
            w.rivals, w.friends = w.rivals * 0.8, w.friends * 1.2
        end
    end
    if not a.faction_key or a.faction_key == "loyalists" or a.faction_key == b.faction_key then
        w.faction = 0
    end
    if a.faction_key and a.faction_key == b.faction_key then
        w.rivals = w.rivals * 0.6
    end
    local total = 0
    for _, kind in ipairs(KIND_ORDER) do
        total = total + (w[kind] or 0)
    end
    local roll = M.random(1, 1000) / 1000 * total
    for _, kind in ipairs(KIND_ORDER) do
        roll = roll - (w[kind] or 0)
        if roll <= 0 then
            return kind
        end
    end
    return "rivals"
end

local function third(s, a, b, kind, serving)
    local tie = (kind == "introduce") and "friends" or "rivals"
    local pool = {}
    for _, c in ipairs(Court.ties(s, a, tie)) do
        if c ~= a and c ~= b and not Court.has_tie(b, c.id, tie) then
            table.insert(pool, c)
        end
    end
    if table.getn(pool) == 0 then
        for _, c in ipairs(serving) do
            if c ~= a and c ~= b and not Court.has_tie(b, c.id, tie)
                    and (kind == "turn" or not Court.is_rival(a, c.id)) then
                table.insert(pool, c)
            end
        end
    end
    if table.getn(pool) == 0 then
        return nil
    end
    return pool[M.random(1, table.getn(pool))]
end

local function sway(s, a, b, place)
    local L = CONFIG.LIFE
    local ia, ib = M.max(1, a.influence or 0), M.max(1, b.influence or 0)
    if M.random(1, 1000) > 1000 * ia / (ia + ib) then
        a, b, ia = b, a, ib
    end
    local pull = M.clamp(ia / CONFIG.INFLUENCE.PULL_FROM, 0.5, 2)
    local gap = a.loyalty - b.loyalty
    if M.abs(gap) < 8 then
        return nil
    end
    local value = M.clamp(M.round(gap * L.SWAY_SHARE * pull), -L.SWAY_CAP, L.SWAY_CAP)
    Court.opinion(b, "talked round by " .. a.name, value, L.SWAY_WEEKS)
    return fill(M.pick((gap > 0) and EVENTS.warmer or EVENTS.colder), s, a, b, place)
end

local function recruit(s, a, b, place)
    if not a.faction_key or a.faction_key == "loyalists" or a.faction_key == b.faction_key then
        return nil
    end
    local L = CONFIG.LIFE
    local pull = M.clamp(M.max(1, a.influence or 0) / CONFIG.INFLUENCE.PULL_FROM, 0.5, 2)
    local def = CONFIG.FACTIONS[a.faction_key]
    b.sway = {key = a.faction_key, value = M.round(L.SWAY_FACTION * pull), until_week = s.week + L.SWAY_WEEKS}
    return fill(M.pick(EVENTS.faction), s, a, b, place, def and def.name or "")
end

local function events_this_week()
    local L = CONFIG.LIFE
    if not M.chance(L.WEEK_CHANCE) then
        return 0
    end
    local roll = M.random(1, 100)
    for n, share in ipairs(L.COUNT) do
        roll = roll - share
        if roll <= 0 then
            return n
        end
    end
    return 1
end

local function pick_actor(serving)
    local L = CONFIG.LIFE
    local total, w = 0, {}
    for i, a in ipairs(serving) do
        w[i] = ((a.title == "governor") and L.GOVERNOR or 1) * M.clamp(0.5 + (a.influence or 0) / 100, 0.5, 2)
        total = total + w[i]
    end
    local roll = M.random(1, 1000) / 1000 * total
    for i, a in ipairs(serving) do
        roll = roll - w[i]
        if roll <= 0 then
            return a
        end
    end
    return serving[table.getn(serving)]
end

function Life.week(s)
    local L = CONFIG.LIFE
    local serving = {}
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if c.status == "serving" then
            table.insert(serving, c)
        end
        if c.sway and c.sway.until_week and s.week > c.sway.until_week then
            c.sway = nil
        end
    end
    if table.getn(serving) < 2 then
        return
    end
    local wanted = events_this_week() - ((s.tie_news_week == s.week) and 1 or 0)
    local events, tries = 0, 0
    while events < wanted and tries < wanted * 4 do
        tries = tries + 1
        local a = pick_actor(serving)
        local p = pick_partner(s, a, serving)
        if p then
            local b = p.char
            local sector = sector_of(s, a) or sector_of(s, b)
            local place = sector and sector.name or nil
            local kind = choose_kind(s, a, b)
            local text
            if kind == "sway" then
                text = sway(s, a, b, place)
            elseif kind == "faction" then
                text = recruit(s, a, b, place)
            elseif kind == "introduce" or kind == "turn" then
                local c = third(s, a, b, kind, serving)
                if c and Court.add_tie(b, c, (kind == "introduce") and "friends" or "rivals") then
                    text = fill(M.pick(EVENTS[kind]), s, a, b, place, nil, c)
                end
            else
                local list = EVENTS[kind][p.rel] or EVENTS[kind].peer
                if Court.add_tie(a, b, kind) or kind == "rivals" then
                    text = fill(M.pick(list), s, a, b, place)
                end
                if p.rel == "down" then
                    Court.opinion(b, (kind == "rivals") and ("mistreated by " .. a.name) or ("favoured by " .. a.name),
                        (kind == "rivals") and -L.VASSAL or L.VASSAL, 10)
                end
            end
            if text then
                events = events + 1
                Court.news(s, text)
            end
        end
    end
end

return Life
