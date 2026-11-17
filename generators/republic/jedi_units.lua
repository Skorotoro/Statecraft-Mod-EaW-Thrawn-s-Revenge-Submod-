-- The Jedi Order's units: Jedi_Units.xml. A Jedi who leaves the Temple on a mission travels as a unit of their own,
-- stealthy, spawned in orbit (Jedi_Mission_<slot>_<kind>, renamed in game; heroes: Jedi_Hero_<key>, a copy of their
-- own team). Each carries a marker (Jedi_Escort_<slot or key>) whose script spawns the students travelling with them
-- beside them in battle (GlobalValue JEDI_ESCORT_<marker>: the escorts' types, comma separated). The Jedi themselves
-- are Thrawn's Jedi by reference, by rank: a Padawan without powers and with a weaker guard, a Knight as Thrawn's, a
-- Master tougher with a surer guard; _T: the Guardians' teaching (more health), _C: and a bonus to the forces in the
-- battle. And the companies of Jedi who fell (Thrawn's Dark Jedi company by reference).
-- Personal fighters (Jedi_Fighter_<craft>_<rank><level>): a Jedi's own craft, put on the field by the Order's battle
-- plugin when they are in orbit of a space battle (never built, never on the galaxy map). Thrawn's fighter by
-- reference: health and shields by rank (stronger than a fighter, weaker than a fighter hero), a Jedi's guard against
-- blaster bolts, more damage by rank; _T: the Guardians' first teaching (+20% health), _TT: and the second (+10%
-- damage). Luke and Corran fly copies of their own X-wings.
local lib = gen.load("lib")

local SLOTS, FALLEN = 20, 4
local KNIGHTS = "New_Republic_Jedi_Knight_Company"
local DARK = "Imperial_Dark_Jedi_Company"
local MARKER = "Infantry_Dummy_Template"
local SHUTTLE = "Alliance_Shuttle_Noncombat"          -- a Jedi's own ride, no warship (heroes keep their own)
local PATHS = {{"G", "Jedi_Guardian", "I_BUTTON_JEDI_GUARDIAN.TGA"}, {"C", "Jedi_Consular", "I_BUTTON_JEDI_CONSULAR.TGA"},
               {"S", "Jedi_Sentinel", "I_BUTTON_JEDI_SENTINEL.TGA"}}
local HEROES = {{"LUKE", "Luke_Skywalker_Jedi_Team"}, {"MARA", "Mara_Saber_Team"}, {"KYLE", "Katarn_Team"},
                {"CORRAN", "Corran_Horn_Team"}, {"CILGHAL", "Cilghal_Team"}, {"ZUMA", "Zuma_Team"}}
-- rank: health factor, guard (block chance) added, the name shown in battle
local RANKS = {P = {0.85, -0.15, "Jedi Padawan"}, K = {1, 0, "Jedi Knight"}, M = {1.35, 0.15, "Jedi Master"}}
local TOUGH = 1.25
local STEALTH = "\t\t\t<Galactic_Stealth_Ability Name=\"Jedi_Order_Galactic_Stealth\">\n"
    .. "\t\t\t\t<Evade_Detection_Chance>0.0</Evade_Detection_Chance>\n"
    .. "\t\t\t</Galactic_Stealth_Ability>\n"

local _, objects = lib.objects()
local function body_of(name)
    local obj = objects[name:upper()]
    if not obj then
        error("jedi units: " .. name .. " is not a Thrawn's Revenge object")
    end
    return obj[2]
end
for _, name in ipairs({KNIGHTS, DARK, MARKER, SHUTTLE, "Jedi_Guardian", "Jedi_Consular", "Jedi_Sentinel"}) do
    body_of(name)
end

local texts, xml = {}, {'<?xml version="1.0" encoding="utf-8"?>', "<Jedi_Units>"}
local function add(text)
    xml[#xml + 1] = text
end

-- A Jedi of a rank: a copy of Thrawn's Jedi of that Path under a new name (abilities renamed with it).
local function jedi(name, base, rank, tough)
    local r = RANKS[rank]
    local body = body_of(base):gsub(base, name)
    local health = tonumber(body:match("<Tactical_Health>%s*([%d%.]+)%s*</Tactical_Health>") or "90")
    body = body:gsub("<Tactical_Health>%s*[%d%.]+%s*</Tactical_Health>",
        "<Tactical_Health>" .. lib.round(health * r[1] * (tough and TOUGH or 1)) .. "</Tactical_Health>", 1)
    body = body:gsub("<Block_Chance>%s*([%d%.]+)%s*</Block_Chance>", function(v)
        local chance = math.max(0.1, math.min(0.9, tonumber(v) + r[2]))
        return "<Block_Chance>" .. string.format("%.2f", chance) .. "</Block_Chance>"
    end)
    if rank == "P" then                       -- no powers: only the blade's guard
        body = body:gsub("<Unit_Abilities_Data SubObjectList=\"Yes\">.-</Unit_Abilities_Data>",
            "<Unit_Abilities_Data SubObjectList=\"Yes\"></Unit_Abilities_Data>")
        body = body:gsub("<Abilities SubObjectList=\"Yes\">(.-)</Abilities>", function(list)
            local kept = {}
            for tag, ability in list:gmatch("(<(%w+_Blaster_Ability) Name=.-</%2>)") do
                kept[#kept + 1] = tag
            end
            return "<Abilities SubObjectList=\"Yes\">\n" .. table.concat(kept, "\n") .. "\n</Abilities>"
        end)
    end
    -- (every unit a travelling company carries must be stealthy, or the company is seen)
    body = body:gsub("</Abilities>", STEALTH .. "</Abilities>", 1)
    local text = "TEXT_JEDI_ORDER_" .. rank
    texts[text] = r[3]
    -- their tooltip is theirs alone (not the Jedi Knight company's members)
    local bio = "TEXT_JEDI_ORDER_" .. rank .. "_BIO"
    texts[bio] = ({P = "A Padawan of the new Jedi Order, still learning the ways of the Force.",
                   K = "A Knight of the new Jedi Order.", M = "A Master of the new Jedi Order."})[rank]
    if body:find("<Encyclopedia_Text>") then
        body = body:gsub("<Encyclopedia_Text>.-</Encyclopedia_Text>", "<Encyclopedia_Text>" .. bio .. "</Encyclopedia_Text>", 1)
    else
        body = body:gsub("<Text_ID>", "<Encyclopedia_Text>" .. bio .. "</Encyclopedia_Text>\n\t\t<Text_ID>", 1)
    end
    if body:find("<Encyclopedia_Unit_Class>") then
        body = body:gsub("<Encyclopedia_Unit_Class>.-</Encyclopedia_Unit_Class>", "<Encyclopedia_Unit_Class>" .. text .. "</Encyclopedia_Unit_Class>", 1)
    end
    -- (in orbit, as a fleet: a company on a world's surface cannot be sent anywhere; the company's own tag is not enough)
    body = body:gsub("<Text_ID>[^<]*</Text_ID>", "<Text_ID>" .. text .. "</Text_ID>\n\t\t<Always_Spawn_In_Orbit>Yes</Always_Spawn_In_Orbit>", 1)
    add("\t<GroundInfantry Name=\"" .. name .. "\">" .. body .. "</GroundInfantry>")
end

local infantry = {}                           -- kind -> name: P, K_G ... M_S, and with _T
for _, tough in ipairs({false, true}) do
    local t = tough and "_T" or ""
    jedi("Jedi_Order_P" .. t, "Jedi_Guardian", "P", tough)
    infantry["P" .. t] = "Jedi_Order_P" .. t
    for _, rank in ipairs({"K", "M"}) do
        for _, path in ipairs(PATHS) do
            local kind = rank .. "_" .. path[1]
            jedi("Jedi_Order_" .. kind .. t, path[2], rank, tough)
            infantry[kind .. t] = "Jedi_Order_" .. kind .. t
        end
    end
end

-- The marker: unseen, it spawns the escorts named for it and leaves the battle (Scripts\GameObject\JediEscort.lua).
local function marker(key)
    texts.TEXT_JEDI_ESCORT = "Jedi"
    add("\t<GroundInfantry Name=\"Jedi_Escort_" .. key .. "\">\n"
        .. "\t\t<Variant_Of_Existing_Type>" .. MARKER .. "</Variant_Of_Existing_Type>\n"
        .. "\t\t<Text_ID>TEXT_JEDI_ESCORT</Text_ID>\n"
        .. "\t\t<Affiliation>Rebel</Affiliation>\n"
        .. "\t\t<Lua_Script>JediEscort</Lua_Script>\n"
        .. "\t\t<Always_Spawn_In_Orbit>Yes</Always_Spawn_In_Orbit>\n"
        .. "\t\t<Abilities SubObjectList=\"Yes\">\n" .. STEALTH .. "\t\t</Abilities>\n"
        .. "\t</GroundInfantry>")
end

local function commander(name)
    return "\t\t\t<Combat_Bonus_Ability Name=\"" .. name .. "_Commander\">\n"
        .. "\t\t\t\t<Activation_Style>Combat_Automatic</Activation_Style>\n"
        .. "\t\t\t\t<Applicable_Unit_Categories>All</Applicable_Unit_Categories>\n"
        .. "\t\t\t\t<Damage_Bonus_Percentage>0.10</Damage_Bonus_Percentage>\n"
        .. "\t\t\t\t<Stacking_Category>0</Stacking_Category>\n"
        .. "\t\t\t</Combat_Bonus_Ability>\n"
end

-- The rides: copies of the transports that carry the Jedi, half as fast again in hyperspace (they hop world to world
-- with shorter waits).
local SPEED = 1.5
local function ride(base)
    local name = "Jedi_Ride_" .. base
    local speed = tonumber(lib.inherited(base, "Hyperspace_Speed")) or 1
    local tag = (objects[base:upper()] and objects[base:upper()][1]) or "TransportUnit"   -- (the base's own kind)
    add("\t<" .. tag .. " Name=\"" .. name .. "\">\n"
        .. "\t\t<Variant_Of_Existing_Type>" .. base .. "</Variant_Of_Existing_Type>\n"
        .. "\t\t<Hyperspace_Speed>" .. string.format("%.2f", speed * SPEED) .. "</Hyperspace_Speed>\n"
        .. "\t</" .. tag .. ">")
    return name
end
local SHUTTLE_RIDE = ride(SHUTTLE)

-- Who travels: one Jedi (by slot, kind, teaching, sex) with their marker; their icon matches their portrait in the
-- Order's roster (the women's and the Sentinel men's portraits are build.py's, dp_ju_*).
local TRAVEL_ICON = {G = "I_BUTTON_JEDI_GUARDIAN.TGA", C = "I_BUTTON_JEDI_CONSULAR.TGA", S = "dp_ju_jedi_sentinel_m.tga",
                     G_F = "dp_ju_jedi_guardian_f.tga", C_F = "dp_ju_jedi_consular_f.tga", S_F = "I_BUTTON_JEDI_SENTINEL.TGA",
                     P = "I_BUTTON_JEDI_CONSULAR.TGA", P_F = "dp_ju_jedi_consular_f.tga"}
for n = 1, SLOTS do
    local text = "TEXT_JEDI_MISSION_" .. n
    texts[text] = "Jedi"
    texts[text .. "_BIO"] = "A Jedi of the new Order, on a mission."
    texts[text .. "_CLASS"] = "Jedi"
    marker("M" .. n)
    for _, rank in ipairs({"K", "M"}) do
        for _, path in ipairs(PATHS) do
            local kind = rank .. "_" .. path[1]
            for _, sex in ipairs({"", "_F"}) do
            for _, level in ipairs({"", "_T", "_C"}) do
                local name = "Jedi_Mission_" .. n .. "_" .. kind .. level .. sex
                local unit = infantry[kind .. ((level ~= "") and "_T" or "")]
                add("\t<GroundCompany Name=\"" .. name .. "\">\n"
                    .. "\t\t<Variant_Of_Existing_Type>" .. KNIGHTS .. "</Variant_Of_Existing_Type>\n"
                    .. "\t\t<Text_ID>" .. text .. "</Text_ID>\n"
                    .. "\t\t<Encyclopedia_Text>" .. text .. "_BIO</Encyclopedia_Text>\n"
                    .. "\t\t<Encyclopedia_Unit_Class>" .. text .. "_CLASS</Encyclopedia_Unit_Class>\n"
                    .. "\t\t<Icon_Name>" .. TRAVEL_ICON[path[1] .. sex] .. "</Icon_Name>\n"
                    .. "\t\t<Build_Initially_Locked>Yes</Build_Initially_Locked>\n"
                    .. "\t\t<Tech_Level>99</Tech_Level>\n"
                    .. "\t\t<Always_Spawn_In_Orbit>Yes</Always_Spawn_In_Orbit>\n"
                    .. "\t\t<Company_Units>" .. unit .. ", Jedi_Escort_M" .. n .. "</Company_Units>\n"
                    .. "\t\t<Company_Transport_Unit>" .. SHUTTLE_RIDE .. "</Company_Transport_Unit>\n"
                    .. "\t\t<Abilities SubObjectList=\"Yes\">\n" .. STEALTH
                    .. ((level == "_C") and commander(name) or "")
                    .. "\t\t</Abilities>\n"
                    .. "\t</GroundCompany>")
            end
            end
        end
    end
end

-- A Padawan travels alone only to their trial.
for n = 1, SLOTS do
    local text = "TEXT_JEDI_MISSION_" .. n
    for _, sex in ipairs({"", "_F"}) do
    for _, level in ipairs({"", "_T"}) do
        add("\t<GroundCompany Name=\"Jedi_Mission_" .. n .. "_P" .. level .. sex .. "\">\n"
            .. "\t\t<Variant_Of_Existing_Type>" .. KNIGHTS .. "</Variant_Of_Existing_Type>\n"
            .. "\t\t<Text_ID>" .. text .. "</Text_ID>\n"
            .. "\t\t<Encyclopedia_Text>" .. text .. "_BIO</Encyclopedia_Text>\n"
            .. "\t\t<Encyclopedia_Unit_Class>" .. text .. "_CLASS</Encyclopedia_Unit_Class>\n"
            .. "\t\t<Icon_Name>" .. TRAVEL_ICON["P" .. sex] .. "</Icon_Name>\n"
            .. "\t\t<Build_Initially_Locked>Yes</Build_Initially_Locked>\n"
            .. "\t\t<Tech_Level>99</Tech_Level>\n"
            .. "\t\t<Always_Spawn_In_Orbit>Yes</Always_Spawn_In_Orbit>\n"
            .. "\t\t<Company_Units>" .. infantry["P" .. level] .. ", Jedi_Escort_M" .. n .. "</Company_Units>\n"
            .. "\t\t<Company_Transport_Unit>" .. SHUTTLE_RIDE .. "</Company_Transport_Unit>\n"
            .. "\t\t<Abilities SubObjectList=\"Yes\">\n" .. STEALTH
            .. "\t\t</Abilities>\n"
            .. "\t</GroundCompany>")
    end
    end
end

-- Heroes travel as a copy of their own team, with their marker.
for _, h in ipairs(HEROES) do
    local key, team = h[1], h[2]
    local units = lib.field(body_of(team), "Company_Units")
    local transport = lib.field(body_of(team), "Company_Transport_Unit")
    local hero_ride = (transport ~= "") and ride(transport) or nil
    local with = "TEXT_JEDI_HERO_" .. key .. "_WITH"
    texts[with] = " "
    local encyclopedia = (body_of(team):match("<Encyclopedia_Text>(.-)</Encyclopedia_Text>") or "") .. "\n\t\t" .. with .. "\n\t\t"
    marker(key)
    for _, level in ipairs({"", "_C"}) do
        local name = "Jedi_Hero_" .. key .. level
        add("\t<HeroCompany Name=\"" .. name .. "\">\n"
            .. "\t\t<Variant_Of_Existing_Type>" .. team .. "</Variant_Of_Existing_Type>\n"
            .. "\t\t<Build_Initially_Locked>Yes</Build_Initially_Locked>\n"
            .. "\t\t<Tech_Level>99</Tech_Level>\n"
            .. "\t\t<Always_Spawn_In_Orbit>Yes</Always_Spawn_In_Orbit>\n"
            .. "\t\t<Company_Units>" .. units .. ", Jedi_Escort_" .. key .. "</Company_Units>\n"
            .. (hero_ride and ("\t\t<Company_Transport_Unit>" .. hero_ride .. "</Company_Transport_Unit>\n") or "")
            .. "\t\t<Encyclopedia_Text>" .. encyclopedia .. "</Encyclopedia_Text>\n"
            .. "\t\t<Abilities SubObjectList=\"Yes\">\n" .. STEALTH
            .. ((level == "_C") and commander(name) or "")
            .. "\t\t</Abilities>\n"
            .. "\t</HeroCompany>")
    end
end

for n = 1, FALLEN do
    local text = "TEXT_JEDI_FALLEN_" .. n
    texts[text] = "Dark Jedi"
    add("\t<GroundCompany Name=\"Jedi_Fallen_" .. n .. "\">\n"
        .. "\t\t<Variant_Of_Existing_Type>" .. DARK .. "</Variant_Of_Existing_Type>\n"
        .. "\t\t<Text_ID>" .. text .. "</Text_ID>\n"
        .. "\t\t<Build_Initially_Locked>Yes</Build_Initially_Locked>\n"
        .. "\t\t<Tech_Level>99</Tech_Level>\n"
        .. "\t</GroundCompany>")
end
local CRAFTS = {{"XWING", "X_Wing", "X-wing"}, {"AWING", "A_Wing", "A-wing"}, {"Z95", "Z95_Headhunter", "Z-95 Headhunter"},
                {"YWING", "Y_Wing", "Y-wing"}, {"EWING", "E_Wing", "E-wing"}, {"BWING", "B_Wing", "B-wing"},
                {"R41", "R41_Starchaser", "R-41 Starchaser"}, {"CLOAKSHAPE", "Cloakshape", "Cloakshape fighter"},
                {"PREYBIRD", "Preybird", "Preybird"}}
local HERO_CRAFTS = {{"LUKE", "Luke_Jedi_XWing", "Luke Skywalker's X-wing"}, {"CORRAN", "Corran_XWing", "Corran Horn's X-wing"},
                     {"KYLE", "Moldy_Crow", "Kyle Katarn's Moldy Crow"}, {"MARA", "Jade_Fire", "Mara Jade's Jade's Fire"}}
-- rank: health, shields, damage bonus, blaster absorb chance, the name's start
local PILOTS = {P = {45, 35, 0, 0.15, "Jedi Padawan"}, K = {75, 55, 0.2, 0.25, "Jedi Knight"}, M = {110, 80, 0.4, 0.35, "Jedi Master"}}
for _, c in ipairs(CRAFTS) do
    body_of(c[2])
end
for _, h in ipairs(HERO_CRAFTS) do
    body_of(h[2])
end

local function fighter(name, base, text, health, shields, damage, absorb, aura)
    local abilities = "\t\t\t<Absorb_Blaster_Ability Name=\"" .. name .. "_Absorb\">\n"
        .. "\t\t\t\t<Activation_Style>Take_Damage</Activation_Style>\n"
        .. "\t\t\t\t<Absorb_Chance>" .. string.format("%.2f", absorb) .. "</Absorb_Chance>\n"
        .. "\t\t\t\t<Damage_Absorb_Percentage>0.01</Damage_Absorb_Percentage>\n"
        .. "\t\t\t\t<Damage_Absorb_Amount>0.01</Damage_Absorb_Amount>\n"
        .. "\t\t\t\t<Applicable_Unit_Categories>Fighter | Bomber | Gunship | Corvette | Frigate | Capital | SpaceStructure</Applicable_Unit_Categories>\n"
        .. "\t\t\t\t<SFXEvent_Activate>Unit_Force_Absorb</SFXEvent_Activate>\n"
        .. "\t\t\t</Absorb_Blaster_Ability>\n"
    if damage > 0 then
        abilities = abilities .. "\t\t\t<Combat_Bonus_Ability Name=\"" .. name .. "_Skill\">\n"
            .. "\t\t\t\t<Activation_Style>Space_Automatic</Activation_Style>\n"
            .. "\t\t\t\t<Applicable_Unit_Types>" .. name .. "</Applicable_Unit_Types>\n"
            .. "\t\t\t\t<Damage_Bonus_Percentage>" .. string.format("%.2f", damage) .. "</Damage_Bonus_Percentage>\n"
            .. "\t\t\t\t<Stacking_Category>3</Stacking_Category>\n"
            .. "\t\t\t</Combat_Bonus_Ability>\n"
    end
    if aura then                                  -- (a Jedi Commander: the forces beside them fight harder)
        abilities = abilities .. "\t\t\t<Combat_Bonus_Ability Name=\"" .. name .. "_Command\">\n"
            .. "\t\t\t\t<Activation_Style>Space_Automatic</Activation_Style>\n"
            .. "\t\t\t\t<Applicable_Unit_Categories>All</Applicable_Unit_Categories>\n"
            .. "\t\t\t\t<Damage_Bonus_Percentage>" .. string.format("%.2f", aura) .. "</Damage_Bonus_Percentage>\n"
            .. "\t\t\t\t<Stacking_Category>0</Stacking_Category>\n"
            .. "\t\t\t</Combat_Bonus_Ability>\n"
    end
    add("\t<UniqueUnit Name=\"" .. name .. "\">\n"
        .. "\t\t<Variant_Of_Existing_Type>" .. base .. "</Variant_Of_Existing_Type>\n"
        .. "\t\t<Text_ID>" .. text .. "</Text_ID>\n"
        .. "\t\t<Is_Named_Hero>No</Is_Named_Hero>\n"
        .. "\t\t<Build_Initially_Locked>Yes</Build_Initially_Locked>\n"
        .. "\t\t<Tech_Level>99</Tech_Level>\n"
        .. "\t\t<Tactical_Health>" .. lib.round(health) .. "</Tactical_Health>\n"
        .. "\t\t<Shield_Points>" .. lib.round(shields) .. "</Shield_Points>\n"
        .. "\t\t<Shield_Refresh_Rate>4</Shield_Refresh_Rate>\n"
        .. "\t\t<Abilities SubObjectList=\"Yes\">\n" .. abilities .. "\t\t</Abilities>\n"
        .. "\t</UniqueUnit>")
end

local LEVELS = {{"", 1, 0}, {"_T", 1.2, 0}, {"_TT", 1.2, 0.1}}
for _, c in ipairs(CRAFTS) do
    for _, rank in ipairs({"P", "K", "M"}) do          -- (a fixed order: the file is the same every build)
        local r = PILOTS[rank]
        local text = "TEXT_JEDI_FIGHTER_" .. c[1] .. "_" .. rank
        texts[text] = r[5] .. "'s " .. c[3]
        for _, level in ipairs(LEVELS) do
            fighter("Jedi_Fighter_" .. c[1] .. "_" .. rank .. level[1], c[2], text, r[1] * level[2], r[2] * level[2],
                r[3] + level[3], r[4])
        end
        if rank ~= "P" then                       -- _C: a Jedi Commander (the third teaching: the first two with it)
            fighter("Jedi_Fighter_" .. c[1] .. "_" .. rank .. "_C", c[2], text, r[1] * 1.2, r[2] * 1.2, r[3] + 0.1, r[4], 0.1)
        end
    end
end
for _, h in ipairs(HERO_CRAFTS) do
    local body = body_of(h[2])
    local health = tonumber(body:match("<Tactical_Health>%s*([%d%.]+)") or "220")
    local shields = tonumber(body:match("<Shield_Points>%s*([%d%.]+)") or "160")
    local text = "TEXT_JEDI_FIGHTER_" .. h[1]
    texts[text] = h[3]
    for _, level in ipairs(LEVELS) do
        fighter("Jedi_Fighter_" .. h[1] .. level[1], h[2], text, health * level[2], shields * level[2], level[3], 0.35)
    end
    fighter("Jedi_Fighter_" .. h[1] .. "_C", h[2], text, health * 1.2, shields * 1.2, 0.1, 0.35, 0.1)
end
add("</Jedi_Units>")

return {["XML\\Jedi_Units.xml"] = lib.tidy_xml(lib.lines(xml)), texts = texts, count = {SLOTS}}
