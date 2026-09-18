local ADDON = ...
local SOUND = "Interface/AddOns/" .. ADDON .. "/rage.ogg"
local RAGE = Enum.PowerType.Rage

local defaults = {
    enabled  = true,
    cooldown = 30,        -- seconds between plays
    channel  = "Master",  -- Master | SFX | Music | Ambience | Dialog
}

local db
local lastPlayed = 0
local soundHandle
local verbose = false

local isSecret = issecretvalue or function() return false end

local function Print(msg)
    print("|cffc41f3bRageKnowsNoBounds|r: " .. msg)
end

local function Readable(v)
    return v ~= nil and not isSecret(v)
end

local function Play(force, source)
    if not force then
        if not db.enabled then return end
        if GetTime() - lastPlayed < math.max(db.cooldown, 2) then return end
    end
    if soundHandle then StopSound(soundHandle) end
    local ok, handle = PlaySoundFile(SOUND, db.channel)
    if ok then
        soundHandle = handle
        lastPlayed = GetTime()
        if verbose and source then Print("played (trigger: " .. source .. ")") end
    else
        Print("could not play rage.ogg. The file must exist before the game launches.")
    end
end

local function IsWarrior()
    local _, class = UnitClass("player")
    return class == "WARRIOR"
end

local function ReadMax()
    local max = UnitPowerMax("player", RAGE)
    if Readable(max) and max > 0 then return max end
    return nil
end

------------------------------------------------------------------------
-- Trigger 1: Blizzard's own player frame.
-- Blizzard code runs secure and can compare secret values. In the modern
-- PlayerFrame the mana bar owns a FullPowerFrame that plays a spike/pulse
-- animation when power caps. Hooking OnPlay on those animation groups is
-- allowed and fires regardless of taint.
------------------------------------------------------------------------
local fullPower = { frame = nil, path = nil, hooked = 0, plays = 0 }

local function FindFullPowerFrame()
    if not PlayerFrame then return nil end
    local seen = {}
    local function walk(t, path, depth)
        if depth > 7 or type(t) ~= "table" or seen[t] then return nil end
        seen[t] = true
        for k, v in pairs(t) do
            if type(k) == "string" and type(v) == "table" and k:find("FullPower") then
                return v, path .. "." .. k
            end
        end
        for k, v in pairs(t) do
            if type(k) == "string" and type(v) == "table" and v.GetObjectType then
                local r, p = walk(v, path .. "." .. k, depth + 1)
                if r then return r, p end
            end
        end
        return nil
    end
    return walk(PlayerFrame, "PlayerFrame", 0)
end

local function HookAnimGroups(t, depth)
    if depth > 3 or type(t) ~= "table" then return end
    for k, v in pairs(t) do
        if type(k) == "string" and type(v) == "table" and v.GetObjectType then
            local ok, ty = pcall(v.GetObjectType, v)
            if ok and ty == "AnimationGroup" then
                -- SpikeAnim plays the moment power caps. PulseAnim follows it
                -- and FadeoutAnim plays when power drops below max, so only
                -- the spike is a trigger.
                local trigger = (k == "SpikeAnim" or k == "AlertSpikeAnim")
                v:HookScript("OnPlay", function()
                    fullPower.plays = fullPower.plays + 1
                    if verbose then Print("Blizzard full-power animation played: " .. k) end
                    if trigger then Play(false, "PlayerFrame " .. k) end
                end)
                fullPower.hooked = fullPower.hooked + 1
            elseif ok then
                HookAnimGroups(v, depth + 1)
            end
        end
    end
end

local function SetupFullPowerHook()
    local ok, frame, path = pcall(FindFullPowerFrame)
    if ok and frame then
        fullPower.frame = frame
        fullPower.path = path
        HookAnimGroups(frame, 0)
    end
end

------------------------------------------------------------------------
-- Trigger 2: size-change sensor.
-- A hidden StatusBar with range (max-1, max) is fed the secret rage value.
-- Its fill texture has width 0 for any rage below max and full width at
-- max, so the texture only changes size when rage crosses into or out of
-- max. A frame anchored to the texture's corners gets OnSizeChanged on
-- each crossing. We never read a value; we just count crossings, which
-- alternate: enter max, leave max, enter max...
------------------------------------------------------------------------
local sensor = { atMax = false, armed = false, fires = 0, ignored = 0 }

local sbar = CreateFrame("StatusBar", nil, UIParent)
sbar:SetSize(200, 8)
sbar:SetPoint("TOP", UIParent, "TOP", 0, 40)
sbar:SetStatusBarTexture("Interface/Buttons/WHITE8x8")
sbar:SetAlpha(0)
sbar:EnableMouse(false)
sbar:Show()

local stex = sbar:GetStatusBarTexture()
local sframe = CreateFrame("Frame", nil, sbar)
sframe:SetPoint("TOPLEFT", stex, "TOPLEFT")
sframe:SetPoint("BOTTOMRIGHT", stex, "BOTTOMRIGHT")
sframe:SetScript("OnSizeChanged", function()
    sensor.fires = sensor.fires + 1
    if not sensor.armed then
        sensor.ignored = sensor.ignored + 1
        return
    end
    sensor.atMax = not sensor.atMax
    if verbose then Print("sensor fired, now " .. (sensor.atMax and "AT MAX" or "below max")) end
    -- the Blizzard hook is the primary trigger; the sensor only plays
    -- when no FullPowerFrame was found on this client
    if sensor.atMax and not fullPower.frame then Play(false, "sensor") end
end)

local function FeedSensor()
    pcall(sbar.SetValue, sbar, UnitPower("player", RAGE))
end

local function ArmSensor()
    local max = ReadMax()
    if not max then return end
    sensor.armed = false
    sbar:SetMinMaxValues(max - 1, max)
    FeedSensor()
    -- let the initial layout settle before counting crossings; assumes
    -- rage is not at max at this moment (true at login / after max change)
    C_Timer.After(1, function()
        sensor.atMax = false
        sensor.armed = true
    end)
end

------------------------------------------------------------------------
-- Trigger 3: plain value read, in case it is ever readable.
------------------------------------------------------------------------
local wasMaxed = false
local function CheckReadable()
    local max = ReadMax()
    if not max then return end
    local cur = UnitPower("player", RAGE)
    if not Readable(cur) then return end
    if cur >= max then
        if not wasMaxed then
            wasMaxed = true
            Play(false, "UnitPower")
        end
    else
        wasMaxed = false
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        RageKnowsNoBoundsDB = RageKnowsNoBoundsDB or {}
        db = RageKnowsNoBoundsDB
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = v end
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        if IsWarrior() then
            self:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
            self:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
            self:RegisterUnitEvent("UNIT_MAXPOWER", "player")
            SetupFullPowerHook()
            ArmSensor()
            CheckReadable()
        end
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
        if arg2 == "RAGE" then
            FeedSensor()
            CheckReadable()
        end
    elseif event == "UNIT_MAXPOWER" then
        ArmSensor()
        CheckReadable()
    end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local function Debug()
    local max = ReadMax()
    Print("debug (" .. (InCombatLockdown() and "in combat" or "out of combat") .. ")")
    print("  max rage: " .. tostring(max))
    print("  UnitPower secret: " .. tostring(isSecret(UnitPower("player", RAGE))))
    if fullPower.frame then
        print("  Blizzard FullPowerFrame: found at " .. fullPower.path
            .. ", anim groups hooked: " .. fullPower.hooked
            .. ", plays seen: " .. fullPower.plays)
    else
        print("  Blizzard FullPowerFrame: not found")
    end
    print("  sensor: armed=" .. tostring(sensor.armed)
        .. " atMax=" .. tostring(sensor.atMax)
        .. " fires=" .. sensor.fires
        .. " (ignored during arming: " .. sensor.ignored .. ")")
    print("  verbose: " .. tostring(verbose))
end

SLASH_RAGEKNOWSNOBOUNDS1 = "/rage"
SlashCmdList.RAGEKNOWSNOBOUNDS = function(input)
    local cmd, rest = input:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "test" then
        Play(true)
    elseif cmd == "debug" then
        Debug()
    elseif cmd == "verbose" then
        verbose = not verbose
        Print("verbose " .. (verbose and "on" or "off"))
    elseif cmd == "reset" then
        ArmSensor()
        Print("sensor re-armed (assumes rage is not at max right now)")
    elseif cmd == "on" then
        db.enabled = true
        Print("enabled")
    elseif cmd == "off" then
        db.enabled = false
        Print("disabled")
    elseif cmd == "cd" or cmd == "cooldown" then
        local n = tonumber(rest)
        if n and n >= 0 then
            db.cooldown = n
            Print("cooldown set to " .. n .. "s")
        else
            Print("cooldown is " .. db.cooldown .. "s. Usage: /rage cd <seconds>")
        end
    elseif cmd == "channel" then
        local c = rest:match("^%S+")
        local valid = { master = "Master", sfx = "SFX", music = "Music", ambience = "Ambience", dialog = "Dialog" }
        if c and valid[c:lower()] then
            db.channel = valid[c:lower()]
            Print("channel set to " .. db.channel)
        else
            Print("channel is " .. db.channel .. ". Usage: /rage channel master|sfx|music|ambience|dialog")
        end
    else
        Print("commands:")
        print("  /rage test          play the clip now")
        print("  /rage debug         show trigger status")
        print("  /rage verbose       print a line whenever a trigger fires")
        print("  /rage reset         re-arm the sensor (do this while rage is not full)")
        print("  /rage on | off      toggle (currently " .. (db.enabled and "on" or "off") .. ")")
        print("  /rage cd <seconds>  minimum time between plays (currently " .. db.cooldown .. "s)")
        print("  /rage channel <x>   master, sfx, music, ambience, dialog (currently " .. db.channel .. ")")
        if not IsWarrior() then print("  (not a warrior: rage watching is inactive on this character)") end
    end
end
