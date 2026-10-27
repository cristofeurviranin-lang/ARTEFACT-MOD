-- BR95 Level: LEVEL tab of the lobby, the classic MULTIPLAYER level ranking.
-- Points (SR) only go up: kill +10, assist +5, win +50, draw +15. Going from level L
-- to L + 1 costs 100 + L SR (level 1000 is the maximum). Every 100 levels the level
-- gets a new name and colour that moves a little (Silver, Platinum, Diamond, ...) and
-- from level 100 the play time is shown. Reads the files written by
-- br95_ranked_core_post.lua. Wrapped in pcall: if something is missing the tab is
-- just not added. Fully restart the game after changes.
if BR95LevelTab then return end
local state = { installed = false }
BR95LevelTab = state

local MENU = "BR95LevelMenu"
local DIR = "jupiter/IO/"
local WHITE, GREY, DIM, LINE, TILE, BLACK = 0xFFFFFF, 0x9A9A9A, 0x5A5A5A, 0x2E2E2E, 0x161616, 0x000000
local GREEN, LOSS = 0x6BD66B, 0xE04040
local MAX_LEVEL = 1000

-- colour of each block of 100 levels (index 1 = levels 0..99): the ranked names and
-- colours (without Bronze), then gold, emerald, ruby and the rainbow at 1000
local TIERS = {
    { name = "ROOKIE",     c1 = 0xD9262E, c2 = 0xD9262E },
    { name = "SILVER",     c1 = 0xC8C8C8, c2 = 0xFFFFFF },
    { name = "PLATINUM",   c1 = 0x7FE0D6, c2 = 0xC8FFF8 },
    { name = "DIAMOND",    c1 = 0x4FA3FF, c2 = 0xB0D8FF },
    { name = "CRIMSON",    c1 = 0xDC143C, c2 = 0xFF6A80 },
    { name = "IRIDESCENT", c1 = 0xC77DFF, c2 = 0x6FF0E4,
      cycle = { 0xB57CFF, 0xF07CFF, 0xEDEDF7, 0x6FF0E4, 0xFFE08A, 0x7FA2FF } },
    { name = "PAINITE",    c1 = 0xFF4D5E, c2 = 0xB0303A },
    { name = "GOLD",       c1 = 0xFFC93C, c2 = 0xFFF0B0 },
    { name = "EMERALD",    c1 = 0x2ECC71, c2 = 0xB5FFD3 },
    { name = "RUBY",       c1 = 0xE0245E, c2 = 0xFF9DB8 },
    { name = "PRISMATIC",  c1 = 0xFF7AD9, c2 = 0x7AD9FF, rainbow = true },
}
local function tierIndex(level) return math.min(#TIERS, math.floor(level / 100) + 1) end

local function mix(a, b, s)
    local ar, ag, ab = math.floor(a / 65536) % 256, math.floor(a / 256) % 256, a % 256
    local br, bg, bb = math.floor(b / 65536) % 256, math.floor(b / 256) % 256, b % 256
    return math.floor(ar + (br - ar) * s) * 65536 + math.floor(ag + (bg - ag) * s) * 256 + math.floor(ab + (bb - ab) * s)
end

local function rainbow(h)
    local x = h * 6
    local i = math.floor(x) % 6
    local f = x - math.floor(x)
    local s = 0.6
    local p, q, t = 1 - s, 1 - f * s, 1 - (1 - f) * s
    local r, g, b
    if i == 0 then r, g, b = 1, t, p
    elseif i == 1 then r, g, b = q, 1, p
    elseif i == 2 then r, g, b = p, 1, t
    elseif i == 3 then r, g, b = p, q, 1
    elseif i == 4 then r, g, b = t, p, 1
    else r, g, b = 1, p, q end
    return math.floor(r * 255) * 65536 + math.floor(g * 255) * 256 + math.floor(b * 255)
end

-- animated colour of a tier at time t (seconds)
local function tierColor(index, t)
    local tier = TIERS[index]
    if tier.rainbow then return rainbow((t * 0.12) % 1) end
    if tier.cycle then
        local n = #tier.cycle
        local pos = (t * 0.3) % n
        local i = math.floor(pos)
        return mix(tier.cycle[i + 1], tier.cycle[(i + 1) % n + 1], pos - i)
    end
    if tier.c1 == tier.c2 then return tier.c1 end
    return mix(tier.c1, tier.c2, (math.sin(t * 2.4) + 1) / 2)
end

local function trace(msg)
    pcall(function()
        local f = io.open(DIR .. "br95_level_trace.txt", "a")
        if f then f:write(os.date("%H:%M:%S") .. " " .. msg .. "\n"); f:close() end
    end)
end

local function matchOf(text, pattern)
    if not text then return nil end
    return text:match(pattern)
end

local function readText(path)
    local text
    pcall(function()
        local f = io.open(path, "r")
        if f then text = f:read("*a"); f:close() end
    end)
    return text
end

local function readProfile()
    local p = { sr = 0, matches = 0, kills = 0, level = 0, last = 0 }
    local sr, m, k, b, l = matchOf(readText(DIR .. "br95_mp_ranked.txt"), "^BR95R1|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|END")
    if sr then p.sr, p.matches, p.kills, p.level, p.last = tonumber(sr), tonumber(m), tonumber(k), tonumber(b), tonumber(l) end
    return p
end

-- oldest first: { sr, gain, kills, assists, result (1 win, 2 loss, 3 draw) }
local function readHistory()
    local list = {}
    local text = readText(DIR .. "br95_mp_history.txt")
    if text then
        for line in text:gmatch("[^\n]+") do
            local sr, gain, k, a, r = line:match("^H|(%-?%d+)|(%-?%d+)|(%d+)|(%d+)|(%d+)")
            if sr then list[#list + 1] = { sr = tonumber(sr), gain = tonumber(gain), k = tonumber(k), a = tonumber(a), r = tonumber(r) } end
        end
    end
    return list
end

local function readStreak()
    local a, b = matchOf(readText(DIR .. "br95_mp_streak.txt"), "^BR95W1|(%d+)|(%d+)|END")
    return tonumber(a) or 0, tonumber(b) or 0
end

local function readRP()
    return tonumber(matchOf(readText(DIR .. "br95_rp.txt"), "^BR95P1|(%d+)|END")) or 0
end

local function readSeconds()
    return tonumber(matchOf(readText(DIR .. "br95_mp_time.txt"), "^BR95T1|(%d+)|END")) or 0
end

-- world rank written by the sync program: BR95X1|OK|place 12 of 340|time|END
local function readWorld()
    local place, total = matchOf(readText(DIR .. "br95_world_status.txt"), "place (%d+) of (%d+)")
    if place then return tonumber(place), tonumber(total) end
    return nil
end

-- season of 40 days (same calendar for everybody), file BR95S2|number|season SR|END
local SEASON_EPOCH = 1792613644
local SEASON_LENGTH = 40 * 86400
local function seasonInfo()
    local now = os.time()
    local number = math.max(1, math.floor((now - SEASON_EPOCH) / SEASON_LENGTH) + 1)
    local left = SEASON_EPOCH + number * SEASON_LENGTH - now
    local n, sr = matchOf(readText(DIR .. "br95_mp_season.txt"), "^BR95S2|(%d+)|(%d+)|END")
    local seasonSR = (tonumber(n) == number) and (tonumber(sr) or 0) or 0
    return number, left, seasonSR
end

local function needFor(level)
    if level <= 0 then return 0 end
    return 100 * level + level * (level - 1) / 2
end

local function levelOf(sr)
    local lv = math.floor(-99.5 + math.sqrt(99.5 * 99.5 + 2 * sr))
    if lv < 0 then lv = 0 end
    while lv > 0 and needFor(lv) > sr do lv = lv - 1 end
    while lv < MAX_LEVEL and needFor(lv + 1) <= sr do lv = lv + 1 end
    return lv
end

local function thousands(n)
    local s = tostring(math.floor(n))
    return (s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", ""))
end

local RESULT = { [1] = { "WIN", GREEN }, [2] = { "LOSS", LOSS }, [3] = { "DRAW", GREY } }

local function font(text, size, bold)
    if FONTS and FONTS.GetFont then
        local f = bold and FONTS.PrimaryBold or FONTS.SecondaryRegular
        if f and f.File then pcall(text.SetFont, text, FONTS.GetFont(f.File)) end
    end
    if text.SetFontSize then pcall(text.SetFontSize, text, size) end
end

local function build(menu, controller)
    local root = LUI.UIElement.new(); root.id = MENU
    root:SetAnchorsAndPosition(0.5, 0.5, 0, 1, -960, 960, 0, 1080)   -- 1920 box centered on the tab area
    local LEFT = LUI.Alignment and LUI.Alignment.Left
    local RIGHT = LUI.Alignment and LUI.Alignment.Right
    local CENTER = LUI.Alignment and LUI.Alignment.Center

    local function box(color, alpha, l, r, t, b)
        local child = LUI.UIImage.new()
        child:SetRGB(color, 0); child:SetAlpha(alpha, 0)
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        root:addElement(child); return child
    end
    local function text(str, size, color, l, r, t, b, align, bold)
        local child = LUI.UIText.new()
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        font(child, size, bold)
        if child.SetAlignment and LUI.Alignment then child:SetAlignment(align or LEFT) end
        child:SetRGB(color or WHITE, 0)
        child:setText(str)
        root:addElement(child); return child
    end

    local p = readProfile()
    local level = levelOf(p.sr)
    local tidx = tierIndex(level)
    local tier = TIERS[tidx]
    local atMax = level >= MAX_LEVEL
    local base = needFor(level)
    local nextAt = atMax and base or needFor(level + 1)
    local pct = atMax and 1 or math.max(0, math.min(1, (p.sr - base) / (nextAt - base)))
    local hist = readHistory()
    local streak, bestStreak = readStreak()
    local rp = readRP()
    local place, total = readWorld()
    local seconds = readSeconds()
    local seasonNumber, seasonLeft, seasonSR = seasonInfo()
    local accent = tier.c1

    -- things that move (colour of the tier, shine on the bar)
    local anim = {}
    local function animate(el, kind) anim[#anim + 1] = { el = el, kind = kind } end

    -- panel + header
    box(BLACK, 0.84, -800, 800, 110, 935)
    animate(box(accent, 1, -800, 800, 110, 113), "tier")
    text("MULTIPLAYER LEVEL", 36, WHITE, -770, 0, 128, 176, LEFT, true)
    local worldText = "WORLD RANK: JOIN FROM THE MAIN MENU"
    if place then worldText = "WORLD RANK  #" .. place .. "  OF  " .. tostring(total or "?") end
    text(worldText, 20, GREY, 150, 770, 140, 168, RIGHT)
    local days = math.floor(seasonLeft / 86400)
    local hours = math.floor((seasonLeft % 86400) / 3600)
    text("SEASON " .. seasonNumber .. "   |   " .. days .. "D " .. string.format("%02d", hours) .. "H LEFT   |   " .. thousands(seasonSR) .. " SEASON SR", 18, GREY, -380, 140, 142, 168, CENTER)
    box(LINE, 1, -770, 770, 184, 185)

    -- LEFT: your level
    local fl, fr, ft, fb = -770, -620, 208, 358
    animate(box(accent, 1, fl, fr, ft, ft + 4), "tier")
    animate(box(accent, 1, fl, fr, fb - 4, fb), "tier")
    animate(box(accent, 1, fl, fl + 4, ft, fb), "tier")
    animate(box(accent, 1, fr - 4, fr, ft, fb), "tier")
    text("MP LEVEL", 16, GREY, fl, fr, ft + 14, ft + 40, CENTER)
    local digits = #tostring(level)
    animate(text(tostring(level), (digits >= 4) and 64 or ((digits == 3) and 78 or 92), accent, fl, fr, ft + 44, ft + 140, CENTER, true), "tier")

    text(thousands(p.sr) .. " SR", 52, WHITE, -592, 0, 204, 266, LEFT, true)
    text("TOTAL POINTS. THEY ONLY GO UP.", 17, GREY, -592, 0, 268, 292, LEFT)
    if level >= 100 then
        animate(text(tier.name .. "   |   PLAYTIME  " .. string.format("%.1f", seconds / 3600) .. " H", 24, accent, -592, 0, 304, 336, LEFT, true), "tier")
    else
        text("ROOKIE   |   FIRST NAME AND COLOUR AT LEVEL 100 (SILVER)", 18, DIM, -592, 0, 306, 334, LEFT)
    end
    if atMax then
        text("MAX LEVEL REACHED", 18, WHITE, -592, 0, 336, 360, LEFT, true)
    end

    -- progress bar with a moving shine
    local barL, barR, barT = -770, -30, 392
    box(LINE, 1, barL, barR, barT, barT + 16)
    local fillW = math.floor((barR - barL) * pct)
    local fill, shine
    if fillW > 0 then
        fill = box(accent, 1, barL, barL + fillW, barT, barT + 16)
        animate(fill, "tier")
        if fillW >= 60 then shine = box(WHITE, 0.45, barL, barL + 30, barT, barT + 16) end
    end
    text(thousands(base) .. " SR", 15, DIM, barL, barL + 200, barT + 22, barT + 44, LEFT)
    if atMax then
        text("MAX LEVEL", 18, WHITE, barL + 100, barR - 100, barT + 22, barT + 46, CENTER, true)
    else
        text(thousands(nextAt - p.sr) .. " SR TO LEVEL " .. (level + 1) .. "   (" .. math.floor(pct * 100) .. "%)", 18, WHITE, barL + 100, barR - 100, barT + 22, barT + 46, CENTER, true)
    end
    text(thousands(nextAt) .. " SR", 15, DIM, barR - 200, barR, barT + 22, barT + 44, RIGHT)

    -- how to earn SR
    text("HOW TO EARN   SR = YOUR LEVEL   RP = SHOP POINTS", 18, WHITE, -770, -30, 462, 488, LEFT, true)
    local earn = { { "KILL", "+10", "+2 RP" }, { "ASSIST", "+5", "+1 RP" }, { "WIN", "+50", "+40 RP" }, { "DRAW", "+15", "+15 RP" } }
    local ew, eg = 175, 13.3
    for k, e in ipairs(earn) do
        local l = math.floor(-770 + (k - 1) * (ew + eg))
        box(TILE, 1, l, l + ew, 496, 566)
        box(accent, 1, l, l + 4, 496, 566)
        text(e[1], 15, GREY, l + 16, l + ew, 502, 524, LEFT)
        text(e[2], 32, WHITE, l + 16, l + ew, 520, 556, LEFT, true)
        text(e[3], 18, GREY, l + 70, l + ew - 10, 526, 552, RIGHT, true)
    end

    -- RIGHT: SR earned per match (last 10)
    text("SR EARNED IN YOUR LAST 10 MATCHES", 18, WHITE, 30, 770, 196, 222, LEFT, true)
    text("ONE BAR = ONE MATCH.  W WIN   L LOSS   D DRAW", 15, GREY, 30, 770, 222, 244, LEFT)
    local ground, slot, barW = 366, 72, 48
    box(LINE, 1, 30, 770, ground, ground + 1)
    if #hist == 0 then
        text("NO MATCH YET. PLAY A MULTIPLAYER MATCH.", 18, DIM, 30, 770, ground - 40, ground - 14, LEFT)
    else
        local from = math.max(1, #hist - 9)
        local maxGain = 100
        for k = from, #hist do maxGain = math.max(maxGain, hist[k].gain) end
        local scale = 90 / maxGain
        for k = from, #hist do
            local h = hist[k]
            local x = 44 + (k - from) * slot
            local bh = math.max(3, math.floor(h.gain * scale))
            box(accent, (h.r == 1) and 1 or 0.45, x, x + barW, ground - bh, ground)
            text("+" .. h.gain, 14, WHITE, x - 12, x + barW + 12, ground - bh - 22, ground - bh - 2, CENTER, true)
            local res = RESULT[h.r] or RESULT[3]
            text(res[1]:sub(1, 1), 15, res[2], x, x + barW, ground + 6, ground + 28, CENTER, true)
        end
    end

    -- RIGHT: stat tiles (2 rows of 3)
    local wins, kills, assists, shown = 0, 0, 0, 0
    for k = math.max(1, #hist - 9), #hist do
        shown = shown + 1
        if hist[k].r == 1 then wins = wins + 1 end
        kills = kills + hist[k].k
        assists = assists + hist[k].a
    end
    local tiles = {
        { "MATCHES PLAYED", tostring(p.matches) },
        { "WIN RATE (LAST 10)", (shown > 0) and (math.floor(wins * 100 / shown) .. "%") or "-" },
        { "WIN STREAK", streak .. "  (BEST " .. bestStreak .. ")" },
        { "KILLS / ASSISTS PER MATCH", (shown > 0) and (string.format("%.1f", kills / shown) .. " / " .. string.format("%.1f", assists / shown)) or "-" },
        { "PLAY TIME", string.format("%.1f", seconds / 3600) .. " H" },
        { "SHOP POINTS (RP)", thousands(rp) },
    }    local tw, tgap = 236, 16
    for k, tile in ipairs(tiles) do
        local col, row = (k - 1) % 3, math.floor((k - 1) / 3)
        local l = 30 + col * (tw + tgap)
        local t = 410 + row * 80
        box(TILE, 1, l, l + tw, t, t + 70)
        box(accent, 1, l, l + 4, t, t + 70)
        text(tile[1], 14, GREY, l + 16, l + tw, t + 6, t + 28, LEFT)
        text(tile[2], 28, WHITE, l + 16, l + tw, t + 28, t + 64, LEFT, true)
    end

    -- BOTTOM LEFT: recent matches
    text("RECENT MATCHES", 18, WHITE, -770, -30, 590, 616, LEFT, true)
    local cols = { { "RESULT", -770, -640 }, { "KILLS", -640, -540 }, { "ASSISTS", -540, -430 }, { "POINTS", -430, -300 }, { "TOTAL SR", -300, -30 } }
    for _, c in ipairs(cols) do text(c[1], 14, DIM, c[2], c[3], 620, 640, (c[1] == "TOTAL SR") and RIGHT or LEFT) end
    box(LINE, 1, -770, -30, 643, 644)
    if #hist == 0 then text("YOUR MATCHES WILL SHOW HERE.", 17, DIM, -770, -30, 656, 682, LEFT) end
    for r = 1, 5 do
        local h = hist[#hist - r + 1]
        if h then
            local t = 650 + (r - 1) * 34
            local res = RESULT[h.r] or RESULT[3]
            text(res[1], 20, res[2], -770, -640, t + 2, t + 30, LEFT, true)
            text(tostring(h.k), 20, WHITE, -640, -540, t + 2, t + 30, LEFT)
            text(tostring(h.a), 20, WHITE, -540, -430, t + 2, t + 30, LEFT)
            text("+" .. h.gain, 20, accent, -430, -300, t + 2, t + 30, LEFT, true)
            text(thousands(h.sr), 18, GREY, -300, -30, t + 2, t + 30, RIGHT)
            box(LINE, 1, -770, -30, t + 32, t + 33)
        end
    end

    -- BOTTOM RIGHT: the colour of every 100 levels
    text("A NEW COLOUR EVERY 100 LEVELS", 18, WHITE, 30, 770, 590, 616, LEFT, true)
    for k = 1, 10 do
        local col, row = (k - 1) % 2, math.floor((k - 1) / 2)
        local l = 30 + col * 380
        local t = 626 + row * 38
        local reached = level >= k * 100
        local tr = TIERS[k + 1]
        local swatch = box(tr.c1, reached and 1 or 0.3, l, l + 10, t + 3, t + 29)
        if k + 1 == tidx then animate(swatch, "tier") end
        text("LEVEL " .. (k * 100), 18, reached and WHITE or DIM, l + 22, l + 150, t, t + 32, LEFT, true)
        text(tr.name, 18, reached and tr.c1 or DIM, l + 150, l + 366, t, t + 32, LEFT, reached)
    end

    -- how it works
    box(LINE, 1, -770, 770, 826, 827)
    text("POINTS ARE ADDED WHEN THE MATCH ENDS: LEAVING EARLY GIVES NOTHING. EVERY MULTIPLAYER MODE COUNTS.", 17, GREY, -770, 770, 836, 862, LEFT)
    text("ASSIST: YOU HIT AN ENEMY AND A TEAMMATE FINISHES HIM WITHIN 5 SECONDS. THE LEVEL RANKING NEVER RESETS.", 17, GREY, -770, 770, 864, 890, LEFT)

    text("THANK YOU FOR USING MY MOD !!!!! :)", 13, DIM, 330, 770, 900, 922, RIGHT)

    -- animation: the tier colour and the shine that runs along the bar
    local tick = 0
    root:registerEventHandler("br95_level_anim", function()
        tick = tick + 1
        local t = tick * 0.05
        local color = tierColor(tidx, t)
        for _, a in ipairs(anim) do pcall(a.el.SetRGB, a.el, color, 0) end
        if shine then
            local x = barL + ((tick * 5) % (fillW - 30))
            pcall(shine.SetAnchorsAndPosition, shine, 0.5, 0.5, 0, 1, x, x + 30, barT, barT + 16)
        end
    end)
    root:addElement(LUI.UITimer.new({ interval = 50, event = "br95_level_anim", disposable = false, eventTarget = root }))
    return root
end

local function install()
    if state.installed then return true end
    if type(MenuBuilder) ~= "table" or type(MenuBuilder.registerType) ~= "function" then return false end
    if type(MAINMENUTABS) ~= "table" or type(MAINMENUTABS.TabData) ~= "table" or type(MAINMENUTABS.Layouts) ~= "table" then return false end

    MenuBuilder.registerType(MENU, function(menu, options)
        local controller = type(options) == "table" and options.controllerIndex or 0
        trace("build start")
        local ok, result = pcall(build, menu, controller)
        if ok and result then trace("build ok"); return result end
        trace("build error: " .. tostring(result))
        local root = LUI.UIElement.new(); root.id = MENU
        root:SetAnchorsAndPosition(0.5, 0.5, 0, 1, -960, 960, 0, 1080)
        local msg = LUI.UIText.new()
        msg:SetAnchorsAndPosition(0.5, 0.5, 0, 1, -770, 770, 300, 360)
        pcall(function() msg:setText("LEVEL ERROR: " .. tostring(result)) end)
        root:addElement(msg)
        return root
    end)
    trace("registered")

    local data = MAINMENUTABS.TabData
    if not data[MENU] then
        local sound = type(data.CustomizeMenu) == "table" and data.CustomizeMenu.menuSound or nil
        data[MENU] = { menuName = MENU, name = "MP LEVEL", menuSound = sound,
            isHidden = function() local ok, d = pcall(LeaguePlayUtils.GetLeaguePlayTypeAndMode, 0); return ok and type(d) == "table" and d.gamemode == 128 end, isDisabled = function() return false end,
            onFocusCallback = function() return true end, menuSpecificCallback = function() end }
    end

    for _, lobby in ipairs({ "PrivateMatchLobby", "MPSystemLinkLobby" }) do
        local layout = MAINMENUTABS.Layouts[lobby]
        if type(layout) == "table" then
            local present = false
            for _, entry in ipairs(layout) do if entry == MENU then present = true end end
            if not present then table.insert(layout, MENU) end
        end
    end

    state.installed = true
    if DebugPrint then pcall(DebugPrint, "[BR95Level] tab installed") end
    return true
end

local function tryInstall()
    local ok, err = pcall(install)
    if not ok then
        state.error = tostring(err)
        if DebugPrint then pcall(DebugPrint, "[BR95Level] tab error: " .. state.error) end
    end
end

tryInstall()

if not state.installed and LUI and LUI.UIRoot and type(LUI.UIRoot.init) == "function" then
    local original = LUI.UIRoot.init
    LUI.UIRoot.init = function(root, ...)
        local result = original(root, ...)
        tryInstall()
        return result
    end
end