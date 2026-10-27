-- BR95 MP Shop: a MP SHOP tab in the multiplayer lobbies. Spend Ranked Points (RP,
-- earned at the end of every multiplayer match by br95_ranked_core_post.lua) on:
--   - FEATURED PACKS: 3 packs with random discounts and a random picture, new ones
--     every 24h (UTC), one purchase each
--   - ITEM SHOP: 6 items (camos, weapon blueprints, operator skins) with their own
--     picture and rarity, new ones every 4 hours
--   - a LOTTERY: 2 free draws per 24h, each gives a random item
--   - a Ranked Case and an RP -> CP exchange (always available)
-- Cases come from the LocalProgression mod (global LocalProgressionRankBridge): the
-- shop credits the CP a case costs there, then opens a real case with bridge.openCase.
-- That only works in menus (never in a match). Item pictures come from the game
-- itself (LOOT.GetItemImageByID).
-- Same tab mechanism as the other BR95 tabs. The two pages (shop / lottery) are two
-- layers created with the tab: the buttons of the hidden page are moved off screen.
-- Everything is wrapped in pcall: if something is missing the tab is simply not
-- added, the game keeps working. Fully restart the game after changes.
if BR95MPShop then return end
local state = { installed = false }
BR95MPShop = state

local RP_FILE = "jupiter/IO/br95_rp.txt"                        -- BR95P1|rp|END
local DAILY_FILE = "jupiter/IO/br95_mpshop_packs.txt"           -- BR95D1|day|bought=1,3|END
local ITEMS_FILE = "jupiter/IO/br95_mpshop_items.txt"           -- BR95M2|window|id,id,..|bought=1,3|END
local LOTTERY_FILE = "jupiter/IO/br95_mpshop_lottery.txt"       -- BR95M3|time,time|END
local POOL_FILE = "jupiter/LocalProgression/local_case_pool.txt"
local MENU = "BR95MPShopMenu"

local ITEM_REFRESH = 4 * 3600                  -- new items every 4 hours
local LOTTERY_USES, LOTTERY_WINDOW = 2, 86400  -- 2 draws per 24 hours

-- the 6 items: 2 camos, 2 weapon blueprints, 2 operator skins
local ITEM_SLOTS = {
    { label = "CAMO",          kinds = { CAMO = true } },
    { label = "CAMO",          kinds = { CAMO = true } },
    { label = "WEAPON",        kinds = { WEAPON = true } },
    { label = "WEAPON",        kinds = { WEAPON = true } },
    { label = "OPERATOR SKIN", kinds = { OPERATOR_SKIN = true, OPERATOR = true } },
    { label = "OPERATOR SKIN", kinds = { OPERATOR_SKIN = true, OPERATOR = true } },
}
local ITEM_PRICES = { [0] = 150, [1] = 250, [2] = 400, [3] = 650, [4] = 1000, [5] = 1500 }

local CASE_RP = 300                 -- one Ranked Case
local EXCHANGE_RP, EXCHANGE_CP = 100, 300

-- rarity = quality of the case mod (0 common .. 5 ultra)
local RARITY = { [0] = { "COMMON", 0xB0B0B0 }, [1] = { "UNCOMMON", 0x6BD66B }, [2] = { "RARE", 0x4FA3FF },
    [3] = { "EPIC", 0xB061FF }, [4] = { "LEGENDARY", 0xFFB020 }, [5] = { "ULTRA", 0xFF4060 } }

-- featured pack pool: cases = cases opened, min = guaranteed rarity of the first case
local PACKS = {
    { name = "STARTER PACK",   cases = 2, min = nil, price = 550,  color = 0x6BD66B },
    { name = "TRIPLE PACK",    cases = 3, min = nil, price = 800,  color = 0x4FA3FF },
    { name = "RARE PACK",      cases = 2, min = 2,   price = 750,  color = 0x4FA3FF },
    { name = "EPIC PACK",      cases = 1, min = 3,   price = 700,  color = 0xB061FF },
    { name = "EPIC BUNDLE",    cases = 3, min = 3,   price = 1200, color = 0xB061FF },
    { name = "LEGENDARY PACK", cases = 1, min = 4,   price = 1500, color = 0xFFB020 },
    { name = "MEGA PACK",      cases = 5, min = 3,   price = 1700, color = 0xFF4060 },
}
local DISCOUNTS = { 0, 10, 15, 20, 25, 30 }     -- random, never more than 30 %

local WHITE, GREY, DARK, PANEL, BLACK = 0xFFFFFF, 0x8A8A8A, 0x141414, 0x1E1E1E, 0x000000
local GREEN, GOLD, RED = 0x6BD66B, 0xFFD166, 0xE04040

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
    local rp = text and text:match("^BR95P1|(%d+)|END")
    return tonumber(rp) or 0
end

local function writeRP(rp)
    return writeText(RP_FILE, "BR95P1|" .. math.max(0, math.floor(rp)) .. "|END")
end

-- ------------------------------------------------------------------
-- daily rotation
-- ------------------------------------------------------------------

local function now()
    local ok, t = pcall(os.time)
    return ok and tonumber(t) or 0
end

local function today() return math.floor(now() / 86400) end

-- own small generator seeded by the day: same packs all day, never touches
-- math.random (the case mod uses it)
local function dailyPacks(day)
    local seed = (day * 7919 + 104729) % 2147483647
    local function rand(n)
        seed = (seed * 48271) % 2147483647
        return seed % n + 1
    end
    local order = {}
    for k = 1, #PACKS do order[k] = k end
    for k = #order, 2, -1 do
        local j = rand(k)
        order[k], order[j] = order[j], order[k]
    end
    local offers = {}
    for slot = 1, 3 do
        local pack = PACKS[order[slot]]
        local off = DISCOUNTS[rand(#DISCOUNTS)]
        offers[slot] = { pack = pack, off = off, price = math.floor(pack.price * (100 - off) / 1000 + 0.5) * 10 }
    end
    return offers
end

local function readDaily(day)
    local bought = {}
    local text = readText(DAILY_FILE)
    if not text then return bought end
    local fileDay, list = text:match("^BR95D1|(%d+)|bought=([%d,]*)|END")
    if list and tonumber(fileDay) == day then
        for slot in list:gmatch("%d+") do bought[tonumber(slot)] = true end
    end
    return bought
end

local function writeDaily(day, bought)
    local list = {}
    for slot = 1, 3 do if bought[slot] then list[#list + 1] = tostring(slot) end end
    return writeText(DAILY_FILE, "BR95D1|" .. day .. "|bought=" .. table.concat(list, ",") .. "|END")
end

local function countdown()
    local left = 86400 - now() % 86400
    return string.format("NEW PACKS IN %dH %02dM", math.floor(left / 3600), math.floor(left % 3600 / 60))
end

-- ------------------------------------------------------------------
-- case mod bridge
-- ------------------------------------------------------------------

local function caseBridge()
    local bridge = rawget(_G, "LocalProgressionRankBridge")
    if type(bridge) ~= "table" or type(bridge.grantLocalCP) ~= "function" or type(bridge.getLocalCP) ~= "function"
        or type(bridge.openCase) ~= "function" then
        return nil
    end
    return bridge
end

local function readCP()
    local bridge = caseBridge()
    if not bridge then return nil end
    local ok, cp = pcall(bridge.getLocalCP)
    return ok and tonumber(cp) or nil
end

local function itemName(id)
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

-- The case mod draws a rarity with the first random() call (rarities in order
-- 0..5, each with its share), then an item with the second. To guarantee a
-- minimum rarity the first value is moved above the share of lower rarities.
local function guaranteedRandom(bridge, minQuality)
    if not minQuality or type(bridge.caseOdds) ~= "function" then return nil end
    local ok, rows = pcall(bridge.caseOdds)
    if not ok or type(rows) ~= "table" then return nil end
    local share, seen = {}, {}
    for _, row in ipairs(rows) do
        local q = row.item and tonumber(row.item.quality)
        if q and not seen[q] then seen[q] = true; share[q] = tonumber(row.tierChance) or 0 end
    end
    local low, high = 0, 0
    for q = 0, 5 do
        if share[q] then
            if q < minQuality then low = low + share[q] end
            high = high + share[q]
        end
    end
    if high <= 0 or low >= high then return nil end
    low = low / high
    local calls = 0
    return function()
        calls = calls + 1
        if calls == 1 then return math.min(0.999999, low + math.random() * (1 - low)) end
        return math.random()
    end
end

-- picture of each daily pack: a real item it can give (skin or blueprint of
-- the guaranteed rarity, epic for packs without one), different every day
local VISUAL = { OPERATOR_SKIN = true, OPERATOR = true, WEAPON = true }
local function packPreviews(day, offers)
    local previews = {}
    local bridge = caseBridge()
    if not bridge or type(bridge.caseOdds) ~= "function" or type(LOOT) ~= "table"
        or type(LOOT.GetItemImageByID) ~= "function" then
        return previews
    end
    local ok, rows = pcall(bridge.caseOdds)
    if not ok or type(rows) ~= "table" then return previews end
    local used = {}
    for slot, offer in ipairs(offers) do
        local minQuality = offer.pack.min or 3
        local candidates = {}
        for _, row in ipairs(rows) do
            local item = row.item
            if item and VISUAL[item.kind] and (tonumber(item.quality) or 0) >= minQuality and not used[item.id] then
                candidates[#candidates + 1] = item
            end
        end
        if #candidates > 0 then
            local item = candidates[(day * 31 + slot * 977) % #candidates + 1]
            local good, image = pcall(LOOT.GetItemImageByID, item.id)
            if good and type(image) == "string" and image ~= "" then
                used[item.id] = true
                previews[slot] = { image = image, name = itemName(item.id), quality = tonumber(item.quality) or 0 }
            end
        end
    end
    return previews
end

-- ------------------------------------------------------------------
-- backgrounds: a loading screen behind the page, a calling card banner on
-- each daily pack, both from the game catalog and different every day
-- ------------------------------------------------------------------

local CATALOG_FILE = "jupiter/LocalProgression/local_cosmetic_catalog.txt"
local catalogCache = {}

local function catalogIds(kind)
    if catalogCache[kind] then return catalogCache[kind] end
    local ids = {}
    local text = readText(CATALOG_FILE)
    if text then
        for id in text:gmatch("\n(%d+)|" .. kind .. "|") do ids[#ids + 1] = tonumber(id) end
    end
    catalogCache[kind] = ids
    return ids
end

local function imageOf(id)
    if not id or type(LOOT) ~= "table" or type(LOOT.GetItemImageByID) ~= "function" then return nil end
    local ok, image = pcall(LOOT.GetItemImageByID, id)
    if ok and type(image) == "string" and image ~= "" then return image end
    return nil
end

-- n-th image of the day for that kind (skips ids without an image)
local function dailyImage(kind, day, n)
    local ids = catalogIds(kind)
    if #ids == 0 then return nil end
    local start = (day * 2654435761 + n * 40503) % #ids
    for k = 0, 9 do
        local image = imageOf(ids[(start + k * 97) % #ids + 1])
        if image then return image end
    end
    return nil
end

-- ------------------------------------------------------------------
-- daily items: one exact item bought through a case
-- ------------------------------------------------------------------

local function ownsItem(bridge, id)
    local store = type(bridge.caseStore) == "table" and bridge.caseStore.store
    return type(store) == "table" and type(store.owned) == "table" and store.owned[id] == true
end

-- The case draw is: 1st random() -> rarity (rarities 0..5 in order, each its
-- share), 2nd random() -> item (items of that rarity in pool file order, each
-- its weight). Returns a maker of a random() that lands on `id`, or nil.
-- Always checked with bridge.sampleCaseItems (free) before paying.
local function exactRandom(bridge, id)
    if type(bridge.caseOdds) ~= "function" then return nil end
    local ok, rows = pcall(bridge.caseOdds)
    if not ok or type(rows) ~= "table" then return nil end
    local chanceOf, qualityOf, share = {}, {}, {}
    for _, row in ipairs(rows) do
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

local LP_STATE_FILE = "jupiter/IO/br95_lp_state.txt"      -- BR95LP|0|END = progression mod off (read at game start)
-- the switch only works when the two loader files of the progression mod carry the BR95 check
local function lpPatched()
    local text = readText("jupiter/Assets/Lua/ui/generated/widgets/frontend/mp/cas/weaponlevelbar.lua")
    return text ~= nil and text:find("LP_OFF", 1, true) ~= nil
end

local function lpEnabled()
    local text = readText(LP_STATE_FILE)
    return not (text and text:match("^BR95LP|0"))
end

-- ------------------------------------------------------------------
-- items of the current 4-hour window: 6 items, chosen once among items not owned
-- yet and saved, so everybody who opens the shop in that window sees the same ones
-- ------------------------------------------------------------------

local function parseSet(list)
    local set = {}
    for n in (list or ""):gmatch("%d+") do set[tonumber(n)] = true end
    return set
end

local function itemInfo(bridge, id)
    local ok, rows = pcall(bridge.caseOdds)
    if ok and type(rows) == "table" then
        for _, row in ipairs(rows) do
            if row.item and row.item.id == id then return row.item.kind, tonumber(row.item.quality) or 0 end
        end
    end
    return nil, 0
end

local function windowItems(window)
    local text = readText(ITEMS_FILE) or ""
    local fileWindow, list, bought = text:match("^BR95M2|(%d+)|([%d,]*)|bought=([%d,]*)|END")
    if list and tonumber(fileWindow) == window then
        local ids = {}
        for id in list:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
        if #ids == #ITEM_SLOTS then return ids, parseSet(bought) end
    end

    local bridge = caseBridge()
    if not bridge or type(bridge.caseOdds) ~= "function" then return nil end
    local ok, rows = pcall(bridge.caseOdds)
    if not ok or type(rows) ~= "table" or #rows == 0 then return nil end
    local ids, used = {}, {}
    for slot, def in ipairs(ITEM_SLOTS) do
        local candidates = {}
        for _, row in ipairs(rows) do
            local item = row.item
            if item and def.kinds[item.kind] and not used[item.id] and not ownsItem(bridge, item.id) then
                candidates[#candidates + 1] = item.id
            end
        end
        table.sort(candidates)
        local id = (#candidates > 0) and candidates[(window * 7919 + slot * 104729) % #candidates + 1] or 0
        ids[slot] = id
        used[id] = true
    end
    writeText(ITEMS_FILE, "BR95M2|" .. window .. "|" .. table.concat(ids, ",") .. "|bought=|END")
    return ids, {}
end

local function saveBought(window, ids, bought)
    local list = {}
    for slot = 1, #ITEM_SLOTS do if bought[slot] then list[#list + 1] = tostring(slot) end end
    writeText(ITEMS_FILE, "BR95M2|" .. window .. "|" .. table.concat(ids, ",") .. "|bought=" .. table.concat(list, ",") .. "|END")
end

-- ------------------------------------------------------------------
-- lottery: 2 draws per rolling 24 hours, each one opens a free random case
-- ------------------------------------------------------------------

local function readLottery()
    local list = {}
    local body = (readText(LOTTERY_FILE) or ""):match("^BR95M3|([%d,]*)|END")
    local t = now()
    if body then
        for v in body:gmatch("%d+") do
            v = tonumber(v)
            if t - v < LOTTERY_WINDOW then list[#list + 1] = v end
        end
    end
    table.sort(list)
    return list
end

local function writeLottery(list)
    return writeText(LOTTERY_FILE, "BR95M3|" .. table.concat(list, ",") .. "|END")
end

-- seconds until the next ticket, nil when a ticket is available
local function lotteryWait(list)
    if #list < LOTTERY_USES then return nil end
    return math.max(0, list[#list - LOTTERY_USES + 1] + LOTTERY_WINDOW - now())
end

local function lotteryDraw()
    local bridge = caseBridge()
    if not bridge then return nil, "CASE MOD NOT FOUND - OPEN ITS CASES MENU ONCE" end
    local casePrice = tonumber(bridge.casePrice) or 1000
    local ok, granted = pcall(bridge.grantLocalCP, casePrice)
    if not ok or granted ~= true then return nil, "THE LOTTERY ONLY WORKS IN THE MENU" end
    local opened, success, drop = pcall(bridge.openCase, nil)
    if not opened or success ~= true or type(drop) ~= "table" then
        return nil, "CP ADDED - OPEN A CASE FROM THE CASES MENU"
    end
    return drop
end

-- pictures that scroll on the lottery reel: real items of the case pool
local function reelPictures()
    local images = {}
    local bridge = caseBridge()
    if not bridge or type(bridge.caseOdds) ~= "function" then return images end
    local ok, rows = pcall(bridge.caseOdds)
    if not ok or type(rows) ~= "table" or #rows == 0 then return images end
    local step = math.max(1, math.floor(#rows / 40))
    for k = 1, #rows, step do
        local item = rows[k].item
        local image = item and imageOf(item.id)
        if image then images[#images + 1] = { image = image, quality = tonumber(item.quality) or 0 } end
    end
    return images
end

local function itemQuality(bridge, id)
    local ok, rows = pcall(bridge.caseOdds)
    if ok and type(rows) == "table" then
        for _, row in ipairs(rows) do
            if row.item and row.item.id == id then return tonumber(row.item.quality) or 0 end
        end
    end
    return 0
end

-- returns the drop, or nil + message. Nothing is paid unless the free dry run
-- lands on the item.
local function buyItem(id, price)
    local bridge = caseBridge()
    if not bridge or type(bridge.sampleCaseItems) ~= "function" then return nil, "CASE MOD NOT FOUND - OPEN ITS CASES MENU ONCE" end
    if ownsItem(bridge, id) then return nil, "ALREADY OWNED" end
    local maker = exactRandom(bridge, id)
    if not maker then return nil, "ITEM NOT AVAILABLE" end
    local ok, sample = pcall(bridge.sampleCaseItems, 1, maker())
    if not ok or type(sample) ~= "table" or not sample[1] or sample[1].id ~= id then
        return nil, "ITEM NOT AVAILABLE (CHECK FAILED, NOTHING PAID)"
    end
    local rp = readRP()
    if rp < price then return nil, "NOT ENOUGH RP" end
    if not writeRP(rp - price) then return nil, "SAVE ERROR" end
    local casePrice = tonumber(bridge.casePrice) or 1000
    local good, granted = pcall(bridge.grantLocalCP, casePrice)
    if not good or granted ~= true then
        writeRP(rp)
        return nil, "CASES ONLY WORK IN THE MENU"
    end
    local opened, success, drop = pcall(bridge.openCase, maker())
    if not opened or success ~= true or type(drop) ~= "table" then
        return nil, "CP ADDED - OPEN A CASE FROM THE CASES MENU"
    end
    return drop
end

-- spends RP, credits the CP of `cases` cases, opens them. Returns the drops,
-- or nil + message. RP are given back if the CP credit fails.
local function buyCases(price, cases, minQuality)
    local bridge = caseBridge()
    if not bridge then return nil, "CASE MOD NOT FOUND - OPEN ITS CASES MENU ONCE" end
    local rp = readRP() -- fresh value: a match may have ended meanwhile
    if rp < price then return nil, "NOT ENOUGH RP" end
    if not writeRP(rp - price) then return nil, "SAVE ERROR" end
    local casePrice = tonumber(bridge.casePrice) or 1000
    local ok, granted = pcall(bridge.grantLocalCP, casePrice * cases)
    if not ok or granted ~= true then
        writeRP(rp)
        return nil, "CASES ONLY WORK IN THE MENU"
    end
    local drops = {}
    for k = 1, cases do
        local random = (k == 1) and guaranteedRandom(bridge, minQuality) or nil
        local good, opened, drop = pcall(bridge.openCase, random)
        if not good or opened ~= true or type(drop) ~= "table" then
            -- the CP left stay in the case mod: open them from its own menu
            drops.unopened = cases - k + 1
            break
        end
        drops[#drops + 1] = drop
    end
    return drops
end

local function exchange()
    local bridge = caseBridge()
    if not bridge then return false, "CASE MOD NOT FOUND - OPEN ITS CASES MENU ONCE" end
    local rp = readRP()
    if rp < EXCHANGE_RP then return false, "NOT ENOUGH RP" end
    if not writeRP(rp - EXCHANGE_RP) then return false, "SAVE ERROR" end
    local ok, granted = pcall(bridge.grantLocalCP, EXCHANGE_CP)
    if not ok or granted ~= true then
        writeRP(rp)
        return false, "CASES ONLY WORK IN THE MENU"
    end
    return true
end

local function font(text, size, bold)
    if FONTS and FONTS.GetFont then
        local f = bold and FONTS.PrimaryBold or FONTS.SecondaryRegular
        if f and f.File then pcall(text.SetFont, text, FONTS.GetFont(f.File)) end
    end
    if text.SetFontSize then pcall(text.SetFontSize, text, size) end
end

local ACCENT = 0xD9262E
local LINE = 0x2E2E2E

local function clock(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%02dH %02dM", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

local function build(menu, controller)
    local root = LUI.UIElement.new(); root.id = MENU
    root:SetAnchorsAndPosition(0.5, 0.5, 0, 1, -960, 960, 0, 1080)   -- 1920 box centered on the tab area
    local LEFT = LUI.Alignment and LUI.Alignment.Left
    local RIGHT = LUI.Alignment and LUI.Alignment.Right
    local CENTER = LUI.Alignment and LUI.Alignment.Center

    -- two layers (pages); everything is created into P, the layer being built
    local function newLayer()
        local layer = LUI.UIElement.new()
        layer:SetAnchorsAndPosition(0, 1, 0, 1, 0, 1920, 0, 1080)
        root:addElement(layer)
        return layer
    end
    local layers = { shop = newLayer(), lottery = newLayer() }
    local P, building = layers.shop, "shop"
    local buttons = { shop = {}, lottery = {} }
    local anims = {}
    local page = "shop"

    local function box(color, alpha, l, r, t, b)
        local child = LUI.UIImage.new()
        child:SetRGB(color, 0); child:SetAlpha(alpha, 0)
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        P:addElement(child); return child
    end
    local function text(str, size, color, l, r, t, b, align, bold)
        local child = LUI.UIText.new()
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        font(child, size, bold)
        if child.SetAlignment and LUI.Alignment then child:SetAlignment(align or LEFT) end
        child:SetRGB(color or WHITE, 0)
        child:setText(str)
        P:addElement(child); return child
    end
    -- a picture from the game (material name); invisible until it has an image
    local function picture(l, r, t, b, image)
        local child = LUI.UIImage.new()
        child:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        P:addElement(child)
        if image then
            pcall(function() child:setImage(RegisterMaterial(image), 0) end)
        else
            child:SetAlpha(0, 0)
        end
        return child
    end
    local function setPicture(child, image)
        if not child then return end
        if image then
            local ok = pcall(function() child:setImage(RegisterMaterial(image), 0) end)
            pcall(child.SetAlpha, child, ok and 1 or 0, 0)
        else
            pcall(child.SetAlpha, child, 0, 0)
        end
    end
    local function button(l, r, t, b, label, action)
        local btn = MenuBuilder.BuildRegisteredType("GenericButton", { controllerIndex = controller })
        btn:SetAnchorsAndPosition(0.5, 0.5, 0, 1, l, r, t, b)
        P:addElement(btn)
        if btn.Text then pcall(btn.Text.setText, btn.Text, label) end
        local mine = building
        btn:addEventHandler("button_action", function()
            if page ~= mine then return end
            pcall(action)
        end)
        buttons[mine][#buttons[mine] + 1] = { btn = btn, l = l, r = r, t = t, b = b }
        return btn
    end
    local function setText(element, str, color)
        if not element then return end
        pcall(element.setText, element, str)
        if color then pcall(element.SetRGB, element, color, 0) end
    end
    local function setLabel(btn, str)
        if btn and btn.Text then pcall(btn.Text.setText, btn.Text, str) end
    end
    local function tint(element, color)
        if element then pcall(element.SetRGB, element, color, 0) end
    end
    local function fade(element, value)
        if element then pcall(element.SetAlpha, element, value, 0) end
    end
    local function animate(fn) anims[#anims + 1] = fn end

    local day = today()
    local window = math.floor(now() / ITEM_REFRESH)
    local offers = dailyPacks(day)
    local bought = readDaily(day)
    local refreshAll

    -- ===================================================================
    -- SHOP PAGE
    -- ===================================================================
    -- background: a loading screen of the day behind a dark veil, red top line
    box(BLACK, 1, -800, 800, 110, 990)
    local bg = picture(-800, 800, 110, 990, dailyImage("LOAD_SCREEN", day, 0))
    box(BLACK, 0.8, -800, 800, 110, 990)
    local topLine = box(ACCENT, 1, -800, 800, 110, 114)
    animate(function(t) fade(topLine, 0.7 + 0.3 * math.sin(t * 3)) end)

    text("THANKS @SWATCOOKIE FOR HELPING", 12, GREY, -270, 30, 138, 154, LEFT)
    text("WITH THE DEVELOPMENT :)", 12, GREY, -270, 30, 154, 170, LEFT)
    text("MP SHOP", 54, WHITE, -770, 200, 118, 176, LEFT, true)
    text("EARN RP IN MULTIPLAYER: 2 PER KILL  |  +1 PER ASSIST  |  WIN +40 RP", 17, GREY, -770, 300, 178, 200, LEFT)

    -- balance
    box(PANEL, 1, 330, 770, 122, 198)
    box(GOLD, 1, 330, 336, 122, 198)
    local coin = box(GOLD, 1, 356, 392, 140, 176)
    box(BLACK, 1, 364, 384, 148, 168)
    text("BALANCE", 15, GREY, 408, 600, 126, 148, LEFT)
    local rpText = text("", 38, GOLD, 408, 760, 148, 194, LEFT, true)
    animate(function(t) fade(coin, 0.75 + 0.25 * math.sin(t * 4)) end)

    -- lottery button (opens the lottery page)
    box(PANEL, 1, 40, 310, 122, 198)
    local lotteryGlow = box(GOLD, 1, 40, 46, 122, 198)
    animate(function(t) fade(lotteryGlow, 0.5 + 0.5 * math.sin(t * 5)) end)
    local lotteryInfo = text("", 14, GREY, 56, 300, 168, 194, LEFT)
    local lotteryBtn = button(52, 300, 126, 166, "LOTTERY", function()
        page = "lottery"
        state.showPage(page)
    end)

    -- section headers
    local function section(str, l, t)
        box(ACCENT, 1, l, l + 5, t + 3, t + 27)
        text(str, 24, WHITE, l + 16, l + 400, t, t + 30, LEFT, true)
    end
    section("FEATURED PACKS", -770, 212)
    local packTimer = text("", 17, GOLD, -420, -22, 216, 240, RIGHT, true)
    section("ITEM SHOP", 20, 212)
    local itemTimer = text("", 17, GOLD, 400, 756, 216, 240, RIGHT, true)

    -- FEATURED PACKS: 3 big cards, random picture, discount ribbon, moving shine
    local packCards = {}
    local PACK_KINDS = { "PLAYERCARD", "LOAD_SCREEN", "PLAYERCARD" }
    for slot, offer in ipairs(offers) do
        local pack = offer.pack
        local l = -770 + (slot - 1) * 254
        local r = l + 240
        local t = 252
        local card = {}
        local frame = box(pack.color, 1, l, r, t, t + 536)
        box(DARK, 1, l + 3, r - 3, t + 3, t + 533)
        picture(l + 3, r - 3, t + 3, t + 333, dailyImage(PACK_KINDS[slot], day, slot * 3 + 1))
        box(pack.color, 0.2, l + 3, r - 3, t + 3, t + 333)
        box(BLACK, 0.45, l + 3, r - 3, t + 273, t + 333)
        local shine = box(WHITE, 0.16, l + 3, l + 33, t + 3, t + 333)
        animate(function(tt)
            local x = l + 3 + ((tt * 90 + slot * 60) % (r - l - 36))
            pcall(shine.SetAnchorsAndPosition, shine, 0.5, 0.5, 0, 1, x, x + 30, t + 3, t + 333)
            fade(frame, 0.7 + 0.3 * math.sin(tt * 3 + slot))
        end)
        if offer.off > 0 then
            local ribbon = box(RED, 1, l + 10, l + 112, t + 14, t + 48)
            text("-" .. offer.off .. "%", 24, WHITE, l + 10, l + 112, t + 17, t + 47, CENTER, true)
            animate(function(tt) tint(ribbon, (math.floor(tt * 2) % 2 == 0) and RED or 0xFF6A4A) end)
        else
            box(pack.color, 1, l + 10, l + 112, t + 14, t + 48)
            text("DAILY", 18, BLACK, l + 10, l + 112, t + 19, t + 47, CENTER, true)
        end
        text(pack.name, 24, WHITE, l + 14, r - 14, t + 344, t + 376, LEFT, true)
        text(pack.cases .. (pack.cases > 1 and " CASES" or " CASE"), 20, WHITE, l + 14, r - 14, t + 378, t + 402, LEFT)
        if pack.min then
            local rarity = RARITY[pack.min]
            text("1ST: " .. rarity[1] .. "+", 16, rarity[2], l + 14, r - 14, t + 404, t + 426, LEFT, true)
        else
            text("RANDOM RARITY", 15, GREY, l + 14, r - 14, t + 404, t + 426, LEFT)
        end
        if offer.off > 0 then text("WAS " .. pack.price .. " RP", 16, GREY, l + 14, r - 14, t + 430, t + 452, LEFT) end
        text(offer.price .. " RP", 34, GOLD, l + 14, r - 14, t + 448, t + 488, LEFT, true)
        card.button = button(l + 14, r - 14, t + 490, t + 528, "BUY", function()
            if bought[slot] then return end
            local drops, err = buyCases(offer.price, pack.cases, pack.min)
            if not drops then state.result("CAN'T BUY", err, RED)
            else
                bought[slot] = true
                writeDaily(day, bought)
                state.drops(drops)
            end
            refreshAll()
        end)
        packCards[slot] = card
    end

    -- ITEM SHOP: 6 cards, each with the picture and the rarity of its item
    local itemCards = {}
    for slot, def in ipairs(ITEM_SLOTS) do
        local c, rw = (slot - 1) % 3, math.floor((slot - 1) / 3)
        local l = 20 + c * 250
        local r = l + 236
        local t = 252 + rw * 278
        local card = { id = 0, price = 0, quality = 0 }
        card.frame = box(RARITY[0][2], 1, l, r, t, t + 262)
        box(DARK, 1, l + 3, r - 3, t + 3, t + 259)
        card.back = box(RARITY[0][2], 0.22, l + 3, r - 3, t + 3, t + 152)
        card.image = picture(l + 22, r - 22, t + 8, t + 148, nil)
        card.kind = text((def.label == "OPERATOR SKIN") and "SKIN" or def.label, 13, WHITE, l + 10, r - 10, t + 6, t + 24, LEFT, true)
        card.rarity = text("", 15, GREY, l + 10, r - 10, t + 155, t + 176, LEFT, true)
        card.name = text("", 17, WHITE, l + 10, r - 10, t + 178, t + 206, LEFT, true)
        card.price = text("", 25, GOLD, l + 10, l + 120, t + 214, t + 250, LEFT, true)
        card.button = button(l + 118, r - 10, t + 212, t + 250, "", function()
            if card.id <= 0 then return end
            local items = state.items
            if items and items.bought[slot] then return end
            local drop, err = buyItem(card.id, card.price_value)
            if not drop then state.result("CAN'T BUY", err, RED)
            else
                if items then items.bought[slot] = true; saveBought(items.window, items.ids, items.bought) end
                state.drops({ drop })
            end
            refreshAll()
        end)
        card.btnText = text("BUY", 20, WHITE, l + 118, r - 10, t + 219, t + 246, CENTER, true)
        animate(function(tt)
            if card.quality >= 3 then fade(card.frame, 0.55 + 0.45 * math.sin(tt * 3 + slot)) else fade(card.frame, 1) end
        end)
        itemCards[slot] = card
    end

    -- last result bar
    local withSwitch = lpPatched()
    local barRight = withSwitch and 390 or 770
    box(PANEL, 1, -770, barRight, 800, 850)
    local resultTitle = text("LAST PURCHASE", 14, GREY, -750, 0, 803, 823, LEFT)
    local resultText = text("BUY SOMETHING TO SEE WHAT YOU GET HERE.", 21, WHITE, -750, barRight - 20, 822, 848, LEFT, true)

    -- switch of the progression mod (the mod by @swatcookie): off = the mod is simply not loaded
    -- at the next start, nothing is deleted, the saves stay in jupiter/IO/local_*
    local lpText
    if withSwitch then
        box(PANEL, 1, 410, 770, 800, 850)
        box(GOLD, 1, 410, 416, 800, 850)
        button(424, 764, 804, 846, "", function()
            local on = lpEnabled()
            writeText(LP_STATE_FILE, "BR95LP|" .. (on and "0" or "1") .. "|END")
            if on then state.result("PROGRESSION MOD", "TURNED OFF. RESTART THE GAME. YOUR PROGRESSION IS KEPT.", GOLD)
            else state.result("PROGRESSION MOD", "TURNED ON. RESTART THE GAME.", GOLD) end
            refreshAll()
        end)
        lpText = text("", 15, WHITE, 424, 764, 811, 839, CENTER, true)
    end

    -- always available
    local function simpleCard(l, r, name, info)
        local t = 864
        box(DARK, 1, l, r, t, t + 108)
        box(ACCENT, 1, l, l + 6, t, t + 108)
        text(name, 26, WHITE, l + 22, r - 20, t + 8, t + 40, LEFT, true)
        text(info, 16, GREY, l + 22, r - 20, t + 42, t + 64, LEFT)
        return button(l + 22, l + 300, t + 66, t + 102, "", function() end)
    end
    local caseBtn = simpleCard(-770, -270, "RANKED CASE", "1 RANDOM CASE  |  " .. CASE_RP .. " RP")
    local exchangeBtn = simpleCard(-250, 250, "RP TO CP", EXCHANGE_RP .. " RP = " .. EXCHANGE_CP .. " CP")
    do
        local t = 864
        box(DARK, 1, 270, 770, t, t + 108)
        box(GOLD, 1, 270, 276, t, t + 108)
        text("HOW IT WORKS", 22, WHITE, 292, 760, t + 8, t + 36, LEFT, true)
        text("PACKS CHANGE EVERY 24H, ITEMS EVERY 4H.", 15, GREY, 292, 760, t + 40, t + 60, LEFT)
        text("THE LOTTERY GIVES 2 FREE ITEMS EVERY 24H.", 15, GREY, 292, 760, t + 62, t + 82, LEFT)
        text("THIS SHOP USE PROGRESSION MOD BY @SWATCOOKIE", 13, GOLD, 292, 760, t + 86, t + 104, LEFT)
    end
    caseBtn:addEventHandler("button_action", function()
        if page ~= "shop" then return end
        pcall(function()
            local drops, err = buyCases(CASE_RP, 1, nil)
            if not drops then state.result("CAN'T BUY", err, RED) else state.drops(drops) end
            refreshAll()
        end)
    end)
    exchangeBtn:addEventHandler("button_action", function()
        if page ~= "shop" then return end
        pcall(function()
            local ok, err = exchange()
            if ok then state.result("EXCHANGE", "+" .. EXCHANGE_CP .. " CP", GREEN)
            else state.result("CAN'T EXCHANGE", err, RED) end
            refreshAll()
        end)
    end)

    function state.result(title, str, color)
        setText(resultTitle, title)
        setText(resultText, str, color or WHITE)
    end
    function state.drops(drops)
        local parts, top = {}, 0
        for _, drop in ipairs(drops) do
            local q = tonumber(drop.quality) or 0
            if q > top then top = q end
            local rarity = RARITY[q] or RARITY[0]
            parts[#parts + 1] = rarity[1] .. " " .. itemName(drop.id) .. (drop.duplicate and " (DUP)" or "")
        end
        local str = table.concat(parts, "  /  ")
        if drops.unopened then
            str = str .. (str ~= "" and "  /  " or "") .. drops.unopened .. " CASE(S) LEFT IN THE CASES MENU"
        end
        state.result("YOU GOT", str, (RARITY[top] or RARITY[0])[2])
    end

    -- ===================================================================
    -- LOTTERY PAGE
    -- ===================================================================
    P, building = layers.lottery, "lottery"
    box(BLACK, 1, -800, 800, 110, 990)
    picture(-800, 800, 110, 990, dailyImage("LOAD_SCREEN", day, 5))
    box(BLACK, 0.86, -800, 800, 110, 990)
    local lotLine = box(GOLD, 1, -800, 800, 110, 114)
    animate(function(t) fade(lotLine, 0.7 + 0.3 * math.sin(t * 3)) end)
    text("LOTTERY", 54, WHITE, -770, 300, 118, 176, LEFT, true)
    text("2 FREE DRAWS EVERY 24 HOURS. EACH DRAW GIVES A RANDOM ITEM.", 17, GREY, -770, 400, 178, 200, LEFT)

    -- tickets
    text("TICKETS", 15, GREY, 40, 200, 126, 148, LEFT)
    local tickets = {}
    for k = 1, LOTTERY_USES do
        local l = 40 + (k - 1) * 64
        box(GOLD, 1, l, l + 56, 150, 190)
        tickets[k] = box(DARK, 0.9, l + 4, l + 52, 154, 186)
    end
    local ticketTimer = text("", 17, GOLD, 180, 520, 156, 186, LEFT, true)
    local backBtn = button(560, 770, 126, 190, "BACK TO SHOP", function()
        page = "shop"
        state.showPage(page)
    end)

    -- reel: 5 pictures, the one in the middle is the prize
    local reelPool = reelPictures()
    local slots = {}
    for k = 1, 5 do
        local l = -590 + (k - 1) * 240
        local mid = (k == 3)
        local frame = box(mid and GOLD or LINE, 1, l - (mid and 8 or 0), l + 220 + (mid and 8 or 0), 300 - (mid and 8 or 0), 520 + (mid and 8 or 0))
        box(DARK, 1, l, l + 220, 300, 520)
        local back = box(0x333333, 0.4, l, l + 220, 300, 520)
        local pic = picture(l + 10, l + 210, 310, 510, nil)
        slots[k] = { frame = frame, back = back, pic = pic, mid = mid }
    end
    text("v", 40, GOLD, -30, 30, 252, 298, CENTER, true)
    text("^", 40, GOLD, -30, 30, 524, 570, CENTER, true)

    local prizeName = text("", 42, WHITE, -770, 770, 580, 636, CENTER, true)
    local prizeInfo = text("", 22, GREY, -770, 770, 638, 676, CENTER, true)
    local drawBtn
    local lotteryNote = text("", 18, GREY, -770, 770, 830, 862, CENTER)

    local reelPos, spinning, spinTick, finalDrop, finalImage = 0, false, 0, nil, nil
    local function slotImage(k)
        if spinning == "done" and k == 3 and finalImage then return finalImage end
        if #reelPool == 0 then return nil end
        return reelPool[(reelPos + k - 1) % #reelPool + 1].image
    end
    local function paintReel()
        for k = 1, 5 do setPicture(slots[k].pic, slotImage(k)) end
    end
    paintReel()

    drawBtn = button(-210, 210, 700, 780, "DRAW", function()
        if spinning == true then return end
        local uses = readLottery()
        if lotteryWait(uses) then
            setText(prizeInfo, "NO TICKET LEFT. NEXT ONE IN " .. clock(lotteryWait(uses)), RED)
            return
        end
        local drop, err = lotteryDraw()
        if not drop then
            setText(prizeInfo, err, RED)
            return
        end
        uses[#uses + 1] = now()
        writeLottery(uses)
        finalDrop = drop
        finalImage = imageOf(drop.id)
        spinning, spinTick = true, 0
        setText(prizeName, "")
        setText(prizeInfo, "")
        refreshAll()
    end)

    -- reel animation: fast, slowing down, then the prize in the middle
    local function reelTick(tt)
        if spinning == true then
            spinTick = spinTick + 1
            local step = 1 + math.floor(spinTick / 14)
            if spinTick % step == 0 then reelPos = reelPos + 1; paintReel() end
            for k = 1, 5 do fade(slots[k].back, 0.25 + 0.2 * math.sin(tt * 20 + k)) end
            if spinTick >= 56 then
                spinning = "done"
                paintReel()
                local q = tonumber(finalDrop.quality) or 0
                local rarity = RARITY[q] or RARITY[0]
                setText(prizeName, itemName(finalDrop.id), rarity[2])
                setText(prizeInfo, rarity[1] .. (finalDrop.duplicate and "  |  DUPLICATE" or "  |  NEW") , WHITE)
                tint(slots[3].frame, rarity[2])
                state.result("LOTTERY", rarity[1] .. " " .. itemName(finalDrop.id), rarity[2])
            end
        elseif spinning == "done" then
            local q = tonumber(finalDrop.quality) or 0
            fade(slots[3].frame, 0.6 + 0.4 * math.sin(tt * 8))
            tint(slots[3].back, (RARITY[q] or RARITY[0])[2])
            fade(slots[3].back, 0.2 + 0.15 * math.sin(tt * 6))
        else
            if math.floor(tt * 4) % 6 == 0 and math.floor(tt * 4) ~= (state.lastIdle or -1) then
                state.lastIdle = math.floor(tt * 4)
                reelPos = reelPos + 1; paintReel()
            end
        end
    end
    animate(reelTick)

    -- ===================================================================
    -- refresh, page switch, tick
    -- ===================================================================
    refreshAll = function()
        setText(rpText, tostring(readRP()) .. " RP")
        do
            local on, loaded = lpEnabled(), caseBridge() ~= nil
            local label
            if on and loaded then label = "PROGRESSION MOD: ON  -  CLICK TO TURN OFF"
            elseif (not on) and (not loaded) then label = "PROGRESSION MOD: OFF  -  CLICK TO TURN ON"
            elseif not on then label = "OFF AFTER RESTART  -  CLICK TO CANCEL"
            else label = "ON AFTER RESTART  -  CLICK TO CANCEL" end
            setText(lpText, label, on and WHITE or GOLD)
        end
        setText(packTimer, "NEW PACKS IN " .. clock(86400 - now() % 86400))
        setText(itemTimer, "NEW ITEMS IN " .. clock(ITEM_REFRESH - now() % ITEM_REFRESH))
        for slot, card in ipairs(packCards) do
            setLabel(card.button, bought[slot] and "SOLD OUT" or "BUY")
        end
        setLabel(caseBtn, "OPEN - " .. CASE_RP .. " RP")
        setLabel(exchangeBtn, "EXCHANGE")

        local bridge = caseBridge()
        window = math.floor(now() / ITEM_REFRESH)
        local ids, boughtItems = windowItems(window)
        state.items = ids and { window = window, ids = ids, bought = boughtItems } or nil
        for slot, card in ipairs(itemCards) do
            local id = ids and ids[slot] or 0
            if id > 0 and bridge then
                local kind, quality = itemInfo(bridge, id)
                local rarity = RARITY[quality] or RARITY[0]
                card.id, card.quality = id, quality
                card.price_value = ITEM_PRICES[quality] or 500
                tint(card.frame, rarity[2]); tint(card.back, rarity[2])
                setText(card.rarity, rarity[1], rarity[2])
                setText(card.name, itemName(id))
                setText(card.price, card.price_value .. " RP")
                setPicture(card.image, imageOf(id))
                local owned = boughtItems[slot] or ownsItem(bridge, id)
                setText(card.btnText, owned and "OWNED" or "BUY")
            else
                card.id = 0
                setText(card.rarity, "")
                setText(card.name, lpEnabled() and "LOADING..." or "PROGRESSION MOD OFF", GREY)
                setText(card.price, "")
                setPicture(card.image, nil)
                setText(card.btnText, "-")
            end
        end

        local uses = readLottery()
        local wait = lotteryWait(uses)
        local left = LOTTERY_USES - #uses
        setText(lotteryInfo, wait and ("NEXT TICKET IN " .. clock(wait)) or (left .. " FREE DRAW" .. (left > 1 and "S" or "") .. " READY"), wait and GREY or GOLD)
        setLabel(lotteryBtn, "LOTTERY  (" .. left .. "/" .. LOTTERY_USES .. ")")
        for k = 1, LOTTERY_USES do tint(tickets[k], (k <= left) and GOLD or 0x222222) end
        setText(ticketTimer, wait and ("NEXT TICKET IN " .. clock(wait)) or "TICKET READY", wait and GREY or GOLD)
        setLabel(drawBtn, (spinning == true) and "..." or (wait and "NO TICKET" or "DRAW"))
        setText(lotteryNote, "THE PRIZE IS ADDED TO YOUR ITEMS RIGHT AWAY (CASE MOD).", GREY)
    end

    -- show one page: its layer visible, the buttons of the other page moved off screen
    function state.showPage(name)
        for pageName, layer in pairs(layers) do pcall(layer.SetAlpha, layer, (pageName == name) and 1 or 0, 0) end
        for pageName, list in pairs(buttons) do
            for _, entry in ipairs(list) do
                if pageName == name then
                    pcall(entry.btn.SetAnchorsAndPosition, entry.btn, 0.5, 0.5, 0, 1, entry.l, entry.r, entry.t, entry.b)
                else
                    pcall(entry.btn.SetAnchorsAndPosition, entry.btn, 0.5, 0.5, 0, 1, entry.l, entry.r, 4000, 4000 + (entry.b - entry.t))
                end
            end
        end
        pcall(refreshAll)
    end

    local tick = 0
    root:registerEventHandler("br95_mpshop_tick", function()
        tick = tick + 1
        local t = tick * 0.06
        for _, fn in ipairs(anims) do pcall(fn, t) end
        if tick % 250 == 0 then pcall(refreshAll) end
    end)
    root:addElement(LUI.UITimer.new({ interval = 60, event = "br95_mpshop_tick", disposable = false, eventTarget = root }))

    state.showPage("shop")
    return root
end

local function trace(msg)
    pcall(function()
        local f = io.open("jupiter/IO/br95_mpshop_trace.txt", "a")
        if f then f:write(os.date("%H:%M:%S") .. " " .. msg .. "\n"); f:close() end
    end)
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
        msg:SetAnchorsAndPosition(0.5, 0.5, 0, 1, -770, 770, 300, 420)
        pcall(function() msg:setText("MP SHOP ERROR: " .. tostring(result)) end)
        root:addElement(msg)
        return root
    end)
    trace("registered")

    local data = MAINMENUTABS.TabData
    if not data[MENU] then
        local sound = type(data.CustomizeMenu) == "table" and data.CustomizeMenu.menuSound or nil
        data[MENU] = { menuName = MENU, name = "MP SHOP", menuSound = sound,
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
    if DebugPrint then pcall(DebugPrint, "[BR95MPShop] tab installed") end
    return true
end

local function tryInstall()
    local ok, err = pcall(install)
    if not ok then
        state.error = tostring(err)
        if DebugPrint then pcall(DebugPrint, "[BR95MPShop] error: " .. state.error) end
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