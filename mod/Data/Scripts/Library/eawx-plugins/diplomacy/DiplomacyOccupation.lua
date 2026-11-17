local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")

local Occupation = {}

local function imperial(faction_name)
    local C = ModContentLoader.get("GameConstants")
    local alias = C.ALIASES and C.ALIASES[faction_name]
    return faction_name == "EMPIRE" or alias == "IMPERIAL"
end

function Occupation.applies(human_name, old_owner_name)
    if not CONFIG.OCCUPATION.FACTIONS[human_name] or not old_owner_name then
        return false
    end
    local old = string.upper(old_owner_name)
    local D = rawget(_G, "Diplomacy")
    local warlord = string.find(old, "^WARLORD") or (D and D.warlord_factions and D.warlord_factions()[old])
    return not warlord and old ~= "NEUTRAL" and not imperial(old)
end

local function hook(d, planet_name)
    if type(InfluencePolicyRepository) ~= "table" then
        return
    end
    local key = string.lower(planet_name)
    if d.occupation_hooks[key] and InfluencePolicyRepository[key] == d.occupation_hooks[key] then
        return
    end
    local original = InfluencePolicyRepository[key]
    d.occupation_hooks[key] = function(planet)
        local base = original or InfluencePolicyRepository.DEFAULT
        local value = base(planet)
        local occupied = d.occupation[string.upper(planet_name)]
        if occupied and planet:get_owner() == d.human then
            value = value - occupied.penalty
        end
        local extra = d.influence_mods and d.influence_mods[string.upper(planet_name)]
        if extra and planet:get_owner() == d.human then
            value = value + extra
        end
        return value
    end
    InfluencePolicyRepository[key] = d.occupation_hooks[key]
end
Occupation.hook = hook

function Occupation.start(d, planet_name, readable_name)
    local penalty = CONFIG.OCCUPATION.PENALTY
    d.occupation[planet_name] = {penalty = penalty, next_ease = GetCurrentTime() + CONFIG.OCCUPATION.EASE_WEEKS * CONFIG.WEEK_SECONDS}
    hook(d, planet_name)
    d.show("Diplomacy: the people of " .. readable_name .. " resent the occupation (influence -" .. penalty
        .. ", easing over time).", nil, {r = 255, g = 190, b = 90})
end

function Occupation.stop(d, planet_name)
    d.occupation[planet_name] = nil
end

function Occupation.update(d)
    local now = GetCurrentTime()
    for name, occupied in pairs(d.occupation) do
        hook(d, name)
        if now >= occupied.next_ease then
            occupied.penalty = occupied.penalty - 1
            occupied.next_ease = now + CONFIG.OCCUPATION.EASE_WEEKS * CONFIG.WEEK_SECONDS
            if occupied.penalty <= 0 then
                d.occupation[name] = nil
                local planet = FindPlanet(name)
                if planet and planet.Get_Owner() == d.human then
                    d.show("Diplomacy: " .. d:planet_name(planet) .. " has come to accept "
                        .. d.display_name(d.human.Get_Faction_Name()) .. " rule.")
                end
            end
        end
    end
end

return Occupation
