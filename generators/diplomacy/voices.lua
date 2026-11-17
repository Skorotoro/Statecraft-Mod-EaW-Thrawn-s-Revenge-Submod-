-- The Diplomacy window's voice clips that the engine cannot play as they are: Mon Mothma's campaign lines (the
-- base game's MP3s in EnglishSpeech.meg, decoded to WAV) and the Hutt laugh (Thrawn's Hutt_Boss_A3 at the
-- loudness of the other Hutt clips: about twice as loud, a soft limiter keeps the peaks). Written to
-- Audio\Diplomacy\ (the sound events in SFXEvents_Diplomacy.xml name them).
local lib = gen.load("lib")

local DIR = "Audio\\Diplomacy\\"

local function wav(pcm, channels, rate)
    return "RIFF" .. string.pack("<I4", 36 + #pcm) .. "WAVE" .. "fmt "
        .. string.pack("<I4I2I2I4I4I2I2", 16, 1, channels, rate, rate * channels * 2, channels * 2, 16)
        .. "data" .. string.pack("<I4", #pcm) .. pcm
end

local outputs = {}
local speech = lib.meg_index("GameData\\Data\\EnglishSpeech.meg")
for name in (gen.data("voices_speech") or ""):gmatch("%S+") do
    local entry = speech[name:upper()]
    if not entry then
        error("speech line missing: " .. name)
    end
    local pcm, channels, rate = gen.mp3_decode(gen.read_range(1, entry[1], entry[2], entry[3]))
    outputs[DIR .. name:gsub("%.[^%.]*$", "") .. ".wav"] = wav(pcm, channels, rate)
end

-- the Hutt laugh, louder
local src = gen.read(0, "Audio\\Heroes\\Hutt_Boss\\Attack\\Hutt_Boss_A3_ENG.wav")
local pos, fmt, data = 13, nil, nil
while pos + 8 <= #src do
    local id, size = src:sub(pos, pos + 3), string.unpack("<I4", src, pos + 4)
    if id == "fmt " then
        fmt = src:sub(pos + 8, pos + 7 + size)
    elseif id == "data" then
        data = src:sub(pos + 8, pos + 7 + size)
    end
    pos = pos + 8 + size + size % 2
end
local _, channels, rate, _, _, bits = string.unpack("<I2I2I4I4I2I2", fmt)
if bits ~= 16 then
    error("the Hutt laugh is not 16-bit")
end
local scale = lib.tanh(2.2)
local out = {}
for i = 1, #data - 1, 2 do
    local a = string.unpack("<i2", data, i) / 32768
    local v = lib.tanh(a * 2.2) / scale * 0.95 * 32767
    out[#out + 1] = string.pack("<i2", v >= 0 and math.floor(v) or math.ceil(v))
end
outputs[DIR .. "DP_Hutt_Laugh.wav"] = wav(table.concat(out), channels, rate)
return outputs
