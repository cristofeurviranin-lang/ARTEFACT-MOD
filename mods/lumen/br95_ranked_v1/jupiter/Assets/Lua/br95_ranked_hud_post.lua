-- BR95 Ranked HUD (V2): small tracker during the match (left, under the minimap)
-- with the official shield, the current SR (official SR logo), the SR won or
-- lost in this match and the bar of the current step; then the result screen
-- back in the menu. It also writes the match history used by the RANKED tab.
-- Data: jupiter/IO/br95_ranked_live.txt written by br95_ranked.gscc
--   BR95L1|sr_now|kills|deaths|delta|active|END
-- Attach / hide logic copied from the working XP bar mod
-- (yellow_player_xp_post.lua). Fully restart the game after changes.
if BR95RankedHUD then return end
local state = { enabled = true }
BR95RankedHUD = state

local LIVE_FILE = "jupiter/IO/br95_ranked_live.txt"

-- texts in the chosen language (br95_ranked_lang_post.lua); English without it
local function T(s, ...)
    local L = rawget(_G, "BR95RankedLang")
    if L and L.T then return L.T(s, ...) end
    if select("#", ...) > 0 then return string.format(s, ...) end
    return s
end
local function loadLang() pcall(function() BR95RankedLang.load() end) end
-- official divisions, must match br95_ranked.gsc (v11)
local RANKS = {
    { name = "BRONZE",     start = 0,     color = 0xCD7F32, icon = "bronze" },
    { name = "SILVER",     start = 1000,  color = 0xC8C8C8, icon = "silver" },
    { name = "GOLD",       start = 2000,  color = 0xE8C05A, icon = "gold" },
    { name = "PLATINUM",   start = 3500,  color = 0x5FE0C8, icon = "platinum" },
    { name = "DIAMOND",    start = 5000,  color = 0x4FA3FF, icon = "diamond" },
    { name = "CRIMSON",    start = 8000,  color = 0xE0303A, icon = "crimson" },
    { name = "IRIDESCENT", start = 12000, color = 0xC77DFF, icon = "iridescent" },
    { name = "TOP 250",    start = 17000, color = 0xF2C14E, icon = "top250" },
}
local ROMAN = { "I", "II", "III" }
local WHITE, GREY, GREEN, RED, BLACK, RPC = 0xFFFFFF, 0x9A9A9A, 0x6BD66B, 0xE04040, 0x000000, 0xFFD27A
local SR_ICON = "iw9_ui_icon_leagueplay_skill_rating"
local STAR_ICON = "iw9_ui_icon_leagueplay_star_filled"
local HIDE_CONDITIONS = { "HideHud", "PrematchPeriod", "MatchCountdown", "IsPlayerDead", "InKillCam",
    "IsMenuOpen", "InScoreboard", "IsTacMapOpen", "IsBRTacMapOpen", "IsOverlayActive",
    "ConnectingToKillstreak", "UsingRemoteKillstreak", "UsingCruiseMissile", "UsingRemoteTurret",
    "InKillstreakOverlays" }

local function readLive()
    local live
    pcall(function()
        local f = io.open(LIVE_FILE, "r")
        if not f then return end
        local text = f:read("*a"); f:close()
        local sr, k, d, delta, active = text:match("^BR95L1|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%d+)|END")
        if sr then
            live = { sr = tonumber(sr), kills = tonumber(k), deaths = tonumber(d), delta = tonumber(delta), active = tonumber(active) }
        end
    end)
    return live
end

local function rankIndex(sr)
    local index = 1
    for i, r in ipairs(RANKS) do if sr >= r.start then index = i end end
    return index
end

local function tierOf(sr)
    local i = rankIndex(sr)
    if i == #RANKS then return nil end
    local size = (RANKS[i + 1].start - RANKS[i].start) / 3
    return math.min(2, math.floor((sr - RANKS[i].start) / size))
end

local function rankLabel(sr)
    local i = rankIndex(sr)
    local tier = tierOf(sr)
    return T(RANKS[i].name) .. (tier and ("  " .. ROMAN[tier + 1]) or "")
end

-- range of the current step (I / II / III); nil in Top 250
local function divisionRange(sr)
    local i = rankIndex(sr)
    if i == #RANKS then return nil end
    local size = (RANKS[i + 1].start - RANKS[i].start) / 3
    local tier = tierOf(sr)
    return math.floor(RANKS[i].start + tier * size), math.floor(RANKS[i].start + (tier + 1) * size)
end

local function tierIndex(sr)
    local i = rankIndex(sr)
    return i * 3 + (tierOf(sr) or 0)
end

local function newText(parent, size, bold, l, r, t, b, align)
    local child = LUI.UIText.new()
    if FONTS and FONTS.GetFont then
        local f = bold and FONTS.PrimaryBold or FONTS.SecondaryRegular
        if f and f.File then pcall(child.SetFont, child, FONTS.GetFont(f.File)) end
    end
    pcall(child.SetFontSize, child, size)
    if child.SetAlignment and LUI.Alignment then child:SetAlignment(align or LUI.Alignment.Left) end
    child:SetAnchorsAndPosition(0, 1, 0, 1, l, r, t, b)
    parent:addElement(child)
    return child
end

local function newBox(parent, color, alpha, l, r, t, b)
    local child = LUI.UIImage.new()
    child:SetRGB(color, 0); child:SetAlpha(alpha, 0)
    child:SetAnchorsAndPosition(0, 1, 0, 1, l, r, t, b)
    parent:addElement(child)
    return child
end

local function newImage(parent, material, l, r, t, b)
    local img = LUI.UIImage.new()
    img:SetAnchorsAndPosition(0, 1, 0, 1, l, r, t, b)
    parent:addElement(img)
    local ok = material ~= nil and pcall(function() img:setImage(RegisterMaterial(material), 0) end)
    img:SetAlpha(ok and 1 or 0, 0)
    return img, ok
end

-- official SR logo (288 x 256)
local function srIcon(parent, l, t, h)
    local _, ok = newImage(parent, SR_ICON, l, l + h * 1.125, t, t + h)
    return ok
end

-- official Ranked Play shield (snake) + official I / II / III, the numeral small
-- on the plate. Returns a function that switches it to the rank of a given SR.
local function setImage(img, material)
    if material == nil then pcall(img.SetAlpha, img, 0, 0); return end
    local ok = pcall(function() img:setImage(RegisterMaterial(material), 0) end)
    pcall(img.SetAlpha, img, ok and 1 or 0, 0)
end

local function drawLogo(parent, l, t, size, large)
    local shield = LUI.UIImage.new()
    shield:SetAnchorsAndPosition(0, 1, 0, 1, l, l + size, t, t + size)
    parent:addElement(shield)
    local o, cy = size * 0.30, t + size * 0.58
    local overlay = LUI.UIImage.new()
    overlay:SetAnchorsAndPosition(0, 1, 0, 1, l + (size - o) / 2, l + (size + o) / 2, cy - o / 2, cy + o / 2)
    parent:addElement(overlay)
    return function(sr)
        local i = rankIndex(sr)
        setImage(shield, "iw9_ui_icon_leagueplay_rank_0_" .. RANKS[i].icon .. (large and "_large" or ""))
        local tier = tierOf(sr)
        if not tier then setImage(overlay, nil); return end
        local data
        pcall(function() data = LeaguePlayUtils.GetSubdivisionData(i, tier + 1) end)
        setImage(overlay, data and data.tierOverlay)
    end
end

-- ------------------------------------------------------------------
-- match history for the RANKED tab (charts, playtime, daily quests):
-- br95_ranked_history.txt = H|time|sr_after|delta|kills|deaths|seconds|rp|END
-- per line, 200 matches kept. The start of the match (time|rp) is saved in
-- br95_ranked_matchstart.txt the first time the live file says "active".
-- ------------------------------------------------------------------
local HISTORY_FILE = "jupiter/IO/br95_ranked_history.txt"
local START_FILE = "jupiter/IO/br95_ranked_matchstart.txt"
local RP_FILE = "jupiter/IO/br95_rp.txt"

local function readAll(path)
    local text
    pcall(function()
        local f = io.open(path, "r")
        if f then text = f:read("*a"); f:close() end
    end)
    return text
end

local function writeFile(path, text)
    pcall(function()
        local f = io.open(path, "w")
        if f then f:write(text); f:close() end
    end)
end

local function readRP()
    local text = readAll(RP_FILE)
    return tonumber(text and text:match("^BR95P1|(%d+)|END")) or 0
end

local function readStart()
    local text = readAll(START_FILE) or ""
    local t, rp = text:match("^(%d+)|(%d+)")
    return tonumber(t) or 0, tonumber(rp) or 0
end

local function markMatchStart()
    if state.startMarked == true then return end
    state.startMarked = true
    local saved = readStart()
    -- a start older than 3 hours belongs to a match that was never finished
    if saved == 0 or os.time() - saved > 10800 then writeFile(START_FILE, os.time() .. "|" .. readRP()) end
end

-- returns the RP won in the match
local function recordMatch(live)
    local start, rpStart = readStart()
    local now = os.time()
    local seconds = (start > 0 and now - start < 10800) and (now - start) or 0
    local rp = (start > 0) and math.max(0, readRP() - rpStart) or 0
    writeFile(START_FILE, "0|0")
    state.startMarked = false
    local lines = {}
    for line in (readAll(HISTORY_FILE) or ""):gmatch("[^\n]+") do
        if line:match("^H|") then lines[#lines + 1] = line end
    end
    lines[#lines + 1] = "H|" .. now .. "|" .. live.sr .. "|" .. live.delta .. "|" .. live.kills .. "|" .. live.deaths
        .. "|" .. seconds .. "|" .. rp .. "|END"
    while #lines > 200 do table.remove(lines, 1) end
    writeFile(HISTORY_FILE, table.concat(lines, "\n") .. "\n")
    return rp
end

local function checkVisibility(root, hud)
    if not root._br95HudMatchReady or not state.enabled or Engine.@InFrontend() then return false end
    if LUI.primaryRoot and root ~= LUI.primaryRoot then return false end
    if CONDITIONS and type(CONDITIONS.HasGameEnded) == "function" and CONDITIONS.HasGameEnded(hud.controller) then return false end
    local loading = root.loadingScreenManager
    if loading and loading:ShouldBeVisible() then return false end
    if type(AnyActiveMenusInStack) == "function" and AnyActiveMenusInStack(root) then return false end
    local conditions = VISIBILITY_CONDITIONS
    if conditions then
        for _, name in ipairs(HIDE_CONDITIONS) do
            local entry = conditions[name]
            if entry and type(entry.conditionFunc) == "function" and entry.conditionFunc(hud.controller) then return false end
        end
    end
    return true
end

local function refresh(hud)
    local live = readLive()
    if not live then hud.panel:SetAlpha(0, 0); hud.hasData = false; return end
    hud.hasData = true
    if live.active == 0 and live.sr == 0 and live.kills == 0 and live.deaths == 0 then
        hud.rank:setText(T("UNRANKED")); hud.rank:SetRGB(GREY, 0)
        hud.sr:setText(T("RANKED OFF")); hud.delta:setText(""); hud.stats:setText("")
        return
    end
    local color = RANKS[rankIndex(live.sr)].color
    local label = rankLabel(live.sr)
    hud.rank:setText(label); hud.rank:SetRGB(color, 0)
    hud.sr:setText(live.sr .. (hud.srIcon and "" or " SR"))
    hud.delta:setText((live.delta >= 0 and "+" or "") .. live.delta)
    hud.delta:SetRGB(live.delta >= 0 and GREEN or RED, 0)
    hud.stats:setText(T("KILLS %s    DEATHS %s", live.kills, live.deaths))
    if hud.color ~= color then
        hud.color = color
        for _, el in ipairs(hud.colored) do pcall(el.SetRGB, el, color, 300) end
    end
    if hud.label ~= label then
        hud.label = label
        pcall(hud.logo, live.sr)
    end
    local lo, hi = divisionRange(live.sr)
    local pct = lo and math.max(0, math.min(1, (live.sr - lo) / (hi - lo))) or 1
    pcall(hud.fill.SetAnchorsAndPosition, hud.fill, 0, 1, 0, 1, hud.barL, hud.barL + math.max(1, hud.barW * pct), hud.barT, hud.barT + 4)
    if live.active == 1 then markMatchStart() end
end

-- ------------------------------------------------------------------
-- end of match screen: rank, SR won/lost, RP won, rank or step change,
-- bar filling up. Shown once back in the menu (15 s).
-- ------------------------------------------------------------------
local function showEndScreen(root, live, rp)
    loadLang()
    local after = live.sr
    local before = math.max(0, live.sr - live.delta)
    local i = rankIndex(after)
    local color = RANKS[i].color
    local CENTER = LUI.Alignment and LUI.Alignment.Center
    local RIGHT = LUI.Alignment and LUI.Alignment.Right

    local panel = LUI.UIElement.new(); panel.id = "BR95RankedEnd"
    panel:SetAnchorsAndPosition(0.5, 0.5, 0.5, 0.5, -440, 440, -260, 260)
    panel:SetAlpha(0, 0)
    root:addElement(panel)

    newBox(panel, BLACK, 0.88, 0, 880, 0, 520)
    newBox(panel, color, 0.08, 0, 880, 0, 520)
    newBox(panel, color, 1, 0, 880, 0, 6)
    local title = newText(panel, 40, true, 30, 600, 22, 70)
    title:setText(T("RANKED RESULT")); title:SetRGB(WHITE, 0)

    local change, changeColor = nil, WHITE
    if rankIndex(after) > rankIndex(before) then change, changeColor = "RANK UP", GREEN
    elseif rankIndex(after) < rankIndex(before) then change, changeColor = "RANK DOWN", RED
    elseif tierIndex(after) > tierIndex(before) then change, changeColor = "PROMOTED", GREEN
    elseif tierIndex(after) < tierIndex(before) then change, changeColor = "DEMOTED", RED end
    if change then
        newBox(panel, changeColor, 1, 620, 850, 26, 66)
        local banner = newText(panel, 26, true, 620, 850, 32, 62, CENTER)
        banner:setText(T(change)); banner:SetRGB(BLACK, 0)
    end

    pcall(drawLogo(panel, 30, 86, 230, true), after)
    local rank = newText(panel, 52, true, 280, 870, 100, 162)
    rank:setText(rankLabel(after)); rank:SetRGB(color, 0)
    local icon = srIcon(panel, 282, 176, 34)
    local sr = newText(panel, 40, true, icon and 326 or 280, 600, 170, 218)
    sr:setText(after .. (icon and "" or " SR")); sr:SetRGB(WHITE, 0)
    local delta = newText(panel, 40, true, 600, 850, 170, 218, RIGHT)
    delta:setText((live.delta >= 0 and "+" or "") .. live.delta)
    delta:SetRGB(live.delta >= 0 and GREEN or RED, 0)
    local from = newText(panel, 18, false, 280, 850, 224, 248)
    from:setText(T("FROM %s SR  (%s)", before, rankLabel(before))); from:SetRGB(GREY, 0)
    if rp and rp > 0 then
        newImage(panel, STAR_ICON, 280, 308, 258, 286)
        local rpText = newText(panel, 26, true, 316, 850, 258, 288)
        rpText:setText("+" .. rp .. " RP"); rpText:SetRGB(RPC, 0)
    end

    local lo, hi = divisionRange(after)
    local pct = 1
    if lo then pct = math.max(0, math.min(1, (after - lo) / (hi - lo))) end
    local segs, segsOn = 24, {}
    local segW = 820 / segs
    for k = 0, segs - 1 do
        local seg = newBox(panel, 0x2A2A2A, 1, 30 + k * segW + 2, 30 + (k + 1) * segW - 2, 370, 396)
        if (k + 1) / segs <= pct + 0.0001 then segsOn[#segsOn + 1] = seg end
    end
    local nextText = newText(panel, 20, true, 30, 850, 404, 430, CENTER)
    if lo then nextText:setText(T("%s SR TO THE NEXT STEP", hi - after)) else nextText:setText(T("TOP 250")) end
    nextText:SetRGB(WHITE, 0)

    local stats = newText(panel, 26, true, 30, 850, 450, 486, CENTER)
    stats:setText(T("KILLS %s    DEATHS %s", live.kills, live.deaths))
    stats:SetRGB(WHITE, 0)

    pcall(panel.SetAlpha, panel, 1, 400)
    local tick = 0
    panel:registerEventHandler("br95_end_tick", function()
        tick = tick + 1
        local seg = segsOn[tick]
        if seg then pcall(seg.SetRGB, seg, color, 120) end
        if tick == 250 then pcall(panel.SetAlpha, panel, 0, 600) end
        if tick == 265 then pcall(panel.close, panel) end
    end)
    panel:addElement(LUI.UITimer.new({ interval = 60, event = "br95_end_tick", disposable = false, eventTarget = panel }))
end

-- back in the menu: if the last ranked match has a result not seen yet
-- (active 0), record it, show the end screen once the loading screen is gone,
-- then mark it as seen (active 2) so it never shows twice
local function frontendWatch(root)
    if root._br95EndWatch then return end
    local watch = LUI.UIElement.new(); watch.id = "BR95RankedEndWatch"
    root._br95EndWatch = watch
    root:addElement(watch)
    local waited = 0
    watch:registerEventHandler("br95_end_watch", function()
        if not Engine.@InFrontend() then return end
        local loading = root.loadingScreenManager
        if loading and loading:ShouldBeVisible() then waited = 0; return end
        waited = waited + 1
        if waited < 4 then return end -- 2 s in the menu first
        local live = readLive()
        if live and live.active == 1 then
            -- back in the menu while the match is still "active": it was left
            -- before the end, its start must not be reused
            if state.startMarked ~= "left" then writeFile(START_FILE, "0|0"); state.startMarked = "left" end
            return
        end
        if not live or live.active ~= 0 then return end
        if live.sr == 0 and live.kills == 0 and live.deaths == 0 and live.delta == 0 then return end -- ranked off
        writeFile(LIVE_FILE, "BR95L1|" .. live.sr .. "|" .. live.kills .. "|" .. live.deaths .. "|" .. live.delta .. "|2|END")
        local ok, rp = pcall(recordMatch, live)
        pcall(showEndScreen, root, live, ok and rp or 0)
    end)
    watch:addElement(LUI.UITimer.new({ interval = 500, event = "br95_end_watch", disposable = false, eventTarget = watch }))
end

local function bind(root)
    if LUI.primaryRoot and root ~= LUI.primaryRoot then return end
    if Engine.@InFrontend() then
        if root._br95Hud then root._br95Hud.panel:SetAlpha(0, 0) end
        pcall(frontendWatch, root)
        return
    end
    local controller = Engine.@GetFirstActiveController()
    if root._br95Hud and root._br95Hud.active then return end
    loadLang()

    -- left of the screen, under the minimap. 300 x 92: shield on the left, then
    -- one column (rank / SR + gain / step bar / kills and deaths) on a common
    -- left edge at x 92, everything 8 px from the borders
    local panel = LUI.UIElement.new(); panel.id = "BR95RankedHUD"
    panel:SetAnchorsAndPosition(0, 1, 0, 1, 24, 324, 330, 422)
    panel:SetAlpha(0, 0)
    local hud = { active = true, controller = controller, panel = panel, colored = {} }
    local X, R = 92, 292

    newBox(panel, BLACK, 0.62, 0, 300, 0, 92)
    hud.colored[#hud.colored + 1] = newBox(panel, 0xFFFFFF, 1, 0, 4, 0, 92)
    hud.logo = drawLogo(panel, 10, 8, 76, false)
    hud.rank = newText(panel, 17, true, X, R, 8, 28)
    hud.srIcon = srIcon(panel, X, 35, 18)
    hud.sr = newText(panel, 21, true, hud.srIcon and (X + 26) or X, 220, 32, 56)
    hud.delta = newText(panel, 21, true, 210, R, 32, 56, LUI.Alignment and LUI.Alignment.Right)
    hud.barL, hud.barW, hud.barT = X, R - X, 62
    newBox(panel, 0x3A3A3A, 1, X, R, 62, 66)
    hud.fill = newBox(panel, 0xFFFFFF, 1, X, X + 1, 62, 66)
    hud.colored[#hud.colored + 1] = hud.fill
    hud.stats = newText(panel, 13, false, X, R, 71, 87)
    hud.stats:SetRGB(GREY, 0)
    hud.sr:SetRGB(WHITE, 0)

    root._br95Hud = hud
    root:addElement(panel)

    -- data: every second; visibility: every 100 ms
    panel:registerEventHandler("br95_hud_refresh", function()
        local ok = pcall(refresh, hud)
        if not ok then hud.hasData = false end
    end)
    panel:addElement(LUI.UITimer.new({ interval = 1000, event = "br95_hud_refresh", disposable = false, eventTarget = panel }))
    panel:registerEventHandler("br95_hud_visibility", function()
        local ok, visible = pcall(checkVisibility, root, hud)
        pcall(panel.SetAlpha, panel, (ok and visible and hud.hasData) and 1 or 0, 150)
    end)
    panel:addElement(LUI.UITimer.new({ interval = 100, event = "br95_hud_visibility", disposable = false, eventTarget = panel }))
    pcall(refresh, hud)
end

local function attach(root)
    if not root or root._br95HudAttached then return end
    if LUI.primaryRoot and root ~= LUI.primaryRoot then return end
    root._br95HudAttached = true
    root._br95HudMatchReady = false
    local function safeBind() pcall(bind, root) end
    local function enteredMatch() root._br95HudMatchReady = true; safeBind() end
    local function hide()
        root._br95HudMatchReady = false
        if root._br95Hud then pcall(root._br95Hud.panel.SetAlpha, root._br95Hud.panel, 0, 0) end
    end
    root:addEventHandler("start_match", enteredMatch)
    root:addEventHandler("bootup_hud", enteredMatch)
    root:addEventHandler("playerdata_available", safeBind)
    root:addEventHandler("end_match", hide)
    root:addEventHandler("end_game", hide)
    safeBind()
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
