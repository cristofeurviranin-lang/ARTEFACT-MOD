-- BR95 Ranked V2: the OFFICIAL Ranked Play of the game, offline, for the
-- RESURGENCE RANKED WARZONE playlist (br95_ranked_playlist_post.lua).
-- Lobby (PLAY tab): Lumen's private lobby + the official Ranked Play pieces (rank card,
-- division, Next Promotion, Rank & Skill / Challenges & Rewards / Top 250 / How to
-- Play cards, Warzone Rewards). The official data is made the offline way: our SR,
-- win streak (Hot Streak, 72 h) and wins are given to the official stat readers, our
-- divisions replace the official (empty) ones, and only the two official set-up
-- steps that work offline run (the full one crashes). Challenges & Rewards and Top 250
-- open our pages (the official ones crash / are web pages of the servers).
-- In a match of that playlist the game is told it is a ranked match (official ranked
-- HUD, ranks of the players: bots around ours).
-- DEBUG = true writes the logs jupiter/IO/br95_lpprobe10.txt and br95_lpgame.txt.
if BR95RankedOfficial then return end
local P = { lines = {}, calls = {} }
BR95RankedOfficial = P
local DEBUG = false

local function log(s)
    if not DEBUG then return end
    P.lines[#P.lines + 1] = s
    pcall(function()
        local f = io.open("jupiter/IO/br95_lpprobe10.txt", "w")
        if f then f:write(table.concat(P.lines, "\n")); f:close() end
    end)
end

local function short(v)
    local t = type(v)
    if t == "string" then return '"' .. v:sub(1, 50) .. '"' end
    if t == "table" then
        local parts, n = {}, 0
        for k, x in pairs(v) do
            n = n + 1
            if n <= 8 then parts[#parts + 1] = tostring(k) .. "=" .. (type(x) == "table" and "{..}" or tostring(x):sub(1, 30)) end
        end
        return "{" .. table.concat(parts, ", ") .. (n > 8 and (", +" .. (n - 8)) or "") .. "}"
    end
    return tostring(v)
end

-- log the first 3 calls of each LeaguePlayUtils function while the tab lives
local function wrapUtils()
    local LP = rawget(_G, "LeaguePlayUtils")
    if type(LP) ~= "table" or P.wrapped then return end
    P.wrapped = true
    for name, fn in pairs(LP) do
        if type(fn) == "function" then
            LP[name] = function(...)
                local n = (P.calls[name] or 0) + 1
                P.calls[name] = n
                local results = { pcall(fn, ...) }
                if P.active and n <= 3 then
                    local args = {}
                    for k = 1, math.min(select("#", ...), 4) do args[#args + 1] = short((select(k, ...))) end
                    log("LP." .. tostring(name) .. "(" .. table.concat(args, ", ") .. ") -> "
                        .. (results[1] and short(results[2]) or ("ERROR " .. tostring(results[2]):sub(1, 100))))
                end
                if not results[1] then error(results[2], 0) end
                return select(2, unpack(results))
            end
        end
    end
end

local TAB = "BR95OfficialRankedTab"

-- our engine's numbers given to the official stat readers:
-- "sr" (skilldivisions) = our SR, "h_streak" (flamestreak) = win streak, "xp"
-- (progression) = our RP (the official rank comes from it)
-- The official widgets ask for these numbers many times per second (every frame in
-- the lobby and in a match): a file is read at most once per second, or the menus
-- and the match stutter.
local fileCache = {}
local function readFile(path)
    local now = os.clock()
    local c = fileCache[path]
    if c and now - c.at < 1 then return c.text end
    local text
    pcall(function()
        local f = io.open(path, "r")
        if f then text = f:read("*a"); f:close() end
    end)
    fileCache[path] = { at = now, text = text or "" }
    return text or ""
end

function feedOurStats()
    if P.fed then return end
    local LP = rawget(_G, "LeaguePlayUtils")
    if type(LP) ~= "table" then return end
    P.fed = true
    local function compute(stat)
        if stat == "sr" then return tonumber(readFile("jupiter/IO/br95_ranked.txt"):match("^BR95R1|(%-?%d+)|")) end
        -- Hot Streak: our win streak, with the time of the last won match ("hs_time");
        -- the flames go out 72 hours after the last win
        if stat == "h_streak" or stat == "hs_time" then
            local lastWin = 0
            for t, d in readFile("jupiter/IO/br95_ranked_history.txt"):gmatch("H|(%d+)|%-?%d+|(%-?%d+)|") do
                if tonumber(d) > 0 then lastWin = tonumber(t) end
            end
            if stat == "hs_time" then return lastWin end
            if lastWin == 0 or os.time() - lastWin > 72 * 3600 then return 0 end
            return tonumber(readFile("jupiter/IO/br95_streak.txt"):match("^BR95W1|(%d+)|")) or 0
        end
        -- the official rank (stars) comes from "xp": our number of won matches
        if stat == "xp" then
            local wins = 0
            for d in readFile("jupiter/IO/br95_ranked_history.txt"):gmatch("H|%d+|%-?%d+|(%-?%d+)|") do
                if tonumber(d) > 0 then wins = wins + 1 end
            end
            return wins
        end
    end
    -- the same stat asked again within a second: the kept answer (no file parsing)
    local answers = {}
    local function ours(stat)
        if stat ~= "sr" and stat ~= "h_streak" and stat ~= "hs_time" and stat ~= "xp" then return nil end
        local now = os.clock()
        local a = answers[stat]
        if a and now - a.at < 1 then return a.value end
        local value = compute(stat)
        answers[stat] = { at = now, value = value }
        return value
    end
    for _, name in ipairs({ "GetLocalPlayerStatSeasonal", "GetLocalPlayerStat" }) do
        local original = LP[name]
        if type(original) == "function" then
            LP[name] = function(stat, ...)
                local value = ours(stat)
                if value then return value end
                -- the official stat table is never filled offline: 0 instead of an error
                local ok, result = pcall(original, stat, ...)
                if ok and result ~= nil then return result end
                return 0
            end
        end
    end
    log("our stats plugged: sr=" .. tostring(ours("sr")) .. " streak=" .. tostring(ours("h_streak")) .. " wins=" .. tostring(ours("xp")))

    -- our divisions (br95_ranked.gsc v12): the official ones are empty offline
    local START = { 0, 1000, 2000, 3500, 5000, 8000, 12000, 17000 }
    local function stepStart(div, sub)
        if div >= 8 then return START[8] end
        local size = (START[div + 1] - START[div]) / 3
        return math.floor(START[div] + ((sub or 1) - 1) * size)
    end
    LP.GetDivisionFromSkillRating = function(sr)
        sr = tonumber(sr) or 0
        local div = 1
        for i, s in ipairs(START) do if sr >= s then div = i end end
        if div >= 8 then return 8, 1 end
        local size = (START[div + 1] - START[div]) / 3
        return div, math.min(3, math.floor((sr - START[div]) / size) + 1)
    end
-- SR at which the step (div, sub) starts: the game asks it for the NEXT step to
    -- show "Next Promotion" (Gold III -> Platinum I = 3500)
    LP.GetSRTargetFromDivision = function(div, sub)
        div, sub = tonumber(div) or 1, tonumber(sub) or 1
        return stepStart(div, sub)
    end
    local originalSub = LP.GetSubdivisionData
    if type(originalSub) == "function" then
        LP.GetSubdivisionData = function(div, sub, ...)
            local data = originalSub(div, sub, ...)
            if type(data) == "table" then data.startRange = stepStart(tonumber(div) or 1, tonumber(sub) or 1) end
            return data
        end
    end
    -- these open online-only menus (they crash offline): a click does nothing
    -- Challenges & Rewards -> our QUESTS page, Top 250 -> our RANKING page
    LP.OpenCareerMenu = function() if P.showV2 then pcall(P.showV2, 8) end end
    LP.OpenTop250Menu = function() if P.showV2 then pcall(P.showV2, 4) end end
    -- the official code greys out the lobby cards offline (Top 250 among them)
    LP.ShouldLobbyButtonBeDisabled = function() return false end
end

-- error text + where it comes from (the first lines of the call stack)
local function traceback(err)
    local text = tostring(err)
    if debug and debug.traceback then text = debug.traceback(text, 2) end
    local lines, n = {}, 0
    for line in text:gmatch("[^\n]+") do
        n = n + 1
        if n <= 7 then lines[#lines + 1] = line end
    end
    return table.concat(lines, " <- ")
end

-- the utility functions the official widgets call: while the official tab is
-- built, a failing one logs its error and gives nil instead of stopping the build
local function forgiveUtils()
    if P.forgiving then return end
    P.forgiving = true
    -- functions that need the online playlist: wherever they are, a failure gives nil
    local NEED_ONLINE = { LoadRankedPlayGametypeAssetFromPlaylist = true }
    local holders = {}
    for gname, lib in pairs(_G) do holders[#holders + 1] = { tostring(gname), lib } end
    if type(LUI) == "table" then
        for name, lib in pairs(LUI) do holders[#holders + 1] = { "LUI." .. tostring(name), lib } end
    end
    for _, holder in ipairs(holders) do
        local gname, lib = holder[1], holder[2]
        if type(lib) == "table" then
            pcall(function()
                for fname in pairs(NEED_ONLINE) do
                    local fn = rawget(lib, fname)
                    if type(fn) == "function" then
                        lib[fname] = function(...)
                            local results = { pcall(fn, ...) }
                            if results[1] then return select(2, unpack(results)) end
                            log("  " .. tostring(gname) .. "." .. fname .. " failed (offline): " .. tostring(results[2]):sub(1, 120))
                            return nil
                        end
                        log("made safe: " .. tostring(gname) .. "." .. fname)
                    end
                end
            end)
        end
    end
    for _, libName in ipairs({ "MPUtils", "PlaylistUtils" }) do
        local lib = rawget(_G, libName)
        if type(lib) == "table" then
            for name, fn in pairs(lib) do
                if type(fn) == "function" then
                    lib[name] = function(...)
                        if not P.building then return fn(...) end
                        local results = { pcall(fn, ...) }
                        if results[1] then return select(2, unpack(results)) end
                        log("  " .. libName .. "." .. tostring(name) .. " failed: " .. tostring(results[2]):sub(1, 160))
                        return nil
                    end
                end
            end
        end
    end
end

-- builds the official tab; a piece (child widget) that fails becomes an empty
-- element instead of failing the whole tab, and its error is logged with its stack
function buildForgiving(options, typeName)
    typeName = typeName or "LPPlayMenu"
    pcall(forgiveUtils)
    local original = MenuBuilder.BuildRegisteredType
    local depth, failures = 0, 0
    MenuBuilder.BuildRegisteredType = function(name, ...)
        depth = depth + 1
        local n = select("#", ...)
        local args = { ... }
        local results = { xpcall(function() return original(name, unpack(args, 1, n)) end, traceback) }
        depth = depth - 1
        if results[1] then return select(2, unpack(results)) end
        failures = failures + 1
        log("  piece " .. tostring(name) .. " failed: " .. tostring(results[2]))
        if depth == 0 then error(results[2], 0) end
        local empty = LUI.UIElement.new()
        empty:SetAnchorsAndPosition(0, 1, 0, 1, 0, 1, 0, 1)
        return empty
    end
    P.building = true
    local ok, widget = pcall(MenuBuilder.BuildRegisteredType, typeName, options)
    P.building = false
    MenuBuilder.BuildRegisteredType = original
    log("forgiving build: " .. failures .. " failed pieces")
    if not ok then error(widget, 0) end
    return widget
end

-- the lobby of the RESURGENCE RANKED WARZONE playlist (br95_mode.txt = 1)
local function rankedLobby()
    return readFile("jupiter/IO/br95_mode.txt"):match("^BR95M1|(%d)") == "1"
end

-- element ids of a widget tree (3 levels), for the log
local function ids(el, depth, out)
    if not el or depth > 3 then return end
    local id = ""
    pcall(function() id = tostring(el.id) end)
    out[#out + 1] = string.rep(" ", depth) .. id
    local child
    pcall(function() child = el:getFirstChild() end)
    while child do
        ids(child, depth + 1, out)
        local nextChild
        pcall(function() nextChild = child:getNextSibling() end)
        child = nextChild
    end
end

-- first element of a tree with this id
function findChild(el, id)
    if not el then return nil end
    local child
    pcall(function() child = el:getFirstChild() end)
    while child do
        local cid
        pcall(function() cid = child.id end)
        if cid == id then return child end
        local found = findChild(child, id)
        if found then return found end
        local nextChild
        pcall(function() nextChild = child:getNextSibling() end)
        child = nextChild
    end
end

-- hides (moves away) the elements of a tree whose id matches a pattern
local function hideMatching(el, pattern, depth, hidden)
    if not el or depth > 4 then return end
    local child
    pcall(function() child = el:getFirstChild() end)
    while child do
        local id = ""
        pcall(function() id = tostring(child.id) end)
        if id:lower():find(pattern) then
            pcall(child.SetAlpha, child, 0, 0)
            pcall(child.SetAnchorsAndPosition, child, 0, 1, 0, 1, 6000, 6001, 6000, 6001)
            hidden[#hidden + 1] = id
        else
            hideMatching(child, pattern, depth + 1, hidden)
        end
        local nextChild
        pcall(function() nextChild = child:getNextSibling() end)
        child = nextChild
    end
end

-- the official ranked data, made the offline way (see the notes at the top)
local function prepareOfficialData(controller)
    pcall(feedOurStats)
    pcall(function() if DataSources.frontEnd.LP == nil then DataSources.frontEnd.LP = {} end end)
    local okInit, errInit = pcall(LeaguePlayUtils.SetupLocalPlayerData, controller)
    if not okInit then log("SetupLocalPlayerData ERROR " .. tostring(errInit)) end
    pcall(LeaguePlayUtils.SetupTop250LadderData, controller)
end

-- the PLAY tab of the ranked playlist: Lumen's private lobby (START MATCH, bots,
-- squad...) with the official Ranked Play pieces (rank, division, cards) on it;
-- the official FIND MATCH button (online matchmaking) is hidden
local function install()
    if P.installed then return true end
    if type(MenuBuilder) ~= "table" or not MenuBuilder.getType("LPPlayMenu") then return false end
    local original = MenuBuilder.getType("WarzonePrivateMatchLobbyPlayMenu")
    if type(original) ~= "function" then return false end
    MenuBuilder.registerType("WarzonePrivateMatchLobbyPlayMenu", function(menu, options)
        local private = original(menu, options)
        if not private or not rankedLobby() then return private end
        P.active = true
        local controller = type(options) == "table" and options.controllerIndex or 0
        log("ranked PLAY tab " .. os.date("%H:%M:%S"))
        prepareOfficialData(controller)
        local ok, official = pcall(buildForgiving, options)
        if not (ok and official) then log("official pieces ERROR " .. tostring(official)); return private end
        rawset(_G, "BR95OfficialLobby", true)
        private:addElement(official)
        local treeP, treeO = {}, {}
        ids(private, 0, treeP); ids(official, 0, treeO)
        log("private lobby tree:\n" .. table.concat(treeP, "\n"))
        log("official tree:\n" .. table.concat(treeO, "\n"))
        local hidden = {}
        -- official pieces that are online only or doubles of Lumen's lobby
        -- (the WARZONE REWARDS / bonus XP panel stays: ADD BOTS moved and the map card is hidden)
        for _, id in ipairs({ "lobbystartbutton", "lobbyinspectbutton", "aarflyoutbase", "helperbar" }) do
            hideMatching(official, "^" .. id .. "$", 0, hidden)
        end
        -- Lumen's squad block sits where the official rank card is
        hideMatching(private, "squad", 0, hidden)
        hideMatching(private, "role", 0, hidden)
        log("hidden: " .. table.concat(hidden, " "))
        -- the official cards stay where the game puts them (bottom right): Lumen's map
        -- card under them goes away and ADD BOTS moves above CODCASTER / LOBBY MEMBERS
        hideMatching(private, "^lobbymap$", 0, hidden)
        for _, id in ipairs({ "BotMenuWZ", "BotMenuWZKBM" }) do
            local bots = findChild(private, id)
            if bots then pcall(bots.SetAnchorsAndPosition, bots, 0, 1, 0, 1, 528, 862, 704, 746) end
        end
        -- the official CHALLENGES & REWARDS menu crashes the game while it is built
        -- offline (seen twice) and the official TOP 250 is a web page of the servers:
        -- the two cards open our pages (season quests, ranking) over the lobby instead.
        -- Built now, far away (buttons made later get no input).
        pcall(function()
            local ours = MenuBuilder.getType("BR95RankedMenu")
            if type(ours) ~= "function" then return end
            local okV2, v2 = pcall(ours, menu, options)
            if not (okV2 and v2) then log("V2 page error " .. tostring(v2)); return end
            -- the page switch of THIS copy of our pages (the RANKED tab has its own)
            local menuState = rawget(_G, "BR95RankedMenu")
            local openThis = menuState and menuState.openView
            -- its animations sleep while the layer is away (no work for a hidden page)
            pcall(function() v2.br95Paused = true end)
            local layer = LUI.UIElement.new(); layer.id = "BR95V2Layer"
            layer:SetAnchorsAndPosition(0, 1, 0, 1, 6000, 7920, 0, 1080)
            private:addElement(layer)
            local dark = LUI.UIImage.new()
            dark:SetAnchorsAndPosition(0, 1, 0, 1, 0, 1920, 0, 1080)
            dark:SetRGB(0, 0); dark:SetAlpha(0.6, 0)
            layer:addElement(dark)
            layer:addElement(v2)
            local back = MenuBuilder.BuildRegisteredType("GenericButton", { controllerIndex = controller })
            back:SetAnchorsAndPosition(0, 1, 0, 1, 1640, 1900, 30, 76)
            layer:addElement(back)
            if back.Text then pcall(back.Text.setText, back.Text, "BACK") end
            back:addEventHandler("button_action", function()
                pcall(layer.SetAnchorsAndPosition, layer, 0, 1, 0, 1, 6000, 7920, 0, 1080)
                pcall(function() v2.br95Paused = true end)
            end)
            P.showV2 = function(page)
                pcall(function() v2.br95Paused = false end)
                pcall(layer.SetAnchorsAndPosition, layer, 0, 1, 0, 1, 0, 1920, 0, 1080)
                if openThis then pcall(openThis, page) end
            end
        end)
        -- the playlist title the hidden official button carried, above START MATCH
        pcall(function()
            local icon = LUI.UIImage.new()
            icon:SetAnchorsAndPosition(0, 1, 0, 1, 84, 126, 708, 750)
            icon:setImage(RegisterMaterial("jup_icon_mode_wz_ranked"), 0)
            private:addElement(icon)
            local title = LUI.UIText.new()
            title:SetAnchorsAndPosition(0, 1, 0, 1, 134, 640, 714, 746)
            if FONTS and FONTS.GetFont and FONTS.PrimaryBold and FONTS.PrimaryBold.File then
                pcall(title.SetFont, title, FONTS.GetFont(FONTS.PrimaryBold.File))
            end
            pcall(title.SetFontSize, title, 28)
            if title.SetAlignment and LUI.Alignment then title:SetAlignment(LUI.Alignment.Left) end
            title:SetRGB(0xFFFFFF, 0)
            local text = "RANKED PLAY: RESURGENCE"
            pcall(function() text = LeaguePlayUtils.GetPlaylistTitle(true) or text end)
            title:setText(text)
            private:addElement(title)
        end)
        return private
    end)
    P.installed = true
    if DEBUG then pcall(wrapUtils) end
    log("official ranked lobby installed on the PLAY tab")
    return true
end


-- ------------------------------------------------------------------
-- in a match of the ranked playlist
-- ------------------------------------------------------------------
local G = {}
local function inMatch()
    local ok, front = pcall(function() return Engine.@InFrontend() end)
    return ok and front == false
end

-- the official SR tracker (BRSRMatchStatTracker) is caught when it is built; a timer
-- child of ours puts the match SR on its number every second
if type(MenuBuilder) == "table" and type(MenuBuilder.BuildRegisteredType) == "function" then
    local originalBuild = MenuBuilder.BuildRegisteredType
    MenuBuilder.BuildRegisteredType = function(name, ...)
        local result = originalBuild(name, ...)
        if result then
            pcall(function()
                if result.id ~= "BRSRMatchStatTracker" or result._br95Timer then return end
                result._br95Timer = true
                local watch = LUI.UIElement.new(); watch.id = "BR95SRWatch"
                result:addElement(watch)
                watch:registerEventHandler("br95_sr_tick", function()
                    if G.updateTracker then pcall(G.updateTracker, result) end
                end)
                watch:addElement(LUI.UITimer.new({ interval = 1000, event = "br95_sr_tick", disposable = false, eventTarget = watch }))
            end)
        end
        return result
    end
end

do
    local LP = rawget(_G, "LeaguePlayUtils")
    local START = { 0, 1000, 2000, 3500, 5000, 8000, 12000, 17000 }
    local steps = {}
    for div = 1, 7 do
        local size = (START[div + 1] - START[div]) / 3
        for t = 0, 2 do steps[#steps + 1] = math.floor(START[div] + t * size) end
    end
    steps[#steps + 1] = START[8]
    local function ourSR()
        return tonumber(readFile("jupiter/IO/br95_ranked.txt"):match("^BR95R1|(%-?%d+)|")) or 0
    end
    local function stepIndex(sr)
        local n = 1
        for k, s in ipairs(steps) do if sr >= s then n = k end end
        return n
    end
    -- ranks of the players: the game passes SR 0 for everyone in a match; a real player
    -- (xuid not 0) gets our SR, the bots (all xuid 0) a step from two below ours to one
    -- above, changing with each request
    if type(LP) == "table" and type(LP.GetSkillDivData) == "function" then
        local original = LP.GetSkillDivData
        LP.GetSkillDivData = function(sr, xuid, top, ...)
            if inMatch() then
                local key = tostring(xuid or "0")
                if key ~= "0" and key ~= "" then
                    sr = ourSR()
                else
                    G.botCalls = (G.botCalls or 0) + 1
                    local k = math.max(1, math.min(#steps, stepIndex(ourSR()) - 2 + (G.botCalls * 7) % 4))
                    sr = steps[k] + 10
                end
            end
            return original(sr, xuid, top, ...)
        end
    end

    -- The number of the tracker ("Count") is written again by the game (0 from the
    -- servers' data): it keeps a setText of ours that puts our value instead of a
    -- number. Its text comes back as a game string: compared through tostring.
    local function isNumber(t)
        if t == nil then return true end
        local s = tostring(t)
        return s == "" or s:match("^[%+%-]?%d+$") ~= nil
    end
    local function setNumbers(el, value, depth)
        if not el or depth > 8 then return end
        pcall(function()
            if not el.setText then return end
            if not el._br95Claimed then
                local t
                if el.getText then pcall(function() t = el:getText() end) end
                if tostring(el.id) ~= "Count" and not isNumber(t) then return end
                el._br95Claimed = true
                local original = el.setText
                el._br95SetText = original
                el.setText = function(self, s, ...)
                    if G.srText and isNumber(s) then s = G.srText end
                    return original(self, s, ...)
                end
            end
            el._br95SetText(el, value)
        end)
        local child
        pcall(function() child = el:getFirstChild() end)
        while child do
            setNumbers(child, value, depth + 1)
            local nextChild
            pcall(function() nextChild = child:getNextSibling() end)
            child = nextChild
        end
    end
    -- match SR of our engine (jupiter/IO/br95_ranked_live.txt: entry cost + kills - deaths)
    local function liveDelta()
        local delta, active = readFile("jupiter/IO/br95_ranked_live.txt"):match("^BR95L1|%-?%d+|%d+|%d+|(%-?%d+)|(%d+)|END")
        if active ~= "1" then return nil end
        return tonumber(delta)
    end
    G.updateTracker = function(tracker)
        if not inMatch() then return end
        local delta = liveDelta()
        if delta == nil then return end
        G.srText = (delta > 0 and "+" or "") .. delta
        setNumbers(tracker, G.srText, 0)
    end
end

-- in a match of the RESURGENCE RANKED WARZONE playlist (br95_mode.txt = 1) the game is
-- told it is a ranked match, so it builds its official ranked HUD
do
    local C = rawget(_G, "CONDITIONS")
    if type(C) == "table" then
        local function rankedMatch()
            if not inMatch() then return false end
            return readFile("jupiter/IO/br95_mode.txt"):match("^BR95M1|(%d)") == "1"
        end
        local YES = { "IsBRLeaguePlayInGame", "IsLeaguePlayInGame", "InGameLP", "IsRankedMatch", "IsBRLeaguePlay",
            "IsLeaguePlay", "IsLeaguePlayEnabled", "IsWZLeaguePlayEnabled", "IsCoreLeaguePlayEnabled" }
        local NO = { "IsBRLPRankDisplayDisabled" }
        local function override(name, answer)
            local original = C[name]
            if type(original) ~= "function" then return end
            C[name] = function(...)
                if rankedMatch() then return answer end
                return original(...)
            end
        end
        for _, name in ipairs(YES) do override(name, true) end
        for _, name in ipairs(NO) do override(name, false) end
    end
end

if LUI and LUI.UIRoot and type(LUI.UIRoot.init) == "function" then
    local originalInit = LUI.UIRoot.init
    LUI.UIRoot.init = function(root, ...)
        local result = originalInit(root, ...)
        pcall(install)
        return result
    end
end
pcall(install)
-- our divisions / stats must be there in a match too, not only once the RANKED tab opened
pcall(feedOurStats)
if type(MenuBuilder) == "table" and type(MenuBuilder.BuildRegisteredType) == "function" then
    local original = MenuBuilder.BuildRegisteredType
    MenuBuilder.BuildRegisteredType = function(name, ...)
        if not P.installed then pcall(install) end
        return original(name, ...)
    end
end
