

local PRIME_ENV = (getgenv and getgenv()) or _G
local PRIME_RUNTIME_KEY = "__PRIME_DEATH_BALL_RUNTIME_V2"
local previousRuntime = PRIME_ENV[PRIME_RUNTIME_KEY]
if type(previousRuntime) == "table" and type(previousRuntime.Shutdown) == "function" then
    pcall(previousRuntime.Shutdown)
end

local PrimeRuntime = {
    Shutdown = nil,
    Connections = {},
    Cleanups = {},
    IsShuttingDown = false
}
PRIME_ENV[PRIME_RUNTIME_KEY] = PrimeRuntime
PrimeRuntime.Errors = {}
local readThreadIdentity = getthreadidentity or getidentity
local writeThreadIdentity = setthreadidentity or setidentity
function PrimeRuntime.Protect(callback, ...)
    local identity
    if type(readThreadIdentity) == "function" and type(writeThreadIdentity) == "function" then
        local ok, current = pcall(readThreadIdentity)
        if ok then identity = current end
    end
    local result = table.pack(pcall(callback, ...))
    if identity ~= nil then
        local restored, failure = pcall(writeThreadIdentity, identity)
        if not restored then return false, "Context restore failed: " .. tostring(failure) end
    end
    return table.unpack(result, 1, result.n)
end
function PrimeRuntime.Run(n, f)
    local ok, e = PrimeRuntime.Protect(f)
    if not ok then
        table.insert(PrimeRuntime.Errors, n .. ": " .. tostring(e))
        warn("DeathBall/" .. n .. ": " .. tostring(e))
    end
    return ok
end

local function TrackRuntimeConnection(connection)
    if connection then
        table.insert(PrimeRuntime.Connections, connection)
    end
    return connection
end

local function TrackRuntimeCleanup(callback)
    if type(callback) == "function" then
        table.insert(PrimeRuntime.Cleanups, callback)
    end
    return callback
end

local UIEnvironment
local NexusUI, Window, Tabs, Options
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local IS_MOBILE
local function Shutdown()
    if PrimeRuntime.IsShuttingDown then return end
    PrimeRuntime.IsShuttingDown = true
    if Options then
        for _, option in pairs(Options) do
            if type(option) == "table" and option.IsToggle and option.Value then pcall(option.SetValue, option, false) end
        end
    end
    local activeWindow = Window or UIEnvironment and UIEnvironment.Window
    if activeWindow then
        pcall(activeWindow.Destroy, activeWindow)
    elseif UIEnvironment then
        local ui = NexusUI or UIEnvironment.NexusUI
        if ui and type(ui.UnloadFeatures) == "function" then pcall(ui.UnloadFeatures, ui) end
        local parent = UIEnvironment.GuiParent
        local partial = parent and parent:FindFirstChild("NexusDeathBallUI")
        if partial then pcall(partial.Destroy, partial) end
    end
    for index = #PrimeRuntime.Cleanups, 1, -1 do pcall(PrimeRuntime.Cleanups[index]) end
    table.clear(PrimeRuntime.Cleanups)
    for _, connection in ipairs(PrimeRuntime.Connections) do
        pcall(function() if connection and connection.Connected then connection:Disconnect() end end)
    end
    table.clear(PrimeRuntime.Connections)
    if PRIME_ENV[PRIME_RUNTIME_KEY] == PrimeRuntime then PRIME_ENV[PRIME_RUNTIME_KEY] = nil end
end
PrimeRuntime.Shutdown = Shutdown

function PrimeRuntime.Require(module)
    assert(module and module:IsA("ModuleScript"), "Death Ball: game module is unavailable")
    local ok, result = PrimeRuntime.Protect(require, module)
    if not ok then error(result, 0) end
    return result
end
