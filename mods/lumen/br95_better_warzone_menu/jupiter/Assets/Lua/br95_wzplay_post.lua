-- BR95 Warzone play menu: the official horizontal Warzone menu (GameMenuWidget) as the
-- first tab PLAY of the first Warzone screen (the local game screen, layout whose first
-- tab is JOIN = SystemLinkPlayMenu). Warzone only: the tab is hidden in Multiplayer and
-- Zombies (same screen), and nothing else of the game is changed.
-- * one row per map (RANKED PLAY, URZIKSTAN, REBIRTH ISLAND, VONDEL, FORTUNE'S KEEP,
--   HELLSPAWN), one official card per Lumen preset, with the official keyart (the large
--   2280x1296 layers: the small "_button" images are only loaded blurred);
-- * picking a card opens the lobby with that preset, the way Lumen's own preset screen
--   does it (tab of the map in SelectedPrestTab, CLUA preset setter with the preset id,
--   then OpenSystemLinkLobby), and writes br95_mode.txt for br95_ranked.gscc.
-- Rows come from PLAY_MENU.FillPlayMenu (menu._modifiedMenuData, one entry per row, cards
-- in rowData): only the menus built by this tab are changed.
-- Everything is in pcall: if something is missing the screen stays as Lumen makes it.
if BR95WZPlay then return end
local state = { ours = setmetatable({}, { __mode = "k" }) }
BR95WZPlay = state

local TAB = "BR95WZPlayMenu"
local JOIN_TAB = "SystemLinkPlayMenu"
local RANKED_NAME = "RESURGENCE RANKED WARZONE"
local LAUNCH_KEY = "c730e9e88337bfc4"   -- CLUA function that selects a preset by id
local MODE_FILE = "jupiter/IO/br95_mode.txt"

-- Lumen's presets (name, preset id). The ranked playlist is Rebirth Resurgence quads (id 4)
-- with br95_mode.txt = 1.
local PRESETS = {
    { RANKED_NAME, 4 },
    { "urzikstan_solos", 103 }, { "urzikstan_duos", 104 }, { "urzikstan_trios", 105 }, { "urzikstan_quads", 106 },
    { "urzikstan_mini", 18 }, { "urzikstan_plunder", 17 }, { "urzikstan_mutation_quads", 47 },
    { "rebirth_resurgence_solos", 1 }, { "rebirth_resurgence_duos", 2 }, { "rebirth_resurgence_trios", 3 },
    { "rebirth_resurgence_quads", 4 }, { "rebirth_lockdown", 32 }, { "rebirth_champions", 6 }, { "rebirth_plunder", 7 },
    { "vondel_resurgence_solos", 12 }, { "vondel_resurgence_duos", 13 }, { "vondel_resurgence_trios", 14 },
    { "vondel_resurgence_quads", 15 }, { "vondel_lockdown", 33 }, { "vondel_zxp", 16 },
    { "fortunes_resurgence_solos", 8 }, { "fortunes_resurgence_duos", 9 }, { "fortunes_resurgence_trios", 10 },
    { "fortunes_resurgence_quads", 11 }, { "fortunes_lockdown", 107 },
    { "hellspawn_resurgence_solos", 35 }, { "hellspawn_resurgence_duos", 36 }, { "hellspawn_resurgence_trios", 37 },
    { "hellspawn_resurgence_quads", 38 }, { "hellspawn_zxp", 34 }, { "hellspawn_purgatory", 5 },
}

-- map prefix -> row title, tab of Lumen's preset screen (SelectedPrestTab), keyart
local MAPS = {
    urzikstan = { row = "URZIKSTAN", tab = 0, art = "menu_keyart_wz_br_quads_layer00" },
    vondel    = { row = "VONDEL", tab = 1, art = "menu_keyart_br_vondel_layer_00" },
    rebirth   = { row = "REBIRTH ISLAND", tab = 3, art = "menu_keyart_wz_big_map_resurgence_layer00" },
    hellspawn = { row = "HELLSPAWN", tab = 4, art = "menu_keyart_catedral_hlwn_layer_00" },
    fortunes  = { row = "FORTUNE'S KEEP", tab = 5, art = "menu_keyart_mini_royale_vondel_layer_00" },
}
local ROW_ORDER = { "RANKED PLAY", "URZIKSTAN", "REBIRTH ISLAND", "VONDEL", "FORTUNE'S KEEP", "HELLSPAWN" }

-- keyart of one preset: the map's art, the mode's own art where the game has one
local function artFor(map, mode)
    if mode == "plunder" then return "menu_keyart_wz_plunder_layer00" end
    if map == "urzikstan" then
        for _, size in ipairs({ "solos", "duos", "trios", "quads" }) do
            if mode == size then return "menu_keyart_wz_br_" .. size .. "_layer00" end
        end
        return mode == "mini" and "menu_keyart_wz_br_trios_layer00" or "menu_keyart_wz_br_quads_layer00"
    end
    if map == "vondel" and mode ~= "resurgence_quads" and mode:find("resurgence", 1, true) == nil then
        return "menu_keyart_resurgence_vondel_layer_00"
    end
    return MAPS[map] and MAPS[map].art or "menu_keyart_wz_layer_00"
end

local function writeFile(path, text)
    pcall(function()
        local f = io.open(path, "w")
        if f then f:write(text); f:close() end
    end)
end

local function upvalue(fn, wanted)
    if type(fn) ~= "function" or not debug or not debug.getupvalue then return nil end
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if not name then return nil end
        if name == wanted then return value, i end
    end
end

-- Warzone and not Multiplayer / Zombies (same test as the RANKED tab)
local function isWarzone()
    local lp = rawget(_G, "LeaguePlayUtils")
    if type(lp) ~= "table" or type(lp.GetLeaguePlayTypeAndMode) ~= "function" then return false end
    local ok, data = pcall(lp.GetLeaguePlayTypeAndMode, 0)
    return ok and type(data) == "table" and data.gamemode == 128
end

-- ------------------------------------------------------------------
-- opening the lobby with a preset (same steps as Lumen's preset screen)
-- ------------------------------------------------------------------
local function launch(name, id, mapKey, ranked)
    local menu = rawget(_G, "PresetModesMenu")
    local open = upvalue(menu, "OpenSystemLinkLobby")
    local clua = rawget(_G, "CLUA")
    local setter
    if type(clua) == "table" then
        for k, fn in pairs(clua) do
            if type(fn) == "function" and tostring(k):find(LAUNCH_KEY, 1, true) then setter = fn end
        end
    end
    if type(open) ~= "function" or type(setter) ~= "function" then return end
    -- the map tab Lumen's lobby reads
    local _, tabIndex = upvalue(open, "SelectedPrestTab")
    if tabIndex then pcall(debug.setupvalue, open, tabIndex, MAPS[mapKey] and MAPS[mapKey].tab or 0) end
    -- the ranked playlist: br95_ranked_playlist_post.lua's launch hook reads this time
    local rp = rawget(_G, "BR95RankedPlaylist")
    if ranked and type(rp) == "table" then rp.rankedReadAt = os.clock() end
    if not pcall(setter, id) then return end
    writeFile(MODE_FILE, "BR95M1|" .. (ranked and "1" or "0") .. "|" .. name .. "|END")
    pcall(open, { controllerIndex = state.controller or 0 })
end

-- ------------------------------------------------------------------
-- cards and rows
-- ------------------------------------------------------------------

-- copy of CREATE PRIVATE MATCH, used when the game gives no private match card here
local BASE = { playlistName = "", markLocalized = false, playlistTitleBackgroundText = "WZ", titleAlpha = 1,
    buttonData = { icon = "jup_icon_mode_wz_br_custom", gameIcon = "icon_wz2_logo_hq_row", header = "",
        image = "jup_ui_menu_keyart_br_private_button", subHeader = "", iconShape = "hud_splash_gamemode_hexagon_rotated" },
    useLeftHqGradient = true, controllerIndex = 0, modeType = "", keyart01 = "", playlistMode = "",
    titleColor = { r = 1, g = 1, b = 1 }, titleAlignment = 2, buttonImage = "jup_ui_menu_keyart_br_private_button",
    useKeyartVignette = true, keyart02 = "", playlistRef = "jup_br_private_create", playlistTags = "",
    keyart00 = "jup_ui_menu_keyart_br_private_layer_00", game = 0,
    titlePosition = { right = 1000, left = 0, bottom = -98, top = -238 }, playlistDesc = "", id = "br95_base",
    primaryActionText = "Select", removeCondition = function() return false end }

-- the game's own CREATE PRIVATE MATCH card (it has the image layers in the right
-- format); never the DEVELOPMENT card (a different kind of card)
local function templateCard(md)
    for _, row in ipairs(md) do
        if type(row) == "table" and type(row.rowData) == "table" then
            for _, c in ipairs(row.rowData) do
                if type(c) == "table" and c.id == "brprivate_create" then return c end
            end
        end
    end
    local pm = rawget(_G, "PLAY_MENU")
    if type(pm) == "table" and type(pm.GetBRPrivateButtonList) == "function" then
        local ok, list = pcall(pm.GetBRPrivateButtonList, state.controller or 0)
        if ok and type(list) == "table" then
            for _, c in ipairs(list) do
                if type(c) == "table" and c.id == "brprivate_create" then return c end
            end
        end
    end
    return BASE
end

local MODE_WORDS = { solos = "SOLOS", duos = "DUOS", trios = "TRIOS", quads = "QUADS" }

local function makeCard(template, name, id)
    local ranked = name == RANKED_NAME
    local mapKey, mode = name:match("^(%a+)_(.+)$")
    if ranked then mapKey, mode = "rebirth", "resurgence_quads" end
    local map = MAPS[mapKey or ""]
    if not map then return nil end
    local title = ranked and name or mode:gsub("_", " "):upper()
    local art = ranked and "menu_keyart_rankedplay_01_layer_00" or artFor(mapKey, mode)
    local card = {}
    for k, v in pairs(template) do card[k] = v end
    card.buttonData = {}
    for k, v in pairs(template.buttonData or {}) do card.buttonData[k] = v end
    card.id = "br95_" .. (ranked and "ranked" or name)
    card.markLocalized = false
    card.playlistName = title
    card.playlistMode = map.row
    card.playlistDesc = ranked and "Ranked Play on Rebirth Island, quads. Win SR and climb from Bronze to Top 250."
        or (map.row .. " - " .. title)
    card.playlistRef = "br95_" .. tostring(id)
    card.buttonData.header = title
    card.buttonData.subHeader = map.row
    card.buttonData.icon = ranked and "jup_icon_mode_wz_ranked"
        or (mapKey == "fortunes" and mode:find("resurgence", 1, true) and "jup_icon_mode_wz_fort_resurge")
        or (mode:find("resurgence", 1, true) and "jup_icon_mode_wz_resurge")
        or card.buttonData.icon
    card.buttonImage = art
    card.buttonData.image = art
    card.keyart00 = art
    card.keyart01, card.keyart02 = "", ""
    if type(template.imageLayers) == "table" and type(template.imageLayers[1]) == "table" then
        local layer = {}
        for k, v in pairs(template.imageLayers[1]) do layer[k] = (v ~= nil and tostring(v) ~= "") and art or v end
        card.imageLayers = { layer }
    end
    card.removeCondition = function() return false end
    card.buttonAction = function() launch(ranked and "rebirth_resurgence_quads" or name, id, mapKey, ranked) end
    card.br95Row = ranked and "RANKED PLAY" or map.row
    return card
end

-- the rows of our menu: one per map, the game's rows (private match, development) removed
local function buildRows(menu)
    local md = menu._modifiedMenuData
    if type(md) ~= "table" or type(md[1]) ~= "table" then return end
    local template = templateCard(md)
    local groups = {}
    for _, p in ipairs(PRESETS) do
        local card = makeCard(template, p[1], p[2])
        if card then
            groups[card.br95Row] = groups[card.br95Row] or {}
            table.insert(groups[card.br95Row], card)
        end
    end
    local rowTemplate = md[1]
    local rows = {}
    for _, rowName in ipairs(ROW_ORDER) do
        if groups[rowName] then
            local r = {}
            for k, v in pairs(rowTemplate) do r[k] = v end
            r.rowData = groups[rowName]
            -- rowName is what the row shows (plain text is shown as it is)
            r.rowName = rowName
            rows[#rows + 1] = r
        end
    end
    if #rows == 0 then return end
    for i = #md, 1, -1 do table.remove(md, i) end
    for _, r in ipairs(rows) do md[#md + 1] = r end
end

local function hookPlayMenu()
    local pm = rawget(_G, "PLAY_MENU")
    if state.hooked or type(pm) ~= "table" or type(pm.FillPlayMenu) ~= "function" then return end
    state.hooked = true
    local fill = pm.FillPlayMenu
    pm.FillPlayMenu = function(menu, ...)
        local results = { fill(menu, ...) }
        if state.building or state.ours[menu] then
            state.ours[menu] = true
            pcall(buildRows, menu)
        end
        return unpack(results)
    end
end

-- ------------------------------------------------------------------
-- the tab
-- ------------------------------------------------------------------

-- the local game layout gets PLAY in front of JOIN (hidden outside Warzone)
local function patchLayout(l)
    if type(l) ~= "table" or l[1] ~= JOIN_TAB or state.patched[l] then return end
    state.patched[l] = true
    table.insert(l, 1, TAB)
end

local function install()
    if state.installed then return end
    if type(MenuBuilder) ~= "table" or type(MenuBuilder.registerType) ~= "function" then return end
    if type(MAINMENUTABS) ~= "table" or type(MAINMENUTABS.TabData) ~= "table" or type(MAINMENUTABS.Layouts) ~= "table" then return end
    local data = MAINMENUTABS.TabData
    local join = data[JOIN_TAB]
    if type(join) ~= "table" then return end
    state.installed = true
    state.patched = setmetatable({}, { __mode = "k" })
    hookPlayMenu()

    MenuBuilder.registerType(TAB, function(menu, options)
        state.controller = type(options) == "table" and options.controllerIndex or 0
        pcall(hookPlayMenu)
        state.building = true
        local ok, result = pcall(MenuBuilder.BuildRegisteredType, "GameMenuWidget", options)
        state.building = false
        if ok and result then
            state.ours[result] = true
            return result
        end
        local holder = LUI.UIElement.new()
        holder:SetAnchorsAndPosition(0, 0, 0, 0, 0, 0, 0, 0)
        return holder
    end)

    -- a plain tab record like the RANKED tab (JOIN's own callbacks refresh the server list)
    local sound = type(data.CustomizeMenu) == "table" and data.CustomizeMenu.menuSound or join.menuSound
    data[TAB] = { menuName = TAB, name = "PLAY", menuSound = sound,
        isHidden = function() return not isWarzone() end,

        isDisabled = function() return false end,
        onFocusCallback = function() return true end, menuSpecificCallback = function() end }

    -- the layouts come through a metatable (pairs lists none): patch the local game
    -- layout when the game asks for it, and now if it is already there
    local layouts = MAINMENUTABS.Layouts
    local mt = getmetatable(layouts)
    if mt and mt.__index then
        local index = mt.__index
        mt.__index = function(t, key)
            local l
            if type(index) == "function" then l = index(t, key) else l = index[key] end
            pcall(patchLayout, l)
            return l
        end
    end
    pcall(function() patchLayout(rawget(layouts, "MPSystemLinkMenu")) end)
end

if LUI and LUI.UIRoot and type(LUI.UIRoot.init) == "function" then
    local original = LUI.UIRoot.init
    LUI.UIRoot.init = function(root, ...)
        local result = original(root, ...)
        pcall(install)
        return result
    end
end
pcall(install)
