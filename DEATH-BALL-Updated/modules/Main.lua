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

do
    local bindName = "DeathBallDirectionalAim"
    local mode, targetName = "Camera Offset", "None"
    local enabled, bound = false, false
    local yaw, pitch = 0, 0
    local activeState, heldDirection, sourceCamera, aimCamera, route, directionProvider
    local targetDropdown
    local aimEnv = getgenv and getgenv() or _G
    local routeKey = "DeathBallCamLookRouteV1"

    local function clearAim()
        sourceCamera, heldDirection = nil, nil
        if aimCamera then aimCamera:Destroy(); aimCamera = nil end
    end

    local function getRoute()
        local existing = aimEnv[routeKey]
        if existing then return existing end
        local remote = ReplicatedStorage:FindFirstChild("ReplicateCamLook")
        if not remote or not remote:IsA("UnreliableRemoteEvent")
            or type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then return nil end

        local state = {}
        local getMethod = getnamecallmethod
        local original
        local function redirect(object, ...)
            if object == remote and state.Provider and getMethod() == "FireServer" and select("#", ...) == 4 then
                local x, y, z, timestamp = ...
                if type(x) == "number" and type(y) == "number" and type(z) == "number" and type(timestamp) == "number" then
                    local direction = state.Provider()
                    if direction then return original(object, direction.X, direction.Y, direction.Z, timestamp) end
                end
            end
            return original(object, ...)
        end
        local ok, previous = pcall(function()
            return hookmetamethod(game, "__namecall", type(newcclosure) == "function" and newcclosure(redirect) or redirect)
        end)
        if not ok or type(previous) ~= "function" then return nil end
        original = previous
        aimEnv[routeKey] = state
        return state
    end

    local function liveRoot(player)
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        return humanoid and humanoid.Health > 0 and root or nil
    end

    local function targetDirection(origin)
        if mode == "Selected Player" then
            local player = Players:FindFirstChild(targetName)
            local root = player and player ~= LocalPlayer and liveRoot(player)
            return root and root.Position - origin or nil
        end
        local best, bestDistance
        for _, player in ipairs(Players:GetPlayers()) do
            local root = player ~= LocalPlayer and liveRoot(player)
            if root then
                local delta = root.Position - origin
                local distance = delta:Dot(delta)
                if not bestDistance or distance < bestDistance then
                    best, bestDistance = delta, distance
                end
            end
        end
        return best
    end

    local function updateAim()
        local camera = Workspace.CurrentCamera
        local root = liveRoot(LocalPlayer)
        if not activeState or activeState:Get() ~= true or not root
            or not camera or camera.CameraType == Enum.CameraType.Scriptable then
            clearAim()
            return
        end
        if sourceCamera ~= camera then clearAim() end
        sourceCamera = camera
        local base = camera.CFrame
        local direction
        if mode == "Hold Direction" then
            heldDirection = heldDirection or base.LookVector
            direction = heldDirection
        elseif mode == "Camera Offset" then
            direction = base.LookVector
        else
            direction = targetDirection(root.Position)
        end
        if not direction or direction.Magnitude < 0.001 then
            clearAim()
            return
        end

        local aim = CFrame.lookAlong(base.Position, direction)
        aim = CFrame.Angles(0, math.rad(yaw), 0) * (aim - base.Position)
            * CFrame.Angles(math.rad(pitch), 0, 0) + base.Position
        if not aimCamera then
            aimCamera = Instance.new("Camera")
            aimCamera.Name = "DeathBallAimCamera"
            aimCamera.CameraType = Enum.CameraType.Scriptable
        end
        aimCamera.FieldOfView = camera.FieldOfView
        aimCamera.Focus = camera.Focus
        aimCamera.CFrame = aim
    end

    local function stopAim()
        if bound then
            RunService:UnbindFromRenderStep(bindName)
            bound = false
        end
        if route and route.Provider == directionProvider then route.Provider = nil end
        route, directionProvider = nil, nil
        clearAim()
    end

    local function refreshTargets(excluded)
        local names = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player ~= excluded then
                table.insert(names, player.Name)
            end
        end
        table.sort(names)
        table.insert(names, 1, "None")
        targetDropdown:SetValues(names)
        if not table.find(names, targetName) then
            targetName = "None"
            targetDropdown:SetValue("None")
        end
    end

    Tabs.Main:AddSection("Ball Direction")
    Tabs.Main:AddToggle("BallDirectionalAim", {
        Title = "Directional Aim", Description = "Aim camera-directed hits without moving your view",
        Default = false,
        Callback = function(value)
            enabled = value == true and not PrimeRuntime.IsShuttingDown
            stopAim()
            if not enabled then return end
            if not activeState then
                local ok, values = pcall(PrimeRuntime.Require, ReplicatedStorage:FindFirstChild("Values"))
                if ok and values then activeState = values.PLAYER_ACTIVE_STATE end
            end
            if not enabled or bound or PrimeRuntime.IsShuttingDown or not activeState then return end
            route = getRoute()
            if not route then
                warn("[DeathBall] Directional Aim requires supported camera routing")
                local option = Options.BallDirectionalAim
                if option then option:SetValue(false) end
                return
            end
            directionProvider = function()
                if aimCamera then return aimCamera.CFrame.LookVector end
            end
            route.Provider = directionProvider
            RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 1, updateAim)
            bound = true
        end,
    })
    Tabs.Main:AddDropdown("BallAimMode", {
        Title = "Aim Mode", Values = {"Camera Offset", "Hold Direction", "Closest Player", "Selected Player"},
        Default = "Camera Offset",
        Callback = function(value)
            mode = value
            clearAim()
        end,
    })
    targetDropdown = Tabs.Main:AddDropdown("BallAimTarget", {
        Title = "Aim Target", Values = {"None"}, Default = "None",
        Callback = function(value) targetName = value or "None" end,
    })
    Tabs.Main:AddSlider("BallAimYaw", {
        Title = "Horizontal Angle", Min = -180, Max = 180, Default = 0, Rounding = 0,
        Callback = function(value) yaw = value end,
    })
    Tabs.Main:AddSlider("BallAimPitch", {
        Title = "Vertical Angle", Min = -60, Max = 60, Default = 0, Rounding = 0,
        Callback = function(value) pitch = value end,
    })
    refreshTargets()
    TrackRuntimeConnection(Players.PlayerAdded:Connect(function() refreshTargets() end))
    TrackRuntimeConnection(Players.PlayerRemoving:Connect(refreshTargets))
    TrackRuntimeCleanup(function()
        enabled = false
        stopAim()
    end)
end
