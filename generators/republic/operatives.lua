-- New Republic Intelligence's units: Republic_Operatives.xml.
-- Generic agents (stealthy, unable to invade, they report on the world they stand at; one unit type each, renamed
-- in game; ranks II-V carry their rank's icon; an agent with the Experimental Starship Hyperdrive trait flies a
-- vessel twice as fast as the shuttle) with their icons per rank (i_button_rep_op_<n>.tga: Thrawn's New Republic
-- infiltrator icon with the numeral), and the Bothan Spy the Republic builds to open a spy network (below).
local lib = gen.load("lib")

local OPERATIVES, RANKS = 6, 5

local _, objects = lib.objects()
for _, base in ipairs({"BOTHAN_SPY", "BOTHAN_SPY_COMPANY", "ALLIANCE_SHUTTLE_NONCOMBAT"}) do
    if not objects[base] then
        error("republic operatives: " .. base .. " is not a Thrawn's Revenge object")
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

-- the agents' icon per rank: the galaxy map shows an agent's rank (its numeral bottom right)
local icons = {}
local name = "i_button_nr_infiltrator.tga"
local src = gen.list(0, "Art\\Textures\\Icons", name, false)[1] or gen.list(0, "Art\\Textures", name, false)[1]
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
    icons["i_button_rep_op_" .. r .. ".tga"] = im
end

local texts = {TEXT_REPUBLIC_OPERATIVE = "NRI Agent", TEXT_REPUBLIC_OPERATIVE_CLASS = "New Republic Intelligence",
               TEXT_REPUBLIC_OPERATIVE_DESC = "An agent of New Republic Intelligence. Unseen by most, it reports on the "
                   .. "world where it stands and runs covert operations from the Republic window's Intelligence tab."}
local xml = {'<?xml version="1.0" encoding="utf-8"?>', "<Republic_Operatives>",
    "\t<GroundInfantry Name=\"Republic_Operative_Agent\">\n"
    .. "\t\t<Variant_Of_Existing_Type>Bothan_Spy</Variant_Of_Existing_Type>\n"
    .. "\t\t<Text_ID>TEXT_REPUBLIC_OPERATIVE</Text_ID>\n"
    .. "\t\t<Encyclopedia_Text>TEXT_REPUBLIC_OPERATIVE_DESC</Encyclopedia_Text>\n"
    .. "\t\t<Encyclopedia_Unit_Class>TEXT_REPUBLIC_OPERATIVE_CLASS</Encyclopedia_Unit_Class>\n"
    .. "\t\t<Icon_Name>i_button_rep_op_1.tga</Icon_Name>\n"
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
local speed = tonumber(field("ALLIANCE_SHUTTLE_NONCOMBAT", "Hyperspace_Speed")) or 1.5
xml[#xml + 1] = "\t<TransportUnit Name=\"Republic_Agent_Vessel\">\n"
    .. "\t\t<Variant_Of_Existing_Type>Alliance_Shuttle_Noncombat</Variant_Of_Existing_Type>\n"
    .. "\t\t<Hyperspace_Speed>" .. string.format("%g", speed * 2) .. "</Hyperspace_Speed>\n"
    .. "\t</TransportUnit>"
for n = 1, OPERATIVES do
    texts["TEXT_REPUBLIC_OPERATIVE_" .. n] = "Agent " .. n
    xml[#xml + 1] = "\t<GroundInfantry Name=\"Republic_Operative_Agent_" .. n .. "\">\n"
        .. "\t\t<Variant_Of_Existing_Type>Republic_Operative_Agent</Variant_Of_Existing_Type>\n"
        .. "\t\t<Text_ID>TEXT_REPUBLIC_OPERATIVE_" .. n .. "</Text_ID>\n"
        .. "\t</GroundInfantry>"
    xml[#xml + 1] = "\t<GroundCompany Name=\"Republic_Operative_" .. n .. "\">\n"
        .. "\t\t<Variant_Of_Existing_Type>Bothan_Spy_Company</Variant_Of_Existing_Type>\n"
        .. "\t\t<Text_ID>TEXT_REPUBLIC_OPERATIVE_" .. n .. "</Text_ID>\n"
        .. "\t\t<Encyclopedia_Text>TEXT_REPUBLIC_OPERATIVE_DESC</Encyclopedia_Text>\n"
        .. "\t\t<Encyclopedia_Unit_Class>TEXT_REPUBLIC_OPERATIVE_CLASS</Encyclopedia_Unit_Class>\n"
        .. "\t\t<Icon_Name>i_button_rep_op_1.tga</Icon_Name>\n"
        .. "\t\t<Company_Units>Republic_Operative_Agent_" .. n .. "</Company_Units>\n"
        .. "\t\t<Company_Transport_Unit>Alliance_Shuttle_Noncombat</Company_Transport_Unit>\n"
        .. "\t\t<Affiliation>Rebel</Affiliation>\n"
        .. "\t\t<Build_Initially_Locked>Yes</Build_Initially_Locked>\n"
        .. "\t\t<Tech_Level>99</Tech_Level>\n"
        .. "\t</GroundCompany>"
    xml[#xml + 1] = "\t<GroundCompany Name=\"Republic_Operative_Fast_" .. n .. "\">\n"
        .. "\t\t<Variant_Of_Existing_Type>Republic_Operative_" .. n .. "</Variant_Of_Existing_Type>\n"
        .. "\t\t<Company_Transport_Unit>Republic_Agent_Vessel</Company_Transport_Unit>\n"
        .. "\t</GroundCompany>"
    for r = 2, RANKS do
        xml[#xml + 1] = "\t<GroundInfantry Name=\"Republic_Operative_Agent_" .. n .. "_R" .. r .. "\">\n"
            .. "\t\t<Variant_Of_Existing_Type>Republic_Operative_Agent_" .. n .. "</Variant_Of_Existing_Type>\n"
            .. "\t\t<Icon_Name>i_button_rep_op_" .. r .. ".tga</Icon_Name>\n"
            .. "\t</GroundInfantry>\n"
            .. "\t<GroundCompany Name=\"Republic_Operative_" .. n .. "_R" .. r .. "\">\n"
            .. "\t\t<Variant_Of_Existing_Type>Republic_Operative_" .. n .. "</Variant_Of_Existing_Type>\n"
            .. "\t\t<Icon_Name>i_button_rep_op_" .. r .. ".tga</Icon_Name>\n"
            .. "\t\t<Company_Units>Republic_Operative_Agent_" .. n .. "_R" .. r .. "</Company_Units>\n"
            .. "\t</GroundCompany>\n"
            .. "\t<GroundCompany Name=\"Republic_Operative_Fast_" .. n .. "_R" .. r .. "\">\n"
            .. "\t\t<Variant_Of_Existing_Type>Republic_Operative_Fast_" .. n .. "</Variant_Of_Existing_Type>\n"
            .. "\t\t<Icon_Name>i_button_rep_op_" .. r .. ".tga</Icon_Name>\n"
            .. "\t\t<Company_Units>Republic_Operative_Agent_" .. n .. "_R" .. r .. "</Company_Units>\n"
            .. "\t</GroundCompany>"
    end
end
-- The Bothan Spy is Thrawn's own squad (its name, icon and tooltip), changed in Thrawn's Probe_Droids.xml: built at the
-- Republic's capital building, and its spy may travel in a fleet (used like a probe droid, its spy ability at the
-- destination uses it up). At Bothawui a twin of the squad (the same name and icon) can be recruited too; the
-- script locks the twin while the capital itself stands on Bothawui, so the build bar shows one.
local probe_path = gen.list(0, "XML\\Units", "Probe_Droids.xml", false)[1]
local probe_xml = probe_path and gen.read(0, probe_path)
if not probe_xml then
    error("republic operatives: Thrawn's Probe_Droids.xml is missing")
end
-- one tag of one object, in place (the object must hold the tag)
local function set_tag(text, kind, name, tag, value)
    local a = text:find("<" .. kind .. "%s+Name=\"" .. name .. "\"")
    local b = a and text:find("</" .. kind .. ">", a, true)
    if not b then
        error("republic operatives: " .. name .. " not found in Probe_Droids.xml")
    end
    local block = text:sub(a, b - 1)
    local patched, n = block:gsub("<" .. tag .. ">[^<]*</" .. tag .. ">", "<" .. tag .. ">" .. value .. "</" .. tag .. ">", 1)
    if n == 0 then
        error("republic operatives: " .. name .. " has no " .. tag)
    end
    return text:sub(1, a - 1) .. patched .. text:sub(b)
end
probe_xml = set_tag(probe_xml, "GroundInfantry", "Bothan_Spy", "Can_Hyperspace_Without_Activating_Ability", "Yes")
probe_xml = set_tag(probe_xml, "GroundCompany", "Bothan_Spy_Company", "Required_Special_Structures", "NewRep_Capital")
probe_xml = set_tag(probe_xml, "GroundCompany", "Bothan_Spy_Company", "Required_Star_Base_Level", "0")
xml[#xml + 1] = "\t<GroundCompany Name=\"Republic_Bothan_Spy_Bothawui\">\n"
    .. "\t\t<Variant_Of_Existing_Type>Bothan_Spy_Company</Variant_Of_Existing_Type>\n"
    .. "\t\t<Required_Special_Structures />\n"
    .. "\t\t<Required_Planets>Bothawui</Required_Planets>\n"
    .. "\t\t<Required_Star_Base_Level>0</Required_Star_Base_Level>\n"
    .. "\t</GroundCompany>"
xml[#xml + 1] = "</Republic_Operatives>"

return {
    ["XML\\Republic_Operatives.xml"] = lib.tidy_xml(lib.lines(xml)),
    [probe_path] = probe_xml,
    icons = icons, texts = texts, count = {OPERATIVES},
}
