-- Imperial Intelligence's generic agents: Court_Operatives.xml (stealthy, unable to invade, they report on the
-- world they stand at; one unit type each, renamed in game; ranks II-V carry their rank's icon; an agent with the
-- Experimental Starship Hyperdrive trait flies a vessel twice as fast as the landing craft), their icons per rank
-- (i_button_court_op_<n>.tga: Thrawn's infiltrator icon with the numeral) and CourtGarrisons.lua: the buildings
-- that raise troops in land battles (for bribery).
local lib = gen.load("lib")

local OPERATIVES, RANKS = 6, 5

local _, objects, order = lib.objects()
for _, base in ipairs({"BOTHAN_SPY", "BOTHAN_SPY_COMPANY", "IMPERIAL_LANDING_CRAFT_NONCOMBAT"}) do
    if not objects[base] then
        error("court operatives: " .. base .. " is not a Thrawn's Revenge object")
    end
end

local function field(obj, tag, depth)
    local entry = objects[obj:upper()]
    depth = depth or 0
    if not entry or depth > 8 then
        return ""
    end
    local v = entry[2]:match("<" .. tag .. ">%s*([^<]-)%s*</" .. tag .. ">")
    if v and v ~= "" then
        return v
    end
    local parent = entry[2]:match("<Variant_Of_Existing_Type>%s*([^<%s]+)")
    return parent and field(parent, tag, depth + 1) or ""
end

-- the operatives' icon per rank: the galaxy map shows an agent's rank (its numeral bottom right)
local icons = {}
local src = gen.list(0, "Art\\Textures\\Icons", "i_button_ISB_infiltrator.tga", false)[1]
    or gen.list(0, "Art\\Textures", "i_button_ISB_infiltrator.tga", false)[1]
local base = src and gen.img_convert(gen.img_open(gen.read(0, src)), "RGBA") or lib.data_image("court_silhouette_1")
for r = 1, RANKS do
    local im = gen.img_copy(base)
    local w, h = gen.img_size(im)
    local numeral = lib.data_image("court_rank_" .. r)
    local nw0, nh0 = gen.img_size(numeral)
    local nw = math.max(8, w * 11 // 20)
    numeral = gen.img_resize(numeral, nw, nw * nh0 // nw0, "lanczos")
    local x0, y0, x1, y1 = gen.img_getbbox(numeral)
    if not x0 then
        x0, y0, x1, y1 = 0, 0, gen.img_size(numeral)
    end
    numeral = gen.img_crop(numeral, x0, y0, x1, y1)
    local cw, ch = gen.img_size(numeral)
    gen.img_alpha_composite(im, numeral, w - cw - 1, h - ch - 1)
    icons["i_button_court_op_" .. r .. ".tga"] = im
end

local texts = {TEXT_COURT_OPERATIVE = "Imperial Operative", TEXT_COURT_OPERATIVE_CLASS = "Imperial Operative",
               TEXT_COURT_OPERATIVE_DESC = "An agent of Imperial Intelligence. Unseen by most, it reports on the world "
                   .. "where it stands and runs covert operations from the Internal Affairs window."}
local xml = {'<?xml version="1.0" encoding="utf-8"?>', "<Court_Operatives>",
    "\t<GroundInfantry Name=\"Court_Operative_Agent\">\n"
    .. "\t\t<Variant_Of_Existing_Type>Bothan_Spy</Variant_Of_Existing_Type>\n"
    .. "\t\t<Text_ID>TEXT_COURT_OPERATIVE</Text_ID>\n"
    .. "\t\t<Encyclopedia_Text>TEXT_COURT_OPERATIVE_DESC</Encyclopedia_Text>\n"
    .. "\t\t<Encyclopedia_Unit_Class>TEXT_COURT_OPERATIVE_CLASS</Encyclopedia_Unit_Class>\n"
    .. "\t\t<Icon_Name>i_button_court_op_1.tga</Icon_Name>\n"
    .. "\t\t<Can_Hyperspace_Without_Activating_Ability>Yes</Can_Hyperspace_Without_Activating_Ability>\n"
    .. "\t\t<Abilities SubObjectList=\"Yes\">\n"
    .. "\t\t\t<Galactic_Stealth_Ability Name=\"Spy_Galactic_Stealth\">\n"
    .. "\t\t\t\t<Evade_Detection_Chance>0.0</Evade_Detection_Chance>\n"
    .. "\t\t\t</Galactic_Stealth_Ability>\n"
    .. "\t\t\t<System_Spy_Ability Name=\"Spy_System\">\n"
    .. "\t\t\t\t<Initially_Enabled>Yes</Initially_Enabled>\n"
    .. "\t\t\t\t<Activation_Style>Galactic_Automatic</Activation_Style>\n"
    .. "\t\t\t\t<Causes_Despawn>No</Causes_Despawn>\n"
    .. "\t\t\t\t<Duration_In_Secs>-1.0</Duration_In_Secs>\n"
    .. "\t\t\t\t<See_Num_Fleets>Yes</See_Num_Fleets>\n"
    .. "\t\t\t\t<See_Fleet_Contents>Yes</See_Fleet_Contents>\n"
    .. "\t\t\t\t<See_Num_Ground_Companies>Yes</See_Num_Ground_Companies>\n"
    .. "\t\t\t\t<See_Special_Structures>Yes</See_Special_Structures>\n"
    .. "\t\t\t\t<See_Minor_Stealth_Heroes>Yes</See_Minor_Stealth_Heroes>\n"
    .. "\t\t\t\t<See_Major_Stealth_Heroes>Yes</See_Major_Stealth_Heroes>\n"
    .. "\t\t\t</System_Spy_Ability>\n"
    .. "\t\t</Abilities>\n"
    .. "\t</GroundInfantry>"}
local speed = tonumber(field("IMPERIAL_LANDING_CRAFT_NONCOMBAT", "Hyperspace_Speed")) or 1.5
xml[#xml + 1] = "\t<TransportUnit Name=\"Court_Agent_Vessel\">\n"
    .. "\t\t<Variant_Of_Existing_Type>Imperial_Landing_Craft_Noncombat</Variant_Of_Existing_Type>\n"
    .. "\t\t<Hyperspace_Speed>" .. string.format("%g", speed * 2) .. "</Hyperspace_Speed>\n"
    .. "\t</TransportUnit>"
for n = 1, OPERATIVES do
    texts["TEXT_COURT_OPERATIVE_" .. n] = "Operative " .. n
    xml[#xml + 1] = "\t<GroundInfantry Name=\"Court_Operative_Agent_" .. n .. "\">\n"
        .. "\t\t<Variant_Of_Existing_Type>Court_Operative_Agent</Variant_Of_Existing_Type>\n"
        .. "\t\t<Text_ID>TEXT_COURT_OPERATIVE_" .. n .. "</Text_ID>\n"
        .. "\t</GroundInfantry>"
    xml[#xml + 1] = "\t<GroundCompany Name=\"Court_Operative_" .. n .. "\">\n"
        .. "\t\t<Variant_Of_Existing_Type>Bothan_Spy_Company</Variant_Of_Existing_Type>\n"
        .. "\t\t<Text_ID>TEXT_COURT_OPERATIVE_" .. n .. "</Text_ID>\n"
        .. "\t\t<Encyclopedia_Text>TEXT_COURT_OPERATIVE_DESC</Encyclopedia_Text>\n"
        .. "\t\t<Encyclopedia_Unit_Class>TEXT_COURT_OPERATIVE_CLASS</Encyclopedia_Unit_Class>\n"
        .. "\t\t<Icon_Name>i_button_court_op_1.tga</Icon_Name>\n"
        .. "\t\t<Company_Units>Court_Operative_Agent_" .. n .. "</Company_Units>\n"
        .. "\t\t<Company_Transport_Unit>Imperial_Landing_Craft_Noncombat</Company_Transport_Unit>\n"
        .. "\t\t<Affiliation>Empire</Affiliation>\n"
        .. "\t\t<Build_Initially_Locked>Yes</Build_Initially_Locked>\n"
        .. "\t\t<Tech_Level>99</Tech_Level>\n"
        .. "\t</GroundCompany>"
    xml[#xml + 1] = "\t<GroundCompany Name=\"Court_Operative_Fast_" .. n .. "\">\n"
        .. "\t\t<Variant_Of_Existing_Type>Court_Operative_" .. n .. "</Variant_Of_Existing_Type>\n"
        .. "\t\t<Company_Transport_Unit>Court_Agent_Vessel</Company_Transport_Unit>\n"
        .. "\t</GroundCompany>"
    for r = 2, RANKS do
        xml[#xml + 1] = "\t<GroundInfantry Name=\"Court_Operative_Agent_" .. n .. "_R" .. r .. "\">\n"
            .. "\t\t<Variant_Of_Existing_Type>Court_Operative_Agent_" .. n .. "</Variant_Of_Existing_Type>\n"
            .. "\t\t<Icon_Name>i_button_court_op_" .. r .. ".tga</Icon_Name>\n"
            .. "\t</GroundInfantry>\n"
            .. "\t<GroundCompany Name=\"Court_Operative_" .. n .. "_R" .. r .. "\">\n"
            .. "\t\t<Variant_Of_Existing_Type>Court_Operative_" .. n .. "</Variant_Of_Existing_Type>\n"
            .. "\t\t<Icon_Name>i_button_court_op_" .. r .. ".tga</Icon_Name>\n"
            .. "\t\t<Company_Units>Court_Operative_Agent_" .. n .. "_R" .. r .. "</Company_Units>\n"
            .. "\t</GroundCompany>\n"
            .. "\t<GroundCompany Name=\"Court_Operative_Fast_" .. n .. "_R" .. r .. "\">\n"
            .. "\t\t<Variant_Of_Existing_Type>Court_Operative_Fast_" .. n .. "</Variant_Of_Existing_Type>\n"
            .. "\t\t<Icon_Name>i_button_court_op_" .. r .. ".tga</Icon_Name>\n"
            .. "\t\t<Company_Units>Court_Operative_Agent_" .. n .. "_R" .. r .. "</Company_Units>\n"
            .. "\t</GroundCompany>"
    end
end
xml[#xml + 1] = "</Court_Operatives>"

-- the buildings that raise troops in land battles (Starting/Reserve_Spawned_Units), through their variants
local function spawns(obj, depth)
    local entry = objects[obj]
    depth = depth or 0
    if not entry or depth > 8 then
        return false
    end
    if entry[2]:find("<Starting_Spawned_Units_Tech_%d+>") or entry[2]:find("<Reserve_Spawned_Units_Tech_%d+>") then
        return true
    end
    local parent = entry[2]:match("<Variant_Of_Existing_Type>%s*([^<%s]+)")
    return parent and spawns(parent:upper(), depth + 1) or false
end
local STRUCTURES = {SpecialStructure = true, SecondaryStructure = true, Generic_Structure = true, GroundBuildable = true}
local garrisons = {}
for _, obj in ipairs(order) do
    if STRUCTURES[objects[obj][1]] and spawns(obj) then
        garrisons[obj] = true
    end
end
local lua = {"return {"}
local count = 0
for _, g in ipairs(lib.sorted_keys(garrisons)) do
    count = count + 1
    if g:find("^[A-Z_][A-Z0-9_]*$") then
        lua[#lua + 1] = "    " .. g .. " = true,"
    end
end
lua[#lua + 1] = "}"

return {
    ["XML\\Court_Operatives.xml"] = lib.tidy_xml(lib.lines(xml)),
    ["Scripts\\Library\\eawx-plugins\\imperial-court\\CourtGarrisons.lua"] = lib.lines(lua),
    icons = icons, texts = texts, count = {OPERATIVES, count},
}
