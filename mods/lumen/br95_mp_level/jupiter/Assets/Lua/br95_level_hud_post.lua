-- BR95 Level HUD: the in-game menu of the multiplayer level ranking.
--  * during a match: a small panel (top right) with your level, the points you
--    earn in this match, a progress bar to the next level and K / A / D
--  * back in the menu: a result screen (VICTORY / DEFEAT / DRAW, points, level up)
-- Data: jupiter/IO/br95_mp_live.txt written by br95_ranked_core_post.lua
--   BR95L2|sr|kills|assists|deaths|gain|result|active|END
-- Attach and hide logic copied from the working XP bar mod (yellow_player_xp_post.lua).
-- Fully restart the game after changes.
if BR95LevelHUD then return end
local state = { enabled = true }
BR95LevelHUD = state

local LIVE_FILE = "jupiter/IO/br95_mp_live.txt"
local ACCENT = 0xD9262E
local WHITE, GREY, DIM, LINE, BLACK = 0xFFFFFF, 0x9A9A9A, 0x5A5A5A, 0x2E2E2E, 0x000000
local GREEN, RED = 0x6BD66B, 0xE04040
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
        local sr, k, a, d, gain, result, active = text:match("^BR95L2|(%-?%d+)|(%d+)|(%d+)|(%d+)|(%-?%d+)|(%d+)|(%d+)|END")
        if sr then
            live = { sr = tonumber(sr), kills = tonumber(k), assists = tonumber(a), deaths = tonumber(d),
                gain = tonumber(gain), result = tonumber(result), active = tonumber(active) }
        end
    end)
    return live
end

-- level 1..1000: going from level L to L + 1 costs 100 + L SR (same as the core)
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

-- colour of each 100 levels (red below 100): the ranked colours Silver, Platinum, Diamond,
-- Crimson, Iridescent, Painite, then gold, emerald, ruby, rainbow at 1000
local TIER_COLORS = { 0xD9262E, 0xC8C8C8, 0x7FE0D6, 0x4FA3FF, 0xDC143C, 0xC77DFF, 0xFF4D5E, 0xFFC93C, 0x2ECC71, 0xE0245E, 0xFF7AD9 }
local function tierColor(level) return TIER_COLORS[math.min(11, math.floor(level / 100) + 1)] end

local function thousands(n)
    local s = tostring(math.floor(n))
    return (s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", ""))
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

-- ---------------------------------------------------------------- result screen
local function showResultScreen(root, live)
    local gainRes = live.gain
    local before = math.max(0, live.sr - gainRes)
    local levelBefore, levelAfter = levelOf(before), levelOf(live.sr)
    local base, nextAt = needFor(levelAfter), needFor(levelAfter + 1)
    local pct = math.max(0, math.min(1, (live.sr - base) / (nextAt - base)))
    local words = { [1] = { "VICTORY", GREEN }, [2] = { "DEFEAT", RED }, [3] = { "DRAW", GREY } }
    local word = words[live.result] or words[3]

    local panel = LUI.UIElement.new(); panel.id = "BR95LevelResult"
    panel:SetAnchorsAndPosition(0.5, 0.5, 0.5, 0.5, -440, 440, -240, 240)
    panel:SetAlpha(0, 0)
    root:addElement(panel)

    newBox(panel, BLACK, 0.9, 0, 880, 0, 480)
    newBox(panel, ACCENT, 1, 0, 880, 0, 6)
    newBox(panel, ACCENT, 1, 0, 6, 6, 480)
    newText(panel, 30, true, 34, 500, 20, 60):setText("MATCH RESULT")
    local w = newText(panel, 70, true, 34, 520, 64, 146); w:setText(word[1]); w:SetRGB(word[2], 0)
    local g = newText(panel, 64, true, 480, 850, 70, 146, LUI.Alignment and LUI.Alignment.Right)
    g:setText("+" .. gainRes .. " SR"); g:SetRGB(ACCENT, 0)

    local rows = {
        { "KILLS", live.kills .. "  x 10", live.kills * 10 },
        { "ASSISTS", live.assists .. "  x 5", live.assists * 5 },
    }
    if live.result == 1 then rows[#rows + 1] = { "VICTORY BONUS", "", 50 }
    elseif live.result == 3 then rows[#rows + 1] = { "DRAW BONUS", "", 15 } end
    for k, row in ipairs(rows) do
        local t = 170 + (k - 1) * 36
        local label = newText(panel, 20, false, 34, 330, t + 2, t + 30); label:setText(row[1]); label:SetRGB(GREY, 0)
        local count = newText(panel, 20, false, 330, 560, t + 2, t + 30); count:setText(row[2]); count:SetRGB(WHITE, 0)
        local pts = newText(panel, 22, true, 560, 850, t + 2, t + 30, LUI.Alignment and LUI.Alignment.Right)
        pts:setText("+" .. row[3]); pts:SetRGB(WHITE, 0)
        newBox(panel, LINE, 1, 34, 850, t + 34, t + 35)
    end

    local lv = newText(panel, 32, true, 34, 850, 330, 372)
    if levelAfter > levelBefore then
        lv:setText("LEVEL UP    " .. levelBefore .. "   >   " .. levelAfter); lv:SetRGB(tierColor(levelAfter), 0)
    else
        lv:setText("LEVEL " .. levelAfter); lv:SetRGB(tierColor(levelAfter), 0)
    end

    local segs, on = 24, {}
    local segW = 816 / segs
    for k = 0, segs - 1 do
        local seg = newBox(panel, LINE, 1, 34 + k * segW + 2, 34 + (k + 1) * segW - 2, 386, 412)
        if (k + 1) / segs <= pct + 0.0001 then on[#on + 1] = seg end
    end
    local hint = newText(panel, 18, true, 34, 850, 420, 446)
    hint:setText((nextAt - live.sr) .. " SR TO LEVEL " .. (levelAfter + 1) .. "     |     TOTAL " .. thousands(live.sr) .. " SR")
    hint:SetRGB(GREY, 0)

    pcall(panel.SetAlpha, panel, 1, 400)
    local tick = 0
    panel:registerEventHandler("br95_level_result_tick", function()
        tick = tick + 1
        local seg = on[tick]
        if seg then pcall(seg.SetRGB, seg, ACCENT, 120) end
        if tick == 250 then pcall(panel.SetAlpha, panel, 0, 600) end
        if tick == 265 then pcall(panel.close, panel) end
    end)
    panel:addElement(LUI.UITimer.new({ interval = 60, event = "br95_level_result_tick", disposable = false, eventTarget = panel }))
end

-- back in the menu: show the result of the last match once, then mark it as seen
local function frontendWatch(root)
    if root._br95LevelWatch then return end
    local watch = LUI.UIElement.new(); watch.id = "BR95LevelResultWatch"
    root._br95LevelWatch = watch
    root:addElement(watch)
    local waited = 0
    watch:registerEventHandler("br95_level_watch", function()
        if not Engine.@InFrontend() then return end
        local loading = root.loadingScreenManager
        if loading and loading:ShouldBeVisible() then waited = 0; return end
        waited = waited + 1
        if waited < 4 then return end   -- 2 s in the menu first
        local live = readLive()
        if not live or live.active ~= 0 then return end
        if live.sr == 0 and live.kills == 0 and live.assists == 0 and live.deaths == 0 and live.gain == 0 then return end
        pcall(function()
            local f = io.open(LIVE_FILE, "w")
            if f then
                f:write("BR95L2|" .. live.sr .. "|" .. live.kills .. "|" .. live.assists .. "|" .. live.deaths .. "|"
                    .. live.gain .. "|" .. live.result .. "|2|END")
                f:close()
            end
        end)
        pcall(showResultScreen, root, live)
    end)
    watch:addElement(LUI.UITimer.new({ interval = 500, event = "br95_level_watch", disposable = false, eventTarget = watch }))
end

-- ---------------------------------------------------------------- in-game panel
local function checkVisibility(root, hud)
    if not root._br95LevelReady or not state.enabled or Engine.@InFrontend() then return false end
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

local BAR_L, BAR_R = 14, 282

local function refresh(hud)
    local live = readLive()
    if not live or live.active ~= 1 then hud.hasData = false; return end
    hud.hasData = true
    local level = levelOf(live.sr)
    local base, nextAt = needFor(level), needFor(level + 1)
    local pct = math.max(0, math.min(1, (live.sr - base) / (nextAt - base)))
    hud.level:setText("LEVEL " .. level)
    pcall(hud.level.SetRGB, hud.level, tierColor(level), 0)
    hud.gain:setText("+" .. live.gain .. " SR")
    hud.stats:setText("K " .. live.kills .. "    A " .. live.assists .. "    D " .. live.deaths)
    pcall(hud.fill.SetAnchorsAndPosition, hud.fill, 0, 1, 0, 1, BAR_L, BAR_L + math.max(1, math.floor((BAR_R - BAR_L) * pct)), 38, 44)
end

local function bind(root)
    if LUI.primaryRoot and root ~= LUI.primaryRoot then return end
    if Engine.@InFrontend() then
        if root._br95LevelHud then root._br95LevelHud.panel:SetAlpha(0, 0) end
        pcall(frontendWatch, root)
        return
    end
    local controller = Engine.@GetFirstActiveController()
    if root._br95LevelHud and root._br95LevelHud.active then return end

    local panel = LUI.UIElement.new(); panel.id = "BR95LevelHUD"
    panel:SetAnchorsAndPosition(1, 0, 0, 1, -320, -24, 210, 294)
    panel:SetAlpha(0, 0)
    local hud = { active = true, controller = controller, panel = panel }

    newBox(panel, BLACK, 0.55, 0, 296, 0, 84)
    newBox(panel, ACCENT, 1, 0, 3, 0, 84)
    hud.level = newText(panel, 17, true, 14, 150, 6, 30)
    hud.level:SetRGB(ACCENT, 0)
    hud.gain = newText(panel, 20, true, 150, 282, 4, 30, LUI.Alignment and LUI.Alignment.Right)
    hud.gain:SetRGB(WHITE, 0)
    newBox(panel, LINE, 1, BAR_L, BAR_R, 38, 44)
    hud.fill = newBox(panel, ACCENT, 1, BAR_L, BAR_L + 1, 38, 44)
    hud.stats = newText(panel, 14, false, 14, 200, 52, 74)
    hud.stats:SetRGB(GREY, 0)
    local tag = newText(panel, 12, false, 150, 282, 54, 74, LUI.Alignment and LUI.Alignment.Right)
    tag:setText("THIS MATCH"); tag:SetRGB(DIM, 0)

    root._br95LevelHud = hud
    root:addElement(panel)

    panel:registerEventHandler("br95_level_refresh", function() pcall(refresh, hud) end)
    panel:addElement(LUI.UITimer.new({ interval = 1000, event = "br95_level_refresh", disposable = false, eventTarget = panel }))
    panel:registerEventHandler("br95_level_visibility", function()
        local ok, visible = pcall(checkVisibility, root, hud)
        pcall(panel.SetAlpha, panel, (ok and visible and hud.hasData) and 1 or 0, 150)
    end)
    panel:addElement(LUI.UITimer.new({ interval = 100, event = "br95_level_visibility", disposable = false, eventTarget = panel }))
    pcall(refresh, hud)
end

local function attach(root)
    if not root or root._br95LevelAttached then return end
    if LUI.primaryRoot and root ~= LUI.primaryRoot then return end
    root._br95LevelAttached = true
    root._br95LevelReady = false
    local function safeBind() pcall(bind, root) end
    local function enteredMatch() root._br95LevelReady = true; safeBind() end
    local function hide()
        root._br95LevelReady = false
        if root._br95LevelHud then pcall(root._br95LevelHud.panel.SetAlpha, root._br95LevelHud.panel, 0, 0) end
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