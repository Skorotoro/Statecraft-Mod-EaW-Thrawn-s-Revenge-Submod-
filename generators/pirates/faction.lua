-- The Pirates: a faction no player chooses, at war with everyone, holding the worlds the map gives it. One faction
-- block for the registry, copied from Thrawn's Warlords faction, in near-black (the faction's text a shade lighter,
-- so it stays readable and apart from the neutral grey).
local COLOR = {32, 32, 32}
local TEXT_COLOR = {64, 64, 64}

local function rgba(c)
    return string.format("%d, %d, %d, 255", c[1], c[2], c[3])
end

local factions_xml = gen.read(0, "XML\\Factions.xml")
local block = factions_xml:match('\t<Faction Name="Warlords">.-</Faction>')
block = block:gsub('Name="Warlords"', 'Name="Pirates"', 1):gsub("TEXT_FACTION_WARLORDS", "TEXT_FACTION_PIRATES")
for _, tag in ipairs({"Color", "No_Colorization_Color", "Selection_Blob_RGBA", "Display_Font_Color"}) do
    local value = tag == "Display_Font_Color" and rgba(TEXT_COLOR) or rgba(COLOR)
    block = block:gsub("<" .. tag .. ">[^<]*</" .. tag .. ">", function()
        return "<" .. tag .. "> " .. value .. " </" .. tag .. ">"
    end)
end

return {
    blocks = {block},
    listed = {{"Pirates", "TEXT_FACTION_PIRATES", "Pirates", COLOR}},
    texts = {TEXT_FACTION_PIRATES = "Pirates"},
}
