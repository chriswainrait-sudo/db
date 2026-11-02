Tabs.Main:AddSection("Main")
Tabs.Main:AddParagraph({Title = "Welcome", Content = "Thank you for being with us! Configure Death Ball features below."})

local readyEnabled, readyEpoch = false, 0
local readyConnection, readyOriginal
local function stopReady()
    readyEpoch = readyEpoch + 1
    if readyConnection then readyConnection:Disconnect(); readyConnection = nil end
    if readyOriginal then
        local original = readyOriginal
        readyOriginal = nil
        pcall(function()
            if original.Part.Parent then
                original.Part.Size = original.Size
                original.Part.Transparency = original.Transparency
                original.Part.CanCollide = original.CanCollide
            end
        end)
    end
end
Tabs.Main:AddToggle("autoready", {
    Title = "Auto Ready", Description = "Automatically readies you at the start of rounds", Default = false,
    Callback = function(enabled)
        readyEnabled = enabled == true and not PrimeRuntime.IsShuttingDown
        stopReady()
        if not readyEnabled then return end
        local epoch = readyEpoch
        task.spawn(function()
            local function current() return readyEnabled and epoch == readyEpoch and not PrimeRuntime.IsShuttingDown end
            local lobby = Workspace:WaitForChild("New Lobby", 5)
            if not lobby or not current() then return end
            local area = lobby:WaitForChild("ReadyArea", 5)
            if not area or not current() then return end
            local zone = area:WaitForChild("ReadyZone", 5)
            if not current() or not zone or not zone:IsA("BasePart") then return end
            readyOriginal = {Part = zone, Size = zone.Size, Transparency = zone.Transparency, CanCollide = zone.CanCollide}
            local size = zone.Size * 60
            readyConnection = RunService.Heartbeat:Connect(function()
                if not current() or not zone.Parent then stopReady(); return end
                zone.Size, zone.CanCollide, zone.Transparency = size, false, 1
            end)
        end)
    end
})
TrackRuntimeCleanup(function() readyEnabled = false; stopReady() end)

local originalFov = setmetatable({}, {__mode = "k"})
local initialCamera = Workspace.CurrentCamera
local desiredFov = initialCamera and math.clamp(initialCamera.FieldOfView, 70, 120) or 70
local originalZoom = LocalPlayer.CameraMaxZoomDistance
Tabs.Main:AddSlider("fov", {
    Title = "FOV Value", Description = "Adjust your field of view (70-120)",
    Default = desiredFov, Min = 70, Max = 120, Rounding = 0,
    Callback = function(value) desiredFov = value end
})
TrackRuntimeConnection(RunService.RenderStepped:Connect(function()
    if PrimeRuntime.IsShuttingDown then return end
    local camera = Workspace.CurrentCamera
    if camera then
        if originalFov[camera] == nil then originalFov[camera] = camera.FieldOfView end
        if camera.FieldOfView ~= desiredFov then camera.FieldOfView = desiredFov end
    end
end))
Tabs.Main:AddSlider("maxzoom", {
    Title = "Max Zoom", Default = 45, Min = 45, Max = 200, Rounding = 0,
    Callback = function(value) LocalPlayer.CameraMaxZoomDistance = value end
})
TrackRuntimeCleanup(function()
    for camera, value in pairs(originalFov) do pcall(function() camera.FieldOfView = value end) end
    LocalPlayer.CameraMaxZoomDistance = originalZoom
end)

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local hudConnection, replacementExpected
local function bindHud(hud)
    if hudConnection then hudConnection:Disconnect(); hudConnection = nil end
    if not hud then return end
    hudConnection = hud.AncestryChanged:Connect(function()
        if not hud.Parent and not PrimeRuntime.IsShuttingDown then replacementExpected = true end
    end)
end
bindHud(playerGui:FindFirstChild("HUD"))
TrackRuntimeConnection(playerGui.ChildAdded:Connect(function(child)
    if child.Name ~= "HUD" or PrimeRuntime.IsShuttingDown then return end
    bindHud(child)
    if replacementExpected then
        replacementExpected = false
        for _, object in ipairs(child:GetDescendants()) do
            if object:IsA("GuiObject") then object.Visible = true end
        end
    end
end))
TrackRuntimeCleanup(function() if hudConnection then hudConnection:Disconnect(); hudConnection = nil end end)
