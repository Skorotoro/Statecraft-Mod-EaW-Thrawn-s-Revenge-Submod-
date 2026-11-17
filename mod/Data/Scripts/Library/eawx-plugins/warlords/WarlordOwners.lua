WarlordOwners = WarlordOwners or {}

local names = nil

local function load_names()
    if names then
        return
    end
    names = {WARLORDS = true}
    local ok, data = pcall(require, "eawx-plugins/warlords/WarlordFactions")
    if ok and type(data) == "table" then
        for _, warlord in ipairs(data.WARLORDS) do
            names[warlord.faction] = true
        end
    end
end

function WarlordOwners.is_minor(player)
    if not player then
        return false
    end
    load_names()
    return names[string.upper(player.Get_Faction_Name())] == true
end

function WarlordOwners.owner_or_warlords(planet)
    if planet then
        local owner = planet.Get_Owner()
        if WarlordOwners.is_minor(owner) then
            return owner
        end
    end
    return Find_Player("Warlords")
end

return WarlordOwners
