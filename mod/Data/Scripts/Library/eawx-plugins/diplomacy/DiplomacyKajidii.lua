local M = require("eawx-plugins/diplomacy/DiplomacyMath")

local K = {}

K.FAMILIES = {
    {key = "besadii", name = "Besadii", spec = {"Spice and Slaves", "Ylesia's Pilgrim Colonies"},
     desc = {"Masters of Ylesia, where pilgrims toil in the spice factories for the Exultation. Rich, proud and",
             "cruel; Durga Besadii Tai has never forgiven the rivals behind his father Aruk's death."}},
    {key = "desilijic", name = "Desilijic", spec = {"Smuggling and Gambling", "Jabba's Old Empire"},
     desc = {"The clan of Jiliac and Jabba. Since Jabba fell at the Great Pit of Carkoon, its spice runs, smuggling",
             "routes and gambling dens from Tatooine to Nar Shaddaa are leaderless, and every other family wants them."}},
    {key = "anjiliac", name = "Anjiliac", spec = {"Shipping and Protection", "The Docks of Nar Shaddaa"},
     desc = {"Old masters of the Smuggler's Moon. The Anjiliac own berths and freight lanes and sell protection to",
             "every captain who would like to keep their ship."}},
    {key = "bareesh", name = "Bareesh", spec = {"Arms and Mercenaries", "Guns for Any Buyer"},
     desc = {"Gunrunners and brokers of hired muscle: Gamorrean guards, Klatooinian regiments, Weequay pirates.",
             "The Bareesh arm whoever pays, and the cartels' private armies first."}},
    {key = "gorensla", name = "Gorensla", spec = {"Information and Blackmail", "Slicers and Informants"},
     desc = {"Patient spymasters of the underworld. The Gorensla trade in secrets, debts and stolen codes, and",
             "it is said every Hutt council meeting is overheard by at least one of their slicers."}},
}

local SEEDS = {
    YLESIA = "besadii", NALHUTTA = "besadii", RYLOTH = "besadii",
    TATOOINE = "desilijic", KESSEL = "desilijic", SRILUUR = "desilijic",
    NARSHADDAA = "anjiliac",
    GAMORR = "bareesh", KLATOOINE = "bareesh", SRIRUUR = "bareesh",
    TOYDARIA = "gorensla", NIMBAN = "gorensla",
}

local INDEX = {}
for i, f in ipairs(K.FAMILIES) do
    INDEX[f.key] = i
end

local function plain(name)
    return string.upper(string.gsub(name, "[%s_%-']", ""))
end

function K.family_of(d, type_name)
    d.kajidii_worlds = d.kajidii_worlds or {}
    local held = d.kajidii_worlds[type_name]
    if held then
        return held
    end
    local seed = SEEDS[plain(type_name)]
    if seed then
        held = INDEX[seed]
    else
        local sum = 0
        local p = plain(type_name)
        for i = 1, string.len(p) do
            sum = sum + string.byte(p, i) * i
        end
        held = sum - table.getn(K.FAMILIES) * M.floor(sum / table.getn(K.FAMILIES)) + 1
    end
    d.kajidii_worlds[type_name] = held
    return held
end

function K.worlds(d)
    local hutts = Find_Player("HUTT_CARTELS")
    local out = {}
    local ok, planets = pcall(FindPlanet.Get_All_Planets)
    if not ok or not planets or not hutts then
        return out
    end
    local okd, Deals = pcall(require, "eawx-plugins/diplomacy/DiplomacyDeals")
    local capital = okd and Deals.capital(d, hutts)
    for _, planet in pairs(planets) do
        if TestValid(planet) then
            local type_name = string.upper(planet.Get_Type().Get_Name())
            local rec = d.underworld and d.underworld[type_name]
            if planet.Get_Owner() == hutts then
                table.insert(out, {planet = planet, type = type_name, held = true,
                                   state = (planet == capital) and "shared" or "hutt",
                                   family = K.family_of(d, type_name), level = 0})
            elseif rec then
                local family, share = rec.family, 100
                if rec.state ~= "controlled" then
                    family, share = nil, 0
                    for i = 1, table.getn(K.FAMILIES) do
                        if (rec.influence[i] or 0) > share then
                            family, share = i, rec.influence[i]
                        end
                    end
                end
                table.insert(out, {planet = planet, type = type_name, held = false, state = rec.state,
                                   family = family or 1, share = share, rec = rec})
            elseif not d.underworld then
                local got, value = pcall(GlobalValue.Get, type_name .. "_SMUGGLING_LEVEL")
                if got and type(value) == "number" and value > 0 then
                    table.insert(out, {planet = planet, type = type_name, held = false, state = "network",
                                       family = K.family_of(d, type_name), level = value})
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.held ~= b.held then
            return a.held
        end
        return a.type < b.type
    end)
    return out
end

return K
