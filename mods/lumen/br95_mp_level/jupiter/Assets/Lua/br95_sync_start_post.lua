-- BR95 world ranking: starts the sync program (jupiter/BR95/BR95Sync.exe) with the
-- game, so the player has nothing to start by hand. The program quits by itself
-- some time after the game is closed. It only sends something after the player
-- entered the ranking in the game (WORLD RANKING button of the main menu).
-- The result is written to jupiter/IO/br95_autostart.txt (what a missing launch
-- would show: "os.execute unavailable" or "exe missing").
if BR95SyncStart then return end
local state = {}
BR95SyncStart = state

local EXE_FILE = "jupiter/BR95/BR95Sync.exe"
local EXE_CMD = "jupiter\\BR95\\BR95Sync.exe"
local RESULT_FILE = "jupiter/IO/br95_autostart.txt"

local function writeResult(text)
    pcall(function()
        local f = io.open(RESULT_FILE, "w")
        if f then f:write(text .. "\n"); f:close() end
    end)
end

local function start()
    local f = io.open(EXE_FILE, "rb")
    if not f then writeResult("exe missing"); return end
    f:close()
    if type(os) ~= "table" or type(os.execute) ~= "function" then
        writeResult("os.execute unavailable")
        return
    end
    local ok, err = pcall(os.execute, 'start "" "' .. EXE_CMD .. '" --follow-game')
    writeResult("started ok=" .. tostring(ok) .. " " .. tostring(err))
end

pcall(start)
