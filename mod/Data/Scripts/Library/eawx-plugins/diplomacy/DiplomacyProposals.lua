local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")

local Proposals = {keys = {}}
for _, off in ipairs(require("eawx-plugins/diplomacy/DiplomacyPanelLayout").offsets or {}) do
    table.insert(Proposals.keys, string.format("%03d", off))
end
table.insert(Proposals.keys, "v")
local COLOR = {r = 150, g = 210, b = 255}
local SUFFIXES = {"", "_e"}

local function list(d)
    d.proposals = d.proposals or {}
    return d.proposals
end

function Proposals.waiting(d)
    return table.getn(list(d))
end

function Proposals.from(d, faction)
    for _, p in ipairs(list(d)) do
        if p.faction == faction then
            return p
        end
    end
    return nil
end

function Proposals.first(d)
    return list(d)[1]
end

function Proposals.add(d, faction, deal, text)
    if Proposals.from(d, faction) then
        return false
    end
    local now = GetCurrentTime()
    table.insert(list(d), {faction = faction, deal = deal, text = text, made = now,
                           expires = now + CONFIG.PROPOSALS.WEEKS * CONFIG.WEEK_SECONDS})
    d.show("Diplomacy: " .. d.display_name(faction) .. " offers you " .. text .. ". Open Diplomacy to answer ("
        .. CONFIG.PROPOSALS.WEEKS .. " weeks).", nil, COLOR, 25)
    Proposals.refresh(d)
    return true
end

local function remove(d, p)
    local keep = {}
    for _, other in ipairs(list(d)) do
        if other ~= p then
            table.insert(keep, other)
        end
    end
    d.proposals = keep
    Proposals.refresh(d)
end

function Proposals.accept(d, p)
    local Deals = require("eawx-plugins/diplomacy/DiplomacyDeals")
    remove(d, p)
    if not Find_Player(p.faction) then
        return false, "They are gone."
    end
    Deals.execute(d, p.faction, p.deal, 0)
    return true, "You accept " .. d.display_name(p.faction) .. "'s offer of " .. p.text .. "."
end

function Proposals.decline(d, p, lapsed)
    remove(d, p)
    if lapsed then
        d.show("Diplomacy: " .. d.display_name(p.faction) .. " withdraws its offer of " .. p.text
            .. ": no answer came.", nil, COLOR, 15)
    end
    return true, "You decline " .. d.display_name(p.faction) .. "'s offer of " .. p.text .. "."
end

function Proposals.update(d)
    local now = GetCurrentTime()
    if Proposals.waiting(d) > 0 and not Proposals.ready then
        Proposals.ready = true
        Proposals.refresh(d)
    end
    for _, p in ipairs(list(d)) do
        if now >= p.expires or not Find_Player(p.faction) or d:relation(p.faction) == "WAR" then
            Proposals.decline(d, p, true)
            return
        end
    end
end

function Proposals.refresh(d)
    local n = Proposals.waiting(d)
    local Window = rawget(_G, "DiplomacyWindow") or require("eawx-plugins/diplomacy/DiplomacyWindow")
    Window.flash_hold = n > 0
    if n > 0 and Engine_Gui_Tick then
        Engine_Gui_Tick(1)
    end
    Proposals.drawn_count = nil
    Proposals.draw(d)
end

function Proposals.draw(d, pair)
    pair = pair or Proposals.pair
    Proposals.pair = pair
    local n = Proposals.waiting(d)
    local t = Engine_Ticks and Engine_Ticks() or 0
    local lit = n > 0 and M.floor(t / 500) - 2 * M.floor(t / 1000) == 0
    for _, suffix in ipairs(SUFFIXES) do
        for _, key in ipairs(Proposals.keys or {}) do
            local badge = "b_diplomacy_panel_badge_" .. key .. suffix
            local button = "b_diplomacy_panel_" .. key .. suffix
            local shown = n > 0 and key == pair
            if Proposals.drawn_count ~= n or Proposals.drawn_pair ~= pair then
                pcall(GUI_Component_Visibility, badge, shown)
                if shown then
                    pcall(GUI_Component_Text, badge, "" .. n)
                end
            end
            if key == pair and (lit ~= Proposals.lit or Proposals.drawn_count ~= n) then
                pcall(GUI_Button_Icon, button, lit and "dp_btn_diplomacy_sel.tga" or "dp_btn_diplomacy.tga", 1, 1, 1, 1)
            end
        end
    end
    Proposals.drawn_count, Proposals.drawn_pair, Proposals.lit = n, pair, lit
end

return Proposals
