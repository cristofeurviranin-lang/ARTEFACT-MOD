-- BR95 Ranked menu: adds a RANKED tab to the lobby that shows the offline
-- rank saved by br95_ranked.gscc (jupiter/IO/br95_ranked.txt).
-- Same tab mechanism as the Local Progression "CASES" tab (MAINMENUTABS).
-- Everything is wrapped in pcall: if something is missing the tab is simply
-- not added, the game keeps working. Fully restart the game after changes.
if BR95RankedMenu then return end
local state = { installed = false }
BR95RankedMenu = state

local FILE = "jupiter/IO/br95_ranked.txt"
local MENU = "BR95RankedMenu"

-- must match br95_ranked.gsc
local RANKS = {
    { name = "BRONZE",     start = 0,     color = 0xCD7F32, cost = 20 },
    { name = "SILVER",     start = 1000,  color = 0xC8C8C8, cost = 40 },
    { name = "PLATINUM",   start = 2500,  color = 0x7FE0D6, cost = 80 },
    { name = "DIAMOND",    start = 5000,  color = 0x4FA3FF, cost = 120 },
    { name = "CRIMSON",    start = 8000,  color = 0xDC143C, cost = 160 },
    { name = "IRIDESCENT", start = 12000, color = 0xC77DFF, cost = 200 },
    { name = "PAINITE",    start = 17000, color = 0xB0303A, cost = 260 },
}
local WHITE, GREY, DARK, BLACK = 0xFFFFFF, 0x8A8A8A, 0x151515, 0x000000
local GREEN, RED = 0x6BD66B, 0xE04040
local ROMAN = { "I", "II", "III" }

-- ------------------------------------------------------------------
-- settings (also read by br95_ranked.gscc) and 3-week seasons
-- ------------------------------------------------------------------
local SETTINGS_FILE = "jupiter/IO/br95_settings.txt"
local SEASON_FILE = "jupiter/IO/br95_season.txt"
local SEASON_DAYS = 21

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
-- colors, speed: 1 slow / 2 normal / 3 fast
local function loadSettings()
    local s = { ranked = 1, spawnmsg = 1, anim = 1, speed = 2 }
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
        .. "|anim=" .. s.anim .. "|speed=" .. s.speed .. "|END")
end

local function resetRanked()
    return writeText(FILE, "BR95R1|0|0|0|0|0|END")
end

-- season: start time + number; past 3 weeks = new season and SR reset
-- Same calendar for every player (21 days from SEASON_EPOCH), so that the world
-- ranking compares players of the same season. The season file keeps the number
-- of the season the saved SR belongs to: another number = SR reset.
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
    pcall(function()
        local f = io.open(FILE, "r")
        if not f then return end
        local text = f:read("*a"); f:close()
        local sr, m, k, b, l = text:match("^BR95R1|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|END")
        if sr then
            p.sr, p.matches, p.kills, p.best, p.last = tonumber(sr), tonumber(m), tonumber(k), tonumber(b), tonumber(l)
        end
    end)
    return p
end

local function rankIndex(sr)
    local index = 1
    for i, r in ipairs(RANKS) do if sr >= r.start then index = i end end
    return index
end

-- division inside the rank: 0, 1, 2 (I, II, III); the top rank has none
local function tierOf(sr)
    local i = rankIndex(sr)
    if i == #RANKS then return nil end
    local size = (RANKS[i + 1].start - RANKS[i].start) / 3
    return math.min(2, math.floor((sr - RANKS[i].start) / size)), size
end

local function font(text, size, bold)
    if FONTS and FONTS.GetFont then
        local f = bold and FONTS.PrimaryBold or FONTS.SecondaryRegular
        if f and f.File then pcall(text.SetFont, text, FONTS.GetFont(f.File)) end
    end
    if text.SetFontSize then pcall(text.SetFontSize, text, size) end
end

local function build(menu, controller)
    local root = LUI.UIElement.new(); root.id = MENU
    root:SetAnchorsAndPosition(0, 1, 0, 1, 0, 1920, 0, 1080)
    local LEFT = LUI.Alignment and LUI.Alignment.Left
    local RIGHT = LUI.Alignment and LUI.Alignment.Right

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
        if child.SetAlignment and LUI.Alignment then child:SetAlignment(align or LUI.Alignment.Center) end
        child:SetRGB(color or WHITE, 0)
        child:setText(str)
        root:addElement(child); return child
    end

    -- rank logos in the Ranked Play style: hexagon shield with a metal rim, a
    -- nameplate across the middle, a blade emblem that grows with the rank and
    -- a gem at the bottom from Platinum. Drawn with boxes (no official images).
    -- iridescent: liquid-metal palette (deep purple, magenta, chrome, teal,
    -- gold, blue) that keeps flowing thanks to a timer (reactive colors)
    local RAINBOW = { 0xB57CFF, 0xF07CFF, 0xEDEDF7, 0x6FF0E4, 0xFFE08A, 0x7FA2FF, 0xD0A0FF }
    -- painite: blood red, ruby, ember and gold, flowing twice as fast
    local PAINITE = { 0xE8505E, 0xFF5A66, 0xFF8A5C, 0xFFD27A, 0xFF7A95, 0xFFB0A0, 0xFF6F61 }
    local animated = {}
    -- slow = number of 110 ms ticks per color step (Iridescent 4, Painite 1)
    -- kind: "iris" or "painite"; the speed is read live from state.settings
    -- at every tick, so the SETTINGS panel changes it right away
    local function anim(el, off, pal, kind)
        if el then animated[#animated + 1] = { el = el, off = off, pal = pal or RAINBOW, kind = kind or "iris" } end
        return el
    end
    local function logo(cx, top, s, idx, tier, faded)
        local color = RANKS[idx].color
        local a = faded and 0.3 or 1
        local H = 220
        local function b(c, al, l, r, t, bt)
            local el = box(c, al, cx + l * s, cx + r * s, top + t * s, top + bt * s)
            if idx == 6 and c ~= BLACK then anim(el, math.floor((t + l * 0.5) / 18), RAINBOW, "iris") end
            if idx == 7 and c ~= BLACK then anim(el, math.floor((t + l * 0.5) / 18), PAINITE, "painite") end
            return el
        end
        local function rowColor(c, y)
            if idx == 6 then return RAINBOW[(math.floor(y / 16) % #RAINBOW) + 1] end
            if idx == 7 then return PAINITE[(math.floor(y / 16) % #PAINITE) + 1] end
            return c
        end
        -- hexagon made of 8 px rows; inset shrinks it to draw rims
        local function hex(c, al, inset)
            local y = inset
            while y < H - inset do
                local yc = y + 4
                local half = 100
                if yc < 50 then half = 55 + (yc / 50) * 45
                elseif yc > H - 50 then half = 55 + ((H - yc) / 50) * 45 end
                half = half - inset
                if half > 0 then b(rowColor(c, y), al, -half, half, y, math.min(y + 8, H - inset)) end
                y = y + 8
            end
        end
        -- small diamond made of rows (blade and gem)
        local function diamond(c, al, cy, height, width)
            local rows = math.max(3, math.floor(height / 6))
            local mid = (rows + 1) / 2
            for r = 1, rows do
                local w = width * (1 - math.abs(r - mid) / (mid + 0.3))
                local y = cy - height / 2 + (r - 1) * (height / rows)
                local rc = c
                if idx == 7 and r % 2 == 0 then rc = 0xFF4D4D end
                if idx == 6 then rc = RAINBOW[(r % #RAINBOW) + 1] end
                b(rc, al, -w / 2, w / 2, y, y + height / rows - 1)
            end
        end

        -- glow behind the top ranks
        if idx >= 6 then
            b(color, 0.15 * a, -124, 124, -14, H + 14)
            b(color, 0.08 * a, -136, 136, -26, H + 26)
        end

        -- Painite: crown of spikes on top (Top 250 inspired)
        if idx == 7 then
            for _, x in ipairs({ -60, -30, 0, 30, 60 }) do
                local h = (x == 0) and 34 or ((math.abs(x) == 30) and 24 or 16)
                b(0xFFD166, a, x - 7, x + 7, 6 - h, 10)
                b(0xFF4D4D, a, x - 3, x + 3, 2 - h, 8 - h)
            end
        end

        -- shield: outer rim, black inside; double rim from Platinum
        hex(color, a, 0)
        hex(BLACK, 1, 8)
        if idx >= 3 then
            hex(color, a * 0.8, 14)
            hex(BLACK, 1, 18)
        end
        hex(color, a * 0.10, 18)

        -- blade emblem above the plate: taller and wider with the rank
        diamond(color, a, 70, 40 + idx * 8, 14 + idx * 5)
        for k = 1, math.min(idx - 1, 4) do
            local w = 30 + k * 14
            local y = 96 - k * 9
            if y > 40 then b(color, a * 0.7, -w / 2, -w / 2 + 10, y, y + 4); b(color, a * 0.7, w / 2 - 10, w / 2, y, y + 4) end
        end

        -- nameplate across the shield (wider than the shield)
        b(color, a, -122, 122, 112, 136)
        b(BLACK, 0.55, -116, 116, 118, 130)
        if idx == 6 then
            for k = 0, 4 do b(RAINBOW[k + 1], a * 0.8, -116 + k * 46.4, -116 + (k + 1) * 46.4, 118, 130) end
        else
            b(color, a * 0.35, -116, 116, 118, 130)
        end

        -- gem at the bottom (Platinum and up), bigger with the rank
        if idx >= 3 then
            diamond(color, a, 168, 26 + idx * 4, 26 + idx * 6)
        end

        -- division notches under the shield (top rank: all lit)
        local pips = tier and (tier + 1) or 3
        for k = 1, 3 do
            local x = (k - 2) * 30
            local lit = k <= pips
            b(lit and color or 0x404040, lit and a or 1, x - 11, x + 11, H + 8, H + 16)
        end
    end

    local settings = loadSettings()
    local seasonNumber, seasonLeft = checkSeason()
    local p = readProfile()
    local i = rankIndex(p.sr)
    local rank = RANKS[i]
    local tier, size = tierOf(p.sr)

    -- backdrop and raw header
    box(BLACK, 0.88, -800, 800, 110, 990)
    local iris = (i == 6) or (i == 7)
    local irisPal = (i == 7) and PAINITE or RAINBOW
    local irisSlow = (i == 7) and "painite" or "iris"
    local function ri(el, off) if iris then anim(el, off, irisPal, irisSlow) end; return el end
    ri(box(rank.color, 1, -800, 800, 110, 118), 0)
    ri(box(rank.color, 1, -800, -792, 118, 990), 3)
    for k = 0, 5 do
        local x = 520 + k * 46
        box(rank.color, 0.25 + k * 0.1, x, x + 24, 132, 196)
    end
    text("RANKED PLAY", 64, WHITE, -770, 300, 128, 198, LEFT, true)
    -- season badge next to the title
    ri(box(rank.color, 1, -318, -218, 140, 190), 4)
    box(BLACK, 1, -314, -222, 144, 186)
    ri(text("S" .. seasonNumber, 34, rank.color, -318, -218, 144, 186, nil, true), 5)
    -- player name (from jupiter/settings.json) + current rank icon and name
    local player = "PLAYER"
    pcall(function()
        local f = io.open("jupiter/settings.json", "r")
        if not f then return end
        local json = f:read("*a"); f:close()
        local name = json:match('"username"%s*:%s*"([^"]*)"')
        local tag = json:match('"clanTag"%s*:%s*"([^"]*)"')
        if name and name ~= "" then
            player = ((tag and tag ~= "") and ("[" .. tag .. "] ") or "") .. name
        end
    end)
    player = string.upper(player)
    local nameW = math.floor(#player * 24 * 0.62)
    text(player, 24, WHITE, -770, -770 + nameW + 40, 196, 226, LEFT, true)
    local iconX = -770 + nameW + 34
    logo(iconX, 197, 0.12, i, tier, false)
    local smallLabel = rank.name .. (tier and (" " .. ROMAN[tier + 1]) or "")
    ri(text(smallLabel, 24, rank.color, iconX + 22, iconX + 400, 196, 226, LEFT, true), 2)

    -- equipped title from the Ranked Shop tab (jupiter/IO/br95_shop.txt)
    local TITLE_NAMES = { headhunter = "HEADHUNTER", nomercy = "NO MERCY", ghost = "GHOST",
        executioner = "EXECUTIONER", untouchable = "UNTOUCHABLE", painitehunter = "PAINITE HUNTER" }
    local shopText = readText("jupiter/IO/br95_shop.txt")
    local titleId = shopText and shopText:match("title=(%w*)") or ""
    if TITLE_NAMES[titleId] then
        ri(text("[ " .. TITLE_NAMES[titleId] .. " ]", 20, rank.color, -500, 400, 226, 250, LEFT, true), 3)
    end

    -- current rank: logo + name + SR
    logo(-640, 256, 0.95, i, tier, false)
    local label = rank.name .. (tier and (" " .. ROMAN[tier + 1]) or "")
    ri(text(label, 72, rank.color, -500, 400, 250, 335, LEFT, true), 1)
    text(p.sr .. " SR", 46, WHITE, -500, 100, 335, 390, LEFT, true)
    text("ENTRY COST " .. rank.cost .. " SR", 22, RED, 100, 770, 350, 380, RIGHT, true)

    -- segmented progress bar to the next division
    local barL, barR, barT = -500, 770, 405
    local segs = 20
    local segW = (barR - barL) / segs
    local pct, from, to = 1, nil, nil
    if tier then
        from = math.floor(rank.start + tier * size)
        to = math.floor(rank.start + (tier + 1) * size)
        pct = math.max(0, math.min(1, (p.sr - from) / (to - from)))
    end
    for k = 0, segs - 1 do
        local filled = (k + 1) / segs <= pct + 0.0001
        local seg = box(filled and rank.color or 0x2A2A2A, 1, barL + k * segW + 2, barL + (k + 1) * segW - 2, barT, barT + 26)
        if filled then ri(seg, k) end
    end
    if tier then
        text(from .. "", 20, GREY, barL, barL + 300, barT + 32, barT + 56, LEFT)
        text((to - p.sr) .. " SR TO NEXT DIVISION", 22, WHITE, -150, 450, barT + 32, barT + 56, nil, true)
        text(to .. "", 20, GREY, barR - 300, barR, barT + 32, barT + 56, RIGHT)
    else
        text("TOP RANK", 22, rank.color, -150, 450, barT + 32, barT + 56, nil, true)
    end

    -- ladder with mini logos
    local w = 1540 / #RANKS
    for k, r in ipairs(RANKS) do
        local cx = -770 + (k - 0.5) * w
        local current = (k == i)
        if current then box(r.color, 0.18, cx - w / 2 + 6, cx + w / 2 - 6, 492, 680) end
        logo(cx, 504, 0.48, k, (k == #RANKS) and nil or 2, not current and k > i)
        text(r.name, 22, (k <= i) and r.color or GREY, cx - w / 2, cx + w / 2, 622, 648, nil, true)
        text(r.start .. "+", 18, GREY, cx - w / 2, cx + w / 2, 650, 672)
    end

    -- stats
    local last = (p.last >= 0 and "+" or "") .. p.last
    local stats = {
        { "MATCHES", tostring(p.matches), WHITE },
        { "KILLS", tostring(p.kills), WHITE },
        { "BEST SR", tostring(p.best), rank.color },
        { "LAST MATCH", last, p.last >= 0 and GREEN or RED },
    }
    for k, s in ipairs(stats) do
        local l = -770 + (k - 1) * 385
        box(DARK, 1, l, l + 375, 700, 800)
        box(s[3], 1, l, l + 6, 700, 800)
        text(s[1], 20, GREY, l + 22, l + 375, 710, 735, LEFT)
        text(s[2], 48, s[3], l + 22, l + 375, 738, 792, LEFT, true)
    end

    -- bottom area: RULES or SETTINGS. Everything is created now (buttons built
    -- with the tab are the only ones that get input); the SETTINGS / RULES
    -- button just swaps which group is visible. Hidden buttons ignore clicks.
    local rulesGroup, settingsGroup = {}, {}
    local showingSettings = false
    local function inGroup(group, el) group[#group + 1] = el; return el end

    inGroup(rulesGroup, box(rank.color, 1, -770, -730, 828, 832))
    inGroup(rulesGroup, text("RULES", 26, WHITE, -720, 0, 815, 845, LEFT, true))
    local rules = {
        "KILL +10 SR  |  DEATH -20 SR  |  ONLY KILLS COUNT: NO DAMAGE OR SURVIVAL SR.",
        "RANKED COUNTS ONLY IN RESURGENCE QUADS. ENTRY COST IS PAID AT THE START: QUITTING MEANS LOSING IT.",
        "MIN KILLS TO SCORE: DIAMOND 20 / CRIMSON 35 / IRIDESCENT 40 / PAINITE 50. DEATHS COST x1.7 TO x3.3.",
        "ENTRY: BRONZE 20 / SILVER 40 / PLATINUM 80 / DIAMOND 120 / CRIMSON 160 / IRIDESCENT 200 / PAINITE 260.",
    }
    for k, line in ipairs(rules) do
        inGroup(rulesGroup, text(line, 18, GREY, -770, 560, 852 + (k - 1) * 30, 876 + (k - 1) * 30, LEFT))
    end

    -- season countdown + ranked state
    local days = math.floor(seasonLeft / 86400)
    local hours = math.floor((seasonLeft % 86400) / 3600)
    inGroup(rulesGroup, text("SEASON " .. seasonNumber .. "  |  RESET IN " .. days .. "D " .. string.format("%02d", hours) .. "H", 20, WHITE,
        300, 770, 815, 845, RIGHT, true))
    if settings.ranked == 0 then
        text("RANKED OFF: MATCHES DO NOT CHANGE YOUR SR", 20, RED, 100, 770, 200, 226, RIGHT, true)
    end

    -- settings group
    local s = settings
    local ONOFF = { [0] = "OFF", [1] = "ON" }
    local SPEED = { "SLOW", "NORMAL", "FAST" }
    inGroup(settingsGroup, box(WHITE, 1, -770, -730, 828, 832))
    inGroup(settingsGroup, text("SETTINGS", 26, WHITE, -720, 0, 815, 845, LEFT, true))
    inGroup(settingsGroup, text("SAVED INSTANTLY  |  RANKED CHANGES APPLY NEXT MATCH", 18, GREY, 0, 770, 820, 845, RIGHT))
    -- section labels in front of each row
    inGroup(settingsGroup, box(0x2A2A2A, 1, -770, -640, 855, 905))
    inGroup(settingsGroup, text("RANKED", 22, rank.color, -770, -640, 867, 893, nil, true))
    inGroup(settingsGroup, box(0x2A2A2A, 1, -770, -640, 920, 970))
    inGroup(settingsGroup, text("MENU", 22, WHITE, -770, -640, 932, 958, nil, true))

    -- each setting: colored status light + button; light updates with the value
    local AMBER = 0xFFB347
    local function setting(label, l, r, t, b, light, action)
        local lamp = inGroup(settingsGroup, box(light(), 1, l, l + 8, t, b))
        local btn = MenuBuilder.BuildRegisteredType("GenericButton", { controllerIndex = controller })
        btn:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l + 14, r, t, b)
        root:addElement(btn)
        local function set(str)
            if btn.Text then pcall(btn.Text.setText, btn.Text, str) end
            pcall(lamp.SetRGB, lamp, light(), 150)
        end
        set(label)
        btn:addEventHandler("button_action", function()
            if showingSettings then pcall(action, set) end
        end)
        return inGroup(settingsGroup, btn)
    end
    local function onoff(key) return function() return s[key] == 1 and GREEN or RED end end
    local function speedLight() return ({ GREY, WHITE, AMBER })[s.speed] or WHITE end

    setting("RANKED: " .. ONOFF[s.ranked], -625, -250, 855, 905, onoff("ranked"), function(set)
        s.ranked = 1 - s.ranked; saveSettings(s); state.settings = s; set("RANKED: " .. ONOFF[s.ranked])
    end)
    setting("RANK AT SPAWN: " .. ONOFF[s.spawnmsg], -235, 170, 855, 905, onoff("spawnmsg"), function(set)
        s.spawnmsg = 1 - s.spawnmsg; saveSettings(s); state.settings = s; set("RANK AT SPAWN: " .. ONOFF[s.spawnmsg])
    end)
    local armed = 0
    setting("NEW SEASON (RESET SR)", 185, 770, 855, 905, function() return armed > 0 and AMBER or RED end, function(set)
        local now = os.clock()
        if now - armed > 4 then
            armed = now; set("CLICK AGAIN TO CONFIRM")
        else
            armed = 0
            local ok, season = newSeason()
            if ok then set("SEASON " .. season .. " STARTED: SR 0") else set("RESET FAILED") end
        end
    end)
    setting("ANIMATED COLORS: " .. ONOFF[s.anim], -625, -250, 920, 970, onoff("anim"), function(set)
        s.anim = 1 - s.anim; saveSettings(s); state.settings = s; set("ANIMATED COLORS: " .. ONOFF[s.anim])
    end)
    setting("ANIMATION: " .. SPEED[s.speed], -235, 170, 920, 970, speedLight, function(set)
        s.speed = (s.speed % 3) + 1; saveSettings(s); state.settings = s; set("ANIMATION: " .. SPEED[s.speed])
    end)
    inGroup(settingsGroup, text("SEASON " .. seasonNumber .. "  |  RESET IN " .. days .. "D " .. string.format("%02d", hours) .. "H",
        20, WHITE, 185, 770, 932, 958, RIGHT, true))
    local function showGroup(group, visible)
        for _, el in ipairs(group) do pcall(el.SetAlpha, el, visible and 1 or 0, 0) end
    end
    showGroup(settingsGroup, false)

    -- SETTINGS / RULES toggle (header, top right: away from the settings buttons)
    local toggle = MenuBuilder.BuildRegisteredType("GenericButton", { controllerIndex = controller })
    toggle.id = "BR95RankedSettingsButton"
    toggle:SetAnchorsAndPosition(0.5, 0.5, 0, 1, 250, 500, 135, 190)
    root:addElement(toggle)
    if toggle.Text then pcall(toggle.Text.setText, toggle.Text, "SETTINGS") end
    toggle:addEventHandler("button_action", function()
        showingSettings = not showingSettings
        showGroup(settingsGroup, showingSettings)
        showGroup(rulesGroup, not showingSettings)
        if toggle.Text then pcall(toggle.Text.setText, toggle.Text, showingSettings and "RULES" or "SETTINGS") end
    end)
    -- flowing colors: 55 ms timer; ticks per color step depend on the live
    -- settings (state.settings is updated by the SETTINGS panel)
    state.settings = settings
    local STEPS = {
        iris = { 16, 8, 4 },     -- slow / normal / fast: 880, 440, 220 ms
        painite = { 4, 2, 1 },   -- slow / normal / fast: 220, 110, 55 ms
    }
    if #animated > 0 then
        local phase = 0
        root:registerEventHandler("br95_iris_tick", function()
            local live = state.settings or settings
            if live.anim ~= 1 then return end
            phase = phase + 1
            local sp = math.max(1, math.min(3, live.speed or 2))
            for _, e in ipairs(animated) do
                local slow = STEPS[e.kind][sp]
                if phase % slow == 0 then
                    local step = math.floor(phase / slow)
                    pcall(e.el.SetRGB, e.el, e.pal[((step + e.off) % #e.pal) + 1], 55 * slow)
                end
            end
        end)
        root:addElement(LUI.UITimer.new({ interval = 55, event = "br95_iris_tick", eventTarget = root, disposable = false }))
    end
    return root
end

-- ------------------------------------------------------------------
-- settings panel (opened by the SETTINGS button, closed by BACK)
-- ------------------------------------------------------------------
-- menuMode: the panel IS the root of the "BR95RankedSettingsMenu" menu opened
-- with LUI.FlowManager (BACK leaves the menu); otherwise it is an overlay
local SETTINGS_MENU = "BR95RankedSettingsMenu"
local function leaveSettingsMenu(root)
    local fm = LUI and LUI.FlowManager
    if fm and fm.RequestLeaveMenuByName and pcall(fm.RequestLeaveMenuByName, SETTINGS_MENU) then return true end
    if ACTIONS and ACTIONS.LeaveMenuByName and pcall(ACTIONS.LeaveMenuByName, SETTINGS_MENU) then return true end
    if fm and fm.RequestLeaveMenu and pcall(fm.RequestLeaveMenu, root) then return true end
    return false
end

state.openSettings = function(parent, controller, menuMode)
    local panel
    if menuMode then
        panel = parent
    else
        if state.settingsPanel then pcall(state.settingsPanel.close, state.settingsPanel) end
        panel = LUI.UIElement.new(); panel.id = "BR95RankedSettings"
        panel:SetAnchorsAndPosition(0, 1, 0, 1, 0, 1920, 0, 1080)
        parent:addElement(panel)
        state.settingsPanel = panel
    end
    local LEFT = LUI.Alignment and LUI.Alignment.Left

    local function box(color, alpha, l, r, t, b)
        local child = LUI.UIImage.new()
        child:SetRGB(color, 0); child:SetAlpha(alpha, 0)
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        panel:addElement(child); return child
    end
    local function text(str, size, color, l, r, t, b, bold)
        local child = LUI.UIText.new()
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        font(child, size, bold)
        if child.SetAlignment and LEFT then child:SetAlignment(LEFT) end
        child:SetRGB(color, 0)
        child:setText(str)
        panel:addElement(child); return child
    end
    local function button(label, l, r, t, b, action)
        local btn = MenuBuilder.BuildRegisteredType("GenericButton", { controllerIndex = controller })
        btn:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        panel:addElement(btn)
        local function set(str) if btn.Text then pcall(btn.Text.setText, btn.Text, str) end end
        set(label)
        btn:addEventHandler("button_action", function() pcall(action, set) end)
        return btn
    end

    local s = loadSettings()
    local ONOFF = { [0] = "OFF", [1] = "ON" }
    local SPEED = { "SLOW", "NORMAL", "FAST" }

    box(BLACK, 0.97, -800, 800, 110, 990)
    box(0xFFFFFF, 1, -800, 800, 110, 118)
    text("SETTINGS", 64, WHITE, -770, 300, 128, 198, true)
    local status = text("CHANGES ARE SAVED RIGHT AWAY. REOPEN THE TAB TO SEE THEM.", 20, GREY, -770, 770, 198, 224)

    -- ranked section
    text("RANKED", 30, WHITE, -770, 0, 260, 300, true)
    box(0xFFFFFF, 1, -770, -730, 302, 306)
    button("RANKED MODE: " .. ONOFF[s.ranked], -770, -250, 320, 380, function(set)
        s.ranked = 1 - s.ranked; saveSettings(s); state.settings = s; set("RANKED MODE: " .. ONOFF[s.ranked])
    end)
    text("OFF = matches do not cost or give SR.", 20, GREY, -230, 770, 335, 365)
    button("RANK MESSAGE AT SPAWN: " .. ONOFF[s.spawnmsg], -770, -250, 395, 455, function(set)
        s.spawnmsg = 1 - s.spawnmsg; saveSettings(s); state.settings = s; set("RANK MESSAGE AT SPAWN: " .. ONOFF[s.spawnmsg])
    end)
    text("Shows your rank on screen when you spawn.", 20, GREY, -230, 770, 410, 440)
    local armed = 0
    button("RESET MY SR", -770, -250, 470, 530, function(set)
        local now = os.clock()
        if now - armed > 4 then
            armed = now; set("CLICK AGAIN TO CONFIRM")
        else
            armed = 0
            local ok, season = newSeason()
            if ok then set("SEASON " .. season .. " STARTED: SR 0") else set("RESET FAILED") end
        end
    end)
    text("Starts a new season: back to Bronze I with 0 SR. Click twice to confirm.", 20, GREY, -230, 770, 485, 515)
    text("Every reset starts a new season (S1, S2, S3...). Automatic reset every " .. SEASON_DAYS .. " days.", 20, GREY, -770, 770, 545, 575)

    -- menu section
    text("MENU", 30, WHITE, -770, 0, 620, 660, true)
    box(0xFFFFFF, 1, -770, -730, 662, 666)
    button("ANIMATED COLORS: " .. ONOFF[s.anim], -770, -250, 680, 740, function(set)
        s.anim = 1 - s.anim; saveSettings(s); state.settings = s; set("ANIMATED COLORS: " .. ONOFF[s.anim])
    end)
    text("Flowing colors of the Iridescent and Painite logos.", 20, GREY, -230, 770, 695, 725)
    button("ANIMATION SPEED: " .. SPEED[s.speed], -770, -250, 755, 815, function(set)
        s.speed = (s.speed % 3) + 1; saveSettings(s); state.settings = s; set("ANIMATION SPEED: " .. SPEED[s.speed])
    end)
    text("Slow, normal or fast flowing colors.", 20, GREY, -230, 770, 770, 800)

    -- BACK sits at the top right: the SETTINGS button of the main view is
    -- under the bottom right corner and would catch the click
    button("BACK", 580, 770, 135, 190, function()
        state.settingsPanel = nil
        if state.settingsButton then pcall(state.settingsButton.SetAlpha, state.settingsButton, 1, 0) end
        if menuMode then
            if not leaveSettingsMenu(panel) then panel:close() end
        else
            panel:close()
        end
    end)
end

local function install()    if state.installed then return true end
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
