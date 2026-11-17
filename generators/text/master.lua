-- Text\MasterTextFile_ENGLISH.dat: Thrawn's English text with the mod's added. Those come from the build
-- (gen.data "strings_mod"); the texts made from Thrawn's own (the vassal and warlord factions' names, the court
-- heroes' class lines, the rebellion battles' loading texts) are made here from the player's files.
-- .dat: uint32 count; count x (crc32(key), value length, key length) sorted by crc; the values (UTF-16LE);
-- the keys (ASCII), both in record order.
local lib = gen.load("lib")

local CRC = {}
for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
        c = (c & 1) ~= 0 and (0xEDB88320 ~ (c >> 1)) or (c >> 1)
    end
    CRC[i] = c
end
local function crc32(s)
    local c = 0xFFFFFFFF
    for i = 1, #s do
        c = CRC[(c ~ s:byte(i)) & 0xFF] ~ (c >> 8)
    end
    return c ~ 0xFFFFFFFF
end

local function utf16(s)
    local out, n = {}, 0
    for _, c in utf8.codes(s, true) do
        if c >= 0x10000 then
            c = c - 0x10000
            out[#out + 1] = string.pack("<I2I2", 0xD800 + (c >> 10), 0xDC00 + (c & 0x3FF))
        else
            out[#out + 1] = string.pack("<I2", c)
        end
        n = n + 1
    end
    return table.concat(out), n
end

local entries, by_key = {}, {}
local function set(key, value, length)
    local e = {crc32(key), key, value, length}
    if by_key[key] then
        entries[by_key[key]] = e
    else
        entries[#entries + 1] = e
        by_key[key] = #entries
    end
end

-- Thrawn's own
local dat = gen.read(0, "Text\\MasterTextFile_ENGLISH.dat")
local count = string.unpack("<I4", dat)
local pos = 4 + 12 * count + 1
local values = {}
for i = 0, count - 1 do
    local crc, vlen = string.unpack("<I4I4", dat, 4 + 12 * i + 1)
    values[i + 1] = {crc, dat:sub(pos, pos + 2 * vlen - 1), vlen}
    pos = pos + 2 * vlen
end
for i = 0, count - 1 do
    local klen = string.unpack("<I4", dat, 4 + 12 * i + 9)
    local key = dat:sub(pos, pos + klen - 1)
    pos = pos + klen
    entries[#entries + 1] = {values[i + 1][1], key, values[i + 1][2], values[i + 1][3]}
    by_key[key] = #entries
end

-- the mod's texts
local added = gen.data("strings_mod")
local n = string.unpack("<I4", added)
pos = 5
for _ = 1, n do
    local klen = string.unpack("<I2", added, pos)
    local key = added:sub(pos + 2, pos + 1 + klen)
    local vlen = string.unpack("<I4", added, pos + 2 + klen)
    local value = added:sub(pos + 6 + klen, pos + 5 + klen + 2 * vlen)
    pos = pos + 6 + klen + 2 * vlen
    set(key, value, vlen)
end

-- made from Thrawn's text: the court heroes' class lines (each its own text, so the court can add a lord's posts
-- to it in game), and the vassal, warlord and other new factions' names
for unit, class in pairs(gen.load("court/lore").classes) do
    set("TEXT_COURT_CLASS_" .. unit, utf16(class))
end
for key, value in pairs(gen.load("diplomacy/factions").texts) do
    set(key, utf16(value))
end
-- every land map's loading screen title and description, for rebellion battles (only where Thrawn has none)
for _, path in ipairs(gen.list(0, "XML", "Planets*.xml", false)) do
    for ted in gen.read(0, path):gmatch("<Land_Tactical_Map>%s*([^<%s]+)%s*</Land_Tactical_Map>") do
        local base = (ted:lower():sub(-4) == ".ted" and ted:sub(1, -5) or ted):upper()
        if not by_key["MT" .. base] then
            set("MT" .. base, utf16("Rebellion"))
        end
        if not by_key["MB" .. base] then
            set("MB" .. base, utf16("The people have risen against your rule. Destroy every rebel force, or the "
                                    .. "world is lost."))
        end
    end
end

-- campaigns that begin in the Alliance of Free Planets' time (4 and 6 ABY, before the New Republic is founded): their
-- intro speeches speak of the Alliance's military
local ALLIANCE_ERA = {"TEXT_CONQUEST_LAMBDASECTOR_"}
local alliance = {}
for key in pairs(by_key) do
    for _, prefix in ipairs(ALLIANCE_ERA) do
        if key:sub(1, #prefix) == prefix then
            alliance[#alliance + 1] = key
        end
    end
end
for _, key in ipairs(alliance) do
    local text = gen.text(key)
    local new, n = (text or ""):gsub("New Republic ([Mm]ilitary)", "Alliance %1")
    if n > 0 then
        set(key, utf16(new))
    end
end

table.sort(entries, function(a, b) return a[1] < b[1] end)
local head, vals, keys = {string.pack("<I4", #entries)}, {}, {}
for i, e in ipairs(entries) do
    head[#head + 1] = string.pack("<I4I4I4", e[1], e[4], #e[2])
    vals[i] = e[3]
    keys[i] = e[2]
end
return {["Text\\MasterTextFile_ENGLISH.dat"] = table.concat(head) .. table.concat(vals) .. table.concat(keys)}
