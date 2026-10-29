-- BR95 World Real: the WORLD RANKING page (opened from the Lumen main menu) with the REAL players of
-- the BR95 mod, from every country. It ranks the MULTIPLAYER LEVEL: two ladders, LEVEL (all
-- time points) and SEASON (points of the current 40-day season). The ladder comes from the ranking server through the
-- sync program (BR95Sync.exe), which writes jupiter/IO/br95_world.txt; this tab
-- only reads files. Your name is the username of jupiter/settings.json, you only
-- pick your country and press JOIN (nothing is sent before that) or LEAVE.
--   br95_world.txt          BR95W3|season|total|myPlace|seasonEnds|fetched|seasonTotal|mySeasonPlace
--                           P|rank|name|CC|sr|matches|level (level ladder), Q|... same (season ladder)
--   br95_world_status.txt   BR95X1|state|message|time|END     (written by the sync program)
--   br95_world_profile.txt  BR95F1|CC|enabled|consent|END     (written by this tab)
-- Same tab mechanism as br95_ranked_shop_post.lua; wrapped in pcall, a failure just
-- means no tab. Fully restart the game after changes.
if BR95WorldReal then return end
local state = { installed = false }
BR95WorldReal = state

local PROFILE_FILE = "jupiter/IO/br95_mp_ranked.txt"   -- BR95R1|sr|matches|kills|level|last|END
local STREAK_FILE = "jupiter/IO/br95_mp_streak.txt"    -- BR95W1|streak|best|END
local WORLD_FILE = "jupiter/IO/br95_world.txt"
local STATUS_FILE = "jupiter/IO/br95_world_status.txt"
local JOIN_FILE = "jupiter/IO/br95_world_profile.txt"
local SETTINGS_JSON = "jupiter/settings.json"
local MENU = "BR95WorldRealMenu"

local PAGE_SIZE = 10

-- code, name (the code is what the ranking shows)
local COUNTRIES = {
    { "FR", "FRANCE" }, { "BE", "BELGIUM" }, { "CH", "SWITZERLAND" }, { "CA", "CANADA" }, { "US", "UNITED STATES" },
    { "GB", "UNITED KINGDOM" }, { "DE", "GERMANY" }, { "ES", "SPAIN" }, { "IT", "ITALY" }, { "PT", "PORTUGAL" },
    { "NL", "NETHERLANDS" }, { "LU", "LUXEMBOURG" }, { "IE", "IRELAND" }, { "AT", "AUSTRIA" }, { "PL", "POLAND" },
    { "CZ", "CZECHIA" }, { "RO", "ROMANIA" }, { "GR", "GREECE" }, { "HU", "HUNGARY" }, { "SE", "SWEDEN" },
    { "NO", "NORWAY" }, { "DK", "DENMARK" }, { "FI", "FINLAND" }, { "RU", "RUSSIA" }, { "UA", "UKRAINE" },
    { "TR", "TURKEY" }, { "MA", "MOROCCO" }, { "DZ", "ALGERIA" }, { "TN", "TUNISIA" }, { "EG", "EGYPT" },
    { "SN", "SENEGAL" }, { "CI", "IVORY COAST" }, { "CM", "CAMEROON" }, { "NG", "NIGERIA" }, { "ZA", "SOUTH AFRICA" },
    { "BR", "BRAZIL" }, { "AR", "ARGENTINA" }, { "MX", "MEXICO" }, { "CL", "CHILE" }, { "CO", "COLOMBIA" },
    { "SA", "SAUDI ARABIA" }, { "AE", "UAE" }, { "IN", "INDIA" }, { "ID", "INDONESIA" }, { "PH", "PHILIPPINES" },
    { "VN", "VIETNAM" }, { "TH", "THAILAND" }, { "JP", "JAPAN" }, { "KR", "SOUTH KOREA" }, { "CN", "CHINA" },
    { "AU", "AUSTRALIA" }, { "NZ", "NEW ZEALAND" },
}

-- names and colours of the multiplayer level, a new one every 100 levels
-- (same as the LEVEL tab); "from" is the first level of the tier
local RANKS = {
    { name = "ROOKIE",     from = 0,    color = 0xD9262E },
    { name = "SILVER",     from = 100,  color = 0xC8C8C8 },
    { name = "PLATINUM",   from = 200,  color = 0x7FE0D6 },
    { name = "DIAMOND",    from = 300,  color = 0x4FA3FF },
    { name = "CRIMSON",    from = 400,  color = 0xDC143C },
    { name = "IRIDESCENT", from = 500,  color = 0xC77DFF },
    { name = "PAINITE",    from = 600,  color = 0xFF4D5E },
    { name = "GOLD",       from = 700,  color = 0xFFC93C },
    { name = "EMERALD",    from = 800,  color = 0x2ECC71 },
    { name = "RUBY",       from = 900,  color = 0xE0245E },
    { name = "PRISMATIC",  from = 1000, color = 0xFF7AD9 },
}
local WHITE, SOFT, LINE, CARD, BG = 0xFFFFFF, 0x9FB3C8, 0x1C2A38, 0x101820, 0x080C12
local CYAN, GREEN, RED, AMBER = 0x35C8FF, 0x6BD66B, 0xE04040, 0xFFB020

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

-- level 1..1000: going from level L to L + 1 costs 100 + L points (same as the game)
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

local function rankIndex(level)
    return math.min(#RANKS, math.floor(level / 100) + 1)
end

-- label and colour of a level: "LV 53", "LV 153  SILVER"
local function rankOf(level)
    local rank = RANKS[rankIndex(level)]
    local label = "LV " .. level
    if level >= 100 then label = label .. "  " .. rank.name end
    return label, rank.color
end

-- the level of a ladder row (the server sends it, else it comes from the points)
local function entryLevel(entry)
    return entry.level or levelOf(entry.sr)
end
local function readMine()
    local p = { sr = 0, matches = 0, kills = 0, best = 0, last = 0 }
    local text = readText(PROFILE_FILE)
    if text then
        local sr, matches, kills, best, last = text:match("^BR95R1|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|")
        if sr then
            p.sr, p.matches, p.kills = tonumber(sr) or 0, tonumber(matches) or 0, tonumber(kills) or 0
            p.best, p.last = tonumber(best) or 0, tonumber(last) or 0
        end
    end
    return p
end

local function readStreak()
    local text = readText(STREAK_FILE)
    local streak, best = 0, 0
    if text then
        local a, b = text:match("^BR95W1|(%d+)|(%d+)|END")
        streak, best = tonumber(a) or 0, tonumber(b) or 0
    end
    return streak, best
end

local function readUsername()
    local text = readText(SETTINGS_JSON)
    local name = text and text:match('"username"%s*:%s*"([^"]+)"')
    return name or ""
end

local function readJoin()
    local text = readText(JOIN_FILE)
    local country, enabled, consent = "", false, false
    if text then
        local c, e, k = text:match("^BR95F1|(%u*)|(%d)|(%d)|END")
        if c then country, enabled, consent = c, e == "1", k == "1" end
    end
    return country, enabled, consent
end

local function writeJoin(country, enabled)
    return writeText(JOIN_FILE, "BR95F1|" .. country .. "|" .. (enabled and "1" or "0") .. "|1|END")
end

-- country of the Windows region, written by the sync program: it only pre-selects
-- the country, nothing is sent before the player presses the button
local function readHint()
    local text = readText("jupiter/IO/br95_world_hint.txt")
    return text and text:match("^BR95H2|(%u%u)|END") or ""
end

local function readStatus()
    local text = readText(STATUS_FILE)
    if not text then return nil end
    local stateName, message, stamp = text:match("^BR95X1|(%u+)|([^|]*)|(%d+)|END")
    if not stateName then return nil end
    return { state = stateName, message = message, age = os.time() - (tonumber(stamp) or 0) }
end

local function readWorld()
    local text = readText(WORLD_FILE)
    if not text then return nil end
    local season, total, place, ends, fetched, seasonTotal, seasonPlace =
        text:match("^BR95W3|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)")
    if not season then return nil end
    local rows, seasonRows = {}, {}
    for rank, name, country, sr, matches, level in text:gmatch("\nP|(%d+)|([^|\n]*)|(%u%u)|(%d+)|(%d+)|(%d+)") do
        rows[#rows + 1] = { place = tonumber(rank), name = name, country = country, sr = tonumber(sr), matches = tonumber(matches), level = tonumber(level) }
    end
    for rank, name, country, sr, matches, level in text:gmatch("\nQ|(%d+)|([^|\n]*)|(%u%u)|(%d+)|(%d+)|(%d+)") do
        seasonRows[#seasonRows + 1] = { place = tonumber(rank), name = name, country = country, sr = tonumber(sr), matches = tonumber(matches), level = tonumber(level) }
    end
    return { season = tonumber(season), total = tonumber(total), place = tonumber(place), ends = tonumber(ends),
        fetched = tonumber(fetched), rows = rows, seasonRows = seasonRows,
        seasonTotal = tonumber(seasonTotal), seasonPlace = tonumber(seasonPlace) }
end
-- ------------------------------------------------------------------
-- menu
-- ------------------------------------------------------------------

local function font(text, size, bold)
    if FONTS and FONTS.GetFont then
        local f = bold and FONTS.PrimaryBold or FONTS.SecondaryRegular
        if f and f.File then pcall(text.SetFont, text, FONTS.GetFont(f.File)) end
    end
    if text.SetFontSize then pcall(text.SetFontSize, text, size) end
end

-- points of the current 40-day season earned by this player (BR95S2|season|sr|END)
local SEASON_EPOCH = 1792613644
local SEASON_LENGTH = 40 * 86400
local function readSeasonSR()
    local text = readText("jupiter/IO/br95_mp_season.txt")
    local number, sr
    if text then number, sr = text:match("^BR95S2|(%d+)|(%d+)|END") end
    local now = math.max(1, math.floor((os.time() - SEASON_EPOCH) / SEASON_LENGTH) + 1)
    if tonumber(number) == now then return tonumber(sr) or 0 end
    return 0
end

-- ------------------------------------------------------------------
-- 10 bots in the ladder (country "BOT"), made up and always the same for a season:
-- they start at fixed levels and earn points after each of your matches
-- ------------------------------------------------------------------
local BOT_COUNT = 10
local BOT_LEVELS = { 12, 28, 41, 55, 68, 83, 97, 115, 140, 180 }
local BOT_ADJ = { "Toxic", "Silent", "Rapid", "Neon", "Frozen", "Savage", "Lucky", "Hollow", "Static", "Rogue" }
local BOT_NOUN = { "Wolf", "Viper", "Pixel", "Ghost", "Nomad", "Falcon", "Reaper", "Cobra", "Titan", "Echo" }

local function botHash(a, b, c)
    return ((a * 7919 + b * 104729 + c * 31337 + 12345) * 48271) % 2147483647
end

local function botList(matches, season)
    local list = {}
    for n = 1, BOT_COUNT do
        local gained = 0
        for m = 1, math.min(matches, 300) do gained = gained + botHash(n, m, season) % (60 + n * 10) end
        local base = needFor(BOT_LEVELS[n]) + botHash(n, season, 3) % 200
        list[#list + 1] = {
            name = BOT_ADJ[(n * 3 + season) % #BOT_ADJ + 1] .. BOT_NOUN[(n * 7 + season) % #BOT_NOUN + 1],
            sr = base + gained,
            seasonSr = math.floor(gained * 0.6) + botHash(n, season, 9) % 400,
            matches = matches + 20 + n * 7,
            bot = true,
        }
    end
    return list
end

-- the real ladder and the bots, sorted, with new places
local function withBots(list, isSeason, matches, season)
    local merged = {}
    for _, entry in ipairs(list) do merged[#merged + 1] = entry end
    for _, bot in ipairs(botList(matches, season)) do
        merged[#merged + 1] = { name = bot.name, country = "BOT", sr = isSeason and bot.seasonSr or bot.sr,
            matches = bot.matches, level = levelOf(bot.sr), bot = true }
    end
    table.sort(merged, function(a, b)
        if a.sr ~= b.sr then return a.sr > b.sr end
        return a.name < b.name
    end)
    for k, entry in ipairs(merged) do entry.place = k end
    return merged
end
local ACCENT, ACCENT_TEXT = 0xD9262E, 0xFF5560           -- red theme
local GOLD, BLUE, BRONZE = 0xFFC93C, 0x4FA3FF, 0xCD7F32   -- places 1, 2, 3
local PODIUM = { GOLD, BLUE, BRONZE }

local function build(menu, controller, onBack)
    local root = LUI.UIElement.new(); root.id = MENU
    if onBack then
        root:SetAnchorsAndPosition(0, 1, 0, 1, 0, 1920, 0, 1080)               -- page of the main menu
    else
        root:SetAnchorsAndPosition(0.5, 0.5, 0, 1, -960, 960, 0, 1080)         -- tab of the lobby
    end
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
    local function button(l, r, t, b, label, action)
        local btn = MenuBuilder.BuildRegisteredType("GenericButton", { controllerIndex = controller })
        btn:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        root:addElement(btn)
        if btn.Text then pcall(btn.Text.setText, btn.Text, label) end
        btn:addEventHandler("button_action", function() pcall(action) end)
        return btn
    end
    local function set(element, str, color)
        if not element then return end
        pcall(element.setText, element, str)
        if color then pcall(element.SetRGB, element, color, 0) end
    end
    local function alpha(element, value)
        if element then pcall(element.SetAlpha, element, value, 0) end
    end
    local function tint(element, color)
        if element then pcall(element.SetRGB, element, color, 0) end
    end

    local mine = readMine()
    local streak, bestStreak = readStreak()
    local myName = readUsername()
    local country, enabled = readJoin()
    local countryIndex = 1
    local preselect = country ~= "" and country or readHint()
    for k, c in ipairs(COUNTRIES) do if c[1] == preselect then countryIndex = k end end
    local savedIndex = (country ~= "") and countryIndex or nil      -- the confirmed country
    local world, rows = nil, {}
    local ladders = { level = {}, season = {} }
    local countryOverride = nil      -- the country just confirmed, shown before the server answers
    local board = "level"            -- "level" (all time points) or "season"
    local page = 1
    local pages = 1

    -- background
    box(BG, onBack and 1 or 0.94, -800, 800, 110, 990)
    box(ACCENT, 1, -800, -794, 110, 990)
    box(ACCENT, 1, -800, 800, 110, 113)
    if onBack then
        -- opened over the main menu: its buttons are under the left part of this page.
        -- An almost invisible button over them takes the clicks instead
        local blocker = button(-735, -390, 385, 845, "", function() end)
        alpha(blocker, 0.02)
    end
    text("WORLD RANKING", 54, WHITE, -770, 300, 118, 176, LEFT, true)
    local subtitle = text("", 17, SOFT, -770, 230, 176, 198, LEFT)

    -- podium: #2 | #1 | #3 (blue, gold, bronze)
    local cards = {}
    local function podiumCard(l, r, t, accent)
        local card = { accent = accent }
        box(CARD, 1, l, r, t, 396)
        box(accent, 1, l, r, t, t + 5)
        card.place = text("", 46, accent, l + 18, l + 112, t + 10, t + 68, LEFT, true)
        card.chipBox = box(LINE, 0, l + 122, l + 170, t + 24, t + 48)
        card.chip = text("", 15, WHITE, l + 122, l + 170, t + 27, t + 47, CENTER, true)
        card.rank = text("", 17, WHITE, l + 180, r - 12, t + 25, t + 49, LEFT, true)
        card.name = text("", 22, WHITE, l + 18, r - 12, t + 74, t + 106, LEFT, true)
        card.sr = text("", 22, WHITE, l + 18, r - 120, t + 110, t + 140, LEFT, true)
        card.matches = text("", 14, SOFT, r - 130, r - 12, t + 118, t + 140, RIGHT)
        return card
    end
    cards[2] = podiumCard(-770, -450, 240, BLUE)
    cards[1] = podiumCard(-430, -110, 214, GOLD)
    cards[3] = podiumCard(-90, 230, 240, BRONZE)

    -- table (paged)
    text("#", 15, SOFT, -762, -690, 410, 432, LEFT)
    text("PLAYER", 15, SOFT, -610, -330, 410, 432, LEFT)
    text("MP LEVEL", 15, SOFT, -320, -80, 410, 432, LEFT)
    text("MATCHES", 15, SOFT, -90, 30, 410, 432, RIGHT)
    local srHeader = text("SR", 15, SOFT, 40, 220, 410, 432, RIGHT)
    box(LINE, 1, -770, 230, 434, 436)

    local tableRows = {}
    for k = 1, PAGE_SIZE do
        local t = 440 + (k - 1) * 44
        local row = {}
        row.bg = box(CARD, 1, -770, 230, t, t + 40)
        row.mark = box(ACCENT, 0, -770, -765, t, t + 40)
        row.place = text("", 22, WHITE, -756, -690, t + 6, t + 36, LEFT, true)
        row.chipBox = box(LINE, 0, -680, -628, t + 9, t + 31)
        row.chip = text("", 14, WHITE, -680, -628, t + 10, t + 30, CENTER, true)
        row.name = text("", 22, WHITE, -614, -330, t + 6, t + 36, LEFT, true)
        row.rank = text("", 18, WHITE, -320, -80, t + 9, t + 35, LEFT, true)
        row.matches = text("", 18, SOFT, -90, 30, t + 9, t + 35, RIGHT, true)
        row.sr = text("", 22, WHITE, 40, 220, t + 6, t + 36, RIGHT, true)
        tableRows[k] = row
    end
    local emptyText = text("", 22, SOFT, -740, 200, 600, 700, CENTER, true)
    local pageText = text("", 18, WHITE, -520, -200, 906, 936, CENTER, true)

    -- your profile (right)
    box(CARD, 1, 270, 770, 214, 480)
    box(ACCENT, 1, 270, 770, 214, 219)
    text("YOUR PROFILE", 16, SOFT, 292, 760, 226, 248, LEFT)
    local nameText = text("", 26, WHITE, 292, 760, 250, 286, LEFT, true)
    local flagText = text("", 18, SOFT, 360, 700, 304, 340, LEFT, true)
    local statusText = text("", 16, SOFT, 292, 760, 392, 416, LEFT, true)
    local noticeText = text("", 12, SOFT, 292, 760, 448, 472, LEFT)

    -- your places: level ladder and season ladder side by side
    box(CARD, 1, 270, 770, 496, 644)
    local standingBar = box(ACCENT, 1, 270, 770, 496, 501)
    box(LINE, 1, 519, 520, 510, 600)
    text("LEVEL LADDER", 15, SOFT, 292, 510, 508, 530, LEFT)
    local levelPlace = text("", 46, ACCENT_TEXT, 292, 510, 528, 584, LEFT, true)
    local levelOfText = text("", 15, SOFT, 292, 510, 584, 606, LEFT)
    text("SEASON LADDER", 15, SOFT, 540, 760, 508, 530, LEFT)
    local seasonPlace = text("", 46, ACCENT_TEXT, 540, 760, 528, 584, LEFT, true)
    local seasonOfText = text("", 15, SOFT, 540, 760, 584, 606, LEFT)
    local infoText = text("", 14, SOFT, 292, 760, 612, 634, LEFT)
    box(LINE, 1, 270, 770, 638, 644)
    local progressFill = box(ACCENT, 1, 270, 271, 638, 644)

    -- spread of the ladder by colour
    box(CARD, 1, 270, 770, 656, 942)
    box(LINE, 1, 270, 770, 656, 661)
    local spreadTitle = text("", 15, SOFT, 292, 760, 666, 688, LEFT)
    local spread = {}
    for k = #RANKS, 1, -1 do
        local t = 694 + (#RANKS - k) * 22
        local entry = { index = k, t = t, label = RANKS[k].from .. "+  " .. RANKS[k].name }
        entry.name = text(entry.label, 14, SOFT, 292, 440, t + 1, t + 21, LEFT)
        box(LINE, 1, 450, 690, t + 4, t + 18)
        entry.bar = box(RANKS[k].color, 1, 450, 453, t + 4, t + 18)
        entry.count = text("", 14, WHITE, 700, 756, t + 1, t + 21, RIGHT, true)
        spread[#spread + 1] = entry
    end

    local joinButton, boardButton
    local function showProfile()
        set(nameText, myName ~= "" and myName or "NO USERNAME FOUND", myName ~= "" and WHITE or ACCENT_TEXT)
        local c = COUNTRIES[countryIndex]
        set(flagText, c[1] .. "   " .. c[2] .. ((enabled and savedIndex ~= countryIndex) and "   (NOT CONFIRMED)" or ""),
            (enabled and savedIndex ~= countryIndex) and AMBER or WHITE)
        if joinButton and joinButton.Text then
            pcall(joinButton.Text.setText, joinButton.Text,
                (not enabled) and ("ENTER THE RANKING AS " .. c[1])
                or ((savedIndex == countryIndex) and "COUNTRY CONFIRMED" or ("CONFIRM COUNTRY: " .. c[1])))
        end
        local status = readStatus()
        if not enabled then
            set(statusText, "NOT IN THE RANKING YET: NOTHING IS SENT.", AMBER)
        elseif not status or status.age > 180 then
            set(statusText, "SYNC PROGRAM NOT RUNNING: IT STARTS WITH THE GAME, RESTART THE GAME.", ACCENT_TEXT)
        elseif status.state == "OK" then
            set(statusText, "IN THE RANKING: " .. status.message:upper(), GREEN)
        elseif status.state == "OFF" then
            set(statusText, "NO SERVER SET YET IN THE SYNC PROGRAM.", AMBER)
        else
            set(statusText, status.state .. ": " .. status.message:upper(), AMBER)
        end
        set(noticeText, enabled and "SENT: NAME, COUNTRY, LEVEL, SR, MATCHES, KILLS. CHANGE YOUR COUNTRY WITH THE ARROWS, THEN CONFIRM IT."
            or "JOINING SHARES: NAME, COUNTRY, LEVEL, SR, MATCHES, KILLS. YOU CANNOT LEAVE AFTERWARDS.", SOFT)
    end

    local function mineRow(entry)
        return myName ~= "" and entry.name:lower() == myName:lower()
    end

    local function showPodium()
        for k = 1, 3 do
            local card, entry = cards[k], rows[k]
            if entry then
                local label, color = rankOf(entryLevel(entry))
                set(card.place, "#" .. entry.place, card.accent)
                set(card.name, entry.name, mineRow(entry) and ACCENT_TEXT or WHITE)
                alpha(card.chipBox, 1)
                set(card.chip, entry.country)
                set(card.rank, label, color)
                set(card.sr, entry.sr .. ((board == "season") and " SEASON SR" or " SR"), WHITE)
                set(card.matches, entry.matches .. " MATCHES", SOFT)
            else
                set(card.place, "#" .. k, card.accent); set(card.name, "-", SOFT); alpha(card.chipBox, 0)
                set(card.chip, ""); set(card.rank, ""); set(card.sr, ""); set(card.matches, "")
            end
        end
    end

    local function showPage()
        for k, row in ipairs(tableRows) do
            local entry = rows[(page - 1) * PAGE_SIZE + k]
            if entry then
                local label, color = rankOf(entryLevel(entry))
                local me = mineRow(entry)
                local medal = PODIUM[entry.place]
                tint(row.bg, me and 0x3A1218 or CARD)
                tint(row.mark, me and ACCENT or (medal or ACCENT))
                alpha(row.mark, (me or medal) and 1 or 0)
                set(row.place, tostring(entry.place), medal or (me and ACCENT_TEXT or WHITE))
                alpha(row.chipBox, 1)
                set(row.chip, entry.country)
                set(row.name, entry.name, me and ACCENT_TEXT or WHITE)
                set(row.rank, label, color)
                set(row.matches, tostring(entry.matches))
                set(row.sr, tostring(entry.sr), me and ACCENT_TEXT or WHITE)
            else
                tint(row.bg, CARD)
                alpha(row.mark, 0); alpha(row.chipBox, 0)
                for _, field in ipairs({ row.place, row.chip, row.name, row.rank, row.matches, row.sr }) do set(field, "") end
            end
        end
        set(pageText, "PAGE " .. page .. " / " .. pages)
    end

    -- my place in a ladder with the bots: found in the list, else the server place plus the bots ahead of me
    local function ladderPlace(name, serverPlace)
        for _, entry in ipairs(ladders[name]) do
            if mineRow(entry) then return entry.place end
        end
        if not serverPlace or serverPlace <= 0 then return nil end
        local mySr = (name == "season") and readSeasonSR() or mine.sr
        local ahead = 0
        for _, entry in ipairs(ladders[name]) do
            if entry.bot and entry.sr > mySr then ahead = ahead + 1 end
        end
        return serverPlace + ahead
    end

    local function showStanding()
        local myLevel = levelOf(mine.sr)
        local label, color = rankOf(myLevel)
        tint(standingBar, color)
        local function place(element, ofElement, p, total, noText)
            if p and p > 0 and enabled then
                set(element, "#" .. p, PODIUM[p] or ACCENT_TEXT)
                set(ofElement, "OF " .. (total or "?") .. " PLAYERS", SOFT)
            else
                set(element, "-", SOFT)
                set(ofElement, enabled and noText or "JOIN TO GET A PLACE", SOFT)
            end
        end
        place(levelPlace, levelOfText, world and ladderPlace("level", world.place), world and (world.total + BOT_COUNT), "PLAY A MULTIPLAYER MATCH")
        place(seasonPlace, seasonOfText, world and ladderPlace("season", world.seasonPlace), world and (world.seasonTotal + BOT_COUNT), "NO POINTS THIS SEASON YET")

        local nextAt = needFor(myLevel + 1)
        local pct = (myLevel >= 1000) and 1 or math.max(0, math.min(1, (mine.sr - needFor(myLevel)) / (nextAt - needFor(myLevel))))
        pcall(progressFill.SetAnchorsAndPosition, progressFill, 0.5, 0.5, 0, 1, 270, 270 + math.max(1, math.floor(500 * pct)), 638, 644)
        tint(progressFill, color)
        set(infoText, label .. "   |   " .. mine.sr .. " SR   |   SEASON " .. readSeasonSR() .. " SR   |   STREAK " .. streak
            .. ((myLevel >= 1000) and "" or ("   |   " .. (nextAt - mine.sr) .. " TO LEVEL " .. (myLevel + 1))), SOFT)

        local counts, most = {}, 1
        for k = 1, #RANKS do counts[k] = 0 end
        for _, entry in ipairs(rows) do
            local index = rankIndex(entryLevel(entry))
            counts[index] = counts[index] + 1
        end
        for k = 1, #RANKS do if counts[k] > most then most = counts[k] end end
        local mineIndex = rankIndex(myLevel)
        for _, entry in ipairs(spread) do
            pcall(entry.bar.SetAnchorsAndPosition, entry.bar, 0.5, 0.5, 0, 1, 450,
                450 + math.max(3, math.floor(240 * counts[entry.index] / most)), entry.t + 4, entry.t + 18)
            set(entry.count, tostring(counts[entry.index]))
            set(entry.name, entry.label, entry.index == mineIndex and ACCENT_TEXT or SOFT)
        end
        set(spreadTitle, "COLOURS OF THE TOP " .. #rows .. " PLAYERS")
    end

    local function applyOverride()
        if not countryOverride then return end
        for _, list in pairs(ladders) do
            for _, entry in ipairs(list) do
                if not entry.bot and mineRow(entry) then entry.country = countryOverride end
            end
        end
    end

    local function reload()
        world = readWorld()
        if world then
            ladders.level = withBots(world.rows, false, mine.matches, world.season)
            ladders.season = withBots(world.seasonRows, true, mine.matches, world.season)
        else
            ladders = { level = {}, season = {} }
        end
        applyOverride()
        rows = ladders[board]
        pages = math.max(1, math.ceil(#rows / PAGE_SIZE))
        if page > pages then page = pages end
        if world then
            local left = math.max(0, world.ends - os.time())
            set(subtitle, ((board == "season") and "SEASON LADDER" or "LEVEL LADDER") .. "  |  SEASON " .. world.season .. "  |  "
                .. (((board == "season") and world.seasonTotal or world.total) + BOT_COUNT) .. " PLAYERS (" .. BOT_COUNT .. " BOTS)  |  SEASON ENDS IN "
                .. math.floor(left / 86400) .. "D " .. math.floor((left % 86400) / 3600) .. "H")
            set(emptyText, #rows == 0 and ((board == "season") and "NOBODY HAS POINTS THIS SEASON YET.\nPLAY A MULTIPLAYER MATCH."
                or "NOBODY IN THE RANKING YET.\nBE THE FIRST: PICK YOUR COUNTRY AND JOIN.") or "")
        else
            set(subtitle, "NO LADDER DOWNLOADED YET")
            local status = readStatus()
            set(emptyText, "NO DATA YET.\nTHE SYNC PROGRAM (BR95SYNC.EXE) DOWNLOADS THE LADDER." ..
                ((status and ("\n" .. status.state .. ": " .. status.message:upper())) or ""), AMBER)
        end
        set(srHeader, (board == "season") and "SEASON SR" or "SR")
        if boardButton and boardButton.Text then
            pcall(boardButton.Text.setText, boardButton.Text, (board == "season") and "LADDER: SEASON" or "LADDER: LEVEL")
        end
        showPodium(); showPage(); showStanding(); showProfile()
    end

    -- country selector (the only thing you can change once you are in) and join
    local function moveCountry(delta)
        countryIndex = ((countryIndex - 1 + delta) % #COUNTRIES) + 1      -- only saved when you confirm
        showProfile()
    end
    -- the arrows are written over empty buttons (a label is small and off-center in a narrow one)
    button(292, 352, 298, 344, "", function() moveCountry(-1) end)
    text("<", 34, WHITE, 292, 352, 300, 342, CENTER, true)
    button(704, 760, 298, 344, "", function() moveCountry(1) end)
    text(">", 34, WHITE, 704, 760, 300, 342, CENTER, true)
    joinButton = button(292, 760, 346, 388, "", function()
        if enabled and savedIndex == countryIndex then return end      -- nothing to confirm
        if not writeJoin(COUNTRIES[countryIndex][1], true) then
            set(statusText, "COULD NOT SAVE YOUR CHOICE.", ACCENT_TEXT)
            return
        end
        enabled = true
        savedIndex = countryIndex
        countryOverride = COUNTRIES[countryIndex][1]
        applyOverride()
        showPodium(); showPage()
        showProfile(); showStanding()
    end)
    text("COUNTRY", 12, SOFT, 360, 700, 292, 306, LEFT)

    -- page navigation
    local function move(delta)
        return function()
            page = ((page - 1 + delta) % pages) + 1
            showPage()
        end
    end
    button(-770, -690, 898, 942, "-10", move(-10))
    button(-680, -550, 898, 942, "PREV", move(-1))
    button(-190, -60, 898, 942, "NEXT", move(1))
    button(-50, 30, 898, 942, "+10", move(10))
    button(40, 230, 898, 942, "FIND ME", function()
        for _, entry in ipairs(rows) do
            if mineRow(entry) then page = math.ceil(entry.place / PAGE_SIZE); showPage(); return end
        end
        local p = world and ladderPlace(board, (board == "season") and world.seasonPlace or world.place)
        if p and p > 0 then page = math.min(pages, math.ceil(p / PAGE_SIZE)); showPage() end
    end)
    -- header buttons
    boardButton = button(270, 440, 124, 172, "LADDER: LEVEL", function()
        board = (board == "level") and "season" or "level"
        page = 1
        reload()
    end)
    button(450, 620, 124, 172, "REFRESH", function() mine = readMine(); reload() end)

    -- opened from the Lumen main menu: a BACK button and a reload hook for the caller
    if onBack then button(640, 790, 124, 172, "BACK", onBack) end
    root.br95Reload = function() mine = readMine(); reload() end

    reload()
    return root
end

state.build = build

local function install()
    if state.installed then return true end
    -- also opened from the Lumen main menu (br95_main_post.lua); here: a tab of the multiplayer lobbies
    if type(MenuBuilder) ~= "table" or type(MenuBuilder.registerType) ~= "function" then return false end
    if type(MAINMENUTABS) ~= "table" or type(MAINMENUTABS.TabData) ~= "table" or type(MAINMENUTABS.Layouts) ~= "table" then return false end

    MenuBuilder.registerType(MENU, function(menu, options)
        local controller = type(options) == "table" and options.controllerIndex or 0
        return build(menu, controller)
    end)

    local data = MAINMENUTABS.TabData
    if not data[MENU] then
        local sound = type(data.CustomizeMenu) == "table" and data.CustomizeMenu.menuSound or nil
        data[MENU] = { menuName = MENU, name = "WORLD RANKING", menuSound = sound,
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
    if DebugPrint then pcall(DebugPrint, "[BR95World] world ranking tab installed") end
    return true
end

local function tryInstall()
    local ok, err = pcall(install)
    if not ok then
        state.error = tostring(err)
        if DebugPrint then pcall(DebugPrint, "[BR95Ranked] world ranking error: " .. state.error) end
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
