-- BR95 Ranked Shop (Ranked 0.6): a RANKED SHOP tab in the Warzone lobby. Spend the
-- Ranked Points (RP, br95_rp.txt) won in ranked matches on:
--   - SHOP: 13 items per rotation (4 camos, 4 weapon blueprints, 4 operator skins and
--     1 FEATURED legendary / ultra item), new items every 8 h (00h, 08h, 16h UTC), and
--     2 ranked bonuses (SR PROTECTION / SR X2, one at a time, used by the next
--     ranked match: applied by br95_ranked_hud_post.lua when the result is seen)
--   - LOTTERY: 300 RP, a random item by rarity odds; an item already owned gives
--     150 RP back
--   - UPGRADE: pick an item, stake RP; chance = stake / item value (max 75 %)
-- Items are given by the LocalProgression case mod (global LocalProgressionRankBridge,
-- by @swatcookie): the shop credits the CP of one case and opens it with a random()
-- steered onto the exact item, checked first with the free bridge.sampleCaseItems
-- (same method as the MP SHOP). Only works in menus.
-- Same purple / blue look as the RANKED tab (br95_ranked_post.lua). Everything that
-- moves runs on one 16 ms timer, timed with the clock (tweens with easing curves).
-- Three pages = three layers created with the tab; buttons of hidden pages are moved
-- off screen. Everything in pcall: on error the tab shows the message, the game keeps
-- working.
if BR95RankedShop then return end
local state = { installed = false }
BR95RankedShop = state

local IO = "jupiter/IO/"
local RP_FILE = IO .. "br95_rp.txt"                     -- BR95P1|rp|END
local ITEMS_FILE = IO .. "br95_rshop_items.txt"         -- BR95RS2|rotation|id,id,..|END
local UPGRADE_FILE = IO .. "br95_rshop_upgrade.txt"     -- BR95RU2|rotation|id,id,id,id|END
local BONUS_FILE = IO .. "br95_shop_bonus.txt"          -- BR95SB1|kind|END (0 none, 1 protection, 2 x2)
local POOL_FILE = "jupiter/LocalProgression/local_case_pool.txt"
local MENU = "BR95RankedShopMenu"
local ROTATION = 8 * 3600                               -- new items every 8 h (3 per day, UTC)

local PRICES = { [0] = 150, [1] = 250, [2] = 400, [3] = 650, [4] = 1000, [5] = 1500 }
local RARITY = { [0] = { "COMMON", 0xB0B0B0 }, [1] = { "UNCOMMON", 0x6BD66B }, [2] = { "RARE", 0x4FA3FF },
    [3] = { "EPIC", 0xB061FF }, [4] = { "LEGENDARY", 0xFFB020 }, [5] = { "ULTRA", 0xFF4060 } }
local CAMO, BLUEPRINT, SKIN = { CAMO = true }, { WEAPON = true }, { OPERATOR_SKIN = true, OPERATOR = true }
local ANY = { CAMO = true, WEAPON = true, OPERATOR_SKIN = true, OPERATOR = true }
local KIND_LABEL = { CAMO = "CAMO", WEAPON = "BLUEPRINT", OPERATOR_SKIN = "SKIN", OPERATOR = "SKIN" }
-- 3 rows of 4 (camos, blueprints, skins), then the featured item (legendary or ultra)
local SLOTS = {
    { label = "CAMO", kinds = CAMO }, { label = "CAMO", kinds = CAMO }, { label = "CAMO", kinds = CAMO }, { label = "CAMO", kinds = CAMO },
    { label = "BLUEPRINT", kinds = BLUEPRINT }, { label = "BLUEPRINT", kinds = BLUEPRINT },
    { label = "BLUEPRINT", kinds = BLUEPRINT }, { label = "BLUEPRINT", kinds = BLUEPRINT },
    { label = "SKIN", kinds = SKIN }, { label = "SKIN", kinds = SKIN }, { label = "SKIN", kinds = SKIN }, { label = "SKIN", kinds = SKIN },
    { label = "FEATURED", kinds = ANY, minQ = 4 },
}
local FEATURED = #SLOTS
local BONUSES = {
    { kind = 1, name = "SR PROTECTION", info = "NEXT RANKED MATCH: NO SR LOST", price = 300, color = 0x4FA3FF },
    { kind = 2, name = "SR X2", info = "NEXT RANKED MATCH: SR WON DOUBLED", price = 500, color = 0xFFB020 },
}
local LOTTERY_PRICE, LOTTERY_REFUND = 300, 150
local LOTTERY_ODDS = { [0] = 40, [1] = 28, [2] = 18, [3] = 9, [4] = 4, [5] = 1 }
local STAKES = { 50, 100, 200, 300, 500 }
local MAX_CHANCE = 75

-- purple / blue look (same as the RANKED tab)
local WHITE, GREY, DIM, BLACK = 0xFFFFFF, 0xC9C0F0, 0x9488D0, 0x000000
local SIDE, MAIN, CARD, EDGE, LINE = 0x1B2C86, 0x3A2690, 0x2C1C78, 0x7A62E0, 0x2A1B70
local GREEN, GOLD, RED, CYAN, BRUSH = 0x6BD66B, 0xFFD166, 0xFF5A6E, 0x5FD4FF, 0x2F7BFF
local BACK_ART = "menu_keyart_rankedplay_01_layer_00"
local STAR_ICON = "iw9_ui_icon_leagueplay_star_filled"
local SR_ICON = "iw9_ui_icon_leagueplay_skill_rating"
local DOT = "hud_reticle_circle_fill"                   -- white disc of the game (tinted)
local CX = 160                                          -- centre of the content (right of the column)

-- easing curves (x 0 -> 1)
local EASE = {}
function EASE.out(x) x = 1 - x; return 1 - x * x * x end
function EASE.quart(x) x = 1 - x; return 1 - x * x * x * x end
-- goes a bit past the end and comes back (things that pop in)
function EASE.back(x) x = x - 1; return 1 + 2.2 * x * x * x + 1.2 * x * x end

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

local function readRP()
    local text = readText(RP_FILE)
    return tonumber(text and text:match("^BR95P1|(%d+)|END")) or 0
end

local function writeRP(rp)
    return writeText(RP_FILE, "BR95P1|" .. math.max(0, math.floor(rp)) .. "|END")
end

local function readBonus()
    return tonumber((readText(BONUS_FILE) or ""):match("^BR95SB1|(%d)|END")) or 0
end

local function now()
    local ok, t = pcall(os.time)
    return ok and tonumber(t) or 0
end

local function rotation() return math.floor(now() / ROTATION) end

local function clock(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%02dH %02dM %02dS", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
end

-- ------------------------------------------------------------------
-- case mod bridge (LocalProgression by @swatcookie)
-- ------------------------------------------------------------------
local Case = {}

function Case.bridge()
    local bridge = rawget(_G, "LocalProgressionRankBridge")
    if type(bridge) ~= "table" or type(bridge.grantLocalCP) ~= "function" or type(bridge.openCase) ~= "function"
        or type(bridge.caseOdds) ~= "function" or type(bridge.sampleCaseItems) ~= "function" then
        return nil
    end
    return bridge
end

function Case.rows(bridge)
    local ok, rows = pcall(bridge.caseOdds)
    if ok and type(rows) == "table" then return rows end
    return {}
end

function Case.owns(bridge, id)
    local store = type(bridge.caseStore) == "table" and bridge.caseStore.store
    return type(store) == "table" and type(store.owned) == "table" and store.owned[id] == true
end

function Case.info(bridge, id)
    for _, row in ipairs(Case.rows(bridge)) do
        if row.item and row.item.id == id then return row.item.kind, tonumber(row.item.quality) or 0 end
    end
    return nil, 0
end

function Case.name(id)
    if type(LOOT) == "table" and type(LOOT.GetItemNameByID) == "function" then
        local ok, name = pcall(LOOT.GetItemNameByID, id)
        if ok and type(name) == "string" and name ~= "" then
            if Engine and type(Engine.Localize) == "function" then
                local good, text = pcall(Engine.Localize, name)
                if good and type(text) == "string" and text ~= "" then name = text end
            end
            return name
        end
    end
    return "ITEM " .. tostring(id)
end

function Case.image(id)
    if not id or type(LOOT) ~= "table" or type(LOOT.GetItemImageByID) ~= "function" then return nil end
    local ok, image = pcall(LOOT.GetItemImageByID, id)
    if ok and type(image) == "string" and image ~= "" then return image end
    return nil
end

-- maker of a random() that makes the case draw land on `id` (1st call = rarity,
-- 2nd = item of that rarity in pool file order), nil when not possible
function Case.exact(bridge, id)
    local chanceOf, qualityOf, share = {}, {}, {}
    for _, row in ipairs(Case.rows(bridge)) do
        local item = row.item
        if item then
            local q = tonumber(item.quality) or 0
            chanceOf[item.id] = tonumber(row.chance) or 0
            qualityOf[item.id] = q
            share[q] = tonumber(row.tierChance) or 0
        end
    end
    local target = qualityOf[id]
    if not target then return nil end
    local low, total = 0, 0
    for q = 0, 5 do
        if share[q] then
            if q < target then low = low + share[q] end
            total = total + share[q]
        end
    end
    if total <= 0 or (share[target] or 0) <= 0 then return nil end
    local first = (low + share[target] / 2) / total
    local text = readText(POOL_FILE)
    if not text then return nil end
    local before, own, sum = 0, 0, 0
    for poolId in text:gmatch("\n(%d+)|%d|") do
        poolId = tonumber(poolId)
        if qualityOf[poolId] == target then
            local c = chanceOf[poolId] or 0
            if poolId == id then own = c elseif own == 0 then before = before + c end
            sum = sum + c
        end
    end
    if sum <= 0 or own <= 0 then return nil end
    local second = (before + own / 2) / sum
    return function()
        local calls = 0
        return function()
            calls = calls + 1
            if calls == 1 then return first end
            return second
        end
    end
end

-- free dry run: true when the steered draw really gives `id`
function Case.check(bridge, id)
    local maker = Case.exact(bridge, id)
    if not maker then return nil end
    local ok, sample = pcall(bridge.sampleCaseItems, 1, maker())
    if not ok or type(sample) ~= "table" or not sample[1] or sample[1].id ~= id then return nil end
    return maker
end

-- gives the item (RP are handled by the caller). Returns the drop or nil + message.
function Case.give(bridge, maker)
    local casePrice = tonumber(bridge.casePrice) or 1000
    local good, granted = pcall(bridge.grantLocalCP, casePrice)
    if not good or granted ~= true then return nil, "ONLY WORKS IN THE MENU" end
    local opened, success, drop = pcall(bridge.openCase, maker())
    if not opened or success ~= true or type(drop) ~= "table" then
        return nil, "CP ADDED - OPEN A CASE FROM THE CASES MENU"
    end
    return drop
end

-- items of a rotation, chosen once among items not owned and saved
function Case.pick(file, tag, rot, count, pickFor)
    local text = readText(file) or ""
    local fileRot, list = text:match("^" .. tag .. "|(%d+)|([%d,]*)|END")
    if list and tonumber(fileRot) == rot then
        local ids = {}
        for id in list:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
        if #ids == count then return ids end
    end
    local bridge = Case.bridge()
    if not bridge then return nil end
    local rows = Case.rows(bridge)
    if #rows == 0 then return nil end
    local ids, used = {}, {}
    for slot = 1, count do
        local candidates = {}
        for _, row in ipairs(rows) do
            local item = row.item
            if item and not used[item.id] and pickFor(slot, item) and not Case.owns(bridge, item.id) then
                candidates[#candidates + 1] = item.id
            end
        end
        table.sort(candidates)
        local id = (#candidates > 0) and candidates[(rot * 7919 + slot * 104729) % #candidates + 1] or 0
        ids[slot] = id
        used[id] = true
    end
    writeText(file, tag .. "|" .. rot .. "|" .. table.concat(ids, ",") .. "|END")
    return ids
end

-- ------------------------------------------------------------------
-- actions (each returns a result table, or nil + message; nothing is paid on failure)
-- ------------------------------------------------------------------
local Act = {}

function Act.buyItem(id)
    local bridge = Case.bridge()
    if not bridge then return nil, "CASE MOD NOT FOUND - OPEN ITS CASES MENU ONCE" end
    if Case.owns(bridge, id) then return nil, "ALREADY OWNED" end
    local _, quality = Case.info(bridge, id)
    local price = PRICES[quality] or 500
    local maker = Case.check(bridge, id)
    if not maker then return nil, "ITEM NOT AVAILABLE (NOTHING PAID)" end
    local rp = readRP()
    if rp < price then return nil, "NOT ENOUGH RP" end
    if not writeRP(rp - price) then return nil, "SAVE ERROR" end
    local drop, err = Case.give(bridge, maker)
    if not drop then
        if err == "ONLY WORKS IN THE MENU" then writeRP(rp) end
        return nil, err
    end
    return { id = id, quality = quality, paid = price }
end

function Act.buyBonus(bonus)
    if readBonus() ~= 0 then return nil, "A BONUS IS ALREADY ACTIVE" end
    local rp = readRP()
    if rp < bonus.price then return nil, "NOT ENOUGH RP" end
    if not writeRP(rp - bonus.price) then return nil, "SAVE ERROR" end
    if not writeText(BONUS_FILE, "BR95SB1|" .. bonus.kind .. "|END") then
        writeRP(rp)
        return nil, "SAVE ERROR"
    end
    return { paid = bonus.price }
end

-- lottery: rarity by LOTTERY_ODDS, then a random item of that rarity
function Act.lottery()
    local bridge = Case.bridge()
    if not bridge then return nil, "CASE MOD NOT FOUND - OPEN ITS CASES MENU ONCE" end
    local rp = readRP()
    if rp < LOTTERY_PRICE then return nil, "NOT ENOUGH RP" end
    local byQuality = {}
    for _, row in ipairs(Case.rows(bridge)) do
        local item = row.item
        if item then
            local q = tonumber(item.quality) or 0
            byQuality[q] = byQuality[q] or {}
            table.insert(byQuality[q], item.id)
        end
    end
    local roll, quality = math.random(1, 100), 0
    for q = 0, 5 do
        roll = roll - LOTTERY_ODDS[q]
        if roll <= 0 then quality = q; break end
    end
    while quality > 0 and not byQuality[quality] do quality = quality - 1 end
    local list = byQuality[quality]
    if not list or #list == 0 then return nil, "NO ITEM AVAILABLE" end
    local id = list[math.random(1, #list)]

    if Case.owns(bridge, id) then
        if not writeRP(rp - LOTTERY_PRICE + LOTTERY_REFUND) then return nil, "SAVE ERROR" end
        return { id = id, quality = quality, duplicate = true, paid = LOTTERY_PRICE - LOTTERY_REFUND }
    end
    local maker = Case.check(bridge, id)
    if not maker then return nil, "DRAW FAILED (NOTHING PAID) - TRY AGAIN" end
    if not writeRP(rp - LOTTERY_PRICE) then return nil, "SAVE ERROR" end
    local drop, err = Case.give(bridge, maker)
    if not drop then
        if err == "ONLY WORKS IN THE MENU" then writeRP(rp) end
        return nil, err
    end
    return { id = id, quality = quality, paid = LOTTERY_PRICE }
end

function Act.chance(stake, quality)
    return math.min(MAX_CHANCE, math.floor(stake * 100 / (PRICES[quality] or 1000)))
end

-- upgrade: the stake is always paid, the item only on a win
function Act.upgrade(id, stake)
    local bridge = Case.bridge()
    if not bridge then return nil, "CASE MOD NOT FOUND - OPEN ITS CASES MENU ONCE" end
    if Case.owns(bridge, id) then return nil, "ALREADY OWNED - PICK ANOTHER ITEM" end
    local _, quality = Case.info(bridge, id)
    local maker = Case.check(bridge, id)
    if not maker then return nil, "ITEM NOT AVAILABLE (NOTHING PAID)" end
    local rp = readRP()
    if rp < stake then return nil, "NOT ENOUGH RP" end
    local chance = Act.chance(stake, quality)
    local roll = math.random(1, 100)
    if not writeRP(rp - stake) then return nil, "SAVE ERROR" end
    if roll > chance then return { id = id, quality = quality, won = false, chance = chance, roll = roll, paid = stake } end
    local drop, err = Case.give(bridge, maker)
    if not drop then
        if err == "ONLY WORKS IN THE MENU" then writeRP(rp) end
        return nil, err
    end
    return { id = id, quality = quality, won = true, chance = chance, roll = roll, paid = stake }
end

-- ------------------------------------------------------------------
-- UI helpers (one table, so the page builders keep few upvalues)
-- ------------------------------------------------------------------
local function newUI(root, controller)
    local U = { anims = {}, layers = {}, buttons = {}, groups = {}, tweens = {}, page = "shop" }
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
        U.layers[name], U.buttons[name], U.groups[name] = layer, {}, {}
        U.P, U.building = layer, name
        return layer
    end
    -- a group of the page (a card...): pops in when the page is shown
    function U.group()
        local g = full(U.layers[U.building])
        table.insert(U.groups[U.building], g)
        U.P = g
        return g
    end
    function U.ungroup() U.P = U.layers[U.building] end

    function U.font(text, size, bold)
        if FONTS and FONTS.GetFont then
            local f = bold and FONTS.PrimaryBold or FONTS.SecondaryRegular
            if f and f.File then pcall(text.SetFont, text, FONTS.GetFont(f.File)) end
        end
        if text.SetFontSize then pcall(text.SetFontSize, text, size) end
    end
    function U.box(color, alpha, l, r, t, b, parent)
        local child = LUI.UIImage.new()
        child:SetRGB(color, 0); child:SetAlpha(alpha, 0)
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        ;(parent or U.P):addElement(child); return child
    end
    function U.text(str, size, color, l, r, t, b, align, bold, parent)
        local child = LUI.UIText.new()
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        U.font(child, size, bold)
        if child.SetAlignment and LUI.Alignment then child:SetAlignment(align or U.LEFT) end
        child:SetRGB(color or WHITE, 0)
        child:setText(str)
        ;(parent or U.P):addElement(child); return child
    end
    function U.picture(l, r, t, b, image, parent)
        local child = LUI.UIImage.new()
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        ;(parent or U.P):addElement(child)
        U.setPicture(child, image)
        return child
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
    -- a tinted disc of the game
    function U.disc(color, alpha, l, r, t, b, parent)
        local d = U.picture(l, r, t, b, DOT, parent)
        pcall(d.SetRGB, d, color, 0); pcall(d.SetAlpha, d, alpha, 0)
        return d
    end
    function U.button(l, r, t, b, label, action)
        local btn = MenuBuilder.BuildRegisteredType("GenericButton", { controllerIndex = controller })
        btn:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        U.P:addElement(btn)
        if btn.Text then pcall(btn.Text.setText, btn.Text, label) end
        local mine = U.building
        btn:addEventHandler("button_action", function()
            if mine ~= "common" and U.page ~= mine then return end
            pcall(action)
        end)
        table.insert(U.buttons[mine], { btn = btn, l = l, r = r, t = t, b = b })
        return btn
    end
    function U.set(element, str, color)
        if not element then return end
        pcall(element.setText, element, str)
        if color then pcall(element.SetRGB, element, color, 0) end
    end
    function U.label(btn, str)
        if btn and btn.Text then pcall(btn.Text.setText, btn.Text, str) end
    end
    function U.tint(element, color) if element then pcall(element.SetRGB, element, color, 0) end end
    function U.fade(element, value) if element then pcall(element.SetAlpha, element, value, 0) end end
    function U.move(element, l, r, t, b) if element then pcall(element.SetAnchorsAndPosition, element, 0.5, 0.5, 0, 1, l, r, t, b) end end
    -- called every frame with (time in s, ms since the last frame)
    function U.animate(fn) U.anims[#U.anims + 1] = fn end
    -- section title: cyan mark + title
    function U.section(str, l, t)
        U.box(CYAN, 1, l, l + 5, t + 3, t + 29)
        U.text(str, 26, WHITE, l + 16, l + 700, t, t + 32, U.LEFT, true)
    end

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
    -- white (or coloured) flash that fades out
    function U.flash(el, color)
        if not el then return end
        U.tint(el, color or WHITE)
        U.tween(0, 650, EASE.out, function(e) U.fade(el, 0.85 * (1 - e)) end)
    end
    return U
end

-- ------------------------------------------------------------------
-- common part: blue column (title, balance, page buttons, rotation timer, bonus),
-- status line, and the reveal shown when something is bought or won
-- ------------------------------------------------------------------
local function buildCommon(U)
    U.layer("common")
    local side = U.group()
    U.text("RANKED", 18, CYAN, -930, -660, 124, 146, U.LEFT, true)
    U.text("SHOP", 56, WHITE, -930, -660, 144, 204, U.LEFT, true)
    -- the brush line draws itself, then its cyan tail appears
    local brush = U.box(BRUSH, 1, -930, -929, 208, 214)
    local tail = U.box(CYAN, 1, -796, -772, 209, 213)
    U.tween(450, 500, EASE.out, function(e) U.move(brush, -930, -930 + math.max(1, 130 * e), 208, 214) end)
    U.tween(850, 300, EASE.out, function() end, tail)

    U.text("BALANCE", 15, GREY, -930, -660, 236, 254, U.LEFT)
    U.picture(-930, -896, 262, 296, STAR_ICON)
    U.rpText = U.text("0 RP", 40, GOLD, -888, -650, 256, 302, U.LEFT, true)
    U.shownRP = 0

    -- page buttons with a white mark and a light wash that glide to the open page
    U.navMark = U.box(WHITE, 1, -944, -936, 330, 376)
    U.navWash = U.box(WHITE, 0.10, -936, -652, 330, 376)
    U.navY, U.navT = 330, {}
    for k, def in ipairs({ { "shop", "SHOP" }, { "lottery", "LOTTERY" }, { "upgrade", "UPGRADE" } }) do
        local t = 330 + (k - 1) * 56
        U.navT[def[1]] = t
        local btn = U.button(-930, -656, t, t + 46, def[2], function() U.show(def[1]) end)
        if btn.Text then pcall(btn.Text.SetFontSize, btn.Text, 20) end
    end

    -- rotation: time left, a bar of the 8 h, the hours
    U.text("NEW ITEMS IN", 15, GREY, -930, -660, 520, 538, U.LEFT)
    U.timerText = U.text("", 30, CYAN, -930, -650, 540, 576, U.LEFT, true)
    U.box(LINE, 1, -930, -660, 586, 592)
    U.timerFill = U.box(CYAN, 1, -930, -929, 586, 592)
    U.text("NEW ITEMS EVERY 8H", 13, GREY, -930, -660, 600, 618, U.LEFT, true)
    U.text("00H  |  08H  |  16H  (UTC)", 13, DIM, -930, -660, 620, 638, U.LEFT)

    U.text("ACTIVE BONUS", 15, GREY, -930, -660, 680, 698, U.LEFT)
    U.bonusText = U.text("NONE", 22, DIM, -930, -650, 700, 730, U.LEFT, true)

    U.text("ITEMS GO STRAIGHT TO YOUR ARMORY", 13, GREY, -930, -660, 890, 930, U.LEFT)
    U.text("PROGRESSION MOD BY @SWATCOOKIE", 13, DIM, -930, -660, 944, 980, U.LEFT)
    U.ungroup()
    U.enter(side, 0, 520, -80, 0)

    U.status = U.text("", 20, GREY, -610, 930, 952, 980, U.CENTER, true)

    -- reveal: dark veil, a panel that opens from a line, the picture pops in, rings
    -- and sparks burst out in the rarity colour, the name rises in
    local F = {}
    F.layer = LUI.UIElement.new()
    F.layer:SetAnchorsAndPosition(0, 1, 0, 1, 0, 1920, 0, 1080)
    U.layers.common:addElement(F.layer)
    F.layer:SetAlpha(0, 0)
    local P = F.layer
    F.veil = U.box(BLACK, 0, -630, 950, 110, 990, P)
    F.panel = U.box(CARD, 0.96, CX - 790, CX + 790, 446, 454, P)
    F.lineT = U.box(GOLD, 1, CX - 790, CX + 790, 443, 446, P)
    F.lineB = U.box(GOLD, 1, CX - 790, CX + 790, 454, 457, P)
    F.bursts = { U.disc(GOLD, 0, CX - 30, CX + 30, 370, 430, P), U.disc(GOLD, 0, CX - 30, CX + 30, 370, 430, P) }
    F.pic = U.picture(CX - 36, CX + 36, 364, 436, nil, P)
    F.sparks = {}
    for k = 1, 22 do F.sparks[k] = U.disc(GOLD, 0, CX - 4, CX + 4, 396, 404, P) end
    F.top = U.text("", 18, CYAN, CX - 760, CX + 760, 532, 556, U.CENTER, true, P)
    F.name = U.text("", 38, WHITE, CX - 760, CX + 760, 558, 602, U.CENTER, true, P)
    F.right = U.text("", 20, GOLD, CX - 760, CX + 760, 606, 632, U.CENTER, true, P)
    U.fx = F

    -- o = { top, name, color, image, right }
    function U.reveal(o)
        U.drop("fx")
        U.busy = true
        local color = o.color or GOLD
        pcall(F.layer.SetAlpha, F.layer, 1, 0)
        U.set(F.top, o.top or "", CYAN)
        U.set(F.name, o.name or "", WHITE)
        U.set(F.right, o.right or "", color)
        U.setPicture(F.pic, o.image)
        -- (a red miss may have hidden or tinted these)
        U.tint(F.veil, BLACK)
        U.fade(F.panel, 0.96); U.fade(F.lineT, 1); U.fade(F.lineB, 1)
        for _, el in ipairs({ F.lineT, F.lineB, F.bursts[1], F.bursts[2] }) do U.tint(el, color) end
        for k, d in ipairs(F.sparks) do U.tint(d, (k % 3 == 0) and WHITE or color) end
        U.tween(0, 240, EASE.out, function(e) U.fade(F.veil, 0.8 * e) end, nil, "fx")
        -- the panel opens from a thin line (half height 4 -> 190)
        U.tween(60, 420, EASE.out, function(e)
            local h = 4 + 186 * e
            U.move(F.panel, CX - 790, CX + 790, 450 - h, 450 + h)
            U.move(F.lineT, CX - 790, CX + 790, 450 - h - 3, 450 - h)
            U.move(F.lineB, CX - 790, CX + 790, 450 + h, 450 + h + 3)
        end, nil, "fx")
        -- two rings of light grow and fade behind the picture
        for k, b in ipairs(F.bursts) do
            U.tween(200 + (k - 1) * 200, 950, EASE.out, function(e)
                local s = 30 + 560 * e
                U.move(b, CX - s, CX + s, 400 - s, 400 + s)
                U.fade(b, (e <= 0) and 0 or 0.45 * (1 - e))
            end, nil, "fx")
        end
        -- the picture pops in (a bit too big, then its size)
        U.tween(220, 600, EASE.back, function(e)
            local s = 120 * (0.25 + 0.75 * e)
            U.move(F.pic, CX - s, CX + s, 400 - s, 400 + s)
        end, nil, "fx")
        -- sparks fly out in every direction and fade
        for k, d in ipairs(F.sparks) do
            local a = (k / #F.sparks) * 2 * math.pi + math.random() * 0.25
            local dist = 230 + math.random() * 300
            local size = 3 + math.random(0, 4)
            U.tween(260, 850 + math.random(0, 350), EASE.quart, function(e)
                local x, y = CX + math.cos(a) * dist * e, 400 + math.sin(a) * dist * e * 0.6
                U.move(d, x - size, x + size, y - size, y + size)
                U.fade(d, (e <= 0) and 0 or (e < 0.6 and 1 or (1 - e) / 0.4))
            end, nil, "fx")
        end
        -- the texts rise in, one after the other
        for k, el in ipairs({ F.top, F.name, F.right }) do
            local t, b = ({ 532, 558, 606 })[k], ({ 556, 602, 632 })[k]
            U.tween(380 + k * 90, 420, EASE.out, function(e)
                local y = 30 * (1 - e)
                U.move(el, CX - 760, CX + 760, t + y, b + y)
                U.fade(el, e)
            end, nil, "fx")
        end
        -- then everything fades out
        U.tween(2200, 380, EASE.out, function(e)
            pcall(F.layer.SetAlpha, F.layer, 1 - e, 0)
            if e >= 1 then U.busy = false end
        end, nil, "fx")
    end
    -- a miss: the screen flashes red once
    function U.miss()
        U.tint(F.veil, RED)
        pcall(F.layer.SetAlpha, F.layer, 1, 0)
        for _, el in ipairs({ F.panel, F.lineT, F.lineB, F.pic, F.top, F.name, F.right, F.bursts[1], F.bursts[2] }) do U.fade(el, 0) end
        for _, d in ipairs(F.sparks) do U.fade(d, 0) end
        U.drop("fx")
        U.tween(0, 600, EASE.out, function(e)
            U.fade(F.veil, 0.35 * (1 - e))
            if e >= 1 then U.tint(F.veil, BLACK); pcall(F.layer.SetAlpha, F.layer, 0, 0) end
        end, nil, "fx")
    end

    -- every frame: balance counts to the saved value, rotation timer
    U.animate(function(t, dt)
        local target = U.rpTarget or U.shownRP
        local diff = target - U.shownRP
        if math.abs(diff) >= 0.5 then
            U.shownRP = U.shownRP + diff * math.min(1, dt / 140)
            if math.abs(target - U.shownRP) < 0.5 then U.shownRP = target end
            U.set(U.rpText, math.floor(U.shownRP + 0.5) .. " RP", diff < 0 and RED or GREEN)
            U.rpColored = true
        elseif U.rpColored then
            U.set(U.rpText, target .. " RP", GOLD)
            U.rpColored = false
        end
        local sec = now()
        if sec ~= U.lastSec then
            U.lastSec = sec
            local left = ROTATION - sec % ROTATION
            U.set(U.timerText, clock(left))
            U.move(U.timerFill, -930, -930 + math.max(1, 270 * (1 - left / ROTATION)), 586, 592)
            -- a new rotation while the tab is open: new items, cards pop in again
            if U.rot and rotation() ~= U.rot and U.page then pcall(U.show, U.page) end
        end
    end)
end

-- ------------------------------------------------------------------
-- SHOP page
-- ------------------------------------------------------------------
-- one item card; big = the featured one
local function itemCard(U, slot, l, r, t, b, big)
    U.group()
    local card = { id = 0, quality = 0, slot = slot }
    local cx = (l + r) / 2
    card.frame = U.box(RARITY[0][2], 1, l, r, t, b)
    U.box(CARD, 1, l + 2, r - 2, t + 2, b - 2)
    local picB = big and 300 or 136
    card.back = U.box(RARITY[0][2], 0.22, l + 2, r - 2, t + 2, t + picB)
    if big then
        card.glow = U.disc(RARITY[0][2], 0.25, cx - 150, cx + 150, t + 20, t + 300)
        card.image = U.picture(l + 22, r - 22, t + 44, t + 292, nil)
        U.box(CYAN, 1, l + 12, l + 132, t + 12, t + 38)
        U.text("FEATURED", 16, 0x10204A, l + 12, l + 132, t + 15, t + 36, U.CENTER, true)
        card.kind = U.text("", 15, WHITE, r - 220, r - 12, t + 16, t + 36, U.RIGHT, true)
        card.rarity = U.text("", 18, GREY, l + 14, r - 14, t + 304, t + 328, U.LEFT, true)
        card.name = U.text("", 24, WHITE, l + 14, r - 14, t + 330, t + 382, U.LEFT, true)
        card.price = U.text("", 30, GOLD, l + 14, l + 180, b - 50, b - 12, U.LEFT, true)
        -- a light sweeps over the picture every 3 s
        card.shine = U.box(WHITE, 0, l + 2, l + 3, t + 2, t + picB)
        card.shineL, card.shineR, card.shineB = l + 2, r - 2, t + picB
    else
        card.image = U.picture(l + 40, r - 40, t + 24, t + 132, nil)
        U.text(SLOTS[slot].label, 12, WHITE, l + 10, r - 10, t + 6, t + 22, U.LEFT, true)
        card.rarity = U.text("", 13, GREY, l + 10, r - 10, t + 138, t + 156, U.LEFT, true)
        card.name = U.text("", 16, WHITE, l + 10, r - 10, t + 158, t + 200, U.LEFT, true)
        card.price = U.text("", 22, GOLD, l + 10, l + 124, b - 40, b - 8, U.LEFT, true)
    end
    local bl, br, bt, bb = big and (r - 196) or (l + 128), big and (r - 14) or (r - 8), big and (b - 52) or (b - 42), big and (b - 10) or (b - 8)
    U.button(bl, br, bt, bb, "", function()
        if U.busy or card.id <= 0 or card.owned then return end
        local res, err = Act.buyItem(card.id)
        if not res then U.say(err, RED) return end
        local rarity = RARITY[res.quality] or RARITY[0]
        U.flash(card.flash, rarity[2])
        U.reveal({ top = "ITEM UNLOCKED", name = Case.name(res.id), color = rarity[2], image = Case.image(res.id),
            right = rarity[1] .. "   |   -" .. res.paid .. " RP" })
        U.say("BOUGHT: " .. Case.name(res.id) .. "  -" .. res.paid .. " RP", GREEN)
        U.refresh()
    end)
    card.btnText = U.text("BUY", big and 22 or 18, WHITE, bl, br, bt + (big and 9 or 7), bb - 6, U.CENTER, true)
    -- owned: the card darkens and gets a stamp
    card.dim = U.box(BLACK, 0, l, r, t, b)
    card.stamp = U.text("", big and 30 or 22, GREEN, l, r, t + (b - t) / 2 - 20, t + (b - t) / 2 + 16, U.CENTER, true)
    card.flash = U.box(WHITE, 0, l, r, t, b)
    U.ungroup()
    U.animate(function(tt)
        if card.id > 0 and card.quality >= 3 then U.fade(card.frame, 0.55 + 0.45 * math.sin(tt * 3 + slot)) end
        if card.shine then
            local w = card.shineR - card.shineL
            local x = card.shineL - 90 + (w + 180) * ((tt % 3.2) / 3.2)
            local sl, sr = math.max(card.shineL, x), math.min(card.shineR, x + 90)
            if sr > sl then U.move(card.shine, sl, sr, t + 2, card.shineB); U.fade(card.shine, 0.16)
            else U.fade(card.shine, 0) end
            U.fade(card.glow, 0.18 + 0.12 * math.sin(tt * 2))
        end
    end)
    return card
end

local function bonusCard(U, bonus, l, r, t, b)
    U.group()
    local card = {}
    U.box(bonus.color, 1, l, r, t, b)
    U.box(CARD, 1, l + 2, r - 2, t + 2, b - 2)
    U.box(bonus.color, 1, l + 2, l + 10, t + 2, b - 2)
    U.picture(r - 70, r - 16, t + 14, t + 62, SR_ICON)
    U.text(bonus.name, 24, WHITE, l + 24, r - 80, t + 12, t + 42, U.LEFT, true)
    U.text(bonus.info, 14, GREY, l + 24, r - 14, t + 46, t + 64, U.LEFT)
    card.state = U.text("", 13, GREY, l + 24, r - 14, t + 68, t + 86, U.LEFT, true)
    U.text(bonus.price .. " RP", 26, GOLD, l + 24, l + 180, b - 46, b - 12, U.LEFT, true)
    U.button(r - 196, r - 14, b - 52, b - 10, "", function()
        if U.busy then return end
        local res, err = Act.buyBonus(bonus)
        if not res then U.say(err, RED) return end
        U.flash(card.flash, bonus.color)
        U.reveal({ top = "BONUS ACTIVE FOR YOUR NEXT RANKED MATCH", name = bonus.name, color = bonus.color,
            image = SR_ICON, right = "-" .. res.paid .. " RP" })
        U.say(bonus.name .. " ACTIVE  -" .. res.paid .. " RP", GREEN)
        U.refresh()
    end)
    card.btnText = U.text("BUY", 22, WHITE, r - 196, r - 14, b - 43, b - 16, U.CENTER, true)
    card.flash = U.box(WHITE, 0, l, r, t, b)
    U.ungroup()
    return card
end

local function buildShop(U)
    U.layer("shop")
    U.section("ITEMS OF THE ROTATION", -610, 124)
    U.text("12 ITEMS + 1 FEATURED  |  NEW ITEMS EVERY 8H", 16, GREY, 300, 930, 132, 154, U.RIGHT, true)
    U.items = {}
    -- left: featured item, then the 2 bonuses
    U.items[FEATURED] = itemCard(U, FEATURED, -620, -250, 172, 600, true)
    U.bonusCards = {}
    for k, bonus in ipairs(BONUSES) do
        local t = 612 + (k - 1) * 170
        U.bonusCards[k] = bonusCard(U, bonus, -620, -250, t, t + 158)
    end
    -- right: 3 rows of 4 (camos, blueprints, skins)
    for slot = 1, FEATURED - 1 do
        local c, rw = (slot - 1) % 4, math.floor((slot - 1) / 4)
        local l = -234 + c * 294
        local t = 172 + rw * 260
        U.items[slot] = itemCard(U, slot, l, l + 282, t, t + 252, false)
    end
end

-- ------------------------------------------------------------------
-- LOTTERY page: a reel that scrolls and slows down on the prize
-- ------------------------------------------------------------------
local function buildLottery(U)
    U.layer("lottery")
    U.section("RANKED LOTTERY", -610, 124)
    U.text("ONE DRAW = " .. LOTTERY_PRICE .. " RP  |  ITEM ALREADY OWNED = " .. LOTTERY_REFUND .. " RP BACK", 16, GREY, 100, 930, 132, 154, U.RIGHT, true)

    -- odds: one bar cut by rarity, and a legend under it
    local x = -610
    for q = 0, 5 do
        local w = 1540 * LOTTERY_ODDS[q] / 100
        U.box(RARITY[q][2], 1, x, x + math.max(2, w - 2), 176, 200)
        x = x + w
        local l = -610 + q * 257
        U.disc(RARITY[q][2], 1, l, l + 14, 214, 228)
        U.text(RARITY[q][1] .. "  " .. LOTTERY_ODDS[q] .. "%", 16, RARITY[q][2], l + 22, l + 250, 210, 232, U.LEFT, true)
    end

    local pool = {}
    local bridge = Case.bridge()
    if bridge then
        local rows = Case.rows(bridge)
        local step = math.max(1, math.floor(#rows / 40))
        for k = 1, #rows, step do
            local item = rows[k].item
            local image = item and Case.image(item.id)
            if image then pool[#pool + 1] = { image = image, quality = tonumber(item.quality) or 0 } end
        end
    end

    -- the centre: a glow and a frame that stay; the cards run under the frame
    local RT, RB, W, N = 270, 510, 236, 9
    local glow = U.disc(GOLD, 0.15, CX - 200, CX + 200, RT - 80, RB + 80)
    local slots = {}
    for k = 1, N do
        local s = {}
        s.body = U.box(CARD, 1, CX - 110, CX + 110, RT, RB)
        s.back = U.box(EDGE, 0.25, CX - 110, CX + 110, RT, RB - 8)
        s.pic = U.picture(CX - 100, CX + 100, RT + 20, RB - 28, nil)
        s.bar = U.box(GREY, 1, CX - 110, CX + 110, RB - 8, RB)
        s.j = nil
        slots[k] = s
    end
    local frame = {}
    for k, r in ipairs({ { -124, 124, RT - 14, RT - 10 }, { -124, 124, RB + 10, RB + 14 }, { -124, -120, RT - 14, RB + 14 }, { 120, 124, RT - 14, RB + 14 } }) do
        frame[k] = U.box(GOLD, 1, CX + r[1], CX + r[2], r[3], r[4])
    end
    local prizeName = U.text("", 40, WHITE, -610, 930, 536, 586, U.CENTER, true)
    local prizeInfo = U.text("", 22, GREY, -610, 930, 588, 620, U.CENTER, true)

    local L = { o = 0, spin = false }
    local function itemAt(j)
        if L.prizeJ and j == L.prizeJ then return L.prize end
        if #pool == 0 then return nil end
        return pool[(j * 7 + 3) % #pool + 1]
    end
    -- places the 9 cards for the reel offset L.o (card j sits at CX + j * W - o)
    local function paint()
        local first = math.floor(L.o / W) - 4
        for j = first, first + N - 1 do
            local s = slots[j % N + 1]
            local x = CX + j * W - L.o
            local d = math.abs(x - CX)
            local a = math.max(0, math.min(1, 1 - (d - 2.2 * W) / (1.3 * W)))
            if s.j ~= j then
                s.j = j
                local it = itemAt(j)
                U.setPicture(s.pic, it and it.image)
                U.tint(s.bar, it and (RARITY[it.quality] or RARITY[0])[2] or GREY)
                s.picOn = it ~= nil
            end
            U.move(s.body, x - 110, x + 110, RT, RB); U.fade(s.body, a)
            U.move(s.back, x - 110, x + 110, RT, RB - 8); U.fade(s.back, 0.25 * a)
            U.move(s.pic, x - 100, x + 100, RT + 20, RB - 28); U.fade(s.pic, s.picOn and a or 0)
            U.move(s.bar, x - 110, x + 110, RB - 8, RB); U.fade(s.bar, a)
        end
    end
    paint()

    U.lotteryBtn = U.button(CX - 210, CX + 210, 650, 730, "PLAY - " .. LOTTERY_PRICE .. " RP", function()
        if L.spin or U.busy then return end
        local res, err = Act.lottery()
        if not res then U.set(prizeInfo, err, RED) return end
        L.res = res
        L.prize = { image = Case.image(res.id), quality = res.quality }
        L.prizeJ = math.floor(L.o / W) + 34
        L.from, L.spin = L.o, true
        for _, s in ipairs(slots) do s.j = nil end
        U.set(prizeName, ""); U.set(prizeInfo, "")
        for _, f in ipairs(frame) do U.tint(f, GOLD) end
        -- 34 cards in 4.6 s, fast then slowing down onto the prize
        U.tween(0, 4600, EASE.quart, function(e)
            L.o = L.from + (L.prizeJ * W - L.from) * e
            if e < 1 then return end
            L.spin = false
            local rarity = RARITY[res.quality] or RARITY[0]
            local name = Case.name(res.id)
            for _, f in ipairs(frame) do U.tint(f, rarity[2]) end
            U.tint(glow, rarity[2])
            U.set(prizeName, name, rarity[2])
            if res.duplicate then
                U.set(prizeInfo, rarity[1] .. "  |  ALREADY OWNED: +" .. LOTTERY_REFUND .. " RP BACK", GOLD)
                U.reveal({ top = "DUPLICATE  -  " .. LOTTERY_REFUND .. " RP BACK", name = name, color = rarity[2], image = L.prize.image, right = rarity[1] })
            else
                U.set(prizeInfo, rarity[1] .. "  |  NEW ITEM", WHITE)
                U.reveal({ top = "LOTTERY WIN", name = name, color = rarity[2], image = L.prize.image, right = rarity[1] })
            end
            U.refresh()
        end, nil, "reel")
    end)
    U.text("THE CARD THAT STOPS IN THE FRAME IS YOURS", 15, GREY, -610, 930, 744, 764, U.CENTER)

    U.animate(function(t, dt)
        -- idle: the reel drifts slowly
        if not L.spin then L.o = L.o + dt * 0.05 end
        if U.page == "lottery" then paint() end
        U.fade(glow, 0.12 + 0.08 * math.sin(t * 2.5))
    end)
end

-- ------------------------------------------------------------------
-- UPGRADE page: 4 items (rare..ultra), 5 stakes, a bar with the win zone
-- ------------------------------------------------------------------
local function buildUpgrade(U)
    U.layer("upgrade")
    U.section("1. PICK THE ITEM YOU WANT", -610, 124)
    local G = { sel = 1, stake = 3, spin = false }
    U.upgrade = G
    G.cards = {}
    for k = 1, 4 do
        local l = -620 + (k - 1) * 392
        local r = l + 376
        local q = k + 1
        U.group()
        local card = { id = 0, quality = q }
        card.frame = U.box(RARITY[q][2], 1, l, r, 172, 420)
        U.box(CARD, 1, l + 2, r - 2, 174, 418)
        card.back = U.box(RARITY[q][2], 0.22, l + 2, r - 2, 174, 290)
        card.image = U.picture(l + 100, r - 100, 180, 286, nil)
        U.text(RARITY[q][1], 15, RARITY[q][2], l + 12, r - 12, 294, 314, U.LEFT, true)
        card.name = U.text("", 18, WHITE, l + 12, r - 12, 316, 342, U.LEFT, true)
        U.text("VALUE " .. PRICES[q] .. " RP", 15, GREY, l + 12, r - 12, 344, 364, U.LEFT)
        card.sel = U.box(CYAN, 0, l, r, 420, 426)
        U.button(l + 12, r - 12, 372, 410, "SELECT", function()
            if G.spin or U.busy then return end
            G.sel = k
            U.flash(card.flash, CYAN)
            U.refresh()
        end)
        card.flash = U.box(WHITE, 0, l, r, 172, 420)
        U.ungroup()
        U.animate(function(tt)
            if k == G.sel then U.fade(card.sel, 0.6 + 0.4 * math.sin(tt * 5)) end
        end)
        G.cards[k] = card
    end

    U.section("2. STAKE YOUR RP", -610, 440)
    G.summary = U.text("", 18, WHITE, 200, 930, 446, 472, U.RIGHT, true)
    G.stakeMarks = {}
    for k, stake in ipairs(STAKES) do
        local l = -620 + (k - 1) * 314
        G.stakeMarks[k] = U.box(CYAN, 0, l, l + 298, 526, 530)
        U.button(l, l + 298, 484, 524, stake .. " RP", function()
            if G.spin or U.busy then return end
            G.stake = k
            U.refresh()
        end)
    end

    -- the bar: 0..100 % over 1440 px, green zone = chance, the marker stops on the roll
    local BL, BW = CX - 720, 1440
    U.box(EDGE, 1, BL - 4, BL + BW + 4, 556, 610)
    U.box(LINE, 1, BL, BL + BW, 560, 606)
    G.zone = U.box(GREEN, 0.85, BL, BL + 1, 560, 606)
    G.marker = U.box(WHITE, 1, BL - 4, BL + 4, 546, 620)
    G.chanceText = U.text("", 44, GREEN, CX - 400, CX + 400, 626, 676, U.CENTER, true)
    U.text("CHANCE = STAKE / ITEM VALUE  (MAX " .. MAX_CHANCE .. "%)", 15, GREY, CX - 400, CX + 400, 678, 698, U.CENTER)
    G.result = U.text("", 24, WHITE, -610, 930, 816, 850, U.CENTER, true)

    local function place(pct, shake)
        local x = BL + BW * math.max(0, math.min(100, pct)) / 100 + (shake or 0)
        U.move(G.marker, x - 4, x + 4, 546, 620)
    end
    place(0)

    U.button(CX - 210, CX + 210, 720, 800, "UPGRADE", function()
        if G.spin or U.busy then return end
        local card = G.cards[G.sel]
        if not card or card.id <= 0 then return end
        local res, err = Act.upgrade(card.id, STAKES[G.stake])
        if not res then U.set(G.result, err, RED) return end
        -- where the marker stops: inside the zone on a win, outside on a loss
        local land
        if res.won then land = math.max(1, res.chance * (0.1 + 0.8 * math.random()))
        else land = res.chance + (100 - res.chance) * (0.1 + 0.8 * math.random()) end
        G.spin = true
        U.set(G.result, "")
        -- 3 passes over the bar in 4.2 s, slowing down, ending on `land`
        U.tween(0, 4200, EASE.out, function(e)
            local pos = ((300 + land) * e) % 200
            place(pos <= 100 and pos or 200 - pos)
            if e < 1 then return end
            place(land)
            G.spin = false
            local rarity = RARITY[res.quality] or RARITY[0]
            local name = Case.name(res.id)
            if res.won then
                U.flash(card.flash, rarity[2])
                U.set(G.result, "UPGRADE SUCCESS: " .. name, GREEN)
                U.reveal({ top = "UPGRADE SUCCESS", name = name, color = rarity[2], image = Case.image(res.id),
                    right = rarity[1] .. "   |   " .. res.chance .. "% CHANCE" })
            else
                U.set(G.result, "MISSED - " .. res.paid .. " RP LOST", RED)
                U.miss()
                -- the marker shakes and the bar flashes red
                U.tween(0, 520, EASE.out, function(s) place(land, math.sin(s * 40) * 14 * (1 - s)) end)
                U.flash(G.zone, RED)
                U.tween(650, 1, EASE.out, function(s) if s >= 1 then U.tint(G.zone, GREEN); U.fade(G.zone, 0.85) end end)
            end
            U.refresh()
        end, nil, "upg")
    end)
end

-- ------------------------------------------------------------------
-- refresh + page switch
-- ------------------------------------------------------------------
local function refreshShop(U, bridge, rot)
    local ids = Case.pick(ITEMS_FILE, "BR95RS2", rot, #SLOTS, function(slot, item)
        local s = SLOTS[slot]
        return s.kinds[item.kind] and (tonumber(item.quality) or 0) >= (s.minQ or 0)
    end)
    for slot, card in ipairs(U.items) do
        local id = ids and ids[slot] or 0
        if id > 0 and bridge then
            local kind, quality = Case.info(bridge, id)
            local rarity = RARITY[quality] or RARITY[0]
            card.id, card.quality = id, quality
            U.tint(card.frame, rarity[2]); U.tint(card.back, rarity[2])
            if quality < 3 then U.fade(card.frame, 1) end
            if card.glow then U.tint(card.glow, rarity[2]) end
            if card.kind then U.set(card.kind, KIND_LABEL[kind] or "") end
            U.set(card.rarity, rarity[1], rarity[2])
            U.set(card.name, Case.name(id), WHITE)
            U.set(card.price, (PRICES[quality] or 500) .. " RP")
            U.setPicture(card.image, Case.image(id))
            card.owned = Case.owns(bridge, id)
            U.set(card.btnText, card.owned and "OWNED" or "BUY", card.owned and GREY or WHITE)
            U.fade(card.dim, card.owned and 0.55 or 0)
            U.set(card.stamp, card.owned and "ALREADY OWNED" or "")
        else
            card.id = 0
            U.set(card.rarity, "")
            U.set(card.name, bridge and ((slot == FEATURED) and "NO FEATURED ITEM THIS ROTATION" or "SOLD OUT")
                or "PROGRESSION MOD NOT LOADED", GREY)
            U.set(card.price, "")
            U.setPicture(card.image, nil)
            U.set(card.btnText, "-")
            U.fade(card.dim, 0); U.set(card.stamp, "")
        end
    end
    local active = readBonus()
    for k, card in ipairs(U.bonusCards) do
        local mine = (BONUSES[k].kind == active)
        U.set(card.state, mine and "ACTIVE - WAITING FOR YOUR NEXT RANKED MATCH" or (active ~= 0 and "ANOTHER BONUS IS ACTIVE" or ""), mine and GREEN or GREY)
        U.set(card.btnText, mine and "ACTIVE" or "BUY", mine and GREEN or WHITE)
    end
    local name, color = "NONE", DIM
    for _, bonus in ipairs(BONUSES) do if bonus.kind == active then name, color = bonus.name, bonus.color end end
    U.set(U.bonusText, name, color)
end

local function refreshUpgrade(U, bridge, rot)
    local G = U.upgrade
    local ids = Case.pick(UPGRADE_FILE, "BR95RU2", rot, 4, function(slot, item) return tonumber(item.quality) == slot + 1 end)
    for k, card in ipairs(G.cards) do
        local id = ids and ids[k] or 0
        card.id = (bridge and id) or 0
        if k ~= G.sel then U.fade(card.sel, 0) end
        if card.id > 0 then
            U.set(card.name, Case.name(id) .. (Case.owns(bridge, id) and "  (OWNED)" or ""), WHITE)
            U.setPicture(card.image, Case.image(id))
        else
            U.set(card.name, bridge and "NONE THIS ROTATION" or "PROGRESSION MOD NOT LOADED", GREY)
            U.setPicture(card.image, nil)
        end
    end
    for k in ipairs(STAKES) do U.fade(G.stakeMarks[k], (k == G.stake) and 1 or 0) end
    local quality = G.sel + 1
    local chance = Act.chance(STAKES[G.stake], quality)
    U.set(G.chanceText, chance .. "%")
    U.set(G.summary, "STAKE " .. STAKES[G.stake] .. " RP  |  VALUE " .. PRICES[quality] .. " RP")
    -- the green zone grows / shrinks smoothly to the new chance
    local from = G.zoneW or 1
    local to = math.max(1, 1440 * chance / 100)
    G.zoneW = to
    U.drop("zone")
    U.tween(0, 300, EASE.out, function(e)
        local w = from + (to - from) * e
        U.move(G.zone, CX - 720, CX - 720 + w, 560, 606)
    end, nil, "zone")
end

local function build(menu, controller)
    pcall(math.randomseed, now())
    local root = LUI.UIElement.new(); root.id = MENU
    root:SetAnchorsAndPosition(0.5, 0.5, 0, 1, -960, 960, 0, 1080)
    local U = newUI(root, controller)

    -- background behind every page: key art under a purple tint, blue column on the left
    local back = LUI.UIElement.new()
    back:SetAnchorsAndPosition(0, 1, 0, 1, 0, 1920, 0, 1080)
    root:addElement(back)
    U.P = back
    U.picture(-630, 950, 110, 990, BACK_ART)
    U.fade(U.box(MAIN, 0.86, -630, 950, 110, 990), 0.86)
    U.box(SIDE, 0.96, -950, -640, 110, 990)
    local top = U.box(GOLD, 1, -630, 950, 110, 113)
    U.animate(function(t) U.fade(top, 0.7 + 0.3 * math.sin(t * 3)) end)

    buildShop(U)
    buildLottery(U)
    buildUpgrade(U)
    buildCommon(U)   -- last: drawn over the pages (column, reveal)

    function U.say(str, color) U.set(U.status, str, color or WHITE) end

    function U.refresh()
        local bridge = Case.bridge()
        local rot = rotation()
        U.rot = rot
        U.rpTarget = readRP()
        pcall(refreshShop, U, bridge, rot)
        pcall(refreshUpgrade, U, bridge, rot)
    end

    function U.show(name)
        U.page = name
        U.drop("page")
        for pageName, layer in pairs(U.layers) do
            if pageName ~= "common" then pcall(layer.SetAlpha, layer, (pageName == name) and 1 or 0, (pageName == name) and 220 or 0) end
        end
        for pageName, list in pairs(U.buttons) do
            if pageName ~= "common" then
                for _, entry in ipairs(list) do
                    local t = (pageName == name) and entry.t or 4000
                    pcall(entry.btn.SetAnchorsAndPosition, entry.btn, 0.5, 0.5, 0, 1, entry.l, entry.r, t, t + (entry.b - entry.t))
                end
            end
        end
        -- the cards of the page pop in one after the other
        for k, g in ipairs(U.groups[name] or {}) do U.enter(g, 60 + k * 45, 460, 0, 40, EASE.back, "page") end
        -- the nav mark glides to the page button
        local from, to = U.navY, U.navT[name] or U.navY
        U.drop("mark")
        U.tween(0, 280, EASE.out, function(e)
            U.navY = from + (to - from) * e
            U.move(U.navMark, -944, -936, U.navY, U.navY + 46)
            U.move(U.navWash, -936, -652, U.navY, U.navY + 46)
        end, nil, "mark")
        pcall(U.refresh)
    end

    -- one 16 ms timer for everything that moves (timed with the clock)
    local last, sinceRefresh = nil, 0
    root:registerEventHandler("br95_rshop_frame", function()
        local ms = os.clock() * 1000
        local dt = last and math.max(0, math.min(100, ms - last)) or 16
        last = ms
        U.runTweens(ms)
        local t = ms / 1000
        for _, fn in ipairs(U.anims) do pcall(fn, t, dt) end
        sinceRefresh = sinceRefresh + dt
        if sinceRefresh > 10000 then sinceRefresh = 0; pcall(U.refresh) end
    end)
    root:addElement(LUI.UITimer.new({ interval = 16, event = "br95_rshop_frame", disposable = false, eventTarget = root }))

    U.show("shop")
    U.say("ITEMS, LOTTERY AND UPGRADE USE YOUR RANKED POINTS", GREY)
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
        pcall(function() msg:setText("RANKED SHOP ERROR: " .. tostring(result)) end)
        root:addElement(msg)
        return root
    end)

    local data = MAINMENUTABS.TabData
    if not data[MENU] then
        local sound = type(data.CustomizeMenu) == "table" and data.CustomizeMenu.menuSound or nil
        data[MENU] = { menuName = MENU, name = "RANKED SHOP", menuSound = sound,
            -- shown in the ranked playlist lobby (same test as br95_ranked_official_post.lua)
            isHidden = function() return (readText(IO .. "br95_mode.txt") or ""):match("^BR95M1|(%d)") ~= "1" end,
            isDisabled = function() return false end,
            onFocusCallback = function() return true end, menuSpecificCallback = function() end }
    end

    -- same lobbies as the RANKED tab (br95_ranked_post.lua), right after it
    for _, lobby in ipairs({ "WarzonePrivateMatchLobby", "PrivateMatchLobby", "MPSystemLinkLobby" }) do
        local layout = MAINMENUTABS.Layouts[lobby]
        if type(layout) == "table" then
            local present, after = false, nil
            for i, entry in ipairs(layout) do
                if entry == MENU then present = true end
                if entry == "BR95RankedMenu" then after = i end
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
