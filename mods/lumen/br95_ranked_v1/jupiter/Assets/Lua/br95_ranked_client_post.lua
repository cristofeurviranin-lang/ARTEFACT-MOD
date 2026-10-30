-- BR95 Ranked for friends (Radmin / LAN): the match is run by the host's PC, so
-- the host's br95_ranked.gscc follows every other human and sends him HIS numbers
-- (client omnvars, flag ui_cash_squad_index_7 = 3). This file runs on every PC; it
-- only acts on those packets, so on the host it never does anything (the host's own
-- SR is written by br95_ranked.gscc itself).
-- The SR are computed here with the rules of br95_ranked.gscc and THIS player's rank:
--   kills: KO +5, elimination +5, assist +3, x gain % of the rank, nothing under the
--   minimum kills; placement SR (Top 12 +20 ... 1st +100); death fee per death;
--   deployment fee paid at the start (quitting = lost); result between -200 and the cap.
-- Packet: ui_armor_squad_index_4 packet number, _5 phase + 10 (1 start, 2 live, 3 end),
-- _6 eliminations, _7 KO; ui_cash_squad_index_4 placement, _5 assists, _6 deaths.
-- Files (jupiter/IO): br95_ranked.txt (profile), br95_ranked_live.txt (HUD, end screen,
-- history), br95_rp.txt, br95_streak.txt, br95_mode.txt (official ranked HUD).
if BR95RankedClient then return end
local state = { lastSeq = nil, active = false, skipped = false, finished = false }
BR95RankedClient = state

local DIR = "jupiter/IO/"
local PROFILE_FILE = DIR .. "br95_ranked.txt"
local LIVE_FILE = DIR .. "br95_ranked_live.txt"
local RP_FILE = DIR .. "br95_rp.txt"
local STREAK_FILE = DIR .. "br95_streak.txt"
local SETTINGS_FILE = DIR .. "br95_settings.txt"
local MODE_FILE = DIR .. "br95_mode.txt"
local FLAG = 3

-- rules of br95_ranked.gscc (division 0 Bronze .. 7 Top 250)
local START = { 0, 1000, 2000, 3500, 5000, 8000, 12000, 17000 }
local GAIN = { 300, 220, 140, 110, 85, 46, 50, 52 }
local MIN_KILLS = { 0, 0, 0, 3, 12, 35, 40, 50 }
local CAP = { 900, 750, 550, 400, 340, 260, 280, 320 }
local DEATH_FEE = { 0, 2, 3, 4, 5, 7, 10, 10 }
local FEES = { nil, { 10, 14, 18 }, { 23, 28, 33 }, { 39, 45, 51 }, { 60, 70, 80 }, { 90, 100, 110 } }
local MATCH_MIN = -200

local function readText(path)
    local text
    pcall(function()
        local f = io.open(path, "r")
        if f then text = f:read("*a"); f:close() end
    end)
    return text
end

local function writeText(path, text)
    return pcall(function()
        local f = io.open(path, "w")
        if not f then error("open") end
        f:write(text); f:close()
    end)
end

-- 1 Bronze .. 8 Top 250
local function division(sr)
    local d = 1
    for k = 1, #START do if sr >= START[k] then d = k end end
    return d
end

local function entryCost(sr)
    local d = division(sr)
    if d == 1 then return 0 end
    if d >= 7 then return math.min(295, 120 + math.floor((sr - 12000) / 500) * 25) end
    local tier = math.min(2, math.floor((sr - START[d]) * 3 / (START[d + 1] - START[d])))
    return FEES[d][tier + 1]
end

local function placementSR(place)
    if not place or place <= 0 then return 0 end
    if place == 1 then return 100 end
    if place <= 3 then return 80 end
    if place <= 5 then return 60 end
    if place <= 8 then return 40 end
    if place <= 12 then return 20 end
    return 0
end

local function matchGain(startSR, p)
    local d = division(startSR)
    local positive = math.floor((p.knocks * 5 + p.kills * 5 + p.assists * 3) * GAIN[d] / 100)
    if math.max(p.kills, p.knocks) < MIN_KILLS[d] then positive = 0 end
    positive = positive + placementSR(p.place)
    local gain = positive - p.deaths * DEATH_FEE[d]
    if gain < MATCH_MIN then gain = MATCH_MIN end
    if gain > CAP[d] then gain = CAP[d] end
    return gain
end

local function loadProfile()
    local p = { sr = 0, matches = 0, kills = 0, best = 0, last = 0 }
    local text = readText(PROFILE_FILE)
    if text then
        local sr, m, k, b, l = text:match("^BR95R1|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|END")
        if sr then
            p.sr, p.matches, p.kills, p.best, p.last = tonumber(sr), tonumber(m), tonumber(k), tonumber(b), tonumber(l)
        end
    end
    return p
end

local function saveProfile(p)
    writeText(PROFILE_FILE, "BR95R1|" .. p.sr .. "|" .. p.matches .. "|" .. p.kills .. "|" .. p.best .. "|" .. p.last .. "|END")
end

local function readRP()
    local text = readText(RP_FILE)
    return tonumber(text and text:match("^BR95P1|(%d+)|END")) or 0
end

local function rankedSettingOn()
    local text = readText(SETTINGS_FILE)
    return not (text and text:find("ranked=0", 1, true))
end

local function writeLive(sr, kills, deaths, delta, active)
    writeText(LIVE_FILE, "BR95L1|" .. sr .. "|" .. kills .. "|" .. deaths .. "|" .. delta .. "|" .. active .. "|END")
end

-- ---- packets ------------------------------------------------------------
local sources = {}
local function omn(name, controller)
    local ok, value = pcall(function()
        local source = sources[name]
        if not source then
            source = LUI.DataSourceFromOmnvar.new(name)
            sources[name] = source
        end
        return source:GetValue(controller)
    end)
    if ok and type(value) == "number" then return value end
    return nil
end

local function readPacket(controller)
    if omn("ui_cash_squad_index_7", controller) ~= FLAG then return nil end
    local seq = omn("ui_armor_squad_index_4", controller)
    if not seq or seq == 0 then return nil end
    return {
        seq = seq,
        phase = (omn("ui_armor_squad_index_5", controller) or 0) % 10,
        kills = omn("ui_armor_squad_index_6", controller) or 0,
        knocks = omn("ui_armor_squad_index_7", controller) or 0,
        place = omn("ui_cash_squad_index_4", controller) or 0,
        assists = omn("ui_cash_squad_index_5", controller) or 0,
        deaths = omn("ui_cash_squad_index_6", controller) or 0,
    }
end

-- first packet: the deployment fee is paid at once (quitting = losing it)
local function beginMatch(p)
    if not rankedSettingOn() then
        state.skipped = true
        writeLive(0, 0, 0, 0, 0)
        return
    end
    local prof = loadProfile()
    state.startSR = prof.sr
    state.cost = entryCost(prof.sr)
    prof.sr = math.max(0, prof.sr - state.cost)
    prof.matches = prof.matches + 1
    prof.last = 0 - state.cost
    saveProfile(prof)
    state.active = true
    -- the official ranked HUD of this PC shows (br95_ranked_official_post.lua)
    writeText(MODE_FILE, "BR95M1|1|RESURGENCE RANKED WARZONE|END")
    writeLive(prof.sr, 0, 0, prof.last, 1)
end

local function liveUpdate(p)
    if not state.active then return end
    local delta = matchGain(state.startSR, p) - state.cost
    writeLive(math.max(0, state.startSR + delta), p.kills, p.deaths, delta, 1)
end

-- last packet: the SR, the RP and the win streak (same rules as the host)
local function finishMatch(p)
    state.finished = true
    if not state.active then return end
    state.active = false
    local gain = matchGain(state.startSR, p)
    local prof = loadProfile()
    prof.sr = math.max(0, prof.sr + gain)
    prof.kills = prof.kills + p.kills
    if prof.sr > prof.best then prof.best = prof.sr end
    prof.last = gain - state.cost
    saveProfile(prof)

    local rp = p.kills * 3 + p.knocks + p.assists
    if gain > 0 then rp = rp + math.floor(gain / 8) end
    if division(prof.sr) > division(state.startSR) then rp = rp + 100 end
    local streak, best = 0, 0
    local text = readText(STREAK_FILE)
    if text then
        local a, b = text:match("^BR95W1|(%d+)|(%d+)|END")
        if a then streak, best = tonumber(a), tonumber(b) end
    end
    if prof.last > 0 then
        streak = streak + 1
        if streak > best then best = streak end
        rp = math.floor(rp * (100 + 10 * math.min(streak, 5)) / 100)
    else
        streak = 0
    end
    writeText(STREAK_FILE, "BR95W1|" .. streak .. "|" .. best .. "|END")
    writeText(RP_FILE, "BR95P1|" .. (readRP() + rp) .. "|END")
    -- active 0 = result not seen yet: the end screen of br95_ranked_hud_post.lua
    writeLive(prof.sr, p.kills, p.deaths, prof.last, 0)
end

local function poll()
    local inFront = false
    pcall(function() inFront = Engine.@InFrontend() end)
    if inFront then
        state.active, state.skipped, state.finished, state.lastSeq = false, false, false, nil
        return
    end
    local controller = 0
    pcall(function() controller = Engine.@GetFirstActiveController() end)
    local p = readPacket(controller)
    if not p or p.seq == state.lastSeq then return end
    state.lastSeq = p.seq
    if state.finished or state.skipped then return end
    -- an end packet without a start (left over from the previous match, or joined
    -- at the very end) is ignored
    if p.phase == 3 then
        if state.active then finishMatch(p) end
        return
    end
    if not state.active then beginMatch(p) end
    liveUpdate(p)
end

local function attach(root)
    if not root or root._br95Client then return end
    if LUI.primaryRoot and root ~= LUI.primaryRoot then return end
    root._br95Client = true
    local watch = LUI.UIElement.new(); watch.id = "BR95RankedClient"
    root:addElement(watch)
    watch:registerEventHandler("br95_client_tick", function() pcall(poll) end)
    watch:addElement(LUI.UITimer.new({ interval = 500, event = "br95_client_tick", disposable = false, eventTarget = watch }))
end

if LUI and LUI.UIRoot and type(LUI.UIRoot.init) == "function" then
    local original = LUI.UIRoot.init
    LUI.UIRoot.init = function(root, ...)
        local result = original(root, ...)
        pcall(attach, root)
        return result
    end
end
if LUI and LUI.roots then
    for _, root in pairs(LUI.roots) do pcall(attach, root) end
end
