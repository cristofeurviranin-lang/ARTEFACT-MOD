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
local function readFile(path)
    local text
    pcall(function()
        local f = io.open(path, "r")
        if f then text = f:read("*a"); f:close() end
    end)
    return text or ""
end

function feedOurStats()
    if P.fed then return end
    local LP = rawget(_G, "LeaguePlayUtils")
    if type(LP) ~= "table" then return end
    P.fed = true
    local function ours(stat)
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
            end)
            P.showV2 = function(page)
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


-- in-match probe: the HUD pieces the game builds and the official ranked functions
-- it calls during a match (to find the official SR widget).
-- Output: jupiter/IO/br95_lpgame.txt
local G = { lines = {}, seen = {}, count = 0 }
local function glog(s)
    if not DEBUG then return end
    G.lines[#G.lines + 1] = s
    pcall(function()
        local f = io.open("jupiter/IO/br95_lpgame.txt", "w")
        if f then f:write(table.concat(G.lines, "\n")); f:close() end
    end)
end
local function inMatch()
    local ok, front = pcall(function() return Engine.@InFrontend() end)
    return ok and front == false
end
if type(MenuBuilder) == "table" and type(MenuBuilder.BuildRegisteredType) == "function" then
    local originalBuild = MenuBuilder.BuildRegisteredType
    MenuBuilder.BuildRegisteredType = function(name, ...)
        local result = originalBuild(name, ...)
        -- the official SR tracker is caught when it is built; a timer on it shows our
        -- match SR every second
        pcall(function()
            if result and result.id == "BRSRMatchStatTracker" and not result._br95Timer then
                result._br95Timer = true
                G.tracker = result
                glog("SR tracker built")
                -- the tracker itself ignores our events: a child element of ours carries the timer
                local watch = LUI.UIElement.new(); watch.id = "BR95SRWatch"
                result:addElement(watch)
                watch:registerEventHandler("br95_sr_tick", function()
                    if G.updateTracker then
                        local ok, err = pcall(G.updateTracker, nil, result)
                        if not ok and not G.toldError then G.toldError = true; glog("tracker update error " .. tostring(err)) end
                    end
                end)
                watch:addElement(LUI.UITimer.new({ interval = 1000, event = "br95_sr_tick", disposable = false, eventTarget = watch }))
            end
        end)
        if G.count < 400 and inMatch() then
            local key = tostring(name)
            if not G.seen[key] then
                G.seen[key] = true; G.count = G.count + 1
                local id = ""
                pcall(function() id = tostring(result and result.id) end)
                glog("hud " .. key .. " -> " .. id)
            end
        end
        return result
    end
end
-- in a match: what the SR events and the ranks of the other players look like, and
-- the ranks of the bots set around ours (two steps below to one step above)
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
        local text = ""
        pcall(function()
            local f = io.open("jupiter/IO/br95_ranked.txt", "r")
            if f then text = f:read("*a") or ""; f:close() end
        end)
        return tonumber(text:match("^BR95R1|(%-?%d+)|")) or 0
    end
    local function stepIndex(sr)
        local n = 1
        for k, s in ipairs(steps) do if sr >= s then n = k end end
        return n
    end
    local function hash(s)
        local h = 7
        for i = 1, #s do h = (h * 31 + s:byte(i)) % 1000003 end
        return h
    end
    if type(LP) == "table" and type(LP.GetSkillDivData) == "function" then
        local original = LP.GetSkillDivData
        local logged = 0
        LP.GetSkillDivData = function(sr, xuid, top, ...)
            if logged < 25 and inMatch() then logged = logged + 1; glog("GetSkillDivData(" .. tostring(sr) .. ", " .. tostring(xuid) .. ", " .. tostring(top) .. ")") end
            -- in a match the game passes SR 0 for everyone: a real player (xuid not 0)
            -- gets our SR, the bots (all xuid 0) one step below ours
            if inMatch() then
                local key = tostring(xuid or "0")
                if key ~= "0" and key ~= "" then
                    sr = ourSR()
                else
                    -- all bots have xuid 0: the rank changes with each request, from
                    -- two steps below ours to one step above (Gold III: Gold I .. Platinum I)
                    G.botCalls = (G.botCalls or 0) + 1
                    local k = math.max(1, math.min(#steps, stepIndex(ourSR()) - 2 + (G.botCalls * 7) % 4))
                    sr = steps[k] + 10
                end
            end
            return original(sr, xuid, top, ...)
        end
    end
    if type(LP) == "table" and type(LP.GetParsedSREvent) == "function" then
        local original = LP.GetParsedSREvent
        local logged = 0
        LP.GetParsedSREvent = function(...)
            local results = { original(...) }
            if logged < 30 then
                logged = logged + 1
                local parts = {}
                for k = 1, select("#", ...) do parts[#parts + 1] = tostring((select(k, ...))) end
                local r = results[1]
                local rs = tostring(r)
                if type(r) == "table" then
                    local f = {}
                    for kk, vv in pairs(r) do f[#f + 1] = tostring(kk) .. "=" .. tostring(vv) end
                    rs = "{" .. table.concat(f, ", ") .. "}"
                end
                glog("GetParsedSREvent(" .. table.concat(parts, ", ") .. ") -> " .. rs)
            end
            return unpack(results)
        end
    end
    -- the official SR tracker of the HUD (BRSRMatchStatTracker) only changes on SR
    -- events sent by the servers: every second its number gets the SR of this match
    -- from our engine (jupiter/IO/br95_ranked_live.txt: entry cost + kills - deaths)
    local function findById(el, id, depth)
        if not el or depth > 12 then return nil end
        local eid
        pcall(function() eid = el.id end)
        if eid == id then return el end
        local child
        pcall(function() child = el:getFirstChild() end)
        while child do
            local found = findById(child, id, depth + 1)
            if found then return found end
            local nextChild
            pcall(function() nextChild = child:getNextSibling() end)
            child = nextChild
        end
    end
    -- The number of the tracker is written again by the game (its data subscription
    -- sets 0 every time): the number text keeps a setText of ours that always puts
    -- our value instead of a number. Texts that are not numbers stay as they are.
    -- the text of the tracker's "Count" comes back as a game string (not a Lua
    -- string): compared through tostring
    local function isNumber(t)
        if t == nil then return true end
        local s = tostring(t)
        return s == "" or s:match("^[%+%-]?%d+$") ~= nil
    end
    local function setNumbers(el, value, depth, report)
        if not el or depth > 8 then return end
        local ok, err = pcall(function()
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
                if report then report[#report + 1] = tostring(el.id) .. " '" .. tostring(t) .. "'" end
            end
            el._br95SetText(el, value)
        end)
        if not ok and report then report[#report + 1] = "error " .. tostring(err) end
        local child
        pcall(function() child = el:getFirstChild() end)
        while child do
            setNumbers(child, value, depth + 1, report)
            local nextChild
            pcall(function() nextChild = child:getNextSibling() end)
            child = nextChild
        end
    end
    local function liveDelta()
        local text = ""
        pcall(function()
            local f = io.open("jupiter/IO/br95_ranked_live.txt", "r")
            if f then text = f:read("*a") or ""; f:close() end
        end)
        local delta, active = text:match("^BR95L1|%-?%d+|%d+|%d+|(%-?%d+)|(%d+)|END")
        if active ~= "1" then return nil end
        return tonumber(delta)
    end
    G.updateTracker = function(root, own)
        if not inMatch() then return end
        local delta = liveDelta()
        if delta == nil then return end
        if not G.toldValue then G.toldValue = true; glog("SR tracker value " .. tostring(delta)) end
        G.srText = (delta > 0 and "+" or "") .. delta
        -- each tracker built updates itself (the HUD can build more than one)
        if own then
            local report = not own._br95Reported and {} or nil
            own._br95Reported = true
            setNumbers(own, G.srText, 0, report)
            if report then
                -- what the tracker is made of (ids, kinds, texts, sizes), to find its number
                local out = {}
                local function walk(el, depth)
                    if not el or depth > 10 then return end
                    local id, t, kind, rect = "", "", "", ""
                    pcall(function() id = tostring(el.id) end)
                    pcall(function() if el.getText then t = tostring(el:getText()) end end)
                    kind = (el.setText and "text" or "") .. (el.setImage and "image" or "") .. (el._br95Claimed and " claimed" or "")
                    pcall(function() rect = table.concat({ el:getLocalRect() }, ",") end)
                    local tt = ""
                    pcall(function() if el.getText then tt = type(el:getText()) end end)
                    out[#out + 1] = string.rep("  ", depth) .. id .. " [" .. kind .. "] '" .. t .. "' (" .. tt .. ") " .. rect
                    local child
                    pcall(function() child = el:getFirstChild() end)
                    while child do
                        walk(child, depth + 1)
                        local nextChild
                        pcall(function() nextChild = child:getNextSibling() end)
                        child = nextChild
                    end
                end
                walk(own, 0)
                local fields = {}
                pcall(function() for k, x in pairs(own) do fields[#fields + 1] = tostring(k) .. ":" .. type(x) end end)
                pcall(function()
                    local f = io.open("jupiter/IO/br95_srtracker.txt", "a")
                    if f then
                        f:write(os.date("%H:%M:%S") .. " claimed now: " .. table.concat(report, ", ") .. " -> " .. G.srText
                            .. " | same as G.tracker: " .. tostring(own == G.tracker) .. "\n" .. table.concat(out, "\n")
                            .. "\nfields: " .. table.concat(fields, " ") .. "\n\n")
                        f:close()
                    end
                end)
            end
            return
        end
        if not G.tracker and root then
            G.tracker = findById(root, "BRSRMatchStatTracker", 0)
            if G.tracker and not G.toldTracker then G.toldTracker = true; glog("SR tracker found") end
        end
        if G.tracker and not G.dumped then
            G.dumped = true
            local out = {}
            local function walk(el, depth)
                if not el or depth > 8 then return end
                local id, t, kind = "", "", ""
                pcall(function() id = tostring(el.id) end)
                pcall(function() if el.getText then t = tostring(el:getText()) end end)
                kind = (el.setText and "text" or "") .. (el.setImage and "image" or "")
                out[#out + 1] = string.rep(" ", depth) .. id .. " [" .. kind .. "] '" .. t .. "'"
                local child
                pcall(function() child = el:getFirstChild() end)
                while child do
                    walk(child, depth + 1)
                    local nextChild
                    pcall(function() nextChild = child:getNextSibling() end)
                    child = nextChild
                end
            end
            walk(G.tracker, 0)
            local fields = {}
            pcall(function() for k, x in pairs(G.tracker) do fields[#fields + 1] = tostring(k) .. ":" .. type(x) end end)
            glog("tracker tree:\n" .. table.concat(out, "\n") .. "\ntracker fields: " .. table.concat(fields, " "))
        end
        if G.tracker then setNumbers(G.tracker, G.srText, 0) end
    end

    -- the values the HUD watches (omnvars) while in a match
    local DSO = LUI and LUI.DataSourceFromOmnvar
    if DEBUG and type(DSO) == "table" and type(DSO.new) == "function" then
        local original = DSO.new
        local seen, n = {}, 0
        DSO.new = function(a, b, ...)
            local name = tostring(b ~= nil and type(a) == "table" and b or a)
            if n < 200 and inMatch() and not seen[name] then seen[name] = true; n = n + 1; glog("omnvar " .. name) end
            return original(a, b, ...)
        end
    end
end

-- the official ranked functions called in a match
do
    local LP = rawget(_G, "LeaguePlayUtils")
    if DEBUG and type(LP) == "table" then
        local seenCall = {}
        for name, fn in pairs(LP) do
            if type(fn) == "function" then
                local inner = fn
                LP[name] = function(...)
                    if not seenCall[name] and inMatch() then
                        seenCall[name] = true
                        glog("LP call in match: " .. tostring(name))
                    end
                    return inner(...)
                end
            end
        end
    end
    local C = rawget(_G, "CONDITIONS")
    if type(C) == "table" then
        local names = {}
        for k in pairs(C) do
            local s = tostring(k)
            if s:lower():find("league") or s:lower():find("ranked") or s:find("LP") or s:find("SR") then names[#names + 1] = s end
        end
        glog("CONDITIONS ranked-looking: " .. table.concat(names, " "))
        -- in a match of the RESURGENCE RANKED WARZONE playlist (br95_mode.txt = 1),
        -- the game is told it is a ranked match so it builds its official ranked HUD
        local function rankedMatch()
            if not inMatch() then return false end
            local text = ""
            pcall(function()
                local f = io.open("jupiter/IO/br95_mode.txt", "r")
                if f then text = f:read("*a") or ""; f:close() end
            end)
            return text:match("^BR95M1|(%d)") == "1"
        end
        local YES = { "IsBRLeaguePlayInGame", "IsLeaguePlayInGame", "InGameLP", "IsRankedMatch", "IsBRLeaguePlay",
            "IsLeaguePlay", "IsLeaguePlayEnabled", "IsWZLeaguePlayEnabled", "IsCoreLeaguePlayEnabled" }
        local NO = { "IsBRLPRankDisplayDisabled" }
        local function override(name, answer)
            local original = C[name]
            if type(original) ~= "function" then glog("condition " .. name .. " is " .. type(original)); return end
            C[name] = function(...)
                if rankedMatch() then
                    if not G["told" .. name] then G["told" .. name] = true; glog("condition " .. name .. " -> " .. tostring(answer)) end
                    return answer
                end
                return original(...)
            end
        end
        for _, name in ipairs(YES) do override(name, true) end
        for _, name in ipairs(NO) do override(name, false) end
    end
end

-- every second in a match: the official SR tracker shows our match SR
local function attachTracker(root)
    if not root or root._br95SRTracker then return end
    if LUI.primaryRoot and root ~= LUI.primaryRoot then return end
    root._br95SRTracker = true
    local watch = LUI.UIElement.new(); watch.id = "BR95SRTrackerWatch"
    root:addElement(watch)
    watch:registerEventHandler("br95_sr_tracker_tick", function()
        if G.updateTracker then pcall(G.updateTracker, root) end
    end)
    watch:addElement(LUI.UITimer.new({ interval = 1000, event = "br95_sr_tracker_tick", disposable = false, eventTarget = watch }))
end

if LUI and LUI.UIRoot and type(LUI.UIRoot.init) == "function" then
    local originalInit = LUI.UIRoot.init
    LUI.UIRoot.init = function(root, ...)
        local result = originalInit(root, ...)
        pcall(install)
        pcall(attachTracker, root)
        return result
    end
end
if LUI and LUI.roots then
    for _, root in pairs(LUI.roots) do pcall(attachTracker, root) end
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