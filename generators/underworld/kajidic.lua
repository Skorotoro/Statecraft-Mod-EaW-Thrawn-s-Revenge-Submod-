-- The Hutt families' art for the Kajidii window, from Thrawn's Hutt sigil and the patriarchs' portraits:
-- crests (dp_kcrest_<n>: the sigil recoloured in the family's colour on the mod's disc) and family cards
-- (dp_kcol_<n>, dp_kcol_<n>_sel; Art\Textures\dp_kcol_<n>_tree.tga: the portrait blurred and dimmed behind
-- the tier tree). The mod's own layers (backdrops, frames, lines, masks) come from the build (gen.data).
local lib = gen.load("lib")

local W, H = 186, 300                    -- a card
local atlas = lib.atlas()

-- the families: "r g b portrait" per line (the build's KAJIDII_ART)
local families = {}
for r, g, b, icon in gen.data("kajidii_families"):gmatch("(%d+) (%d+) (%d+) (%S+)") do
    families[#families + 1] = {{tonumber(r), tonumber(g), tonumber(b)}, icon}
end

local function lut(fn)
    local out = {}
    for v = 0, 255 do
        out[v + 1] = string.char(math.max(0, math.min(255, fn(v))))
    end
    return table.concat(out)
end

-- the sigil's olive strokes (the disc is grey) in the family's colour
local function crest(sigil, color, disc)
    local src = gen.img_bytes(gen.img_resize(gen.img_convert(sigil, "RGBA"), 64, 64, "lanczos"))
    local out = gen.img_bytes(disc)
    local pixels = {}
    for i = 1, #src, 4 do
        local r, g, b, a = src:byte(i, i + 3)
        local hi, lo = math.max(r, g, b), math.min(r, g, b)
        if a > 40 and hi - lo > 45 then
            local k = math.min(1.0, hi / 200)
            pixels[#pixels + 1] = string.char(math.floor(color[1] * (0.55 + 0.45 * k)),
                                              math.floor(color[2] * (0.55 + 0.45 * k)),
                                              math.floor(color[3] * (0.55 + 0.45 * k)), 255)
        else
            pixels[#pixels + 1] = out:sub(i, i + 3)
        end
    end
    local im = gen.img_copy(disc)
    gen.img_set_bytes(im, table.concat(pixels))
    return im
end

local icons, outputs = {}, {}
local sigil = atlas.icon("I_BUTTON_FACTION_HUTTS.TGA")
local dim = lut(function(v) return math.floor(v * 0.42) end)
for i, family in ipairs(families) do
    local color, portrait = family[1], family[2]
    local art = atlas.icon(portrait)
    local c = crest(sigil, color, lib.data_image("kcrest_disc_" .. i))
    icons["dp_kcrest_" .. i .. ".tga"] = c
    -- the tree card's portrait: blurred, dimmed, with a soft round edge (no square of background)
    local aw, ah = gen.img_size(art)
    local r, g, b, a = gen.img_split(gen.img_gaussian(gen.img_convert(art, "RGBA"), 4))
    a = gen.img_multiply(a, lib.data_image("kajidic_soft_mask_" .. aw .. "x" .. ah, "L"))
    local blurred = gen.img_merge("RGBA", {gen.img_point(r, dim), gen.img_point(g, dim), gen.img_point(b, dim), a})
    for _, v in ipairs({{false, "", art, false}, {true, "_sel", art, false}, {true, "_tree", blurred, true}}) do
        local sel, suffix, face, tree = v[1], v[2], v[3], v[4]
        local size = tree and 150 or 110
        local base = lib.data_image("kcol_base_" .. i .. suffix)
        local p = gen.img_resize(gen.img_convert(face, "RGBA"), size, size, "lanczos")
        gen.img_alpha_composite(base, p, W // 2 - size // 2, math.floor(H * 0.5) - size // 2)
        local card = gen.img_new("RGBA", W, H, 0, 0, 0, 0)
        gen.img_alpha_composite(card, base)
        gen.img_paste(card, lib.data_image("kcol_rim_" .. i .. suffix), 0, 0, lib.data_image("kcol_rimmask_" .. i .. suffix, "L"))
        if tree then                      -- a small crest left of the name, on the header above the rule
            gen.img_alpha_composite(card, gen.img_resize(c, 26, 26, "lanczos"), 12, 10)
            gen.img_alpha_composite(card, lib.data_image("kcol_lines_" .. i))
        else
            gen.img_alpha_composite(card, gen.img_resize(c, 46, 46, "lanczos"), W // 2 - 23, 7)
        end
        gen.img_alpha_composite(card, lib.data_image(sel and "kcol_frame_sel" or "kcol_frame"), W // 2 - 75, 258 - 13)
        if tree then
            outputs["Art\\Textures\\dp_kcol_" .. i .. "_tree.tga"] = gen.img_tga(card)
        else
            icons["dp_kcol_" .. i .. suffix .. ".tga"] = card
        end
    end
end
outputs.icons = icons
return outputs
