-- BR95 Ranked core: the Lua half of the team referee (br95_ranked.gscc).
-- The game script sends, with free omnvars, what the SQUAD did (kills, deaths,
-- squads alive). This file runs on EVERY PC (host and friends), reads those
-- numbers and updates THIS PC's own profile with the rules of the player's own
-- rank: same team performance for everybody, SR won or lost depends on your rank.
--   ui_armor_squad_index_4 = packet number (written last)
--   ui_armor_squad_index_5 = phase (1 start, 2 live, 3 end) + 10 * humans in the squad
--   ui_armor_squad_index_6 = squad kills       ui_armor_squad_index_7 = squad deaths
--   ui_cash_squad_index_4  = 2 * squads alive + (1 if your squad is alive)
--   ui_cash_squad_index_5  = your kills        ui_cash_squad_index_6  = your deaths
--   ui_cash_squad_index_7  = 1 ranked on, 0 off
-- Files (jupiter/IO): br95_ranked.txt (profile), br95_ranked_live.txt (HUD and
-- result screen), br95_rp.txt, br95_streak.txt, br95_settings.txt (ranked on/off).
-- The last packet is written to br95_core_last.txt (to check what arrives).
-- Fully restart the game after changes.
if BR95RankedCore then return end
local state = { lastSeq = nil, active = false, skipped = false, finished = false }
BR95RankedCore = state

local DIR = "jupiter/IO/"
local PROFILE_FILE = DIR .. "br95_ranked.txt"
local LIVE_FILE = DIR .. "br95_ranked_live.txt"
local RP_FILE = DIR .. "br95_rp.txt"
local STREAK_FILE = DIR .. "br95_streak.txt"
local SETTINGS_FILE = DIR .. "br95_settings.txt"
local LAST_FILE = DIR .. "br95_core_last.txt"

-- rank rules (1 Bronze, 2 Silver, 3 Platinum, 4 Diamond, 5 Crimson, 6 Iridescent, 7 Painite)
local START  = { 0, 1000, 2500, 5000, 8000, 12000, 17000 }
local COST   = { 20, 40, 80, 120, 160, 200, 260 }       -- paid when the match starts
local GAIN   = { 100, 85, 55, 60, 46, 50, 52 }          -- % of the kill points
local MINK   = { 0, 0, 0, 20, 35, 40, 50 }              -- min kills PER PLAYER (x squad size)
local CAP    = { 150, 160, 150, 180, 220, 260, 300 }    -- most SR a match can give
local DEATHP = { 100, 120, 170, 200, 240, 280, 330 }    -- % of the death penalty
local SR_KILL, SR_DEATH, MATCH_MIN = 10, 20, -200

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

local function rankIndex(sr)
    local index = 1
    for k = 1, #START do if sr >= START[k] then index = k end end
    return index
end

-- Top 1 / top 3 / top 5 bonus: only for a squad that is still alive at the end
local function placementBonus(alive, ourAlive)
    if ourAlive ~= 1 then return 0 end
    if alive <= 1 then return 100 end
    if alive <= 3 then return 50 end
    if alive <= 5 then return 25 end
    return 0
end

-- squad kills T, squad deaths D, n humans in the squad: the squad kills are
-- shared between its players (everybody is credited the AVERAGE, so a quad is
-- not worth 4 solos), deaths too, and the minimum kills are compared to that
-- average (T >= min * n). The bonus only counts once the minimum is reached.
local function matchGain(startSR, T, D, n, bonus)
    local i = rankIndex(startSR)
    local positive = 0
    if T >= MINK[i] * n then
        positive = math.floor(T * SR_KILL * GAIN[i] / (100 * n)) + math.floor(bonus * GAIN[i] / 100)
    end
    local deaths = math.ceil(D / n)
    local penalty = math.floor(deaths * SR_DEATH * DEATHP[i] / 100)
    local gain = positive - penalty
    if gain < MATCH_MIN then gain = MATCH_MIN end
    if gain > CAP[i] then gain = CAP[i] end
    return gain
end

-- ---- files -------------------------------------------------------------
local function loadProfile(path)
    local p = { sr = 0, matches = 0, kills = 0, best = 0, last = 0 }
    local text = readText(path or PROFILE_FILE)
    if text then
        local sr, m, k, b, l = text:match("^BR95R1|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|END")
        if sr then
            p.sr, p.matches, p.kills, p.best, p.last = tonumber(sr), tonumber(m), tonumber(k), tonumber(b), tonumber(l)
        end
    end
    return p
end

local function saveProfile(p, path)
    writeText(path or PROFILE_FILE, "BR95R1|" .. p.sr .. "|" .. p.matches .. "|" .. p.kills .. "|" .. p.best .. "|" .. p.last .. "|END")
end

local function readRP()
    local text = readText(RP_FILE)
    return tonumber(text and text:match("^BR95P1|(%d+)|END")) or 0
end

local function loadStreak()
    local s = { streak = 0, best = 0 }
    local text = readText(STREAK_FILE)
    if text then
        local a, b = text:match("^BR95W1|(%d+)|(%d+)|END")
        if a then s.streak, s.best = tonumber(a), tonumber(b) end
    end
    return s
end

local function rankedSettingOn()
    local text = readText(SETTINGS_FILE)
    if text and text:find("ranked=0", 1, true) then return false end
    return true
end

local function writeLive(sr, kills, deaths, delta, active)
    writeText(LIVE_FILE, "BR95L1|" .. sr .. "|" .. kills .. "|" .. deaths .. "|" .. delta .. "|" .. active .. "|END")
end

-- multiplayer: BR95L2|sr|kills|assists|deaths|gain|result|active|END
-- result 0 while playing, 1 win, 2 loss, 3 draw; active 1 playing, 0 result not seen
-- yet, 2 result seen (the HUD writes 2 after showing the result screen)
local MP_LIVE_FILE = DIR .. "br95_mp_live.txt"
local function writeLiveMP(sr, kills, assists, deaths, gain, result, active)
    writeText(MP_LIVE_FILE, "BR95L2|" .. sr .. "|" .. kills .. "|" .. assists .. "|" .. deaths .. "|" .. gain .. "|" .. result .. "|" .. active .. "|END")
end

-- ---- packets -----------------------------------------------------------
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
    local seq = omn("ui_armor_squad_index_4", controller)
    if not seq or seq == 0 then return nil end
    local pn = omn("ui_armor_squad_index_5", controller) or 0
    local a = omn("ui_cash_squad_index_4", controller) or 0
    return {
        seq = seq,
        phase = pn % 10,
        n = math.max(1, math.floor(pn / 10)),
        T = omn("ui_armor_squad_index_6", controller) or 0,
        D = omn("ui_armor_squad_index_7", controller) or 0,
        raw = a,
        alive = math.floor(a / 2),
        ourAlive = a % 2,
        pk = omn("ui_cash_squad_index_5", controller) or 0,
        pd = omn("ui_cash_squad_index_6", controller) or 0,
        flag = omn("ui_cash_squad_index_7", controller) or 0,
    }
end

local function updateLive(p)
    local gain = matchGain(state.startSR, p.T, p.D, p.n, 0)
    local delta = gain - state.cost
    writeLive(math.max(0, state.startSR + delta), p.T, math.ceil(p.D / p.n), delta, 1)
end

-- first packet of a match: pay the entry cost right away (quitting = losing it)
local function beginMatch(p)
    if p.flag == 0 or not rankedSettingOn() then
        state.skipped = true
        writeLive(0, 0, 0, 0, 0)
        return
    end
    local prof = loadProfile()
    state.startSR = prof.sr
    state.cost = COST[rankIndex(prof.sr)]
    prof.sr = math.max(0, prof.sr - state.cost)
    prof.matches = prof.matches + 1
    prof.last = 0 - state.cost
    saveProfile(prof)
    state.active = true
    updateLive(p)
end

-- ---- match history (last 12 matches), shown by the RANKED tab ---------------
-- file br95_history.txt, one line per match: H|sr_after|net|squad_kills|own_kills|place|humans
-- place: 1 = Top 1, 2..9 = still alive among that many squads, 0 = eliminated
local HISTORY_FILE = DIR .. "br95_history.txt"
local function appendHistory(srAfter, net, squadKills, ownKills, place, humans, file)
    file = file or HISTORY_FILE
    local lines = {}
    local text = readText(file)
    if text then
        for line in text:gmatch("[^\n]+") do
            if line:match("^H|") then lines[#lines + 1] = line end
        end
    end
    lines[#lines + 1] = "H|" .. srAfter .. "|" .. net .. "|" .. squadKills .. "|" .. ownKills .. "|" .. place .. "|" .. humans
    while #lines > 12 do table.remove(lines, 1) end
    writeText(file, table.concat(lines, "\n") .. "\nEND")
end

local function finishMatch(p)    state.finished = true
    if state.skipped or not state.active then return end
    state.active = false

    local bonus = placementBonus(p.alive, p.ourAlive)
    local gain = matchGain(state.startSR, p.T, p.D, p.n, bonus)
    local prof = loadProfile()
    prof.sr = math.max(0, prof.sr + gain)
    prof.kills = prof.kills + p.pk
    if prof.sr > prof.best then prof.best = prof.sr end
    prof.last = gain - state.cost
    saveProfile(prof)
    local place = 0
    if bonus >= 100 then place = 1 elseif p.ourAlive == 1 then place = math.max(2, math.min(9, p.alive)) end
    appendHistory(prof.sr, prof.last, p.T, p.pk, place, p.n)

    -- Ranked Points: 3 per squad kill (shared), +1 per 8 SR won, +100 per rank
    -- gained, +50 for a Top 1; +10 % per win in the streak (5 wins at most)
    local rp = math.floor(p.T / p.n) * 3
    if gain > 0 then rp = rp + math.floor(gain / 8) end
    if rankIndex(prof.sr) > rankIndex(state.startSR) then rp = rp + 100 end
    if bonus >= 100 then rp = rp + 50 end
    local st = loadStreak()
    if prof.last > 0 then
        st.streak = st.streak + 1
        if st.streak > st.best then st.best = st.streak end
        rp = math.floor(rp * (100 + 10 * math.min(st.streak, 5)) / 100)
    else
        st.streak = 0
    end
    writeText(STREAK_FILE, "BR95W1|" .. st.streak .. "|" .. st.best .. "|END")
    writeText(RP_FILE, "BR95P1|" .. (readRP() + rp) .. "|END")
    writeLive(prof.sr, p.T, math.ceil(p.D / p.n), prof.last, 0)
end

-- ---- classic multiplayer (flag 2): a LEVEL ranking --------------------------
-- Not a ranked mode: the SR of this ranking are points that only go up.
--   kill +10, assist +5, win +50 (draw +15); a loss gives only its kills/assists.
-- The level (1 to 1000) comes from the total: going from level L to L + 1 costs
-- 100 + L SR, so level L needs 100 * L + L * (L - 1) / 2 SR in all.
-- Points are given when the match ends (leaving early gives nothing). Own files,
-- so the world ranking uses this one (profile field "best" stores the level).
local MP_FILE = DIR .. "br95_mp_ranked.txt"
local MP_HISTORY = DIR .. "br95_mp_history.txt"      -- H|sr_after|gain|kills|assists|result(1 win 2 loss 3 draw)|1
local MP_STREAK = DIR .. "br95_mp_streak.txt"
local MP_KILL, MP_ASSIST, MP_WIN, MP_DRAW = 10, 5, 50, 15

local MP_SEASON = DIR .. "br95_mp_season.txt"      -- BR95S2|season number|SR earned in this season|END
local MP_SEASON_EPOCH = 1792613644                   -- same calendar for everybody
local MP_SEASON_LENGTH = 40 * 86400
local MP_TIME = DIR .. "br95_mp_time.txt"          -- BR95T1|seconds played in finished MP matches|END

local function needFor(level)
    if level <= 0 then return 0 end
    return 100 * level + level * (level - 1) / 2
end

local function levelOf(sr)
    local lv = math.floor(-99.5 + math.sqrt(99.5 * 99.5 + 2 * sr))
    if lv < 0 then lv = 0 end
    while lv > 0 and needFor(lv) > sr do lv = lv - 1 end
    while lv < 1000 and needFor(lv + 1) <= sr do lv = lv + 1 end
    return lv
end

-- kills k, assists a, result 1 win / 2 loss / 3 draw (0 = match not over)
local function mpGain(k, a, result)
    local gain = k * MP_KILL + a * MP_ASSIST
    if result == 1 then gain = gain + MP_WIN elseif result == 3 then gain = gain + MP_DRAW end
    return gain
end

local function updateLiveMP(p)
    local gain = mpGain(p.T, p.pk, 0)
    writeLiveMP(state.startSR + gain, p.T, p.pk, p.D, gain, 0, 1)
end

local function beginMatchMP(p)
    if p.flag == 0 or not rankedSettingOn() then
        state.skipped = true
        writeLiveMP(0, 0, 0, 0, 0, 0, 0)
        return
    end
    local prof = loadProfile(MP_FILE)
    state.mp = true
    state.startTime = os.time()
    state.startSR = prof.sr
    prof.matches = prof.matches + 1
    prof.last = 0
    saveProfile(prof, MP_FILE)
    state.active = true
    updateLiveMP(p)
end

local function finishMatchMP(p)
    state.finished = true
    if state.skipped or not state.active then return end
    state.active = false

    local result = p.raw
    if result < 1 or result > 3 then result = 3 end
    local gain = mpGain(p.T, p.pk, result)

    local prof = loadProfile(MP_FILE)
    local levelBefore = levelOf(prof.sr)
    prof.sr = prof.sr + gain
    prof.kills = prof.kills + p.T
    prof.best = levelOf(prof.sr)
    prof.last = gain
    saveProfile(prof, MP_FILE)
    appendHistory(prof.sr, gain, p.T, p.pk, result, 1, MP_HISTORY)

    -- season SR: resets every 40 days, the level itself never resets
    local seasonNumber = math.max(1, math.floor((os.time() - MP_SEASON_EPOCH) / MP_SEASON_LENGTH) + 1)
    local seasonText = readText(MP_SEASON)
    local sn, ssr
    if seasonText then sn, ssr = seasonText:match("^BR95S2|(%d+)|(%d+)|END") end
    local seasonSR = (tonumber(sn) == seasonNumber) and (tonumber(ssr) or 0) or 0
    writeText(MP_SEASON, "BR95S2|" .. seasonNumber .. "|" .. (seasonSR + gain) .. "|END")

    -- play time of the finished match (at most 3 hours), shown in the LEVEL tab
    local elapsed = state.startTime and (os.time() - state.startTime) or 0
    if elapsed < 0 then elapsed = 0 end
    if elapsed > 10800 then elapsed = 10800 end
    local seconds = tonumber(readText(MP_TIME) and readText(MP_TIME):match("^BR95T1|(%d+)|END")) or 0
    writeText(MP_TIME, "BR95T1|" .. (seconds + elapsed) .. "|END")

    -- Ranked Points: 2 per kill, 1 per assist, win 40 / draw 15 / loss 10, +50 per
    -- level gained; the MP win streak adds +10 % per win (5 at most)
    local rp = p.T * 2 + p.pk + ((result == 1) and 40 or ((result == 3) and 15 or 10))
    if prof.best > levelBefore then rp = rp + 50 end
    local text = readText(MP_STREAK)
    local sa, sb
    if text then sa, sb = text:match("^BR95W1|(%d+)|(%d+)|END") end
    local streak, best = tonumber(sa) or 0, tonumber(sb) or 0
    if result == 1 then
        streak = streak + 1
        if streak > best then best = streak end
        rp = math.floor(rp * (100 + 10 * math.min(streak, 5)) / 100)
    elseif result == 2 then
        streak = 0
    end
    writeText(MP_STREAK, "BR95W1|" .. streak .. "|" .. best .. "|END")
    writeText(RP_FILE, "BR95P1|" .. (readRP() + rp) .. "|END")
    writeLiveMP(prof.sr, p.T, p.pk, p.D, gain, result, 0)
end

local function onPacket(p)
    writeText(LAST_FILE, p.seq .. "|phase " .. p.phase .. "|n " .. p.n .. "|squad kills " .. p.T .. "|squad deaths " .. p.D
        .. "|alive squads " .. p.alive .. "|ours alive " .. p.ourAlive .. "|own " .. p.pk .. "/" .. p.pd .. "|ranked " .. p.flag
        .. "|active " .. tostring(state.active) .. "|skipped " .. tostring(state.skipped) .. "|finished " .. tostring(state.finished))
    if state.finished then return end
    if p.phase == 3 then
        if p.flag == 2 then finishMatchMP(p) else finishMatch(p) end
        return
    end
    if state.skipped then return end
    if state.active then
        if state.mp then updateLiveMP(p) else updateLive(p) end
    elseif p.flag == 2 then
        beginMatchMP(p)
    else
        state.mp = false
        beginMatch(p)
    end
end

-- ---- seasons -----------------------------------------------------------
-- Same calendar for every player (21 days from SEASON_EPOCH), so the world
-- ranking compares players of the same season. The season file keeps the
-- number of the season the saved SR belongs to: another number = SR reset.
-- Checked at load and then every minute while in the menu (never in a match).
local SEASON_FILE = DIR .. "br95_season.txt"       -- BR95S1|start|number|END
local SEASON_EPOCH = 1792613644
local SEASON_LENGTH = 21 * 86400
local lastSeasonCheck = 0

local function checkSeason()
    local now = os.time()
    local number = math.max(1, math.floor((now - SEASON_EPOCH) / SEASON_LENGTH) + 1)
    local start = SEASON_EPOCH + (number - 1) * SEASON_LENGTH
    local text = readText(SEASON_FILE)
    local stored = text and tonumber(text:match("^BR95S1|%d+|(%d+)"))
    if stored ~= number then
        writeText(SEASON_FILE, "BR95S1|" .. start .. "|" .. number .. "|END")
        if stored then
            writeText(PROFILE_FILE, "BR95R1|0|0|0|0|0|END")
            writeText(STREAK_FILE, "BR95W1|0|0|END")
            if DebugPrint then pcall(DebugPrint, "[BR95Ranked] new season " .. number .. ", SR reset") end
        end
    end
end

local function seasonTick()
    local now = os.time()
    if now - lastSeasonCheck < 60 then return end
    lastSeasonCheck = now
    checkSeason()
end
local function poll()
    local inFront = false
    pcall(function() inFront = Engine.@InFrontend() end)
    if inFront then
        -- back in the menu: forget this match (leaving before the end only costs the entry fee)
        state.active, state.skipped, state.finished, state.lastSeq = false, false, false, nil
        pcall(seasonTick)
        return
    end
    local controller = 0
    pcall(function() controller = Engine.@GetFirstActiveController() end)
    local seq = omn("ui_armor_squad_index_4", controller)
    if not seq or seq == 0 or seq == state.lastSeq then return end
    state.lastSeq = seq
    local p = readPacket(controller)
    if p then pcall(onPacket, p) end
end

local function attach(root)
    if not root or root._br95Core then return end
    if LUI.primaryRoot and root ~= LUI.primaryRoot then return end
    root._br95Core = true
    local watch = LUI.UIElement.new(); watch.id = "BR95RankedCore"
    root:addElement(watch)
    watch:registerEventHandler("br95_core_tick", function() pcall(poll) end)
    watch:addElement(LUI.UITimer.new({ interval = 250, event = "br95_core_tick", disposable = false, eventTarget = watch }))
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