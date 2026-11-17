local Sight = {}

local function reveal(name, on)
    if StoryUtil and StoryUtil.RevealPlanet then
        pcall(StoryUtil.RevealPlanet, name, on)
    end
end

local function subject_worlds(d)
    local out = {}
    local subjects = {}
    local vassals = d:vassal_player()
    if vassals then
        subjects[vassals] = true
    end
    for faction, relation in pairs(d.relations or {}) do
        if relation == "VASSAL" or relation == "PROTECTORATE" then
            local player = Find_Player(faction)
            if player then
                subjects[player] = true
            end
        end
    end
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if subjects[planet.Get_Owner()] then
            out[string.upper(planet.Get_Type().Get_Name())] = true
        end
    end
    return out
end

function Sight.update(d)
    if GetCurrentTime() < (d.next_sight or 0) then
        return
    end
    d.next_sight = GetCurrentTime() + 5
    d.sight = d.sight or {}
    local now = subject_worlds(d)
    for name in pairs(now) do
        if not d.sight[name] then
            reveal(name, true)
            d.sight[name] = true
        end
    end
    for name in pairs(d.sight) do
        if not now[name] then
            local planet = FindPlanet(name)
            if not (planet and planet.Get_Owner() == d.human) then
                reveal(name, false)
            end
            d.sight[name] = nil
        end
    end
end

return Sight
