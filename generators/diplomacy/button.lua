-- The Diplomacy panel button (dp_btn_diplomacy.tga, _sel): Thrawn's gold documentation ring from its government
-- button, with the mod's centre (three worlds linked around a star) pasted in through its round mask.
local lib = gen.load("lib")

local atlas = lib.atlas()
local centre, mask = lib.data_image("diplomacy_button_centre"), lib.data_image("diplomacy_button_mask", "L")
local icons = {}
for name, ring in pairs({["dp_btn_diplomacy.tga"] = "I_BUTTON_DOCUMENTATION_GOVERNMENT.TGA",
                         ["dp_btn_diplomacy_sel.tga"] = "I_BUTTON_DOCUMENTATION_GOVERNMENT_SELECTED.TGA"}) do
    local out = gen.img_resize(gen.img_convert(atlas.icon(ring), "RGBA"), 128, 128, "lanczos")
    gen.img_paste(out, centre, 0, 0, mask)
    icons[name] = out
end
return {icons = icons}
