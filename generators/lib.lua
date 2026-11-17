-- Shared helpers for the data generators. A generator reads the installed game files through the
-- host's `gen` table and returns {[output path] = file contents}. The same scripts run in build.py and
-- at game start (POWRPROF.dll), so both must give the same bytes:
--   gen.read(root, path)                       file contents or nil (root 0 = Thrawn's Data, 1 = game folder)
--   gen.list(root, folder, pattern, recursive)  file paths ("XML\\Planets.xml"), sorted by lower case path
--   gen.text(key)                              Thrawn's English text of a key (UTF-8) or nil
--   gen.load(name)                             another generator script's result (run once)
-- The order of pairs() differs between the two hosts: never let it decide what is written.
local lib = {}

-- XML copied out of the game's files, without its comments, trailing spaces and runs of blank lines.
function lib.tidy_xml(text)
    local nl = string.find(text, "\r\n", 1, true) and "\r\n" or "\n"
    text = string.gsub(string.gsub(text, "\r\n", "\n"), "<!%-%-.-%-%->", function(comment)
        local _, lines = string.gsub(comment, "\n", "\n")
        return "\0" .. string.rep("\n\0", lines)
    end)
    local out, last_blank = {}, true
    for raw in string.gmatch(text .. "\n", "([^\n]*)\n") do
        local marked = string.find(raw, "\0", 1, true)
        local line = string.gsub(string.gsub(raw, "\0", ""), "[ \t]+$", "")
        if not (marked and line == "") then
            local blank = line == ""
            if not (blank and last_blank) then
                out[#out + 1] = line
            end
            last_blank = blank
        end
    end
    while out[#out] == "" do
        out[#out] = nil
    end
    return table.concat(out, nl) .. nl
end

-- Python's round(): halves go to the even neighbour
function lib.round(x)
    local f = math.floor(x)
    local d = x - f
    if d > 0.5 or (d == 0.5 and f % 2 == 1) then
        f = f + 1
    end
    return math.tointeger(f) or f
end

-- UTF-8 text as Latin-1, "?" for every character outside it
function lib.latin1(s)
    if not s:find("[\128-\255]") then
        return s
    end
    local out = {}
    for _, c in utf8.codes(s, true) do
        out[#out + 1] = c < 256 and string.char(c) or "?"
    end
    return table.concat(out)
end

function lib.sorted_keys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

function lib.lines(lines)
    return table.concat(lines, "\r\n") .. "\r\n"
end

-- Python's \s and \w (the build used to match with Python's re), by code point
function lib.is_space(c)
    return c ~= nil and ((c >= 9 and c <= 13) or (c >= 28 and c <= 32) or c == 0x85 or c == 0xA0 or c == 0x1680
        or (c >= 0x2000 and c <= 0x200A) or c == 0x2028 or c == 0x2029 or c == 0x202F or c == 0x205F or c == 0x3000)
end

function lib.is_word(c)
    if c == nil then
        return false
    end
    if c < 128 then
        return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95
    end
    return c == 0xAA or c == 0xB2 or c == 0xB3 or c == 0xB5 or c == 0xB9 or c == 0xBA or (c >= 0xBC and c <= 0xBE)
        or (c >= 0xC0 and c <= 0x2AF and c ~= 0xD7 and c ~= 0xF7) or (c >= 0x370 and c <= 0x52F and c ~= 0x37E
        and c ~= 0x387 and c ~= 0x3F6 and c ~= 0x482)
end

function lib.codes(s)
    local cps = {}
    for _, c in utf8.codes(s, true) do
        cps[#cps + 1] = c
    end
    return cps
end

-- Python's str.strip() on UTF-8 text
function lib.strip(s)
    if not s:find("[\128-\255]") then
        return (s:gsub("^[%s\28-\31]+", ""):gsub("[%s\28-\31]+$", ""))
    end
    local cps = lib.codes(s)
    local a, b = 1, #cps
    while a <= b and lib.is_space(cps[a]) do
        a = a + 1
    end
    while b >= a and lib.is_space(cps[b]) do
        b = b - 1
    end
    return a > b and "" or utf8.char(table.unpack(cps, a, b))
end

-- Calls fn(tag, NAME, body) for each object <Tag Name="..."> ... </Tag> of an XML text in order, as
-- Python's re.finditer did with <(\w+)\s+Name="([^"]+)"[^>]*>(.*?)</\1>; tags (a set) limits the tags.
function lib.each_object(text, fn, tags)
    local pos = 1
    while true do
        local s, e, tag, name = text:find('<([%w_]+)%s+Name="([^"]+)"[^>]*>', pos)
        if not s then
            return
        end
        local close_s, close_e
        if not tags or tags[tag] then
            close_s, close_e = text:find("</" .. tag .. ">", e + 1, true)
        end
        if close_s then
            fn(tag, name:upper(), text:sub(e + 1, close_s - 1))
            pos = close_e + 1
        else
            pos = s + 1
        end
    end
end

-- Every object in Thrawn's XML: by_tag[tag][NAME] = body (the first of each name per tag),
-- any[NAME] = {tag, body} (the first of each name of any tag) and order: those names as first seen
local objects, any_objects, any_order
function lib.objects()
    if objects then
        return objects, any_objects, any_order
    end
    objects, any_objects, any_order = {}, {}, {}
    for _, path in ipairs(gen.list(0, "XML", "*.xml", "walk")) do
        lib.each_object(gen.read(0, path), function(tag, name, body)
            local of_tag = objects[tag]
            if not of_tag then
                of_tag = {}
                objects[tag] = of_tag
            end
            if not of_tag[name] then
                of_tag[name] = body
            end
            if not any_objects[name] then
                any_objects[name] = {tag, body}
                any_order[#any_order + 1] = name
            end
        end)
    end
    return objects, any_objects, any_order
end

-- The mod's own images the build drew (gen.data): uint32 width, height, then the pixels (RGBA, or L for a mask)
function lib.data_image(name, mode)
    local data = gen.data(name)
    if not data then
        error("missing data " .. name)
    end
    local w, h = string.unpack("<I4I4", data)
    return gen.img_frombytes(mode or "RGBA", w, h, data:sub(9))
end

-- the command bar atlas of Thrawn's Revenge: atlas.icon(name) -> RGBA image or nil, atlas.has(name)
local atlas
function lib.atlas()
    if atlas then
        return atlas
    end
    local mtd = gen.read(0, "Art\\Textures\\MT_commandbar.MTD")
    local where = {}
    local count = string.unpack("<I4", mtd)
    for i = 0, count - 1 do
        local o = 4 + 81 * i
        local name = mtd:sub(o + 1, o + 64):match("^[^%z]*"):upper()
        if not where[name] then
            where[name] = {string.unpack("<I4I4I4I4", mtd, o + 65)}
        end
    end
    local bmp
    atlas = {}
    function atlas.has(name)
        return where[name:upper()] ~= nil
    end
    function atlas.icon(name)
        local w = where[name:upper()]
        if not w then
            return nil
        end
        bmp = bmp or gen.read(0, "Art\\Textures\\MT_Commandbar.tga")
        return gen.img_from_bmp(bmp, w[1], w[2], w[3], w[4])
    end
    return atlas
end

-- A field of an object (<Tag> value </Tag>, trimmed), "" if it has none
function lib.field(body, tag)
    local value = body:match("<" .. tag .. ">%s*(.-)%s*</" .. tag .. ">")
    return value and lib.strip(value) or ""
end

-- A field of an object, else of the type it is a variant of (Variant_Of_Existing_Type), up to 6 steps
function lib.inherited(name, tag, depth)
    local _, any = lib.objects()
    local obj = any[name:upper()]
    depth = depth or 0
    if not obj or depth > 6 then
        return ""
    end
    local value = lib.field(obj[2], tag)
    if value ~= "" then
        return value
    end
    return lib.inherited(lib.field(obj[2], "Variant_Of_Existing_Type"), tag, depth + 1)
end

-- Thrawn's hyperlanes: lanes[PLANET] = {NEIGHBOUR = true}
local lanes
function lib.lanes()
    if lanes then
        return lanes
    end
    lanes = {}
    local function link(a, b)
        lanes[a] = lanes[a] or {}
        lanes[a][b] = true
    end
    for _, path in ipairs(gen.list(0, "XML", "TradeRoutes_*.xml", false)) do
        local text = gen.read(0, path)
        for pa, pb in text:gmatch("<Point_A>%s*([^<%s]+)%s*</Point_A>%s*<Point_B>%s*([^<%s]+)%s*</Point_B>") do
            local a, b = pa:upper(), pb:upper()
            link(a, b)
            link(b, a)
        end
    end
    return lanes
end

-- asin, atan and atan2 with only + - * / and sqrt (ports of fdlibm's), so both hosts compute the same bits
-- whatever their C library does
local function hi_word(x)
    local _, hi = string.unpack("<I4I4", string.pack("<d", x))
    return hi
end

local function with_hi(hi)
    return (string.unpack("<d", string.pack("<I4I4", 0, hi)))
end

local ASIN_975 = with_hi(0x3FEF3333)
local pS0, pS1, pS2 = 1.66666666666666657415e-01, -3.25565818622400915405e-01, 2.01212532134862925881e-01
local pS3, pS4, pS5 = -4.00555345006794114027e-02, 7.91534994289814532176e-04, 3.47933107596021167570e-05
local qS1, qS2 = -2.40339491173441421878e+00, 2.02094576023350569471e+00
local qS3, qS4 = -6.88283971605453293030e-01, 7.70381505559019352791e-02
local pio2_hi, pio2_lo, pio4_hi = 1.57079632679489655800e+00, 6.12323399573676603587e-17, 7.85398163397448278999e-01

function lib.asin(x)
    local ax = x < 0 and -x or x
    if ax >= 1.0 then
        if ax == 1.0 then
            return x * pio2_hi + x * pio2_lo
        end
        return 0 / 0
    end
    if ax < 0.5 then
        if ax < 2 ^ -27 then
            return x
        end
        local t = x * x
        local p = t * (pS0 + t * (pS1 + t * (pS2 + t * (pS3 + t * (pS4 + t * pS5)))))
        local q = 1.0 + t * (qS1 + t * (qS2 + t * (qS3 + t * qS4)))
        return x + x * (p / q)
    end
    local w = 1.0 - ax
    local t = w * 0.5
    local p = t * (pS0 + t * (pS1 + t * (pS2 + t * (pS3 + t * (pS4 + t * pS5)))))
    local q = 1.0 + t * (qS1 + t * (qS2 + t * (qS3 + t * qS4)))
    local s = math.sqrt(t)
    if ax >= ASIN_975 then
        t = pio2_hi - (2.0 * (s + s * (p / q)) - pio2_lo)
    else
        w = with_hi(hi_word(s))
        local c = (t - w * w) / (s + w)
        local r = p / q
        p = 2.0 * s * r - (pio2_lo - 2.0 * c)
        q = pio4_hi - 2.0 * w
        t = pio4_hi - (p - q)
    end
    return x > 0 and t or -t
end

local atanhi = {4.63647609000806093515e-01, 7.85398163397448278999e-01, 9.82793723247329054082e-01,
                1.57079632679489655800e+00}
local atanlo = {2.26987774529616870924e-17, 3.06161699786838301793e-17, 1.39033110312309984516e-17,
                6.12323399573676603587e-17}
local aT = {3.33333333333329318027e-01, -1.99999999998764832476e-01, 1.42857142725034663711e-01,
            -1.11111104054623557880e-01, 9.09088713343650656196e-02, -7.69187620504482999495e-02,
            6.66107313738753120669e-02, -5.83357013379057348645e-02, 4.97687799461593236017e-02,
            -3.65315727442169155270e-02, 1.62858201153657823623e-02}

function lib.atan(x)
    local negative = hi_word(x) >= 0x80000000
    local ax = negative and -x or x
    local id
    if ax >= 2 ^ 66 then
        return negative and -(atanhi[4] + atanlo[4]) or atanhi[4] + atanlo[4]
    end
    if ax < 0.4375 then
        if ax < 2 ^ -29 then
            return x
        end
        id = 0
    else
        x = ax
        if ax < 1.1875 then
            if ax < 0.6875 then
                id = 1
                x = (2.0 * x - 1.0) / (2.0 + x)
            else
                id = 2
                x = (x - 1.0) / (x + 1.0)
            end
        elseif ax < 2.4375 then
            id = 3
            x = (x - 1.5) / (1.0 + 1.5 * x)
        else
            id = 4
            x = -1.0 / x
        end
    end
    local z = x * x
    local w = z * z
    local s1 = z * (aT[1] + w * (aT[3] + w * (aT[5] + w * (aT[7] + w * (aT[9] + w * aT[11])))))
    local s2 = w * (aT[2] + w * (aT[4] + w * (aT[6] + w * (aT[8] + w * aT[10]))))
    if id == 0 then
        return x - x * (s1 + s2)
    end
    z = atanhi[id] - ((x * (s1 + s2) - atanlo[id]) - x)
    return negative and -z or z
end

-- exp (fdlibm's) for |x| < 700, and tanh from it
local ln2HI = {6.93147180369123816490e-01, -6.93147180369123816490e-01}
local ln2LO = {1.90821492927058770002e-10, -1.90821492927058770002e-10}
local halF = {0.5, -0.5}
local invln2 = 1.44269504088896338700e+00
local P1, P2, P3 = 1.66666666666666019037e-01, -2.77777777770155933842e-03, 6.61375632143793436117e-05
local P4, P5 = -1.65339022054652515390e-06, 4.13813679705723846039e-08

function lib.exp(x)
    local hx = hi_word(x)
    local xsb = hx >= 0x80000000 and 2 or 1
    hx = hx & 0x7fffffff
    local hi, lo, k = 0, 0, 0
    if hx > 0x3fd62e42 then
        if hx < 0x3FF0A2B2 then
            hi = x - ln2HI[xsb]
            lo = ln2LO[xsb]
            k = xsb == 1 and 1 or -1
        else
            local v = invln2 * x + halF[xsb]
            k = v >= 0 and math.floor(v) or math.ceil(v)
            hi = x - k * ln2HI[1]
            lo = k * ln2LO[1]
        end
        x = hi - lo
    elseif hx < 0x3e300000 then
        return 1.0 + x
    end
    local t = x * x
    local c = x - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))))
    if k == 0 then
        return 1.0 - ((x * c) / (c - 2.0) - x)
    end
    local y = 1.0 - ((lo - (x * c) / (2.0 - c)) - hi)
    return y * with_hi((0x3ff + k) << 20)
end

function lib.tanh(x)
    if x < 0 then
        return -lib.tanh(-x)
    end
    local t = lib.exp(2 * x)
    return (t - 1) / (t + 1)
end

local pi_o_2, pi_lo, PI = 1.5707963267948965580E+00, 1.2246467991473531772E-16, 3.1415926535897931160E+00

function lib.atan2(y, x)
    if x == 1.0 then
        return lib.atan(y)
    end
    local hy, hx = hi_word(y), hi_word(x)
    local m = (hy >= 0x80000000 and 1 or 0) + (hx >= 0x80000000 and 2 or 0)
    if y == 0 then
        if m < 2 then
            return y
        end
        return m == 2 and PI + 1e-300 or -PI - 1e-300
    end
    if x == 0 then
        return hy >= 0x80000000 and -pi_o_2 - 1e-300 or pi_o_2 + 1e-300
    end
    local k = ((hy & 0x7fffffff) - (hx & 0x7fffffff)) // (1 << 20)
    local z
    if k > 60 then
        z = pi_o_2 + 0.5 * pi_lo
    elseif hx >= 0x80000000 and k < -60 then
        z = 0.0
    else
        z = lib.atan(math.abs(y / x))
    end
    if m == 0 then
        return z
    elseif m == 1 then
        return -z
    elseif m == 2 then
        return PI - (z - pi_lo)
    end
    return (z - pi_lo) - PI
end

-- Art by file name, like the game finds it: Thrawn's loose Art\Models and Art\Textures first, then the base
-- game's archives (Forces of Corruption's, then Empire at War's). files:read(name) -> bytes or nil
local ARCHIVES = {"corruption\\Data\\models.meg", "corruption\\Data\\textures.meg", "GameData\\Data\\models.meg",
                  "GameData\\Data\\textures.meg"}

local function base_name(path)
    return (path:match("([^\\/]+)$") or path):upper()
end

-- {NAME = {archive, start, size}} of a MEG (v1) archive, the first entry of a name winning
local function meg_index(archive, index)
    local head = gen.read_range(1, archive, 0, 8)
    if not head or #head < 8 then
        return
    end
    local names_count, files_count = string.unpack("<I4I4", head)
    local pos, chunk, chunk_at = 8, "", 8
    local function bytes(n)
        while pos + n > chunk_at + #chunk do
            local more = gen.read_range(1, archive, chunk_at + #chunk, 1 << 20)
            if not more or more == "" then
                error("broken archive " .. archive)
            end
            chunk = chunk .. more
        end
        local out = chunk:sub(pos - chunk_at + 1, pos - chunk_at + n)
        pos = pos + n
        return out
    end
    local names = {}
    for i = 1, names_count do
        local n = string.unpack("<I2", bytes(2))
        names[i] = bytes(n)
    end
    local table_data = gen.read_range(1, archive, pos, 20 * files_count)
    for i = 0, files_count - 1 do
        local _, _, size, start, name_index = string.unpack("<I4I4I4I4I4", table_data, 20 * i + 1)
        local key = base_name(names[name_index + 1]:gsub("/", "\\"))
        if not index[key] then
            index[key] = {archive, start, size}
        end
    end
end

-- {NAME = {archive, start, size}} of one archive (root 1: under the game folder)
function lib.meg_index(archive)
    local index = {}
    meg_index(archive, index)
    return index
end

local files
function lib.game_files()
    if files then
        return files
    end
    local loose, archived = {}, {}
    for _, folder in ipairs({"Art\\Models", "Art\\Textures"}) do
        for _, path in ipairs(gen.list(0, folder, "*", false)) do
            local key = base_name(path)
            if not loose[key] then
                loose[key] = path
            end
        end
    end
    for _, archive in ipairs(ARCHIVES) do
        meg_index(archive, archived)
    end
    files = {}
    function files:read(name)
        local key = name:upper()
        if not loose[key] and not archived[key] and key:find("%.") then      -- the engine swaps .tga / .dds
            local stem, ext = key:match("^(.*)%.([^%.]*)$")
            local other = stem .. (ext == "TGA" and ".DDS" or ".TGA")
            if loose[other] or archived[other] then
                key = other
            end
        end
        if loose[key] then
            return gen.read(0, loose[key])
        end
        local a = archived[key]
        return a and gen.read_range(1, a[1], a[2], a[3])
    end
    return files
end

return lib
