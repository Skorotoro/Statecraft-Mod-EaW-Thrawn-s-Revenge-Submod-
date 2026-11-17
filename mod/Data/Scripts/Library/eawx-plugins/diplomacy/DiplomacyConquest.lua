local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local CONQUEST = require("eawx-plugins/diplomacy/DiplomacyConfig").CONQUEST

local function popup_text(tag, part, name, tooltip)
    local id = "TEXT_DIPLOMACY_" .. tag .. "_" .. part
    local object = string.gsub(string.lower(tag .. "_" .. part), "(%a)([%w]*)", function(a, b) return string.upper(a) .. b end)
    if name then
        if Engine_Set_Object_Text then
            Engine_Set_Object_Text(object, id, name)
        elseif Engine_Set_Text then
            Engine_Set_Text(id, name)
        end
    end
    if tooltip and Engine_Set_Text then
        Engine_Set_Text(id .. "_TIP", tooltip)
    end
end

local Conquest = {}
local pending = {}
local COLOR = {r = 170, g = 200, b = 255}

local function part(name)
    local ok, mod = pcall(require, "eawx-plugins/new-republic/" .. name)
    return ok and type(mod) == "table" and mod or nil
end

local function occupy_tip(d, c)
    local Republic, Council = part("Republic"), part("RepublicCouncil")
    local R = part("RepublicConfig")
    local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
    local council = Council and Council.active and Council.active(d)
    local band = string.upper(c.band or "Wary")
    local occ = CONFIG.OCCUPATION
    local parts = {}
    if band == "SYMPATHETIC" then
        table.insert(parts, "Its people welcome the Republic as liberators: no occupation and no blame")
    else
        table.insert(parts, "Its people resent the occupation: influence -" .. occ.PENALTY .. ", easing one a "
            .. "point every " .. occ.EASE_WEEKS .. " weeks")
        local cost = Council and Council.occupy_cost and Council.occupy_cost(band, c.old)
        if cost then
            local U = part("RepublicUtil")
            local kind = U and U.category(c.old or "")
            local crusade = council and Council.focus and Council.focus(d) == "CRUSADE"
                and (kind == "IMPERIAL" or kind == "WARLORD")
            table.insert(parts, "its people's opinion -" .. cost.joined)
            if crusade then
                table.insert(parts, "the Crusade to Coruscant spares the rest")
            else
                table.insert(parts, "independent worlds' attitude -" .. cost.independents .. " (easing a point every "
                    .. R.OCCUPY_COSTS.FADE_WEEKS .. " weeks), every world's sympathy -" .. cost.sympathy
                    .. (council and "" or (", cohesion -" .. cost.cohesion)))
            end
        end
        if council and R then
            local loss = (band == "HOSTILE") and R.COUNCIL.MANDATE.HOSTILE_INVASION or R.COUNCIL.MANDATE.WARY_INVASION
            table.insert(parts, "mandate -" .. loss .. ((band == "HOSTILE")
                and ", the Councillors and nearby worlds think less of the Alliance" or ""))
        end
        local free = require("eawx-plugins/diplomacy/DiplomacyOccupation").applies(d.human.Get_Faction_Name(), c.old)
        if free and not council and R then
            table.insert(parts, "a free world: cohesion -" .. R.INVASION_COHESION .. ", your reputation falls a "
                .. "rank, independents trust the Republic less")
        end
    end
    local approved = council or not c.old or c.old == "INDEPENDENT_FORCES" or c.old == "NEUTRAL"
        or (d.senate and d.senate.approved and d.senate.approved[c.old])
    if not approved then
        table.insert(parts, "not an approved war target: cohesion -" .. CONFIG.SENATE.UNAPPROVED_CONQUEST_COST)
    end
    return "It joins the Republic. " .. table.concat(parts, "; ") .. "."
end

function Conquest.applies(d, key, new_owner, old_owner)
    if not (d.republic and d.human and d.human.Get_Faction_Name() == "REBEL") then
        return false
    end
    if not (new_owner and old_owner) or string.upper(new_owner) ~= "REBEL" or string.upper(old_owner) == "REBEL" then
        return false
    end
    local U, Republic = part("RepublicUtil"), part("Republic")
    if not (U and Republic) or not U.populated(key) or Republic.is_territory(key) then
        return false
    end
    return true
end

local function imperial(old)
    local U = part("RepublicUtil")
    local kind = U and U.category(old or "")
    return kind == "IMPERIAL" or kind == "WARLORD"
end

local function band(d, key, old)
    local Sym, R = part("RepublicSympathy"), part("RepublicConfig")
    local ok, value = false, nil
    if Sym then
        ok, value = pcall(Sym.value, d, key, old)
    end
    if not (ok and type(value) == "number" and R) then
        return nil
    end
    return (value < R.SYMPATHY_HOSTILE and "Hostile") or (value >= R.SYMPATHY_SYMPATHETIC and "Sympathetic") or "Wary",
        value
end

local function claimant(d, key, old)
    local ok, Rebellion = pcall(require, "eawx-plugins/diplomacy/DiplomacyRebellion")
    local f = ok and Rebellion.preferred and Rebellion.preferred(d, key)
    f = f and string.upper(f)
    if not f or f == "INDEPENDENT_FORCES" or f == "REBEL" or f == old or imperial(f) then
        return nil
    end
    local p = Find_Player(f)
    if not p or p.Is_Enemy(d.human) or table.getn(require("eawx-plugins/diplomacy/DiplomacyDeals").worlds_of(p)) == 0 then
        return nil
    end
    return f
end

local function ask(d)
    local c = pending[1]
    if not c or not Engine_Set_Text then
        return
    end
    if GlobalValue.Get("POPUP_ACTIVE") ~= nil then
        c.shown = false
        return
    end
    c.shown = true
    c.band, c.sympathy = band(d, c.key, c.old)
    local who = d.display_name(c.old)
    local from_free = c.old == "INDEPENDENT_FORCES"
    popup_text("CONQUEST", "HEADER", c.readable .. " is ours")
    popup_text("CONQUEST", "BODY", "The Republic took " .. c.readable .. " from " .. who
        .. ". Decide its future before the fleet moves on.")
    popup_text("CONQUEST", "BODY", nil, "Its people were " .. string.lower(c.band or "wary") .. " toward the Republic"
        .. (c.sympathy and (" (sympathy " .. M.round(c.sympathy) .. ")") or "") .. ".")
    popup_text("CONQUEST", "TAKE", "Occupy (" .. (c.band or "Wary") .. ")")
    popup_text("CONQUEST", "TAKE", nil, occupy_tip(d, c))
    popup_text("CONQUEST", "FREE", "Liberate")
    local resent = (c.band == "Hostile") or c.loyal_elsewhere
    popup_text("CONQUEST", "FREE", nil, "The fleet withdraws and the world governs itself, at no political cost."
        .. (resent and (" Its people still resent the invasion" .. (c.loyal_elsewhere and ": they wanted another ruler." or ".")) or ""))
    popup_text("CONQUEST", "PROTECT", "Protectorate")
    popup_text("CONQUEST", "PROTECT", nil, "It governs itself under the Republic's protection"
        .. (imperial(c.old) and ": no conquest penalties." or "; the invasion still counts against you."))
    popup_text("CONQUEST", "NOPROTECT", "Protectorate (refused: hostile)")
    popup_text("CONQUEST", "NOPROTECT", nil, "A hostile world will never accept the Republic's protection.")
    if c.claimant then
        local name = d.display_name(c.claimant)
        popup_text("CONQUEST", "GIVE", "Give it to " .. name)
        popup_text("CONQUEST", "GIVE", nil, "Its people wanted " .. name .. " to rule them: hand it over, and "
            .. name .. " will be grateful.")
    end
    local options = {"TAKE"}
    if not from_free then
        table.insert(options, "FREE")
    end
    table.insert(options, (c.band == "Hostile") and "NOPROTECT" or "PROTECT")
    if c.claimant then
        table.insert(options, "GIVE")
    end
    local ok, err = pcall(GenericPopup, "CONQUEST", options, "CONQUEST_OPTION")
    if not ok then
        d.report_error("CONQUEST POPUP", err)
        local first = table.remove(pending, 1)
        d:conquest_effects(first.key, first.readable, "REBEL", first.old)
    end
end

local GARRISON_WEEKS = 4
local GARRISON_STARBASE = "Empire_Star_Base_1"
local GARRISON_BARRACKS = {urban = "Revolt_Urban_Barracks", rural = "Revolt_Rural_Barracks"}
local URBAN_TIER = 3

local function fleet_in_orbit(d, key)
    for _, unit in pairs(Find_All_Objects_Of_Type(d.human) or {}) do
        if TestValid(unit) then
            local ok, at = pcall(unit.Get_Planet_Location)
            if ok and at and string.upper(at.Get_Type().Get_Name()) == key then
                local okp, parent = pcall(unit.Get_Parent_Object)
                if okp and parent and TestValid(parent) and parent.Get_Type().Get_Name() == "GALACTIC_FLEET" then
                    return true
                end
            end
        end
    end
    return false
end

local function raise_garrisons(d)
    if not d.freed_garrisons or GetCurrentTime() < (d.next_garrison_check or 0) then
        return
    end
    d.next_garrison_check = GetCurrentTime() + 5
    local Grants = require("eawx-plugins/diplomacy/DiplomacyGrants")
    for key, since in pairs(d.freed_garrisons) do
        local planet = FindPlanet(key)
        local owner = planet and planet.Get_Owner()
        local week = require("eawx-plugins/diplomacy/DiplomacyConfig").WEEK_SECONDS
        local now = d.garrison_now and d.garrison_now[key]
        if not planet or owner == d.human or GetCurrentTime() - since > GARRISON_WEEKS * week then
            d.freed_garrisons[key] = nil
            if d.garrison_now then
                d.garrison_now[key] = nil
            end
        elseif now or not fleet_in_orbit(d, key) then
            d.freed_garrisons[key] = nil
            if d.garrison_now then
                d.garrison_now[key] = nil
            end
            local spawned = 0
            local ok_p, tiers = pcall(require, "eawx-plugins/diplomacy/DiplomacyPopulations")
            local urban = ok_p and type(tiers) == "table" and (tiers[key] or 0) >= URBAN_TIER
            for _, name in ipairs({GARRISON_STARBASE, urban and GARRISON_BARRACKS.urban or GARRISON_BARRACKS.rural}) do
                local unit_type = Find_Object_Type(name)
                if unit_type and pcall(Spawn_Unit, unit_type, planet, owner) then
                    spawned = spawned + 1
                end
            end
            for _ = 1, 2 do
                local ok, types = pcall(Grants.for_world, key)
                for _, unit_type in ipairs(ok and types or {}) do
                    if pcall(Spawn_Unit, unit_type, planet, owner) then
                        spawned = spawned + 1
                    end
                end
            end
            if Engine_Log then
                Engine_Log("GARRISON " .. key .. ": " .. spawned .. " units raised for " .. owner.Get_Faction_Name())
            end
        end
    end
end

function Conquest.tick(d)
    local c = pending[1]
    if c and c.shown == false and GlobalValue.Get("POPUP_ACTIVE") == nil then
        ask(d)
    end
    pcall(raise_garrisons, d)
end

function Conquest.ask(d, key, readable, old_owner)
    local old = string.upper(old_owner)
    local ok, Rebellion = pcall(require, "eawx-plugins/diplomacy/DiplomacyRebellion")
    local loyal = ok and Rebellion.preferred and string.upper(Rebellion.preferred(d, key) or "INDEPENDENT_FORCES")
    table.insert(pending, {key = key, readable = readable, old = old, band = band(d, key, old),
                           claimant = claimant(d, key, old),
                           loyal_elsewhere = loyal and loyal ~= "INDEPENDENT_FORCES" and loyal ~= "REBEL"})
    if table.getn(pending) == 1 then
        ask(d)
    end
end

function Conquest.on_choice(d, option)
    local c = pending[1]
    if not c then
        return
    end
    option = string.upper(option or "")
    if string.find(option, "NOPROTECT") then
        d.show("Republic: the people of " .. c.readable .. " are hostile. They will never accept the Republic's protection.",
            nil, COLOR)
        ask(d)
        return
    end
    table.remove(pending, 1)
    local planet = FindPlanet(c.key)
    local human = string.upper(d.human.Get_Faction_Name())
    if string.find(option, "TAKE") or not planet or planet.Get_Owner() ~= d.human then
        d:conquest_effects(c.key, c.readable, "REBEL", c.old)
    elseif string.find(option, "GIVE") and c.claimant and Find_Player(c.claimant) then
        if not imperial(c.old) then
            d:conquest_effects(c.key, c.readable, "REBEL", c.old)
        end
        d:transfer_world(planet, Find_Player(c.claimant), false, true)
        require("eawx-plugins/diplomacy/DiplomacyOpinions").add(c.claimant, human, CONQUEST.GIFT_OPINION, 30,
            "the Republic gave them " .. c.readable)
        d.show("Republic: " .. c.readable .. " goes to " .. d.display_name(c.claimant) .. ", as its people wished.",
            nil, COLOR)
        local Favour = part("RepublicFavour")
        if Favour then
            pcall(Favour.deed, d, "GIVE")
        end
    else
        local protect = string.find(option, "PROTECT") ~= nil
        if protect and not imperial(c.old) then
            d:conquest_effects(c.key, c.readable, "REBEL", c.old)
        end
        local independent = Find_Player("Independent_Forces")
        if independent then
            d:transfer_world(planet, independent, false, true, true)
        end
        local r = d.republic
        if r and r.conquered then
            r.conquered[c.key] = nil
        end
        require("eawx-plugins/diplomacy/DiplomacyOccupation").stop(d, c.key)
        local P = part("RepublicProtectorates")
        local Favour = part("RepublicFavour")
        if Favour then
            pcall(Favour.deed, d, protect and "PROTECT" or "LIBERATE")
        end
        d.freed_garrisons = d.freed_garrisons or {}
        d.freed_garrisons[c.key] = GetCurrentTime()
        if protect and P then
            d.garrison_now = d.garrison_now or {}
            d.garrison_now[c.key] = true
            d.next_garrison_check = 0
            P.protect_world(d, planet, c.readable, true)
            d.show("Republic: " .. c.readable .. " is free, under the Republic's protection.", nil, COLOR)
        else
            local grudge = ((c.band == "Hostile") and CONQUEST.INVADED or 0) + (c.loyal_elsewhere and CONQUEST.NOT_THEIR_CHOICE or 0)
            if grudge ~= 0 then
                d.memory.world_grudges = d.memory.world_grudges or {}
                d.memory.world_grudges[c.key] = {time = GetCurrentTime(), value = grudge}
            end
            d.show("Republic: " .. c.readable .. " is liberated. The Republic's fleet withdraws and its people govern "
                .. "themselves.", nil, COLOR)
        end
    end
    if pending[1] then
        ask(d)
    end
end

return Conquest
