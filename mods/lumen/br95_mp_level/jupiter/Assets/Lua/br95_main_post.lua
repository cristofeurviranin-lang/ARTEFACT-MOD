-- BR95 main menu button: a WORLD RANKING button in the gap between WARZONE and
-- LUMEN SETTINGS of the Lumen main menu. It shows the ranking of the real players
-- (br95_world_real_post.lua) as a full-screen page inside the main menu itself.
-- The page is built with the menu (only buttons built with a menu get input) and
-- waits off-screen; the button slides it in, BACK slides it out.
-- EXPERIMENTAL: the position of the button comes from a screenshot of the menu.
-- Wrapped in pcall; if it fails the menu stays as it was. Fully restart the game
-- after changes.
if BR95MainMenu then return end
local state = { installed = false }
BR95MainMenu = state

local MENU_TYPE = "MainMenu"
local OFFSCREEN = { 0, 1, 0, 1, 6000, 7920, 0, 1080 }
local ONSCREEN = { 0, 1, 0, 1, 0, 1920, 0, 1080 }
-- the gap between the WARZONE and LUMEN SETTINGS buttons, lined up with them
-- (measured on a screenshot of the menu); the second row hides the button
local BUTTON_ON = { 0.5, 0.5, 0, 1, -720, -390, 637, 671 }
local BUTTON_OFF = { 0.5, 0.5, 0, 1, 6000, 6330, 637, 671 }

local function addRanking(widget, options)
    local real = rawget(_G, "BR95WorldReal")
    if type(real) ~= "table" or type(real.build) ~= "function" then
        state.lastError = "BR95WorldReal not loaded"
        return
    end
    local controller = type(options) == "table" and options.controllerIndex or 0

    local page, button
    local spread = unpack or table.unpack
    local function place(element, position)
        pcall(function() element:SetAnchorsAndPosition(spread(position)) end)
    end
    local function close()
        place(page, OFFSCREEN)
        place(button, BUTTON_ON)
    end
    page = real.build(nil, controller, close)
    place(page, OFFSCREEN)
    widget:addElement(page)

    button = MenuBuilder.BuildRegisteredType("GenericButton", { controllerIndex = controller })
    place(button, BUTTON_ON)
    if button.Text then pcall(button.Text.setText, button.Text, "WORLD RANKING") end
    button:addEventHandler("button_action", function()
        pcall(function()
            if page.br95Reload then page.br95Reload() end
            place(page, ONSCREEN)
            place(button, BUTTON_OFF)
        end)
    end)
    widget:addElement(button)
end

local function install()
    if state.installed then return true end
    if type(MenuBuilder) ~= "table" or type(MenuBuilder.getType) ~= "function" or type(MenuBuilder.registerType) ~= "function" then return false end
    local original = MenuBuilder.getType(MENU_TYPE)
    if type(original) ~= "function" then return false end

    MenuBuilder.registerType(MENU_TYPE, function(menu, options)
        local widget = original(menu, options)
        local ok, err = pcall(addRanking, widget, options)
        if not ok then
            state.lastError = tostring(err)
            if DebugPrint then pcall(DebugPrint, "[BR95Main] " .. state.lastError) end
        end
        return widget
    end)
    state.installed = true
    if DebugPrint then pcall(DebugPrint, "[BR95Main] button installed on " .. MENU_TYPE) end
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
