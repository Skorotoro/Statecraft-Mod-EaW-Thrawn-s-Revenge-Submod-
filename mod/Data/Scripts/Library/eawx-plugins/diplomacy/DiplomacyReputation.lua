local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")

local Reputation = {}

Reputation.WORDS = {"Reliable", "Unscrupulous", "Treacherous"}
Reputation.COLORS = {{r = 150, g = 230, b = 150}, {r = 255, g = 220, b = 110}, {r = 255, g = 120, b = 100}}

local state = {}
local human = nil

function Reputation.set_human(faction)
    human = string.upper(faction)
    if state[human] then
        state[human].base = 1
    end
end

local function rules()
    return CONFIG.REPUTATION
end

local function weeks(n)
    return n * CONFIG.WEEK_SECONDS
end

local function start_rank(faction)
    local r = rules()
    local ok, year = pcall(GlobalValue.Get, "GALACTIC_YEAR")
    year = ok and year or nil
    local by_year = year and r.BY_YEAR[year]
    if by_year and by_year[faction] then
        return by_year[faction]
    end
    if r.START[faction] then
        return r.START[faction]
    end
    if Diplomacy and Diplomacy.warlord_factions and Diplomacy.warlord_factions()[faction] then
        return r.WARLORDS_START
    end
    return 1
end

local function entry(faction)
    faction = string.upper(faction)
    local e = state[faction]
    if not e then
        local rank = start_rank(faction)
        e = {rank = rank, base = (faction == human) and 1 or rank, since = GetCurrentTime(), causes = {}}
        state[faction] = e
    end
    return e
end

function Reputation.rank(faction)
    return entry(faction).rank
end

function Reputation.word(faction)
    return Reputation.WORDS[Reputation.rank(faction)]
end

function Reputation.drop(faction, ranks, cause)
    local e = entry(faction)
    local before = e.rank
    e.rank = M.min(3, e.rank + (ranks or 1))
    e.since = GetCurrentTime()
    table.insert(e.causes, {text = cause or "bad faith", time = GetCurrentTime()})
    while table.getn(e.causes) > rules().CAUSES do
        table.remove(e.causes, 1)
    end
    return e.rank, before
end

function Reputation.weeks_to_recover(faction)
    local e = entry(faction)
    if e.rank <= e.base then
        return nil
    end
    local need = weeks(rules().RECOVER_WEEKS[e.rank] or 25)
    return M.max(0, M.ceil((need - (GetCurrentTime() - e.since)) / CONFIG.WEEK_SECONDS))
end

function Reputation.update()
    local recovered = {}
    for faction, e in pairs(state) do
        if e.rank > e.base and GetCurrentTime() - e.since >= weeks(rules().RECOVER_WEEKS[e.rank] or 25) then
            e.rank = e.rank - 1
            e.since = GetCurrentTime()
            table.insert(recovered, faction)
        end
    end
    return recovered
end

function Reputation.penalty(faction, treaty)
    local rank = Reputation.rank(faction)
    local table_ = treaty and rules().TREATY or rules().DEAL
    return table_[rank] or 0
end

function Reputation.opinion(faction)
    return rules().OPINION[Reputation.rank(faction)] or 0
end

function Reputation.describe(faction)
    local e = entry(faction)
    local text = Reputation.WORDS[e.rank]
    local parts = {}
    for i = table.getn(e.causes), 1, -1 do
        local c = e.causes[i]
        local ago = M.floor((GetCurrentTime() - c.time) / CONFIG.WEEK_SECONDS)
        table.insert(parts, c.text .. ((ago > 0) and (" (" .. ago .. " week" .. ((ago == 1) and "" or "s") .. " ago)")
            or " (this week)"))
    end
    if table.getn(parts) > 0 then
        text = text .. ": " .. table.concat(parts, "; ")
    elseif e.rank > 1 then
        text = text .. ": its record precedes it"
    end
    local left = Reputation.weeks_to_recover(faction)
    if left then
        text = text .. ". Can recover in " .. left .. " week" .. ((left == 1) and "" or "s")
    end
    return text .. "."
end

function Reputation.share()
    DIPLOMACY_REPUTATION = function(faction)
        return Reputation.rank(faction), Reputation.word(faction)
    end
    DIPLOMACY_REPUTATION_DROP = Reputation.drop
    DIPLOMACY_REPUTATION_SPYING = Reputation.spying
end

function Reputation.spying(spy, target, tier, label)
    local r = rules()
    if (tier or 1) < r.SPY_TIER or not Reputation.relation_of then
        return nil
    end
    local relation = Reputation.relation_of(string.upper(spy), string.upper(target))
    if not (relation and r.SPY_TREATIES[relation]) then
        return nil
    end
    return Reputation.drop(spy, 1, "was caught spying on " .. (label or target) .. ", its "
        .. ((relation == "ALLIANCE") and "ally" or string.lower(relation == "VASSAL" and "vassal" or "protectorate")))
end

return Reputation
