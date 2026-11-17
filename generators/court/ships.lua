-- The Admiralty's flagships: Court_Ships.xml (the pools' hero types, variants of Imperial ships, and the lore
-- characters' flagships from court/lore) and CourtShips.lua (the pools, prices and classes). An officer
-- appointed Grand Admiral, Admiral or Captain who has no hero unit of their own commands one of these,
-- named in game after them.
local lib = gen.load("lib")

-- rank -> how many, the base types (in turn), the encyclopedia class
local SHIPS = {
    {"G", 3, {"IMPERIAL_II_STAR_DESTROYER"}, "GRAND_ADMIRAL"},
    {"M", 8, {"IMPERIAL_I_STAR_DESTROYER", "VICTORY_I_STAR_DESTROYER", "VICTORY_II_STAR_DESTROYER"}, "ADMIRAL"},
    {"V", 10, {"CARRACK_CRUISER", "STRIKE_CRUISER", "LANCER_FRIGATE"}, "CAPTAIN"},
    -- the Supreme Commander of the Fleet: an Allegiance, or an Imperial II while the Allegiance is locked
    {"S", 2, {"ALLEGIANCE_BATTLECRUISER", "IMPERIAL_II_STAR_DESTROYER"}, "SUPREME_COMMANDER"},
}
local CLASS = {IMPERIAL_II_STAR_DESTROYER = "Imperial II Star Destroyer",
               IMPERIAL_I_STAR_DESTROYER = "Imperial I Star Destroyer",
               VICTORY_I_STAR_DESTROYER = "Victory I Star Destroyer",
               VICTORY_II_STAR_DESTROYER = "Victory II Star Destroyer",
               CARRACK_CRUISER = "Carrack cruiser", STRIKE_CRUISER = "Strike Cruiser",
               LANCER_FRIGATE = "Lancer frigate", ALLEGIANCE_BATTLECRUISER = "Allegiance battlecruiser"}

local _, objects = lib.objects()

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

local xml = {'<?xml version="1.0" encoding="utf-8"?>', "<Court_Ships>"}
local lua = {"return {", "    pools = {"}
local prices, classes, texts, total = {}, {}, {}, 0
for _, s in ipairs(SHIPS) do
    local rank, count, bases, cls = s[1], s[2], s[3], s[4]
    local names = {}
    for n = 1, count do
        local base = bases[(n - 1) % #bases + 1]
        if not objects[base:upper()] then
            error("court ships: " .. base .. " is not a Thrawn's Revenge object")
        end
        local name = "Court_Ship_" .. rank .. n
        local price = math.floor(tonumber(field(base, "Build_Cost_Credits")) or 0)
        if price <= 0 then
            error("court ships: no build cost for " .. base)
        end
        prices[#prices + 1] = string.format("        %s = %d,", name:upper(), price)
        classes[#classes + 1] = string.format('        %s = "%s",', name:upper(), CLASS[base] or "warship")
        local text_id = "TEXT_COURT_SHIP_" .. rank .. n
        local mask = field(base, "CategoryMask")
        if mask == "" then mask = "Capital" end
        local parts = {}
        for piece in mask:gmatch("[^|]+") do
            local p = lib.strip(piece)
            if p ~= "" and p ~= "SpaceHero" then parts[#parts + 1] = p end
        end
        texts[text_id] = "Imperial Flagship"
        xml[#xml + 1] = "\t<UniqueUnit Name=\"" .. name .. "\">\n"
            .. "\t\t<Variant_Of_Existing_Type>" .. base .. "</Variant_Of_Existing_Type>\n"
            .. "\t\t<Is_Named_Hero>Yes</Is_Named_Hero>\n"
            .. "\t\t<Text_ID>" .. text_id .. "</Text_ID>"
            .. (cls and "\n\t\t<Encyclopedia_Unit_Class> TEXT_ENCYCLOPEDIA_CLASS_" .. cls .. " </Encyclopedia_Unit_Class>" or "")
            .. "\n\t\t<CategoryMask> SpaceHero | " .. table.concat(parts, " | ") .. " </CategoryMask>\n"
            .. "\t\t<Tech_Level>99</Tech_Level>\n"
            .. "\t\t<Icon_Name>i_button_court_officer.tga</Icon_Name>\n"
            .. "\t\t<Show_Hero_Head>Yes</Show_Hero_Head>\n"
            .. "\t\t<Is_Sellable>Sellable_Never</Is_Sellable>\n"
            .. "\t\t<Affiliation>Independent_Forces</Affiliation>\n"
            .. "\t</UniqueUnit>"
        names[#names + 1] = '"' .. name:upper() .. '"'
        total = total + 1
    end
    lua[#lua + 1] = "        " .. rank .. " = {" .. table.concat(names, ", ") .. "},"
end
for _, flag in ipairs(gen.load("court/lore").flags) do
    xml[#xml + 1] = flag
    total = total + 1
end
xml[#xml + 1] = "</Court_Ships>"
lua[#lua + 1] = "    },"
lua[#lua + 1] = "    price = {"
for _, l in ipairs(prices) do lua[#lua + 1] = l end
lua[#lua + 1] = "    },"
lua[#lua + 1] = "    class = {"
for _, l in ipairs(classes) do lua[#lua + 1] = l end
lua[#lua + 1] = "    },"
lua[#lua + 1] = "}"

return {
    ["XML\\Court_Ships.xml"] = lib.tidy_xml(lib.lines(xml)),
    ["Scripts\\Library\\eawx-plugins\\imperial-court\\CourtShips.lua"] = lib.lines(lua),
    texts = texts, count = total,
}
