-- BR95 World Ranking (Ranked 0.6): WORLD RANKING tab of the ranked lobby (after EVENTS),
-- the online ladder of Ranked Warzone, same purple / blue look as the RANKED tab.
-- The game has no internet: a small job of the ARTEFACT launcher (core.py --wz-sync, Python,
-- set up by the launcher when the Ranked mod is installed, started with Windows) sends this
-- PC's SR and profile to the server (Supabase) and downloads the ladder. There is no way to
-- leave the ranking: once made, a profile stays in it. Files in jupiter/IO:
--   br95_wr_profile.txt  written here  BR95WP1|joined|name|country|avatar|banner|title|weapon|discord|END
--   br95_wr_request.txt  written here  any change = the sync refreshes at once
--   br95_wr_board.txt    read here     BR95WB1|fetched|total|season|END, then P|... rows (M| = this PC
--                                      outside the list): place|id|name|country|sr|best|matches|kills|
--                                      deaths|wins|avatar|banner|title|weapon|bot|updated|created|discord
--   br95_wr_status.txt   read here     BR95WS1|state|message|time|END (heartbeat of the sync)
--   br95_wr_id.txt       read here     BR95WI1|id|secret|END (which row is this PC)
--   br95_wr_hint.txt     read here     BR95WH1|CC|END (Windows region: country picked first)
-- First visit: a profile wizard (pseudo, nationality, avatar, banner, title, favorite
-- weapon, Discord). Every player (and the server's bots, tagged BOT) can be clicked to
-- see his profile. Avatar / banner / weapon / flag = game item ids (LOOT images), title =
-- index in TITLES: the lists must stay the same for every player (only add at the end).
-- The file name sorts after br95_ranked_tab_events_post.lua: the tab goes after EVENTS.
if BR95WorldRanking then return end
local state = { installed = false }
BR95WorldRanking = state

local IO = "jupiter/IO/"
local PROFILE_FILE = IO .. "br95_wr_profile.txt"
local BOARD_FILE = IO .. "br95_wr_board.txt"
local STATUS_FILE = IO .. "br95_wr_status.txt"
local ID_FILE = IO .. "br95_wr_id.txt"
local HINT_FILE = IO .. "br95_wr_hint.txt"
local REQUEST_FILE = IO .. "br95_wr_request.txt"
local MENU = "BR95WorldRankingMenu"

-- code, name, flag emblem item id (0 = no flag in the game: a code chip instead)
local COUNTRIES = {
    { "AL", "ALBANIA", 10058 }, { "DZ", "ALGERIA", 0 }, { "AR", "ARGENTINA", 9800 }, { "AM", "ARMENIA", 9608 },
    { "AU", "AUSTRALIA", 10040 }, { "AT", "AUSTRIA", 9660 }, { "BE", "BELGIUM", 10279 }, { "BR", "BRAZIL", 10288 },
    { "CM", "CAMEROON", 0 }, { "CA", "CANADA", 9621 }, { "CL", "CHILE", 10229 }, { "CN", "CHINA", 9614 },
    { "CO", "COLOMBIA", 9619 }, { "HR", "CROATIA", 0 }, { "CZ", "CZECHIA", 9801 }, { "DK", "DENMARK", 10382 },
    { "EC", "ECUADOR", 9571 }, { "EG", "EGYPT", 0 }, { "FI", "FINLAND", 9721 }, { "FR", "FRANCE", 9791 },
    { "DE", "GERMANY", 9754 }, { "GR", "GREECE", 9642 }, { "HU", "HUNGARY", 10023 }, { "IN", "INDIA", 9852 },
    { "ID", "INDONESIA", 0 }, { "IE", "IRELAND", 9890 }, { "IL", "ISRAEL", 9981 }, { "IT", "ITALY", 9647 },
    { "CI", "IVORY COAST", 0 }, { "JP", "JAPAN", 9477 }, { "KW", "KUWAIT", 10356 }, { "LV", "LATVIA", 9499 },
    { "LB", "LEBANON", 0 }, { "LU", "LUXEMBOURG", 0 }, { "MX", "MEXICO", 0 }, { "MA", "MOROCCO", 0 },
    { "NL", "NETHERLANDS", 10000 }, { "NZ", "NEW ZEALAND", 9677 }, { "NO", "NORWAY", 9862 }, { "PK", "PAKISTAN", 9617 },
    { "PE", "PERU", 9695 }, { "PH", "PHILIPPINES", 10239 }, { "PL", "POLAND", 9923 }, { "PT", "PORTUGAL", 10436 },
    { "QA", "QATAR", 0 }, { "RO", "ROMANIA", 10402 }, { "RU", "RUSSIA", 0 }, { "SA", "SAUDI ARABIA", 0 },
    { "SN", "SENEGAL", 0 }, { "RS", "SERBIA", 0 }, { "SG", "SINGAPORE", 9901 }, { "SK", "SLOVAKIA", 10137 },
    { "KR", "SOUTH KOREA", 9615 }, { "ES", "SPAIN", 9529 }, { "SE", "SWEDEN", 9887 }, { "CH", "SWITZERLAND", 0 },
    { "TH", "THAILAND", 10065 }, { "TN", "TUNISIA", 0 }, { "TR", "TURKEY", 9826 }, { "AE", "UAE", 0 },
    { "UA", "UKRAINE", 23264 }, { "GB", "UNITED KINGDOM", 10371 }, { "US", "UNITED STATES", 10366 },
    { "VE", "VENEZUELA", 9541 }, { "VN", "VIETNAM", 10114 },
}
local AVATARS = { 30288, 30556, 30875, 30878, 31325, 37390, 39199, 43417, 43573, 44500, 49344, 51693, 51695, 51697,
    51699, 51703, 51705, 51707, 51709, 51711, 52010, 52019, 52031, 53512, 56982, 57070, 58156, 58158 }
local BANNERS = { 17523, 17524, 17525, 17526, 17527, 17528, 17529, 17531, 17535, 21345, 21346, 21347, 21348, 21349,
    21350, 21351, 21352, 21353 }
local TITLES = { "ROOKIE", "SNIPER", "RUSHER", "CAMPER", "SUPPORT", "SQUAD LEADER", "LONE WOLF", "TRYHARD",
    "CLUTCH KING", "HEADHUNTER", "SLIDE MASTER", "LOOT GOBLIN", "REBIRTH LEGEND", "SWEAT", "CHILL PLAYER",
    "HUMAN AIMBOT", "ENTRY FRAGGER", "SHOT CALLER", "MEDIC", "STRATEGIST", "ROOF KING", "PREDATOR", "GHOST",
    "FINAL CIRCLE GOD" }
local WEAPONS = { 17180, 17181, 17182, 17183, 17184, 17185, 17186, 17187, 17189, 17190, 17191, 17192, 17193, 17194,
    17197, 17198, 17199, 17202, 17203, 17205, 17207, 17208, 17209, 17210, 17211, 17212, 17213, 17214, 17216, 17218,
    24669, 24670, 24677, 25498, 29641, 30275, 32080, 32081, 46570, 46989, 48518, 49649, 49835, 49909, 49948, 57063,
    58072, 58297, 58665, 60287, 64105, 65145 }

-- official divisions (same thresholds as br95_ranked_post.lua): name, start, colour, icon
local RANKS = { { "BRONZE", 0, 0xCD7F32, "bronze" }, { "SILVER", 1000, 0xC8C8C8, "silver" },
    { "GOLD", 2000, 0xE8C05A, "gold" }, { "PLATINUM", 3500, 0x5FE0C8, "platinum" },
    { "DIAMOND", 5000, 0x4FA3FF, "diamond" }, { "CRIMSON", 8000, 0xE0303A, "crimson" },
    { "IRIDESCENT", 12000, 0xC77DFF, "iridescent" }, { "TOP 250", 17000, 0xF2C14E, "top250" } }
local ROMAN = { "I", "II", "III" }

-- purple / blue look (same as the RANKED tab)
local WHITE, GREY, DIM, BLACK = 0xFFFFFF, 0xC9C0F0, 0x9488D0, 0x000000
local SIDE, MAIN, CARD, EDGE, LINE, ROW = 0x1B2C86, 0x3A2690, 0x2C1C78, 0x7A62E0, 0x2A1B70, 0x4A30AE
local GREEN, GOLD, RED, CYAN, BRUSH, MINE = 0x6BD66B, 0xFFD166, 0xFF5A6E, 0x5FD4FF, 0x2F7BFF, 0x2E6B4A
local DISCORD = 0x8C9EFF
local MEDAL = { 0xFFD166, 0xD8D8E8, 0xD08A50 }
local CHIP = { 0x4FA3FF, 0xE0303A, 0x6BD66B, 0xFFB020, 0xB061FF, 0x5FE0C8 }
local BACK_ART = "menu_keyart_rankedplay_01_layer_00"
local SR_ICON = "iw9_ui_icon_leagueplay_skill_rating"
local CX = 160                                          -- centre of the content (right of the column)
local NAV = { board = 334, me = 390, setup = 446 }

local EASE = {}
function EASE.out(x) x = 1 - x; return 1 - x * x * x end
-- goes a bit past the end and comes back (things that pop in)
function EASE.back(x) x = x - 1; return 1 + 2.2 * x * x * x + 1.2 * x * x end

local COUNTRY_BY = {}
for _, c in ipairs(COUNTRIES) do COUNTRY_BY[c[1]] = { name = c[2], flag = c[3] } end

-- ------------------------------------------------------------------
-- files
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

local function now()
    local ok, t = pcall(os.time)
    return ok and tonumber(t) or 0
end

-- "a|b||c" -> { "a", "b", "", "c" }
local function fields(line)
    local f = {}
    for part in ((line or "") .. "|"):gmatch("([^|]*)|") do f[#f + 1] = part end
    return f
end

local function readProfile()
    local f = fields((readText(PROFILE_FILE) or ""):match("^[^\r\n]*"))
    if f[1] ~= "BR95WP1" or #f < 10 then return nil end
    return { joined = f[2] == "1", name = f[3], country = f[4], avatar = tonumber(f[5]) or 0,
        banner = tonumber(f[6]) or 0, title = tonumber(f[7]) or 0, weapon = tonumber(f[8]) or 0, discord = f[9] }
end

local function writeProfile(p)
    return writeText(PROFILE_FILE, table.concat({ "BR95WP1", p.joined and 1 or 0, p.name, p.country, p.avatar,
        p.banner, p.title, p.weapon, p.discord, "END" }, "|"))
end

local function readBoard()
    local text = readText(BOARD_FILE)
    if not text then return nil end
    local board = { list = {}, fetched = 0, total = 0, season = 0 }
    for line in text:gmatch("[^\r\n]+") do
        local f = fields(line)
        if f[1] == "BR95WB1" then
            board.fetched, board.total, board.season = tonumber(f[2]) or 0, tonumber(f[3]) or 0, tonumber(f[4]) or 0
        elseif (f[1] == "P" or f[1] == "M") and #f >= 20 then
            local e = { place = tonumber(f[2]) or 0, id = f[3], name = f[4], country = f[5], sr = tonumber(f[6]) or 0,
                best = tonumber(f[7]) or 0, matches = tonumber(f[8]) or 0, kills = tonumber(f[9]) or 0,
                deaths = tonumber(f[10]) or 0, wins = tonumber(f[11]) or 0, avatar = tonumber(f[12]) or 0,
                banner = tonumber(f[13]) or 0, title = tonumber(f[14]) or 0, weapon = tonumber(f[15]) or 0,
                bot = f[16] == "1", updated = tonumber(f[17]) or 0, created = tonumber(f[18]) or 0, discord = f[19] }
            if f[1] == "P" then board.list[#board.list + 1] = e else board.me = e end
        end
    end
    return board
end

local function readStatus()
    local f = fields((readText(STATUS_FILE) or ""):match("^[^\r\n]*"))
    if f[1] ~= "BR95WS1" then return nil end
    return { state = f[2] or "", message = f[3] or "", time = tonumber(f[4]) or 0 }
end

local function myId()
    return (readText(ID_FILE) or ""):match("^BR95WI1|([^|]+)|")
end

-- local SR / matches / kills (br95_ranked.txt), for my card before the server knows me
local function localStats()
    local sr, m, k = (readText(IO .. "br95_ranked.txt") or ""):match("^BR95R1|(%-?%d+)|(%-?%d+)|(%-?%d+)|")
    return tonumber(sr) or 0, tonumber(m) or 0, tonumber(k) or 0
end

local function request()
    writeText(REQUEST_FILE, "BR95WQ1|" .. now() .. "|" .. math.random(1, 999999) .. "|END")
end

-- name allowed by the server: 3..16 of A-Z a-z 0-9 _ . -
local function cleanName(s) return (tostring(s or ""):gsub("[^%w_%.%-]", "")):sub(1, 16) end

local function lumenName()
    local json = readText("jupiter/settings.json") or ""
    return cleanName(json:match('"username"%s*:%s*"([^"]*)"'))
end

-- ------------------------------------------------------------------
-- game data
-- ------------------------------------------------------------------
local function itemImage(id)
    if not id or id <= 0 or type(LOOT) ~= "table" or type(LOOT.GetItemImageByID) ~= "function" then return nil end
    local ok, image = pcall(LOOT.GetItemImageByID, id)
    if ok and type(image) == "string" and image ~= "" then return image end
    return nil
end

local function itemName(id)
    if id and id > 0 and type(LOOT) == "table" and type(LOOT.GetItemNameByID) == "function" then
        local ok, name = pcall(LOOT.GetItemNameByID, id)
        if ok and type(name) == "string" and name ~= "" then
            if Engine and type(Engine.Localize) == "function" then
                local good, text = pcall(Engine.Localize, name)
                if good and type(text) == "string" and text ~= "" then name = text end
            end
            return string.upper(name)
        end
    end
    return "-"
end

-- division of an SR: index, label (with I / II / III), colour, shield image
local function division(sr)
    local idx = 1
    for k, r in ipairs(RANKS) do if sr >= r[2] then idx = k end end
    local r = RANKS[idx]
    local label = r[1]
    if idx < #RANKS then
        local size = (RANKS[idx + 1][2] - r[2]) / 3
        label = label .. " " .. ROMAN[math.min(3, math.floor((sr - r[2]) / size) + 1)]
    end
    return idx, label, r[3], "iw9_ui_icon_leagueplay_rank_0_" .. r[4]
end

local function ago(t)
    local s = math.max(0, now() - (t or 0))
    if s < 60 then return s .. "S AGO" end
    if s < 3600 then return math.floor(s / 60) .. " MIN AGO" end
    if s < 86400 then return math.floor(s / 3600) .. "H AGO" end
    return math.floor(s / 86400) .. " DAYS AGO"
end

-- ------------------------------------------------------------------
-- UI helpers (one table, so the page builders keep few upvalues)
-- ------------------------------------------------------------------
local function newUI(root, controller)
    local U = { anims = {}, layers = {}, buttons = {}, tweens = {}, onShow = {}, page = "" }
    U.LEFT = LUI.Alignment and LUI.Alignment.Left
    U.RIGHT = LUI.Alignment and LUI.Alignment.Right
    U.CENTER = LUI.Alignment and LUI.Alignment.Center

    local function full(parent)
        local g = LUI.UIElement.new()
        g:SetAnchorsAndPosition(0, 1, 0, 1, 0, 1920, 0, 1080)
        parent:addElement(g)
        return g
    end
    -- a page (or "common"): new elements go into it
    function U.layer(name)
        local layer = full(root)
        U.layers[name] = layer
        U.P, U.building = layer, name
        return layer
    end
    -- a group of the page that can slide / fade on its own
    function U.group()
        U.P = full(U.layers[U.building])
        return U.P
    end
    function U.ungroup() U.P = U.layers[U.building] end

    function U.font(text, size, bold)
        if FONTS and FONTS.GetFont then
            local f = bold and FONTS.PrimaryBold or FONTS.SecondaryRegular
            if f and f.File then pcall(text.SetFont, text, FONTS.GetFont(f.File)) end
        end
        if text.SetFontSize then pcall(text.SetFontSize, text, size) end
    end
    function U.box(color, alpha, l, r, t, b)
        local child = LUI.UIImage.new()
        child:SetRGB(color, 0); child:SetAlpha(alpha, 0)
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        U.P:addElement(child); return child
    end
    function U.text(str, size, color, l, r, t, b, align, bold)
        local child = LUI.UIText.new()
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        U.font(child, size, bold)
        if child.SetAlignment and LUI.Alignment then child:SetAlignment(align or U.LEFT) end
        child:SetRGB(color or WHITE, 0)
        child:setText(str)
        U.P:addElement(child); return child
    end
    function U.setPicture(child, image)
        if not child then return end
        if image then
            local ok = pcall(function() child:setImage(RegisterMaterial(image), 0) end)
            pcall(child.SetAlpha, child, ok and 1 or 0, 0)
        else
            pcall(child.SetAlpha, child, 0, 0)
        end
    end
    function U.picture(l, r, t, b, image)
        local child = LUI.UIImage.new()
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        U.P:addElement(child)
        U.setPicture(child, image)
        return child
    end
    function U.set(el, str, color)
        if not el then return end
        pcall(el.setText, el, str)
        if color then pcall(el.SetRGB, el, color, 0) end
    end
    function U.tint(el, color) if el then pcall(el.SetRGB, el, color, 0) end end
    function U.fade(el, value) if el then pcall(el.SetAlpha, el, value, 0) end end
    function U.move(el, l, r, t, b) if el then pcall(el.SetAnchorsAndPosition, el, 0.5, 0.5, 0, 1, l, r, t, b) end end
    function U.label(e, str) if e and e.btn.Text then pcall(e.btn.Text.setText, e.btn.Text, str) end end
    -- called every frame with (time in s, ms since the last frame)
    function U.animate(fn) U.anims[#U.anims + 1] = fn end
    function U.section(str, l, t)
        U.box(CYAN, 1, l, l + 5, t + 3, t + 29)
        return U.text(str, 26, WHITE, l + 16, l + 800, t, t + 32, U.LEFT, true)
    end

    -- buttons: e.on = wanted; shown when on and its page is open, else parked at y 4000
    -- (a hidden button would still light up and catch clicks)
    function U.button(l, r, t, b, label, action)
        local btn = MenuBuilder.BuildRegisteredType("GenericButton", { controllerIndex = controller })
        btn:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        U.P:addElement(btn)
        if btn.Text then pcall(btn.Text.setText, btn.Text, label) end
        local e = { btn = btn, l = l, r = r, t = t, b = b, on = true, page = U.building }
        btn:addEventHandler("button_action", function()
            if not e.on or (e.page ~= "common" and U.page ~= e.page) then return end
            pcall(action)
        end)
        U.buttons[#U.buttons + 1] = e
        return e
    end
    function U.placeButton(e)
        local t = (e.on and (e.page == "common" or e.page == U.page)) and e.t or 4000
        pcall(e.btn.SetAnchorsAndPosition, e.btn, 0.5, 0.5, 0, 1, e.l, e.r, t, t + (e.b - e.t))
    end
    function U.setButton(e, on, l, r, t, b)
        e.on = on
        if l then e.l, e.r, e.t, e.b = l, r, t, b end
        U.placeButton(e)
    end

    -- flag: the flag emblem of the game, or a coloured chip with the country code
    function U.flag(l, r, t, b, size)
        local fl = {}
        fl.chip = U.box(EDGE, 0, l, r, t + (b - t) * 0.18, b - (b - t) * 0.18)
        fl.code = U.text("", size or 14, WHITE, l, r, t + (b - t) / 2 - (size or 14) / 2 - 2, t + (b - t) / 2 + (size or 14) / 2 + 2, U.CENTER, true)
        fl.pic = U.picture(l, r, t, b, nil)
        fl.size = size or 14
        return fl
    end
    function U.setFlag(fl, code, l, r, t, b)
        if l then
            local s = fl.size
            U.move(fl.pic, l, r, t, b)
            U.move(fl.chip, l, r, t + (b - t) * 0.18, b - (b - t) * 0.18)
            U.move(fl.code, l, r, t + (b - t) / 2 - s / 2 - 2, t + (b - t) / 2 + s / 2 + 2)
        end
        local c = COUNTRY_BY[code or ""]
        local image = c and itemImage(c.flag)
        if image then
            U.setPicture(fl.pic, image); U.fade(fl.chip, 0); U.set(fl.code, "")
        else
            U.setPicture(fl.pic, nil)
            local n = code and #code == 2 and (code:byte(1) + code:byte(2)) % #CHIP + 1 or 1
            U.tint(fl.chip, CHIP[n]); U.fade(fl.chip, (code and code ~= "") and 1 or 0)
            U.set(fl.code, code or "")
        end
    end
    -- "BOT" tag
    function U.botTag(l, r, t, b)
        local tag = { back = U.box(GREY, 0, l, r, t, b), text = U.text("", 13, 0x20185A, l, r, t + (b - t) / 2 - 8, t + (b - t) / 2 + 8, U.CENTER, true) }
        return tag
    end
    function U.setBot(tag, on) U.fade(tag.back, on and 1 or 0); U.set(tag.text, on and "BOT" or "") end

    -- tweens: step(e) with e 0 -> 1 along `ease`, after `delay` ms, during `dur` ms;
    -- `fade` fades an element in; `tag` lets a later tween of the same kind stop it
    function U.tween(delay, dur, ease, step, fade, tag)
        U.tweens[#U.tweens + 1] = { delay = delay, dur = dur, ease = ease, step = step, fade = fade, tag = tag }
        pcall(step, 0)
        if fade then pcall(fade.SetAlpha, fade, 0, 0) end
    end
    function U.drop(tag)
        for k = #U.tweens, 1, -1 do if U.tweens[k].tag == tag then table.remove(U.tweens, k) end end
    end
    function U.runTweens(ms)
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
    end
    -- a full-screen group slides in from (dx, dy) and fades in
    function U.enter(g, delay, dur, dx, dy, ease, tag)
        U.tween(delay, dur, ease or EASE.out, function(e)
            local x, y = dx * (1 - e), dy * (1 - e)
            g:SetAnchorsAndPosition(0, 1, 0, 1, x, 1920 + x, y, 1080 + y)
        end, g, tag)
    end
    -- a picture / box pops from `from` (0..1) of its size to its size
    function U.pop(el, l, r, t, b, delay, from, tag)
        local cx, cy, w, h = (l + r) / 2, (t + b) / 2, (r - l) / 2, (b - t) / 2
        U.tween(delay, 520, EASE.back, function(e)
            local s = from + (1 - from) * e
            U.move(el, cx - w * s, cx + w * s, cy - h * s, cy + h * s)
        end, nil, tag)
    end
    function U.flash(el, color)
        if not el then return end
        U.tint(el, color or WHITE)
        U.tween(0, 600, EASE.out, function(e) U.fade(el, 0.7 * (1 - e)) end)
    end

    -- page switch; nav = which column button gets the mark
    function U.show(name, nav)
        U.page = name
        for pageName, layer in pairs(U.layers) do
            if pageName ~= "common" then pcall(layer.SetAlpha, layer, (pageName == name) and 1 or 0, (pageName == name) and 200 or 0) end
        end
        for _, e in ipairs(U.buttons) do U.placeButton(e) end
        local from, to = U.navY or NAV.board, NAV[nav or name] or NAV.board
        U.drop("mark")
        U.tween(0, 280, EASE.out, function(e)
            U.navY = from + (to - from) * e
            U.move(U.navMark, -944, -936, U.navY, U.navY + 46)
            U.move(U.navWash, -936, -652, U.navY, U.navY + 46)
        end, nil, "mark")
    end
    return U
end

-- ------------------------------------------------------------------
-- left column: title, my card, page buttons, sync state
-- ------------------------------------------------------------------
local function buildColumn(U)
    U.layer("common")
    local side = U.group()
    U.text("WORLD", 18, CYAN, -930, -660, 124, 146, U.LEFT, true)
    U.text("RANKING", 48, WHITE, -930, -650, 144, 198, U.LEFT, true)
    local brush = U.box(BRUSH, 1, -930, -929, 208, 214)
    local tail = U.box(CYAN, 1, -796, -772, 209, 213)
    U.tween(450, 500, EASE.out, function(e) U.move(brush, -930, -930 + math.max(1, 130 * e), 208, 214) end)
    U.tween(850, 300, EASE.out, function() end, tail)

    -- my card (click = my profile)
    U.button(-934, -650, 226, 310, "", function() U.openMine() end)
    U.box(CARD, 0.9, -934, -650, 226, 310)
    U.meFrame = U.box(CYAN, 1, -930, -854, 230, 306)
    U.meAvatar = U.picture(-928, -856, 232, 304, nil)
    U.meName = U.text("", 20, WHITE, -846, -654, 234, 260, U.LEFT, true)
    U.mePlace = U.text("", 15, CYAN, -846, -654, 262, 282, U.LEFT, true)
    U.meSR = U.text("", 15, GREY, -846, -654, 284, 304, U.LEFT, true)

    U.navWash = U.box(WHITE, 0.10, -936, -652, NAV.board, NAV.board + 46)
    U.navMark = U.box(WHITE, 1, -944, -936, NAV.board, NAV.board + 46)
    U.navY = NAV.board
    U.button(-930, -656, NAV.board, NAV.board + 46, "RANKING", function() U.openBoard() end)
    U.button(-930, -656, NAV.me, NAV.me + 46, "MY PROFILE", function() U.openMine() end)
    U.button(-930, -656, NAV.setup, NAV.setup + 46, "EDIT PROFILE", function() U.openSetup() end)

    U.syncDot = U.box(GREEN, 1, -930, -918, 880, 892)
    U.syncState = U.text("", 16, WHITE, -910, -654, 874, 898, U.LEFT, true)
    U.syncInfo = U.text("", 13, GREY, -930, -654, 902, 922, U.LEFT, true)
    U.syncHelp = U.text("", 13, GREY, -930, -654, 926, 946, U.LEFT, true)
    U.syncHelp2 = U.text("", 13, GREY, -930, -654, 948, 968, U.LEFT, true)
    U.ungroup()
    U.enter(side, 0, 520, -80, 0)
end

-- ------------------------------------------------------------------
-- RANKING page: podium (top 3) + 10 rows per page, every player can be clicked
-- ------------------------------------------------------------------
local function buildBoard(U)
    U.layer("board")
    local B = { page = 1, filter = "global", rows = {}, podium = {} }
    U.B = B
    U.section("WORLD RANKING", -610, 124)
    B.info = U.text("", 16, GREY, -610, 540, 164, 186, U.LEFT, true)
    B.globalBtn = U.button(560, 744, 124, 166, "GLOBAL", function() B.filter = "global"; B.page = 1; U.refreshBoard(true) end)
    B.countryBtn = U.button(752, 936, 124, 166, "MY COUNTRY", function() B.filter = "country"; B.page = 1; U.refreshBoard(true) end)
    B.filterMark = U.box(CYAN, 1, 560, 744, 168, 172)

    for k = 1, 3 do
        local l = -620 + (k - 1) * 524
        local r, t, b = l + 512, 196, 340
        local P = {}
        P.g = U.group()
        P.btn = U.button(l, r, t, b, "", function() if P.entry then U.openProfile(P.entry) end end)
        U.box(CARD, 1, l, r, t, b)
        P.banner = U.picture(l, r, t, b, nil)
        U.box(BLACK, 0.5, l, r, t, b)
        U.box(MEDAL[k], 1, l, r, b - 4, b)
        U.text("#" .. k, 44, MEDAL[k], l + 14, l + 110, t + 8, t + 58, U.LEFT, true)
        U.box(MEDAL[k], 1, l + 14, l + 90, t + 62, t + 138)
        P.avatar = U.picture(l + 16, l + 88, t + 64, t + 136, nil)
        P.bot = U.botTag(l + 24, l + 80, t + 116, t + 134)
        P.flag = U.flag(l + 104, l + 136, t + 16, t + 48, 13)
        P.name = U.text("", 26, WHITE, l + 144, r - 12, t + 16, t + 50, U.LEFT, true)
        P.title = U.text("", 15, CYAN, l + 104, r - 100, t + 54, t + 74, U.LEFT, true)
        P.shield = U.picture(r - 92, r - 12, t + 56, t + 136, nil)
        P.sr = U.text("", 30, WHITE, l + 104, r - 100, t + 92, t + 130, U.LEFT, true)
        U.ungroup()
        B.podium[k] = P
    end

    U.text("#", 14, DIM, -604, -540, 352, 370, U.LEFT, true)
    U.text("PLAYER", 14, DIM, -480, 0, 352, 370, U.LEFT, true)
    U.text("DIVISION", 14, DIM, 150, 400, 352, 370, U.LEFT, true)
    U.text("MATCHES", 14, DIM, 410, 520, 352, 370, U.LEFT, true)
    U.text("K/D", 14, DIM, 530, 640, 352, 370, U.LEFT, true)
    U.text("SR", 14, DIM, 660, 928, 352, 370, U.RIGHT, true)
    for k = 1, 10 do
        local t = 376 + (k - 1) * 56
        local R = { t = t }
        R.g = U.group()
        -- the row is one button (under the pictures and texts)
        R.btn = U.button(-620, 940, t, t + 52, "", function() if R.entry then U.openProfile(R.entry) end end)
        R.back = U.box(ROW, 0.6, -620, 940, t, t + 52)
        R.mark = U.box(CYAN, 1, -620, -614, t, t + 52)
        R.place = U.text("", 22, WHITE, -604, -530, t + 13, t + 39, U.LEFT, true)
        R.flag = U.flag(-526, -490, t + 8, t + 44, 12)
        R.avatar = U.picture(-482, -436, t + 3, t + 49, nil)
        R.name = U.text("", 20, WHITE, -424, 60, t + 4, t + 28, U.LEFT, true)
        R.title = U.text("", 13, CYAN, -424, 60, t + 30, t + 48, U.LEFT, true)
        R.bot = U.botTag(70, 126, t + 16, t + 36)
        R.shield = U.picture(150, 190, t + 6, t + 46, nil)
        R.div = U.text("", 16, WHITE, 200, 400, t + 15, t + 37, U.LEFT, true)
        R.matches = U.text("", 16, GREY, 410, 520, t + 15, t + 37, U.LEFT, true)
        R.kd = U.text("", 16, GREY, 530, 640, t + 15, t + 37, U.LEFT, true)
        R.sr = U.text("", 22, WHITE, 660, 898, t + 13, t + 39, U.RIGHT, true)
        R.srIcon = U.picture(904, 928, t + 14, t + 38, SR_ICON)
        U.ungroup()
        B.rows[k] = R
    end
    B.empty = U.text("", 20, GREY, -610, 930, 560, 590, U.CENTER, true)

    U.button(-620, -440, 944, 984, "TOP", function() B.page = 1; U.refreshBoard(true) end)
    U.button(-430, -250, 944, 984, "< PREV", function() B.page = B.page - 1; U.refreshBoard(true) end)
    B.pageText = U.text("", 18, WHITE, -240, 140, 952, 976, U.CENTER, true)
    U.button(150, 330, 944, 984, "NEXT >", function() B.page = B.page + 1; U.refreshBoard(true) end)
    U.button(340, 520, 944, 984, "FIND ME", function()
        for i, e in ipairs(B.shown or {}) do
            if e.id == U.id then B.page = math.ceil(i / 10); U.refreshBoard(true); return end
        end
        B.note = (U.board and U.board.me) and ("YOU ARE #" .. U.board.me.place .. " (OUTSIDE THIS LIST)") or "YOU ARE NOT IN THE LIST YET"
        U.refreshBoard(false)
    end)
    U.button(530, 710, 944, 984, "REFRESH", function() request(); B.note = "REFRESHING..."; U.refreshBoard(false) end)

    -- the rows of the page slide in from the right, the podium pops
    function U.boardIntro()
        for k, P in ipairs(B.podium) do if P.entry then U.enter(P.g, 40 + k * 90, 480, 0, 40, EASE.back, "page") end end
        for k, R in ipairs(B.rows) do if R.entry then U.enter(R.g, 160 + k * 45, 420, 120, 0, nil, "page") end end
    end

    function U.refreshBoard(animate)
        local board = U.board
        local list = {}
        local myCountry = U.profile and U.profile.country or ""
        for _, e in ipairs(board and board.list or {}) do
            if B.filter == "global" or e.country == myCountry then list[#list + 1] = e end
        end
        B.shown = list
        local pages = math.max(1, math.ceil(#list / 10))
        B.page = math.max(1, math.min(pages, B.page))
        U.move(B.filterMark, B.filter == "global" and 560 or 752, B.filter == "global" and 744 or 936, 168, 172)
        -- info line: warnings first
        local st = U.syncState_
        local info, color = "", GREY
        if U.profile and U.profile.joined and st == "NAMETAKEN" then
            info, color = "THIS PSEUDO IS ALREADY TAKEN: EDIT YOUR PROFILE", RED
        elseif st == "OFF" then
            info, color = "THE RANKING CANNOT UPDATE: OPEN THE ARTEFACT LAUNCHER ONCE (IT STARTS THE SYNC)", RED
        elseif B.note then
            info, color = B.note, CYAN
        elseif board then
            info = "SEASON " .. board.season .. "  |  " .. board.total .. " PLAYERS  |  UPDATED " .. ago(board.fetched)
        end
        B.note = nil
        U.set(B.info, info, color)
        for k, P in ipairs(B.podium) do
            local e = list[k]
            P.entry = e
            U.setButton(P.btn, e ~= nil)
            if e then
                local _, _, divColor, shield = division(e.sr)
                U.setPicture(P.banner, itemImage(e.banner))
                U.setPicture(P.avatar, itemImage(e.avatar))
                U.setBot(P.bot, e.bot)
                U.setFlag(P.flag, e.country)
                U.set(P.name, e.name, (e.id == U.id) and GREEN or WHITE)
                U.set(P.title, TITLES[e.title] or "")
                U.setPicture(P.shield, shield)
                U.set(P.sr, e.sr .. " SR", divColor)
                U.fade(P.g, 1)
            else
                U.fade(P.g, 0)
            end
        end
        for k, R in ipairs(B.rows) do
            local i = (B.page - 1) * 10 + k
            local e = list[i]
            R.entry = e
            U.setButton(R.btn, e ~= nil)
            if e then
                local _, label, divColor, shield = division(e.sr)
                local me = (e.id == U.id)
                U.tint(R.back, me and MINE or ROW)
                U.tint(R.mark, me and GREEN or (e.place <= 3 and MEDAL[e.place] or CYAN))
                U.fade(R.mark, (me or e.place <= 3) and 1 or 0)
                U.set(R.place, "#" .. e.place, e.place <= 3 and MEDAL[e.place] or WHITE)
                U.setFlag(R.flag, e.country)
                U.setPicture(R.avatar, itemImage(e.avatar))
                U.set(R.name, e.name, me and GREEN or WHITE)
                U.set(R.title, TITLES[e.title] or "")
                U.setBot(R.bot, e.bot)
                U.setPicture(R.shield, shield)
                U.set(R.div, label, divColor)
                U.set(R.matches, tostring(e.matches))
                U.set(R.kd, string.format("%.2f", e.kills / math.max(1, e.deaths)))
                U.set(R.sr, tostring(e.sr), divColor)
                U.fade(R.g, 1)
            else
                U.fade(R.g, 0)
            end
        end
        if not board then
            U.set(B.empty, (st == "OFF") and "NO RANKING YET: OPEN THE ARTEFACT LAUNCHER ONCE" or "LOADING THE RANKING...")
        elseif #list == 0 then
            U.set(B.empty, (B.filter == "country") and "NOBODY FROM YOUR COUNTRY YET" or "NOBODY IN THE RANKING YET")
        else
            U.set(B.empty, "")
        end
        U.set(B.pageText, "PAGE " .. B.page .. " / " .. pages)
        if animate then U.boardIntro() end
    end
end

-- ------------------------------------------------------------------
-- PROFILE page (any player)
-- ------------------------------------------------------------------
local function buildProfile(U)
    U.layer("profile")
    local P = { tiles = {}, info = {} }
    U.PR = P
    P.bannerG = U.group()
    U.box(CARD, 1, -620, 340, 124, 364)
    P.banner = U.picture(-620, 340, 124, 364, nil)
    U.box(BLACK, 0.2, -620, 340, 124, 364)
    U.box(BLACK, 0.45, -620, 340, 300, 364)
    P.bannerLine = U.box(CYAN, 1, -620, 340, 362, 366)
    U.ungroup()

    P.divG = U.group()
    U.box(ROW, 0.85, 356, 940, 124, 364)
    P.divLine = U.box(CYAN, 1, 356, 940, 124, 127)
    P.shield = U.picture(376, 526, 156, 306, nil)
    U.text("DIVISION", 14, GREY, 546, 930, 150, 168, U.LEFT, true)
    P.div = U.text("", 28, WHITE, 546, 930, 170, 204, U.LEFT, true)
    P.sr = U.text("", 34, WHITE, 546, 930, 208, 248, U.LEFT, true)
    P.place = U.text("", 20, CYAN, 546, 930, 252, 278, U.LEFT, true)
    P.best = U.text("", 16, GREY, 546, 930, 282, 304, U.LEFT, true)
    P.season = U.text("", 14, DIM, 546, 930, 308, 326, U.LEFT, true)
    U.ungroup()

    P.idG = U.group()
    P.avFrame = U.box(WHITE, 1, -600, -412, 266, 454)
    U.box(CARD, 1, -598, -414, 268, 452)
    P.avatar = U.picture(-596, -416, 270, 450, nil)
    P.bot = U.botTag(-560, -452, 426, 448)
    P.name = U.text("", 46, WHITE, -396, 340, 372, 420, U.LEFT, true)
    P.title = U.text("", 22, CYAN, -396, 340, 422, 448, U.LEFT, true)
    P.flag = U.flag(-396, -360, 454, 490, 13)
    P.country = U.text("", 18, WHITE, -350, 340, 460, 484, U.LEFT, true)
    P.discord = U.text("", 18, DISCORD, -396, 340, 494, 518, U.LEFT, true)
    U.ungroup()

    local names = { "MATCHES", "WINS", "WIN RATE", "KILLS", "DEATHS", "K/D", "KILLS / MATCH" }
    local w = 1560 / #names
    for k, name in ipairs(names) do
        local l = -620 + (k - 1) * w
        local g = U.group()
        U.box(ROW, 0.85, l + 4, l + w - 4, 530, 626)
        U.box(CYAN, 1, l + 4, l + w - 4, 530, 533)
        U.text(name, 14, GREY, l + 16, l + w - 8, 544, 562, U.LEFT, true)
        local value = U.text("", 32, WHITE, l + 16, l + w - 8, 568, 608, U.LEFT, true)
        U.ungroup()
        P.tiles[k] = { g = g, value = value }
    end

    P.weaponG = U.group()
    U.box(ROW, 0.85, -620, 400, 642, 860)
    U.text("FAVORITE WEAPON", 18, GREY, -604, 380, 652, 674, U.LEFT, true)
    P.weapon = U.picture(-600, -120, 684, 844, nil)
    P.weaponName = U.text("", 28, WHITE, -100, 390, 744, 780, U.LEFT, true)
    U.ungroup()
    P.infoG = U.group()
    U.box(ROW, 0.85, 416, 940, 642, 860)
    U.text("PLAYER INFO", 18, GREY, 432, 930, 652, 674, U.LEFT, true)
    for k = 1, 4 do P.info[k] = U.text("", 17, WHITE, 432, 930, 688 + (k - 1) * 40, 712 + (k - 1) * 40, U.LEFT, true) end
    U.ungroup()

    -- (no way to leave the ranking: once made, a profile stays in it)
    U.button(-620, -380, 880, 930, "BACK TO RANKING", function() U.openBoard() end)
    P.editBtn = U.button(-370, -130, 880, 930, "EDIT PROFILE", function() U.openSetup() end)
    P.msg = U.text("", 16, GREY, -110, 940, 894, 918, U.LEFT, true)

    function U.openProfile(e)
        local me = (e.id == U.id) or e.local_
        local _, label, divColor, shield = division(e.sr)
        U.setPicture(P.banner, itemImage(e.banner))
        U.setPicture(P.avatar, itemImage(e.avatar))
        U.setBot(P.bot, e.bot)
        U.set(P.name, e.name, me and GREEN or WHITE)
        U.set(P.title, TITLES[e.title] or "")
        U.setFlag(P.flag, e.country)
        U.set(P.country, (COUNTRY_BY[e.country] and COUNTRY_BY[e.country].name) or e.country or "")
        U.set(P.discord, (e.discord and e.discord ~= "") and ("DISCORD   " .. e.discord) or "")
        for _, el in ipairs({ P.bannerLine, P.divLine, P.avFrame }) do U.tint(el, divColor) end
        U.setPicture(P.shield, shield)
        U.set(P.div, label, divColor)
        U.set(P.place, (e.place and e.place > 0) and ("#" .. e.place .. " IN THE WORLD") or "NOT RANKED YET")
        U.set(P.best, "BEST SR THIS SEASON  " .. math.max(e.best or 0, e.sr))
        U.set(P.season, e.bot and "BOT" or ((U.board and U.board.season or 1) > 0 and ("SEASON " .. (U.board and U.board.season or 1)) or ""))
        U.setPicture(P.weapon, itemImage(e.weapon))
        U.set(P.weaponName, itemName(e.weapon))
        local okC, created = pcall(os.date, "!%d/%m/%Y", e.created or 0)
        U.set(P.info[1], "MEMBER SINCE   " .. ((e.created or 0) > 0 and okC and created or "-"))
        U.set(P.info[2], "LAST UPDATE   " .. ((e.updated or 0) > 0 and ago(e.updated) or "-"))
        U.set(P.info[3], "COUNTRY   " .. (e.country or "-"))
        U.set(P.info[4], e.bot and "THIS PLAYER IS A BOT OF THE SERVER" or (me and "THIS IS YOU" or ""))
        U.setButton(P.editBtn, me)
        U.set(P.msg, "")
        U.show("profile", me and "me" or "board")
        -- the banner settles from a zoom, the avatar pops, the stats count up
        U.drop("page")
        U.tween(0, 900, EASE.out, function(x)
            local z = 40 * (1 - x)
            U.move(P.banner, -620 - z, 340 + z, 124 - z * 0.25, 364 + z * 0.25)
        end, nil, "page")
        U.enter(P.bannerG, 0, 360, 0, 0, nil, "page")
        U.pop(P.avatar, -596, -416, 270, 450, 120, 0.4, "page")
        U.pop(P.avFrame, -600, -412, 266, 454, 120, 0.4, "page")
        U.enter(P.idG, 120, 420, 0, 30, nil, "page")
        U.enter(P.divG, 180, 460, 80, 0, nil, "page")
        local values = { e.matches, e.wins, e.matches > 0 and math.floor(e.wins * 100 / e.matches + 0.5) or 0, e.kills,
            e.deaths, e.kills / math.max(1, e.deaths), e.matches > 0 and e.kills / e.matches or 0 }
        for k, tile in ipairs(P.tiles) do
            U.enter(tile.g, 260 + k * 60, 460, 0, 34, EASE.back, "page")
            local v = values[k]
            U.tween(320 + k * 60, 900, EASE.out, function(x)
                local s
                if k == 3 then s = math.floor(v * x + 0.5) .. "%"
                elseif k >= 6 then s = string.format(k == 6 and "%.2f" or "%.1f", v * x)
                else s = tostring(math.floor(v * x + 0.5)) end
                U.set(tile.value, s)
            end, nil, "page")
        end
        U.enter(P.weaponG, 600, 480, -100, 0, nil, "page")
        U.enter(P.infoG, 660, 480, 100, 0, nil, "page")
    end
end

-- ------------------------------------------------------------------
-- PROFILE WIZARD: pseudo, nationality, avatar, banner, title, weapon, Discord
-- ------------------------------------------------------------------
local STEPS = {
    { key = "name", title = "PSEUDO", kind = "keys",
      hint = { "3 TO 16 CHARACTERS", "LETTERS, NUMBERS, _ . -", "EVERY PSEUDO IS UNIQUE" } },
    { key = "country", title = "NATIONALITY", kind = "grid", cols = 6, rows = 4, w = 160, h = 140,
      hint = { "YOUR FLAG IS SHOWN NEXT TO YOUR", "PSEUDO IN THE RANKING", "" } },
    { key = "avatar", title = "AVATAR", kind = "grid", cols = 7, rows = 4, w = 136, h = 136,
      hint = { "YOUR PICTURE IN THE RANKING", "AND ON YOUR PROFILE", "" } },
    { key = "banner", title = "BANNER", kind = "grid", cols = 3, rows = 6, w = 328, h = 82,
      hint = { "THE BIG PICTURE AT THE TOP", "OF YOUR PROFILE", "" } },
    { key = "title", title = "TITLE", kind = "grid", cols = 4, rows = 6, w = 244, h = 70,
      hint = { "A SHORT TITLE SHOWN", "UNDER YOUR PSEUDO", "" } },
    { key = "weapon", title = "FAVORITE WEAPON", kind = "grid", cols = 4, rows = 4, w = 244, h = 136,
      hint = { "SHOWN ON YOUR PROFILE", "", "" } },
    { key = "discord", title = "DISCORD", kind = "keys",
      hint = { "OPTIONAL: YOUR DISCORD NAME SO", "PLAYERS CAN ADD YOU", "LEAVE EMPTY TO HIDE IT" } },
}
local KEY_ROWS = { "1234567890", "QWERTYUIOP", "ASDFGHJKL_", "ZXCVBNM.-" }

-- values of a grid step
local function stepList(key)
    if key == "country" then
        local list = {}
        for k, c in ipairs(COUNTRIES) do list[k] = c[1] end
        return list
    elseif key == "avatar" then return AVATARS
    elseif key == "banner" then return BANNERS
    elseif key == "weapon" then return WEAPONS
    elseif key == "title" then
        local list = {}
        for k in ipairs(TITLES) do list[k] = k end
        return list
    end
    return {}
end

local function buildSetup(U)
    U.layer("setup")
    local S = { step = 1, page = 1, upper = true, cells = {}, keys = {}, draft = {} }
    U.S = S
    U.box(CYAN, 1, -610, -605, 127, 153)
    S.titleText = U.text("", 26, WHITE, -594, 380, 124, 156, U.LEFT, true)
    S.stepText = U.text("", 16, GREY, -610, 380, 162, 184, U.LEFT, true)
    S.bar = {}
    local segW = (1000 - 6 * 6) / 7
    for k = 1, 7 do
        local l = -620 + (k - 1) * (segW + 6)
        S.bar[k] = U.box(LINE, 1, l, l + segW, 194, 200)
    end

    -- keyboard step: the text, then the keys
    S.keyG = U.group()
    U.box(ROW, 0.85, -620, 380, 222, 300)
    S.inputLine = U.box(CYAN, 1, -620, 380, 297, 300)
    S.input = U.text("", 40, WHITE, -600, 200, 236, 286, U.LEFT, true)
    S.count = U.text("", 16, GREY, 200, 366, 252, 272, U.RIGHT, true)
    U.ungroup()
    for row, chars in ipairs(KEY_ROWS) do
        for k = 1, #chars do
            local ch = chars:sub(k, k)
            local l, t = -620 + (k - 1) * 100, 316 + (row - 1) * 64
            local key = { ch = ch }
            key.e = U.button(l, l + 92, t, t + 56, ch, function() U.typeKey(key.ch) end)
            S.keys[#S.keys + 1] = key
        end
    end
    S.caseBtn = U.button(-620, -420, 572, 628, "abc", function() S.upper = not S.upper; U.paintKeys() end)
    S.delBtn = U.button(-410, -210, 572, 628, "DEL", function() U.typeKey("DEL") end)
    S.clearBtn = U.button(-200, 0, 572, 628, "CLEAR", function() U.typeKey("CLEAR") end)
    S.useBtn = U.button(10, 380, 572, 628, "USE MY GAME NAME", function() U.typeKey("USE") end)

    -- grid steps: one pool of 28 cells, placed for each step
    S.sel = U.box(CYAN, 0, 0, 1, 0, 1)
    for k = 1, 28 do
        local c = {}
        c.e = U.button(-620, -500, 230, 350, "", function() U.pickCell(k) end)
        c.back = U.box(ROW, 0.55, -620, -500, 230, 350)
        c.pic = U.picture(-620, -500, 230, 350, nil)
        c.flag = U.flag(-620, -500, 230, 350, 20)
        c.label = U.text("", 14, WHITE, -620, -500, 330, 350, U.CENTER, true)
        S.cells[k] = c
    end
    S.prevBtn = U.button(-620, -420, 822, 862, "< PAGE", function() S.page = S.page - 1; U.paintStep(true) end)
    S.pageText = U.text("", 18, WHITE, -410, 170, 830, 854, U.CENTER, true)
    S.nextPageBtn = U.button(180, 380, 822, 862, "PAGE >", function() S.page = S.page + 1; U.paintStep(true) end)
    S.msg = U.text("", 18, RED, -620, 380, 872, 898, U.LEFT, true)
    S.backBtn = U.button(-620, -400, 916, 964, "BACK", function()
        if S.step > 1 then S.step = S.step - 1; S.page = 0; U.paintStep(true) end
    end)
    S.cancelBtn = U.button(-390, -170, 916, 964, "CANCEL", function() U.openBoard() end)
    S.nextBtn = U.button(160, 380, 916, 964, "NEXT", function() U.nextStep() end)

    -- preview card (updates live)
    S.pv = U.group()
    U.box(CARD, 1, 400, 940, 172, 307)
    S.pvBanner = U.picture(400, 940, 172, 307, nil)
    U.box(BLACK, 0.35, 400, 940, 240, 307)
    U.box(ROW, 0.9, 400, 940, 307, 640)
    S.pvFrame = U.box(WHITE, 1, 418, 542, 248, 372)
    U.box(CARD, 1, 420, 540, 250, 370)
    S.pvAvatar = U.picture(422, 538, 252, 368, nil)
    S.pvName = U.text("", 30, WHITE, 556, 936, 312, 348, U.LEFT, true)
    S.pvTitle = U.text("", 18, CYAN, 556, 936, 350, 374, U.LEFT, true)
    S.pvFlag = U.flag(418, 452, 388, 422, 12)
    S.pvCountry = U.text("", 18, WHITE, 462, 936, 393, 417, U.LEFT, true)
    S.pvDiscord = U.text("", 16, DISCORD, 418, 936, 428, 450, U.LEFT, true)
    U.text("FAVORITE WEAPON", 14, GREY, 418, 936, 466, 484, U.LEFT, true)
    S.pvWeapon = U.picture(418, 718, 492, 592, nil)
    S.pvWeaponName = U.text("", 18, WHITE, 728, 936, 530, 556, U.LEFT, true)
    S.pvSR = U.text("", 16, GREY, 418, 936, 606, 630, U.LEFT, true)
    S.pvFlash = U.box(WHITE, 0, 400, 940, 172, 640)
    U.ungroup()
    U.box(ROW, 0.85, 400, 940, 656, 800)
    U.text("TIP", 14, CYAN, 418, 936, 666, 684, U.LEFT, true)
    S.hint = {}
    for k = 1, 3 do S.hint[k] = U.text("", 16, WHITE, 418, 936, 690 + (k - 1) * 30, 712 + (k - 1) * 30, U.LEFT, true) end

    function U.paintPreview()
        local d = S.draft
        U.setPicture(S.pvBanner, itemImage(d.banner))
        U.setPicture(S.pvAvatar, itemImage(d.avatar))
        U.set(S.pvName, (d.name ~= "") and d.name or "-")
        U.set(S.pvTitle, TITLES[d.title] or "")
        U.setFlag(S.pvFlag, d.country)
        U.set(S.pvCountry, (COUNTRY_BY[d.country] and COUNTRY_BY[d.country].name) or "")
        U.set(S.pvDiscord, (d.discord ~= "") and ("DISCORD   " .. d.discord) or "")
        U.setPicture(S.pvWeapon, itemImage(d.weapon))
        U.set(S.pvWeaponName, itemName(d.weapon))
        local sr = localStats()
        local _, label, color = division(sr)
        U.set(S.pvSR, "YOUR SR " .. sr .. "   |   " .. label, color)
        U.tint(S.pvFrame, color)
    end

    function U.paintKeys()
        local discord = STEPS[S.step].key == "discord"
        for _, key in ipairs(S.keys) do
            local ch = key.ch
            if ch:match("%a") then ch = (S.upper and not discord) and ch:upper() or ch:lower() end
            U.label(key.e, ch)
        end
        U.label(S.caseBtn, S.upper and "abc" or "ABC")
        U.setButton(S.caseBtn, U.page == "setup" and not discord and STEPS[S.step].kind == "keys")
    end

    function U.paintInput()
        local key = STEPS[S.step].key
        local value = S.draft[key] or ""
        local max = (key == "discord") and 32 or 16
        S.blinkText = value
        U.set(S.input, value)
        U.set(S.count, #value .. " / " .. max)
    end

    function U.typeKey(ch)
        local key = STEPS[S.step].key
        local discord = key == "discord"
        local value = S.draft[key] or ""
        local max = discord and 32 or 16
        U.set(S.msg, "")
        if ch == "DEL" then value = value:sub(1, -2)
        elseif ch == "CLEAR" then value = ""
        elseif ch == "USE" then
            if discord then value = "" else value = lumenName() end
        else
            if ch:match("%a") then ch = (S.upper and not discord) and ch:upper() or ch:lower() end
            if discord and ch == "-" then U.set(S.msg, "DISCORD NAMES CANNOT HAVE -"); return end
            if #value >= max then U.set(S.msg, "MAX " .. max .. " CHARACTERS"); return end
            value = value .. ch
        end
        S.draft[key] = value
        U.paintInput()
        U.paintPreview()
    end

    function U.pickCell(k)
        local step = STEPS[S.step]
        local list = stepList(step.key)
        local per = step.cols * step.rows
        local value = list[(S.page - 1) * per + k]
        if value == nil then return end
        S.draft[step.key] = value
        U.placeSel(true)
        U.paintPreview()
        U.flash(S.pvFlash, CYAN)
    end

    -- the cyan frame behind the chosen cell glides to it
    function U.placeSel(animate)
        local step = STEPS[S.step]
        if step.kind ~= "grid" then U.fade(S.sel, 0); return end
        local list = stepList(step.key)
        local per = step.cols * step.rows
        local at
        for i, v in ipairs(list) do if v == S.draft[step.key] then at = i end end
        if not at or math.ceil(at / per) ~= S.page then U.fade(S.sel, 0); return end
        local k = at - (S.page - 1) * per
        local col, row = (k - 1) % step.cols, math.floor((k - 1) / step.cols)
        local l, t = -620 + col * (step.w + 8), 230 + row * (step.h + 8)
        local to = { l - 4, l + step.w + 4, t - 4, t + step.h + 4 }
        local from = S.selRect or to
        S.selRect = to
        U.fade(S.sel, 1)
        U.drop("sel")
        U.tween(0, animate and 260 or 1, EASE.out, function(e)
            U.move(S.sel, from[1] + (to[1] - from[1]) * e, from[2] + (to[2] - from[2]) * e,
                from[3] + (to[3] - from[3]) * e, from[4] + (to[4] - from[4]) * e)
        end, nil, "sel")
    end

    -- shows the current step (cells, keyboard, texts, buttons)
    function U.paintStep(animate)
        local step = STEPS[S.step]
        local editing = U.profile and U.profile.joined
        U.set(S.titleText, editing and "EDIT YOUR PROFILE" or "CREATE YOUR WORLD RANKING PROFILE")
        U.set(S.stepText, "STEP " .. S.step .. " / " .. #STEPS .. "   -   " .. step.title)
        for k, seg in ipairs(S.bar) do U.tint(seg, (k <= S.step) and CYAN or LINE) end
        for k = 1, 3 do U.set(S.hint[k], step.hint[k] or "") end
        U.set(S.msg, "")
        local keys = step.kind == "keys"
        U.fade(S.keyG, keys and 1 or 0)
        for _, key in ipairs(S.keys) do U.setButton(key.e, keys) end
        U.setButton(S.delBtn, keys); U.setButton(S.clearBtn, keys); U.setButton(S.useBtn, keys)
        U.label(S.useBtn, (step.key == "discord") and "NO DISCORD" or "USE MY GAME NAME")
        U.paintKeys()
        if keys then U.paintInput() end
        -- grid
        local list = keys and {} or stepList(step.key)
        local per = keys and 0 or step.cols * step.rows
        local pages = keys and 1 or math.max(1, math.ceil(#list / per))
        if S.page == 0 and not keys then
            -- open on the page of the current choice
            S.page = 1
            for i, v in ipairs(list) do if v == S.draft[step.key] then S.page = math.ceil(i / per) end end
        end
        S.page = math.max(1, math.min(pages, S.page))
        for k, c in ipairs(S.cells) do
            local value = (not keys and k <= per) and list[(S.page - 1) * per + k] or nil
            if value ~= nil then
                local col, row = (k - 1) % step.cols, math.floor((k - 1) / step.cols)
                local l, t = -620 + col * (step.w + 8), 230 + row * (step.h + 8)
                local r, b = l + step.w, t + step.h
                local cx = (l + r) / 2
                U.setButton(c.e, true, l, r, t, b)
                U.move(c.back, l, r, t, b); U.fade(c.back, 0.55)
                U.set(c.label, "")
                U.setPicture(c.pic, nil)
                U.setFlag(c.flag, nil)
                if step.key == "country" then
                    U.setFlag(c.flag, value, cx - 40, cx + 40, t + 12, t + 92)
                    U.move(c.label, l + 4, r - 4, t + 100, t + 124)
                    U.set(c.label, COUNTRY_BY[value].name)
                elseif step.key == "avatar" then
                    U.move(c.pic, l + 8, r - 8, t + 8, b - 8)
                    U.setPicture(c.pic, itemImage(value))
                elseif step.key == "banner" then
                    U.move(c.pic, l + 4, r - 4, t + 4, b - 4)
                    U.setPicture(c.pic, itemImage(value))
                elseif step.key == "title" then
                    U.move(c.label, l + 6, r - 6, t + step.h / 2 - 12, t + step.h / 2 + 12)
                    U.set(c.label, TITLES[value])
                elseif step.key == "weapon" then
                    U.move(c.pic, l + 12, r - 12, t + 6, t + 98)
                    U.setPicture(c.pic, itemImage(value))
                    U.move(c.label, l + 4, r - 4, t + 104, t + 126)
                    U.set(c.label, itemName(value))
                end
                if animate then U.pop(c.back, l, r, t, b, k * 14, 0.6, "page") end
            else
                U.setButton(c.e, false)
                U.fade(c.back, 0); U.set(c.label, ""); U.setPicture(c.pic, nil); U.setFlag(c.flag, nil)
            end
        end
        local paged = not keys and pages > 1
        U.setButton(S.prevBtn, paged and S.page > 1)
        U.setButton(S.nextPageBtn, paged and S.page < pages)
        U.set(S.pageText, paged and ("PAGE " .. S.page .. " / " .. pages) or "")
        U.setButton(S.backBtn, S.step > 1)
        U.setButton(S.cancelBtn, editing and true or false)
        U.label(S.nextBtn, (S.step < #STEPS) and "NEXT" or (editing and "SAVE PROFILE" or "ENTER THE RANKING"))
        U.placeSel(false)
        U.paintPreview()
        if animate then U.enter(S.keyG, 0, 300, 0, 20, nil, "page") end
    end

    function U.nextStep()
        local step = STEPS[S.step]
        local d = S.draft
        if step.key == "name" then
            if #d.name < 3 then U.set(S.msg, "AT LEAST 3 CHARACTERS"); return end
            if d.name ~= cleanName(d.name) then U.set(S.msg, "ONLY LETTERS, NUMBERS, _ . -"); return end
        end
        if step.key == "discord" and not d.discord:match("^[a-z0-9_%.]*$") then
            U.set(S.msg, "ONLY a-z, 0-9, _ AND ."); return
        end
        if S.step < #STEPS then
            S.step = S.step + 1
            S.page = 0
            U.paintStep(true)
            return
        end
        d.joined = true
        if not writeProfile(d) then U.set(S.msg, "COULD NOT SAVE (FILE ERROR)"); return end
        U.profile = d
        request()
        U.B.note = "PROFILE SAVED: SENDING IT TO THE SERVER..."
        U.openBoard()
    end

    function U.openSetup()
        local p = U.profile
        S.draft = {
            name = (p and p.name ~= "") and p.name or lumenName(),
            country = (p and COUNTRY_BY[p.country]) and p.country or U.hint or "FR",
            avatar = p and p.avatar > 0 and p.avatar or AVATARS[1],
            banner = p and p.banner > 0 and p.banner or BANNERS[1],
            title = p and TITLES[p.title] and p.title or 1,
            weapon = p and p.weapon > 0 and p.weapon or WEAPONS[1],
            discord = p and p.discord or "",
        }
        if not COUNTRY_BY[S.draft.country] then S.draft.country = "FR" end
        S.step, S.page, S.selRect = 1, 0, nil
        U.show("setup", "setup")
        U.drop("page")
        U.paintStep(true)
        U.enter(S.pv, 100, 500, 80, 0, nil, "page")
    end

    -- caret of the text input
    U.animate(function(t)
        if U.page ~= "setup" or STEPS[S.step].kind ~= "keys" then return end
        local on = math.floor(t * 2) % 2 == 0
        if on ~= S.blinkOn then
            S.blinkOn = on
            U.set(S.input, (S.blinkText or "") .. (on and "_" or ""))
        end
        U.fade(S.inputLine, 0.6 + 0.4 * math.sin(t * 4))
    end)
end

-- ------------------------------------------------------------------
-- the tab
-- ------------------------------------------------------------------
local function build(menu, controller)
    pcall(math.randomseed, now())
    local root = LUI.UIElement.new(); root.id = MENU
    root:SetAnchorsAndPosition(0.5, 0.5, 0, 1, -960, 960, 0, 1080)
    local U = newUI(root, controller)

    -- background: key art under a purple tint, blue column on the left
    U.layer("back")
    U.picture(-630, 950, 110, 990, BACK_ART)
    U.box(MAIN, 0.86, -630, 950, 110, 990)
    U.box(SIDE, 0.96, -950, -640, 110, 990)
    local top = U.box(CYAN, 1, -630, 950, 110, 113)
    U.layers.back = nil            -- static: never hidden by a page switch

    U.profile = readProfile()
    U.id = myId()
    U.hint = (readText(HINT_FILE) or ""):match("^BR95WH1|(%u%u)|")
    U.board = readBoard()

    buildBoard(U)
    buildProfile(U)
    buildSetup(U)
    buildColumn(U)                 -- last: drawn over the pages

    -- my card in the column
    function U.paintMine()
        local p = U.profile
        local mine = U.board and U.board.me
        if U.board and not mine then
            for _, e in ipairs(U.board.list) do if e.id == U.id then mine = e end end
        end
        U.mine = mine
        local sr = localStats()
        if p then
            U.setPicture(U.meAvatar, itemImage(p.avatar))
            U.set(U.meName, p.name)
        else
            U.setPicture(U.meAvatar, nil)
            U.set(U.meName, "NO PROFILE YET")
        end
        if U.syncState_ == "NAMETAKEN" and p and p.joined then
            U.set(U.mePlace, "PSEUDO ALREADY TAKEN", RED)
        elseif mine and p and p.joined then
            U.set(U.mePlace, "#" .. mine.place .. " OF " .. (U.board.total or 0), CYAN)
        elseif p and p.joined then
            U.set(U.mePlace, "NOT RANKED YET", CYAN)
        else
            U.set(U.mePlace, p and "NOT IN THE RANKING" or "CREATE YOUR PROFILE", GREY)
        end
        local _, label, color = division(sr)
        U.set(U.meSR, sr .. " SR   " .. label, color)
        U.tint(U.meFrame, color)
    end

    -- sync program state in the column
    function U.paintSync()
        local st = readStatus()
        local age = st and (now() - st.time) or 99999
        local state, line1, line2, line3, color
        if not st or age > 90 then
            state, color = "OFF", RED
            line1, line2, line3 = "SYNC NOT RUNNING", "OPEN THE ARTEFACT LAUNCHER", "ONCE: IT STARTS IT"
        elseif st.state == "OFFLINE" then
            state, color = "OFFLINE", GOLD
            line1, line2, line3 = "NO INTERNET", "RETRYING...", ""
        elseif st.state == "ERROR" then
            state, color = "ERROR", RED
            line1, line2, line3 = "SYNC ERROR", st.message, ""
        else
            state, color = (st.state == "NAMETAKEN") and "NAMETAKEN" or "ONLINE", GREEN
            line1 = "ONLINE"
            line2 = U.board and ("UPDATED " .. ago(U.board.fetched)) or "WAITING FOR THE RANKING"
            line3 = st.message
        end
        U.syncState_ = state
        U.tint(U.syncDot, color)
        U.set(U.syncState, line1, color)
        U.set(U.syncInfo, line2 or "")
        U.set(U.syncHelp, line3 or "")
        U.set(U.syncHelp2, "")
    end

    function U.openBoard()
        U.drop("page")
        U.show("board", "board")
        U.refreshBoard(true)
    end
    function U.openMine()
        local p = U.profile
        if not p then U.openSetup(); return end
        if U.mine then U.openProfile(U.mine); return end
        -- not on the server yet: my own data
        local sr, matches, kills = localStats()
        U.openProfile({ id = U.id, local_ = true, name = p.name, country = p.country, sr = sr, best = sr,
            matches = matches, kills = kills, deaths = 0, wins = 0, avatar = p.avatar, banner = p.banner,
            title = p.title, weapon = p.weapon, discord = p.discord, bot = false, place = 0, updated = 0, created = 0 })
    end

    U.paintSync()
    U.paintMine()
    request()
    if U.profile and U.profile.name ~= "" then U.openBoard() else U.openSetup() end

    -- every 2 s: sync state, new ladder from the sync program
    local nextCheck = 0
    U.animate(function(t)
        U.fade(top, 0.7 + 0.3 * math.sin(t * 3))
        if t < nextCheck then return end
        nextCheck = t + 2
        U.paintSync()
        local text = readText(BOARD_FILE)
        local fetched = text and tonumber(text:match("^BR95WB1|(%d+)|"))
        if fetched and (not U.board or fetched ~= U.board.fetched) then
            U.board = readBoard()
            U.id = myId()
            U.profile = readProfile() or U.profile
            if U.page == "board" then U.refreshBoard(false) end
        elseif U.page == "board" then
            U.refreshBoard(false)
        end
        U.paintMine()
    end)

    -- one 16 ms timer for everything that moves (timed with the clock)
    local last
    root:registerEventHandler("br95_world_frame", function()
        local ms = os.clock() * 1000
        local dt = last and math.max(0, math.min(100, ms - last)) or 16
        last = ms
        U.runTweens(ms)
        for _, fn in ipairs(U.anims) do pcall(fn, ms / 1000, dt) end
    end)
    root:addElement(LUI.UITimer.new({ interval = 16, event = "br95_world_frame", disposable = false, eventTarget = root }))
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
        pcall(function() msg:setText("WORLD RANKING ERROR: " .. tostring(result)) end)
        root:addElement(msg)
        return root
    end)

    local data = MAINMENUTABS.TabData
    if not data[MENU] then
        local sound = type(data.CustomizeMenu) == "table" and data.CustomizeMenu.menuSound or nil
        data[MENU] = { menuName = MENU, name = "WORLD RANKING", menuSound = sound,
            -- shown in the ranked playlist lobby (same test as br95_ranked_official_post.lua)
            isHidden = function() return (readText(IO .. "br95_mode.txt") or ""):match("^BR95M1|(%d)") ~= "1" end,
            isDisabled = function() return false end,
            onFocusCallback = function() return true end, menuSpecificCallback = function() end }
    end

    -- same lobbies as the RANKED tab, after EVENTS (or RANKED SHOP / RANKED)
    local AFTER = { BR95RankedEventsMenu = 3, BR95RankedShopMenu = 2, BR95RankedMenu = 1 }
    for _, lobby in ipairs({ "WarzonePrivateMatchLobby", "PrivateMatchLobby", "MPSystemLinkLobby" }) do
        local layout = MAINMENUTABS.Layouts[lobby]
        if type(layout) == "table" then
            local present, after, best = false, nil, 0
            for i, entry in ipairs(layout) do
                if entry == MENU then present = true end
                if AFTER[entry] and AFTER[entry] > best then after, best = i, AFTER[entry] end
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
