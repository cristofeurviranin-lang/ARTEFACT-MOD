-- BR95 Ranked lobby card: your rank on the right of the Warzone lobby (above ADD BOTS),
-- like the official Ranked Play lobby (shield with I / II / III, RANK, division
-- banner, SR, next promotion). Uses the helpers of br95_ranked_post.lua
-- (BR95RankedMenu.shared) and the game's own images.
-- It wraps the menu type of the FIRST tab of the Warzone private match lobby;
-- what it found is written to jupiter/IO/br95_lobby_info.txt.
-- Position measured on a screenshot of the lobby (map card at x 1402..1832, ADD BOTS at y 713).
-- Wrapped in pcall; if it fails the lobby stays as it was. Fully restart the
-- game after changes.
if BR95RankedLobby then return end
local state = { installed = false }
BR95RankedLobby = state

local LOBBY = "WarzonePrivateMatchLobby"
local INFO_FILE = "jupiter/IO/br95_lobby_info.txt"
-- left, top of the card (1920 x 1080 screen), 300 x 448, centred on the map card
local CARD = { x = 1467, y = 256 }
local WHITE, GREY, BLACK = 0xFFFFFF, 0x9A9A9A, 0x000000

-- the lobby is ranked when the RESURGENCE RANKED WARZONE playlist was picked
-- (br95_ranked_playlist_post.lua writes BR95M1|1|...); no file yet = ranked
local function rankedLobby()
    local text
    pcall(function()
        local f = io.open("jupiter/IO/br95_mode.txt", "r")
        if f then text = f:read("*a"); f:close() end
    end)
    if not text then return true end
    return text:match("^BR95M1|(%d)") == "1"
end

-- playlist title above START MATCH, with the official Warzone Ranked emblem
local function addTitle(widget, shared)
    local icon = LUI.UIImage.new()
    icon:SetAnchorsAndPosition(0, 1, 0, 1, 88, 124, 723, 759)
    widget:addElement(icon)
    local ok = pcall(function() icon:setImage(RegisterMaterial("jup_icon_mode_wz_ranked"), 0) end)
    icon:SetAlpha(ok and 1 or 0, 0)
    local title = LUI.UIText.new()
    title:SetAnchorsAndPosition(0, 1, 0, 1, 132, 620, 729, 755)
    shared.font(title, 22, true)
    if title.SetAlignment and LUI.Alignment then title:SetAlignment(LUI.Alignment.Left) end
    title:SetRGB(0xFFFFFF, 0)
    title:setText("RESURGENCE RANKED WARZONE")
    widget:addElement(title)
end

local function addCard(widget)
    local shared = BR95RankedMenu and BR95RankedMenu.shared
    if not shared then return end
    if not rankedLobby() then return end
    -- the official Ranked Play pieces are shown on the PLAY tab: no card / title of ours
    if rawget(_G, "BR95RankedOfficial") then return end
    pcall(addTitle, widget, shared)
    pcall(function() BR95RankedLang.load() end)
    local L = rawget(_G, "BR95RankedLang")
    local function T(s) return (L and L.T) and L.T(s) or s end
    local RANKS = shared.RANKS
    local p = shared.readProfile()
    local i = shared.rankIndex(p.sr)
    local rank = RANKS[i]
    local list = shared.steps()
    local cur = shared.stepOf(list, p.sr)
    local nextStep = list[cur + 1]

    local card = LUI.UIElement.new(); card.id = "BR95RankedLobbyCard"
    card:SetAnchorsAndPosition(0, 1, 0, 1, CARD.x, CARD.x + 300, CARD.y, CARD.y + 448)
    widget:addElement(card)
    local LEFT = LUI.Alignment and LUI.Alignment.Left
    local function box(color, alpha, l, r, t, b)
        local el = LUI.UIImage.new()
        el:SetRGB(color, 0); el:SetAlpha(alpha, 0)
        el:SetAnchorsAndPosition(0, 1, 0, 1, l, r, t, b)
        card:addElement(el); return el
    end
    local function image(material, l, r, t, b)
        local el = LUI.UIImage.new()
        el:SetAnchorsAndPosition(0, 1, 0, 1, l, r, t, b)
        card:addElement(el)
        local ok = material ~= nil and pcall(function() el:setImage(RegisterMaterial(material), 0) end)
        el:SetAlpha(ok and 1 or 0, 0)
        return el, ok
    end
    local function text(str, size, color, l, r, t, b, align, bold)
        local el = LUI.UIText.new()
        el:SetAnchorsAndPosition(0, 1, 0, 1, l, r, t, b)
        shared.font(el, size, bold)
        if el.SetAlignment and LUI.Alignment then el:SetAlignment(align or LUI.Alignment.Center) end
        el:SetRGB(color, 0); el:setText(str)
        card:addElement(el); return el
    end
    local function srLine(value, size, color, t)
        local str = tostring(value)
        local w = math.floor(#str * size * 0.72)
        local icon = size * 0.95
        local l = 150 - (w + icon + 8) / 2
        local _, ok = image(shared.SR_ICON, l, l + icon, t + size * 0.14, t + size * 0.14 + icon * 0.89)
        text(str .. (ok and "" or " SR"), size, color, l + icon + 8, l + icon + 8 + w + 200, t, t + size + 4, LEFT, true)
    end

    -- body under the shield, tinted with the rank colour
    box(BLACK, 0.6, 0, 300, 150, 448)
    box(rank.color, 0.10, 0, 300, 150, 448)
    box(rank.color, 1, 0, 300, 446, 448)
    -- shield with the small numeral on the plate
    image(shared.shieldName(i, true), 55, 245, 0, 190)
    local tier = list[cur].tier
    if tier and i < #RANKS then
        local o, cy = 190 * 0.30, 190 * 0.58
        image(shared.tierOverlay(i, tier), 150 - o / 2, 150 + o / 2, cy - o / 2, cy + o / 2)
    end
    text(T("RANK"), 16, GREY, 0, 300, 194, 214, nil, true)
    text(shared.percentText(p.sr), 36, WHITE, 0, 300, 214, 256, nil, true)
    box(rank.color, 1, 20, 280, 264, 300)
    text(shared.stepLabel(list[cur]), 22, WHITE, 20, 280, 270, 296, nil, true)
    srLine(p.sr, 22, WHITE, 306)
    if nextStep then
        text(T("NEXT PROMOTION"), 14, GREY, 20, 280, 342, 360, nil, true)
        local pct = math.max(0, math.min(1, (p.sr - list[cur].from) / (nextStep.from - list[cur].from)))
        box(0x3A3A3A, 1, 20, 280, 366, 372)
        box(rank.color, 1, 20, 20 + math.max(1, 260 * pct), 366, 372)
        text(shared.stepLabel(nextStep) .. "  -  " .. (nextStep.from - p.sr) .. " SR", 16, WHITE, 20, 280, 380, 402, nil, true)
    else
        text(T("TOP 250"), 18, RANKS[#RANKS].color, 20, 280, 350, 376, nil, true)
    end
    -- Ranked Points
    local rp = shared.readRP and shared.readRP() or 0
    box(0xFFD27A, 0.14, 20, 280, 410, 438)
    image(shared.STAR_ICON, 92, 114, 413, 435)
    text(rp .. " RP", 20, 0xFFD27A, 118, 280, 412, 436, LEFT, true)
end

local function install()
    if state.installed then return true end
    if type(MenuBuilder) ~= "table" or type(MenuBuilder.getType) ~= "function" or type(MenuBuilder.registerType) ~= "function" then return false end
    if type(MAINMENUTABS) ~= "table" or type(MAINMENUTABS.Layouts) ~= "table" then return false end
    local layout = MAINMENUTABS.Layouts[LOBBY]
    if type(layout) ~= "table" or not layout[1] then return false end
    local first = layout[1]
    local data = type(MAINMENUTABS.TabData) == "table" and MAINMENUTABS.TabData[first]
    local menuName = (type(data) == "table" and data.menuName) or first
    local original = MenuBuilder.getType(menuName)

    local info = { "lobby " .. LOBBY, "tabs:" }
    for k, name in ipairs(layout) do
        local d = MAINMENUTABS.TabData and MAINMENUTABS.TabData[name]
        info[#info + 1] = "  " .. k .. " " .. tostring(name) .. " menu=" .. tostring(type(d) == "table" and d.menuName) .. " label=" .. tostring(type(d) == "table" and d.name)
    end
    info[#info + 1] = "wrapped=" .. tostring(menuName) .. " found=" .. tostring(type(original) == "function")
    pcall(function()
        local f = io.open(INFO_FILE, "w")
        if f then f:write(table.concat(info, "\n")); f:close() end
    end)
    if type(original) ~= "function" then return false end

    MenuBuilder.registerType(menuName, function(menu, options)
        local widget = original(menu, options)
        local ok, err = pcall(addCard, widget)
        if not ok then state.lastError = tostring(err) end
        return widget
    end)
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
