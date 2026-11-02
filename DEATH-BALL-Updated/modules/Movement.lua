local player = LocalPlayer
local flyConnection = nil
local flyEnabled = false
local flySpeed = 50
local speedHackEnabled = false
local speedHackValue = 50
local speedHackConnection = nil
local originalSpeedValue = nil
local jumpPowerEnabled = false
local jumpPowerValue = 50
local jumpPowerConnection = nil
local originalJumpPowerValue = nil
local allConnections = {}
local allToggles = {}

local function enableFly()
    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChild("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then return end
    if flyConnection then flyConnection:Disconnect() end
    local wasBodyVelocity = false
    flyConnection = RunService.RenderStepped:Connect(function()
        local currentChar = player.Character
        local currentRootPart = currentChar and currentChar:FindFirstChild("HumanoidRootPart")
        if not flyEnabled or not currentRootPart then return end
        local camCF = workspace.CurrentCamera.CFrame
        local moveVec = Vector3.new()
        if IS_MOBILE then
            moveVec = moveVec + camCF.LookVector
        else
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVec = moveVec + camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVec = moveVec - camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVec = moveVec - camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVec = moveVec + camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveVec = moveVec + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                moveVec = moveVec - Vector3.new(0, 1, 0)
            end
        end
        if moveVec.Magnitude > 0 then
            moveVec = moveVec.Unit * flySpeed
            currentRootPart.Velocity = moveVec
            wasBodyVelocity = true
        else
            if wasBodyVelocity then currentRootPart.Velocity = Vector3.zero end
        end
    end)
end

local function disableFly()
    if flyConnection then flyConnection:Disconnect(); flyConnection = nil end
    local character = player.Character
    if character then
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if rootPart then rootPart.Velocity = Vector3.zero end
    end
end

local function getMovementHandler()
    local ReplicatedFirst = game:GetService("ReplicatedFirst")
    local Classes = ReplicatedFirst:FindFirstChild("Classes")
    if not Classes then return nil end
    local PlayerControl = Classes:FindFirstChild("PlayerControl")
    if not PlayerControl then return nil end
    local success, result = PrimeRuntime.Protect(require, PlayerControl)
    if success then return result end
    return nil
end

local function applySpeedHack()
    if not speedHackEnabled then return end
    if originalSpeedValue == nil then
        local control = getMovementHandler()
        if control and control.Movement then originalSpeedValue = {Control = control, RunSpeed = control.Movement.RunSpeed, OverrideWalkSpeed = control.Movement.OverrideWalkSpeed} end
    end
    if speedHackConnection then speedHackConnection:Disconnect() end
    speedHackConnection = RunService.Heartbeat:Connect(function()
        if speedHackEnabled then
            local control = getMovementHandler()
            if control and control.Movement then
                control.Movement.RunSpeed = speedHackValue
                control.Movement.OverrideWalkSpeed = speedHackValue
            end
        end
    end)
    table.insert(allConnections, speedHackConnection)
end

local function disableSpeedHack()
    if speedHackConnection then speedHackConnection:Disconnect(); speedHackConnection = nil end
    if originalSpeedValue ~= nil then
        local control = originalSpeedValue.Control
        if control and control.Movement then
            control.Movement.RunSpeed = originalSpeedValue.RunSpeed
            control.Movement.OverrideWalkSpeed = originalSpeedValue.OverrideWalkSpeed
        end
        originalSpeedValue = nil
    end
end

local function applyJumpPower()
    if not jumpPowerEnabled then return end
    if originalJumpPowerValue == nil then
        local control = getMovementHandler()
        if control and control.Movement then originalJumpPowerValue = {Control = control, DoubleJumpPower = control.Movement.DoubleJumpPower, Humanoid = control.Movement.Humanoid, JumpPower = control.Movement.Humanoid and control.Movement.Humanoid.JumpPower} end
    end
    if jumpPowerConnection then jumpPowerConnection:Disconnect() end
    jumpPowerConnection = RunService.Heartbeat:Connect(function()
        if jumpPowerEnabled then
            local control = getMovementHandler()
            if control and control.Movement then
                control.Movement.DoubleJumpPower = jumpPowerValue
                if control.Movement.Humanoid then control.Movement.Humanoid.JumpPower = jumpPowerValue end
            end
        end
    end)
    table.insert(allConnections, jumpPowerConnection)
end

local function disableJumpPower()
    if jumpPowerConnection then jumpPowerConnection:Disconnect(); jumpPowerConnection = nil end
    if originalJumpPowerValue ~= nil then
        local control = originalJumpPowerValue.Control
        if control and control.Movement then control.Movement.DoubleJumpPower = originalJumpPowerValue.DoubleJumpPower end
        if originalJumpPowerValue.Humanoid then
            pcall(function() originalJumpPowerValue.Humanoid.JumpPower = originalJumpPowerValue.JumpPower end)
        end
        originalJumpPowerValue = nil
    end
end

local function disableAllToggles()
    flyEnabled = false; speedHackEnabled = false; jumpPowerEnabled = false
    disableFly(); disableSpeedHack(); disableJumpPower()
    for _, toggle in ipairs(allToggles) do
        if toggle and toggle.SetValue then toggle:SetValue(false) end
    end
end

local function cleanupAllConnections()
    for _, connection in ipairs(allConnections) do
        if connection and connection.Connected then connection:Disconnect() end
    end
    allConnections = {}
end

local flyToggle = Tabs.Movement:AddToggle("flyToggle", {
    Title = "Fly",
    Description = "Enable flight mode to freely move in any direction",
    Default = false,
    Callback = function(value)
        flyEnabled = value
        if value then enableFly() else disableFly() end
    end
})
table.insert(allToggles, flyToggle)

Tabs.Movement:AddSlider("flySpeed", {
    Title = "Fly speed", Default = 50, Min = 10, Max = 200, Rounding = 0,
    Callback = function(value) flySpeed = value end
})

local speedHackToggle = Tabs.Movement:AddToggle("speedHackToggle", {
    Title = "Speed Hack",
    Description = "Increase your movement speed",
    Default = false,
    Callback = function(value)
        speedHackEnabled = value
        if value then applySpeedHack() else disableSpeedHack() end
    end
})
table.insert(allToggles, speedHackToggle)

Tabs.Movement:AddSlider("speedValue", {
    Title = "Speed Value", Default = 50, Min = 0, Max = 200, Rounding = 0,
    Callback = function(value) speedHackValue = value end
})

local jumpPowerToggle = Tabs.Movement:AddToggle("jumpPowerToggle", {
    Title = "Jump Power",
    Description = "Increase your jump power",
    Default = false,
    Callback = function(value)
        jumpPowerEnabled = value
        if value then applyJumpPower() else disableJumpPower() end
    end
})
table.insert(allToggles, jumpPowerToggle)

Tabs.Movement:AddSlider("jumpPowerValue", {
    Title = "Jump Power Value", Default = 50, Min = 0, Max = 200, Rounding = 0,
    Callback = function(value) jumpPowerValue = value end
})


TrackRuntimeCleanup(function()
    disableAllToggles()
    cleanupAllConnections()
end)
