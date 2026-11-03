-- BR95 Ranked Events (Ranked 0.6): an EVENTS tab in the ranked lobby (after RANKED
-- SHOP), same purple / blue look as the RANKED tab. Events are written in the EVENTS
-- list below. The tab shows the live, upcoming and last ended ones with a countdown;
-- their challenges are counted on the ranked matches played during the event
-- (br95_ranked_history.txt) and give RP when claimed (claims in br95_events.txt).
-- With no event in the list the tab shows a "no event right now" screen.
-- Everything that moves runs on one 16 ms timer, timed with the clock.
-- The file name sorts after br95_ranked_shop_post.lua on purpose: loaded after it, the
-- tab finds RANKED SHOP in the lobby layouts and goes right after it.
if BR95RankedEvents then return end
local state = { installed = false }
BR95RankedEvents = state

local IO = "jupiter/IO/"
local RP_FILE = IO .. "br95_rp.txt"                     -- BR95P1|rp|END
local HISTORY_FILE = IO .. "br95_ranked_history.txt"    -- H|time|sr_after|delta|kills|deaths|seconds|rp|END
local CLAIM_FILE = IO .. "br95_events.txt"              -- one line per event: E|id|0101|END
local MENU = "BR95RankedEventsMenu"

-- The events. Dates in UTC, "YYYY-MM-DD HH:MM". Example:
-- {
--     id = "nighthunt1",                      -- unique, never reused (claims are saved by id)
--     name = "NIGHT HUNT", tag = "LIMITED EVENT", color = 0xFF8A1E,
--     from = "2026-11-07 18:00", to = "2026-11-10 22:00",
--     art = "loading_mp_jup_escape5_hell_bg", -- game image for the banner (optional)
--     desc = { "FIRST LINE", "SECOND LINE" }, -- up to 4 lines
--     challenges = {                          -- up to 4; stat = kills, matches, wins, srwon, minutes
--         { desc = "GET %s KILLS IN RANKED", stat = "kills", goal = 50, rp = 300 },
--     },
-- },
local EVENTS = {
}

-- what a ranked match adds to a challenge
local STATS = {
    kills = function(m) return m.kills end,
    matches = function() return 1 end,
    wins = function(m) return (m.delta > 0) and 1 or 0 end,
    srwon = function(m) return math.max(0, m.delta) end,
    minutes = function(m) return m.seconds / 60 end,
}

-- purple / blue look (same as the RANKED tab)
local WHITE, GREY, DIM, BLACK = 0xFFFFFF, 0xC9C0F0, 0x9488D0, 0x000000
local SIDE, MAIN, CARD, EDGE, LINE = 0x1B2C86, 0x3A2690, 0x2C1C78, 0x7A62E0, 0x2A1B70
local GREEN, GOLD, CYAN, BRUSH, ROW = 0x6BD66B, 0xFFD166, 0x5FD4FF, 0x2F7BFF, 0x4A30AE
local BACK_ART = "menu_keyart_rankedplay_01_layer_00"
local STAR_ICON = "iw9_ui_icon_leagueplay_star_filled"
local MODE_ICON = "jup_icon_mode_wz_ranked"
local DOT = "hud_reticle_circle_fill"                   -- white disc of the game (tinted)
local CX = 160                                          -- centre of the content (right of the column)
local MAX_LIST, MAX_CH = 6, 4

local EASE = {}
function EASE.out(x) x = 1 - x; return 1 - x * x * x end
function EASE.back(x) x = x - 1; return 1 + 2.2 * x * x * x + 1.2 * x * x end

-- ------------------------------------------------------------------
-- files, dates
-- ------------------------------------------------------------------
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

local function readRP()
    return tonumber((readText(RP_FILE) or ""):match("^BR95P1|(%d+)|END")) or 0
end

local function now()
    local ok, t = pcall(os.time)
    return ok and tonumber(t) or 0
end

-- "YYYY-MM-DD HH:MM" (UTC) -> seconds since 1970 (no os.time: it reads local time)
local function utc(s)
    local y, m, d, hh, mm = tostring(s or ""):match("^(%d+)%-(%d+)%-(%d+)%s+(%d+):(%d+)")
    if not y then return nil end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return (era * 146097 + doe - 719468) * 86400 + tonumber(hh) * 3600 + tonumber(mm) * 60
end

local function countdown(seconds)
    seconds = math.max(0, math.floor(seconds))
    local d = math.floor(seconds / 86400)
    local text = string.format("%02dH %02dM %02dS", math.floor(seconds % 86400 / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
    return (d > 0) and (d .. "D " .. text) or text
end

local function readHistory()
    local list = {}
    for line in (readText(HISTORY_FILE) or ""):gmatch("[^\n]+") do
        local f = {}
        for part in line:gmatch("[^|]+") do f[#f + 1] = part end
        if f[1] == "H" and #f >= 8 then
            list[#list + 1] = { time = tonumber(f[2]) or 0, delta = tonumber(f[4]) or 0,
                kills = tonumber(f[5]) or 0, seconds = tonumber(f[7]) or 0 }
        end
    end
    return list
end

local function readClaims()
    local claims = {}
    for id, bits in (readText(CLAIM_FILE) or ""):gmatch("E|([^|\n]+)|(%d*)|END") do claims[id] = bits end
    return claims
end

local function saveClaims(claims)
    local lines = {}
    for id, bits in pairs(claims) do lines[#lines + 1] = "E|" .. id .. "|" .. bits .. "|END" end
    table.sort(lines)
    return writeText(CLAIM_FILE, table.concat(lines, "\n") .. "\n")
end

-- events to show: live (ending first), upcoming (starting first), the 2 last ended
local function eventList()
    local t = now()
    local live, soon, ended = {}, {}, {}
    for _, e in ipairs(EVENTS) do
        local from, to = utc(e.from), utc(e.to)
        if from and to and e.id then
            local item = { e = e, from = from, to = to }
            if t < from then item.status = "soon"; soon[#soon + 1] = item
            elseif t < to then item.status = "live"; live[#live + 1] = item
            else item.status = "ended"; ended[#ended + 1] = item end
        end
    end
    table.sort(live, function(a, b) return a.to < b.to end)
    table.sort(soon, function(a, b) return a.from < b.from end)
    table.sort(ended, function(a, b) return a.to > b.to end)
    local list = {}
    for _, x in ipairs(live) do list[#list + 1] = x end
    for _, x in ipairs(soon) do list[#list + 1] = x end
    for k = 1, math.min(2, #ended) do list[#list + 1] = ended[k] end
    while #list > MAX_LIST do table.remove(list) end
    return list
end

-- value of a challenge: ranked matches played between the start and the end
local function challengeValue(ch, item, history)
    local fn = STATS[ch.stat] or STATS.matches
    local sum = 0
    for _, m in ipairs(history) do
        if m.time >= item.from and m.time < item.to then sum = sum + fn(m) end
    end
    return math.min(ch.goal, math.floor(sum))
end

local STATUS = { live = { "LIVE NOW", GREEN }, soon = { "UPCOMING", CYAN }, ended = { "ENDED", DIM } }

-- ------------------------------------------------------------------
-- the tab
-- ------------------------------------------------------------------
local function build(menu, controller)
    local root = LUI.UIElement.new(); root.id = MENU
    root:SetAnchorsAndPosition(0.5, 0.5, 0, 1, -960, 960, 0, 1080)
    local U = { anims = {}, tweens = {} }
    local LEFT = LUI.Alignment and LUI.Alignment.Left
    local RIGHT = LUI.Alignment and LUI.Alignment.Right
    local CENTER = LUI.Alignment and LUI.Alignment.Center

    local function full(parent)
        local g = LUI.UIElement.new()
        g:SetAnchorsAndPosition(0, 1, 0, 1, 0, 1920, 0, 1080)
        parent:addElement(g)
        return g
    end
    local function font(text, size, bold)
        if FONTS and FONTS.GetFont then
            local f = bold and FONTS.PrimaryBold or FONTS.SecondaryRegular
            if f and f.File then pcall(text.SetFont, text, FONTS.GetFont(f.File)) end
        end
        if text.SetFontSize then pcall(text.SetFontSize, text, size) end
    end
    local function box(parent, color, alpha, l, r, t, b)
        local child = LUI.UIImage.new()
        child:SetRGB(color, 0); child:SetAlpha(alpha, 0)
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        parent:addElement(child); return child
    end
    local function text(parent, str, size, color, l, r, t, b, align, bold)
        local child = LUI.UIText.new()
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        font(child, size, bold)
        if child.SetAlignment and LUI.Alignment then child:SetAlignment(align or LEFT) end
        child:SetRGB(color or WHITE, 0)
        child:setText(str)
        parent:addElement(child); return child
    end
    local function setPicture(child, image)
        if image then
            local ok = pcall(function() child:setImage(RegisterMaterial(image), 0) end)
            pcall(child.SetAlpha, child, ok and 1 or 0, 0)
        else
            pcall(child.SetAlpha, child, 0, 0)
        end
    end
    local function picture(parent, image, l, r, t, b)
        local child = LUI.UIImage.new()
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        parent:addElement(child)
        setPicture(child, image)
        return child
    end
    local function disc(parent, color, alpha, l, r, t, b)
        local d = picture(parent, DOT, l, r, t, b)
        pcall(d.SetRGB, d, color, 0); pcall(d.SetAlpha, d, alpha, 0)
        return d
    end
    local function set(el, str, color)
        if not el then return end
        pcall(el.setText, el, str)
        if color then pcall(el.SetRGB, el, color, 0) end
    end
    local function move(el, l, r, t, b) if el then pcall(el.SetAnchorsAndPosition, el, 0.5, 0.5, 0, 1, l, r, t, b) end end
    local function fade(el, a) if el then pcall(el.SetAlpha, el, a, 0) end end
    local function tint(el, c) if el then pcall(el.SetRGB, el, c, 0) end end
    local function button(parent, l, r, t, b, label, action)
        local btn = MenuBuilder.BuildRegisteredType("GenericButton", { controllerIndex = controller })
        btn:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        parent:addElement(btn)
        if btn.Text then pcall(btn.Text.setText, btn.Text, label) end
        btn:addEventHandler("button_action", function() pcall(action) end)
        return btn
    end
    local function label(btn, str) if btn and btn.Text then pcall(btn.Text.setText, btn.Text, str) end end

    -- tweens: step(e) with e 0 -> 1 along `ease`, after `delay` ms, during `dur` ms
    local function tween(delay, dur, ease, step, fadeIn, tag)
        U.tweens[#U.tweens + 1] = { delay = delay, dur = dur, ease = ease, step = step, fade = fadeIn, tag = tag }
        pcall(step, 0)
        if fadeIn then pcall(fadeIn.SetAlpha, fadeIn, 0, 0) end
    end
    local function drop(tag)
        for k = #U.tweens, 1, -1 do if U.tweens[k].tag == tag then table.remove(U.tweens, k) end end
    end
    local function enter(g, delay, dur, dx, dy, ease, tag)
        tween(delay, dur, ease or EASE.out, function(e)
            local x, y = dx * (1 - e), dy * (1 - e)
            g:SetAnchorsAndPosition(0, 1, 0, 1, x, 1920 + x, y, 1080 + y)
        end, g, tag)
    end

    -- background: key art under a purple tint, blue column on the left
    picture(root, BACK_ART, -630, 950, 110, 990)
    box(root, MAIN, 0.86, -630, 950, 110, 990)
    box(root, SIDE, 0.96, -950, -640, 110, 990)
    local topLine = box(root, CYAN, 1, -630, 950, 110, 113)

    local list = eventList()
    local history = readHistory()
    local claims = readClaims()
    local sel = 1

    -- ---------------- left column ----------------
    local side = full(root)
    text(side, "RANKED", 18, CYAN, -930, -660, 124, 146, LEFT, true)
    text(side, "EVENTS", 52, WHITE, -930, -650, 144, 202, LEFT, true)
    local brush = box(side, BRUSH, 1, -930, -929, 208, 214)
    local brushTail = box(side, CYAN, 1, -796, -772, 209, 213)
    tween(450, 500, EASE.out, function(e) move(brush, -930, -930 + math.max(1, 130 * e), 208, 214) end)
    tween(850, 300, EASE.out, function() end, brushTail)
    text(side, (#list > 0) and "LIVE AND UPCOMING" or "NO EVENT YET", 15, GREY, -930, -660, 236, 254, LEFT)
    local wash = box(side, WHITE, 0.10, -936, -652, 266, 312)
    local mark = box(side, WHITE, 1, -944, -936, 266, 312)
    fade(wash, (#list > 0) and 0.10 or 0); fade(mark, (#list > 0) and 1 or 0)
    local markY = 266
    local showEvent
    for k, item in ipairs(list) do
        local t = 266 + (k - 1) * 56
        -- status dot on the right of the button
        disc(side, STATUS[item.status][2], 1, -680, -668, t + 17, t + 29)
        button(side, -930, -688, t, t + 46, item.e.name or "EVENT", function() showEvent(k) end)
    end
    -- legend of the dots
    local ly = 266 + math.max(1, #list) * 56 + 16
    for k, key in ipairs({ "live", "soon", "ended" }) do
        local l = -930 + (k - 1) * 92
        disc(side, STATUS[key][2], 1, l, l + 10, ly + 5, ly + 15)
        text(side, ({ "LIVE", "SOON", "ENDED" })[k], 13, GREY, l + 16, l + 90, ly, ly + 20, LEFT, true)
    end
    text(side, "BALANCE", 15, GREY, -930, -660, 880, 898, LEFT)
    picture(side, STAR_ICON, -930, -900, 904, 934)
    local rpText = text(side, readRP() .. " RP", 34, GOLD, -892, -650, 900, 940, LEFT, true)
    enter(side, 0, 520, -80, 0)

    -- ---------------- no event: placeholder ----------------
    local empty = full(root)
    local bokeh = {}
    for k = 1, 9 do
        local s = 90 + (k * 37) % 140
        bokeh[k] = { el = disc(empty, (k % 3 == 0) and CYAN or EDGE, 0.10, CX - s, CX + s, 450 - s, 450 + s),
            s = s, x = -560 + (k * 211) % 1400, y = 200 + (k * 97) % 620, sp = 0.15 + (k % 4) * 0.07, ph = k * 1.7 }
    end
    local halo = disc(empty, BRUSH, 0.25, CX - 190, CX + 190, 220, 600)
    picture(empty, MODE_ICON, CX - 90, CX + 90, 320, 500)
    text(empty, "NO EVENT RIGHT NOW", 54, WHITE, -610, 930, 520, 580, CENTER, true)
    text(empty, "LIMITED EVENTS, CHALLENGES AND RP REWARDS WILL SHOW UP HERE", 18, GREY, -610, 930, 588, 612, CENTER, true)
    local stay = text(empty, "STAY TUNED", 24, CYAN, -610, 930, 640, 672, CENTER, true)

    -- ---------------- an event ----------------
    local ev = full(root)
    local banner = full(ev)
    local art = picture(banner, nil, -620, 940, 120, 430)
    box(banner, BLACK, 0.30, -620, 940, 120, 430)
    box(banner, BLACK, 0.45, -620, 940, 300, 430)
    local bannerLine = box(banner, CYAN, 1, -620, 940, 427, 431)
    local pill = box(banner, GREEN, 1, -596, -436, 140, 172)
    local pillText = text(banner, "", 18, 0x10204A, -596, -436, 145, 168, CENTER, true)
    local tagText = text(banner, "", 18, WHITE, -420, 400, 145, 168, LEFT, true)
    local nameText = text(ev, "", 64, WHITE, -596, 930, 300, 370, LEFT, true)
    local countText = text(ev, "", 26, CYAN, -596, 930, 372, 404, LEFT, true)

    local about = full(ev)
    box(about, ROW, 0.82, -620, 380, 446, 600)
    box(about, EDGE, 0.8, -620, 380, 599, 600)
    local aboutLine = box(about, CYAN, 1, -620, 380, 446, 448)
    text(about, "ABOUT THE EVENT", 18, GREY, -604, 360, 456, 478, LEFT, true)
    local descLines = {}
    for k = 1, 4 do descLines[k] = text(about, "", 17, WHITE, -604, 366, 484 + (k - 1) * 27, 506 + (k - 1) * 27, LEFT) end

    local when = full(ev)
    box(when, ROW, 0.82, 396, 940, 446, 600)
    box(when, EDGE, 0.8, 396, 940, 599, 600)
    local whenLine = box(when, CYAN, 1, 396, 940, 446, 448)
    text(when, "DATES (UTC)", 18, GREY, 412, 924, 456, 478, LEFT, true)
    local fromText = text(when, "", 17, WHITE, 412, 924, 486, 508, LEFT, true)
    local toText = text(when, "", 17, WHITE, 412, 924, 512, 534, LEFT, true)
    box(when, LINE, 1, 412, 924, 556, 566)
    local timeFill = box(when, CYAN, 1, 412, 413, 556, 566)
    local timePct = text(when, "", 15, GREY, 412, 924, 570, 590, RIGHT, true)

    text(ev, "EVENT CHALLENGES", 26, WHITE, -594, 300, 616, 648, LEFT, true)
    box(ev, CYAN, 1, -610, -605, 619, 645)
    local noChallenge = text(ev, "", 18, GREY, -610, 930, 700, 726, CENTER, true)
    local rows = {}
    for k = 1, MAX_CH do
        local t = 656 + (k - 1) * 72
        local g = full(ev)
        local row = { g = g, t = t }
        box(g, ROW, 0.85, -620, 940, t, t + 64)
        row.mark = box(g, CYAN, 1, -620, -614, t, t + 64)
        row.star = picture(g, STAR_ICON, -600, -560, t + 12, t + 52)
        row.desc = text(g, "", 20, WHITE, -548, 290, t + 8, t + 34, LEFT, true)
        box(g, LINE, 1, -548, 290, t + 42, t + 52)
        row.fill = box(g, GOLD, 1, -548, -547, t + 42, t + 52)
        row.value = text(g, "", 16, WHITE, 300, 520, t + 8, t + 30, LEFT, true)
        row.reward = text(g, "", 22, GOLD, 300, 520, t + 32, t + 58, LEFT, true)
        row.flash = box(g, WHITE, 0, -620, 940, t, t + 64)
        row.btn = button(g, 700, 930, t + 12, t + 52, "CLAIM", function() if row.claim then row.claim() end end)
        rows[k] = row
    end

    local function hideButtons()
        for _, row in ipairs(rows) do move(row.btn, 700, 930, 4000, 4040) end
    end

    -- fills the event view with list[k] and plays its entrance
    showEvent = function(k)
        local item = list[k]
        if not item then return end
        sel = k
        local e, color = item.e, item.e.color or CYAN
        local st = STATUS[item.status]
        drop("event")
        -- the column mark glides to the event
        local from, to = markY, 266 + (k - 1) * 56
        tween(0, 280, EASE.out, function(x)
            markY = from + (to - from) * x
            move(mark, -944, -936, markY, markY + 46); move(wash, -936, -652, markY, markY + 46)
        end, nil, "event")
        setPicture(art, e.art)
        for _, el in ipairs({ bannerLine, aboutLine, whenLine, topLine }) do tint(el, color) end
        tint(pill, st[2]); set(pillText, st[1])
        set(tagText, e.tag or "EVENT")
        set(nameText, e.name or "EVENT", WHITE)
        for n = 1, 4 do set(descLines[n], (e.desc and e.desc[n]) or "") end
        local ok1, s1 = pcall(os.date, "!%d/%m/%Y  %H:%M", item.from)
        local ok2, s2 = pcall(os.date, "!%d/%m/%Y  %H:%M", item.to)
        set(fromText, "START   " .. (ok1 and s1 or e.from))
        set(toText, "END      " .. (ok2 and s2 or e.to))
        -- challenges
        local bits = claims[e.id] or ""
        local chs = e.challenges or {}
        set(noChallenge, (#chs == 0) and "NO CHALLENGE IN THIS EVENT" or "")
        for n, row in ipairs(rows) do
            local ch = chs[n]
            if ch then
                local val = challengeValue(ch, item, history)
                local done = val >= ch.goal
                local claimed = bits:sub(n, n) == "1"
                local ok, str = pcall(string.format, ch.desc or "", ch.goal)
                set(row.desc, ok and str or (ch.desc or ""), claimed and DIM or (done and GOLD or WHITE))
                set(row.value, val .. " / " .. ch.goal)
                set(row.reward, "+" .. (ch.rp or 0) .. " RP")
                tint(row.mark, claimed and DIM or (done and GREEN or color))
                fade(row.star, done and 1 or 0.35)
                label(row.btn, claimed and "CLAIMED" or (done and "CLAIM" or ((item.status == "soon") and "SOON" or (item.status == "ended" and "ENDED" or "IN PROGRESS"))))
                move(row.btn, 700, 930, row.t + 12, row.t + 52)
                row.claim = function()
                    local now_ = readClaims()
                    local b = now_[e.id] or ""
                    if b:sub(n, n) == "1" or challengeValue(ch, item, readHistory()) < ch.goal then return end
                    while #b < n do b = b .. "0" end
                    now_[e.id] = b:sub(1, n - 1) .. "1" .. b:sub(n + 1)
                    if not saveClaims(now_) then return end
                    claims = now_
                    writeText(RP_FILE, "BR95P1|" .. (readRP() + (ch.rp or 0)) .. "|END")
                    label(row.btn, "CLAIMED")
                    tint(row.desc, DIM); tint(row.mark, DIM)
                    tint(row.flash, color)
                    tween(0, 650, EASE.out, function(x) fade(row.flash, 0.8 * (1 - x)) end)
                    U.rpTarget = readRP()
                end
                -- the row pops in, then its bar fills
                enter(row.g, 350 + n * 90, 460, 0, 30, EASE.back, "event")
                local pct = val / ch.goal
                tween(500 + n * 90, 800, EASE.out, function(x)
                    move(row.fill, -548, -548 + math.max(1, 838 * pct * x), row.t + 42, row.t + 52)
                end, nil, "event")
                tint(row.fill, done and GREEN or GOLD)
            else
                row.claim = nil
                fade(row.g, 0)
                move(row.btn, 700, 930, 4000, 4040)
            end
        end
        -- banner: the picture settles from a little zoom, the name rises, panels slide in
        tween(0, 900, EASE.out, function(x)
            local z = 40 * (1 - x)
            move(art, -620 - z, 940 + z, 120 - z * 0.2, 430 + z * 0.2)
        end, nil, "event")
        enter(banner, 0, 420, 0, 0, nil, "event")
        tween(150, 450, EASE.out, function(x)
            local y = 36 * (1 - x)
            move(nameText, -596, 930, 300 + y, 370 + y); fade(nameText, x)
            move(countText, -596, 930, 372 + y * 1.4, 404 + y * 1.4); fade(countText, x)
        end, nil, "event")
        enter(about, 250, 460, -60, 0, nil, "event")
        enter(when, 300, 460, 60, 0, nil, "event")
        U.item = item
    end

    if #list > 0 then
        fade(empty, 0)
        showEvent(1)
    else
        fade(ev, 0)
        hideButtons()
        enter(empty, 100, 700, 0, 40)
    end

    -- every frame: countdown, pulses, balance, placeholder bubbles
    U.shownRP, U.rpTarget = readRP(), readRP()
    U.anims[#U.anims + 1] = function(t, dt)
        local item = U.item
        if item and #list > 0 then
            local sec = now()
            if sec ~= U.lastSec then
                U.lastSec = sec
                if item.status == "soon" then
                    set(countText, (sec < item.from) and ("STARTS IN " .. countdown(item.from - sec)) or "STARTED: REOPEN THE TAB")
                elseif item.status == "live" then
                    set(countText, (sec < item.to) and ("ENDS IN " .. countdown(item.to - sec)) or "ENDED")
                else
                    set(countText, "THIS EVENT IS OVER")
                end
                local pct = math.max(0, math.min(1, (sec - item.from) / math.max(1, item.to - item.from)))
                move(timeFill, 412, 412 + math.max(1, 512 * pct), 556, 566)
                set(timePct, math.floor(pct * 100) .. "% OF THE EVENT DONE")
            end
            if item.status == "live" then fade(pill, 0.65 + 0.35 * math.sin(t * 4)) end
        else
            for _, b in ipairs(bokeh) do
                local x = b.x + math.sin(t * b.sp + b.ph) * 60
                local y = b.y + math.cos(t * b.sp * 0.8 + b.ph) * 40
                move(b.el, CX + x - b.s, CX + x + b.s, y - b.s, y + b.s)
            end
            fade(halo, 0.18 + 0.1 * math.sin(t * 1.8))
            fade(stay, 0.55 + 0.45 * math.sin(t * 3))
        end
        fade(topLine, 0.7 + 0.3 * math.sin(t * 3))
        -- balance counts to the saved value
        local diff = U.rpTarget - U.shownRP
        if math.abs(diff) >= 0.5 then
            U.shownRP = U.shownRP + diff * math.min(1, dt / 140)
            if math.abs(U.rpTarget - U.shownRP) < 0.5 then U.shownRP = U.rpTarget end
            set(rpText, math.floor(U.shownRP + 0.5) .. " RP", GREEN)
            U.rpColored = true
        elseif U.rpColored then
            set(rpText, U.rpTarget .. " RP", GOLD)
            U.rpColored = false
        end
    end

    -- one 16 ms timer for everything that moves (timed with the clock)
    local last
    root:registerEventHandler("br95_events_frame", function()
        local ms = os.clock() * 1000
        local dt = last and math.max(0, math.min(100, ms - last)) or 16
        last = ms
        for k = #U.tweens, 1, -1 do
            local tw = U.tweens[k]
            if tw then
                tw.start = tw.start or ms
                tw.frames = (tw.frames or 0) + 1
                local x = (ms - tw.start - tw.delay) / tw.dur
                -- safety: if the clock ever stalls, a tween still ends after enough frames
                if tw.frames > (tw.delay + tw.dur) / 3 + 120 then x = 1 end
                if x >= 0 then
                    if tw.fade and not tw.faded then
                        tw.faded = true
                        pcall(tw.fade.SetAlpha, tw.fade, 1, math.max(1, math.floor(tw.dur * 0.7)))
                    end
                    if x >= 1 then x = 1; table.remove(U.tweens, k) end
                    pcall(tw.step, tw.ease(x))
                end
            end
        end
        for _, fn in ipairs(U.anims) do pcall(fn, ms / 1000, dt) end
    end)
    root:addElement(LUI.UITimer.new({ interval = 16, event = "br95_events_frame", disposable = false, eventTarget = root }))
    return root
end

local function install()
    if state.installed then return true end
    if type(MenuBuilder) ~= "table" or type(MenuBuilder.registerType) ~= "function" then return false end
    if type(MAINMENUTABS) ~= "table" or type(MAINMENUTABS.TabData) ~= "table" or type(MAINMENUTABS.Layouts) ~= "table" then return false end

    MenuBuilder.registerType(MENU, function(menu, options)
        local controller = type(options) == "table" and options.controllerIndex or 0
        local ok, result = pcall(build, menu, controller)
        if ok and result then return result end
        local root = LUI.UIElement.new(); root.id = MENU
        root:SetAnchorsAndPosition(0.5, 0.5, 0, 1, -960, 960, 0, 1080)
        local msg = LUI.UIText.new()
        msg:SetAnchorsAndPosition(0.5, 0.5, 0, 1, -770, 770, 300, 420)
        pcall(function() msg:setText("EVENTS ERROR: " .. tostring(result)) end)
        root:addElement(msg)
        return root
    end)

    local data = MAINMENUTABS.TabData
    if not data[MENU] then
        local sound = type(data.CustomizeMenu) == "table" and data.CustomizeMenu.menuSound or nil
        data[MENU] = { menuName = MENU, name = "EVENTS", menuSound = sound,
            -- shown in the ranked playlist lobby (same test as br95_ranked_official_post.lua)
            isHidden = function() return (readText(IO .. "br95_mode.txt") or ""):match("^BR95M1|(%d)") ~= "1" end,
            isDisabled = function() return false end,
            onFocusCallback = function() return true end, menuSpecificCallback = function() end }
    end

    -- same lobbies as the RANKED tab, after RANKED SHOP (or after RANKED)
    for _, lobby in ipairs({ "WarzonePrivateMatchLobby", "PrivateMatchLobby", "MPSystemLinkLobby" }) do
        local layout = MAINMENUTABS.Layouts[lobby]
        if type(layout) == "table" then
            local present, after = false, nil
            for i, entry in ipairs(layout) do
                if entry == MENU then present = true end
                if entry == "BR95RankedShopMenu" or (entry == "BR95RankedMenu" and not after) then after = i end
            end
            if not present then
                if after then table.insert(layout, after + 1, MENU) else table.insert(layout, MENU) end
            end
        end
    end

    state.installed = true
    return true
end

local function tryInstall()
    local ok, err = pcall(install)
    if not ok then state.error = tostring(err) end
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
