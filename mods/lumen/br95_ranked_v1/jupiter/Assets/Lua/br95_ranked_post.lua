-- BR95 Ranked V2 menu: RANKED tab of the Warzone lobby, built like the official
-- Ranked Play screens with the game's own images (shields, I / II / III, SR logo,
-- RANKED PLAY logo, key art), taken by name: nothing is shipped with the mod.
-- Pages: OVERVIEW, QUESTS (3 daily quests), STATS (charts), RANKING (local board
-- of 200 to 5000 players), SETTINGS. Data: br95_ranked.txt (br95_ranked.gscc),
-- br95_ranked_history.txt (one line per match, written by
-- br95_ranked_hud_post.lua), br95_quests.txt, br95_rp.txt, br95_settings.txt.
-- Same tab mechanism as the Local Progression "CASES" tab (MAINMENUTABS).
-- Everything is wrapped in pcall: if something is missing the tab is simply
-- not added, the game keeps working. Fully restart the game after changes.
if BR95RankedMenu then return end
local state = { installed = false }
BR95RankedMenu = state

local FILE = "jupiter/IO/br95_ranked.txt"
local HISTORY_FILE = "jupiter/IO/br95_ranked_history.txt"
local QUEST_FILE = "jupiter/IO/br95_quests.txt"
local RP_FILE = "jupiter/IO/br95_rp.txt"
local MENU = "BR95RankedMenu"

-- official divisions, must match br95_ranked.gsc (v11)
local RANKS = {
    { name = "BRONZE",     start = 0,     color = 0xCD7F32, cost = 0,   icon = "bronze" },
    { name = "SILVER",     start = 1000,  color = 0xC8C8C8, cost = 10,  icon = "silver" },
    { name = "GOLD",       start = 2000,  color = 0xE8C05A, cost = 30,  icon = "gold" },
    { name = "PLATINUM",   start = 3500,  color = 0x5FE0C8, cost = 70,  icon = "platinum" },
    { name = "DIAMOND",    start = 5000,  color = 0x4FA3FF, cost = 120, icon = "diamond" },
    { name = "CRIMSON",    start = 8000,  color = 0xE0303A, cost = 160, icon = "crimson" },
    { name = "IRIDESCENT", start = 12000, color = 0xC77DFF, cost = 200, icon = "iridescent" },
    { name = "TOP 250",    start = 17000, color = 0xF2C14E, cost = 260, icon = "top250" },
}
local IRIS, TOP = 7, 8
local WHITE, GREY, DIM, BLACK = 0xFFFFFF, 0x9A9A9A, 0x5A5A5A, 0x000000
local TILE, LINE = 0x101010, 0x2A2A2A
local GREEN, RED, GOLDC, AMBER, RPC = 0x6BD66B, 0xE04040, 0xF2C14E, 0xFFB347, 0xFFD27A
local ROMAN = { "I", "II", "III" }

local SR_ICON = "iw9_ui_icon_leagueplay_skill_rating"
local STAR_ICON = "iw9_ui_icon_leagueplay_star_filled"
local TOP_ART = "menu_keyart_ranked_250_layer_00"
local BACK_ART = "menu_keyart_rankedplay_01_layer_00"
local MODE_ICON = "jup_icon_mode_wz_ranked"

-- ------------------------------------------------------------------
-- files, settings (also read by br95_ranked.gscc) and 3-week seasons
-- ------------------------------------------------------------------
local SETTINGS_FILE = "jupiter/IO/br95_settings.txt"
local SEASON_FILE = "jupiter/IO/br95_season.txt"
local SEASON_DAYS = 21
local BOARD_SIZES = { 200, 500, 1000, 2000, 3000, 5000 }

local function readText(path)
    local text
    pcall(function()
        local f = io.open(path, "r")
        if f then text = f:read("*a"); f:close() end
    end)
    return text
end

local function writeText(path, text)
    local ok = pcall(function()
        local f = io.open(path, "w")
        if not f then error("open") end
        f:write(text); f:close()
    end)
    return ok
end

-- ranked: 1 on / 0 off, spawnmsg: rank message at spawn, anim: animated
-- colors, speed: 1 slow / 2 normal / 3 fast, board: players in the RANKING page
local function loadSettings()
    local s = { ranked = 1, spawnmsg = 1, anim = 1, speed = 2, board = 1000 }
    local text = readText(SETTINGS_FILE)
    if text then
        for k, v in text:gmatch("(%a+)=(%d+)") do
            if s[k] ~= nil then s[k] = tonumber(v) end
        end
    end
    return s
end

local function saveSettings(s)
    return writeText(SETTINGS_FILE, "BR95C1|ranked=" .. s.ranked .. "|spawnmsg=" .. s.spawnmsg
        .. "|anim=" .. s.anim .. "|speed=" .. s.speed .. "|board=" .. s.board .. "|END")
end

local function resetRanked()
    return writeText(FILE, "BR95R1|0|0|0|0|0|END")
end

-- season: start time + number; past 3 weeks = new season and SR reset
-- Same calendar for every player (21 days from SEASON_EPOCH). The season file
-- keeps the number of the season the saved SR belongs to: another number = reset.
local SEASON_EPOCH = 1792613644
local function checkSeason()
    local now = os.time()
    local length = SEASON_DAYS * 86400
    local number = math.max(1, math.floor((now - SEASON_EPOCH) / length) + 1)
    local start = SEASON_EPOCH + (number - 1) * length
    local text = readText(SEASON_FILE)
    local stored = text and tonumber(text:match("^BR95S1|%d+|(%d+)"))
    if stored ~= number then
        writeText(SEASON_FILE, "BR95S1|" .. start .. "|" .. number .. "|END")
        if stored then
            resetRanked()
            if DebugPrint then pcall(DebugPrint, "[BR95Ranked] new season " .. number .. ", SR reset") end
        end
    end
    return number, start + length - now
end

-- manual reset: SR back to 0 (the season number follows the shared calendar)
local function newSeason()
    local number = checkSeason()
    return resetRanked(), number
end

local function readProfile()
    local p = { sr = 0, matches = 0, kills = 0, best = 0, last = 0 }
    local text = readText(FILE)
    if text then
        local sr, m, k, b, l = text:match("^BR95R1|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|END")
        if sr then
            p.sr, p.matches, p.kills, p.best, p.last = tonumber(sr), tonumber(m), tonumber(k), tonumber(b), tonumber(l)
        end
    end
    return p
end

local function saveProfile(p)
    return writeText(FILE, "BR95R1|" .. p.sr .. "|" .. p.matches .. "|" .. p.kills .. "|" .. p.best .. "|" .. p.last .. "|END")
end

local function readRP()
    local text = readText(RP_FILE)
    local rp = text and text:match("^BR95P1|(%d+)|END")
    return tonumber(rp) or 0
end

local function readStreak()
    local text = readText("jupiter/IO/br95_streak.txt")
    local s, b = 0, 0
    if text then
        local a1, a2 = text:match("^BR95W1|(%d+)|(%d+)|END")
        if a1 then s, b = tonumber(a1), tonumber(a2) end
    end
    return s, b
end

-- history: H|time|sr_after|delta|kills|deaths|seconds|rp|END, oldest first
-- (rp = RP won in the match, missing on the first lines)
local function readHistory()
    local list = {}
    local text = readText(HISTORY_FILE)
    if not text then return list end
    for line in text:gmatch("[^\n]+") do
        local f = {}
        for part in line:gmatch("[^|]+") do f[#f + 1] = part end
        if f[1] == "H" and #f >= 8 then
            list[#list + 1] = { time = tonumber(f[2]) or 0, sr = tonumber(f[3]) or 0, delta = tonumber(f[4]) or 0,
                kills = tonumber(f[5]) or 0, deaths = tonumber(f[6]) or 0, seconds = tonumber(f[7]) or 0,
                rp = (f[9] and tonumber(f[8])) or 0 }
        end
    end
    return list
end

local function rankIndex(sr)
    local index = 1
    for i, r in ipairs(RANKS) do if sr >= r.start then index = i end end
    return index
end

local function font(text, size, bold)
    if FONTS and FONTS.GetFont then
        local f = bold and FONTS.PrimaryBold or FONTS.SecondaryRegular
        if f and f.File then pcall(text.SetFont, text, FONTS.GetFont(f.File)) end
    end
    if text.SetFontSize then pcall(text.SetFontSize, text, size) end
end

local function shieldName(idx, large)
    return "iw9_ui_icon_leagueplay_rank_0_" .. RANKS[idx].icon .. (large and "_large" or "")
end

local function tierOverlay(idx, tier)
    local data
    pcall(function() data = LeaguePlayUtils.GetSubdivisionData(idx, tier + 1) end)
    return data and data.tierOverlay
end

local function seasonLogo()
    local logo
    pcall(function() logo = LeaguePlayUtils.GetSeasonLogo(1) end)
    return logo
end

-- every division step in order: Bronze I .. Iridescent III, then Top 250
local function steps()
    local list = {}
    for i = 1, TOP - 1 do
        local size = (RANKS[i + 1].start - RANKS[i].start) / 3
        for t = 0, 2 do
            list[#list + 1] = { idx = i, tier = t, from = math.floor(RANKS[i].start + t * size) }
        end
    end
    list[#list + 1] = { idx = TOP, from = RANKS[TOP].start }
    return list
end

local function stepOf(list, sr)
    local n = 1
    for k, s in ipairs(list) do if sr >= s.from then n = k end end
    return n
end

local function stepLabel(s)
    return RANKS[s.idx].name .. (s.tier and ("  " .. ROMAN[s.tier + 1]) or "")
end

-- share of players above you (fictional population), shown as TOP x %
local PERCENT = { { 0, 100 }, { 1000, 72 }, { 2000, 48 }, { 3500, 27 }, { 5000, 13 }, { 8000, 4.5 }, { 12000, 0.9 }, { 17000, 0.05 } }
local function topPercent(sr)
    for k = #PERCENT, 1, -1 do
        local a = PERCENT[k]
        if sr >= a[1] then
            local b = PERCENT[k + 1]
            if not b then return a[2] end
            return a[2] + (b[2] - a[2]) * (sr - a[1]) / (b[1] - a[1])
        end
    end
    return 100
end

local function percentText(sr)
    local v = topPercent(sr)
    if v >= 10 then return "TOP " .. math.floor(v + 0.5) .. "%" end
    return "TOP " .. string.format("%.1f", v) .. "%"
end

local function minutesText(seconds)
    local m = math.floor(seconds / 60)
    if m >= 60 then return math.floor(m / 60) .. "H " .. string.format("%02d", m % 60) .. "M" end
    return m .. "M"
end

-- ------------------------------------------------------------------
-- RANKING: the best players of the season (local), 200 to 5000 of them, the
-- same for a whole season, who climb a little after each of your matches.
-- The first 250 are the Top 250 (17000 SR and more).
-- ------------------------------------------------------------------
local TAG_A = { "Ghost", "Viper", "Nova", "Frost", "Rogue", "Hex", "Blaze", "Shadow", "Kairo", "Zyn",
    "Axel", "Onyx", "Raven", "Drift", "Echo", "Lynx", "Mako", "Nyx", "Orion", "Pulse", "Reaper", "Sable",
    "Talon", "Vex", "Wraith", "Zero", "Kilo", "Ash", "Bolt", "Cipher", "Havoc", "Jinx", "Krypt", "Lotus",
    "Mamba", "Nomad", "Phantom", "Quake", "Riot", "Saint", "Toxic", "Venom", "Wolf", "Xeno", "Yuki", "Zephyr",
    "Apex", "Bandit", "Cobra", "Dusk", "Ember", "Fury", "Glitch", "Hydra", "Ion", "Jet", "Karma", "Lucid" }
local TAG_B = { "", "TTV", "YT", "_fps", "x", "99", "OG", "Pro", "GG", "_wz", "SZN", "Main", "exe", "07",
    "Hz", "_", "Ace", "1", "LIVE", "Z" }

local function makeBoard(season, matches, player, playerSR, size)
    local seed = (season * 7919 + 17) % 2147483647
    local function rnd()
        seed = (seed * 16807) % 2147483647
        return seed / 2147483647
    end
    local board, used = {}, {}
    for n = 1, size do
        local name
        repeat
            name = TAG_A[math.floor(rnd() * #TAG_A) + 1] .. TAG_B[math.floor(rnd() * #TAG_B) + 1]
            if rnd() < ((n > 600) and 0.7 or 0.35) then name = name .. math.floor(rnd() * 900 + 10) end
        until not used[name]
        used[name] = true
        local climb = math.floor(matches * (8 + rnd() * 30))
        local sr
        if n <= 250 then
            sr = 17000 + math.floor(15500 * (1 - (n - 1) / 250) ^ 2.4) + math.floor(rnd() * 400) + climb
        else
            -- below the Top 250 the board goes down through every division to
            -- Bronze, whatever its size (for 5000: about half Platinum or better,
            -- the last fifth in Bronze)
            local frac = (n - 250) / math.max(1, size - 250)
            sr = math.floor(16990 * (1 - frac) ^ 1.8 * (0.97 + rnd() * 0.03) + climb * 0.3 * (1 - frac))
            sr = math.max(0, math.min(16990, sr))
        end
        board[n] = { name = name, sr = sr, kills = math.floor(sr / 9 + rnd() * 900), matches = math.floor(sr / 60 + rnd() * 120) }
    end
    if playerSR >= board[size].sr then
        board[#board + 1] = { name = player, sr = playerSR, me = true }
    end
    table.sort(board, function(a, b) return a.sr > b.sr end)
    for k = #board, size + 1, -1 do board[k] = nil end
    local mine
    for k, e in ipairs(board) do if e.me then mine = k end end
    return board, mine
end

-- ------------------------------------------------------------------
-- daily quests: 3 per UTC day, picked from the pool by the day number,
-- progress from today's matches in the history, rewards claimed by hand
-- (SR added to the profile + RP). File: BR95Q1|day|c1|c2|c3|bonus|END
-- ------------------------------------------------------------------
local QUESTS = {
    { title = "WARM UP",      desc = "PLAY 3 RANKED MATCHES",                 goal = 3,   sr = 15, rp = 50,
        value = function(h) return #h end },
    { title = "HEADHUNTER",   desc = "GET 25 KILLS IN RANKED",                goal = 25,  sr = 20, rp = 75,
        value = function(h) local n = 0; for _, m in ipairs(h) do n = n + m.kills end; return n end },
    { title = "ONE MAN ARMY", desc = "GET 12 KILLS IN ONE MATCH",             goal = 12,  sr = 25, rp = 100,
        value = function(h) local n = 0; for _, m in ipairs(h) do n = math.max(n, m.kills) end; return n end },
    { title = "IN THE GREEN", desc = "WIN 2 MATCHES (MORE SR AT THE END)",    goal = 2,   sr = 25, rp = 100,
        value = function(h) local n = 0; for _, m in ipairs(h) do if m.delta > 0 then n = n + 1 end end; return n end },
    { title = "CLIMBER",      desc = "EARN 120 SR IN WON MATCHES",            goal = 120, sr = 20, rp = 75,
        value = function(h) local n = 0; for _, m in ipairs(h) do if m.delta > 0 then n = n + m.delta end end; return n end },
    { title = "SURVIVOR",     desc = "FINISH A MATCH WITH 8+ KILLS, 1 DEATH MAX", goal = 1, sr = 30, rp = 100,
        value = function(h) local n = 0; for _, m in ipairs(h) do if m.kills >= 8 and m.deaths <= 1 then n = 1 end end; return n end },
    { title = "GRINDER",      desc = "PLAY 45 MINUTES OF RANKED",             goal = 45,  sr = 15, rp = 75,
        value = function(h) local n = 0; for _, m in ipairs(h) do n = n + m.seconds end; return math.floor(n / 60) end },
}
local BONUS_SR, BONUS_RP = 40, 150

local function today() return math.floor(os.time() / 86400) end

local function dailyQuests(day)
    local seed = (day * 48271 + 11) % 2147483647
    local picked, used = {}, {}
    while #picked < 3 do
        seed = (seed * 16807) % 2147483647
        local k = (seed % #QUESTS) + 1
        if not used[k] then used[k] = true; picked[#picked + 1] = QUESTS[k] end
    end
    return picked
end

local function readQuestState(day)
    local q = { day = day, c = { 0, 0, 0 }, bonus = 0 }
    local text = readText(QUEST_FILE)
    if text then
        local d, a, b, c, e = text:match("^BR95Q1|(%d+)|(%d)|(%d)|(%d)|(%d)|END")
        if d and tonumber(d) == day then q.c = { tonumber(a), tonumber(b), tonumber(c) }; q.bonus = tonumber(e) end
    end
    return q
end

local function saveQuestState(q)
    return writeText(QUEST_FILE, "BR95Q1|" .. q.day .. "|" .. q.c[1] .. "|" .. q.c[2] .. "|" .. q.c[3] .. "|" .. q.bonus .. "|END")
end

local function giveReward(sr, rp)
    local p = readProfile()
    p.sr = p.sr + sr
    if p.sr > p.best then p.best = p.sr end
    saveProfile(p)
    writeText(RP_FILE, "BR95P1|" .. (readRP() + rp) .. "|END")
end

-- ------------------------------------------------------------------
-- the tab
-- ------------------------------------------------------------------
local function build(menu, controller)
    local root = LUI.UIElement.new(); root.id = MENU
    root:SetAnchorsAndPosition(0, 1, 0, 1, 0, 1920, 0, 1080)
    local LEFT = LUI.Alignment and LUI.Alignment.Left
    local RIGHT = LUI.Alignment and LUI.Alignment.Right

    local function view()
        local v = LUI.UIElement.new()
        v:SetAnchorsAndPosition(0, 1, 0, 1, 0, 1920, 0, 1080)
        root:addElement(v); return v
    end
    local function place(el, l, r, t, b)
        pcall(el.SetAnchorsAndPosition, el, 0.5, 0.5, 0, 1, l, r, t, b)
    end
    local function box(parent, color, alpha, l, r, t, b)
        local child = LUI.UIImage.new()
        child:SetRGB(color, 0); child:SetAlpha(alpha, 0)
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        parent:addElement(child); return child
    end
    local function image(parent, material, alpha, l, r, t, b)
        local child = LUI.UIImage.new()
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        parent:addElement(child)
        local ok = material ~= nil and pcall(function() child:setImage(RegisterMaterial(material), 0) end)
        child:SetAlpha(ok and alpha or 0, 0)
        return child, ok
    end
    local function text(parent, str, size, color, l, r, t, b, align, bold)
        local child = LUI.UIText.new()
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        font(child, size, bold)
        if child.SetAlignment and LUI.Alignment then child:SetAlignment(align or LUI.Alignment.Center) end
        child:SetRGB(color or WHITE, 0)
        child:setText(str)
        parent:addElement(child); return child
    end
    local function set(el, str) if el then pcall(el.setText, el, str) end end
    -- panel with a dark body, a thin top line and a title
    local function panel(parent, title, l, r, t, b, color)
        box(parent, TILE, 0.82, l, r, t, b)
        box(parent, color or LINE, 1, l, r, t, t + 2)
        if title then text(parent, title, 18, GREY, l + 16, r - 16, t + 10, t + 32, LEFT, true) end
    end
    -- official shield + official I / II / III, the numeral small on the plate
    local function shield(parent, cx, top, size, idx, tier, alpha)
        local s = image(parent, shieldName(idx, size > 64), alpha, cx - size / 2, cx + size / 2, top, top + size)
        if tier and idx < TOP then
            local o = size * 0.30
            local cy = top + size * 0.58
            image(parent, tierOverlay(idx, tier), alpha, cx - o / 2, cx + o / 2, cy - o / 2, cy + o / 2)
        end
        return s
    end
    -- number with the official SR logo in front of it; align "center" or "left"
    local function srValue(parent, value, size, color, x, t, align)
        local str = tostring(value)
        -- width of the digits of this bold font (about 0.72 of the size); the
        -- text box gets a lot more room so a number never wraps
        local w = math.floor(#str * size * 0.72)
        local icon = size * 0.95
        local l = (align == "left") and x or (x - (w + icon + 8) / 2)
        local _, ok = image(parent, SR_ICON, 1, l, l + icon, t + size * 0.14, t + size * 0.14 + icon * 0.89)
        if not ok then str = str .. " SR" end
        return text(parent, str, size, color, l + icon + 8, l + icon + 8 + w + 240, t, t + size + 4, LEFT, true)
    end
    -- RP amount with the star in front of it
    local function rpValue(parent, value, size, x, t)
        image(parent, STAR_ICON, 1, x, x + size, t, t + size)
        return text(parent, value .. " RP", size, RPC, x + size + 6, x + size + 260, t, t + size + 2, LEFT, true)
    end
    -- plain progress bar; returns a function to fill it (0..1)
    local function bar(parent, l, r, t, h, color)
        box(parent, LINE, 1, l, r, t, t + h)
        local fill = box(parent, color, 1, l, l + 1, t, t + h)
        return function(pct)
            pct = math.max(0, math.min(1, pct))
            place(fill, l, l + math.max(1, (r - l) * pct), t, t + h)
        end
    end

    -- data
    local settings = loadSettings()
    local seasonNumber, seasonLeft = checkSeason()
    local p = readProfile()
    local i = rankIndex(p.sr)
    local rank = RANKS[i]
    local list = steps()
    local cur = stepOf(list, p.sr)
    local nextStep = list[cur + 1]
    local streak, bestStreak = readStreak()
    local rp = readRP()
    local history = readHistory()
    local day = today()

    local player = "PLAYER"
    pcall(function()
        local json = readText("jupiter/settings.json") or ""
        local name = json:match('"username"%s*:%s*"([^"]*)"')
        local tag = json:match('"clanTag"%s*:%s*"([^"]*)"')
        if name and name ~= "" then
            player = ((tag and tag ~= "") and ("[" .. tag .. "] ") or "") .. name
        end
    end)
    player = string.upper(player)

    -- flowing colours (Iridescent / Top 250) and pulses
    local RAINBOW = { 0xB57CFF, 0xF07CFF, 0xEDEDF7, 0x6FF0E4, 0xFFE08A, 0x7FA2FF, 0xD0A0FF }
    local GOLDEN = { 0xF2C14E, 0xFFD27A, 0xFFF0B0, 0xE8A93A, 0xFF5A66, 0xFFD27A, 0xF7DC8C }
    local animated, pulses, intro = {}, {}, {}
    local flowing = (i == IRIS) or (i == TOP)
    local pal = (i == TOP) and GOLDEN or RAINBOW
    local kind = (i == TOP) and "fast" or "slow"
    local function accent(el, off)
        if flowing and el then animated[#animated + 1] = { el = el, off = off or 0 } end
        return el
    end
    local function pulse(el, lo, hi) pulses[#pulses + 1] = { el = el, lo = lo, hi = hi }; return el end

    -- backdrop: official key art, darkened (static)
    image(root, BACK_ART, 0.32, -800, 800, 110, 990)
    box(root, BLACK, 0.80, -800, 800, 110, 990)
    accent(box(root, rank.color, 1, -800, 800, 110, 114), 1)
    box(root, BLACK, 0.5, -800, 800, 114, 244)

    -- header: RANKED PLAY logo, player, rank chip, season, RP
    local _, logoOk = image(root, seasonLogo(), 1, -790, -550, 120, 240)
    local nameL = -530
    if not logoOk then
        image(root, MODE_ICON, 1, -785, -685, 128, 228)
        nameL = -670
    end
    text(root, player, 26, WHITE, nameL, -130, 130, 162, LEFT, true)
    shield(root, nameL + 16, 166, 32, i, list[cur].tier, 1)
    accent(text(root, stepLabel(list[cur]), 22, rank.color, nameL + 40, nameL + 330, 170, 196, LEFT, true), 2)
    text(root, percentText(p.sr), 18, WHITE, nameL + 200, nameL + 390, 172, 196, LEFT, true)
    local days = math.floor(seasonLeft / 86400)
    local hours = math.floor((seasonLeft % 86400) / 3600)
    text(root, "SEASON " .. seasonNumber .. "   |   ENDS IN " .. days .. "D " .. string.format("%02d", hours) .. "H",
        16, GREY, nameL, -60, 204, 226, LEFT)
    -- RP chip (top right, under the page buttons)
    box(root, RPC, 0.12, 560, 780, 200, 238)
    box(root, RPC, 1, 560, 563, 200, 238)
    local rpText = rpValue(root, rp, 22, 574, 207)
    if settings.ranked == 0 then
        text(root, "RANKED OFF: MATCHES DO NOT CHANGE YOUR SR", 16, RED, -40, 540, 210, 232, RIGHT, true)
    end

    -- pages
    local PAGES = { "OVERVIEW", "QUESTS", "STATS", "RANKING", "SETTINGS" }
    local views, pageButtons, current = {}, {}, 1
    for k = 1, #PAGES do
        views[k] = view(); pageButtons[k] = {}
        if k > 1 then views[k]:SetAlpha(0, 0) end
    end
    -- buttons of a page: built now (only buttons built with the tab get input);
    -- while their page is not shown they wait far off-screen (a hidden button
    -- would still light up and catch clicks)
    local function pageButton(page, label, l, r, t, b, action)
        local btn = MenuBuilder.BuildRegisteredType("GenericButton", { controllerIndex = controller })
        root:addElement(btn)
        local entry = { btn = btn, l = l, r = r, t = t, b = b }
        if page == 1 then place(btn, l, r, t, b) else place(btn, l + 6000, r + 6000, t, b) end
        local function label_(str) if btn.Text then pcall(btn.Text.setText, btn.Text, str) end end
        label_(label)
        btn:addEventHandler("button_action", function() if current == page then pcall(action, label_) end end)
        pageButtons[page][#pageButtons[page] + 1] = entry
        return btn, label_
    end

    -- ================================================================
    -- OVERVIEW
    -- ================================================================
    local v = views[1]
    panel(v, nil, -780, -230, 258, 984, rank.color)
    box(v, rank.color, 0.12, -690, -320, 280, 650)
    shield(v, -505, 270, 370, i, list[cur].tier, 1)
    accent(box(v, rank.color, 1, -735, -275, 650, 696), 4)
    box(v, BLACK, 0.25, -735, -275, 692, 696)
    text(v, stepLabel(list[cur]), 32, WHITE, -735, -275, 656, 692, nil, true)
    local srText = srValue(v, 0, 44, WHITE, -505, 708)
    text(v, percentText(p.sr) .. "  OF PLAYERS", 18, GREY, -735, -275, 762, 786, nil, true)
    -- the SR bar is the living part of the screen: it fills up, a light runs
    -- along the filled part and its tip pulses
    local BL, BR, BT, BH = -750, -260, 800, 16
    box(v, LINE, 1, BL, BR, BT, BT + BH)
    for k = 1, 3 do box(v, BLACK, 0.6, BL + (BR - BL) * k / 4 - 1, BL + (BR - BL) * k / 4 + 1, BT, BT + BH) end
    local heroFill = accent(box(v, rank.color, 1, BL, BL + 1, BT, BT + BH), 7)
    local shine = box(v, WHITE, 0, BL, BL + 1, BT, BT + BH)
    local tip = box(v, WHITE, 0.8, BL - 3, BL + 3, BT - 4, BT + BH + 4)
    local heroPct = nextStep and ((p.sr - list[cur].from) / (nextStep.from - list[cur].from)) or 1
    heroPct = math.max(0, math.min(1, heroPct))
    local heroRight = BL
    local function setHero(pct)
        heroRight = BL + math.max(1, (BR - BL) * pct)
        place(heroFill, BL, heroRight, BT, BT + BH)
        place(tip, heroRight - 3, heroRight + 3, BT - 4, BT + BH + 4)
    end
    if nextStep then
        text(v, list[cur].from .. "", 16, GREY, BL, BL + 150, BT + 20, BT + 40, LEFT)
        text(v, nextStep.from .. "", 16, GREY, BR - 150, BR, BT + 20, BT + 40, RIGHT)
        text(v, (nextStep.from - p.sr) .. " SR TO GO", 18, WHITE, BL + 150, BR - 150, BT + 18, BT + 42, nil, true)
        box(v, 0x1A1A1A, 1, -750, -260, 860, 960)
        shield(v, -705, 868, 84, nextStep.idx, nextStep.tier, 1)
        text(v, "NEXT PROMOTION", 16, GREY, -650, -270, 874, 894, LEFT)
        text(v, stepLabel(nextStep), 26, RANKS[nextStep.idx].color, -650, -270, 896, 926, LEFT, true)
        srValue(v, nextStep.from, 18, GREY, -650, 930, "left")
    else
        text(v, "YOU ARE IN THE TOP 250: CHECK THE RANKING", 18, GOLDC, BL, BR, BT + 20, BT + 44, nil, true)
        image(v, TOP_ART, 0.8, -750, -260, 860, 960)
    end

    -- division road (right, top): 8 cards in 2 rows
    panel(v, "DIVISIONS", -210, 780, 258, 494)
    text(v, "ENTRY COST " .. rank.cost .. " SR", 16, RED, 400, 764, 268, 290, RIGHT, true)
    local cw, ch = 990 / 4, 90
    for k, r in ipairs(RANKS) do
        local col, row = (k - 1) % 4, math.floor((k - 1) / 4)
        local l, t = -210 + col * cw + 8, 298 + row * (ch + 6)
        local reached = p.sr >= r.start
        local now = (k == i)
        local card = box(v, r.color, now and 0.32 or (reached and 0.14 or 0.05), l, l + cw - 16, t, t + ch)
        if now then pulse(accent(card, 5), 0.22, 0.40) end
        local bars = (k == TOP) and 1 or 3
        local bw = (cw - 16) / bars
        for s = 0, bars - 1 do
            local lit = (k < i) or (now and ((k == TOP) or (list[cur].tier ~= nil and s <= list[cur].tier)))
            box(v, lit and r.color or 0x3A3A3A, 1, l + s * bw + 1, l + (s + 1) * bw - 1, t, t + 5)
        end
        shield(v, l + 44, t + 12, 70, k, nil, reached and 1 or 0.4)
        text(v, r.name, 20, reached and WHITE or GREY, l + 92, l + cw - 20, t + 22, t + 46, LEFT, true)
        local top = RANKS[k + 1] and (RANKS[k + 1].start - 1) or nil
        image(v, SR_ICON, reached and 1 or 0.5, l + 92, l + 112, t + 56, t + 74)
        text(v, r.start .. (top and (" - " .. top) or "+"), 16, GREY, l + 116, l + cw - 20, t + 55, t + 75, LEFT)
    end

    -- recent matches (right, middle)
    panel(v, "RECENT MATCHES", -210, 780, 504, 750)
    local cols = { { "RESULT", -184 }, { "KILLS", 0 }, { "DEATHS", 110 }, { "SR", 230 }, { "RP", 360 }, { "AFTER", 470 }, { "WHEN", 640 } }
    for _, c in ipairs(cols) do text(v, c[1], 14, DIM, c[2], c[2] + 130, 534, 552, LEFT) end
    if #history == 0 then
        text(v, "NO MATCH RECORDED YET: PLAY A RANKED MATCH (RESURGENCE QUADS)", 18, GREY, -184, 764, 600, 626, LEFT)
    end
    for k = 1, 5 do
        local m = history[#history - k + 1]
        if m then
            local t = 556 + (k - 1) * 38
            local win = m.delta > 0
            box(v, k % 2 == 0 and 0x161616 or 0x1C1C1C, 1, -200, 770, t, t + 34)
            box(v, win and GREEN or RED, 1, -200, -196, t, t + 34)
            text(v, win and "WIN" or "LOSS", 18, win and GREEN or RED, -184, -10, t + 7, t + 29, LEFT, true)
            text(v, tostring(m.kills), 18, WHITE, 0, 100, t + 7, t + 29, LEFT, true)
            text(v, tostring(m.deaths), 18, WHITE, 110, 220, t + 7, t + 29, LEFT, true)
            text(v, (m.delta >= 0 and "+" or "") .. m.delta, 18, win and GREEN or RED, 230, 350, t + 7, t + 29, LEFT, true)
            text(v, m.rp > 0 and ("+" .. m.rp) or "-", 18, RPC, 360, 460, t + 7, t + 29, LEFT, true)
            srValue(v, m.sr, 16, GREY, 470, t + 8, "left")
            local when = ""
            pcall(function() when = os.date("%d/%m %H:%M", m.time) end)
            text(v, when, 16, GREY, 640, 770, t + 8, t + 28, LEFT)
        end
    end

    -- today's quests (right, bottom)
    local quests = dailyQuests(day)
    local today_ = {}
    for _, m in ipairs(history) do if math.floor(m.time / 86400) == day then today_[#today_ + 1] = m end end
    local qs = readQuestState(day)
    panel(v, "DAILY QUESTS", -210, 780, 760, 984, GOLDC)
    local left = 86400 - (os.time() % 86400)
    local resetText = math.floor(left / 3600) .. "H " .. string.format("%02d", math.floor((left % 3600) / 60)) .. "M"
    text(v, "NEW QUESTS IN " .. resetText, 16, GREY, 400, 764, 770, 792, RIGHT)
    for k, q in ipairs(quests) do
        local t = 800 + (k - 1) * 58
        local val = math.min(q.goal, q.value(today_))
        local done = val >= q.goal
        image(v, STAR_ICON, done and 1 or 0.35, -194, -160, t + 6, t + 40)
        text(v, q.title, 18, done and GOLDC or WHITE, -150, 200, t + 2, t + 24, LEFT, true)
        text(v, q.desc, 14, GREY, -150, 400, t + 26, t + 44, LEFT)
        local fill = bar(v, 410, 640, t + 18, 8, done and GREEN or GOLDC)
        fill(val / q.goal)
        text(v, val .. " / " .. q.goal, 16, WHITE, 410, 640, t - 2, t + 16, RIGHT)
        local status = (qs.c[k] == 1) and "CLAIMED" or (done and "READY" or ("+" .. q.rp .. " RP"))
        text(v, status, 16, (qs.c[k] == 1) and DIM or (done and GREEN or RPC), 650, 764, t + 12, t + 32, RIGHT, true)
    end

    -- ================================================================
    -- QUESTS
    -- ================================================================
    v = views[2]
    panel(v, nil, -780, 780, 258, 984, GOLDC)
    image(v, STAR_ICON, 1, -760, -700, 276, 336)
    text(v, "DAILY QUESTS", 44, WHITE, -690, 0, 278, 330, LEFT, true)
    text(v, "3 NEW QUESTS EVERY DAY (UTC)  |  ONLY RANKED MATCHES COUNT  |  CLAIM TO GET THE REWARD", 16, GREY, -690, 780, 332, 352, LEFT)
    text(v, "RESET IN " .. resetText, 22, GOLDC, 300, 760, 290, 318, RIGHT, true)
    local function questCard(k, q)
        local t = 372 + (k - 1) * 150
        local val = math.min(q.goal, q.value(today_))
        local done = val >= q.goal
        box(v, 0x1A1A1A, 1, -760, 760, t, t + 136)
        box(v, done and GREEN or GOLDC, 1, -760, -754, t, t + 136)
        if done and qs.c[k] ~= 1 then pulse(box(v, GREEN, 0.10, -754, 760, t, t + 136), 0.04, 0.14) end
        image(v, STAR_ICON, done and 1 or 0.3, -730, -650, t + 28, t + 108)
        text(v, "QUEST " .. k, 16, GREY, -630, -200, t + 16, t + 36, LEFT)
        text(v, q.title, 34, done and GOLDC or WHITE, -630, 200, t + 36, t + 76, LEFT, true)
        text(v, q.desc, 18, GREY, -630, 300, t + 80, t + 102, LEFT)
        local fill = bar(v, -630, 300, t + 110, 12, done and GREEN or GOLDC)
        fill(val / q.goal)
        text(v, val .. " / " .. q.goal, 18, WHITE, 100, 300, t + 82, t + 104, RIGHT, true)
        text(v, "REWARD", 14, GREY, 330, 500, t + 20, t + 38, LEFT)
        srValue(v, "+" .. q.sr, 24, WHITE, 330, t + 42, "left")
        rpValue(v, "+" .. q.rp, 22, 330, t + 84)
        pageButton(2, (qs.c[k] == 1) and "CLAIMED" or (done and "CLAIM" or "IN PROGRESS"), 520, 750, t + 44, t + 92,
            function(lbl)
                local now = readQuestState(day)
                if now.c[k] == 1 or not done then return end
                now.c[k] = 1
                saveQuestState(now); qs = now
                giveReward(q.sr, q.rp)
                rp = rp + q.rp
                set(rpText, rp .. " RP")
                lbl("CLAIMED")
            end)
        return done
    end
    local allDone = true
    for k, q in ipairs(quests) do
        if not questCard(k, q) then allDone = false end
    end
    local bt = 828
    box(v, 0x1A1A1A, 1, -760, 760, bt, bt + 136)
    box(v, rank.color, 1, -760, -754, bt, bt + 136)
    shield(v, -690, bt + 18, 100, i, list[cur].tier, 1)
    text(v, "DAILY BONUS", 16, GREY, -630, -200, bt + 16, bt + 36, LEFT)
    text(v, "COMPLETE THE 3 QUESTS", 34, allDone and GOLDC or WHITE, -630, 300, bt + 36, bt + 76, LEFT, true)
    text(v, "CLAIM THE 3 QUESTS FIRST, THEN THE BONUS", 18, GREY, -630, 300, bt + 80, bt + 102, LEFT)
    text(v, "REWARD", 14, GREY, 330, 500, bt + 20, bt + 38, LEFT)
    srValue(v, "+" .. BONUS_SR, 24, WHITE, 330, bt + 42, "left")
    rpValue(v, "+" .. BONUS_RP, 22, 330, bt + 84)
    pageButton(2, (qs.bonus == 1) and "CLAIMED" or "CLAIM BONUS", 520, 750, bt + 44, bt + 92, function(lbl)
        local now = readQuestState(day)
        if now.bonus == 1 then return end
        if now.c[1] + now.c[2] + now.c[3] < 3 then lbl("CLAIM THE 3 FIRST"); return end
        now.bonus = 1
        saveQuestState(now); qs = now
        giveReward(BONUS_SR, BONUS_RP)
        rp = rp + BONUS_RP
        set(rpText, rp .. " RP")
        lbl("CLAIMED")
    end)

    -- ================================================================
    -- STATS
    -- ================================================================
    v = views[3]
    local kills, deaths, seconds, wins, bestKills, rpWon = 0, 0, 0, 0, 0, 0
    for _, m in ipairs(history) do
        kills = kills + m.kills; deaths = deaths + m.deaths; seconds = seconds + m.seconds
        rpWon = rpWon + m.rp
        if m.delta > 0 then wins = wins + 1 end
        bestKills = math.max(bestKills, m.kills)
    end
    local n = #history
    local tiles = {
        { "PLAYTIME", minutesText(seconds), WHITE },
        { "MATCHES", tostring(math.max(p.matches, n)), WHITE },
        { "WINS", tostring(wins), GREEN },
        { "WIN RATE", n > 0 and (math.floor(wins * 100 / n + 0.5) .. "%") or "-", WHITE },
        { "K/D", n > 0 and string.format("%.2f", kills / math.max(1, deaths)) or "-", WHITE },
        { "KILLS / MATCH", p.matches > 0 and string.format("%.1f", p.kills / p.matches) or "-", WHITE },
        { "BEST MATCH", bestKills .. " KILLS", GOLDC },
        { "RP WON", tostring(rpWon), RPC },
    }
    local tw = 1560 / #tiles
    for k, s in ipairs(tiles) do
        local l = -780 + (k - 1) * tw
        box(v, TILE, 0.85, l + 3, l + tw - 3, 258, 338)
        box(v, s[3], 1, l + 3, l + tw - 3, 258, 261)
        text(v, s[1], 14, GREY, l + 14, l + tw - 6, 270, 288, LEFT)
        text(v, s[2], 28, s[3], l + 14, l + tw - 6, 292, 326, LEFT, true)
    end
    if n == 0 then
        text(v, "THE CHARTS FILL UP WITH YOUR NEXT RANKED MATCHES", 20, GREY, -780, 780, 600, 628, nil, true)
    end

    -- chart helper: bars from a list of values, each with its own colour
    local function chart(title, l, r, t, b, values, colors, labels, unit)
        panel(v, title, l, r, t, b)
        local top, bottom = t + 52, b - 34
        local maxV = 1
        for _, x in ipairs(values) do maxV = math.max(maxV, x) end
        box(v, LINE, 1, l + 16, r - 16, bottom, bottom + 1)
        text(v, maxV .. (unit or ""), 14, DIM, l + 16, l + 160, top - 20, top - 4, LEFT)
        local slots = math.max(#values, 1)
        local w = (r - l - 32) / slots
        for k, x in ipairs(values) do
            local h = (bottom - top) * x / maxV
            local bl = l + 16 + (k - 1) * w + math.max(2, w * 0.18)
            local br = l + 16 + k * w - math.max(2, w * 0.18)
            local el = box(v, colors[k] or GOLDC, 0, bl, br, bottom - math.max(2, h), bottom)
            intro[#intro + 1] = { el = el, alpha = 0.9, ms = 120 + k * 35 }
            if labels and labels[k] then text(v, labels[k], 13, GREY, bl - 20, br + 20, bottom + 6, bottom + 22) end
            if #values <= 10 and x > 0 then text(v, tostring(x), 13, WHITE, bl - 20, br + 20, bottom - h - 18, bottom - h - 2) end
        end
    end

    local srV, srC, kV, kC = {}, {}, {}, {}
    for k = math.max(1, n - 19), n do
        local m = history[k]
        srV[#srV + 1] = math.max(0, m.sr)
        srC[#srC + 1] = RANKS[rankIndex(m.sr)].color
        kV[#kV + 1] = m.kills
        kC[#kC + 1] = (m.delta > 0) and GREEN or RED
    end
    chart("SR - LAST 20 MATCHES", -780, -10, 352, 650, srV, srC)
    chart("KILLS - LAST 20 MATCHES (GREEN = WIN)", 10, 780, 352, 650, kV, kC)

    local dayV, dayL, dayC = {}, {}, {}
    for k = 6, 0, -1 do
        local d = day - k
        local s = 0
        for _, m in ipairs(history) do if math.floor(m.time / 86400) == d then s = s + m.seconds end end
        dayV[#dayV + 1] = math.floor(s / 60)
        dayC[#dayC + 1] = (k == 0) and GOLDC or rank.color
        local label = (k == 0) and "TODAY" or ""
        if k > 0 then pcall(function() label = string.upper(os.date("%a %d", d * 86400 + 43200)) end) end
        dayL[#dayL + 1] = label
    end
    chart("PLAYTIME - LAST 7 DAYS (MINUTES)", -780, 780, 664, 984, dayV, dayC, dayL, " MIN")

    -- ================================================================
    -- RANKING (200 to 5000 local players, built the first time it is shown)
    -- ================================================================
    v = views[4]
    image(v, TOP_ART, 0.35, -780, 780, 258, 984)
    box(v, BLACK, 0.55, -780, 780, 258, 984)
    box(v, GOLDC, 1, -780, 780, 258, 260)
    image(v, shieldName(TOP, true), 1, -770, -660, 266, 376)
    local boardTitle = text(v, "", 50, GOLDC, -650, 300, 278, 334, LEFT, true)
    text(v, "SEASON " .. seasonNumber .. "  |  THE FIRST 250 ARE THE TOP 250 (17000 SR AND MORE)", 16, GREY, -650, 780, 338, 358, LEFT)
    local youText = text(v, "", 20, WHITE, -650, 780, 362, 388, LEFT, true)
    local podium = {}
    for k = 1, 3 do
        local l = -770 + (k - 1) * 520
        local c = ({ GOLDC, 0xD8D8D8, 0xCD7F32 })[k]
        box(v, c, 0.16, l, l + 500, 400, 466)
        box(v, c, 1, l, l + 6, 400, 466)
        text(v, "#" .. k, 34, c, l + 20, l + 110, 412, 454, LEFT, true)
        podium[k] = { name = text(v, "", 24, WHITE, l + 110, l + 490, 408, 436, LEFT, true),
            sr = text(v, "", 18, c, l + 140, l + 490, 440, 462, LEFT, true) }
        image(v, SR_ICON, 1, l + 110, l + 132, 442, 461)
    end
    text(v, "#", 14, DIM, -770, -680, 474, 492, LEFT)
    text(v, "PLAYER", 14, DIM, -600, 0, 474, 492, LEFT)
    text(v, "MATCHES", 14, DIM, 0, 180, 474, 492, RIGHT)
    text(v, "KILLS", 14, DIM, 200, 380, 474, 492, RIGHT)
    text(v, "SR", 14, DIM, 440, 740, 474, 492, RIGHT)
    local rows = {}
    for k = 1, 10 do
        local t = 496 + (k - 1) * 38
        local row = {}
        row.back = box(v, 0x1A1A1A, 0.85, -770, 770, t, t + 34)
        row.mark = box(v, GOLDC, 1, -770, -766, t, t + 34)
        row.pos = text(v, "", 20, WHITE, -756, -660, t + 7, t + 29, LEFT, true)
        row.icon = image(v, shieldName(TOP, false), 1, -652, -622, t + 2, t + 32)
        row.name = text(v, "", 20, WHITE, -600, 0, t + 7, t + 29, LEFT, true)
        row.matches = text(v, "", 18, GREY, 0, 180, t + 8, t + 28, RIGHT)
        row.kills = text(v, "", 18, GREY, 200, 380, t + 8, t + 28, RIGHT)
        row.sr = text(v, "", 20, GOLDC, 440, 728, t + 7, t + 29, RIGHT, true)
        row.srIcon = image(v, SR_ICON, 1, 734, 756, t + 8, t + 27)
        rows[k] = row
    end
    local pageText = text(v, "", 18, WHITE, -200, 200, 880, 904, nil, true)
    local entries, mine, boardPage, boardPages = nil, nil, 1, 1
    local function showPage(nPage)
        boardPage = math.max(1, math.min(boardPages, nPage))
        for k = 1, 10 do
            local pos = (boardPage - 1) * 10 + k
            local e = entries[pos]
            local row = rows[k]
            for _, el in pairs(row) do pcall(el.SetAlpha, el, e and 1 or 0, 0) end
            if e then
                local d = rankIndex(e.sr)
                set(row.pos, "#" .. pos)
                set(row.name, e.name)
                set(row.matches, e.me and tostring(p.matches) or tostring(e.matches))
                set(row.kills, e.me and tostring(p.kills) or tostring(e.kills))
                set(row.sr, tostring(e.sr))
                pcall(row.sr.SetRGB, row.sr, RANKS[d].color, 0)
                pcall(function() row.icon:setImage(RegisterMaterial(shieldName(d, false)), 0) end)
                pcall(row.back.SetRGB, row.back, e.me and 0x24402A or 0x1A1A1A, 0)
                pcall(row.pos.SetRGB, row.pos, pos <= 3 and GOLDC or WHITE, 0)
                pcall(row.mark.SetAlpha, row.mark, (e.me or pos <= 3) and 1 or 0, 0)
                pcall(row.mark.SetRGB, row.mark, e.me and GREEN or GOLDC, 0)
            end
        end
        set(pageText, "PAGE " .. boardPage .. " / " .. boardPages)
    end
    local function buildBoard()
        local size = settings.board
        entries, mine = makeBoard(seasonNumber, p.matches, player, p.sr, size)
        boardPages = math.max(1, math.ceil(#entries / 10))
        set(boardTitle, "TOP " .. size)
        set(youText, mine and ("YOU ARE #" .. mine .. " WITH " .. p.sr .. " SR")
            or ("NOT IN THE TOP " .. size .. " YET: BEAT #" .. size .. " (" .. entries[#entries].sr .. " SR)"))
        pcall(youText.SetRGB, youText, mine and GREEN or WHITE, 0)
        for k = 1, 3 do
            set(podium[k].name, entries[k].name)
            set(podium[k].sr, tostring(entries[k].sr))
        end
        showPage(1)
    end
    local W, G = 214, 7
    local function bx(k) return -770 + (k - 1) * (W + G) end
    pageButton(4, "TOP 10", bx(1), bx(1) + W, 912, 956, function() showPage(1) end)
    pageButton(4, "<< 10", bx(2), bx(2) + W, 912, 956, function() showPage(boardPage - 10) end)
    pageButton(4, "< PREV", bx(3), bx(3) + W, 912, 956, function() showPage(boardPage - 1) end)
    pageButton(4, "NEXT >", bx(4), bx(4) + W, 912, 956, function() showPage(boardPage + 1) end)
    pageButton(4, "10 >>", bx(5), bx(5) + W, 912, 956, function() showPage(boardPage + 10) end)
    pageButton(4, "FIND ME", bx(6), bx(6) + W, 912, 956, function(lbl)
        if mine then showPage(math.ceil(mine / 10)) else showPage(boardPages); lbl("NOT IN IT") end
    end)
    pageButton(4, "SIZE: " .. settings.board, bx(7), bx(7) + W, 912, 956, function(lbl)
        local nextSize = BOARD_SIZES[1]
        for k, sz in ipairs(BOARD_SIZES) do if sz == settings.board then nextSize = BOARD_SIZES[(k % #BOARD_SIZES) + 1] end end
        settings.board = nextSize; saveSettings(settings)
        lbl("SIZE: " .. nextSize)
        buildBoard()
    end)

    -- ================================================================
    -- SETTINGS (+ rules)
    -- ================================================================
    v = views[5]
    panel(v, "SETTINGS", -780, -10, 258, 984)
    panel(v, "RULES", 10, 780, 258, 984, rank.color)
    local s = settings
    local ONOFF = { [0] = "OFF", [1] = "ON" }
    local SPEED = { "SLOW", "NORMAL", "FAST" }
    local function setting(k, labelText, help, light, action)
        local t = 300 + (k - 1) * 112
        local lamp = box(v, light(), 1, -760, -754, t, t + 52)
        text(v, help, 16, GREY, -740, -30, t + 60, t + 82, LEFT)
        pageButton(5, labelText, -740, -30, t, t + 52, function(lbl)
            pcall(action, lbl)
            pcall(lamp.SetRGB, lamp, light(), 150)
        end)
    end
    local function onoff(key) return function() return s[key] == 1 and GREEN or RED end end
    setting(1, "RANKED: " .. ONOFF[s.ranked], "OFF = MATCHES DO NOT COST OR GIVE SR (CHANGES APPLY NEXT MATCH)", onoff("ranked"), function(lbl)
        s.ranked = 1 - s.ranked; saveSettings(s); state.settings = s; lbl("RANKED: " .. ONOFF[s.ranked])
    end)
    setting(2, "RANK AT SPAWN: " .. ONOFF[s.spawnmsg], "YOUR RANK ON SCREEN WHEN YOU SPAWN", onoff("spawnmsg"), function(lbl)
        s.spawnmsg = 1 - s.spawnmsg; saveSettings(s); state.settings = s; lbl("RANK AT SPAWN: " .. ONOFF[s.spawnmsg])
    end)
    setting(3, "ANIMATED COLORS: " .. ONOFF[s.anim], "FLOWING COLOURS OF IRIDESCENT AND TOP 250", onoff("anim"), function(lbl)
        s.anim = 1 - s.anim; saveSettings(s); state.settings = s; lbl("ANIMATED COLORS: " .. ONOFF[s.anim])
    end)
    setting(4, "ANIMATION: " .. SPEED[s.speed], "SPEED OF THE FLOWING COLOURS",
        function() return ({ GREY, WHITE, AMBER })[s.speed] or WHITE end, function(lbl)
        s.speed = (s.speed % 3) + 1; saveSettings(s); state.settings = s; lbl("ANIMATION: " .. SPEED[s.speed])
    end)
    setting(5, "RANKING SIZE: " .. s.board, "PLAYERS IN THE RANKING PAGE: 200, 500, 1000, 2000, 3000 OR 5000", function() return GOLDC end, function(lbl)
        local nextSize = BOARD_SIZES[1]
        for k, sz in ipairs(BOARD_SIZES) do if sz == s.board then nextSize = BOARD_SIZES[(k % #BOARD_SIZES) + 1] end end
        s.board = nextSize; saveSettings(s); lbl("RANKING SIZE: " .. nextSize)
        entries = nil
    end)
    local armed = 0
    setting(6, "NEW SEASON (RESET SR)", "BACK TO BRONZE I WITH 0 SR. CLICK TWICE TO CONFIRM", function() return armed > 0 and AMBER or RED end, function(lbl)
        local now = os.clock()
        if now - armed > 4 then
            armed = now; lbl("CLICK AGAIN TO CONFIRM")
        else
            armed = 0
            local ok, season = newSeason()
            if ok then lbl("SEASON " .. season .. " STARTED: SR 0") else lbl("RESET FAILED") end
        end
    end)
    local rules = {
        { "KILLS", "+10 SR PER KILL, MORE IN BRONZE (x3), SILVER (x2.2) AND GOLD (x1.4)." },
        { "DEATHS", "-20 SR PER DEATH: x0.25 IN BRONZE UP TO x3.3 IN TOP 250." },
        { "SPEED", "BRONZE AND SILVER GO FAST, GOLD A BIT LESS. FROM PLATINUM IT GETS HARD." },
        { "ENTRY COST", "PAID AT THE START (QUIT = LOST): 0 / 10 / 30 / 70 / 120 / 160 / 200 / 260." },
        { "MIN KILLS", "UNDER IT KILLS GIVE NOTHING: PLATINUM 5, DIAMOND 20, CRIMSON 35, IRIDESCENT 40, TOP 250 50." },
        { "MODE", "RANKED COUNTS ONLY IN RESURGENCE QUADS." },
        { "STEPS", "EACH DIVISION HAS 3 STEPS (I, II, III). TOP 250 STARTS AT 17000 SR." },
        { "RP", "RANKED POINTS: 3 PER KILL, +1 PER 8 SR WON, +100 PER RANK UP, WIN STREAK +10% (MAX +50%)." },
        { "SEASON", "EVERY " .. SEASON_DAYS .. " DAYS. NEW SEASON = SR BACK TO 0." },
        { "QUESTS", "3 DAILY QUESTS GIVE SR AND RP. CLAIM THEM IN THE QUESTS PAGE." },
    }
    for k, r in ipairs(rules) do
        local t = 300 + (k - 1) * 66
        text(v, r[1], 18, rank.color, 30, 220, t, t + 24, LEFT, true)
        text(v, r[2], 15, WHITE, 220, 770, t + 2, t + 24, LEFT)
        box(v, LINE, 1, 30, 770, t + 50, t + 51)
    end

    -- page buttons in the header, with an underline on the current page
    local navL, navW = -120, 178
    local underline = accent(box(root, rank.color, 1, navL, navL + navW - 10, 186, 190), 6)
    local function showView(k)
        current = k
        if k == 4 and not entries then pcall(buildBoard) end
        for j = 1, #PAGES do
            pcall(views[j].SetAlpha, views[j], (j == k) and 1 or 0, 150)
            for _, e in ipairs(pageButtons[j]) do
                local off = (j == k) and 0 or 6000
                place(e.btn, e.l + off, e.r + off, e.t, e.b)
            end
        end
        local l = navL + (k - 1) * navW
        place(underline, l, l + navW - 10, 186, 190)
    end
    for k, name in ipairs(PAGES) do
        local l = navL + (k - 1) * navW
        local btn = MenuBuilder.BuildRegisteredType("GenericButton", { controllerIndex = controller })
        btn:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, l + navW - 10, 134, 182)
        root:addElement(btn)
        if btn.Text then
            pcall(btn.Text.SetFontSize, btn.Text, 18)
            pcall(btn.Text.setText, btn.Text, name)
        end
        btn:addEventHandler("button_action", function() pcall(showView, k) end)
    end

    -- one 55 ms timer: SR counting up, the living SR bar, pulses, flowing colours
    state.settings = settings
    local SPEEDS = { slow = { 16, 8, 4 }, fast = { 4, 2, 1 } }
    local phase, shown, up, shineX = 0, 0, true, BL
    root:registerEventHandler("br95_iris_tick", function()
        phase = phase + 1
        if phase == 2 then
            for _, e in ipairs(intro) do pcall(e.el.SetAlpha, e.el, e.alpha, e.ms) end
        end
        -- SR counts up and the bar follows it
        if shown < p.sr then
            shown = math.min(p.sr, shown + math.max(1, math.ceil(p.sr / 22)))
            set(srText, tostring(shown))
            pcall(setHero, heroPct * shown / math.max(1, p.sr))
        elseif phase == 3 then
            pcall(setHero, heroPct)
        end
        -- a light runs along the filled part of the bar
        shineX = shineX + 9
        if shineX > heroRight + 60 then shineX = BL - 60 end
        local sl, sr = math.max(BL, shineX), math.min(heroRight, shineX + 60)
        if sr > sl then
            place(shine, sl, sr, BT, BT + BH); pcall(shine.SetAlpha, shine, 0.35, 0)
        else
            pcall(shine.SetAlpha, shine, 0, 0)
        end
        -- the tip of the bar breathes
        if phase % 11 == 0 then pcall(tip.SetAlpha, tip, (phase % 22 == 0) and 1 or 0.25, 550) end
        if phase % 22 == 0 then
            up = not up
            for _, pu in ipairs(pulses) do pcall(pu.el.SetAlpha, pu.el, up and pu.hi or pu.lo, 1150) end
        end
        local live = state.settings or settings
        if live.anim ~= 1 or not flowing then return end
        local sp = math.max(1, math.min(3, live.speed or 2))
        local slow = SPEEDS[kind][sp]
        if phase % slow == 0 then
            local step = math.floor(phase / slow)
            for _, e in ipairs(animated) do
                pcall(e.el.SetRGB, e.el, pal[((step + e.off) % #pal) + 1], 55 * slow)
            end
        end
    end)
    root:addElement(LUI.UITimer.new({ interval = 55, event = "br95_iris_tick", eventTarget = root, disposable = false }))
    return root
end

-- shared with the lobby card (br95_ranked_lobby_post.lua)
state.shared = { RANKS = RANKS, readProfile = readProfile, rankIndex = rankIndex, steps = steps, stepOf = stepOf,
    stepLabel = stepLabel, shieldName = shieldName, tierOverlay = tierOverlay, percentText = percentText,
    font = font, SR_ICON = SR_ICON, STAR_ICON = STAR_ICON, readRP = readRP }

local function install()
    if state.installed then return true end
    if type(MenuBuilder) ~= "table" or type(MenuBuilder.registerType) ~= "function" then return false end
    if type(MAINMENUTABS) ~= "table" or type(MAINMENUTABS.TabData) ~= "table" or type(MAINMENUTABS.Layouts) ~= "table" then return false end

    MenuBuilder.registerType(MENU, function(menu, options)
        local controller = type(options) == "table" and options.controllerIndex or 0
        return build(menu, controller)
    end)

    local data = MAINMENUTABS.TabData
    if not data[MENU] then
        local sound = type(data.CustomizeMenu) == "table" and data.CustomizeMenu.menuSound or nil
        data[MENU] = { menuName = MENU, name = "RANKED", menuSound = sound,
            isHidden = function() return false end, isDisabled = function() return false end,
            onFocusCallback = function() return true end, menuSpecificCallback = function() end }
    end

    for _, lobby in ipairs({ "WarzonePrivateMatchLobby", "PrivateMatchLobby", "MPSystemLinkLobby" }) do
        local layout = MAINMENUTABS.Layouts[lobby]
        if type(layout) == "table" then
            local present = false
            for _, entry in ipairs(layout) do if entry == MENU then present = true end end
            if not present then table.insert(layout, MENU) end
        end
    end

    state.installed = true
    if DebugPrint then pcall(DebugPrint, "[BR95Ranked] menu tab installed") end
    return true
end

local function tryInstall()
    local ok, err = pcall(install)
    if not ok then
        state.error = tostring(err)
        if DebugPrint then pcall(DebugPrint, "[BR95Ranked] menu error: " .. state.error) end
    end
end

tryInstall()

-- not ready yet at load time: retry when a UI root is created
if not state.installed and LUI and LUI.UIRoot and type(LUI.UIRoot.init) == "function" then
    local original = LUI.UIRoot.init
    LUI.UIRoot.init = function(root, ...)
        local result = original(root, ...)
        tryInstall()
        return result
    end
end
