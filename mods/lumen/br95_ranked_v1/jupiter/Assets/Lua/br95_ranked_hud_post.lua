-- BR95 Ranked HUD: small panel during the match (top right) with the rank
-- logo, the current SR and the SR won or lost in this match, live.
-- Data: jupiter/IO/br95_ranked_live.txt written by br95_ranked.gscc
--   BR95L1|sr_now|kills|deaths|delta|active|END
-- Attach / hide logic copied from the working XP bar mod
-- (yellow_player_xp_post.lua). Fully restart the game after changes.
if BR95RankedHUD then return end
local state = { enabled = true }
BR95RankedHUD = state

local LIVE_FILE = "jupiter/IO/br95_ranked_live.txt"
local RANKS = {
    { name = "BRONZE",     start = 0,     color = 0xCD7F32 },
    { name = "SILVER",     start = 1000,  color = 0xC8C8C8 },
    { name = "PLATINUM",   start = 2500,  color = 0x7FE0D6 },
    { name = "DIAMOND",    start = 5000,  color = 0x4FA3FF },
    { name = "CRIMSON",    start = 8000,  color = 0xDC143C },
    { name = "IRIDESCENT", start = 12000, color = 0xC77DFF },
    { name = "PAINITE",    start = 17000, color = 0xB0303A },
}
local ROMAN = { "I", "II", "III" }
local WHITE, GREY, GREEN, RED, BLACK = 0xFFFFFF, 0x9A9A9A, 0x6BD66B, 0xE04040, 0x000000
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

local function rankLabel(sr)
    local i = rankIndex(sr)
    if i == #RANKS then return RANKS[i].name end
    local size = (RANKS[i + 1].start - RANKS[i].start) / 3
    local tier = math.min(2, math.floor((sr - RANKS[i].start) / size))
    return RANKS[i].name .. " " .. ROMAN[tier + 1]
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

-- small version of the menu logo: hexagon shield, nameplate, blade
local function drawLogo(parent, cx, top, s, colored)
    local function b(color, alpha, l, r, t, bt)
        local el = newBox(parent, color, alpha, cx + l * s, cx + r * s, top + t * s, top + bt * s)
        if color ~= BLACK then colored[#colored + 1] = el end
    end
    local function hex(color, alpha, inset)
        local y = inset
        while y < 220 - inset do
            local yc = y + 10
            local half = 100
            if yc < 50 then half = 55 + (yc / 50) * 45 elseif yc > 170 then half = 55 + ((220 - yc) / 50) * 45 end
            half = half - inset
            if half > 0 then b(color, alpha, -half, half, y, math.min(y + 20, 220 - inset)) end
            y = y + 20
        end
    end
    hex(0xFFFFFF, 1, 0)
    hex(BLACK, 1, 12)
    for r = 1, 5 do
        local w = 50 * (1 - math.abs(r - 3) / 3.3)
        b(0xFFFFFF, 1, -w / 2, w / 2, 40 + (r - 1) * 14, 52 + (r - 1) * 14)
    end
    b(0xFFFFFF, 1, -118, 118, 112, 136)
    b(BLACK, 0.5, -112, 112, 118, 130)
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
        hud.rank:setText("UNRANKED"); hud.rank:SetRGB(GREY, 0)
        hud.sr:setText("RANKED OFF"); hud.delta:setText(""); hud.stats:setText("")
        return
    end
    local color = RANKS[rankIndex(live.sr)].color
    hud.rank:setText(rankLabel(live.sr)); hud.rank:SetRGB(color, 0)
    hud.sr:setText(live.sr .. " SR")
    hud.delta:setText((live.delta >= 0 and "+" or "") .. live.delta)
    hud.delta:SetRGB(live.delta >= 0 and GREEN or RED, 0)
    hud.stats:setText("K " .. live.kills .. "   D " .. live.deaths .. "   |   THIS MATCH")
    if hud.color ~= color then
        hud.color = color
        for _, el in ipairs(hud.colored) do pcall(el.SetRGB, el, color, 300) end
    end
end

-- ------------------------------------------------------------------
-- end of match screen: rank, SR won/lost, rank or division change,
-- progress bar filling up. Shown once when the match ends (15 s).
-- ------------------------------------------------------------------
local function tierIndex(sr)
    local i = rankIndex(sr)
    if i == #RANKS then return i * 3 end
    local size = (RANKS[i + 1].start - RANKS[i].start) / 3
    return i * 3 + math.min(2, math.floor((sr - RANKS[i].start) / size))
end

local function divisionRange(sr)
    local i = rankIndex(sr)
    if i == #RANKS then return nil end
    local size = (RANKS[i + 1].start - RANKS[i].start) / 3
    local tier = math.min(2, math.floor((sr - RANKS[i].start) / size))
    return math.floor(RANKS[i].start + tier * size), math.floor(RANKS[i].start + (tier + 1) * size)
end

local function showEndScreen(root, live)
    local after = live.sr
    local before = math.max(0, live.sr - live.delta)
    local i = rankIndex(after)
    local color = RANKS[i].color

    local panel = LUI.UIElement.new(); panel.id = "BR95RankedEnd"
    panel:SetAnchorsAndPosition(0.5, 0.5, 0.5, 0.5, -440, 440, -250, 250)
    panel:SetAlpha(0, 0)
    root:addElement(panel)
    local colored = {}

    newBox(panel, BLACK, 0.88, 0, 880, 0, 500)
    newBox(panel, color, 1, 0, 880, 0, 8)
    newBox(panel, color, 1, 0, 6, 8, 500)
    local title = newText(panel, 40, true, 30, 600, 22, 70)
    title:setText("RANKED RESULT"); title:SetRGB(WHITE, 0)

    -- rank / division change banner
    local change, changeColor = nil, WHITE
    if rankIndex(after) > rankIndex(before) then change, changeColor = "RANK UP", GREEN
    elseif rankIndex(after) < rankIndex(before) then change, changeColor = "RANK DOWN", RED
    elseif tierIndex(after) > tierIndex(before) then change, changeColor = "DIVISION UP", GREEN
    elseif tierIndex(after) < tierIndex(before) then change, changeColor = "DIVISION DOWN", RED end
    if change then
        newBox(panel, changeColor, 1, 600, 850, 26, 66)
        local banner = newText(panel, 26, true, 600, 850, 32, 62, LUI.Alignment and LUI.Alignment.Center)
        banner:setText(change); banner:SetRGB(BLACK, 0)
    end

    -- logo + rank + SR
    drawLogo(panel, 140, 100, 0.95, colored)
    for _, el in ipairs(colored) do pcall(el.SetRGB, el, color, 0) end
    local rank = newText(panel, 54, true, 270, 870, 105, 170)
    rank:setText(rankLabel(after)); rank:SetRGB(color, 0)
    local sr = newText(panel, 40, true, 270, 600, 175, 225)
    sr:setText(after .. " SR"); sr:SetRGB(WHITE, 0)
    local delta = newText(panel, 40, true, 600, 850, 175, 225, LUI.Alignment and LUI.Alignment.Right)
    delta:setText((live.delta >= 0 and "+" or "") .. live.delta .. " SR")
    delta:SetRGB(live.delta >= 0 and GREEN or RED, 0)
    local from = newText(panel, 20, false, 270, 850, 228, 254)
    from:setText("FROM " .. before .. " SR  (" .. rankLabel(before) .. ")"); from:SetRGB(GREY, 0)

    -- progress bar inside the new division, filling up segment by segment
    local lo, hi = divisionRange(after)
    local pct = 1
    if lo then pct = math.max(0, math.min(1, (after - lo) / (hi - lo))) end
    local segs, segs_on = 24, {}
    local segW = 820 / segs
    for k = 0, segs - 1 do
        local seg = newBox(panel, 0x2A2A2A, 1, 30 + k * segW + 2, 30 + (k + 1) * segW - 2, 360, 390)
        if (k + 1) / segs <= pct + 0.0001 then segs_on[#segs_on + 1] = seg end
    end
    local next = newText(panel, 20, true, 30, 850, 396, 422, LUI.Alignment and LUI.Alignment.Center)
    if lo then next:setText((hi - after) .. " SR TO NEXT DIVISION") else next:setText("TOP RANK") end
    next:SetRGB(WHITE, 0)

    -- match stats
    local stats = newText(panel, 26, true, 30, 850, 440, 476, LUI.Alignment and LUI.Alignment.Center)
    stats:setText("KILLS " .. live.kills .. "      DEATHS " .. live.deaths)
    stats:SetRGB(WHITE, 0)

    -- animation: fade in, fill the bar, stay, fade out
    pcall(panel.SetAlpha, panel, 1, 400)
    local tick = 0
    panel:registerEventHandler("br95_end_tick", function()
        tick = tick + 1
        local seg = segs_on[tick]
        if seg then pcall(seg.SetRGB, seg, color, 120) end
        if tick == 250 then pcall(panel.SetAlpha, panel, 0, 600) end
        if tick == 265 then pcall(panel.close, panel) end
    end)
    panel:addElement(LUI.UITimer.new({ interval = 60, event = "br95_end_tick", disposable = false, eventTarget = panel }))
end

-- back in the menu: if the last ranked match has a result not seen yet
-- (active 0), show the end screen once the loading screen is gone, then mark
-- it as seen (active 2) so it never shows twice
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
        if not live or live.active ~= 0 then return end
        if live.sr == 0 and live.kills == 0 and live.deaths == 0 and live.delta == 0 then return end -- ranked off
        pcall(function()
            local f = io.open(LIVE_FILE, "w")
            if f then
                f:write("BR95L1|" .. live.sr .. "|" .. live.kills .. "|" .. live.deaths .. "|" .. live.delta .. "|2|END"); f:close()
            end
        end)
        pcall(showEndScreen, root, live)
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

    -- top right of the screen, under the compass / minimap area
    local panel = LUI.UIElement.new(); panel.id = "BR95RankedHUD"
    panel:SetAnchorsAndPosition(1, 0, 0, 1, -300, -24, 210, 286)
    panel:SetAlpha(0, 0)
    local hud = { active = true, controller = controller, panel = panel, colored = {} }

    newBox(panel, BLACK, 0.55, 0, 276, 0, 76)
    hud.colored[#hud.colored + 1] = newBox(panel, 0xFFFFFF, 1, 0, 3, 0, 76)
    drawLogo(panel, 34, 9, 0.26, hud.colored)
    hud.rank = newText(panel, 16, true, 68, 272, 5, 24)
    hud.sr = newText(panel, 19, true, 68, 190, 26, 49)
    hud.delta = newText(panel, 19, true, 190, 268, 26, 49, LUI.Alignment and LUI.Alignment.Right)
    hud.stats = newText(panel, 12, false, 68, 272, 53, 70)
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
