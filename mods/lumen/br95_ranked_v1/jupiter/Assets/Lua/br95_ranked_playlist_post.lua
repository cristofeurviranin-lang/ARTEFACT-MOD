-- BR95 Ranked playlist: adds "RESURGENCE RANKED WARZONE" to Lumen's list of private
-- match modes (Rebirth Island tab, right after REBIRTH_RESURGENCE_QUADS). It is a copy
-- of the Rebirth Resurgence quads preset (same Lumen preset id 4: same map, mode and
-- squads); picking it writes jupiter/IO/br95_mode.txt = BR95M1|1|...|END so that
-- br95_ranked.gscc counts the match, every other preset writes 0 (normal match, no SR).
-- A Lumen preset record keys its fields by hash: the name is the field ...c4bcadba8e631b86.
-- What the preset buttons receive is traced once to jupiter/IO/br95_playlist_trace.txt.
-- Wrapped in pcall: if anything is missing Lumen's list stays as it was.
if BR95RankedPlaylist then return end
local state = {}
BR95RankedPlaylist = state

local RANKED_NAME = "RESURGENCE RANKED WARZONE"
local SOURCE_NAME = "rebirth_resurgence_quads"
local NAME_KEY = "c4bcadba8e631b86"
local ID_KEY = "8b72e07b55c3ac0"        -- preset id field of a Lumen preset record
local LAUNCH_KEY = "c730e9e88337bfc4"   -- CLUA function that starts a preset
local MODE_FILE = "jupiter/IO/br95_mode.txt"
local TRACE_FILE = "jupiter/IO/br95_playlist_trace.txt"

local function writeFile(path, text)
    pcall(function()
        local f = io.open(path, "w")
        if f then f:write(text); f:close() end
    end)
end

local function nameKey(record)
    if type(record) ~= "table" then return nil end
    for key in pairs(record) do
        if tostring(key):find(NAME_KEY, 1, true) then return key end
    end
end

local function nameOf(record)
    local key = nameKey(record)
    return key and record[key]
end

local function upvalue(fn, wanted)
    if type(fn) ~= "function" or not debug or not debug.getupvalue then return nil end
    for i = 1, 40 do
        local name, value = debug.getupvalue(fn, i)
        if not name then return nil end
        if name == wanted then return value, i end
    end
end

-- the ranked copy goes right after the Rebirth Resurgence quads preset
local function addRanked(list)
    if type(list) ~= "table" then return false end
    local sourceIndex
    for i, record in ipairs(list) do
        local name = nameOf(record)
        if name == RANKED_NAME then return true end
        if name == SOURCE_NAME then sourceIndex = i end
    end
    if not sourceIndex then return false end
    local copy = {}
    local idKey, idValue
    for key, value in pairs(list[sourceIndex]) do
        if tostring(key):find(ID_KEY, 1, true) then idKey, idValue = key, value else copy[key] = value end
    end
    copy[nameKey(copy)] = RANKED_NAME
    -- the preset id is read through a metatable: the time of the read tells the
    -- launch hook below that the ranked copy is the one being started
    if idKey then
        setmetatable(copy, { __index = function(_, key)
            if key == idKey then state.rankedReadAt = os.clock(); return idValue end
        end })
    end
    table.insert(list, sourceIndex + 1, copy)
    return true
end

-- Lumen starts a preset with a CLUA function (key ...c730e9e88337bfc4) given the
-- preset id; the ranked copy has the same id, so it is told apart by the read just
-- before (same click)
local function hookLaunch()
    if state.launchHooked then return end
    local clua = rawget(_G, "CLUA")
    if type(clua) ~= "table" then return end
    for key, fn in pairs(clua) do
        if type(fn) == "function" and tostring(key):find(LAUNCH_KEY, 1, true) then
            clua[key] = function(id, ...)
                local delta = state.rankedReadAt and (os.clock() - state.rankedReadAt)
                local ranked = delta ~= nil and delta < 0.25
                state.rankedReadAt = nil
                local extra = {}
                for i = 1, select("#", ...) do local v = select(i, ...); extra[#extra + 1] = type(v) .. ":" .. tostring(v) end
                writeFile(TRACE_FILE, "launch id=" .. tostring(id) .. " extra args [" .. table.concat(extra, ", ") .. "] ranked read " .. tostring(delta) .. " s before -> ranked=" .. tostring(ranked) .. "\n")
                writeFile(MODE_FILE, "BR95M1|" .. (ranked and "1" or "0") .. "|" .. (ranked and RANKED_NAME or ("preset " .. tostring(id))) .. "|END")
                return fn(id, ...)
            end
            state.launchHooked = true
            return
        end
    end
end

-- Lumen fills AvailablePresets in BuildAvailablePresets: add the copy after each build
local function hookBuild()
    if state.hooked then return end
    local menu = rawget(_G, "PresetModesMenu")
    local build, index = upvalue(menu, "BuildAvailablePresets")
    if type(build) ~= "function" then return end
    local wrapped = function(...)
        local results = { build(...) }
        pcall(addRanked, upvalue(build, "AvailablePresets"))
        state.list = upvalue(build, "AvailablePresets") or state.list
        pcall(state.dumpPresets, menu, build)
        return unpack(results)
    end
    debug.setupvalue(menu, index, wrapped)
    -- the other functions of the preset screen may hold it too
    for _, other in ipairs({ "GeneratePresetTabs", "SetupPresetMenu" }) do
        local fn = upvalue(menu, other)
        local _, i = upvalue(fn, "BuildAvailablePresets")
        if i then debug.setupvalue(fn, i, wrapped) end
    end
    state.hooked = true
    state.list = upvalue(build, "AvailablePresets")
    pcall(addRanked, state.list)
    pcall(state.dumpPresets, menu, build)
end

-- the official Warzone menu (br95_wzplay_post.lua) needs the presets before Lumen's
-- preset screen was ever opened: Lumen's own BuildAvailablePresets fills the list
state.ensureList = function()
    if type(state.list) == "table" and #state.list > 0 then return state.list end
    pcall(hookBuild)
    local menu = rawget(_G, "PresetModesMenu")
    local build = upvalue(menu, "BuildAvailablePresets")
    local real = upvalue(build, "build") or build
    local e1, e2
    if type(build) == "function" then
        local ok, err = pcall(build)
        e1 = tostring(ok) .. " " .. tostring(err)
        state.list = upvalue(real, "AvailablePresets") or state.list
        -- maybe it wants the controller
        if type(state.list) ~= "table" or #state.list == 0 then
            ok, err = pcall(build, 0)
            e2 = tostring(ok) .. " " .. tostring(err)
        end
    end
    state.list = upvalue(real, "AvailablePresets") or state.list
    pcall(addRanked, state.list)
    -- what was found (for the official menu): jupiter/IO/br95_wzplay_status.txt
    pcall(function()
        local clua = rawget(_G, "CLUA")
        local gm = type(clua) == "table" and clua.Gamemodes
        local first = ""
        if type(gm) == "table" then
            local n = 0
            for k, v in pairs(gm) do
                n = n + 1
                if n == 1 then
                    first = tostring(k) .. "="
                    if type(v) == "table" then for kk, vv in pairs(v) do first = first .. tostring(kk) .. ":" .. tostring(vv) .. " " end else first = first .. tostring(v) end
                end
            end
            first = n .. " entries, first " .. first
        end
        local f = io.open("jupiter/IO/br95_wzplay_status.txt", "a")
        if f then
            f:write(os.date("%H:%M:%S") .. " ensureList: menu " .. type(menu) .. ", build " .. type(build) .. ", call " .. tostring(e1)
                .. ", call(0) " .. tostring(e2) .. ", presets " .. (type(state.list) == "table" and #state.list or -1)
                .. "\n  CLUA.Gamemodes: " .. type(gm) .. " " .. first .. "\n")
            f:close()
        end
    end)
    return state.list
end

-- one-time survey for the horizontal Warzone menu: every preset record (all its
-- fields) and the names of the preset screen's helpers, in br95_presets_dump.txt
state.dumpPresets = function(menu, build)
    if state.dumped then return end
    if type(state.list) ~= "table" or #state.list == 0 then
        writeFile("jupiter/IO/br95_presets_dump.txt", "no presets yet: list " .. type(state.list) .. " build " .. type(build))
        return
    end
    state.dumped = true
    local out = { "presets: " .. #state.list }
    for i, record in ipairs(state.list) do
        local fields = {}
        for k, v in pairs(record) do
            local value = type(v) == "table" and ("table#" .. #v) or tostring(v)
            fields[#fields + 1] = tostring(k) .. "=" .. value
        end
        out[#out + 1] = i .. ": " .. table.concat(fields, " | ")
    end
    for _, fn in ipairs({ menu, build }) do
        local names = {}
        for i = 1, 60 do
            local name, value = debug.getupvalue(fn, i)
            if not name then break end
            names[#names + 1] = name .. ":" .. type(value)
        end
        out[#out + 1] = "upvalues: " .. table.concat(names, " ")
    end
    local clua = rawget(_G, "CLUA")
    if type(clua) == "table" then
        local keys = {}
        for k, v in pairs(clua) do keys[#keys + 1] = tostring(k) .. ":" .. type(v) end
        out[#out + 1] = "CLUA: " .. table.concat(keys, " ")
    end
    writeFile("jupiter/IO/br95_presets_dump.txt", table.concat(out, "\n"))
end

-- finds the preset record a button was built for, in its options
local function recordIn(value, depth)
    if type(value) ~= "table" or depth > 2 then return nil end
    if nameOf(value) then return value end
    for _, x in pairs(value) do
        local found = recordIn(x, depth + 1)
        if found then return found end
    end
end

local function trace(options)
    if state.traced then return end
    state.traced = true
    local parts = {}
    if type(options) == "table" then
        for k, v in pairs(options) do parts[#parts + 1] = tostring(k) .. "=" .. type(v) end
    end
    local record = recordIn(options, 0)
    writeFile(TRACE_FILE, "PresetModeButton options: " .. table.concat(parts, " ")
        .. "\nrecord found: " .. tostring(record ~= nil) .. " name=" .. tostring(record and nameOf(record)) .. "\n")
end

if type(MenuBuilder) == "table" and type(MenuBuilder.BuildRegisteredType) == "function" then
    local original = MenuBuilder.BuildRegisteredType
    MenuBuilder.BuildRegisteredType = function(name, options, ...)
        local key = tostring(name)
        if key == "PresetModesMenu" then pcall(hookBuild); pcall(addRanked, state.list); pcall(hookLaunch) end
        local result = original(name, options, ...)
        if key == "PresetModesMenu" then
            pcall(function()
                local menu = rawget(_G, "PresetModesMenu")
                local build = upvalue(menu, "BuildAvailablePresets")
                -- the wrapped build keeps the real one as its upvalue "build"
                local real = upvalue(build, "build") or build
                state.list = upvalue(real, "AvailablePresets") or state.list
                state.dumpPresets(menu, real)
            end)
        end
        if key == "PresetModeButton" and result then
            pcall(trace, options)
            local record = recordIn(options, 0)
            local presetName = record and nameOf(record)
            if presetName then
                pcall(function()
                    result:addEventHandler("button_action", function()
                        local ranked = presetName == RANKED_NAME
                        writeFile(MODE_FILE, "BR95M1|" .. (ranked and "1" or "0") .. "|" .. presetName .. "|END")
                    end)
                end)
            end
        end
        return result
    end
end

if LUI and LUI.UIRoot and type(LUI.UIRoot.init) == "function" then
    local originalInit = LUI.UIRoot.init
    LUI.UIRoot.init = function(root, ...)
        local result = originalInit(root, ...)
        pcall(hookBuild)
        return result
    end
end
pcall(hookBuild)
